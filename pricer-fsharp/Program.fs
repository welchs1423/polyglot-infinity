open System
open Microsoft.AspNetCore.Builder
open Microsoft.AspNetCore.Http
open Microsoft.Extensions.DependencyInjection

module MathHelper =
    let normCdf (x: float) =
        let t = 1.0 / (1.0 + 0.2316419 * abs x)
        let poly = t * (0.319381530 + t * (-0.356563782 + t * (1.781477937 + t * (-1.821255978 + t * 1.330274429))))
        let pdf = exp(-x * x / 2.0) / sqrt(2.0 * Math.PI)
        if x >= 0.0 then 1.0 - pdf * poly else pdf * poly
    let normPdf (x: float) = exp(-x * x / 2.0) / sqrt(2.0 * Math.PI)

module BlackScholes =
    open MathHelper
    let price (s: float) (k: float) (r: float) (sigma: float) (t: float) =
        if t <= 0.0 then
            {| call_price = max (s-k) 0.0; put_price = max (k-s) 0.0
               delta_call = (if s > k then 1.0 else 0.0); delta_put = (if s < k then -1.0 else 0.0)
               gamma = 0.0; vega = 0.0; theta_call = 0.0; rho_call = 0.0; engine = "F#-Pricer-v2" |}
        else
            let d1 = (log(s/k) + (r + sigma*sigma/2.0)*t) / (sigma * sqrt t)
            let d2 = d1 - sigma * sqrt t
            let callP = s * normCdf d1 - k * exp(-r*t) * normCdf d2
            let putP  = k * exp(-r*t) * normCdf(-d2) - s * normCdf(-d1)
            {| call_price  = Math.Round(callP, 6)
               put_price   = Math.Round(putP, 6)
               delta_call  = Math.Round(normCdf d1, 6)
               delta_put   = Math.Round(normCdf d1 - 1.0, 6)
               gamma       = Math.Round(normPdf d1 / (s * sigma * sqrt t), 6)
               vega        = Math.Round(s * normPdf d1 * sqrt t / 100.0, 6)
               theta_call  = Math.Round((-(s * normPdf d1 * sigma) / (2.0 * sqrt t) - r * k * exp(-r*t) * normCdf d2) / 365.0, 6)
               rho_call    = Math.Round(k * t * exp(-r*t) * normCdf d2 / 100.0, 6)
               engine      = "F#-Pricer-v2" |}

module Dcf =
    let calculate (fcf: float) (growthRate: float) (terminalGrowth: float) (wacc: float) (years: int) =
        let flows   = [ for y in 1..years -> fcf * Math.Pow(1.0 + growthRate, float y) ]
        let pvFlows = flows |> List.mapi (fun i cf -> cf / Math.Pow(1.0 + wacc, float (i+1)))
        let tv      = List.last flows * (1.0 + terminalGrowth) / (wacc - terminalGrowth)
        let npv     = List.sum pvFlows + tv / Math.Pow(1.0 + wacc, float years)
        {| intrinsic_value  = Math.Round(npv, 2)
           margin_of_safety = Math.Round((npv - fcf) / npv * 100.0, 2)
           npv              = Math.Round(npv, 2)
           cash_flows       = flows |> List.map (fun x -> Math.Round(x, 2))
           engine           = "F#-Pricer-v2" |}

module ImpliedVol =
    open MathHelper
    open BlackScholes

    /// Newton-Raphson 역산으로 Implied Volatility 를 구한다.
    ///
    /// 수렴 조건:
    ///   |BS(σ_n) - market_price| < tol  또는 iter >= max_iter
    ///
    /// 반환값:
    ///   Some σ  — 수렴 성공
    ///   None    — vega ⍨00 또는 범위 이탈 (로우/하이 불리)
    let solve
            (marketPrice : float)
            (s           : float)
            (k           : float)
            (r           : float)
            (t           : float)
            (isCall      : bool)
            : {| iv: float option; iterations: int; error: float option; engine: string |} =

        let maxIter = 200
        let tol     = 1e-8
        let mutable sigma       = 0.20   // 초기값
        let mutable iter        = 0
        let mutable converged   = false
        let mutable lastError   = Double.MaxValue

        while iter < maxIter && not converged do
            let bs    = price s k r sigma t
            let bsP   = if isCall then bs.call_price else bs.put_price
            // vega 는 price() 에서 /100 스케일링되어 나온다 → 원래 vega 복원
            let vega  = bs.vega * 100.0
            lastError <- abs (bsP - marketPrice)

            if vega < 1e-10 then
                iter <- maxIter   // vega ≈ 0: 수렴 불가
            else
                let step = (bsP - marketPrice) / vega
                sigma <- max 0.001 (min 10.0 (sigma - step))
                if abs step < tol then converged <- true

            iter <- iter + 1

        let ivResult = if converged then Some (Math.Round(sigma, 8)) else None
        let errResult = if converged then Some (Math.Round(lastError, 10)) else None

        {| iv         = ivResult
           iterations = iter
           error      = errResult
           engine     = "F#-Pricer-v2" |}

[<EntryPoint>]
let main args =
    let builder = WebApplication.CreateBuilder(args)
    builder.Services.AddCors(fun opt ->
        opt.AddDefaultPolicy(fun p -> p.AllowAnyOrigin().AllowAnyMethod().AllowAnyHeader() |> ignore)
    ) |> ignore
    let app = builder.Build()
    app.UseCors() |> ignore

    let getF (q: IQueryCollection) key def =
        match q.TryGetValue(key) with
        | true, v -> try float (string v) with _ -> def
        | _       -> def

    let writeJson (ctx: HttpContext) obj =
        ctx.Response.ContentType <- "application/json"
        ctx.Response.WriteAsync(Text.Json.JsonSerializer.Serialize(obj))

    app.MapGet("/api/fsharp/option", RequestDelegate(fun ctx ->
        let q   = ctx.Request.Query
        let res = BlackScholes.price (getF q "s" 100.0) (getF q "k" 100.0)
                                     (getF q "r" 0.05) (getF q "sigma" 0.20)
                                     (getF q "t" 1.0)
        writeJson ctx res
    )) |> ignore

    // GET /api/fsharp/iv?market_price=10.5&s=100&k=100&r=0.05&t=1.0&type=call
    // Newton-Raphson 역산으로 Implied Volatility 계산
    app.MapGet("/api/fsharp/iv", RequestDelegate(fun ctx ->
        let q        = ctx.Request.Query
        let mktPrice = getF q "market_price" 10.0
        let s        = getF q "s"            100.0
        let k        = getF q "k"            100.0
        let r        = getF q "r"            0.05
        let t        = getF q "t"            1.0
        let isCall   =
            match q.TryGetValue("type") with
            | true, v -> (string v).ToLower() <> "put"
            | _       -> true
        let res = ImpliedVol.solve mktPrice s k r t isCall
        writeJson ctx res
    )) |> ignore

    app.MapGet("/api/fsharp/dcf", RequestDelegate(fun ctx ->
        let q     = ctx.Request.Query
        let years = match q.TryGetValue("years") with
                    | true, v -> try int (string v) with _ -> 5
                    | _       -> 5
        let res   = Dcf.calculate (getF q "fcf" 1_000_000.0) (getF q "growth" 0.10)
                                  (getF q "terminal" 0.03) (getF q "wacc" 0.08) years
        writeJson ctx res
    )) |> ignore

    app.MapGet("/health", RequestDelegate(fun ctx ->
        writeJson ctx {| status = "ok"; engine = "F#-Pricer-v2"; port = 9001 |}
    )) |> ignore

    app.Urls.Add("http://0.0.0.0:9001")
    app.Run()
    0
