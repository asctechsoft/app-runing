import 'dart:math' as math;

const double _earthRadiusM = 6371008.8;

double _rad(double deg) => deg * math.pi / 180.0;

/// Khoảng cách Haversine (mét).
double haversineM(double lat1, double lon1, double lat2, double lon2) {
  final dLat = _rad(lat2 - lat1);
  final dLon = _rad(lon2 - lon1);
  final a = math.sin(dLat / 2) * math.sin(dLat / 2) + math.cos(_rad(lat1)) * math.cos(_rad(lat2)) * math.sin(dLon / 2) * math.sin(dLon / 2);
  return 2 * _earthRadiusM * math.asin(math.min(1.0, math.sqrt(a)));
}

/// Điểm cách [lat],[lon] một khoảng [distanceM] theo hướng [bearingDeg]. Dùng cho fixture test và cắt tuyến.
(double, double) offsetPoint(double lat, double lon, double distanceM, double bearingDeg) {
  final d = distanceM / _earthRadiusM;
  final b = _rad(bearingDeg);
  final la1 = _rad(lat);
  final lo1 = _rad(lon);
  final la2 = math.asin(math.sin(la1) * math.cos(d) + math.cos(la1) * math.sin(d) * math.cos(b));
  final lo2 = lo1 + math.atan2(math.sin(b) * math.sin(d) * math.cos(la1), math.cos(d) - math.sin(la1) * math.sin(la2));
  return (la2 * 180 / math.pi, lo2 * 180 / math.pi);
}
