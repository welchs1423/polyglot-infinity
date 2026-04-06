// quant-v/server.v — V 0.5 퀀트 분석 엔진 :4002
// Monte Carlo VaR · Kelly Criterion · 포트폴리오 최적화

module main

import net
import math

const port = 4002

// ---------- LCG 랜덤 ----------
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

// ---------- GBM Monte Carlo ----------
struct SimResult {
	ann_return f64
	ann_vol    f64
	var_95     f64
	cvar_95    f64
	sharpe     f64
	kelly      f64
	n          int
}

fn simulate(n int, mu f64, sigma f64, seed u64) SimResult {
	dt := 1.0 / 252.0
	drift := (mu - 0.5 * sigma * sigma) * dt
	diff := sigma * math.sqrt(dt)

	mut returns := []f64{len: n}
	mut s := seed
	for i in 0 .. n {
		z, ns := lcg_normal(s)
		s = ns
		returns[i] = drift + diff * z
	}

	// 평균 / 표준편차
	mut sum := 0.0
	for r in returns { sum += r }
	mean := sum / f64(n)

	mut var_sum := 0.0
	for r in returns { var_sum += (r - mean) * (r - mean) }
	vol := math.sqrt(var_sum / f64(n))

	ann_ret := mean * 252.0
	ann_vol := vol * math.sqrt(252.0)

	// VaR 95% (5th percentile)
	mut sorted := returns.clone()
	sorted.sort()
	idx := int(f64(n) * 0.05)
	var95 := sorted[idx]

	// CVaR
	mut tail_sum := 0.0
	mut tail_count := 0
	for r in sorted {
		if r <= var95 {
			tail_sum += r
			tail_count++
		}
	}
	cvar95 := if tail_count > 0 { tail_sum / f64(tail_count) } else { var95 }

	// Sharpe
	sharpe := if ann_vol > 0.0 { ann_ret / ann_vol } else { 0.0 }

	// Kelly Criterion  f* = μ/σ²
	kelly := if vol * vol > 0.0 { mean / (vol * vol) } else { 0.0 }

	return SimResult{
		ann_return: ann_ret
		ann_vol:    ann_vol
		var_95:     var95
		cvar_95:    cvar95
		sharpe:     sharpe
		kelly:      kelly
		n:          n
	}
}

// ---------- 포트폴리오 최적화 (2자산 Equal Weight vs Min Var) ----------
struct PortResult {
	eq_ret     f64
	eq_vol     f64
	eq_sharpe  f64
	mv_w1      f64
	mv_w2      f64
	mv_ret     f64
	mv_vol     f64
	mv_sharpe  f64
}

fn portfolio_opt(mu1 f64, mu2 f64, sig1 f64, sig2 f64, rho f64) PortResult {
	// Equal weight
	eq_ret := 0.5 * mu1 + 0.5 * mu2
	eq_var := 0.25 * sig1 * sig1 + 0.25 * sig2 * sig2 + 2.0 * 0.25 * rho * sig1 * sig2
	eq_vol := math.sqrt(eq_var)
	eq_sharpe := if eq_vol > 0.0 { eq_ret / eq_vol } else { 0.0 }

	// Min variance: w1 = (σ2² - ρσ1σ2) / (σ1² + σ2² - 2ρσ1σ2)
	denom := sig1 * sig1 + sig2 * sig2 - 2.0 * rho * sig1 * sig2
	mv_w1 := if denom > 0.0 { (sig2 * sig2 - rho * sig1 * sig2) / denom } else { 0.5 }
	mv_w1_clamped := if mv_w1 < 0.0 { 0.0 } else if mv_w1 > 1.0 { 1.0 } else { mv_w1 }
	mv_w2 := 1.0 - mv_w1_clamped

	mv_ret := mv_w1_clamped * mu1 + mv_w2 * mu2
	mv_var := mv_w1_clamped * mv_w1_clamped * sig1 * sig1 +
		mv_w2 * mv_w2 * sig2 * sig2 +
		2.0 * mv_w1_clamped * mv_w2 * rho * sig1 * sig2
	mv_vol := math.sqrt(mv_var)
	mv_sharpe := if mv_vol > 0.0 { mv_ret / mv_vol } else { 0.0 }

	return PortResult{
		eq_ret:    eq_ret
		eq_vol:    eq_vol
		eq_sharpe: eq_sharpe
		mv_w1:     mv_w1_clamped
		mv_w2:     mv_w2
		mv_ret:    mv_ret
		mv_vol:    mv_vol
		mv_sharpe: mv_sharpe
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

fn parse_f(s string, d f64) f64 {
	return s.f64()
}

fn parse_i(s string, d int) int {
	v := s.int()
	return if v == 0 && s != '0' { d } else { v }
}

// ---------- HTTP 핸들러 ----------
fn handle_health() string {
	body := '{"status":"ok","service":"v-quant","version":"V 0.5.1"}'
	return 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}'
}

fn handle_var(query string) string {
	n := parse_i(get_param(query, 'n', '252'), 252)
	mu := parse_f(get_param(query, 'mu', '0.08'), 0.08)
	sigma := parse_f(get_param(query, 'sigma', '0.2'), 0.20)
	seed := u64(parse_i(get_param(query, 'seed', '42'), 42))

	r := simulate(n, mu, sigma, seed)
	body := '{"n":${r.n},"annualized_return":${fmt6(r.ann_return)},"annualized_vol":${fmt6(r.ann_vol)},"var_95":${fmt6(r.var_95)},"cvar_95":${fmt6(r.cvar_95)},"sharpe_ratio":${fmt6(r.sharpe)},"kelly_fraction":${fmt6(r.kelly)},"engine":"V 0.5.1"}'
	return 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}'
}

fn handle_portfolio(query string) string {
	mu1 := parse_f(get_param(query, 'mu1', '0.10'), 0.10)
	mu2 := parse_f(get_param(query, 'mu2', '0.06'), 0.06)
	sig1 := parse_f(get_param(query, 'sig1', '0.20'), 0.20)
	sig2 := parse_f(get_param(query, 'sig2', '0.12'), 0.12)
	rho := parse_f(get_param(query, 'rho', '0.3'), 0.30)

	p := portfolio_opt(mu1, mu2, sig1, sig2, rho)
	body := '{"equal_weight":{"return":${fmt6(p.eq_ret)},"vol":${fmt6(p.eq_vol)},"sharpe":${fmt6(p.eq_sharpe)}},"min_variance":{"w1":${fmt6(p.mv_w1)},"w2":${fmt6(p.mv_w2)},"return":${fmt6(p.mv_ret)},"vol":${fmt6(p.mv_vol)},"sharpe":${fmt6(p.mv_sharpe)}},"engine":"V 0.5.1"}'
	return 'HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}'
}

fn handle_404() string {
	body := '{"error":"not found"}'
	return 'HTTP/1.1 404 Not Found\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: ${body.len}\r\nConnection: close\r\n\r\n${body}'
}

fn route(path string, query string) string {
	return match path {
		'/health' { handle_health() }
		'/api/v/var' { handle_var(query) }
		'/api/v/portfolio' { handle_portfolio(query) }
		else { handle_404() }
	}
}

// ---------- main ----------
fn main() {
	mut listener := net.listen_tcp(.ip, ':${port}') or {
		eprintln('Failed to listen on :${port}: ${err}')
		return
	}
	println('V 0.5.1 quant engine listening on :${port}')
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
