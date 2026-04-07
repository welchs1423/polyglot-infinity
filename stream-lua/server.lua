-- stream-lua/server.lua
-- Polyglot Infinity — Lua 5.4 Coroutine Stream Aggregator (:8007)
-- 핵심 강점: coroutine.create/yield/resume — 단일 스레드에서 여러 가격 스트림을 협력적으로 멀티플렉싱
-- OS 스레드 없음, 락 없음, 콜백 없음. 각 피드는 독립적인 coroutine.
--
-- GET /health
-- GET /api/lua/status
-- GET /api/lua/stream?feeds=4&steps=200

local socket = require("socket")

-- ── LCG 의사난수 (외부 의존 없음) ──────────────────────────────────
local MOD   = 2^32
local function lcg_next(s) return (1664525 * s + 1013904223) % MOD end
local function lcg_uniform(s)
    local ns = lcg_next(s)
    return ns / (MOD - 1), ns
end
local function box_muller(s)
    local u1, s1 = lcg_uniform(s)
    local u2, s2 = lcg_uniform(s1)
    u1 = math.max(u1, 1e-15)
    return math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2), s2
end

-- ── 가격 피드 코루틴 팩토리 ─────────────────────────────────────────
-- 핵심: 각 피드는 coroutine.create()로 생성된 독립 코루틴입니다.
-- coroutine.yield()로 실행을 "일시 중단"하여 제어를 스케줄러에게 돌려줍니다.
-- 스케줄러가 coroutine.resume()을 호출하면 yield한 지점부터 재개됩니다.
-- 이 방식으로 단일 스레드에서 N개의 가격 생성기를 교대로 실행합니다.
local function make_feed(symbol, seed, base_price, annual_vol, annual_mu)
    return coroutine.create(function()
        local s     = seed
        local price = base_price
        local dt    = 1.0 / 252.0  -- 1 거래일 단위
        while true do
            local z
            z, s = box_muller(s)
            local drift     = (annual_mu - 0.5 * annual_vol^2) * dt
            local diffusion = annual_vol * math.sqrt(dt) * z
            price = price * math.exp(drift + diffusion)
            -- coroutine.yield: 이 시점에서 실행 중단, 값을 호출자에게 전달
            -- 다음 resume 시 이 줄 바로 다음부터 재개됨
            coroutine.yield(symbol, price, annual_vol)
        end
    end)
end

-- ── 코루틴 스케줄러 ─────────────────────────────────────────────────
-- 단일 스레드에서 N개 피드를 라운드로빈으로 스케줄링합니다.
-- OS 스레드나 인터럽트 없이 순수하게 yield/resume으로만 전환됩니다.
local function run_scheduler(n_feeds, n_steps)
    local configs = {
        {"AAPL", 42,  182.0, 0.25, 0.12},
        {"NVDA", 137, 875.0, 0.45, 0.30},
        {"MSFT", 99,  420.0, 0.22, 0.14},
        {"TSLA", 256, 215.0, 0.55, 0.18},
        {"GOOG", 17,  168.0, 0.28, 0.13},
        {"META", 333, 510.0, 0.32, 0.20},
    }
    n_feeds = math.min(n_feeds, #configs)

    -- 코루틴 생성 — 각 피드는 독립적인 실행 스택을 가집니다
    local feeds = {}
    for i = 1, n_feeds do
        local c = configs[i]
        feeds[i] = {
            co      = make_feed(c[1], c[2], c[3], c[4], c[5]),
            symbol  = c[1],
            prices  = {},
        }
    end

    -- 스케줄러 루프: 매 step마다 모든 피드를 한 번씩 resume
    -- 총 resume 횟수 = n_steps * n_feeds (단일 스레드)
    local total_resumes = 0
    for _ = 1, n_steps do
        for _, feed in ipairs(feeds) do
            -- coroutine.resume: 코루틴을 재개하여 다음 yield까지 실행
            local ok, sym, price = coroutine.resume(feed.co)
            if ok then
                feed.prices[#feed.prices + 1] = price
                feed.last_price = price
                total_resumes   = total_resumes + 1
            end
        end
    end

    -- 각 피드의 통계 집계
    local results = {}
    for _, feed in ipairs(feeds) do
        local prices = feed.prices
        local n      = #prices
        local first  = prices[1] or 0
        local last   = prices[n] or 0
        local ret    = n > 0 and (last - first) / math.max(first, 1e-15) or 0

        -- 실현 변동성 (로그 수익률 std)
        local log_rets = {}
        for i = 2, n do
            log_rets[#log_rets + 1] = math.log(math.max(prices[i] / prices[i-1], 1e-15))
        end
        local mean = 0
        for _, r in ipairs(log_rets) do mean = mean + r end
        mean = mean / math.max(#log_rets, 1)
        local var = 0
        for _, r in ipairs(log_rets) do var = var + (r - mean)^2 end
        var = var / math.max(#log_rets - 1, 1)
        local vol_ann = math.sqrt(var * 252) * 100

        -- coroutine.status: "suspended" = 일시중단 중, "dead" = 종료됨
        local co_status = coroutine.status(feed.co)

        results[#results + 1] = string.format(
            '{"symbol":"%s","ticks":%d,"start_price":%.2f,"end_price":%.2f,"return_pct":%.2f,"ann_vol_pct":%.2f,"coroutine_status":"%s"}',
            feed.symbol, n, first, last, ret * 100, vol_ann, co_status
        )
    end

    return results, total_resumes
end

-- ── HTTP 유틸리티 ──────────────────────────────────────────────────
local function parse_request(line)
    local path, qs = line:match("^%u+ (/[^?%s]*)%??(.-) HTTP")
    if not path then return nil, {} end
    local params = {}
    for k, v in (qs or ""):gmatch("([^&=]+)=([^&]+)") do
        params[k] = v
    end
    return path, params
end

local function drain_headers(client)
    while true do
        local h = client:receive("*l")
        if not h or h == "" or h == "\r" then break end
    end
end

local function send_json(client, body, status)
    status = status or "200 OK"
    local resp = "HTTP/1.1 " .. status .. "\r\n"
        .. "Content-Type: application/json\r\n"
        .. "Content-Length: " .. #body .. "\r\n"
        .. "Access-Control-Allow-Origin: *\r\n"
        .. "Connection: close\r\n\r\n"
        .. body
    client:send(resp)
    client:close()
end

-- ── 라우터 ────────────────────────────────────────────────────────
local function handle(client)
    client:settimeout(2)
    local line = client:receive("*l")
    if not line then client:close(); return end
    drain_headers(client)

    local path, params = parse_request(line)
    if not path then
        send_json(client, '{"error":"bad request"}', "400 Bad Request"); return
    end

    if path == "/health" then
        send_json(client, string.format(
            '{"status":"ok","lang":"lua","version":"%s","port":8007}', _VERSION))

    elseif path == "/api/lua/status" then
        send_json(client, string.format(
            '{"lang":"lua","version":"%s","port":8007,'
            .. '"paradigm":"cooperative-multitasking",'
            .. '"description":"single OS thread — coroutines yield/resume for interleaving",'
            .. '"max_feeds":6}',
            _VERSION))

    elseif path == "/api/lua/stream" then
        local n_feeds = math.max(1, math.min(tonumber(params["feeds"]) or 4, 6))
        local n_steps = math.max(10, math.min(tonumber(params["steps"]) or 200, 2000))

        local t0 = socket.gettime()
        local results, total_resumes = run_scheduler(n_feeds, n_steps)
        local elapsed_ms = (socket.gettime() - t0) * 1000

        send_json(client, string.format(
            '{"lang":"lua","version":"%s","paradigm":"coroutine",'
            .. '"n_feeds":%d,"steps_per_feed":%d,"total_resumes":%d,'
            .. '"elapsed_ms":%.2f,'
            .. '"scheduler":"single-thread round-robin — no OS threads, no locks, no callbacks",'
            .. '"feeds":[%s]}',
            _VERSION, n_feeds, n_steps, total_resumes,
            elapsed_ms, table.concat(results, ",")))

    else
        send_json(client, '{"error":"not found"}', "404 Not Found")
    end
end

-- ── 서버 루프 ─────────────────────────────────────────────────────
local server = assert(socket.bind("*", 8007))
server:settimeout(1)
io.write("Lua " .. _VERSION .. " Coroutine Stream Server on :8007\n")
io.flush()

while true do
    local client = server:accept()
    if client then
        local ok, err = pcall(handle, client)
        if not ok then
            io.write("[ERROR] " .. tostring(err) .. "\n"); io.flush()
            pcall(function() client:close() end)
        end
    end
end
