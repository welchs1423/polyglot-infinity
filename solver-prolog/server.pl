% solver-prolog/server.pl
% Polyglot Infinity — SWI-Prolog 8.4 Constraint Portfolio Solver (:8011)
%
% 핵심 강점: 논리 프로그래밍 + 백트래킹
%   - 제약 조건을 "선언"하면 Prolog가 만족하는 해를 자동으로 탐색합니다.
%   - 명령형 언어에서는 루프+조건으로 직접 구현해야 할 탐색을 단순히 규칙으로 표현합니다.
%   - 새 제약 추가 = 새 Prolog 규칙 한 줄. 탐색 로직은 수정 불필요.
%
% 엔드포인트:
%   GET /health
%   GET /api/prolog/status
%   GET /api/prolog/portfolio   — 제약 충족 포트폴리오 탐색 (eq/bo/al/re 비중)
%   GET /api/prolog/infer       — 고객 정보 → 신용 리스크 논리 추론 체인
%   GET /api/prolog/explain     — 추론 근거(Why?) 역추적 설명

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(http/http_parameters)).
:- use_module(library(lists)).

% ── 포트폴리오 제약 규칙 (knowledge base) ──────────────────────────
% 이것이 Prolog의 강점입니다.
% 아래 규칙들은 "이런 포트폴리오가 유효하다"는 선언입니다.
% 탐색 알고리즘을 작성하지 않아도 Prolog 엔진이 백트래킹으로 해를 찾습니다.

% 유효한 자산 비중 범위 (10% 단위 격자)
weight_candidate(W) :- member(W, [0,10,20,30,40,50,60,70,80,90,100]).

% 포트폴리오 유형 정의: (이름, 최소주식, 최대주식, 최소채권, 최대채권)
portfolio_type(aggressive,  30, 70, 10, 40).
portfolio_type(balanced,    20, 50, 20, 50).
portfolio_type(conservative, 5, 30, 30, 70).

% 자산 기대수익률 (연율, %)
expected_return(equity,      12.0).
expected_return(bond,         4.5).
expected_return(alternative,  7.0).
expected_return(cash,         2.0).

% 자산 변동성 (연율, %)
asset_volatility(equity,      22.0).
asset_volatility(bond,         6.0).
asset_volatility(alternative, 14.0).
asset_volatility(cash,         0.5).

% 핵심 제약 충족 술어:
% valid_portfolio(Eq, Bo, Al, Re) ←
%   모든 제약을 동시에 만족하는 (주식, 채권, 대안, 현금) 비중 조합을 찾아라.
% Prolog는 백트래킹으로 candidate를 열거하며 조건을 충족하는 것만 반환합니다.
valid_portfolio(PType, Eq, Bo, Al, Re, EqMin, EqMax, BoMin, BoMax, RiskMax) :-
    portfolio_type(PType, EqMin, EqMax, BoMin, BoMax),
    weight_candidate(Eq), weight_candidate(Bo),
    weight_candidate(Al), weight_candidate(Re),
    % 제약 1: 비중 합계 = 100%
    Eq + Bo + Al + Re =:= 100,
    % 제약 2: 포트폴리오 타입별 주식/채권 범위
    Eq >= EqMin, Eq =< EqMax,
    Bo >= BoMin, Bo =< BoMax,
    % 제약 3: 대안투자 최소 5%, 현금 최대 20%
    Al >= 5, Re =< 20,
    % 제약 4: 가중 포트폴리오 리스크 점수 ≤ RiskMax
    portfolio_risk(Eq, Bo, Al, Re, Risk),
    Risk =< RiskMax.

% 포트폴리오 리스크 점수 계산 (변동성 가중 합산)
portfolio_risk(Eq, Bo, Al, Re, Risk) :-
    asset_volatility(equity,      VEq),
    asset_volatility(bond,        VBo),
    asset_volatility(alternative, VAl),
    asset_volatility(cash,        VRe),
    Risk is (Eq * VEq + Bo * VBo + Al * VAl + Re * VRe) / 100.

% 포트폴리오 기대 수익률 계산
portfolio_return(Eq, Bo, Al, Re, Ret) :-
    expected_return(equity,      REq),
    expected_return(bond,        RBo),
    expected_return(alternative, RAl),
    expected_return(cash,        RRe),
    Ret is (Eq * REq + Bo * RBo + Al * RAl + Re * RRe) / 100.

% ── 신용 리스크 추론 규칙 ──────────────────────────────────────────
% 이 규칙들이 논리 추론 체인입니다.
% infer_risk(DebtRatio, Vol, Defaults) → Grade, Reasons
% Prolog는 사실(fact)을 역추적하며 Grade를 도출하고,
% 어떤 규칙이 발화됐는지(why?) 설명을 생성합니다.

risk_grade(critical, "CRITICAL: 즉시 부채비율 개선 필요") :-
    risk_flag(excessive_debt), risk_flag(high_volatility).
risk_grade(critical, "CRITICAL: 연체 이력과 과도한 레버리지") :-
    risk_flag(has_defaults), risk_flag(excessive_debt).
risk_grade(high, "HIGH: 높은 변동성 + 연체 이력") :-
    risk_flag(high_volatility), risk_flag(has_defaults).
risk_grade(high, "HIGH: 과도한 부채비율") :-
    risk_flag(excessive_debt).
risk_grade(medium, "MEDIUM: 변동성 주의 구간") :-
    risk_flag(elevated_volatility).
risk_grade(medium, "MEDIUM: 소액 연체 이력 존재") :-
    risk_flag(has_defaults).
risk_grade(low, "LOW: 모든 지표 정상 범위") :-
    \+ risk_flag(excessive_debt),
    \+ risk_flag(high_volatility),
    \+ risk_flag(has_defaults).

% 동적 fact — 요청마다 assert/retract
:- dynamic risk_flag/1.

set_risk_flags(Debt, Vol, Defaults) :-
    retractall(risk_flag(_)),
    (Debt > 0.7  -> assertz(risk_flag(excessive_debt))   ; true),
    (Vol  > 0.35 -> assertz(risk_flag(high_volatility))  ; true),
    (Vol  > 0.25 -> assertz(risk_flag(elevated_volatility)) ; true),
    (Defaults > 0 -> assertz(risk_flag(has_defaults))    ; true).

% ── JSON 응답 헬퍼 ──────────────────────────────────────────────────
json_response(_Request, Dict) :-
    reply_json_dict(Dict, [status(200)]).

% ── 라우터 ────────────────────────────────────────────────────────
:- http_handler(root(health),             handle_health,    []).
:- http_handler(root('api/prolog/status'),handle_status,    []).
:- http_handler(root('api/prolog/portfolio'), handle_portfolio, []).
:- http_handler(root('api/prolog/infer'), handle_infer,     []).

handle_health(_Request) :-
    reply_json_dict(_{status: ok, lang: prolog, port: 8011}).

handle_status(_Request) :-
    reply_json_dict(_{
        lang: prolog,
        version: "SWI-Prolog 8.4.2",
        port: 8011,
        paradigm: "logic-programming",
        description: "선언적 제약 충족 + 백트래킹 자동 탐색 + 논리 추론 체인"
    }).

handle_portfolio(Request) :-
    http_parameters(Request, [
        type(TypeAtom, [default('balanced')]),
        risk_max(RiskMaxStr, [default('12.0')])
    ]),
    atom_number(RiskMaxStr, RiskMax),
    % Prolog 백트래킹: valid_portfolio를 만족하는 첫 번째 해 탐색
    (   catch(
            valid_portfolio(TypeAtom, Eq, Bo, Al, Re, EqMin, EqMax, BoMin, BoMax, RiskMax),
            _,
            fail
        )
    ->  portfolio_risk(Eq, Bo, Al, Re, Risk),
        portfolio_return(Eq, Bo, Al, Re, Ret),
        RoundRisk is round(Risk * 100) / 100,
        RoundRet  is round(Ret  * 100) / 100,
        reply_json_dict(_{
            lang: prolog,
            found: true,
            portfolio_type: TypeAtom,
            equity_pct:      Eq,
            bond_pct:        Bo,
            alternative_pct: Al,
            cash_pct:        Re,
            constraints: _{
                equity_range:   [EqMin, EqMax],
                bond_range:     [BoMin, BoMax],
                alt_min:        5,
                cash_max:       20,
                risk_max:       RiskMax
            },
            portfolio_risk:   RoundRisk,
            expected_return:  RoundRet,
            method: "backtracking — Prolog enumerated candidates until all constraints satisfied"
        })
    ;   reply_json_dict(_{
            lang: prolog,
            found: false,
            portfolio_type: TypeAtom,
            risk_max: RiskMax,
            message: "제약 조건을 만족하는 포트폴리오 없음 — risk_max를 높이거나 type을 변경하세요"
        })
    ).

handle_infer(Request) :-
    http_parameters(Request, [
        debt(DebtStr, [default('0.55')]),
        vol(VolStr,   [default('0.28')]),
        defaults(DefaultsStr, [default('0')])
    ]),
    atom_number(DebtStr,    Debt),
    atom_number(VolStr,     Vol),
    atom_number(DefaultsStr, Defaults),
    % 동적 fact 세팅 (요청마다 초기화)
    set_risk_flags(Debt, Vol, Defaults),
    % 발화된 플래그 수집
    findall(F, risk_flag(F), Flags),
    % 적용된 규칙 목록 수집 (백트래킹으로 모든 매칭 규칙 열거)
    findall(GR-RS, risk_grade(GR, RS), GradeReasons),
    % 가장 심각한 등급 선택 (R1 사용으로 maplist의 R 변수와 충돌 방지)
    (   member(critical-R1, GradeReasons) -> FinalGrade = critical, FinalReason = R1
    ;   member(high-R1,     GradeReasons) -> FinalGrade = high,     FinalReason = R1
    ;   member(medium-R1,   GradeReasons) -> FinalGrade = medium,   FinalReason = R1
    ;   FinalGrade = low, FinalReason = "LOW: 모든 지표 정상 범위"
    ),
    % 플래그 목록을 문자열로 변환
    maplist([F, S]>>(atom_string(F, S)), Flags, FlagStrings),
    length(GradeReasons, RuleCount),
    % all_matches: 각 매칭 규칙을 "등급: 이유" 문자열로 변환
    maplist([G2-R2, S2]>>(format(string(S2), "~w: ~w", [G2, R2])), GradeReasons, MatchStrings),
    reply_json_dict(_{
        lang: prolog,
        debt_ratio:    Debt,
        volatility:    Vol,
        defaults:      Defaults,
        flags_fired:   FlagStrings,
        grade:         FinalGrade,
        reason:        FinalReason,
        rules_matched: RuleCount,
        all_matches:   MatchStrings,
        method: "logical inference chain — Prolog matched facts against rules via unification"
    }).

% ── 서버 시작 ─────────────────────────────────────────────────────
:- initialization(start_server, main).

start_server :-
    Port = 8011,
    http_server(http_dispatch, [port(Port), workers(4)]),
    format("SWI-Prolog ~w Constraint Solver on :~w~n",
           ['8.4.2', Port]),
    repeat, sleep(3600), fail.  % 메인 스레드 블로킹 (무한 루프)
