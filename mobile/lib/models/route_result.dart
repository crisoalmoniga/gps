import 'package:latlong2/latlong.dart';

class RouteResult {
  final double distanceMeters;
  final double durationSeconds;
  final List<LatLng> points;
  final double avgRiskScore;
  final double avgCongestionPct;

  const RouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.points,
    this.avgRiskScore = 0.0,
    this.avgCongestionPct = 0.0,
  });

  factory RouteResult.fromJson(Map<String, dynamic> json) {
    final coords = (json['geometry'] as List)
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
    return RouteResult(
      distanceMeters: (json['distance_meters'] as num).toDouble(),
      durationSeconds: (json['duration_seconds'] as num).toDouble(),
      points: coords,
      avgRiskScore: (json['avg_risk_score'] as num?)?.toDouble() ?? 0.0,
      avgCongestionPct: (json['avg_congestion_pct'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
