# frozen_string_literal: true

# ============================================================
# Ruby 3.0 Credit Scoring Engine
# Port: 9004
# Uses: WEBrick (stdlib) — zero external gems
# Endpoints:
#   GET /health
#   GET /api/ruby/score   — credit scoring + risk tier
#   GET /api/ruby/summary — portfolio summary (n loans)
# ============================================================

require 'webrick'
require 'json'
require 'cgi'

PORT = 9004

# ---------- Math ----------

def clamp(x, lo, hi)
  [[x, lo].max, hi].min
end

def mean(arr)
  arr.sum.to_f / arr.size
end

def std_dev(arr)
  m = mean(arr)
  variance = arr.map { |x| (x - m)**2 }.sum / arr.size
  Math.sqrt(variance)
end

def percentile(arr, p)
  sorted = arr.sort
  idx = (p / 100.0 * sorted.size).floor
  sorted[clamp(idx, 0, sorted.size - 1)]
end

# Sigmoid / logistic
def logistic(z)
  1.0 / (1.0 + Math.exp(-z))
end

# ---------- Credit Scoring Model ----------
# Features: debt_ratio, ltv, num_defaults, annual_income_k (thousands)
# Returns: score 0-1000, grade A+..D, pd (probability of default)

WEIGHTS = {
  debt_ratio:       -2.5,
  ltv:              -1.8,
  num_defaults:     -1.2,
  annual_income_k:   0.8,
  intercept:         1.5
}.freeze

GRADE_THRESHOLDS = [
  [850, 'A+'],
  [750, 'A'],
  [650, 'B+'],
  [550, 'B'],
  [450, 'C'],
  [350, 'C-'],
  [0,   'D']
].freeze

def credit_score(debt_ratio, ltv, num_defaults, annual_income_k)
  z = WEIGHTS[:intercept] +
      WEIGHTS[:debt_ratio]       * debt_ratio +
      WEIGHTS[:ltv]              * ltv +
      WEIGHTS[:num_defaults]     * num_defaults +
      WEIGHTS[:annual_income_k]  * (annual_income_k / 100.0)

  pd = logistic(-z)   # probability of default (lower z → higher pd)
  score = ((1.0 - pd) * 1000).round

  grade = GRADE_THRESHOLDS.find { |thresh, _| score >= thresh }&.last || 'D'
  risk  = if score >= 750 then 'LOW'
          elsif score >= 550 then 'MEDIUM'
          elsif score >= 350 then 'HIGH'
          else 'CRITICAL'
          end

  { score: score, grade: grade, risk_tier: risk, pd: pd.round(4) }
end

# ---------- LCG pseudo-random ----------

def lcg_seq(seed, n)
  xs = []
  s  = seed
  n.times do
    s = (1_664_525 * s + 1_013_904_223) % (2**31)
    xs << s.to_f / (2**31)
  end
  xs
end

def gen_loan(rand_val, idx)
  seed2 = idx * 7 + 13
  r2 = (1_664_525 * seed2 + 1_013_904_223) % (2**31)
  r2 = r2.to_f / (2**31)

  debt_ratio      = 0.1 + rand_val * 0.7         # 0.1..0.8
  ltv             = 0.2 + r2 * 0.6               # 0.2..0.8
  num_defaults    = (rand_val * 3).round          # 0..3
  annual_income_k = 30 + (r2 * 120).round         # 30..150k

  credit_score(debt_ratio, ltv, num_defaults, annual_income_k)
    .merge(debt_ratio: debt_ratio.round(3),
           ltv: ltv.round(3),
           annual_income_k: annual_income_k)
end

# ---------- Handlers ----------

def handle_score(query)
  params = CGI.parse(query)
  debt_ratio      = (params['debt_ratio']&.first || '0.4').to_f
  ltv             = (params['ltv']&.first || '0.6').to_f
  num_defaults    = (params['num_defaults']&.first || '0').to_i
  annual_income_k = (params['annual_income_k']&.first || '60').to_f

  result = credit_score(debt_ratio, ltv, num_defaults, annual_income_k)
  result.merge(
    engine: 'Ruby 3.0 (WEBrick)',
    inputs: {
      debt_ratio: debt_ratio,
      ltv: ltv,
      num_defaults: num_defaults,
      annual_income_k: annual_income_k
    }
  )
end

def handle_summary(query)
  params = CGI.parse(query)
  n    = (params['n']&.first || '200').to_i.clamp(10, 2000)
  seed = (params['seed']&.first || '42').to_i

  randoms = lcg_seq(seed, n)
  loans   = randoms.each_with_index.map { |r, i| gen_loan(r, i) }

  scores = loans.map { |l| l[:score] }
  pds    = loans.map { |l| l[:pd] }

  grade_counts = loans.group_by { |l| l[:grade] }.transform_values(&:count)
  risk_counts  = loans.group_by { |l| l[:risk_tier] }.transform_values(&:count)

  {
    n: n,
    mean_score:    mean(scores).round(2),
    std_score:     std_dev(scores).round(2),
    p10_score:     percentile(scores, 10),
    p25_score:     percentile(scores, 25),
    p50_score:     percentile(scores, 50),
    p75_score:     percentile(scores, 75),
    p90_score:     percentile(scores, 90),
    mean_pd:       mean(pds).round(4),
    grade_dist:    grade_counts,
    risk_dist:     risk_counts,
    engine:        'Ruby 3.0 (WEBrick)'
  }
end

# ---------- WEBrick Server ----------

server = WEBrick::HTTPServer.new(
  Port:        PORT,
  Logger:      WEBrick::Log.new('/dev/null'),
  AccessLog:   []
)

server.mount_proc('/') do |req, res|
  path  = req.path
  query = req.query_string || ''

  res['Content-Type']                = 'application/json; charset=utf-8'
  res['Access-Control-Allow-Origin'] = '*'

  body = case path
         when '/health'
           { status: 'ok', service: 'ruby-scorer', version: RUBY_VERSION }.to_json
         when '/api/ruby/score'
           handle_score(query).to_json
         when '/api/ruby/summary'
           handle_summary(query).to_json
         else
           res.status = 404
           { error: 'not found' }.to_json
         end

  res.body = body
end

trap('INT')  { server.shutdown }
trap('TERM') { server.shutdown }

puts "Ruby #{RUBY_VERSION} scorer listening on :#{PORT}"
server.start
