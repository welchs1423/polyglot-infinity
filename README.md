# 🚀 Polyglot Infinity Portal

다양한 프로그래밍 언어와 기술 스택을 통합하여 구축하는 하이 퍼포먼스 포털 프로젝트입니다.
**Svelte 5(Front) + Go(Hunter) + Python(Brain)** 시스템이 유기적으로 연결되어 동작합니다.

---

## 🏗️ 개발 마일스톤 (Development Milestone)

### 📅 2026-02-15 (최신)
<details open>
<summary><strong>Python(The Brain) 엔진 구축 및 3단 대통합 성공</strong></summary>

#### ✅ 구축 내역
- **Python 기반 'The Brain' 엔진 완성**: FastAPI를 활용한 분석 API 서버 구축.
- **가상환경(venv) 최적화**: `requirements.txt` 생성 및 불필요한 바이너리 제거 성공.
- **Svelte-Go-Python 연동**: Go 서버를 중계기로 활용하여 프론트엔드까지 데이터 도달 확인.

#### 🔍 트러블슈팅 (Troubleshooting)
| 이슈 내용 | 원인 분석 및 해결 방안 |
| :--- | :--- |
| **`venv` 생성 및 pip 오류** | 시스템 패키지 부재 -> `python3-venv`, `python3-pip` 설치로 해결. |
| **`ImportError` (FastAPI)** | 대소문자 오타 및 `app` 변수 선언 누락 -> 코드 교정 후 정상 구동. |
| **`venv` 폴더 유입** | 깃허브에 수천 개 파일 업로드 -> `.gitignore` 설정 및 `git rm --cached`로 정화. |
| **Go 문법 에러** | 응답 구조체 마지막 필드 콤마(`,`) 누락 -> Go 규격에 맞게 수정. |
</details>

### 📅 2026-02-14
<details>
<summary><strong>Go(The Hunter) 서버 연동 및 README 관리 규정 수립</strong></summary>

#### ✅ 구축 내역
- **Go(The Hunter) 백엔드 구축**: 프론트엔드 요청을 처리할 API 서버 기본 골격 완성.
- **문서화 원칙 수립**: "최신 날짜가 항상 상단에 오도록 기록"하는 README 관리 규칙 적용.

#### 🔍 트러블슈팅
| 이슈 내용 | 원인 분석 및 해결 방안 |
| :--- | :--- |
| **README 날짜 정렬** | 과거 내역이 위에 위치 -> **최신 날짜 우선 정렬**로 구조 변경. |
</details>

### 📅 2026-02-12
<details>
<summary><strong>Git 워크플로우 강화</strong></summary>

#### ✅ 구축 내역
- **변경 감지 자동화**: 코드 푸시 시 `README.md` 수정 사항을 반드시 체크하도록 워크플로우 설정.
</details>

<details>

#### ✅ 구축 내역
- **Bun + SvelteKit** 프로젝트 초기화.
- **Tailwind CSS v4** 기반 디자인 시스템 및 UI 컴포넌트 설계.
- **레시피 작성 규정**: 재료 목록과 양을 명시하는 표준 레시피 형식 수립.
- **언어 설정**: 모든 답변 및 가이드를 한국어로 제공하도록 설정.
</details>

---

## 🛠️ 기술 스택 (Tech Stack)

| 구분 | 기술 | 역할 |
| :--- | :--- | :--- |
| **Frontend** | Svelte 5, Tailwind CSS v4 | 인터페이스 및 시각화 |
| **Backend** | Go (The Hunter) | 비즈니스 로직 및 중계 |
| **Engine** | Python (The Brain) | 데이터 분석 및 AI 로직 |

---

## 🛡️ 유지보수 가이드
- **파일 관리**: `venv/`, `node_modules/`는 절대 커밋 금지. 추가 시 `git rm --cached` 실행 필수.
- **기록**: 새로운 작업 완료 후 README 상단에 날짜별 접이식 블록을 추가할 것.