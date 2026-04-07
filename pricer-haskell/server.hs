{-# LANGUAGE DataKinds         #-}
{-# LANGUAGE DeriveGeneric     #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeOperators     #-}

module Main where

import Data.Aeson                 (ToJSON)
import GHC.Generics               (Generic)
import Network.Wai.Handler.Warp   (run)
import Servant

-- Port: 8006
-- Endpoints:
--   GET /health
--   GET /price?s=&k=&r=&sigma=&t=
--   GET /montecarlo?s=&vol=&mu=&n=&days=
--   GET /stream?s=&mu=&sigma=&n=&seed=

-- ── Pure math ──────────────────────────────────────────────────

pi' :: Double
pi' = 3.141592653589793

-- Cumulative normal distribution via Abramowitz and Stegun 26.2.17
normCdf :: Double -> Double
normCdf x
  | x < 0    = 1.0 - normCdf (-x)
  | otherwise =
      let t = 1.0 / (1.0 + 0.2316419 * x)
          d = exp (-0.5 * x * x) / sqrt (2.0 * pi')
          p = t * ( 0.319381530
                  + t * (-0.356563782
                  + t * ( 1.781477937
                  + t * (-1.821255978
                  + t *   1.330274429))))
      in 1.0 - d * p

normPdf :: Double -> Double
normPdf x = exp (-0.5 * x * x) / sqrt (2.0 * pi')

-- ── Black-Scholes model (European vanilla options) ─────────────
--
-- Inputs:
--   s     spot price
--   k     strike price
--   r     continuous risk-free rate (annualised)
--   sigma implied volatility (annualised)
--   t     time to expiry in years
--
-- Outputs:
--   call / put price (GBM closed-form solution)
--   delta  dV/dS
--   gamma  d2V/dS2
--   vega   dV/d(sigma) per 1-pct move
--   theta  dV/dt per calendar day

data BSResult = BSResult
  { callPrice  :: Double
  , putPrice   :: Double
  , delta      :: Double
  , gamma      :: Double
  , vega       :: Double
  , thetaDaily :: Double
  , d1         :: Double
  , d2         :: Double
  , engine     :: String
  } deriving (Generic, Show)

instance ToJSON BSResult

blackScholes :: Double -> Double -> Double -> Double -> Double -> BSResult
blackScholes s k r sigma t =
  let d1v   = (log (s / k) + (r + 0.5 * sigma * sigma) * t) / (sigma * sqrt t)
      d2v   = d1v - sigma * sqrt t
      call  = s * normCdf d1v - k * exp (-r * t) * normCdf d2v
      put   = k * exp (-r * t) * normCdf (-d2v) - s * normCdf (-d1v)
      dlt   = normCdf d1v
      gma   = normPdf d1v / (s * sigma * sqrt t)
      vga   = s * normPdf d1v * sqrt t / 100.0
      tht   = (-(s * normPdf d1v * sigma) / (2.0 * sqrt t)
               - r * k * exp (-r * t) * normCdf d2v) / 365.0
  in BSResult call put dlt gma vga tht d1v d2v "Haskell GHC servant-server"

-- ── Pseudo-random via LCG ──────────────────────────────────────

lcgSeq :: Int -> [Double]
lcgSeq seed = map toUnit $ iterate lcgNext seed
  where
    lcgNext x  = (1664525 * x + 1013904223) `mod` (2 ^ (31 :: Int))
    toUnit  x  = fromIntegral x / fromIntegral (2 ^ (31 :: Int))

-- Box-Muller transform: pairs of uniform -> standard normals
boxMuller :: [Double] -> [Double]
boxMuller (u1:u2:rest) =
  let z = sqrt (-2.0 * log (max u1 1e-10)) * cos (2.0 * pi' * u2)
  in z : boxMuller rest
boxMuller _ = []

-- ── Geometric Brownian Motion Monte Carlo ─────────────────────
--
-- Returns final prices of nPaths simulated paths after nDays steps.
-- Uses LCG + Box-Muller; deterministic with fixed seed.

mcFinals :: Double -> Double -> Double -> Int -> Int -> Int -> [Double]
mcFinals s0 mu vol nPaths nDays seed =
  let dt     = 1.0 / 252.0
      drift  = (mu - 0.5 * vol * vol) * dt
      diff   = vol * sqrt dt
      zs     = take (nPaths * nDays) $ boxMuller (lcgSeq seed)
      path i = foldl (\p z -> p * exp (drift + diff * z)) s0
                     (take nDays $ drop (i * nDays) zs)
  in map path [0 .. nPaths - 1]

mean' :: [Double] -> Double
mean' xs = sum xs / fromIntegral (length xs)

std' :: [Double] -> Double
std' xs =
  let m = mean' xs
      v = mean' (map (\x -> (x - m) ^ (2 :: Int)) xs)
  in sqrt v

percentile :: [Double] -> Double -> Double
percentile xs p =
  let sorted = foldr insertSorted [] xs
      n      = fromIntegral (length sorted)
      i      = min (floor (p / 100.0 * n)) (length sorted - 1)
  in sorted !! i
  where
    insertSorted y []     = [y]
    insertSorted y (z:zs) = if y <= z then y:z:zs else z : insertSorted y zs

-- ── Infinite lazy GBM stream (iterate / scanl) ────────────────
--
-- Haskell lazy evaluation: gbmStream produces an infinite list;
-- consumers materialise only the prefix they request via take.

gbmStream :: Double -> Double -> Double -> Int -> [Double]
gbmStream s0 mu sigma seed =
  let dt    = 1.0 / 252.0
      drift = (mu - 0.5 * sigma * sigma) * dt
      diff  = sigma * sqrt dt
      zs    = boxMuller (drop 1 $ lcgSeq seed)
  in scanl (\p z -> p * exp (drift + diff * z)) s0 zs

logReturns :: [Double] -> [Double]
logReturns ps = zipWith (\a b -> log (b / max a 1e-10)) ps (tail ps)

-- EWMA volatility (RiskMetrics lambda = 0.94)
ewmaVol :: Double -> [Double] -> [Double]
ewmaVol lam rets =
  let lam1 = 1.0 - lam
      v0   = case rets of { [] -> 0.0; (r:_) -> r * r }
  in map sqrt $ scanl (\v r -> lam * v + lam1 * r * r) v0 rets

runningDrawdown :: [Double] -> [Double]
runningDrawdown prices =
  let peaks = scanl1 max prices
      dds   = zipWith (\pk p -> if pk > 0 then (pk - p) / pk else 0.0) peaks prices
  in scanl max 0.0 dds

-- ── Response types ─────────────────────────────────────────────

data HealthResponse = HealthResponse
  { status  :: String
  , service :: String
  , version :: String
  } deriving (Generic)

instance ToJSON HealthResponse

data MCResult = MCResult
  { meanLogReturn     :: Double
  , stdLogReturn      :: Double
  , annualisedReturn  :: Double
  , annualisedVol     :: Double
  , var95             :: Double
  , cvar95            :: Double
  , avgFinalPrice     :: Double
  , nPaths            :: Int
  , nDays             :: Int
  , mcEngine          :: String
  } deriving (Generic)

instance ToJSON MCResult

data StreamResult = StreamResult
  { snDays            :: Int
  , finalPrice        :: Double
  , streamAnnReturn   :: Double
  , streamAnnVol      :: Double
  , sharpeRatio       :: Double
  , maxDrawdown       :: Double
  , streamEngine      :: String
  } deriving (Generic)

instance ToJSON StreamResult

-- ── Servant API definition ─────────────────────────────────────

type API
    = "health" :> Get '[JSON] HealthResponse
 :<|> "price"
        :> QueryParam "s"     Double
        :> QueryParam "k"     Double
        :> QueryParam "r"     Double
        :> QueryParam "sigma" Double
        :> QueryParam "t"     Double
        :> Get '[JSON] BSResult
 :<|> "montecarlo"
        :> QueryParam "s"    Double
        :> QueryParam "vol"  Double
        :> QueryParam "mu"   Double
        :> QueryParam "n"    Int
        :> QueryParam "days" Int
        :> Get '[JSON] MCResult
 :<|> "stream"
        :> QueryParam "s"     Double
        :> QueryParam "mu"    Double
        :> QueryParam "sigma" Double
        :> QueryParam "n"     Int
        :> QueryParam "seed"  Int
        :> Get '[JSON] StreamResult

-- ── Handlers ───────────────────────────────────────────────────

healthHandler :: Handler HealthResponse
healthHandler = return $ HealthResponse "ok" "pricer-haskell" "GHC servant-server"

-- Default parameter values follow standard ATM 1-year option convention
priceHandler
  :: Maybe Double -> Maybe Double -> Maybe Double
  -> Maybe Double -> Maybe Double
  -> Handler BSResult
priceHandler ms mk mr msigma mt =
  let s     = maybe 100.0 id ms
      k     = maybe 100.0 id mk
      r     = maybe 0.05  id mr
      sigma = maybe 0.20  id msigma
      t     = maybe 1.0   id mt
  in return $ blackScholes s k r sigma t

mcHandler
  :: Maybe Double -> Maybe Double -> Maybe Double
  -> Maybe Int -> Maybe Int
  -> Handler MCResult
mcHandler ms mvol mmu mn mdays =
  let s     = maybe 100.0 id ms
      vol   = maybe 0.20  id mvol
      mu    = maybe 0.08  id mmu
      n     = maybe 500   id mn
      days  = maybe 252   id mdays
      seed  = 42
      finals = mcFinals s mu vol n days seed
      rets  = map (\p -> log (p / s)) finals
      m     = mean' rets
      sv    = std' rets
      scale = 252.0 / fromIntegral days
      annR  = m * scale
      annV  = sv * sqrt scale
      v95   = percentile rets 5.0
      cv95  = mean' (filter (<= v95) rets)
  in return $ MCResult m sv annR annV v95 cv95 (mean' finals) n days
                       "Haskell GHC servant-server monte-carlo GBM"

streamHandler
  :: Maybe Double -> Maybe Double -> Maybe Double
  -> Maybe Int -> Maybe Int
  -> Handler StreamResult
streamHandler ms mmu msigma mn mseed =
  let s     = maybe 100.0 id ms
      mu    = maybe 0.08  id mmu
      sigma = maybe 0.20  id msigma
      n     = min 500 $ maybe 60 id mn
      seed  = maybe 42 id mseed
      stream = gbmStream s mu sigma seed
      prices = take (n + 1) stream
      rets   = take n $ logReturns prices
      vols   = take n $ ewmaVol 0.94 rets
      dds    = take (n + 1) $ runningDrawdown prices
      annR   = mean' rets * 252.0
      annV   = std'  rets * sqrt 252.0
      sharpe = if annV > 0 then annR / annV else 0.0
      mdd    = last dds
      -- suppress unused warning for vols (included for completeness)
      _      = length vols
  in return $ StreamResult n (last prices) annR annV sharpe mdd
                           "Haskell GHC servant-server lazy-stream scanl"

server :: Server API
server = healthHandler
    :<|> priceHandler
    :<|> mcHandler
    :<|> streamHandler

api :: Proxy API
api = Proxy

main :: IO ()
main = do
  let port = 8006 :: Int
  putStrLn $ "pricer-haskell listening on :" ++ show port
  run port (serve api server)
