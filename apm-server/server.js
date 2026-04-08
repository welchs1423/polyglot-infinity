// apm-server/server.js
// Central APM ingestion server for the polyglot-infinity platform.
//
// Endpoints:
//   POST /ingest  — accepts a JSON array of TransactionMetric objects.
//                   Stores them in a fixed-size circular buffer.
//                   Returns 202 Accepted with { accepted, total }.
//   GET  /metrics — returns aggregated stats (p50/p95/p99/avg/max per service)
//                   and the most recent events.  Optional query param: limit=N
//   GET  /health  — liveness probe, returns { status, buffered }.
//
// Design:
//   - Single Node.js event loop; no external dependencies.
//   - Circular buffer capped at MAX_BUFFER entries; oldest entries are evicted
//     when the buffer is full so memory use is bounded.
//   - All aggregation (percentile, per-service grouping) is computed at read
//     time on the in-memory array so ingest is O(1).
//   - CORS is enabled for all origins to allow the Svelte portal to query
//     metrics directly.
//
// Environment variables:
//   PORT — TCP port to bind (default: 9009)

'use strict';

const http = require('node:http');

const PORT = parseInt(process.env.PORT || '9009', 10);
const MAX_BUFFER = 100_000;

const CORS_HEADERS = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, X-Correlation-Id',
};

// ── Circular buffer ───────────────────────────────────────────────────────────
// Implemented as a plain Array with splice-on-overflow.
// At 1200 TPS sustained this fills at ~600 events/500ms flush; Max 100 000 gives
// ~83 seconds of full-rate history before the oldest events are evicted.
const buffer = [];

function ingest(events) {
    const overflow = buffer.length + events.length - MAX_BUFFER;
    if (overflow > 0) {
        buffer.splice(0, overflow);
    }
    for (let i = 0; i < events.length; i++) {
        buffer.push(events[i]);
    }
}

// ── Statistics ────────────────────────────────────────────────────────────────

function percentile(sorted, p) {
    if (sorted.length === 0) return 0;
    const idx = Math.ceil((p / 100) * sorted.length) - 1;
    return sorted[Math.max(0, idx)];
}

function computeStats(values) {
    if (values.length === 0) {
        return { count: 0, p50: 0, p95: 0, p99: 0, avg: 0, max: 0 };
    }
    const sorted = values.slice().sort((a, b) => a - b);
    let sum = 0;
    for (let i = 0; i < sorted.length; i++) sum += sorted[i];
    return {
        count: sorted.length,
        p50: percentile(sorted, 50),
        p95: percentile(sorted, 95),
        p99: percentile(sorted, 99),
        avg: Math.round(sum / sorted.length),
        max: sorted[sorted.length - 1],
    };
}

// Builds the metrics response object.
//   limit — number of most recent raw events to include in the response.
function buildMetrics(limit) {
    const clampedLimit = Math.min(Math.max(limit, 1), 1000);

    // Per-service aggregation: collect responseMs values keyed by service name.
    const byService = Object.create(null);
    const allResp = [];

    for (let i = 0; i < buffer.length; i++) {
        const e = buffer[i];
        const svc = (e && typeof e.service === 'string') ? e.service : 'unknown';
        if (typeof e.responseMs === 'number') {
            if (!byService[svc]) byService[svc] = [];
            byService[svc].push(e.responseMs);
            allResp.push(e.responseMs);
        }
    }

    const serviceStats = Object.create(null);
    const svcNames = Object.keys(byService);
    for (let i = 0; i < svcNames.length; i++) {
        serviceStats[svcNames[i]] = computeStats(byService[svcNames[i]]);
    }

    return {
        total_ingested: buffer.length,
        overall_stats: computeStats(allResp),
        service_stats: serviceStats,
        recent_events: buffer.slice(-clampedLimit),
    };
}

// ── HTTP request body reader ──────────────────────────────────────────────────

function readBody(req) {
    return new Promise(function (resolve, reject) {
        const chunks = [];
        req.on('data', function (chunk) { chunks.push(chunk); });
        req.on('end', function () { resolve(Buffer.concat(chunks).toString('utf8')); });
        req.on('error', reject);
    });
}

// ── Request router ────────────────────────────────────────────────────────────

const server = http.createServer(function (req, res) {
    // Delegate to the async handler; unhandled promise rejections produce a 500.
    handleRequest(req, res).catch(function (err) {
        if (!res.headersSent) {
            res.writeHead(500, Object.assign({ 'Content-Type': 'application/json' }, CORS_HEADERS));
            res.end(JSON.stringify({ error: err.message }));
        }
    });
});

async function handleRequest(req, res) {
    const headers = Object.assign({ 'Content-Type': 'application/json' }, CORS_HEADERS);

    // CORS preflight
    if (req.method === 'OPTIONS') {
        res.writeHead(204, CORS_HEADERS);
        res.end();
        return;
    }

    // GET /health
    if (req.method === 'GET' && req.url === '/health') {
        res.writeHead(200, headers);
        res.end(JSON.stringify({ status: 'ok', buffered: buffer.length }));
        return;
    }

    // POST /ingest
    if (req.method === 'POST' && req.url === '/ingest') {
        const body = await readBody(req);
        let events;
        try {
            events = JSON.parse(body);
        } catch (_) {
            res.writeHead(400, headers);
            res.end(JSON.stringify({ error: 'request body must be valid JSON' }));
            return;
        }
        if (!Array.isArray(events)) {
            res.writeHead(400, headers);
            res.end(JSON.stringify({ error: 'request body must be a JSON array' }));
            return;
        }
        ingest(events);
        res.writeHead(202, headers);
        res.end(JSON.stringify({ accepted: events.length, total: buffer.length }));
        return;
    }

    // GET /metrics[?limit=N]
    if (req.method === 'GET' && req.url.startsWith('/metrics')) {
        const queryStart = req.url.indexOf('?');
        let limit = 100;
        if (queryStart !== -1) {
            const qs = req.url.slice(queryStart + 1);
            const match = qs.match(/(?:^|&)limit=(\d+)/);
            if (match) limit = parseInt(match[1], 10);
        }
        const payload = buildMetrics(limit);
        res.writeHead(200, headers);
        res.end(JSON.stringify(payload));
        return;
    }

    res.writeHead(404, headers);
    res.end(JSON.stringify({ error: 'not found', path: req.url }));
}

// ── Start ─────────────────────────────────────────────────────────────────────

server.listen(PORT, '::', function () {
    process.stdout.write('[apm-server] listening on :' + PORT + '\n');
    process.stdout.write('[apm-server] POST /ingest  — batch metric ingest\n');
    process.stdout.write('[apm-server] GET  /metrics — aggregated stats\n');
    process.stdout.write('[apm-server] GET  /health  — liveness probe\n');
});
