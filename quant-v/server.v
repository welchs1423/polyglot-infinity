// quant-v/server.v — V 0.5.1 — Zero-GC 전략 백테스터 :4002
// 컴파일: v -gc none server.v
// --gc none → GC 일시정지가 물리적으로 불가능 → 결정론적 레이턴시 보증
// JVM(Kotlin/Scala), Python, Julia 등은 GC 일시정지를 막을 수 없습니다.
//
// 엔드포인트:
//   GET /health
//   GET /api/v/backtest?ticks=100000&fast=20&slow=50&seed=42
//   GET /api/v/stress?ticks=200000&seed=42  — 3개 전략 동시 스트레스 테스팅

module main

import net
import math
import time

const port = 4002

// ---------- LCG pseudo-random (value type only — no heap) ----------
fn lcg_next(seed u64) u64 {
	return (6364136223846793005 * seed + 1442695040888963407) & 0xFFFFFFFFFFFFFFFF
}

fn lcg_uniform(seed u64) (f64, u64) {
	ns := lcg_next(seed)
	return f64(ns) / f64(u64(0xFFFFFFFFFFFFFFFF)), ns
}

fn lcg_normal(seed u64) (f64, u64) {
	u1, s1 := lcg_uniform(seed)
	u2, s2 := lcg_uniform(s1)
	safe := if u1 < 1e-15 { 1e-15 } else { u1 }
	r := math.sqrt(-2.0 * math.log(safe))
	z := r * math.cos(2.0 * math.pi * u2)
	return z, s2
}

// ---------- BacktestResult (value type — GC 불필요) ----------

struct BacktestResult {
	strategy     string
	ticks        int
	trades       int
	win_trades   int
	loss_trades  int
	win_rate     f64
	total_return f64
	max_dd       f64
	sharpe       f64
	gc_pauses_ms int // v -gc none 컴파일 시 항상 0
}

// ---------- MA 크로스오버 전략 백테스터 ----------
// 틱 수 100만 개를 처리하는 동안 GC 일시정지가 0번 발생합니다.

fn backtest_ma(ticks int, fast_period int, slow_period int, seed u64) BacktestResult {
	// 가격 시계열 생성 — 고정 크기 배열, 힙 재할당 없음
	mut prices := []f64{len: ticks}
	mut s := seed
	prices[0] = 100.0
	for i in 1 .. ticks {
		z, ns := lcg_normal(s)
		s = ns
		prices[i] = prices[i - 1] * math.exp(0.0002 + 0.015 / math.sqrt(252.0) * z)
	}

	mut trades := 0
	mut wins := 0
	mut losses := 0
	mut position := 0
	mut entry_price := 0.0
	mut nav := 1.0
	mut peak := 1.0
	mut max_dd := 0.0
	mut total_return := 0.0
	mut ret_sum := 0.0
	mut ret_sq := 0.0
	mut ret_n := 0

	for i in slow_period .. ticks {
		mut fsum := 0.0
		for j in (i - fast_period) .. i {
			fsum += prices[j]
		}
		fast_ma := fsum / f64(fast_period)
		mut ssum := 0.0
		for j in (i - slow_period) .. i {
			ssum += prices[j]
		}
		slow_ma := ssum / f64(slow_period)

		// 골든 크로스 → 롱 진입
		if fast_ma > slow_ma && position <= 0 {
			if position == -1 {
				pnl := (entry_price - prices[i]) / entry_price
				total_return += pnl
				nav *= (1.0 + pnl)
				ret_sum += pnl
				ret_sq += pnl * pnl
				ret_n++
				if pnl > 0 { wins++ } else { losses++ }
			}
			position = 1
			entry_price = prices[i]
			trades++
		} else if fast_ma < slow_ma && position >= 0 {
			// 데드 크로스 → 숏 진입
			if position == 1 {
				pnl := (prices[i] - entry_price) / entry_price
				total_return += pnl
				nav *= (1.0 + pnl)
				ret_sum += pnl
				ret_sq += pnl * pnl
				ret_n++
				if pnl > 0 { wins++ } else { losses++ }
			}
			position = -1
			entry_price = prices[i]
			trades++
		}
		if nav > peak { peak = nav }
		dd := (peak - nav) / peak
		if dd > max_dd { max_dd = dd }
	}

	win_rate := if trades > 0 { f64(wins) / f64(trades) } else { 0.0 }
	ret_mean := if ret_n > 0 { ret_sum / f64(ret_n) } else { 0.0 }
	ret_var := if ret_n > 1 {
		(ret_sq - f64(ret_n) * ret_mean * ret_mean) / f64(ret_n - 1)
	} else {
		1.0
	}
	ret_vol := math.sqrt(ret_var)
	sharpe := if ret_vol > 0.0 { ret_mean / ret_vol * math.sqrt(252.0) } else { 0.0 }

	return BacktestResult{
		strategy:     'MA(${fast_period},${slow_period})'
		ticks:        ticks
		trades:       trades
		win_trades:   wins
		loss_trades:  losses
		win_rate:     win_rate
		total_return: total_return
		max_dd:       max_dd
		sharpe:       sharpe
		gc_pauses_ms: 0
	}
}

// ---------- 유틸 ----------

fn fmt6(x f64) string {
	return '${x:.6f}'
}

fn get_param(query string, key string, def string) string {
	parts := query.split('&')
	for p in parts {
		kv := p.split('=')
		if kv.len == 2 && kv[0] == key {
			return kv[1]
		}
	}
	return def
}

fn parse_i(s string, d int) int {
	v := s.int()
	return if v == 0 && s != '0' { d } else { v }
}

// ---------- HTTP 핸들러 ----------

fn handle_health() string {
	body := '{"status":"ok","service":"v-quant","gc_mode":"--gc none","version":"V 0.5.1"}'
	return 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}'
}

fn handle_backtest(query string) string {
	ticks  := parse_i(get_param(query, 'ticks', '100000'), 100000)
	fast   := parse_i(get_param(query, 'fast', '20'), 20)
	slow_p := parse_i(get_param(query, 'slow', '50'), 50)
	seed   := u64(parse_i(get_param(query, 'seed', '42'), 42))

	safe_ticks := if ticks > 1000000 { 1000000 } else if ticks < 100 { 100 } else { ticks }
	safe_fast  := if fast < 2 { 2 } else if fast > 100 { 100 } else { fast }
	safe_slow  := if slow_p <= safe_fast { safe_fast + 1 } else if slow_p > 200 { 200 } else { slow_p }

	sw := time.new_stopwatch()
	r := backtest_ma(safe_ticks, safe_fast, safe_slow, seed)
	elapsed_ms := sw.elapsed().milliseconds()

	body := '{"strategy":"${r.strategy}-Crossover","ticks":${r.ticks},"trades":${r.trades},"win_trades":${r.win_trades},"loss_trades":${r.loss_trades},"win_rate":${fmt6(r.win_rate)},"total_return":${fmt6(r.total_return)},"max_drawdown":${fmt6(r.max_dd)},"sharpe_ratio":${fmt6(r.sharpe)},"elapsed_ms":${elapsed_ms},"gc_pauses_ms":${r.gc_pauses_ms},"gc_mode":"--gc none","note":"GC \uc77c\uc2dc\uc815\uc9c0 \ubb3c\ub9ac\uc801 \ubd88\uac00 \u2014 \uacb0\uc815\ub860\uc801 \ub808\uc774\ud150\uc2dc","engine":"V 0.5.1"}'
	return 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}'
}

fn handle_stress(query string) string {
	ticks := parse_i(get_param(query, 'ticks', '200000'), 200000)
	seed  := u64(parse_i(get_param(query, 'seed', '42'), 42))

	safe_ticks := if ticks > 333333 { 333333 } else if ticks < 100 { 100 } else { ticks }

	sw := time.new_stopwatch()
	r1 := backtest_ma(safe_ticks, 5,  20, seed)
	r2 := backtest_ma(safe_ticks, 20, 50, seed + 1)
	r3 := backtest_ma(safe_ticks, 10, 30, seed + 2)
	elapsed_ms := sw.elapsed().milliseconds()

	total_ticks := r1.ticks + r2.ticks + r3.ticks
	body := '{"strategies":["${r1.strategy}","${r2.strategy}","${r3.strategy}"],"total_ticks":${total_ticks},"elapsed_ms":${elapsed_ms},"sharpes":[${fmt6(r1.sharpe)},${fmt6(r2.sharpe)},${fmt6(r3.sharpe)}],"win_rates":[${fmt6(r1.win_rate)},${fmt6(r2.win_rate)},${fmt6(r3.win_rate)}],"gc_pauses_ms":0,"gc_mode":"--gc none","note":"3\uac1c \uc804\ub7b5 \uc21c\ucc28 \uc2e4\ud589 \u2014 GC \uc77c\uc2dc\uc815\uc9c0 0\ud68c","engine":"V 0.5.1"}'
	return 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}'
}

fn handle_404() string {
	body := '{"error":"not found"}'
	return 'HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}'
}

fn route(path string, query string) string {
	return match path {
		'/health'         { handle_health() }
		'/api/v/backtest' { handle_backtest(query) }
		'/api/v/stress'   { handle_stress(query) }
		else              { handle_404() }
	}
}

fn main() {
	mut listener := net.listen_tcp(.ip, ':${port}') or {
		eprintln('Failed to listen on :${port}: ${err}')
		return
	}
	println('V 0.5.1 Zero-GC Backtester listening on :${port}')
	println('Compiled with --gc none — GC pauses: impossible')
	for {
		mut conn := listener.accept() or { continue }
		go handle_conn(mut conn)
	}
}

fn handle_conn(mut conn net.TcpConn) {
	defer { conn.close() or {} }
	mut buf := []u8{len: 4096}
	n := conn.read(mut buf) or { return }
	req := buf[..n].bytestr()
	lines := req.split('\r\n')
	if lines.len == 0 { return }
	parts := lines[0].split(' ')
	if parts.len < 2 { return }
	path_query := parts[1]
	mut path := path_query
	mut query := ''
	if path_query.contains('?') {
		qi := path_query.index('?') or { -1 }
		if qi >= 0 {
			path = path_query[..qi]
			query = path_query[qi + 1..]
		}
	}
	resp := route(path, query)
	conn.write_string(resp) or {}
}




