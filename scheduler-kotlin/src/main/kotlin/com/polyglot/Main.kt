package com.polyglot

import com.sun.net.httpserver.HttpExchange
import com.sun.net.httpserver.HttpServer
import kotlinx.coroutines.*
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.net.InetSocketAddress
import java.sql.DriverManager
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

@Serializable
data class RiskReport(
    val id: Int,
    val generatedAt: String,
    val avgRiskScore: Double,
    val totalRecords: Long,
    val maxRiskScore: Double,
    val minRiskScore: Double,
)

private const val DB_URL             = "jdbc:postgresql://localhost:5433/postgres"
private const val DB_USER            = "postgres"
private const val DB_PASS            = "postgres"
private const val REPORT_INTERVAL_MS = 60_000L

fun main() {
    initDb()

    val scheduler = CoroutineScope(Dispatchers.IO)
    scheduler.launch { runScheduler() }

    val server = HttpServer.create(InetSocketAddress(9000), 0)
    server.createContext("/api/reports/latest") { ex -> handleLatest(ex) }
    server.createContext("/api/reports/now") { ex ->
        runBlocking { generateReport() }
        respond(ex, """{"status":"ok","message":"리포트 즉시 생성 완료"}""")
    }
    server.createContext("/health") { ex ->
        respond(ex, """{"status":"online","module":"Kotlin-Scheduler-v1"}""")
    }
    server.executor = null
    server.start()
    println("[Kotlin Scheduler] 🚀 Server running on http://0.0.0.0:9000")

    runBlocking { awaitCancellation() }
}

fun initDb() {
    DriverManager.getConnection(DB_URL, DB_USER, DB_PASS).use { conn ->
        conn.createStatement().execute("""
            CREATE TABLE IF NOT EXISTS risk_reports (
                id             SERIAL PRIMARY KEY,
                generated_at   TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                avg_risk_score FLOAT NOT NULL DEFAULT 0,
                total_records  BIGINT NOT NULL DEFAULT 0,
                max_risk_score FLOAT NOT NULL DEFAULT 0,
                min_risk_score FLOAT NOT NULL DEFAULT 0
            )
        """.trimIndent())
        println("[Kotlin Scheduler] ✅ DB 초기화 완료")
    }
}

suspend fun runScheduler() {
    println("[Kotlin Scheduler] ⏰ 스케줄러 시작 (${REPORT_INTERVAL_MS}ms 간격)")
    while (true) {
        try { generateReport() }
        catch (e: Exception) { println("[Kotlin Scheduler] ⚠️ 오류: ${e.message}") }
        delay(REPORT_INTERVAL_MS)
    }
}

suspend fun generateReport() = withContext(Dispatchers.IO) {
    DriverManager.getConnection(DB_URL, DB_USER, DB_PASS).use { conn ->
        val rs = conn.createStatement().executeQuery(
            "SELECT COUNT(*), AVG(risk_score), MAX(risk_score), MIN(risk_score) FROM risk_logs"
        )
        if (!rs.next()) return@withContext
        val total = rs.getLong(1)
        if (total == 0L) return@withContext
        val avg = rs.getDouble(2)
        val max = rs.getDouble(3)
        val min = rs.getDouble(4)

        conn.prepareStatement(
            "INSERT INTO risk_reports (avg_risk_score, total_records, max_risk_score, min_risk_score) VALUES (?,?,?,?)"
        ).apply {
            setDouble(1, avg)
            setLong(2, total)
            setDouble(3, max)
            setDouble(4, min)
        }.executeUpdate()

        val now = LocalDateTime.now().format(DateTimeFormatter.ISO_LOCAL_DATE_TIME)
        println("[Kotlin Scheduler] 📊 리포트 생성 @ $now | avg=$avg total=$total")
    }
}

fun handleLatest(ex: HttpExchange) {
    val reports = DriverManager.getConnection(DB_URL, DB_USER, DB_PASS).use { conn ->
        val rs = conn.createStatement().executeQuery(
            "SELECT id, generated_at, avg_risk_score, total_records, max_risk_score, min_risk_score FROM risk_reports ORDER BY id DESC LIMIT 10"
        )
        buildList {
            while (rs.next()) add(RiskReport(
                id           = rs.getInt(1),
                generatedAt  = rs.getTimestamp(2).toString(),
                avgRiskScore = rs.getDouble(3),
                totalRecords = rs.getLong(4),
                maxRiskScore = rs.getDouble(5),
                minRiskScore = rs.getDouble(6),
            ))
        }
    }
    respond(ex, Json.encodeToString(reports))
}

fun respond(ex: HttpExchange, body: String) {
    val bytes = body.toByteArray()
    ex.responseHeaders.set("Content-Type", "application/json")
    ex.responseHeaders.set("Access-Control-Allow-Origin", "*")
    ex.sendResponseHeaders(200, bytes.size.toLong())
    ex.responseBody.use { it.write(bytes) }
}
