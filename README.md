# 🌈 Polyglot 5: Infinity Project
> **5대 핵심 언어(Svelte, Go, Python, Rust, C++) 정복을 위한 통합 포털**

본 프로젝트는 각 언어의 성능을 극대화하여 실시간 데이터 수집부터 AI 분석까지 구현하는 개발자의 성장 기록입니다.
현재 **Svelte 5(Frontend) ↔ Go(Backend) ↔ Python(Engine) ↔ PostgreSQL(Database)** 4대 요소가 유기적으로 연결되어 동작 중입니다.

---

## 🛠 현재 기술 스택 (Tech Stack)

### 🎨 Frontend
- **Framework**: SvelteKit (Svelte 5)
- **Runtime**: **Bun**
- **Style**: Tailwind CSS v4
- **Language**: TypeScript

### ⚙️ Backend & Engine
- **Go**: 메인 API 서버, 트래픽 중계 및 고성능 처리.
- **Python**: FastAPI 기반 데이터 분석 및 AI 엔진.
- **Rust (예정)**: 고성능 데이터 파이프라인.
- **C++ (예정)**: 저수준 최적화 모듈.

### 🗄️ Database & Infra
- **Primary**: **PostgreSQL**
- **Driver**: Go `lib/pq`, `go-redis/v9`
- **Environment**: WSL2 (Ubuntu), OrbStack

---

## 🏗️ 개발 로그 및 트러블슈팅 (Dev Log)

### 🗄️ Database (PostgreSQL)
> **역할:** 데이터 영구 저장, 시스템 로그 기록

<details open>
<summary><strong>📅 2026-02-16 (최신): DB 구축 및 스키마 설계</strong></summary>

#### ✅ 구축 내역
- WSL 환경 내 PostgreSQL 설치 및 서비스 구동.
- 전용 유저(`dev`) 및 데이터베이스(`polyglot_db`) 생성.
- 시스템 로그 저장을 위한 `system_logs` 테이블 스키마 설계.
</details>

<br>

### Go (Backend)
> **역할:** 프론트엔드와 엔진 사이의 중계(Proxy), 메인 비즈니스 로직


<details open>
<summary><strong>📅 2026-02-18 (최신): 로그 조회 API 개발</strong></summary>

#### ✅ 구축 내역
- **History API (`/api/history`)**: PostgreSQL에 저장된 로그를 최신순(DESC)으로 조회하여 반환.
- **DB 조회 로직**: `Query` 및 `Scan`을 활용한 데이터 매핑 구현.
</details>

<details>
<summary><strong>📅 2026-02-16 (최신): DB 연동 및 버전 업그레이드</strong></summary>

#### ✅ 구축 내역
- `lib/pq` 드라이버를 활용한 PostgreSQL 접속 구현 (`main.go`).
- API 요청 시 자동으로 DB에 로그를 적재(`INSERT`)하는 로직 추가.
- Go 최신 문법 지원을 위한 런타임 업그레이드 (1.18 → 1.23+).

#### 🔍 트러블슈팅 (Troubleshooting)
| 이슈 (Issue) | 원인 및 해결 (Solution) |
| :--- | :--- |
| **패키지 버전 에러** | `slices` 등 최신 패키지 미지원(Go 1.18) → PPA 추가하여 Go 1.23+로 업그레이드. |
| **VS Code 멈춤** | Go 버전 변경으로 인한 `gopls` 재설정 지연 → 언어 서버(Language Server) 리스타트. |
</details>

<details>
<summary><strong>📅 2026-02-15: Python 엔진 연동</strong></summary>

#### ✅ 구축 내역
- Python 서버(`localhost:8000`)로 HTTP 요청 전송 및 응답 수신 로직 구현.
- Svelte에게 최종 데이터를 병합하여 반환하는 구조체 설계.

#### 🔍 트러블슈팅 (Troubleshooting)
| 이슈 (Issue) | 원인 및 해결 (Solution) |
| :--- | :--- |
| **컴파일 에러 (Syntax)** | 구조체 마지막 필드 뒤 콤마(`,`) 누락 → Go 문법 준수하여 수정. |
</details>

<details>
<summary><strong>📅 2026-02-14: 초기 서버 구축</strong></summary>

#### ✅ 구축 내역
- `net/http` 기반 웹 서버 구동.
- CORS (Cross-Origin Resource Sharing) 정책 설정 완료.
</details>

<br>

### 🐍 Python (Engine)
> **역할:** 데이터 분석, AI 추론, Go 서버의 요청 처리

<details>
<summary><strong>📅 2026-02-15: 엔진 구축 및 환경 최적화</strong></summary>

#### ✅ 구축 내역
- FastAPI 서버 구축 (`main.py`) 및 JSON 응답 API 구현.
- 가상환경(`venv`) 구성 및 의존성 관리(`requirements.txt`).
- `.gitignore` 적용을 통한 저장소 경량화.

#### 🔍 트러블슈팅 (Troubleshooting)
| 이슈 (Issue) | 원인 및 해결 (Solution) |
| :--- | :--- |
| **`venv` 생성 실패** | `ensurepip` 누락 → `sudo apt install python3-venv` 설치. |
| **`pip`/`uvicorn` 미인식** | 시스템 패키지 부재 → `python3-pip` 설치 및 `python3 -m` 실행 방식 적용. |
| **`ImportError`** | `from fastapi import fastapi` 오타 → `FastAPI` (대문자)로 수정. |
| **Git 저장소 오염** | `venv` 폴더 업로드됨 → `git rm -r --cached venv/`로 인덱스 정화. |
</details>

<br>

### 🎨 Frontend (Svelte 5)
> **역할:** 사용자 인터페이스, 실시간 데이터 시각화

<details open>
<summary><strong>📅 2026-02-18 (최신): 시스템 로그 대시보드 구현</strong></summary>

#### ✅ 구축 내역
- **로그 시각화 UI**: 백엔드에서 받은 시스템 로그를 테이블 형태로 출력하는 컴포넌트 구현.
- **상태 동기화 로직**: `Status Check` → `Log Fetch`로 이어지는 비동기 연쇄 호출(Chaining) 처리.
</details>

<details>
<summary><strong>📅 2026-02-14: 프로젝트 스캐폴딩</strong></summary>

#### ✅ 구축 내역
- Bun 런타임 기반 SvelteKit 프로젝트 초기화.
- Tailwind CSS v4 디자인 시스템 통합.
- 백엔드(Go) 통신을 위한 Fetch 로직 구현.
</details>

### ⚡ Redis (Cache)
> **역할:** 데이터 캐싱을 통한 엔진 부하 감소 및 응답 속도 최적화

<details open>
<summary><strong>📅 2026-02-20 (최신): Redis 캐싱 레이어 도입</strong></summary>

#### ✅ 구축 내역
- **Cache-Aside 패턴**: 요청 시 Redis를 우선 조회(Cache Hit)하고, 데이터가 없을 경우에만 Python 엔진을 호출(Cache Miss)하는 로직 구현.
- **TTL(Time To Live) 설정**: 캐시 데이터의 유효 시간을 10초로 설정하여 데이터 정합성 유지.
- **성능 개선**: 캐시 적중 시 엔진 호출 프로세스를 생략하여 즉각적인 응답 반환 확인.

#### 🔍 트러블슈팅 (Troubleshooting)
| 이슈 (Issue) | 원인 및 해결 (Solution) |
| :--- | :--- |
| **Panic (Nil Pointer)** | Redis 클라이언트(`rdb`) 초기화 누락 -> `NewClient` 코드 추가로 해결. |
| **Key 정합성** | JSON 필드명 오타(`anlysis`) -> `analysis`로 교정하여 프론트엔드 연동 정상화. |
</details>

---

## 🚀 마일스톤 (Milestones)
- [x] [2026-02-20] **Redis 캐싱 레이어 도입 및 성능 최적화 성공**
- [x] [2026-02-16] **PostgreSQL 데이터 스키마 설계 및 연동 완료**
- [x] [2026-02-15] **Svelte ↔ Go ↔ Python 3단 대통합 성공**
- [x] [2026-02-15] Python 분석 엔진 구축 및 가상환경 설정
- [x] [2026-02-14] Bun & SvelteKit 프로젝트 초기화 성공
- [x] [2026-02-14] Tailwind CSS v4 디자인 시스템 적용
- [x] [2026-02-14] Go 기반 API 서버 구축 (CORS 해결)
- [ ] Docker 컨테이너 환경 구축

---

## 🛡️ 유지보수 가이드
1. **Python 환경**: 실행 전 반드시 `source venv/bin/activate` 활성화.
2. **Git 관리**: `venv/`, `node_modules/`, `main` (Go 바이너리) 등은 절대 커밋하지 않음. 실수로 추가 시 즉시 `git rm --cached` 수행.
3. **기록 원칙**: 작업 완료 시 README의 해당 언어 섹션 최상단에 날짜별 로그를 추가한다.

---
*“1류는 도구에 매몰되지 않고, 도구를 지배하여 가치를 창출한다.”*