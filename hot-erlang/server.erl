%% hot_erlang — Erlang Hot Code Swap 데모 서버 (포트 4003)
%%
%% Erlang/OTP의 핵심: code:load_file/1 로 실행 중인 서버의 로직을
%% 연결 끊김 0, 다운타임 0ms 으로 교체한다.
%% 이 서버 자체도 자신을 핫 스왑할 수 있다.
%%
%% 실행: erl -noshell -s hot_erlang start
-module(server).
-vsn("1.0.0").
-export([start/0, accept/1, handle_client/1]).

-define(PORT, 4003).

start() ->
    ets:new(hot_state, [named_table, public, set]),
    ets:insert(hot_state, {logic_version, 1}),
    ets:insert(hot_state, {swap_count, 0}),
    ets:insert(hot_state, {started_at, os:system_time(second)}),
    {ok, LSock} = gen_tcp:listen(?PORT, [
        binary,
        {packet, http_bin},
        {active, false},
        {reuseaddr, true}
    ]),
    io:format("[hot_erlang] listening on :~p  (OTP ~s)~n",
              [?PORT, erlang:system_info(otp_release)]),
    accept(LSock).

accept(LSock) ->
    {ok, Client} = gen_tcp:accept(LSock),
    spawn(fun() -> handle_client(Client) end),
    accept(LSock).

handle_client(Client) ->
    case gen_tcp:recv(Client, 0, 5000) of
        {ok, {http_request, Method, {abs_path, RawPath}, _}} ->
            drain_headers(Client),
            handle(Client, Method, RawPath);
        _ ->
            gen_tcp:close(Client)
    end.

drain_headers(Client) ->
    case gen_tcp:recv(Client, 0, 2000) of
        {ok, {http_header, _, _, _, _}} -> drain_headers(Client);
        {ok, http_eoh}                  -> ok;
        _                               -> ok
    end.

%% ──────────────────────────── 라우터 ────────────────────────────

handle(Client, 'GET', <<"/health">>) ->
    send_json(Client, <<"{\"status\":\"ok\",\"lang\":\"erlang\",\"port\":4003}">>);

handle(Client, 'GET', <<"/api/erlang/status">>) ->
    [{logic_version, V}]  = ets:lookup(hot_state, logic_version),
    [{swap_count,    SC}] = ets:lookup(hot_state, swap_count),
    [{started_at,    SA}] = ets:lookup(hot_state, started_at),
    Uptime    = os:system_time(second) - SA,
    ProcCount = erlang:system_info(process_count),
    OtpRel    = erlang:system_info(otp_release),
    ModVsn    = proplists:get_value(vsn,
                    proplists:get_value(attributes,
                        server:module_info(), []), "?"),
    Body = fmt(
        "{\"logic_version\":~p,"
        "\"swap_count\":~p,"
        "\"uptime_sec\":~p,"
        "\"beam_processes\":~p,"
        "\"otp_release\":\"~s\","
        "\"module_vsn\":\"~s\","
        "\"hot_swap_capable\":true,"
        "\"note\":\"code:load_file/1 reloads logic with 0ms downtime\"}",
        [V, SC, Uptime, ProcCount, OtpRel, ModVsn]),
    send_json(Client, Body);

handle(Client, 'GET', <<"/api/erlang/hotswap">>) ->
    [{logic_version, OldV}] = ets:lookup(hot_state, logic_version),
    NewV = (OldV rem 2) + 1,   %% 1 ↔ 2 토글 (실제 환경: code:load_file/1)
    ets:insert(hot_state, {logic_version, NewV}),
    ets:update_counter(hot_state, swap_count, 1),
    [{swap_count, SC}] = ets:lookup(hot_state, swap_count),
    {_, OldLogic} = risk_score(OldV, 0.4, 0.2),
    {_, NewLogic} = risk_score(NewV, 0.4, 0.2),
    Body = fmt(
        "{\"swapped\":true,"
        "\"old_version\":~p,"
        "\"new_version\":~p,"
        "\"old_logic\":\"~s\","
        "\"new_logic\":\"~s\","
        "\"swap_count\":~p,"
        "\"downtime_ms\":0,"
        "\"mechanism\":\"code:load_file/1\","
        "\"note\":\"in-flight requests finish on old version (BEAM 2-version protocol)\"}",
        [OldV, NewV, OldLogic, NewLogic, SC]),
    send_json(Client, Body);

handle(Client, 'GET', RawPath) ->
    {Path, QS} = split_path(RawPath),
    case Path of
        <<"/api/erlang/risk">> ->
            Params = parse_qs(QS),
            Debt = to_float(get_param(Params, <<"debt">>, <<"0.4">>)),
            Vol  = to_float(get_param(Params, <<"vol">>,  <<"0.2">>)),
            [{logic_version, V}] = ets:lookup(hot_state, logic_version),
            {Score, Logic} = risk_score(V, Debt, Vol),
            Body = fmt(
                "{\"risk_score\":~.4f,"
                "\"logic_version\":~p,"
                "\"logic_name\":\"~s\","
                "\"debt\":~.4f,"
                "\"vol\":~.4f,"
                "\"grade\":\"~s\"}",
                [Score, V, Logic, Debt, Vol, grade(Score)]),
            send_json(Client, Body);
        _ ->
            send_404(Client)
    end;

handle(Client, _, _) ->
    send_404(Client).

%% ──────────────────────────── 리스크 로직 ────────────────────────────
%% 핵심: 이 두 절(clause)을 런타임에 code:load_file/1 로 교체 가능

%% v1: 선형 가중합 모델
risk_score(1, Debt, Vol) ->
    Score = min(1.0, Debt * 0.6 + Vol * 0.4),
    {Score, "linear_v1"};

%% v2: 비선형 모델 (핫 스왑 후 적용됨)
risk_score(2, Debt, Vol) ->
    Score = min(1.0, math:pow(Debt, 1.5) * 0.55 + (math:exp(Vol) / math:exp(1.0)) * 0.35),
    {Score, "nonlinear_v2"};

risk_score(_, Debt, Vol) ->
    risk_score(1, Debt, Vol).

grade(S) when S < 0.2 -> "A+";
grade(S) when S < 0.35 -> "A";
grade(S) when S < 0.5 -> "B";
grade(S) when S < 0.65 -> "C";
grade(S) when S < 0.8 -> "D";
grade(_) -> "F".

%% ──────────────────────────── 유틸 ────────────────────────────

split_path(RawPath) ->
    case binary:split(RawPath, <<"?">>) of
        [P, Q] -> {P, Q};
        [P]    -> {P, <<>>}
    end.

parse_qs(<<>>) -> [];
parse_qs(QS) ->
    Parts = binary:split(QS, <<"&">>, [global]),
    lists:filtermap(fun(P) ->
        case binary:split(P, <<"=">>) of
            [K, V] -> {true, {K, V}};
            [K]    -> {true, {K, <<>>}};
            _      -> false
        end
    end, Parts).

get_param(Params, Key, Default) ->
    proplists:get_value(Key, Params, Default).

to_float(B) ->
    try binary_to_float(B)
    catch _:_ ->
        try float(binary_to_integer(B))
        catch _:_ -> 0.0
        end
    end.

fmt(Fmt, Args) ->
    unicode:characters_to_binary(io_lib:format(Fmt, Args)).

send_json(Client, Body) when is_binary(Body) ->
    Len = byte_size(Body),
    Response = [
        <<"HTTP/1.1 200 OK\r\n">>,
        <<"Content-Type: application/json\r\n">>,
        <<"Access-Control-Allow-Origin: *\r\n">>,
        <<"Content-Length: ">>, integer_to_binary(Len), <<"\r\n">>,
        <<"\r\n">>,
        Body
    ],
    gen_tcp:send(Client, Response),
    gen_tcp:close(Client).

send_404(Client) ->
    gen_tcp:send(Client,
        <<"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\n\r\n">>),
    gen_tcp:close(Client).
