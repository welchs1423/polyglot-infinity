(* risk-ocaml server.ml
   OCaml Risk and Credit Rule Engine
   Port: 8004
   Endpoints:
     GET /health
     GET /api/ocaml/risk          rule-based risk level
     GET /api/ocaml/score         logistic credit score
     GET /api/ocaml/portfolio     4-asset portfolio VaR
     GET /api/ocaml/loan          loan approval decision via pattern matching
     GET /api/ocaml/margincall    margin call status via pattern matching
*)

(* ── Portfolio risk ──────────────────────────────────────────── *)

(* 4-asset equal-weight portfolio VaR under normal distribution.
   corr_flat: 4x4 correlation matrix in row-major order. *)
let portfolio_risk ~vols ~weights ~corr_flat =
  let n       = Array.length vols in
  let port_var = ref 0.0 in
  for i = 0 to n - 1 do
    for j = 0 to n - 1 do
      let cov_ij = vols.(i) *. vols.(j) *. corr_flat.(i * n + j) in
      port_var := !port_var +. weights.(i) *. weights.(j) *. cov_ij
    done
  done;
  let port_vol = sqrt !port_var in
  let ann_vol  = port_vol *. sqrt 252.0 in
  let var_95   = 1.6449 *. port_vol in
  let cvar_95  = port_vol *. (exp (-. 1.6449 *. 1.6449 /. 2.0))
                              /. (0.05 *. sqrt (2.0 *. Float.pi)) in
  (ann_vol, var_95, cvar_95, !port_var)

let assets       = [| "KRW"; "JPY"; "EUR"; "CNY" |]
let default_vols = [| 0.012; 0.008; 0.007; 0.005 |]
let default_corr = [|
  1.00; 0.35; 0.20; 0.45;
  0.35; 1.00; 0.30; 0.25;
  0.20; 0.30; 1.00; 0.15;
  0.45; 0.25; 0.15; 1.00;
|]

(* ── Risk level ──────────────────────────────────────────────── *)

type risk_level = Low | Medium | High | Critical

let string_of_risk = function
  | Low      -> "LOW"
  | Medium   -> "MEDIUM"
  | High     -> "HIGH"
  | Critical -> "CRITICAL"

(* Rule-based scoring: accumulate penalty points, then classify. *)
let evaluate_risk ~debt_ratio ~volatility ~leverage ~credit_score =
  let score = ref 0 in
  (if      debt_ratio   > 0.80 then score := !score + 40
   else if debt_ratio   > 0.60 then score := !score + 20
   else if debt_ratio   > 0.40 then score := !score + 10);
  (if      volatility   > 0.35 then score := !score + 30
   else if volatility   > 0.20 then score := !score + 15
   else if volatility   > 0.10 then score := !score + 5);
  (if      leverage     > 5.0  then score := !score + 20
   else if leverage     > 3.0  then score := !score + 10
   else if leverage     > 2.0  then score := !score + 5);
  (if      credit_score < 600  then score := !score + 20
   else if credit_score < 700  then score := !score + 10
   else if credit_score < 750  then score := !score + 5);
  let level =
    if      !score >= 70 then Critical
    else if !score >= 45 then High
    else if !score >= 20 then Medium
    else                      Low
  in
  (!score, level)

(* ── Credit scoring ──────────────────────────────────────────── *)

(* Logistic function maps real line to (0, 1). *)
let logistic x = 1.0 /. (1.0 +. exp (-. x))

(* Linear predictor z uses debt-to-income ratio, history length,
   and missed payment count as features. *)
let credit_score ~income ~debt ~history_years ~missed_payments =
  let income_f  = float_of_int income in
  let debt_f    = float_of_int debt in
  let history_f = float_of_int history_years in
  let missed_f  = float_of_int missed_payments in
  let dti       = if income_f > 0.0 then debt_f /. income_f else 1.0 in
  let z         = 2.5
               -. 3.5 *. dti
               +. 0.08 *. history_f
               -. 0.6  *. missed_f in
  let prob_good = logistic z in
  let score     = int_of_float (300.0 +. 550.0 *. prob_good) in
  let grade =
    if      score >= 800 then "A+"
    else if score >= 750 then "A"
    else if score >= 700 then "B+"
    else if score >= 650 then "B"
    else if score >= 600 then "C"
    else                      "D"
  in
  (score, grade, prob_good)

(* ── Loan decision (pattern matching) ───────────────────────── *)

(* Applicant record groups all underwriting inputs in one place.
   Pattern matching on this record allows exhaustive, readable
   classification without nested if-else chains. *)

type applicant = {
  credit_score_i  : int;
  debt_ratio      : float;
  collateral_ratio: float;
  leverage        : float;
  income          : int;
  missed_payments : int;
}

type loan_decision =
  | Approved
  | ConditionalApproval of string
  | Rejected            of string

(* Patterns ordered from most to least permissive.
   Guard clauses enforce numeric thresholds that cannot be
   expressed as constructor patterns alone. *)
let evaluate_loan ap =
  match ap with
  | { credit_score_i; debt_ratio; missed_payments; _ }
    when credit_score_i >= 750
      && debt_ratio      <  0.40
      && missed_payments =  0 ->
    Approved

  | { credit_score_i; debt_ratio; missed_payments; collateral_ratio; _ }
    when credit_score_i >= 700
      && debt_ratio      <  0.60
      && missed_payments <= 1
      && collateral_ratio >= 0.30 ->
    ConditionalApproval "interest rate surcharge 0.5 pct"

  | { credit_score_i; debt_ratio; collateral_ratio; _ }
    when credit_score_i >= 650
      && debt_ratio      <  0.70
      && collateral_ratio >= 0.50 ->
    ConditionalApproval "requires guarantor and quarterly review"

  | { credit_score_i; _ }
    when credit_score_i < 600 ->
    Rejected "credit score below minimum threshold 600"

  | { debt_ratio; _ }
    when debt_ratio >= 0.80 ->
    Rejected "debt ratio exceeds hard limit 0.80"

  | _ ->
    Rejected "profile does not meet any approval criteria"

let string_of_loan_decision = function
  | Approved                      -> "APPROVED"
  | ConditionalApproval _         -> "CONDITIONAL"
  | Rejected _                    -> "REJECTED"

let reason_of_loan_decision = function
  | Approved                      -> "all underwriting criteria satisfied"
  | ConditionalApproval condition -> condition
  | Rejected reason               -> reason

(* ── Margin call status (pattern matching) ───────────────────── *)

(* Margin status represents a 4-level escalation ladder used in
   prime brokerage and futures clearing.
   Thresholds follow Basel III Annex 4 indicative values. *)

type margin_status =
  | Safe
  | MarginWarning
  | MarginCall
  | ForcedLiquidation

let string_of_margin = function
  | Safe               -> "SAFE"
  | MarginWarning      -> "WARNING"
  | MarginCall         -> "MARGIN_CALL"
  | ForcedLiquidation  -> "FORCED_LIQUIDATION"

let margin_action = function
  | Safe               -> "no action required"
  | MarginWarning      -> "notify client, monitor intraday"
  | MarginCall         -> "issue margin call notice, T+1 cure"
  | ForcedLiquidation  -> "liquidate positions to restore maintenance margin"

(* Leverage and collateral ratio determine margin status.
   collateral_ratio = free collateral / total exposure. *)
let evaluate_margin ap =
  match ap with
  | { leverage; collateral_ratio; _ }
    when leverage > 8.0 || collateral_ratio < 0.10 ->
    ForcedLiquidation

  | { leverage; collateral_ratio; _ }
    when leverage > 5.0 || collateral_ratio < 0.20 ->
    MarginCall

  | { leverage; collateral_ratio; _ }
    when leverage > 3.0 || collateral_ratio < 0.30 ->
    MarginWarning

  | _ ->
    Safe

(* ── JSON helpers ────────────────────────────────────────────── *)

let json_string s =
  let buf = Buffer.create (String.length s + 2) in
  Buffer.add_char buf '"';
  String.iter (function
    | '"'  -> Buffer.add_string buf "\\\""
    | '\\' -> Buffer.add_string buf "\\\\"
    | '\n' -> Buffer.add_string buf "\\n"
    | c    -> Buffer.add_char   buf c
  ) s;
  Buffer.add_char buf '"';
  Buffer.contents buf

let json_kv_s k v = Printf.sprintf "%s:%s"   (json_string k) (json_string v)
let json_kv_f k v = Printf.sprintf "%s:%.4f" (json_string k) v
let json_kv_i k v = Printf.sprintf "%s:%d"   (json_string k) v

(* ── HTTP helpers ────────────────────────────────────────────── *)

let parse_query qs =
  let pairs = String.split_on_char '&' qs in
  List.filter_map (fun pair ->
    match String.split_on_char '=' pair with
    | [k; v] -> Some (k, v)
    | _       -> None
  ) pairs

let get_param params key default =
  match List.assoc_opt key params with
  | Some v -> v
  | None   -> default

let get_float params key default =
  try float_of_string (get_param params key (string_of_float default))
  with _ -> default

let get_int params key default =
  try int_of_string (get_param params key (string_of_int default))
  with _ -> default

let http_200 body =
  Printf.sprintf
    "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n\
     Access-Control-Allow-Origin: *\r\n\
     Content-Length: %d\r\nConnection: close\r\n\r\n%s"
    (String.length body) body

let http_404 =
  "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\n\
   Connection: close\r\n\r\nNot Found"

(* ── Request router ──────────────────────────────────────────── *)

let handle_request req =
  let first_line =
    match String.split_on_char '\n' req with
    | line :: _ -> String.trim line
    | []        -> ""
  in
  let (path, query) =
    match String.split_on_char ' ' first_line with
    | _ :: url :: _ ->
      (match String.split_on_char '?' url with
       | [p]    -> (p, "")
       | p :: q -> (p, String.concat "?" q)
       | []     -> ("/", ""))
    | _ -> ("/", "")
  in
  let params = parse_query query in
  match path with

  | "/health" ->
    let body = Printf.sprintf "{%s,%s}"
      (json_kv_s "status"  "ok")
      (json_kv_s "service" "ocaml-risk-engine") in
    http_200 body

  | "/api/ocaml/risk" ->
    let debt_ratio    = get_float params "debt_ratio"    0.55 in
    let volatility    = get_float params "volatility"    0.22 in
    let leverage      = get_float params "leverage"      2.5  in
    let credit_score_ = get_int   params "credit_score"  680  in
    let (score, level) = evaluate_risk
      ~debt_ratio ~volatility ~leverage ~credit_score:credit_score_ in
    let body = Printf.sprintf "{%s,%s,%s,%s,%s,%s,%s}"
      (json_kv_s "level"        (string_of_risk level))
      (json_kv_i "risk_score"   score)
      (json_kv_f "debt_ratio"   debt_ratio)
      (json_kv_f "volatility"   volatility)
      (json_kv_f "leverage"     leverage)
      (json_kv_i "credit_score" credit_score_)
      (json_kv_s "engine"       "OCaml rule-based") in
    http_200 body

  | "/api/ocaml/score" ->
    let income          = get_int params "income"          5000000 in
    let debt            = get_int params "debt"            1500000 in
    let history_years   = get_int params "history_years"   5       in
    let missed_payments = get_int params "missed_payments" 0       in
    let (sc, grade, prob) = credit_score
      ~income ~debt ~history_years ~missed_payments in
    let body = Printf.sprintf "{%s,%s,%s,%s,%s,%s,%s}"
      (json_kv_i "score"          sc)
      (json_kv_s "grade"          grade)
      (json_kv_f "prob_good"      prob)
      (json_kv_i "income"         income)
      (json_kv_i "debt"           debt)
      (json_kv_i "history_years"  history_years)
      (json_kv_s "engine"         "OCaml logistic") in
    http_200 body

  | "/api/ocaml/portfolio" ->
    let w = [| 0.25; 0.25; 0.25; 0.25 |] in
    let (ann_vol, var_95, cvar_95, port_var) =
      portfolio_risk ~vols:default_vols ~weights:w ~corr_flat:default_corr in
    let mcvar_list = Array.mapi (fun i _ ->
      let contrib = ref 0.0 in
      for j = 0 to 3 do
        contrib := !contrib
          +. w.(j) *. default_vols.(i) *. default_vols.(j)
          *. default_corr.(i * 4 + j)
      done;
      !contrib /. sqrt port_var
    ) default_vols in
    let asset_rows = Array.to_list (Array.mapi (fun i a ->
      Printf.sprintf "{%s,%s,%s}"
        (json_kv_s "asset"       a)
        (json_kv_f "daily_vol"   default_vols.(i))
        (json_kv_f "marginal_var" mcvar_list.(i))
    ) assets) in
    let assets_json = "[" ^ (String.concat "," asset_rows) ^ "]" in
    let body = Printf.sprintf "{%s,%s,%s,%s,%s,%s}"
      (json_kv_f "portfolio_ann_vol" ann_vol)
      (json_kv_f "var_95_1day"       var_95)
      (json_kv_f "cvar_95_1day"      cvar_95)
      (json_kv_s "weights"           "25/25/25/25")
      (Printf.sprintf "\"assets\":%s" assets_json)
      (json_kv_s "engine"            "OCaml portfolio-risk") in
    http_200 body

  | "/api/ocaml/loan" ->
    (* Loan approval endpoint.
       Query params: credit_score, debt_ratio, collateral_ratio,
                     leverage, income, missed_payments *)
    let credit_score_i   = get_int   params "credit_score"    700  in
    let debt_ratio       = get_float params "debt_ratio"      0.45 in
    let collateral_ratio = get_float params "collateral_ratio" 0.40 in
    let leverage         = get_float params "leverage"         2.0  in
    let income           = get_int   params "income"          5000000 in
    let missed_payments  = get_int   params "missed_payments"  0    in
    let ap = { credit_score_i; debt_ratio; collateral_ratio;
               leverage; income; missed_payments } in
    let decision = evaluate_loan ap in
    let body = Printf.sprintf "{%s,%s,%s,%s,%s,%s,%s,%s}"
      (json_kv_s "decision"         (string_of_loan_decision decision))
      (json_kv_s "reason"           (reason_of_loan_decision decision))
      (json_kv_i "credit_score"     credit_score_i)
      (json_kv_f "debt_ratio"       debt_ratio)
      (json_kv_f "collateral_ratio" collateral_ratio)
      (json_kv_f "leverage"         leverage)
      (json_kv_i "missed_payments"  missed_payments)
      (json_kv_s "engine"           "OCaml pattern-matching loan") in
    http_200 body

  | "/api/ocaml/margincall" ->
    (* Margin call status endpoint.
       Query params: leverage, collateral_ratio *)
    let leverage         = get_float params "leverage"         3.5  in
    let collateral_ratio = get_float params "collateral_ratio" 0.25 in
    let credit_score_i   = get_int   params "credit_score"    700  in
    let debt_ratio       = get_float params "debt_ratio"      0.45 in
    let income           = get_int   params "income"          5000000 in
    let missed_payments  = get_int   params "missed_payments"  0    in
    let ap = { credit_score_i; debt_ratio; collateral_ratio;
               leverage; income; missed_payments } in
    let status = evaluate_margin ap in
    let body = Printf.sprintf "{%s,%s,%s,%s,%s}"
      (json_kv_s "status"           (string_of_margin status))
      (json_kv_s "action"           (margin_action status))
      (json_kv_f "leverage"         leverage)
      (json_kv_f "collateral_ratio" collateral_ratio)
      (json_kv_s "engine"           "OCaml pattern-matching margin") in
    http_200 body

  | _ -> http_404

(* ── TCP server loop ──────────────────────────────────────────── *)

let () =
  let port = 8004 in
  let sock = Unix.socket Unix.PF_INET Unix.SOCK_STREAM 0 in
  Unix.setsockopt sock Unix.SO_REUSEADDR true;
  Unix.bind sock (Unix.ADDR_INET (Unix.inet_addr_any, port));
  Unix.listen sock 32;
  Printf.printf "OCaml Risk Engine listening on :%d\n%!" port;
  while true do
    let (client, _addr) = Unix.accept sock in
    (try
      let ic  = Unix.in_channel_of_descr client in
      let buf = Buffer.create 1024 in
      (try
        let line = ref (input_line ic) in
        while !line <> "\r" && !line <> "" do
          Buffer.add_string buf !line;
          Buffer.add_char   buf '\n';
          line := input_line ic
        done
      with End_of_file -> ());
      let req  = Buffer.contents buf in
      let resp = handle_request req in
      let oc   = Unix.out_channel_of_descr client in
      output_string oc resp;
      flush oc
    with _ -> ());
    Unix.close client
  done
