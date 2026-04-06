// Polyglot Infinity — Scala Streaming Aggregator (:9003)
// Scala 3 + JDK HttpServer (외부 의존 없음)
// 역할: 스트림 집계 · 이동평균 · 지수평활
//
// 엔드포인트:
//   GET /api/scala/aggregate  — 시계열 스트림 집계 통계
//   GET /api/scala/smooth     — 지수평활(Holt-Winters 단순 버전)
//   GET /health

import com.sun.net.httpserver.{HttpServer, HttpExchange}
import java.net.InetSocketAddress
import java.io.{OutputStream, PrintStream}
import scala.math.{sqrt, exp, log, sin, cos, Pi, pow}
import scala.util.Try

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

    httpSv.setExecutor(null)
    println(s"Scala Streaming Aggregator listening on :$port")
    httpSv.start()

