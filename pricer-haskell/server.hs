{-# LANGUAGE OverloadedStrings #-}
module Main where

import Network.Socket
import Network.Socket.ByteString (recv, sendAll)
import qualified Data.ByteString.Char8 as B
import Data.List (intercalate, sort)
import Data.Char (isAlpha, toLower)
import System.IO (hSetBuffering, stdout, BufferMode(..))

-- ============================================================
-- Pure Functional Finance (Haskell 8.8.4)
-- Port: 8006
-- Endpoints:
--   GET /health
--   GET /api/haskell/blackscholes?s=100&k=100&r=0.05&sigma=0.2&t=1
--   GET /api/haskell/montecarlo?s=100&vol=0.2&mu=0.08&n=1000&days=252
-- ============================================================

-- ---------- Math helpers (stdlib only) ----------

pi' :: Double
pi' = 3.141592653589793

-- Cumulative Normal Distribution (Hart approximation)
normCdf :: Double -> Double
normCdf x
  | x < 0    = 1.0 - normCdf (-x)
  | otherwise =
      let t  = 1.0 / (1.0 + 0.2316419 * x)
          d  = exp (-0.5 * x * x) / sqrt (2.0 * pi')
          p  = t * (0.319381530
                 + t * (-0.356563782
                 + t * (1.781477937
                 + t * (-1.821255978
                 + t * 1.330274429))))
      in 1.0 - d * p

normPdf :: Double -> Double
normPdf x = exp (-0.5 * x * x) / sqrt (2.0 * pi')

-- ---------- Black-Scholes ----------

data BSResult = BSResult
  { bsCall   :: Double
  , bsPut    :: Double
  , bsDelta  :: Double
  , bsGamma  :: Double
  , bsVega   :: Double
  , bsTheta  :: Double
  , bsD1     :: Double
  , bsD2     :: Double
  } deriving (Show)

blackScholes :: Double -> Double -> Double -> Double -> Double -> BSResult
blackScholes s k r sigma t =
  let d1    = (log (s / k) + (r + 0.5 * sigma * sigma) * t) / (sigma * sqrt t)
      d2    = d1 - sigma * sqrt t
      call  = s * normCdf d1 - k * exp (-r * t) * normCdf d2
      put   = k * exp (-r * t) * normCdf (-d2) - s * normCdf (-d1)
      delta = normCdf d1
      gamma = normPdf d1 / (s * sigma * sqrt t)
      vega  = s * normPdf d1 * sqrt t / 100.0    -- per 1% move
      theta = (-(s * normPdf d1 * sigma) / (2.0 * sqrt t)
               - r * k * exp (-r * t) * normCdf d2) / 365.0
  in BSResult call put delta gamma vega theta d1 d2

-- ---------- Pseudo-random (LCG) ----------

lcgNext :: Int -> Int
lcgNext seed = (1664525 * seed + 1013904223) `mod` (2 ^ (31 :: Int))

lcgSeq :: Int -> [Double]
lcgSeq seed = map toUnit $ iterate lcgNext seed
  where toUnit x = fromIntegral x / fromIntegral (2 ^ (31 :: Int))

-- Box-Muller (pairs)
boxMuller :: [Double] -> [Double]
boxMuller (u1:u2:rest) =
  let z = sqrt (-2.0 * log (max u1 1e-10)) * cos (2.0 * pi' * u2)
  in z : boxMuller rest
boxMuller _ = []

-- GBM Monte Carlo: returns list of final prices
monteCarloFinals :: Double -> Double -> Double -> Int -> Int -> Int -> [Double]
monteCarloFinals s0 mu vol nPaths nDays seed =
  let dt    = 1.0 / 252.0
      drift = (mu - 0.5 * vol * vol) * dt
      diffS  = vol * sqrt dt
      randoms = take (nPaths * nDays) $ boxMuller (lcgSeq seed)
      simulatePath zs = foldl (\p z -> p * exp (drift + diffS * z))
                              s0
                              (take nDays zs)
      paths  = map (\i -> simulatePath (drop (i * nDays) randoms)) [0..nPaths-1]
  in paths

-- Stats helpers
mean' :: [Double] -> Double
mean' xs = sum xs / fromIntegral (length xs)

std' :: [Double] -> Double
std' xs =
  let m = mean' xs
      v = mean' (map (\x -> (x - m) ^ (2 :: Int)) xs)
  in sqrt v

percentile :: [Double] -> Double -> Double
percentile xs p =
  let sorted = sort xs
      n      = fromIntegral (length sorted)
      idx    = floor (p / 100.0 * n) :: Int
      i      = min idx (length sorted - 1)
  in sorted !! i

-- ---------- Lazy Infinite Price Stream (Haskell 핵심 강점) ----------
-- iterate로 무한 리스트 생성 → 필요한 만큼만 take로 구체화
-- 메모리에 전체 스트림을 올리지 않음 (레이지 평가)

-- 무한 GBM 가격 스트림: iterate + scanl 조합
gbmStream :: Double -> Double -> Double -> Int -> [Double]
gbmStream s0 mu sigma seed =
  let dt    = 1.0 / 252.0
      drift = (mu - 0.5 * sigma * sigma) * dt
      diff  = sigma * sqrt dt
      zs    = boxMuller (drop 1 $ lcgSeq seed)  -- 무한 정규분포 스트림
  in scanl (\p z -> p * exp (drift + diff * z)) s0 zs

-- 로그 수익률 스트림 (zipWith로 인접 쌍 처리)
logReturns :: [Double] -> [Double]
logReturns ps = zipWith (\a b -> log (b / max a 1e-10)) ps (tail ps)

-- EWMA 변동성 스트림 (RiskMetrics λ=0.94, scanl로 상태 전이)
ewmaVol :: Double -> [Double] -> [Double]
ewmaVol lambda rets =
  let lam1   = 1.0 - lambda
      v0     = case rets of { [] -> 0.0; (r:_) -> r * r }
      update v r = lambda * v + lam1 * r * r
  in map sqrt $ scanl update v0 rets

-- 누적 최대 낙폭 스트림 (scanl로 peak 추적)
runningDrawdown :: [Double] -> [Double]
runningDrawdown prices =
  let peaks = scanl1 max prices
      dds   = zipWith (\peak p -> if peak > 0 then (peak - p) / peak else 0.0)
                      peaks prices
  in scanl max 0.0 dds

-- ---------- Stream JSON ----------

showList' :: [Double] -> String
showList' xs = "[" ++ intercalate "," (map (show . roundTo 6) xs) ++ "]"

streamJson :: [Double] -> Int -> String
streamJson stream n =
  let prices  = take (n + 1) stream          -- 무한 스트림에서 n+1개만 구체화
      rets    = take n $ logReturns prices   -- 레이지 zipWith
      vols    = take n $ ewmaVol 0.94 rets   -- 레이지 scanl
      drawdowns = take (n + 1) $ runningDrawdown prices
      finalP  = last prices
      annRet  = mean' rets * 252.0
      annVol  = std' rets * sqrt 252.0
      sharpe  = if annVol > 0 then annRet / annVol else 0.0
      mdd     = last drawdowns
  in "{" ++ intercalate ","
    [ jsonKVI  "n"                n
    , jsonKV   "final_price"      finalP
    , jsonKV   "annualized_return" annRet
    , jsonKV   "annualized_vol"    annVol
    , jsonKV   "sharpe_ratio"      sharpe
    , jsonKV   "max_drawdown"      mdd
    , "\"prices\":"     ++ showList' prices
    , "\"ewma_vol\":"   ++ showList' vols
    , "\"drawdowns\":"  ++ showList' drawdowns
    , jsonStr  "engine" "Haskell GHC 8.8.4 — infinite lazy stream (iterate/scanl/zipWith)"
    ] ++ "}"



type Query = [(String, String)]

parseQuery :: String -> Query
parseQuery "" = []
parseQuery qs =
  map parsePair $ splitOn '&' qs
  where
    parsePair pair = case break (== '=') pair of
      (k, '=':v) -> (k, v)
      (k, _)     -> (k, "")

splitOn :: Char -> String -> [String]
splitOn _ "" = [""]
splitOn c (x:xs)
  | x == c    = "" : splitOn c xs
  | otherwise = let (w:ws) = splitOn c xs in (x:w) : ws

lookupParam :: Query -> String -> Double -> Double
lookupParam q key def =
  case lookup key q of
    Just v  -> case reads v of
                 [(n, "")] -> n
                 _         -> def
    Nothing -> def

lookupInt :: Query -> String -> Int -> Int
lookupInt q key def =
  case lookup key q of
    Just v  -> case reads v :: [(Int, String)] of
                 [(n, "")] -> n
                 _         -> def
    Nothing -> def

-- ---------- JSON helpers ----------

jsonKV :: String -> Double -> String
jsonKV k v = "\"" ++ k ++ "\":" ++ show (roundTo 6 v)

jsonKVI :: String -> Int -> String
jsonKVI k v = "\"" ++ k ++ "\":" ++ show v

jsonStr :: String -> String -> String
jsonStr k v = "\"" ++ k ++ "\":\"" ++ v ++ "\""

roundTo :: Int -> Double -> Double
roundTo d x = fromIntegral (round (x * f) :: Int) / f
  where f = 10.0 ^ d

-- ---------- Handlers ----------

healthJson :: String
healthJson = "{\"status\":\"ok\",\"service\":\"haskell-pricer\",\"version\":\"GHC 8.8.4\"}"

bsJson :: BSResult -> Double -> Double -> Double -> Double -> Double -> String
bsJson r s k sigma t annVol =
  "{" ++ intercalate ","
    [ jsonKV "call_price"   (bsCall r)
    , jsonKV "put_price"    (bsPut r)
    , jsonKV "delta"        (bsDelta r)
    , jsonKV "gamma"        (bsGamma r)
    , jsonKV "vega"         (bsVega r)
    , jsonKV "theta_daily"  (bsTheta r)
    , jsonKV "d1"           (bsD1 r)
    , jsonKV "d2"           (bsD2 r)
    , jsonStr "engine"       "Haskell GHC 8.8.4"
    ] ++ "}"

mcJson :: [Double] -> Double -> Double -> Double -> Int -> Int -> String
mcJson finals s0 mu vol nDays nPaths =
  let returns_ = map (\p -> log (p / s0)) finals
      m       = mean' returns_
      s       = std' returns_
      annRet  = m * (252.0 / fromIntegral nDays)
      annVol  = s * sqrt (252.0 / fromIntegral nDays)
      var95   = percentile returns_ 5.0
      cvar95  = mean' (filter (<= var95) returns_)
      avgFin  = mean' finals
  in "{" ++ intercalate ","
    [ jsonKV "mean_log_return" m
    , jsonKV "std_log_return"  s
    , jsonKV "annualized_return" annRet
    , jsonKV "annualized_vol"    annVol
    , jsonKV "var_95"            var95
    , jsonKV "cvar_95"           cvar95
    , jsonKV "avg_final_price"   avgFin
    , jsonKVI "n_paths"          nPaths
    , jsonKVI "n_days"           nDays
    , jsonStr "engine"           "Haskell GHC 8.8.4"
    ] ++ "}"

-- ---------- HTTP server ----------

httpResponse :: Int -> String -> String -> String
httpResponse code contentType body =
  "HTTP/1.1 " ++ show code ++ " " ++ statusText code ++ "\r\n"
  ++ "Content-Type: " ++ contentType ++ "; charset=utf-8\r\n"
  ++ "Access-Control-Allow-Origin: *\r\n"
  ++ "Content-Length: " ++ show (length body) ++ "\r\n"
  ++ "Connection: close\r\n"
  ++ "\r\n"
  ++ body

statusText :: Int -> String
statusText 200 = "OK"
statusText 404 = "Not Found"
statusText _   = "Error"

parseRequest :: String -> (String, String)
parseRequest req =
  case lines req of
    (l:_) -> case words l of
               (_:path:_) -> case break (== '?') path of
                               (p, '?':q) -> (p, q)
                               (p, _)     -> (p, "")
               _          -> ("/", "")
    _     -> ("/", "")

handleRequest :: String -> String -> String
handleRequest path query
  | path == "/health" =
      httpResponse 200 "application/json" healthJson

  | path == "/api/haskell/blackscholes" =
      let q     = parseQuery query
          s     = lookupParam q "s"     100.0
          k     = lookupParam q "k"     100.0
          r     = lookupParam q "r"     0.05
          sigma = lookupParam q "sigma" 0.2
          t     = lookupParam q "t"     1.0
          res   = blackScholes s k r sigma t
      in httpResponse 200 "application/json" (bsJson res s k sigma t sigma)

  | path == "/api/haskell/montecarlo" =
      let q      = parseQuery query
          s      = lookupParam q "s"    100.0
          vol    = lookupParam q "vol"  0.2
          mu     = lookupParam q "mu"   0.08
          n      = lookupInt q "n"      500
          days   = lookupInt q "days"   252
          finals = monteCarloFinals s mu vol n days 42
      in httpResponse 200 "application/json" (mcJson finals s mu vol days n)

  | path == "/api/haskell/stream" =
      let q     = parseQuery query
          s     = lookupParam q "s"     100.0
          mu    = lookupParam q "mu"    0.08
          sigma = lookupParam q "sigma" 0.2
          n     = min 500 $ lookupInt q "n" 60
          seed  = lookupInt q "seed" 42
          stream = gbmStream s mu sigma seed
      in httpResponse 200 "application/json" (streamJson stream n)

  | otherwise =
      httpResponse 404 "application/json" "{\"error\":\"not found\"}"

serveClient :: Socket -> IO ()
serveClient conn = do
  reqBytes <- recv conn 4096
  let req   = B.unpack reqBytes
      (path, query) = parseRequest req
      resp  = handleRequest path query
  sendAll conn (B.pack resp)
  close conn

runServer :: Int -> IO ()
runServer port = do
  hSetBuffering stdout LineBuffering
  sock <- socket AF_INET Stream defaultProtocol
  setSocketOption sock ReuseAddr 1
  bind sock (SockAddrInet (fromIntegral port) 0)
  listen sock 128
  putStrLn $ "Haskell pricer listening on :" ++ show port
  loop sock
  where
    loop sock = do
      (conn, _) <- accept sock
      serveClient conn
      loop sock

main :: IO ()
main = runServer 8006
