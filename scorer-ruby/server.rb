# frozen_string_literal: true

# ============================================================
# Ruby 3.0 — 런타임 동적 리스크 DSL 엔진
# Port: 9004
# Uses: WEBrick (stdlib), zero external gems
#
# Ruby의 핵심 강점: instance_eval로 서버 재시작 없이
# 위험 규칙을 런타임에 코드로 동적 적재
# OCaml/F#/Haskell/Kotlin 등 컴파일 언어로는 불가능
#
# 엔드포인트:
#   GET  /health
#   GET  /api/ruby/ruleset    — 현재 활성 DSL 규칙 목록
#   POST /api/ruby/rules      — 새 규칙 런타임 등록 (instance_eval)
#   GET  /api/ruby/evaluate   — 모든 DSL 규칙 평가
#   GET  /api/ruby/score      — 신용 점수 + DSL 규칙 적용 결과
# ============================================================

require 'webrick'
require 'json'
require 'cgi'
require 'thread'

PORT = 9004

# ── DSL 엔진 ────────────────────────────────────────────────
# instance_eval을 통해 런타임에 rule(:name) { 조건 } 블록을
# 서버 재시작 없이 동적으로 적재합니다.
class RiskDSL
  attr_reader :rules, :loaded_at

  def initialize
    @rules     = {}
    @loaded_at = {}
  end

  # DSL 키워드: rule(:identifier) { 불리언 표현식 }
  def rule(name, &block)
    @rules[name.to_s] = block
    @loaded_at[name.to_s] = Time.now.strftime('%H:%M:%S')
  end

  # instance_eval로 DSL 소스를 적재 — 안전 검사 포함
  # rule(:name) { ... } 패턴만 허용 (다중 규칙 지원)
  def safe_load(source)
    stripped = source.strip
    # 각 줄이 rule(...) { ... } 형식인지 확인
    lines = stripped.split("\n").map(&:strip).reject(&:empty?)
    lines.each do |line|
      unless line.match?(/\Arule\(:\w+\)\s*\{.*\}\s*\z/)
        raise ArgumentError, "허용되지 않는 DSL 구문: #{line.inspect}\n" \
                             "rule(:name) { 조건 } 형식만 허용됩니다"
      end
    end
    instance_eval(stripped)
    @rules.size
  end

  # 컨텍스트 객체에 등록된 모든 규칙 평가
  def evaluate_all(ctx)
    @rules.transform_values do |blk|
      ctx.instance_exec(&blk)
    rescue StandardError => e
      "error: #{e.message}"
    end
  end
end

# ── 규칙 평가 컨텍스트 ─────────────────────────────────────
# instance_exec 안에서 이 속성들을 직접 참조합니다
class LoanContext
  attr_reader :debt_ratio, :ltv, :num_defaults, :annual_income_k

  def initialize(params)
    @debt_ratio      = params['debt_ratio'].to_f
    @ltv             = params['ltv'].to_f
    @num_defaults    = params['num_defaults'].to_i
    @annual_income_k = params['annual_income_k'].to_f
  end
end

# ── 규칙 저장소 (스레드 안전) ────────────────────────────────
RULE_MUTEX  = Mutex.new
RULE_ENGINE = RiskDSL.new

# 기본 내장 규칙 — 서버 시작 시 자동 적재
DEFAULT_RULES = <<~DSL.freeze
  rule(:high_ltv) { ltv > 0.85 }
  rule(:high_debt_burden) { debt_ratio > 0.70 }
  rule(:repeat_defaults) { num_defaults >= 2 }
  rule(:vip_client) { annual_income_k > 300 && num_defaults == 0 }
  rule(:auto_reject) { ltv > 0.90 && debt_ratio > 0.80 }
DSL
RULE_ENGINE.safe_load(DEFAULT_RULES)

# ── 신용 점수 모델 (기존 로직) ──────────────────────────────
def logistic(z) = 1.0 / (1.0 + Math.exp(-z))

SCORE_WEIGHTS = {
  'debt_ratio'      => -2.5,
  'ltv'             => -1.8,
  'num_defaults'    => -1.2,
  'annual_income_k' =>  0.8,
  'intercept'       =>  1.5
}.freeze

GRADE_THRESHOLDS = [
  [850, 'A+'], [750, 'A'], [650, 'B+'], [550, 'B'],
  [450, 'C'],  [350, 'C-'], [0, 'D']
].freeze

def credit_score(dr, ltv, nd, inc)
  z = SCORE_WEIGHTS['intercept'] +
      SCORE_WEIGHTS['debt_ratio']      * dr +
      SCORE_WEIGHTS['ltv']             * ltv +
      SCORE_WEIGHTS['num_defaults']    * nd +
      SCORE_WEIGHTS['annual_income_k'] * (inc / 100.0)
  pd    = logistic(-z)
  score = ((1.0 - pd) * 1000).round
  grade = GRADE_THRESHOLDS.find { |t, _| score >= t }&.last || 'D'
  { score: score, grade: grade, pd: pd.round(4) }
end

# ── HTTP 핸들러 ─────────────────────────────────────────────

def handle_ruleset
  RULE_MUTEX.synchronize do
    rules_list = RULE_ENGINE.rules.map do |name, _|
      { name: name, loaded_at: RULE_ENGINE.loaded_at[name] }
    end
    {
      total_rules: rules_list.size,
      rules:       rules_list,
      engine:      'Ruby 3.0 instance_eval DSL',
      note:        'POST /api/ruby/rules 로 서버 재시작 없이 규칙 추가 가능'
    }
  end
end

def handle_evaluate(query)
  p = CGI.parse(query)
  ctx = LoanContext.new(
    'debt_ratio'      => (p['debt_ratio']&.first || '0.4'),
    'ltv'             => (p['ltv']&.first || '0.6'),
    'num_defaults'    => (p['num_defaults']&.first || '0'),
    'annual_income_k' => (p['annual_income_k']&.first || '60')
  )
  results = RULE_MUTEX.synchronize { RULE_ENGINE.evaluate_all(ctx) }
  fired   = results.select { |_, v| v == true }.keys
  {
    evaluated:   results,
    fired_rules: fired,
    fired_count: fired.size,
    total_rules: results.size,
    inputs: {
      debt_ratio: ctx.debt_ratio, ltv: ctx.ltv,
      num_defaults: ctx.num_defaults, annual_income_k: ctx.annual_income_k
    },
    engine: 'Ruby 3.0 instance_eval DSL'
  }
end

def handle_score(query)
  p   = CGI.parse(query)
  dr  = (p['debt_ratio']&.first || '0.4').to_f
  ltv = (p['ltv']&.first || '0.6').to_f
  nd  = (p['num_defaults']&.first || '0').to_i
  inc = (p['annual_income_k']&.first || '60').to_f
  result = credit_score(dr, ltv, nd, inc)
  ctx = LoanContext.new(
    'debt_ratio' => dr.to_s, 'ltv' => ltv.to_s,
    'num_defaults' => nd.to_s, 'annual_income_k' => inc.to_s
  )
  dsl = RULE_MUTEX.synchronize { RULE_ENGINE.evaluate_all(ctx) }
  fired = dsl.select { |_, v| v == true }.keys
  result.merge(engine: 'Ruby 3.0 instance_eval DSL', dsl_rules: dsl, fired_rules: fired)
end

def handle_load_rules(body)
  RULE_MUTEX.synchronize do
    before = RULE_ENGINE.rules.size
    RULE_ENGINE.safe_load(body.to_s.strip)
    after  = RULE_ENGINE.rules.size
    { loaded: true, rules_before: before, rules_after: after,
      engine: 'Ruby 3.0 instance_eval DSL' }
  end
rescue ArgumentError, SyntaxError => e
  { loaded: false, error: e.message }
end

# ── WEBrick 서버 ────────────────────────────────────────────

server = WEBrick::HTTPServer.new(
  Port:      PORT,
  Logger:    WEBrick::Log.new('/dev/null'),
  AccessLog: []
)

server.mount_proc('/') do |req, res|
  res['Content-Type']                = 'application/json; charset=utf-8'
  res['Access-Control-Allow-Origin'] = '*'

  body = case req.path
         when '/health'
           { status: 'ok', service: 'ruby-dsl',
             version: RUBY_VERSION, active_rules: RULE_ENGINE.rules.size }.to_json
         when '/api/ruby/ruleset'
           handle_ruleset.to_json
         when '/api/ruby/evaluate'
           handle_evaluate(req.query_string || '').to_json
         when '/api/ruby/score'
           handle_score(req.query_string || '').to_json
         when '/api/ruby/rules'
           if req.request_method == 'POST'
             handle_load_rules(req.body).to_json
           else
             res.status = 405
             { error: 'POST required' }.to_json
           end
         else
           res.status = 404
           { error: 'not found' }.to_json
         end

  res.body = body
end

trap('INT')  { server.shutdown }
trap('TERM') { server.shutdown }

puts "Ruby #{RUBY_VERSION} DSL Engine listening on :#{PORT}"
puts "Active rules: #{RULE_ENGINE.rules.size} (instance_eval dynamic loading enabled)"
