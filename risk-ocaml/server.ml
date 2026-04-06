(* Polyglot Infinity — OCaml Risk Rule Engine (:8004)
   순수 stdlib Unix 소켓 기반 HTTP 서버 (외부 패키지 무의존)
   엔드포인트:
     GET /api/ocaml/risk   — 리스크 등급 판정 룰 엔진
     GET /api/ocaml/score  — 신용 스코어링
     GET /health           — 헬스체크
*)

(* ── 리스크 룰 엔진 ── *)

type risk_level = Low | Medium | High | Critical

let string_of_risk = function
  | Low      -> "LOW"
  | Medium   -> "MEDIUM"
  | High     -> "HIGH"
  | Critical -> "CRITICAL"

(* 단순 규칙 기반 리스크 판정 *)
let evaluate_risk ~debt_ratio ~volatility ~leverage ~credit_score =
  let score = ref 0 in
  (* 부채비율 규칙 *)
  if debt_ratio > 0.80 then score := !score + 40
  else if debt_ratio > 0.60 then score := !score + 20
  else if debt_ratio > 0.40 then score := !score + 10;
  (* 변동성 규칙 *)
  if volatility > 0.35 then score := !score + 30
  else if volatility > 0.20 then score := !score + 15
  else if volatility > 0.10 then score := !score + 5;
  (* 레버리지 규칙 *)
  if leverage > 5.0 then score := !score + 20
  else if leverage > 3.0 then score := !score + 10
  else if leverage > 2.0 then score := !score + 5;
  (* 신용점수 규칙 (역방향) *)
  if credit_score < 600 then score := !score + 20
  else if credit_score < 700 then score := !score + 10
  else if credit_score < 750 then score := !score + 5;
  (* 등급 판정 *)
  let level =
    if !score >= 70 then Critical
    else if !score >= 45 then High
    else if !score >= 20 then Medium
    else Low
  in
  (!score, level)

(* 신용 스코어링 — 로지스틱 근사 *)
let logistic x = 1.0 /. (1.0 +. exp (-. x))

let credit_score ~income ~debt ~history_years ~missed_payments =
  let income_f   = float_of_int income in
  let debt_f     = float_of_int debt in
  let history_f  = float_of_int history_years in
  let missed_f   = float_of_int missed_payments in
  let dti        = if income_f > 0.0 then debt_f /. income_f else 1.0 in
  let z = 2.5
        -. 3.5 *. dti
        +. 0.08 *. history_f
        -. 0.6  *. missed_f in
  let prob_good = logistic z in
  let score = int_of_float (300.0 +. 550.0 *. prob_good) in
  let grade =
    if score >= 800 then "A+"
    else if score >= 750 then "A"
    else if score >= 700 then "B+"
    else if score >= 650 then "B"
    else if score >= 600 then "C"
    else "D"
  in
  (score, grade, prob_good)

(* ── JSON helpers ── *)

let json_string s =
  let buf = Buffer.create (String.length s + 2) in
  Buffer.add_char buf '"';
  String.iter (function
    | '"'  -> Buffer.add_string buf "\\\""
    | '\\' -> Buffer.add_string buf "\\\\"
    | '\n' -> Buffer.add_string buf "\\n"
    | c    -> Buffer.add_char buf c
  ) s;
  Buffer.add_char buf '"';
  Buffer.contents buf

let json_kv_s k v = Printf.sprintf "%s:%s" (json_string k) (json_string v)
let json_kv_f k v = Printf.sprintf "%s:%.4f" (json_string k) v
let json_kv_i k v = Printf.sprintf "%s:%d"   (json_string k) v

(* ── HTTP helpers ── *)

let parse_query qs =
  (* "a=1&b=2" → [("a","1");("b","2")] *)
  let pairs = String.split_on_char '&' qs in
  List.filter_map (fun pair ->
    match String.split_on_char '=' pair with
    | [k; v] -> Some (k, v)
    | _       -> None
  ) pairs

let get_param params key default =
  match List.assoc_opt key params with
  | Some v -> v
  | None   -> default

let get_float params key default =
  try float_of_string (get_param params key (string_of_float default))
  with _ -> default

let get_int params key default =
  try int_of_string (get_param params key (string_of_int default))
  with _ -> default

let http_200 body =
  Printf.sprintf
    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: %d\r\nConnection: close\r\n\r\n%s"
    (String.length body) body

let http_404 =
  "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\nNot Found"

(* ── 요청 처리 ── *)

let handle_request req =
  (* 첫 줄: "GET /path?query HTTP/1.1" *)
  let first_line =
    match String.split_on_char '\n' req with
    | line :: _ -> String.trim line
    | []        -> ""
  in
  let (path, query) =
    match String.split_on_char ' ' first_line with
    | _ :: url :: _ ->
      (match String.split_on_char '?' url with
       | [p]    -> (p, "")
       | p :: q -> (p, String.concat "?" q)
       | []     -> ("/", ""))
    | _ -> ("/", "")
  in
  let params = parse_query query in
  match path with
  | "/health" ->
    let body = Printf.sprintf "{%s,%s}"
      (json_kv_s "status" "ok")
      (json_kv_s "service" "ocaml-risk-engine") in
    http_200 body

  | "/api/ocaml/risk" ->
    let debt_ratio    = get_float params "debt_ratio"    0.55 in
    let volatility    = get_float params "volatility"    0.22 in
    let leverage      = get_float params "leverage"      2.5  in
    let credit_score_ = get_int   params "credit_score"  680  in
    let (score, level) = evaluate_risk
      ~debt_ratio ~volatility ~leverage ~credit_score:credit_score_ in
    let vars = Printf.sprintf "{%s,%s,%s,%s,%s,%s,%s}"
      (json_kv_s "level"        (string_of_risk level))
      (json_kv_i "risk_score"   score)
      (json_kv_f "debt_ratio"   debt_ratio)
      (json_kv_f "volatility"   volatility)
      (json_kv_f "leverage"     leverage)
      (json_kv_i "credit_score" credit_score_)
      (json_kv_s "engine"       "OCaml 4.13 rule-based") in
    http_200 vars

  | "/api/ocaml/score" ->
    let income          = get_int   params "income"          5000000 in
    let debt            = get_int   params "debt"            1500000 in
    let history_years   = get_int   params "history_years"   5       in
    let missed_payments = get_int   params "missed_payments" 0       in
    let (sc, grade, prob) = credit_score
      ~income ~debt ~history_years ~missed_payments in
    let body = Printf.sprintf "{%s,%s,%s,%s,%s,%s,%s}"
      (json_kv_i "score"          sc)
      (json_kv_s "grade"          grade)
      (json_kv_f "prob_good"      prob)
      (json_kv_i "income"         income)
      (json_kv_i "debt"           debt)
      (json_kv_i "history_years"  history_years)
      (json_kv_s "engine"         "OCaml 4.13 logistic") in
    http_200 body

  | _ -> http_404

(* ── TCP 서버 루프 ── *)

let () =
  let port = 8004 in
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_any, port));
  Unix.listen sock 32;
  Printf.printf "OCaml Risk Engine listening on :%d\n%!" port;
  while true do
    let (client, _addr) = Unix.accept sock in
    (* 간단한 단일-스레드 처리 (연구용) *)
    (try
      let ic = Unix.in_channel_of_descr client in
      let buf = Buffer.create 1024 in
      (try
        let line = ref (input_line ic) in
        while !line <> "\r" && !line <> "" do
          Buffer.add_string buf !line;
          Buffer.add_char buf '\n';
          line := input_line ic
        done
      with End_of_file -> ());
      let req = Buffer.contents buf in
      let resp = handle_request req in
      let oc = Unix.out_channel_of_descr client in
      output_string oc resp;
      flush oc
    with _ -> ());
    Unix.close client
  done
