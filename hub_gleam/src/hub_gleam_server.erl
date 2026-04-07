%% hub_gleam_server.erl — TCP HTTP server for Gleam pipeline engine
%% Calls hub_gleam Gleam module for financial computations
-module(hub_gleam_server).
-export([start/0]).

start() ->
    Port = 4001,
    {ok, LSock} = gen_tcp:listen(Port, [
        binary, {packet, raw}, {active, false}, {reuseaddr, true}
    ]),
    io:format("Gleam 1.15 pipeline engine listening on :~w~n", [Port]),
    accept_loop(LSock).

accept_loop(LSock) ->
    case gen_tcp:accept(LSock) of
        {ok, Sock} ->
            spawn(fun() -> handle_client(Sock) end),
            accept_loop(LSock);
        _ ->
            accept_loop(LSock)
    end.

handle_client(Sock) ->
    case gen_tcp:recv(Sock, 0, 5000) of
        {ok, Data} ->
            Req = binary_to_list(Data),
            {Path, Query} = parse_request(Req),
            Response = route(Path, Query),
            gen_tcp:send(Sock, Response),
            gen_tcp:close(Sock);
        _ ->
            gen_tcp:close(Sock)
    end.

parse_request(Req) ->
    Lines = string:split(Req, "\r\n"),
    case Lines of
        [FirstLine | _] ->
            Parts = string:split(FirstLine, " ", all),
            case Parts of
                [_, PathQuery | _] ->
                    case string:split(PathQuery, "?", leading) of
                        [Path, Query] -> {Path, Query};
                        [Path]        -> {Path, ""}
                    end;
                _ -> {"/", ""}
            end;
        _ -> {"/", ""}
    end.

route(Path, Query) ->
    {Body, Status} = case Path of
        "/health" ->
            B = <<"{\"status\":\"ok\",\"service\":\"gleam-pipeline\",\"version\":\"Gleam 1.15\"}">>,
            {B, 200};
        "/api/gleam/pipeline" ->
            Params = parse_query(Query),
            N     = get_int(Params, "n", 252),
            Mu    = get_float(Params, "mu", 0.08),
            Sigma = get_float(Params, "sigma", 0.20),
            Result = hub_gleam:pipeline_json(N, Mu, Sigma),
            {Result, 200};
        "/api/gleam/risk" ->
            Params = parse_query(Query),
            N     = get_int(Params, "n", 252),
            Mu    = get_float(Params, "mu", 0.08),
            Sigma = get_float(Params, "sigma", 0.20),
            Result = hub_gleam:risk_json(N, Mu, Sigma),
            {Result, 200};
        "/api/gleam/validate" ->
            Params = parse_query(Query),
            Service = get_str(Params, "service", "risk"),
            case Service of
                "risk" ->
                    Score = get_float(Params, "score", 500.0),
                    Grade = get_str(Params, "grade", "B"),
                    Result = hub_gleam:validate_risk_json(Score, Grade),
                    {Result, 200};
                "option" ->
                    Call  = get_float(Params, "call", 10.0),
                    Delta = get_float(Params, "delta", 0.5),
                    Result = hub_gleam:validate_option_json(Call, Delta),
                    {Result, 200};
                _ ->
                    Result = hub_gleam:validate_risk_json(500.0, "B"),
                    {Result, 200}
            end;
        "/api/gleam/contract" ->
            Result = hub_gleam:contract_json(),
            {Result, 200};
        _ ->
            {<<"{\"error\":\"not found\"}">>, 404}
    end,
    http_response(Status, Body).

http_response(Status, Body) ->
    StatusText = case Status of
        200 -> "OK";
        404 -> "Not Found";
        _   -> "Error"
    end,
    BodyBin = iolist_to_binary(Body),
    Len = byte_size(BodyBin),
    iolist_to_binary([
        "HTTP/1.1 ", integer_to_list(Status), " ", StatusText, "\r\n",
        "Content-Type: application/json; charset=utf-8\r\n",
        "Access-Control-Allow-Origin: *\r\n",
        "Content-Length: ", integer_to_list(Len), "\r\n",
        "Connection: close\r\n",
        "\r\n",
        BodyBin
    ]).

parse_query(Query) ->
    Pairs = string:split(list_to_binary(Query), <<"&">>, all),
    lists:filtermap(fun(Pair) ->
        case string:split(Pair, <<"=">>, leading) of
            [K, V] -> {true, {binary_to_list(K), binary_to_list(V)}};
            _      -> false
        end
    end, Pairs).

get_int(Params, Key, Default) ->
    case lists:keyfind(Key, 1, Params) of
        {_, V} ->
            case string:to_integer(V) of
                {N, _} when is_integer(N) -> N;
                _                         -> Default
            end;
        false -> Default
    end.

get_float(Params, Key, Default) ->
    case lists:keyfind(Key, 1, Params) of
        {_, V} ->
            try list_to_float(V)
            catch _:_ ->
                try float(list_to_integer(V))
                catch _:_ -> Default
                end
            end;
        false -> Default
    end.

get_str(Params, Key, Default) ->
    case lists:keyfind(Key, 1, Params) of
        {_, V} -> V;
        false  -> Default
    end.
