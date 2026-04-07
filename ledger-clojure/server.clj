;; ledger-clojure/server.clj
;; Polyglot Infinity — Clojure 1.10 STM Account Ledger (:8009)
;; 핵심 강점: ref + dosync — 소프트웨어 트랜잭션 메모리(STM)
;;
;; dosync 블록 내의 모든 alter는 원자적으로 커밋됩니다.
;; 다른 스레드가 같은 ref를 동시에 수정하면 → 자동 재시도(retry).
;; 결과: 전체 잔액 합계가 항상 36,500.0으로 보존됩니다. (잠금 없음)
;;
;; GET /health
;; GET /api/clojure/status    — 현재 계좌 잔액 조회
;; GET /api/clojure/transfer?from=ACC-001&to=ACC-002&amount=500
;; GET /api/clojure/stress?n=200  — N개 동시 이체, 합계 불변성 검증

(ns ledger.server
  (:import [com.sun.net.httpserver HttpServer HttpExchange]
           [java.net InetSocketAddress]
           [java.util.concurrent Executors]
           [java.io OutputStream]))

;; ── STM 상태 정의 ──────────────────────────────────────────────────
;; ref: STM으로 관리되는 변경 가능 참조.
;; dosync 외부에서 alter/ref-set 호출 시 IllegalStateException 발생.

(def ^:private INITIAL_BALANCES
  {"ACC-001" {:name "Alpha Fund"  :balance 10000.0}
   "ACC-002" {:name "Beta Corp"   :balance  8500.0}
   "ACC-003" {:name "Gamma Inc"   :balance 12000.0}
   "ACC-004" {:name "Delta Ltd"   :balance  6000.0}})

;; 각 계좌는 독립적인 ref — dosync 안에서만 수정 가능
(def accounts
  (into {} (map (fn [[k v]] [k (ref v)]) INITIAL_BALANCES)))

(def transfer-log   (ref []))
(def total-transfers (ref 0))

;; ── STM 이체 ──────────────────────────────────────────────────────
;; dosync: 트랜잭션 경계. 모든 alter는 원자적으로 커밋됩니다.
;; 충돌(conflict) 발생 시 dosync 블록 전체가 자동 재시도됩니다.
;; 잠금이 필요 없고, 데드락이 발생하지 않습니다.
(defn transfer! [from-id to-id amount]
  (dosync
   (let [from-ref (accounts from-id)
         to-ref   (accounts to-id)]
     (when (and from-ref to-ref
                (>= (:balance @from-ref) (double amount)))
       (alter from-ref update :balance - (double amount))
       (alter to-ref   update :balance + (double amount))
       (alter total-transfers inc)
       (alter transfer-log conj
              {:from from-id :to to-id
               :amount (double amount)
               :ts (System/currentTimeMillis)})
       true))))

(defn total-balance []
  (apply + (map #(:balance (deref (val %))) accounts)))

(defn reset-accounts! []
  (dosync
   (doseq [[k v] accounts]
     (ref-set v (INITIAL_BALANCES k)))
   (ref-set transfer-log [])
   (ref-set total-transfers 0)))

;; ── 스트레스 테스트 ───────────────────────────────────────────────
;; N개 future가 동시에 이체를 수행합니다.
;; STM이 충돌하는 트랜잭션을 자동 재시도하여 일관성을 유지합니다.
;; 완료 후: total-balance = 36,500.0 (±0.01 오차 이내)
(defn run-stress! [n]
  (reset-accounts!)
  (let [ids     (vec (keys accounts))
        n-ids   (count ids)
        ;; 각 future는 독립 스레드에서 실행
        futures (doall
                 (for [i (range n)]
                   (future
                     (let [from (ids (mod i n-ids))
                           to   (ids (mod (+ i 1) n-ids))
                           amt  (+ 10.0 (double (mod i 90)))]
                       (transfer! from to amt)))))]
    ;; 모든 future 완료 대기
    (doseq [f futures] @f))

  (let [final   (total-balance)
        expected 36500.0
        diff    (Math/abs (- final expected))]
    {:transfers-attempted   n
     :transfers-committed   @total-transfers
     :final-total-balance   final
     :expected-total        expected
     :invariant-preserved   (< diff 0.01)
     :stm-note              "dosync auto-retried conflicting transactions — no money created or destroyed"}))

;; ── JSON 직렬화 (외부 의존 없음) ──────────────────────────────────
(defn to-json [v]
  (cond
    (map? v)
    (str "{"
         (->> v
              (map (fn [[k val]]
                     (str (to-json (if (keyword? k) (name k) (str k)))
                          ":"
                          (to-json val))))
              (clojure.string/join ","))
         "}")

    (or (vector? v) (seq? v) (list? v))
    (str "[" (clojure.string/join "," (map to-json v)) "]")

    (string? v)
    (str "\"" (-> v
                  (clojure.string/replace "\\" "\\\\")
                  (clojure.string/replace "\"" "\\\""))
         "\"")

    (nil? v)    "null"
    (true? v)   "true"
    (false? v)  "false"
    (float? v)  (format "%.4f" (double v))
    :else       (str v)))

;; ── HTTP 유틸리티 ─────────────────────────────────────────────────
(defn parse-qs [qs]
  (into {}
        (for [pair (clojure.string/split (or qs "") #"&")
              :let  [[k v] (clojure.string/split pair #"=" 2)]
              :when (and (seq k) v)]
          [k v])))

(defn send-json! [^HttpExchange ex ^String body]
  (let [bytes  (.getBytes body "UTF-8")
        hdrs   (.getResponseHeaders ex)]
    (.set hdrs "Content-Type" "application/json")
    (.set hdrs "Access-Control-Allow-Origin" "*")
    (.sendResponseHeaders ex 200 (alength bytes))
    (let [^OutputStream out (.getResponseBody ex)]
      (.write out bytes)
      (.close out))))

;; ── 라우터 ────────────────────────────────────────────────────────
(defn route [path params]
  (cond
    (= path "/health")
    (to-json {:status "ok" :lang "clojure" :port 8009})

    (= path "/api/clojure/status")
    (to-json {:lang        "clojure"
              :version     (clojure-version)
              :port        8009
              :paradigm    "stm"
              :accounts
              (into {} (map (fn [[k v]]
                              [k {:name    (:name @v)
                                  :balance (:balance @v)}])
                            accounts))
              :total-balance      (total-balance)
              :total-transfers    @total-transfers})

    (= path "/api/clojure/transfer")
    (let [from   (params "from"   "ACC-001")
          to     (params "to"     "ACC-002")
          amount (Double/parseDouble (params "amount" "100.0"))
          ok?    (transfer! from to amount)]
      (to-json {:status            (if ok? "ok" "insufficient-funds")
                :from              from
                :to                to
                :amount            amount
                :total-balance     (total-balance)
                :total-transfers   @total-transfers}))

    (= path "/api/clojure/stress")
    (let [n   (Integer/parseInt (params "n" "200"))
          n   (max 10 (min n 1000))
          res (run-stress! n)]
      (to-json (merge res {:lang "clojure" :port 8009})))

    :else
    (to-json {:error "not found"})))

;; ── HTTP 핸들러 ───────────────────────────────────────────────────
(defn make-handler []
  (reify com.sun.net.httpserver.HttpHandler
    (handle [_ ex]
      (try
        (let [uri    (.getRequestURI ex)
              path   (.getPath uri)
              qs     (.getQuery uri)
              params (fn [k default] (or (get (parse-qs qs) k) default))
              body   (route path params)]
          (send-json! ex body))
        (catch Exception e
          (try
            (send-json! ex (to-json {:error (.getMessage e)}))
            (catch Exception _ nil)))))))

;; ── 서버 시작 ────────────────────────────────────────────────────
(defn start-server! []
  (let [port   8009
        server (HttpServer/create (InetSocketAddress. port) 128)]
    (.createContext server "/" (make-handler))
    (.setExecutor server (Executors/newCachedThreadPool))
    (.start server)
    (println (str "Clojure " (clojure-version) " STM Ledger Server on :" port))
    server))

(defn -main [& _args]
  (start-server!)
  ;; 메인 스레드를 블로킹하여 서버 유지
  @(promise))

(-main)
