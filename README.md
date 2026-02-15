# 🚀 Polyglot Infinity Portal

다양한 프로그래밍 언어와 기술 스택을 통합하여 구축하는 하이 퍼포먼스 포털 프로젝트입니다.

## 🛠 Tech Stack
- **Frontend**: Svelte 5, Tailwind CSS v4
- **Runtime**: Bun
- **Backend**: Go (The Hunter)
- **Target**: Python (The Brain), PostgreSQL (The Memory)

---

## 📝 Development History & Issue Log

### 📅 2026-02-14: 프로젝트 기초 및 디자인 시스템 구축
- **구현 기능**
    - Bun 기반 SvelteKit 프로젝트 초기화.
    - Tailwind CSS v4 디자인 시스템 도입 및 다크 모드 UI 구현.
- **이슈 (걸림돌)**
    - `bunx tailwindcss init -p` 실행 시 실행 파일을 찾지 못하는 에러 발생.
    - Tailwind 클래스가 화면에 적용되지 않고 기본 텍스트만 출력됨.
- **원인 분석**
    - Tailwind v4는 기존 v3와 달리 별도의 CLI 초기화(`init`) 방식보다 Vite 플러그인 기반 설정을 지향함.
    - Svelte v5와 Tailwind v4 조합에서 Vite 플러그인(`@tailwindcss/vite`) 연결이 누락됨.
- **해결 방법**
    - `vite.config.ts`에 `@tailwindcss/vite` 플러그인을 수동으로 추가.
    - `app.css`에서 `@import "tailwindcss";` 한 줄로 설정을 간소화하여 최신 방식 적용.

### 📅 2026-02-15: Go 백엔드 구축 및 첫 이종 언어 연동
- **구현 기능**
    - Go(The Hunter)를 이용한 기초 HTTP API 서버 구축 (`/api/status`).
    - Svelte 프론트엔드에서 버튼 클릭 시 Go 서버의 데이터를 가져오는 `fetch` 로직 구현.
- **이슈 (걸림돌)**
    - Svelte에서 버튼 클릭 시 `404 Not Found` 에러 발생.
    - 터미널 로그에 `GET /http://localhost:8080/...`와 같이 비정상적인 경로 출력.
- **원인 분석**
    - `fetch` 함수 내부의 URL 작성 시 주소 앞에 실수로 슬래시(`/`)가 포함됨.
    - 브라우저가 이를 절대 경로 URL이 아닌 현재 도메인의 하위 리소스 경로로 인식하여 발생한 오타 문제.
- **해결 방법**
    - `fetch` 주소에서 불필요한 슬래시를 제거하고 `http://localhost:8080/api/status`로 정확히 수정.
    - Go 서버에 CORS 헤더(`Access-Control-Allow-Origin: *`) 설정을 추가하여 브라우저 보안 정책 문제 해결.

### 📅 2026-02-15: Python 환경 구축 및 가상환경 이슈 해결
- **구현 기능**
    - Python 가상환경(venv) 설정 및 FastAPI 기반 'The Brain' 엔진 기초 구축.
- **이슈 (걸림돌)**
    - `python3 -m venv venv` 실행 시 `ensurepip` 부재로 인해 가상환경 생성 실패.
- **원인 분석**
    - Ubuntu/WSL 환경에서는 `python3-venv` 패키지가 기본 파이썬 설치와 분리되어 있어 발생한 문제.
- **해결 방법**
    - `sudo apt update && sudo apt install python3-venv` 명령어로 시스템 패키지 설치 후 가상환경 재생성 성공.

### 📅 2026-02-15: Svelte-Go-Python 3단 대통합 및 이슈 해결
- **구현 기능**
    - Python(FastAPI) 엔진 구축 및 Go 서버와의 REST API 연동.
    - Svelte 프론트엔드에서 Go를 거쳐 Python의 분석 데이터까지 수신하는 Full-Stack 체인 완성.
- **이슈 및 해결 (Troubleshooting)**
    - **Issue 1**: Python 가상환경(`venv`) 패키지 미설치로 인한 `uvicorn` 실행 불가.
        - *해결*: `sudo apt install python3-pip` 및 `venv` 내 `pip install` 재수행.
    - **Issue 2**: `uvicorn` 실행 시 `Attribute "app" not found` 및 `ImportError`.
        - *원인*: `main.py` 내 객체명 불일치 및 `fastapi` 대소문자 오타.
        - *해결*: `from fastapi import FastAPI`로 대소문자 교정 및 `app` 변수 선언 확인.
    - **Issue 3**: Go 서버 컴파일 에러 (`syntax error: unexpected newline`).
        - *원인*: 응답 구조체 마지막 필드 뒤 콤마(`,`) 누락.
        - *해결*: Go 문법 규격에 맞게 콤마 추가.
    - **Issue 4**: GitHub에 수천 개의 `venv` 파일 노출.
        - *해결*: `.gitignore` 설정 및 `git rm --cached`를 통한 원격 저장소 정리.

---

## 🚀 마일스톤
- [x] Bun & SvelteKit 프로젝트 초기화
- [x] Tailwind CSS v4 디자인 시스템 적용 완료 ✨
- [x] Go API 서버 구축 및 프론트엔드 연동 성공 🏹
- [x] Python 환경 구축 및 가상환경 설정 완료 🐍
- [ ] PostgreSQL(The Memory) 데이터베이스 설계 및 연결