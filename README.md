# 🌈 Polyglot Infinity

> **20개 언어/런타임**(Svelte · Go · Python · Rust · C++ · **Lua · Zig · Kotlin · Elixir · Julia · R · F# · WebAssembly · OCaml · Crystal · Nim · Scala · Haskell · Ruby · Dart**)과 2개 DB(PostgreSQL · Redis)가 유기적으로 연결된
> **실시간 다중 통화 마이크로 대출 리스크 분석 플랫폼**

---

## 📐 시스템 아키텍처

```
[Svelte 5 · :5173]
       │ fetch
       ▼
[Go API Hub · :8080] ──────────────────────────────────┐
       │  ★ Lua EVAL 원자적 스크립트                      │
       ├─ Cache Hit → [Redis · :6379]                   │
       │                                                │
       ├─ Cache Miss → [Python FastAPI · :8000]         │
       │                    ├─ C++ FFI (libcore.so)     │
       │                    ├─ Zig FFI (libzigcore.so)  │
       │                    └─ Julia HTTP (:8002)       │
       │                                                │
       ├─ Pipeline → [Rust Axum · :8081] ───────────────┘
       │                  └─ [PostgreSQL · :5433]
       │
[Kotlin Scheduler · :9000]  ← 60s 코루틴 리포트 생성
[Elixir/Phoenix Hub · :4000] ← WebSocket · GenServer 폴링
[Julia GBM Engine · :8002]   ← 병렬 Monte Carlo
[R Plumber Engine · :8003]   ← MLE 분포 피팅 · VaR/CVaR
[F# ASP.NET Engine · :9001] ← Black-Scholes Greeks · DCF
[WebAssembly (Zig → WASM32)]  ← 브라우저 직접 실행 · 서버 왕복 없음
[OCaml Risk Engine · :8004]   ← 규칙 기반 리스크 판정 · 신용 스코어링
[Crystal Gateway · :9002]     ← 포트폴리오 성과 · Sharpe/MDD · FX 가중평균
[Nim Analytics · :8005]       ← 시계열 기술통계 · RSI/MACD/볼린저 모멘텀
[Scala Streamer · :9003]      ← 스트림 집계 · Holt 이중 지수평활 · SMA/percentile
[Haskell Pricer · :8006]      ← 순수 함수형 · Black-Scholes Greeks · GBM Monte Carlo
[Ruby Scorer · :9004]         ← 로지스틱 신용 스코어링 · 포트폴리오 요약 통계
[Dart Engine · :9005]         ← 채구 가격 · 듀레이션 · Nelson-Siegel 수익률 곡선
```

| 서비스 | 포트 | 역할 |
|:---|:---:|:---|
| Svelte 5 (SvelteKit + Bun) | 5173 | UI · 실시간 대시보드 |
| Go (`net/http`) | 8080 | API Hub · Redis 캐싱 · 프록시 |
| Python (FastAPI) | 8000 | 다중 환율 수집 · C++/Zig FFI · Julia HTTP |
| Rust (Axum + tokio) | 8081 | 고성능 벌크 인서트 파이프라인 |
| **Kotlin (코루틴)** | **9000** | **60초 주기 리스크 리포트 스케줄러** |
| **Elixir/Phoenix** | **4000** | **WebSocket Hub · GenServer OTP 슈퍼바이저** |
| **Julia (HTTP.jl)** | **8002** | **GBM 병렬 Monte Carlo · VaR/CVaR 95%** |
| **R (Plumber)** | **8003** | **MLE 분포 피팅 · VaR/CVaR · Sharpe Ratio** |
| **F# (ASP.NET 8)** | **9001** | **Black-Scholes Greeks · DCF 가치평가** |
| **WebAssembly (Zig → WASM32)** | **Browser** | **클라이언트 직접 실행 · Black-Scholes/VaR/DCF · 서버 불필요** |
| **OCaml 4.13** | **8004** | **규칙 기반 리스크 판정 · 신용 스코어링 (로지스틱)** |
| **Crystal 1.19** | **9002** | **포트폴리오 성과 · Sharpe/Sortino/MDD · FX 가중평균** |
| **Nim 2.2.8** | **8005** | **시계열 기술통계 · skewness/kurtosis/autocorr · RSI/MACD/볼린저** |
| **Scala 3.8.3** | **9003** | **스트림 집계 · Holt 이중 지수평활 · SMA/percentile/EWM** |
| **Haskell GHC 8.8.4** | **8006** | **순수 함수형 옵션 프라이서 · Black-Scholes Greeks · GBM Monte Carlo** |
| **Ruby 3.0.2** | **9004** | **로지스틱 신용 스코어링 · 포트폴리오 통계 (WEBrick stdlib)** |
| **Dart 3.11** | **9005** | **채구 가격 · Macaulay/Modified Duration · DV01 · Nelson-Siegel 수익률 곡선** |
| PostgreSQL | 5432 / 5433 | 시스템 로그 · 리스크 데이터 영구 저장 |
| Redis | 6379 | Python 분석 결과 캐싱 (**Lua EVAL 원자적 연산**) |
| **Zig (C ABI 라이브러리)** | N/A | **libzigcore.so — 변동성 추정 · VaR 계산** |
| **Lua (Redis EVAL 스크립트)** | N/A | **Go 내 원자적 캐시 히트/미스 카운터** |

---

## 🛠 기술 스택

| 영역 | 기술 |
|:---|:---|
| **Frontend** | SvelteKit (Svelte 5), Bun, TypeScript |
| **API Gateway** | Go 1.23+, `net/http`, `lib/pq`, `go-redis/v9` |
| **Scripting** | **Lua** — Redis EVAL 원자적 캐시 카운터 (Go 내 임베디드) |
| **Risk Engine** | Python 3, FastAPI, `ctypes` (C++ & Zig FFI) |
| **Core (C++)** | C++ (`-O3`), `libcore.so` 공유 라이브러리 |
| **Core (Zig)** | **Zig 0.13, `libzigcore.so` — 변동성 추정 · VaR 계산** |
| **Pipeline** | Rust, Axum, tokio, sqlx |
| **Scheduler** | **Kotlin 2.0 + Coroutines, Java HttpServer (:9000)** |
| **Realtime Hub** | **Elixir/Phoenix, OTP Supervisor, WebSocket (:4000)** |
| **Simulation** | **Julia 1.10, HTTP.jl, Threads.@threads GBM (:8002)** |
| **Statistics** | **R 4.1, Plumber, MASS — MLE 분포 피팅 · Sharpe (:8003)** |
| **Option Pricing** | **F# (.NET 8), ASP.NET Core — Black-Scholes Greeks · DCF (:9001)** |
| **WebAssembly** | **Zig 0.13 → WASM32 freestanding — 브라우저 클라이언트 실행 (서버 없음)** |
| **Risk Rules** | **OCaml 4.13, stdlib Unix HTTP — 규칙 기반 리스크 + 로지스틱 신용점수 (:8004)** |
| **Portfolio/FX** | **Crystal 1.19, HTTP::Server — 포트폴리오 Sharpe/Sortino/MDD + FX 가중평균 (:9002)** |
| **Time-series** | **Nim 2.2.8, asynchttpserver — 시계열 기술통계 + RSI/MACD/Bollinger (:8005)** |
| **Stream Agg** | **Scala 3.8.3, JDK HttpServer — Holt 이중 지수평활 + 스트림 집계 (:9003)** |
| **Option Pricer** | **Haskell GHC 8.8.4, Network.Socket — 순수 함수형 Black-Scholes Greeks + GBM Monte Carlo (:8006)** |
| **Credit Scoring** | **Ruby 3.0.2, WEBrick stdlib — 로지스틱 신용 스코어링 + 포트폴리오 요약 (:9004)** |
| **Yield Curve** | **Dart 3.11, dart:io HttpServer — 채구 가격 + Nelson-Siegel 수익률 곡선 (:9005)** |
| **Infra** | PostgreSQL, Redis, WSL2 (Ubuntu) |

---

## 🔌 API 명세

### Go `:8080`

| Method | Endpoint | 설명 |
|:---|:---|:---|
| `GET` | `/api/status` | 전체 시스템 상태 · Python 분석 결과 · Rust 상태 집계 |
| `GET` | `/api/history` | `system_logs` 최신 10건 조회 |
| `POST` | `/api/pipeline/trigger` | Rust 벌크 인서트 트리거 · 결과 DB 기록 |
| `GET` | `/api/cache/stats` | **Lua EVAL** 원자적 캐시 히트/미스 카운터 조회 |

### Python `:8000`

| Method | Endpoint | 설명 |
|:---|:---|:---|
| `GET` | `/api/analyze` | KRW·JPY·EUR·CNY 환율 수집 → C++/Zig FFI + Julia HTTP 리스크 계산 |

### Rust `:8081`

| Method | Endpoint | 설명 |
|:---|:---|:---|
| `GET` | `/api/rust/status` | 파이프라인 상태 · `risk_logs` 총 레코드 수 반환 |
| `POST` | `/api/bulk-insert` | 10,000건 리스크 데이터 트랜잭션 일괄 적재 |

### Kotlin `:9000`

| Method | Endpoint | 설명 |
|:---|:---|:---|
| `GET` | `/api/reports/latest` | 최신 리스크 리포트 10건 조회 |
| `GET` | `/api/reports/now` | 즉시 리포트 생성 및 반환 |
| `GET` | `/health` | 헬스체크 |

### Elixir `:4000`

| Method | Endpoint | 설명 |
|:---|:---|:---|
| `GET` | `/api/hub/status` | Phoenix Hub 상태 · PubSub 브로드캐스트 채널 확인 |
| `WS` | `/socket` (channel: `system:*`) | WebSocket 실시간 스냅샷 스트림 |

### Julia `:8002`

| Method | Endpoint | 설명 |
|:---|:---|:---|
| `GET` | `/api/julia/simulate` | GBM Monte Carlo (`paths`, `days`, `vol`, `mu` 파라미터) |
| `GET` | `/health` | 헬스체크 |

### R `:8003`

| Method | Endpoint | 설명 |
|:---|:---|:---|
| `GET` | `/api/r/fit` | MLE 정규·t분포 피팅 · VaR/CVaR 95% · Sharpe Ratio (`n`, `seed` 파라미터) |
| `GET` | `/api/r/correlation` | 4-asset 상관행렬 · 포트폴리오 연율화 변동성 |
| `GET` | `/health` | 헬스체크 |

### F# `:9001`

| Method | Endpoint | 설명 |
|:---|:---|:---|
| `GET` | `/api/fsharp/option` | Black-Scholes 옵션 가격 · Delta/Gamma/Vega/Theta/Rho (`s`,`k`,`r`,`sigma`,`t`) |
| `GET` | `/api/fsharp/dcf` | DCF 내재가치 · 안전마진 · 현금흐름 PV (`fcf`,`growth`,`terminal`,`wacc`,`years`) |
| `GET` | `/health` | 헬스체크 |

### Scala `:9003`

| Method | Endpoint | 설명 |
|:---|:---|:---|
| `GET` | `/api/scala/aggregate` | 의사난수 수익률 집계: mean/std/median/ann\_return/ann\_vol/p5/p95/sma20 (`mu`,`sigma`,`n`) |
| `GET` | `/api/scala/smooth` | Holt 이중 지수평활 + 1-step 예측 (`mu`,`sigma`,`n`,`alpha`,`beta`) |
| `GET` | `/health` | 헬스체크 |

### Haskell `:8006`

| Method | Endpoint | 설명 |
|:---|:---|:---|
| `GET` | `/api/haskell/blackscholes` | Black-Scholes 옵션 가격 · Delta/Gamma/Vega/Theta (`s`,`k`,`r`,`sigma`,`t`) |
| `GET` | `/api/haskell/montecarlo` | GBM Monte Carlo (LCG + Box-Muller) · VaR/CVaR 95% (`s`,`vol`,`mu`,`n`,`days`) |
| `GET` | `/health` | 헬스체크 |

### Ruby `:9004`

| Method | Endpoint | 설명 |
|:---|:---|:---|
| `GET` | `/api/ruby/score` | 로지스틱 회귀 신용 스코어(0-1000) · 등급 · PD (`debt_ratio`,`ltv`,`num_defaults`,`annual_income_k`) |
| `GET` | `/api/ruby/summary` | n개 대출 포트폴리오 요약: 평균/std/백분위수 + 리스크 분포 (`n`,`seed`) |
| `GET` | `/health` | 헬스체크 |

### Dart `:9005`

| Method | Endpoint | 설명 |
|:---|:---|:---|
| `GET` | `/api/dart/bond` | 채권 가격 · Macaulay/Modified Duration · Convexity · DV01 (`face`,`coupon`,`ytm`,`years`) |
| `GET` | `/api/dart/yieldcurve` | Nelson-Siegel 수익률 곡선 · 10Y-2Y 스프레드 · 곡선 형태 (`b0`,`b1`,`b2`,`tau`) |
| `GET` | `/health` | 헬스체크 |

---

## 🗄️ DB 스키마

```sql
-- Go (polyglot_db)
CREATE TABLE system_logs (
    id         SERIAL PRIMARY KEY,
    source     TEXT,
    message    TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Rust (postgres DB · :5433)
CREATE TABLE IF NOT EXISTS risk_logs (
    id         SERIAL PRIMARY KEY,
    user_id    INT NOT NULL,
    risk_score FLOAT NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Kotlin Scheduler (postgres DB · :5433)
CREATE TABLE IF NOT EXISTS risk_reports (
    id              SERIAL PRIMARY KEY,
    generated_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    avg_risk_score  FLOAT,
    total_records   INT,
    max_risk_score  FLOAT,
    min_risk_score  FLOAT
);
```

---

## 🚀 마일스톤 (최신순)

- [x] **2026-04-07** — **Dart 수익률 곡선 엔진 추가 (15번째 신규 언어)**
  - **Dart 3.11** (SDK zip 설치) `dart:io HttpServer` — 외부 패키지 완전 무
  - `/api/dart/bond`: 채구 가격 · Macaulay/Modified Duration · Convexity · DV01 (`:9005`)
  - `/api/dart/yieldcurve`: Nelson-Siegel 면 (b0/b1/b2/tau) · 10Y-2Y 스프레드 · 곡선 형태 판정
  - Svelte: **Dart Yield Curve Engine 패널** 추가 (청리씨 그라디언트)
- [x] **2026-04-07** — **Ruby 신용 스코어링 엔진 추가 (14번째 신규 언어)**
  - **Ruby 3.0.2** (apt 설치) WEBrick stdlib — 외부 gem 완전 무
  - `/api/ruby/score`: 로지스틱 회귀 신용 스코어(0-1000) + 등급(A+~D) + PD (`:9004`)
  - `/api/ruby/summary`: n개 대울 포트폴리오 요약 (평균/표준편차/백분위수 + 리스크 분포)
  - Svelte: **Ruby Credit Scorer 패널** 추가 (써레드 빨겕 그라디언트)
- [x] **2026-04-07** — **Haskell 옵션 프라이서 추가 (13번째 신규 언어)**
  - **Haskell GHC 8.8.4** (apt 설치) `Network.Socket` + `libghc-network-dev` — Stdlib 전용
  - `/api/haskell/blackscholes`: Black-Scholes 옵션 가격 + Delta/Gamma/Vega/Theta (`:8006`)
  - `/api/haskell/montecarlo`: GBM Monte Carlo (LCG + Box-Muller) • VaR/CVaR 95% + 연율화 수익률/변동성
  - Svelte: **Haskell Option Pricer 패널** 추가 (보라 그라디언트)
- [x] **2026-04-07** — **Scala 스트리밍 집계 엔진 추가 (12번째 신규 언어)**
  - **Scala 3.8.3** (Coursier 설치) + JDK 21 내장 `HttpServer` — 외부 의존 무
  - `/api/scala/aggregate`: mean/std/median/ann_return/ann_vol/p5/p95/sma20 (`:9003`)
  - `/api/scala/smooth`: Holt 이중 지수평활 · 1-step ahead 예측
  - Svelte: **Scala Streaming Aggregator 패널** 추가 (빨강 그라디언트)
- [x] **2026-04-07** — **Nim 시계열 분석 엔진 추가 (11번째 신규 언어)**
  - **Nim 2.2.8** (choosenim 설치) asynchttpserver — 외부 패키지 무의존
  - `/api/nim/timeseries`: mean/std/skewness/excess_kurtosis/autocorr 연환산 (`:8005`)
  - `/api/nim/momentum`: RSI(14) · MACD · EMA12/26 · 볼린저밴드 (너비/위치)
  - Svelte: **Nim Time-series Analytics 패널** 추가 (초록 그라디언트)
- [x] **2026-04-07** — **Crystal 포트폴리오 게이트웨이 추가 (10번째 신규 언어)**
  - **Crystal 1.19** (Ruby 문법 + LLVM 싼 컴파일) `HTTP::Server` — 3.2MB 네이티브 바이너리
  - `/api/crystal/portfolio`: 의사난수 수익률 시뮬레이션 → Total Return · Sharpe · Sortino · MDD (`:9002`)
  - `/api/crystal/fx`: USD/EUR/JPY/CNY 가중평균 KRW 환율
  - Svelte: **Crystal Portfolio Gateway 패널** 추가 (뷁보라 그라디언트)
- [x] **2026-04-07** — **OCaml 리스크 엔진 추가 (9번째 신규 언어)**
  - **OCaml 4.13** stdlib Unix 소켓 HTTP 서버 — 외부 패키지 무의존 네이티브 컴파일 (`ocamlfind ocamlopt -package unix`)
  - `/api/ocaml/risk`: 부체비율·영변도·레버리지·신용점수 규칙 기반 LOW/MEDIUM/HIGH/CRITICAL 판정 (`:8004`)
  - `/api/ocaml/score`: 로지스틱 회귀 신용 점수 + A+~D 등급
  - Svelte: **OCaml Risk Rule Engine 패널** 추가 (리스크 레벨 색상 코딩)
- [x] **2026-04-08** — **WebAssembly 추가 (8번째 신규 언어 — 브라우저 런타임)**
  - **Zig → WASM32 freestanding**: `finance.wasm` (24KB) — normCdf · bsCall · bsPut · bsDelta · bsGamma · varNormal · dcfValue
  - Svelte: **WebAssembly 패널** 추가 (`fetch` → `WebAssembly.instantiate` · 서버 왕복 없음)
- [x] **2026-04-08** — **F# 옵션 프라이서 추가 (7번째 신규 언어)**
  - **F# (.NET 8) + ASP.NET Core**: Black-Scholes 옵션 가격 · Delta/Gamma/Vega/Theta/Rho · DCF 가치평가 (`:9001`)
  - Svelte: **F# Black-Scholes 패널** 추가 (6-grid Greeks 카드)
- [x] **2026-04-08** — **R 통계 엔진 추가 (6번째 신규 언어)**
  - **R 4.1 + Plumber**: MLE 정규/t분포 피팅 · VaR/CVaR 95% · Sharpe Ratio · 4-asset 상관행렬 (`:8003`)
  - Svelte: **R Distribution Fit 패널** 추가
- [x] **2026-04-08** — **5개 언어 추가 (Lua · Zig · Kotlin · Elixir · Julia)**
  - **Lua**: Go 내 Redis `EVAL` 원자적 Lua 스크립트로 캐시 히트/미스 카운터 (`/api/cache/stats`)
  - **Zig 0.13**: `libzigcore.so` C ABI — `volatility_estimate()` · `value_at_risk()` · Python ctypes 연동
  - **Kotlin 2.0**: 코루틴 스케줄러 `:9000` — 60초 주기 리스크 리포트 자동 생성 (`scheduler.jar` 빌드 완료)
  - **Elixir/Phoenix**: OTP Supervisor · GenServer Poller · WebSocket Channel `:4000` (코드 완성, Erlang 설치 필요)
  - **Julia 1.10**: `Threads.@threads` GBM Monte Carlo `:8002` — VaR 95% · CVaR 95% · Sharpe Ratio
  - Svelte: **Lua/Julia/Kotlin/Elixir 패널** 4개 추가, Zig 상태 카드 추가
  - Svelte: `reports` null 안전성 버그 수정 (`reports.length` → `reports && reports.length`)
- [x] **2026-04-07** — 전 서비스 연동 완성 및 UI 기능 대폭 강화
  - Rust 포트 불일치 버그 수정 (3000 → **8081**)
  - Rust `GET /api/rust/status` 신규 추가 (DB 레코드 수 포함)
  - Go `POST /api/pipeline/trigger` 신규 추가 (Rust 프록시 + DB 로깅)
  - Python 단일 통화(KRW) → **4개 통화(KRW·JPY·EUR·CNY) 가중합** 복합 리스크 연산
  - Svelte: **Auto-Sync 토글** (10초 자동 갱신) 추가
  - Svelte: **Bulk Insert 트리거 패널** 추가 (소요시간·적재 건수 표시)
  - Svelte: Python 카드에 **멀티 통화 칩**, Rust 카드에 **DB 레코드 수** 표시
- [x] **2026-03-18** — Rust 파이프라인 실전 가동 · Docker PostgreSQL 컨테이너 연동
- [x] **2026-03-07** — 외부 금융 API(USD/KRW) 연동 · Svelte 금융 데이터 시각화
- [x] **2026-03-05** — C++ Core 엔진 구축 · Python FFI 연동 · Python 대비 **47배** 속도 향상
- [x] **2026-02-25** — Svelte 상태 카드 UI 고도화 · TypeScript/CSS 경고 제거
- [x] **2026-02-24** — Rust Axum 파이프라인 초기화 · `--release` 최적화 검증
- [x] **2026-02-20** — Redis Cache-Aside 패턴 도입 (TTL 10s)
- [x] **2026-02-18** — Go `/api/history` 로그 조회 API · Svelte 로그 테이블 UI
- [x] **2026-02-16** — PostgreSQL 스키마 설계 · Go DB 연동 · Go 1.23+ 업그레이드
- [x] **2026-02-15** — Svelte ↔ Go ↔ Python 3단 대통합 성공
- [x] **2026-02-14** — 프로젝트 초기화 (SvelteKit + Bun, Go API, Tailwind CSS v4)
- [ ] Docker Compose 전체 스택 컨테이너화

---

## 🏗️ 개발 로그

### 🎨 Svelte 5 (Frontend)

<details open>
<summary><strong>📅 2026-04-08 : 5개 언어 패널 추가 · 버그 수정</strong></summary>

#### ✅ 구축 내역
- **Zig 상태 카드**: 변동성 추정치 · VaR 95% 표시.
- **Lua Cache Stats 패널**: `/api/cache/stats` 호출 → 히트/미스 카운터 박스.
- **Julia Monte Carlo 패널**: 6-grid 메트릭 카드 (VaR, CVaR, 평균, 변동성, Sharpe, 경로 수).
- **Kotlin Reports 패널**: 스케줄러 리포트 테이블 (평균·최대·최소 리스크 스코어).
- **Elixir Hub 패널**: Hub 상태 확인 + WebSocket 안내.

#### 🔧 버그 수정
- **Svelte TS 오류 수정**: `reports` 초기값이 `null`이므로 `reports.length` 접근 시 `TS18047` 발생 → `reports && reports.length > 0` 조건으로 수정.
</details>

<details>
<summary><strong>📅 2026-04-07 : UI 기능 대폭 강화</strong></summary>

#### ✅ 구축 내역
- **Auto-Sync 토글**: 활성화 시 10초마다 `/api/status` · `/api/history` 자동 갱신. `onDestroy`로 인터벌 메모리 정리.
- **Rust Pipeline 패널**: `POST /api/pipeline/trigger` 호출 후 적재 건수·소요 시간 실시간 표시.
- **멀티 통화 칩**: Python 카드에 KRW·JPY·EUR·CNY 환율 값을 뱃지로 표시.
- **Rust DB 레코드 수**: Rust 카드에 `total_risk_logs` 값 표시.
</details>

<details>
<summary><strong>📅 2026-02-25 : 대시보드 고도화</strong></summary>

#### ✅ 구축 내역
- JSON 데이터를 상태 카드 그리드로 재설계하여 가독성 극대화.
- JSDoc `@type` 도입으로 Svelte 5 `$state` TypeScript 추론 에러 해결.
- CSS `background-clip` 표준 속성 적용으로 브라우저 호환성 경고 제거.
</details>

<details>
<summary><strong>📅 2026-02-14 : 프로젝트 스캐폴딩</strong></summary>

#### ✅ 구축 내역
- Bun 런타임 기반 SvelteKit 프로젝트 초기화.
- Tailwind CSS v4 디자인 시스템 통합.
- Go 백엔드 통신용 Fetch 로직 구현.
</details>

<br>

### ⚙️ Go (API Hub)

<details open>
<summary><strong>📅 2026-04-07 : Pipeline Trigger API 추가</strong></summary>

#### ✅ 구축 내역
- **`POST /api/pipeline/trigger`**: Rust `:8081/api/bulk-insert`를 프록시 호출, 결과를 `system_logs`에 기록 후 JSON 반환.
- Rust 포트 불일치 버그 수정 (`:3000` → `:8081`).
</details>

<details>
<summary><strong>📅 2026-02-18 : 로그 조회 API</strong></summary>

#### ✅ 구축 내역
- `GET /api/history`: PostgreSQL 로그 최신 10건 DESC 조회.
</details>

<details>
<summary><strong>📅 2026-02-16 : DB 연동 · 버전 업그레이드</strong></summary>

#### ✅ 구축 내역
- `lib/pq` 기반 PostgreSQL 접속 및 API 요청 시 자동 로그 적재.
- Go 1.18 → 1.23+ 업그레이드.

#### 🔍 트러블슈팅
| 이슈 | 해결 |
|:---|:---|
| 최신 패키지 미지원 | PPA 추가 후 Go 1.23+ 업그레이드 |
| VS Code `gopls` 멈춤 | 언어 서버 재시작 |
</details>

<details>
<summary><strong>📅 2026-02-14 : 초기 서버 구축</strong></summary>

#### ✅ 구축 내역
- `net/http` 기반 웹 서버 구동.
- CORS 정책 설정 완료.
</details>

<br>

### 🐍 Python (Risk Engine)

<details open>
<summary><strong>📅 2026-04-07 : 다중 통화 복합 리스크 분석</strong></summary>

#### ✅ 구축 내역
- **4개 통화 동시 수집**: KRW(45%) · JPY(25%) · EUR(20%) · CNY(10%) 가중합으로 복합 리스크 이터레이션 계산.
- API 실패 시 통화별 폴백 값 개별 적용.
- 응답에 `rates` 객체 및 `rate_summary` 필드 추가.
</details>

<details>
<summary><strong>📅 2026-03-07 : 외부 환율 API 연동</strong></summary>

#### ✅ 구축 내역
- `open.er-api.com`에서 실시간 USD/KRW 환율 수집.
- 환율 기반 C++ FFI 연산 이터레이션 동적 계산.
</details>

<details>
<summary><strong>📅 2026-02-15 : 엔진 구축</strong></summary>

#### ✅ 구축 내역
- FastAPI 서버 구축 및 `venv` 가상환경 구성.

#### 🔍 트러블슈팅
| 이슈 | 해결 |
|:---|:---|
| `venv` 생성 실패 | `sudo apt install python3-venv` |
| `uvicorn` 미인식 | `python3-pip` 설치 후 `python3 -m` 방식 적용 |
| `ImportError` | `FastAPI` 대소문자 오타 수정 |
| Git 저장소 오염 | `git rm -r --cached venv/` |
</details>

<br>

### ⚡ C++ (Core Engine)

<details open>
<summary><strong>📅 2026-03-05 : FFI 연동 완료</strong></summary>

#### ✅ 구축 내역
- g++ `-O3` 최적화 옵션으로 `libcore.so` 공유 라이브러리 빌드.
- Python `ctypes`로 C++ 함수 직접 호출 인터페이스 구축.
- 순수 Python 대비 **약 47배** 처리 속도 향상 검증.
</details>

<br>

### 🦀 Rust (Data Pipeline)

<details open>
<summary><strong>📅 2026-04-07 : 상태 API 추가 · 포트 통일</strong></summary>

#### ✅ 구축 내역
- **`GET /api/rust/status`** 신규 추가: `risk_logs` 총 레코드 수를 집계하여 반환.
- 포트 `:3000` → **`:8081`** 변경 (Go와 일치).
</details>

<details>
<summary><strong>📅 2026-03-18 : 파이프라인 실전 가동</strong></summary>

#### ✅ 구축 내역
- `sqlx` 비동기 드라이버 · 트랜잭션 기반 벌크 인서트 구현.
- 10,000건 리스크 데이터 초고속 DB 적재 성공.
- Docker 기반 PostgreSQL `:5433` 컨테이너 연동.
</details>

<details>
<summary><strong>📅 2026-02-24 : 뼈대 구축</strong></summary>

#### ✅ 구축 내역
- Axum + tokio 비동기 서버 초기화.
- `--release` 모드 컴파일러 최적화 검증.
- `target/` 빌드 디렉토리 `.gitignore` 등록.
</details>

<br>

### 🗄️ PostgreSQL / Redis

<details open>
<summary><strong>📅 2026-02-20 : Redis 캐싱 레이어 도입</strong></summary>

#### ✅ 구축 내역
- **Cache-Aside 패턴**: Redis 우선 조회 → Miss 시에만 Python 엔진 호출.
- TTL 10초 설정으로 데이터 정합성 유지.

#### 🔍 트러블슈팅
| 이슈 | 해결 |
|:---|:---|
| Panic (Nil Pointer) | Redis `NewClient` 초기화 코드 누락 추가 |
| JSON 키 오타 | `anlysis` → `analysis` 수정 |
</details>

<details>
<summary><strong>📅 2026-02-16 : DB 구축</strong></summary>

#### ✅ 구축 내역
- WSL 환경 내 PostgreSQL 설치 및 서비스 구동.
- `dev` 유저 · `polyglot_db` 데이터베이스 · `system_logs` 테이블 설계.
</details>

---

### 🌙 Lua (Redis 원자적 스크립팅)

<details open>
<summary><strong>📅 2026-04-08 : Redis EVAL 원자적 캐시 카운터</strong></summary>

#### ✅ 구축 내역
- Go 내 `redis.NewScript` 로 Lua 스크립트 2개 정의: `luaGetAndCount` (GET + 히트/미스 INCR 원자적), `luaSetWithTTL` (SET + EXPIRE 원자적).
- `GET /api/cache/stats` 엔드포인트로 히트·미스 카운터 노출.
- Lua 스크립트는 Redis 서버에서 원자적으로 실행되어 경쟁 조건 방지.
</details>

<br>

### ⚡ Zig (C ABI Core 라이브러리)

<details open>
<summary><strong>📅 2026-04-08 : libzigcore.so 구축 · Python FFI 연동</strong></summary>

#### ✅ 구축 내역
- Zig 0.13.0 설치 (`~/.local/zig`).
- `core-zig/src/core.zig`: `extreme_computation`, `volatility_estimate`, `value_at_risk` C ABI 함수 구현.
- `zig build` → `core-zig/zig-out/lib/libzigcore.so` (`ReleaseFast` 최적화).
- Python `brain-python/main.py` ctypes로 Zig FFI 연동.
</details>

<br>

### ☕ Kotlin (코루틴 스케줄러)

<details open>
<summary><strong>📅 2026-04-08 : 리스크 리포트 스케줄러 구축</strong></summary>

#### ✅ 구축 내역
- Kotlin 2.0.21 + OpenJDK 21 설치 (`~/.local/kotlinc`, `~/.local/jdk`).
- `scheduler-kotlin/src/main/kotlin/com/polyglot/Main.kt`: Java 내장 `HttpServer` 사용 (Ktor 대신 — 의존성 최소화).
- `initDb()` → `risk_reports` 테이블 자동 생성.
- `runScheduler()` 코루틴 → 60초 주기 리스크 통계 집계 후 DB 적재.
- `build.sh` + `run.sh` 제공, `scheduler.jar` 빌드 완료.

#### 🔍 트러블슈팅
| 이슈 | 해결 |
|:---|:---|
| Ktor transitive JAR 누락 | Ktor 제거, Java 내장 `HttpServer`로 대체 |
| SDKMAN 설치 실패 (`zip` 없음) | 직접 JDK/Kotlin 바이너리 다운로드 |
</details>

<br>

### 💜 Elixir/Phoenix (WebSocket Hub)

<details open>
<summary><strong>📅 2026-04-08 : OTP Supervisor + WebSocket Channel 구조 완성</strong></summary>

#### ✅ 구축 내역
- `hub-elixir/mix.exs`: Phoenix, phoenix_pubsub, bandit, jason, httpoison 의존성.
- `application.ex`: OTP Supervisor (PubSub + Poller + Bandit).
- `poller.ex`: GenServer — 10초 주기 Go API 폴링 후 `Phoenix.PubSub` 브로드캐스트.
- `channels/system_channel.ex`: 클라이언트 join 시 즉시 스냅샷 push.
- **실행**: Erlang/OTP 설치 후 `cd hub-elixir && mix deps.get && mix run --no-halt`.

#### 🔍 트러블슈팅
| 이슈 | 해결 |
|:---|:---|
| Erlang/OTP 빌드(97MB) 시간 초과 | 코드 완성 후 런타임 설치 별도 진행으로 분리 |
</details>

<br>

### 🔬 Julia (Monte Carlo 엔진)

<details open>
<summary><strong>📅 2026-04-08 : GBM 병렬 시뮬레이션 · VaR/CVaR 서버</strong></summary>

#### ✅ 구축 내역
- Julia 1.10.5 설치 (`~/.local/julia`), HTTP.jl + JSON3.jl 패키지 설치.
- `engine-julia/server.jl`: `Threads.@threads` 병렬 GBM Monte Carlo 구현.
- 리스크 메트릭: VaR 95%, CVaR 95%, 평균/표준편차, 최대/최소 수익률, Sharpe Ratio.
- `GET /api/julia/simulate?paths=&days=&vol=&mu=` 쿼리 파라미터 지원.
- Python `brain-python/main.py`에서 Julia 서버 호출 (graceful fallback).
- 로직 검증 완료: `mean=0.0495 std=0.2067`.
</details>

<br>

### 📊 R (통계 분석 엔진)

<details open>
<summary><strong>📅 2026-04-08 : MLE 분포 피팅 · VaR/CVaR · 상관 분석</strong></summary>

#### ✅ 구축 내역
- R 4.1.2 (사전 설치), plumber + jsonlite 패키지 설치 (`~/R/library`).
- `engine-r/server.R`: 두 엔드포인트 구현:
  - `/api/r/fit` — `MASS::fitdistr()` MLE 정규/t분포 피팅, VaR 95%, CVaR 95%, Sharpe Ratio.
  - `/api/r/correlation` — 4-asset(KRW/JPY/EUR/CNY) 상관행렬, 등가중 포트폴리오 연율화 변동성.
- `engine-r/run.R`: Plumber HTTP 진입점 (`:8003`).
- 로직 검증 완료: `VaR 95%=0.0288 CVaR 95%=0.0361`.
- Svelte: **R Distribution Fit 패널** (6-grid 메트릭) 추가.

#### 🔍 트러블슈팅
| 이슈 | 해결 |
|:---|:---|
| `/usr/local/lib/R` 쓰기 권한 없음 | `~/R/library` 사용자 라이브러리 경로 지정 |
| `curl` 패키지 빌드 실패 | `libcurl4-openssl-dev` + `libsodium-dev` sudo 설치 후 재시도 |
</details>

<br>

### 🎯 Dart (수익률 곡선 엔진)

<details open>
<summary><strong>📅 2026-04-07 : 채권 가격 + Nelson-Siegel 수익률 곡선</strong></summary>

#### ✅ 구축 내역
- Dart 3.11.4 (SDK zip 직접 다운로드 → `~/.local/dart-sdk`) `dart:io HttpServer` — 외부 패키지 완전 무.
- `engine-dart/bin/server.dart`: 순수 함수형 채권 수학 구현.
- `bondPrice` (반기 이표), `macaulayDuration`, `modifiedDuration`, `convexity`, `dv01`.
- `nelsonSiegel` — b0(수준)/b1(기울기)/b2(곡률)/tau(감쇠) 4-파라미터 수익률 면 모델.
- `/api/dart/bond`: 채권 가격 + 6개 지표.
- `/api/dart/yieldcurve`: 10개 만기 수익률 배열 + 10Y-2Y 스프레드 + 곡선 형태(normal/inverted).
- Svelte: 청리색 그라디언트 **Dart Yield Curve Engine 패널** 추가.

#### 🔍 트러블슈팅
| 이슈 | 해결 |
|:---|:---|
| `apt install dart` —  GPG 서명 실패 | SDK zip 직접 다운로드 후 `~/.local/dart-sdk` 추출 |
| `The argument type 'num' can't be assigned to 'double'` | 정수 리터럴 `[0.25, 0.5, 1, 2, ...]` → `[0.25, 0.5, 1.0, 2.0, ...]` 로 수정 |
</details>

<br>

### 💎 Ruby (신용 스코어링 엔진)

<details open>
<summary><strong>📅 2026-04-07 : 로지스틱 회귀 신용 스코어 + 포트폴리오 요약</strong></summary>

#### ✅ 구축 내역
- Ruby 3.0.2 (`apt install ruby`) + WEBrick stdlib — 외부 gem 완전 무.
- `scorer-ruby/server.rb`: `credit_score` 함수 — 4-feature 로지스틱 회귀 (debt_ratio/LTV/num_defaults/income).
- 점수 0-1000, 등급 A+~D, 리스크 티어 LOW/MEDIUM/HIGH/CRITICAL.
- `/api/ruby/score`: 개별 신용 평가.
- `/api/ruby/summary`: LCG 의사난수 → n개 대출 시뮬레이션 → 분포/백분위수/리스크 분포.
- Svelte: 쉐이드 빨강 그라디언트 **Ruby Credit Scorer 패널** 추가.

#### 🔍 트러블슈팅
| 이슈 | 해결 |
|:---|:---|
| `ruby` apt 패키지명 | `apt install ruby` (버전 3.0.2 설치됨) |
</details>

<br>

### λ Haskell (순수 함수형 옵션 프라이서)

<details open>
<summary><strong>📅 2026-04-07 : Black-Scholes Greeks + GBM Monte Carlo</strong></summary>

#### ✅ 구축 내역
- GHC 8.8.4 (`apt install ghc`) + `libghc-network-dev` — stdlib 전용, 외부 의존 없음.
- `pricer-haskell/server.hs`: 순수 함수형 구현, IO 모나드 내 소켓 서버.
- `normCdf` (Hart 근사), `blackScholes` — call/put/Delta/Gamma/Vega/Theta/d1/d2.
- `monteCarloFinals` — LCG 의사난수 + Box-Muller 변환 → GBM 경로 생성.
- `/api/haskell/blackscholes`: 6개 Greeks 반환.
- `/api/haskell/montecarlo`: 연율화 수익률/변동성 · VaR 95% · CVaR 95% · 평균 최종가격.
- `ghc -O2 -o server server.hs` → 네이티브 바이너리 컴파일.
- Svelte: 보라 그라디언트 **Haskell Option Pricer 패널** 추가.

#### 🔍 트러블슈팅
| 이슈 | 해결 |
|:---|:---|
| `Could not find module 'Network.Socket'` | `sudo apt install libghc-network-dev` |
</details>

<br>

### ⚡ Scala (스트리밍 집계 엔진)

<details open>
<summary><strong>📅 2026-04-07 : 스트림 집계 + Holt 이중 지수평활 예측</strong></summary>

#### ✅ 구축 내역
- Scala 3.8.3 (Coursier 설치) + JDK 21 내장 `com.sun.net.httpserver.HttpServer` — 외부 의존 완전 무.
- `streamer-scala/server.scala`: `object Stats` — mean/variance/stdDev/median/percentile/sma/ewma/holtSmooth.
- `LazyList.iterate(...).drop(1)` — Box-Muller 변환 시 seed 값 제외 (NaN 방지).
- `/api/scala/aggregate`: 252일 의사난수 수익률 시계열 집계 통계 + SMA-20.
- `/api/scala/smooth`: Holt Double Exponential Smoothing (α/β 파라미터) + 1-step 예측.
- `streamer-scala/server.jar` (25KB) + `run.sh` (JDK PATH 자동 설정).
- Svelte: 빨강 그라디언트 **Scala Streaming Aggregator 패널** 추가.

#### 🔍 트러블슈팅
| 이슈 | 해결 |
|:---|:---|
| `scalac: java not found` | JDK가 `/home/dev/.local/jdk/bin`에 있어 PATH에 없음 → `run.sh`에서 export 설정 |
| `@main def` → `CommandLineParser$ParseError` | `object Main { def main(args: Array[String]) }` 패턴으로 변경 |
| Box-Muller → NaN | `LazyList.iterate(seed)` 시 seed 값(3.0) 포함으로 log(>1) → sqrt(음수) → `.drop(1)` 으로 수정 |
</details>

<br>

### 💎 Nim (시계열 분석 엔진)

<details open>
<summary><strong>📅 2026-04-07 : 시계열 기술통계 + RSI/MACD/볼린저 모멘텀</strong></summary>

#### ✅ 구축 내역
- `choosenim` 공식 설치 → Nim 2.2.8 (`~/.nimble/bin`).
- `analytics-nim/server.nim`: `asynchttpserver` 내장 → 외부 패키지 무의존.
- `/api/nim/timeseries`: mean/std/skewness/excess_kurtosis/autocorr(lag=1) + 연환산 수익률/변동성.
- `/api/nim/momentum`: RSI(14) · MACD · EMA12/26 · 볼린저밴드 너비/위치.
- `nim compile --opt:speed` → C 트랜스파일 후 gcc 최적화 컴파일.
- Svelte: 초록 그라디언트 Nim 패널 추가.

#### 🔍 트러블슈팅
| 이슈 | 해결 |
|:---|:---|
| `apt install nim` 패키지 없음 | choosenim 공식 설치 스크립트 사용 |
| `else 0.0` 문법 오류 | Nim `if` 표현식은 `else:` 콜론 필수 |
</details>

<br>
### � Crystal (포트폴리오 게이트웨이)

<details open>
<summary><strong>📅 2026-04-07 : 포트폴리오 성과 분석 · FX 가중평균 환율</strong></summary>

#### ✅ 구축 내역
- `crystal-lang` 공식 설치 스크립트 → Crystal 1.19.1 (LLVM 20.1.8).
- `gateway-crystal/server.cr`: `HTTP::Server` 내장 라이브러리로 구현 (외부 shard 무의존).
- `/api/crystal/portfolio`: 의사난수 수익률 시뮬레이션 → Total Return · 연환산 변동성 · Sharpe · Sortino · MDD.
- `/api/crystal/fx`: USD/EUR/JPY/CNY 가중평균 KRW 환율 계산.
- `crystal build --release` → 3.2MB 네이티브 바이너리 (LLVM 최적화).
- Svelte: 보라 그라디언트 Crystal 패널 추가.

#### 🔍 트러블슈팅
| 이슈 | 해결 |
|:---|:---|
| 포트 9002 이미 사용 중 (이전 프로세스) | `fuser -k 9002/tcp` 로 강제 종료 후 재기동 |
</details>

<br>

### �🐪 OCaml (리스크 룰 엔진)

<details open>
<summary><strong>📅 2026-04-07 : 규칙 기반 리스크 판정 · 신용 스코어링</strong></summary>

#### ✅ 구축 내역
- `apt install ocaml ocaml-findlib` — OCaml 4.13.1 + ocamlfind 설치.
- `risk-ocaml/server.ml`: 외부 패키지 의존 없이 `Unix` stdlib 소켓으로 HTTP 서버 구현.
- `/api/ocaml/risk`: 부채비율·변동성·레버리지·신용점수 4개 규칙 → LOW/MEDIUM/HIGH/CRITICAL 판정.
- `/api/ocaml/score`: 로지스틱 회귀 근사 → 300~850 신용점수 + A+~D 등급 + 상환 확률.
- `ocamlfind ocamlopt -package unix -linkpkg` 단일 명령 컴파일 → 1.4MB 네이티브 바이너리.
- Svelte: 리스크 레벨 색상 코딩 (green/yellow/orange/red) 패널 추가.

#### 🔍 트러블슈팅
| 이슈 | 해결 |
|:---|:---|
| 외부 HTTP 라이브러리 opam 설치 불필요 | stdlib `Unix` 소켓으로 직접 HTTP 파싱 구현 |
</details>

<br>
### �️ WebAssembly (Client-side)

<details open>
<summary><strong>📅 2026-04-08 : Zig → WASM32 · 브라우저 직접 실행</strong></summary>

#### ✅ 구축 내역
- `wasm-zig/src/finance.zig`: `normCdf` · `bsCall` · `bsPut` · `bsDelta` · `bsGamma` · `varNormal` · `dcfValue` 구현.
- `wasm32-freestanding` + `ReleaseFast` 컴파일 → `portal-svelte/static/finance.wasm` (24KB).
- Svelte: `fetch('/finance.wasm')` → `WebAssembly.instantiate` → 내보낸 함수 직접 호출 (서버 없음).
- 패널: Call·Put 가격, Delta, Gamma, VaR 95%, DCF Value 실시간 계산 표시.

#### 🔍 트러블슈팅
| 이슈 | 해결 |
|:---|:---|
| `-dynamic` 플래그 실패 (`dynamic linking unavailable on wasm32-freestanding`) | `--export=funcname` 명시 플래그로 대체 |

#### 🔧 WASM 재빌드 명령
```bash
~/.local/zig/zig build-lib wasm-zig/src/finance.zig \
  -target wasm32-freestanding -O ReleaseFast \
  --export=normCdf --export=bsCall --export=bsPut \
  --export=bsDelta --export=bsGamma --export=varNormal --export=dcfValue \
  -femit-bin=portal-svelte/static/finance.wasm
```
</details>

<br>

### �🟣 F# (옵션 프라이서)

<details open>
<summary><strong>📅 2026-04-08 : Black-Scholes Greeks · DCF 가치평가 엔진</strong></summary>

#### ✅ 구축 내역
- .NET SDK 8.0 apt 설치 (`dotnet-sdk-8.0`).
- `pricer-fsharp/` F# ASP.NET Core 프로젝트 생성 (`dotnet new web -lang F#`).
- `MathHelper` 모듈: Abramowitz & Stegun 근사 `normCdf`, `normPdf` 구현.
- `BlackScholes` 모듈: d1/d2 계산 → Call/Put 가격, Δ/Γ/ν/Θ/ρ Greeks 전량 반환.
- `Dcf` 모듈: FCF 연도별 성장 PV + Terminal Value → 내재가치 · 안전마진.
- `RequestDelegate` 명시 캐스팅으로 F# `MapGet` 오버로드 해결.
- `dotnet build -c Release` 성공 (경고 3건, 에러 0).

#### 🔍 트러블슈팅
| 이슈 | 해결 |
|:---|:---|
| `MapGet` overload FS0041 | `fun (ctx: HttpContext)` → `RequestDelegate(fun ctx ->)` 명시 캐스팅 |
</details>

---

## 🛡️ 유지보수 가이드

1. **Python 환경**: 실행 전 반드시 `source venv/bin/activate` 활성화.
2. **Zig**: `cd core-zig && ~/.local/zig/zig build` → `zig-out/lib/libzigcore.so`.
3. **Kotlin Scheduler**: `bash scheduler-kotlin/run.sh` (OpenJDK 21 자동 참조).
4. **Julia Engine**: `~/.local/julia/bin/julia --threads auto engine-julia/server.jl`.
5. **R Engine**: `Rscript engine-r/run.R` (포트 `:8003`).
6. **F# Pricer**: `dotnet run --project pricer-fsharp` (포트 `:9001`).
7. **WASM 재빌드**: `~/.local/zig/zig build-lib wasm-zig/src/finance.zig -target wasm32-freestanding -O ReleaseFast --export=normCdf --export=bsCall --export=bsPut --export=bsDelta --export=bsGamma --export=varNormal --export=dcfValue -femit-bin=portal-svelte/static/finance.wasm`
8. **OCaml Engine**: `ocamlfind ocamlopt -package unix -linkpkg risk-ocaml/server.ml -o risk-ocaml/server && ./risk-ocaml/server` (포트 `:8004`).
9. **Crystal Gateway**: `crystal build --release gateway-crystal/server.cr -o gateway-crystal/server && ./gateway-crystal/server` (포트 `:9002`).
10. **Nim Analytics**: `export PATH=$HOME/.nimble/bin:$PATH && nim compile --opt:speed -o:analytics-nim/server analytics-nim/server.nim && ./analytics-nim/server` (포트 `:8005`).
11. **Elixir Hub**: Erlang/OTP 설치 후 `cd hub-elixir && mix deps.get && mix run --no-halt`.
9. **Git 관리**: `venv/`, `node_modules/`, Go 바이너리(`main`), `zig-out/`, `target/`, `pricer-fsharp/bin/`, `pricer-fsharp/obj/` 커밋 금지.
9. **기록 원칙**: 작업 완료 시 README 해당 섹션 최상단에 날짜별 로그 추가.

---

*"1류는 도구에 매몰되지 않고, 도구를 지배하여 가치를 창출한다."*
