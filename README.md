# 🌈 Polyglot Infinity

> **10개 언어/런타임**(Svelte · Go · Python · Rust · C++ · **Lua · Zig · Kotlin · Elixir · Julia**)과 2개 DB(PostgreSQL · Redis)가 유기적으로 연결된
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

---

## 🛡️ 유지보수 가이드

1. **Python 환경**: 실행 전 반드시 `source venv/bin/activate` 활성화.
2. **Zig**: `cd core-zig && ~/.local/zig/zig build` → `zig-out/lib/libzigcore.so`.
3. **Kotlin Scheduler**: `bash scheduler-kotlin/run.sh` (OpenJDK 21 자동 참조).
4. **Julia Engine**: `~/.local/julia/bin/julia --threads auto engine-julia/server.jl`.
5. **Elixir Hub**: Erlang/OTP 설치 후 `cd hub-elixir && mix deps.get && mix run --no-halt`.
6. **Git 관리**: `venv/`, `node_modules/`, Go 바이너리(`main`), `zig-out/`, `target/` 커밋 금지.
7. **기록 원칙**: 작업 완료 시 README 해당 섹션 최상단에 날짜별 로그 추가.

---

*"1류는 도구에 매몰되지 않고, 도구를 지배하여 가치를 창출한다."*
