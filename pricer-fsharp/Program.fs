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
               gamma = 0.0; vega = 0.0; theta_call = 0.0; rho_call = 0.0; engine = "F#-Pricer-v1" |}
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
               engine      = "F#-Pricer-v1" |}

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
           engine           = "F#-Pricer-v1" |}

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

    app.MapGet("/api/fsharp/dcf", RequestDelegate(fun ctx ->
        let q     = ctx.Request.Query
        let years = match q.TryGetValue("years") with true, v -> try int (string v) with _ -> 5 | _ -> 5
        let res   = Dcf.calculate (getF q "fcf" 1_000_000.0) (getF q "growth" 0.10)
                                  (getF q "terminal" 0.03) (getF q "wacc" 0.08) years
        writeJson ctx res
    )) |> ignore

    app.MapGet("/health", RequestDelegate(fun ctx ->
        writeJson ctx {| status = "ok"; engine = "F#-Pricer-v1"; port = 9001 |}
    )) |> ignore

    app.Urls.Add("http://0.0.0.0:9001")
    app.Run()
    0
