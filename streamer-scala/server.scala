// Polyglot Infinity — Scala Streaming Aggregator (:9003)
// Scala 3 + JDK HttpServer (외부 의존 없음)
// Scala 3의 핵심 강점:
//   - enum (ADT): 모든 variant가 case에서 강제 처리 (컴파일 타임 검증)
//   - LazyList: 무한 스트림을 타입 안전하게 선언
//   - extension: 도메인 타입에 연산 직접 추가
//   - given/using: 타입 클래스로 다형성 표현
//
// 엔드포인트:
//   GET /api/scala/aggregate  — 시계열 스트림 집계
//   GET /api/scala/smooth     — Holt 이중지수평활
//   GET /api/scala/stream     — Scala 3 ADT 타입 이벤트 스트림
//   GET /health

import com.sun.net.httpserver.{HttpServer, HttpExchange}
import java.net.InetSocketAddress
import java.io.{OutputStream, PrintStream}
import scala.math.{sqrt, exp, log, sin, cos, Pi, pow}
import scala.util.Try

// ── Scala 3 enum — ADT (대수적 데이터 타입) ───────────────────
// 모든 variant가 match에서 강제 처리됩니다.
// 새 variant 추가 후 match 미수정 시 → 컴파일 경고/에러 (exhaustive check)
enum RiskEvent:
  case Tick(price: Double, vol: Double, ts: Long)
  case Alert(level: AlertLevel, message: String)
  case Heartbeat(seqNo: Long)

enum AlertLevel:
  case Info, Warning, Critical

// ── 타입 클래스: Aggregatable ──────────────────────────────────
// given/using 으로 타입별 집계 로직을 분리합니다
trait Aggregatable[A]:
  def toValue(a: A): Option[Double]
  def severity(a: A): Int

given Aggregatable[RiskEvent] with
  def toValue(e: RiskEvent): Option[Double] = e match
    case RiskEvent.Tick(price, _, _)  => Some(price)
    case RiskEvent.Alert(_, _)        => None
    case RiskEvent.Heartbeat(_)       => None
    // 새 RiskEvent variant 추가 시 → 여기 케이스 추가 필수 (컴파일 강제)

  def severity(e: RiskEvent): Int = e match
    case RiskEvent.Tick(_, vol, _)          => if vol > 0.3 then 2 else 0
    case RiskEvent.Alert(AlertLevel.Critical, _) => 3
    case RiskEvent.Alert(AlertLevel.Warning, _)  => 2
    case RiskEvent.Alert(AlertLevel.Info, _)     => 1
    case RiskEvent.Heartbeat(_)                  => 0

// ── extension: LazyList[RiskEvent] 에 도메인 연산 추가 ──────────
extension [A](stream: LazyList[A])
  def collectValues(using agg: Aggregatable[A]): LazyList[Double] =
    stream.flatMap(e => agg.toValue(e))

  def maxSeverity(using agg: Aggregatable[A]): Int =
    stream.map(e => agg.severity(e)).maxOption.getOrElse(0)

// ── 타입 안전 이벤트 스트림 생성 ────────────────────────────────
def riskEventStream(seed: Int, mu: Double, sigma: Double): LazyList[RiskEvent] =
  // LazyList.unfold: 무한 스트림을 상태 전이 함수로 선언 (메모리 즉시 생성 없음)
  LazyList.unfold((seed.toLong, 100.0, 0L)): (s, price, seq) =>
    val s2   = (1_664_525L * s + 1_013_904_223L) & 0x7FFFFFFFL
    val s3   = (1_664_525L * s2 + 1_013_904_223L) & 0x7FFFFFFFL
    val u    = s2.toDouble / 0x7FFFFFFF.toDouble
    val u2   = s3.toDouble / 0x7FFFFFFF.toDouble
    val z    = sqrt(-2.0 * log(u + 1e-10)) * cos(2.0 * Pi * u2)
    val newP = price * exp(mu / 252.0 + sigma / sqrt(252.0) * z)
    val vol  = sigma * (0.8 + u * 0.4)
    // 낮은 확률로 Alert, 매우 낮은 확률로 Heartbeat, 나머지는 Tick
    val event: RiskEvent =
      if seq % 50 == 0      then RiskEvent.Heartbeat(seq)
      else if vol > 0.28    then RiskEvent.Alert(AlertLevel.Warning, s"vol=${vol.formatted("%.3f")}")
      else                       RiskEvent.Tick(newP, vol, seq)
    Some(event, (s3, newP, seq + 1))

def streamJson(events: Seq[RiskEvent], n: Int)(using agg: Aggregatable[RiskEvent]): String =
  val ticks     = events.collect { case t: RiskEvent.Tick => t }
  val alerts    = events.collect { case a: RiskEvent.Alert => a }
  val heartbeat = events.collect { case h: RiskEvent.Heartbeat => h }
  val prices    = ticks.map(_.price)
  val m  = if prices.isEmpty then 0.0 else prices.sum / prices.size
  val sd = if prices.size < 2 then 0.0 else sqrt(prices.map(p => (p-m)*(p-m)).sum / prices.size)
  val alertCounts = alerts.groupBy(_.level).map((k, v) => s""""${k}":${v.size}""").mkString(",")
  val maxSev = events.toLazyList.maxSeverity
  f"""{
    "n_total":${events.size},
    "n_ticks":${ticks.size},
    "n_alerts":${alerts.size},
    "n_heartbeats":${heartbeat.size},
    "alert_breakdown":{$alertCounts},
    "tick_price_mean":$m%.4f,
    "tick_price_std":$sd%.4f,
    "max_severity_score":$maxSev,
    "adt_types":["Tick","Alert(Info|Warning|Critical)","Heartbeat"],
    "lazy_stream":true,
    "engine":"Scala 3 (ADT enum + LazyList.unfold + given/using)"
  }"""

// ── 수학 헬퍼 (함수형 스타일) ──────────────────────────────

object Stats:
  def mean(xs: Seq[Double]): Double =
    if xs.isEmpty then 0.0 else xs.sum / xs.size

  def variance(xs: Seq[Double]): Double =
    val m = mean(xs)
    if xs.isEmpty then 0.0
    else xs.map(x => (x - m) * (x - m)).sum / xs.size

  def stdDev(xs: Seq[Double]): Double = sqrt(variance(xs))

  def median(xs: Seq[Double]): Double =
    val sorted = xs.sorted
    val n = sorted.size
    if n == 0 then 0.0
    else if n % 2 == 1 then sorted(n / 2)
    else (sorted(n / 2 - 1) + sorted(n / 2)) / 2.0

  def percentile(xs: Seq[Double], p: Double): Double =
    val sorted = xs.sorted
    val idx = ((p / 100.0) * (sorted.size - 1)).toInt.min(sorted.size - 1).max(0)
    sorted(idx)

  // 이동평균 (SMA)
  def sma(xs: Seq[Double], window: Int): Seq[Double] =
    xs.sliding(window).map(w => w.sum / w.size).toSeq

  // 지수 가중 이동평균 (EWM)
  def ewma(xs: Seq[Double], alpha: Double): Seq[Double] =
    xs.scanLeft(xs.headOption.getOrElse(0.0)):
      (prev, x) => alpha * x + (1 - alpha) * prev
    .drop(1)

  // 단순 지수평활 + 트렌드 (Holt Double Exponential)
  def holtSmooth(xs: Seq[Double], alpha: Double, beta: Double): (Seq[Double], Double) =
    if xs.size < 2 then return (xs, 0.0)
    var level = xs(0)
    var trend = xs(1) - xs(0)
    val smoothed = scala.collection.mutable.ArrayBuffer[Double](level + trend)
    for x <- xs.drop(2) do
      val prevLevel = level
      level = alpha * x + (1 - alpha) * (level + trend)
      trend = beta * (level - prevLevel) + (1 - beta) * trend
      smoothed += level + trend
    (smoothed.toSeq, level + trend)  // 마지막 = 1기 예측값

// ── 의사난수 시계열 생성 ───────────────────────────────────

def pseudoSeries(seed: Int, n: Int, mu: Double, sigma: Double): Seq[Double] =
  // drop(1)으로 seed 원값(>1.0) 제거, iterate는 항상 (0,1) 범위 소수부만 생성
  LazyList.iterate(seed.toDouble): x =>
    val s = sin(x * 12.9898 + 78.233) * 43758.5453
    s - math.floor(s)
  .drop(1)           // 첫 번째 원소(seed 그 자체)는 [0,1] 범위 아님
  .take(n * 2 + 2)
  .sliding(2, 2)
  .map: pair =>
    val x = pair(0); val y = pair(1)
    val z = sqrt(-2.0 * log(x + 1e-10)) * cos(2.0 * Pi * y)
    mu / 252.0 + sigma / sqrt(252.0) * z
  .take(n).toSeq

// ── JSON 빌더 ──────────────────────────────────────────────

def aggJson(xs: Seq[Double], smaVals: Seq[Double]): String =
  val m    = Stats.mean(xs)
  val s    = Stats.stdDev(xs)
  val med  = Stats.median(xs)
  val p5   = Stats.percentile(xs, 5)
  val p95  = Stats.percentile(xs, 95)
  val annR = m * 252
  val annV = s * sqrt(252)
  val lastSma = if smaVals.isEmpty then 0.0 else smaVals.last
  f"""{
    "mean_daily":$m%.6f,
    "std_daily":$s%.6f,
    "median_daily":$med%.6f,
    "annualized_return":$annR%.4f,
    "annualized_volatility":$annV%.4f,
    "p5":$p5%.6f,
    "p95":$p95%.6f,
    "sma_20_last":$lastSma%.6f,
    "n":${xs.size},
    "engine":"Scala 3.8.3"
  }"""

def smoothJson(smoothed: Seq[Double], forecast: Double, alpha: Double, beta: Double): String =
  val last3 = smoothed.takeRight(3)
  val arr   = last3.map(v => f"$v%.6f").mkString("[", ",", "]")
  f"""{
    "alpha":$alpha%.3f,
    "beta":$beta%.3f,
    "forecast_next":$forecast%.6f,
    "last_3_smoothed":$arr,
    "n_smoothed":${smoothed.size},
    "engine":"Scala 3.8.3"
  }"""

// ── 쿼리 파싱 ──────────────────────────────────────────────

def parseQuery(query: String): Map[String, String] =
  if query == null || query.isEmpty then Map.empty
  else
    query.split("&").flatMap: pair =>
      pair.split("=", 2) match
        case Array(k, v) => Some(k -> java.net.URLDecoder.decode(v, "UTF-8"))
        case _           => None
    .toMap

def getDouble(params: Map[String, String], key: String, default: Double): Double =
  params.get(key).flatMap(v => Try(v.toDouble).toOption).getOrElse(default)

def getInt(params: Map[String, String], key: String, default: Int): Int =
  params.get(key).flatMap(v => Try(v.toInt).toOption).getOrElse(default)

// ── HTTP CORS 헤더 응답 ────────────────────────────────────

def respond(ex: HttpExchange, status: Int, body: String): Unit =
  val bytes = body.getBytes("UTF-8")
  ex.getResponseHeaders.add("Content-Type", "application/json")
  ex.getResponseHeaders.add("Access-Control-Allow-Origin", "*")
  ex.sendResponseHeaders(status, bytes.length)
  val os: OutputStream = ex.getResponseBody
  os.write(bytes)
  os.close()

// ── 메인 ──────────────────────────────────────────────────

object Main:
  def main(args: Array[String]): Unit =
    val port   = 9003
    val httpSv = HttpServer.create(new InetSocketAddress(port), 0)

    httpSv.createContext("/health", ex =>
      respond(ex, 200, """{"status":"ok","service":"scala-streamer"}""")
    )

    httpSv.createContext("/api/scala/aggregate", ex =>
      val params = parseQuery(ex.getRequestURI.getQuery)
      val mu     = getDouble(params, "mu",    0.08)
      val sigma  = getDouble(params, "sigma", 0.15)
      val n      = getInt(params,    "n",     252)
      val seed   = getInt(params,    "seed",  3)
      val xs     = pseudoSeries(seed, n, mu, sigma)
      val smaV   = Stats.sma(xs, 20)
      respond(ex, 200, aggJson(xs, smaV))
    )

    httpSv.createContext("/api/scala/smooth", ex =>
      val params = parseQuery(ex.getRequestURI.getQuery)
      val mu     = getDouble(params, "mu",    0.08)
      val sigma  = getDouble(params, "sigma", 0.15)
      val n      = getInt(params,    "n",     252)
      val seed   = getInt(params,    "seed",  3)
      val alpha  = getDouble(params, "alpha", 0.3)
      val beta   = getDouble(params, "beta",  0.1)
      val xs     = pseudoSeries(seed, n, mu, sigma)
      val (smoothed, forecast) = Stats.holtSmooth(xs, alpha, beta)
      respond(ex, 200, smoothJson(smoothed, forecast, alpha, beta))
    )

    httpSv.createContext("/api/scala/stream", ex =>
      val params = parseQuery(ex.getRequestURI.getQuery)
      val mu     = getDouble(params, "mu",    0.08)
      val sigma  = getDouble(params, "sigma", 0.15)
      val n      = getInt(params,    "n",     200).min(2000).max(10)
      val seed   = getInt(params,    "seed",  7)
      // LazyList.unfold 로 생성된 무한 스트림에서 n개만 구체화
      val events = riskEventStream(seed, mu, sigma).take(n).toSeq
      respond(ex, 200, streamJson(events, n))
    )

    httpSv.setExecutor(null)
    println(s"Scala Streaming Aggregator listening on :$port")
    httpSv.start()

