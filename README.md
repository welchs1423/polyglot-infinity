# 🌈 Polyglot Infinity

> 5개 언어(Svelte · Go · Python · Rust · C++)와 2개 DB(PostgreSQL · Redis)가 유기적으로 연결된
> **실시간 다중 통화 마이크로 대출 리스크 분석 플랫폼**

---

## 📐 시스템 아키텍처

```
[Svelte 5 · :5173]
       │ fetch
       ▼
[Go API Hub · :8080] ──────────────────────────────┐
       │                                            │
       ├─ Cache Hit → [Redis · :6379]               │
       │                                            │
       ├─ Cache Miss → [Python FastAPI · :8000]     │
       │                    └─ C++ FFI (libcore.so) │
       │                                            │
       └─ Pipeline → [Rust Axum · :8081] ───────────┘
                          └─ [PostgreSQL · :5433]
```

| 서비스 | 포트 | 역할 |
|:---|:---:|:---|
| Svelte 5 (SvelteKit + Bun) | 5173 | UI · 실시간 대시보드 |
| Go (`net/http`) | 8080 | API Hub · Redis 캐싱 · 프록시 |
| Python (FastAPI) | 8000 | 다중 환율 수집 · C++ FFI 리스크 연산 |
| Rust (Axum + tokio) | 8081 | 고성능 벌크 인서트 파이프라인 |
| PostgreSQL | 5432 / 5433 | 시스템 로그 · 리스크 데이터 영구 저장 |
| Redis | 6379 | Python 분석 결과 10초 캐싱 |

---

## 🛠 기술 스택

| 영역 | 기술 |
|:---|:---|
| **Frontend** | SvelteKit (Svelte 5), Bun, Tailwind CSS v4, TypeScript |
| **API Gateway** | Go 1.23+, `net/http`, `lib/pq`, `go-redis/v9` |
| **Risk Engine** | Python 3, FastAPI, `ctypes` (C++ FFI) |
| **Core** | C++ (`-O3`), `libcore.so` 공유 라이브러리 |
| **Pipeline** | Rust, Axum, tokio, sqlx |
| **Infra** | PostgreSQL, Redis, WSL2 (Ubuntu) |

---

## 🔌 API 명세

### Go `:8080`

| Method | Endpoint | 설명 |
|:---|:---|:---|
| `GET` | `/api/status` | 전체 시스템 상태 · Python 분석 결과 · Rust 상태 집계 |
| `GET` | `/api/history` | `system_logs` 최신 10건 조회 |
| `POST` | `/api/pipeline/trigger` | Rust 벌크 인서트 트리거 · 결과 DB 기록 |

### Python `:8000`

| Method | Endpoint | 설명 |
|:---|:---|:---|
| `GET` | `/api/analyze` | KRW·JPY·EUR·CNY 환율 수집 → C++ 복합 리스크 계산 |

### Rust `:8081`

| Method | Endpoint | 설명 |
|:---|:---|:---|
| `GET` | `/api/rust/status` | 파이프라인 상태 · `risk_logs` 총 레코드 수 반환 |
| `POST` | `/api/bulk-insert` | 10,000건 리스크 데이터 트랜잭션 일괄 적재 |

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
```

---

## 🚀 마일스톤 (최신순)

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

## 🛡️ 유지보수 가이드

1. **Python 환경**: 실행 전 반드시 `source venv/bin/activate` 활성화.
2. **Git 관리**: `venv/`, `node_modules/`, Go 바이너리(`main`)는 커밋 금지. 실수 추가 시 `git rm --cached` 즉시 수행.
3. **기록 원칙**: 작업 완료 시 README 해당 섹션 최상단에 날짜별 로그 추가.

---

*"1류는 도구에 매몰되지 않고, 도구를 지배하여 가치를 창출한다."*
