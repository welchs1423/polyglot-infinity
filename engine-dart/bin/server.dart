// ============================================================
// Dart 3.11 Yield Curve & Bond Pricing Engine
// Port: 9005
// Uses: dart:io HttpServer — zero external packages
// Endpoints:
//   GET /health
//   GET /api/dart/bond     — bond price + duration + convexity
//   GET /api/dart/yieldcurve — Nelson-Siegel yield curve + spread
// ============================================================

import 'dart:io';
import 'dart:convert';
import 'dart:math';

// ---------- Math helpers ----------

double clamp(double x, double lo, double hi) =>
    x < lo ? lo : (x > hi ? hi : x);

double mean(List<double> xs) =>
    xs.isEmpty ? 0.0 : xs.reduce((a, b) => a + b) / xs.length;

double stdDev(List<double> xs) {
  if (xs.length < 2) return 0.0;
  final m = mean(xs);
  final v = xs.map((x) => (x - m) * (x - m)).reduce((a, b) => a + b) / xs.length;
  return sqrt(v);
}

// ---------- Bond Pricing ----------

double bondPrice(double faceValue, double couponRate, double ytm, int periods) {
  final c = faceValue * couponRate / 2; // semi-annual coupon
  final r = ytm / 2;
  var pv = 0.0;
  for (var t = 1; t <= periods; t++) {
    pv += c / pow(1 + r, t);
  }
  pv += faceValue / pow(1 + r, periods);
  return pv;
}

// Macaulay Duration (in semi-annual periods / 2 = years)
double macaulayDuration(
    double faceValue, double couponRate, double ytm, int periods) {
  final c = faceValue * couponRate / 2;
  final r = ytm / 2;
  final price = bondPrice(faceValue, couponRate, ytm, periods);
  var weightedTime = 0.0;
  for (var t = 1; t <= periods; t++) {
    final pv = c / pow(1 + r, t);
    weightedTime += (t / 2.0) * pv / price;
  }
  weightedTime += (periods / 2.0) * (faceValue / pow(1 + r, periods)) / price;
  return weightedTime;
}

// Modified Duration
double modifiedDuration(
    double faceValue, double couponRate, double ytm, int periods) {
  final mac = macaulayDuration(faceValue, couponRate, ytm, periods);
  return mac / (1 + ytm / 2);
}

// Convexity (semi-annual)
double convexity(
    double faceValue, double couponRate, double ytm, int periods) {
  final c = faceValue * couponRate / 2;
  final r = ytm / 2;
  final price = bondPrice(faceValue, couponRate, ytm, periods);
  var conv = 0.0;
  for (var t = 1; t <= periods; t++) {
    final pv = c / pow(1 + r, t);
    conv += t * (t + 1) * pv / (price * pow(1 + r, 2));
  }
  final pvFace = faceValue / pow(1 + r, periods);
  conv += periods * (periods + 1) * pvFace / (price * pow(1 + r, 2));
  return conv / 4.0; // convert to annual
}

// ---------- Nelson-Siegel Yield Curve ----------
// y(t) = b0 + b1*(1-exp(-t/tau))/(t/tau) + b2*((1-exp(-t/tau))/(t/tau) - exp(-t/tau))

double nelsonSiegel(
    double t, double b0, double b1, double b2, double tau) {
  if (t <= 0) return b0;
  final u = t / tau;
  final factor = (1 - exp(-u)) / u;
  return b0 + b1 * factor + b2 * (factor - exp(-u));
}

// ---------- Spread analysis ----------
// Simple credit spread: OAS approximation via parallel yield shift

double creditSpread(double govtYtm, double corpCoupon, double faceValue,
    double corpPrice, int periods) {
  // Binary search for corp YTM
  var lo = 0.0001, hi = 0.5;
  for (var i = 0; i < 64; i++) {
    final mid = (lo + hi) / 2;
    if (bondPrice(faceValue, corpCoupon, mid, periods) > corpPrice) {
      lo = mid;
    } else {
      hi = mid;
    }
  }
  final corpYtm = (lo + hi) / 2;
  return corpYtm - govtYtm;
}

// ---------- Parse query params ----------

Map<String, String> parseQuery(String query) {
  final result = <String, String>{};
  if (query.isEmpty) return result;
  for (final pair in query.split('&')) {
    final parts = pair.split('=');
    if (parts.length == 2) {
      result[parts[0]] = Uri.decodeComponent(parts[1]);
    }
  }
  return result;
}

double qd(Map<String, String> q, String key, double def) {
  final v = q[key];
  if (v == null) return def;
  return double.tryParse(v) ?? def;
}

int qi(Map<String, String> q, String key, int def) {
  final v = q[key];
  if (v == null) return def;
  return int.tryParse(v) ?? def;
}

// ---------- Request handlers ----------

Map<String, dynamic> handleBond(String query) {
  final q = parseQuery(query);
  final face = qd(q, 'face', 1000.0);
  final coupon = qd(q, 'coupon', 0.05);
  final ytm = qd(q, 'ytm', 0.06);
  final years = qi(q, 'years', 10);
  final periods = years * 2; // semi-annual

  final price = bondPrice(face, coupon, ytm, periods);
  final macDur = macaulayDuration(face, coupon, ytm, periods);
  final modDur = modifiedDuration(face, coupon, ytm, periods);
  final conv = convexity(face, coupon, ytm, periods);
  // DV01: price change for 1bp ytm shift
  final dv01 = (bondPrice(face, coupon, ytm - 0.0001, periods) -
                bondPrice(face, coupon, ytm + 0.0001, periods)) /
               2.0;

  return {
    'price': double.parse(price.toStringAsFixed(4)),
    'macaulay_duration': double.parse(macDur.toStringAsFixed(4)),
    'modified_duration': double.parse(modDur.toStringAsFixed(4)),
    'convexity': double.parse(conv.toStringAsFixed(4)),
    'dv01': double.parse(dv01.toStringAsFixed(4)),
    'ytm': ytm,
    'coupon_rate': coupon,
    'face_value': face,
    'years': years,
    'engine': 'Dart 3.11 (dart:io)',
  };
}

Map<String, dynamic> handleYieldCurve(String query) {
  final q = parseQuery(query);
  // Nelson-Siegel params (typical US treasury shape)
  final b0 = qd(q, 'b0', 0.045); // long-run level
  final b1 = qd(q, 'b1', -0.02); // slope
  final b2 = qd(q, 'b2', 0.01);  // curvature
  final tau = qd(q, 'tau', 2.0);  // decay factor

  final maturities = [0.25, 0.5, 1.0, 2.0, 3.0, 5.0, 7.0, 10.0, 20.0, 30.0];
  final yields = maturities
      .map((t) => double.parse(
          nelsonSiegel(t, b0, b1, b2, tau).toStringAsFixed(5)))
      .toList();

  // 10Y - 2Y spread (key recession indicator)
  final y2y = nelsonSiegel(2.0, b0, b1, b2, tau);
  final y10y = nelsonSiegel(10.0, b0, b1, b2, tau);
  final spread10_2 = y10y - y2y;

  // 30Y - 3M spread
  final y3m = nelsonSiegel(0.25, b0, b1, b2, tau);
  final y30y = nelsonSiegel(30.0, b0, b1, b2, tau);
  final spread30_3m = y30y - y3m;

  return {
    'maturities': maturities,
    'yields': yields,
    'spread_10y_2y': double.parse(spread10_2.toStringAsFixed(5)),
    'spread_30y_3m': double.parse(spread30_3m.toStringAsFixed(5)),
    'curve_shape': spread10_2 > 0 ? 'normal' : 'inverted',
    'b0': b0,
    'b1': b1,
    'b2': b2,
    'tau': tau,
    'engine': 'Dart 3.11 (dart:io)',
  };
}

// ---------- HTTP Server ----------

void cors(HttpResponse res) {
  res.headers.add('Access-Control-Allow-Origin', '*');
  res.headers.contentType = ContentType.json;
}

Future<void> main() async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 9005);
  print('Dart ${Platform.version.split(' ').first} yield-curve engine on :9005');

  await for (final req in server) {
    final res = req.response;
    cors(res);

    final path = req.uri.path;
    final query = req.uri.query;

    try {
      Map<String, dynamic> body;
      if (path == '/health') {
        body = {
          'status': 'ok',
          'service': 'dart-yieldcurve',
          'version': 'Dart 3.11'
        };
      } else if (path == '/api/dart/bond') {
        body = handleBond(query);
      } else if (path == '/api/dart/yieldcurve') {
        body = handleYieldCurve(query);
      } else {
        res.statusCode = 404;
        body = {'error': 'not found'};
      }
      res.write(jsonEncode(body));
    } catch (e) {
      res.statusCode = 500;
      res.write(jsonEncode({'error': e.toString()}));
    }
    await res.close();
  }
}
