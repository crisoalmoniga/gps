import 'package:latlong2/latlong.dart';

class RouteResult {
  final double distanceMeters;
  final double durationSeconds;
  final List<LatLng> points;

  const RouteResult({
    required this.distanceMeters,
    required this.durationSeconds,
    required this.points,
  });

  factory RouteResult.fromJson(Map<String, dynamic> json) {
    final coords = (json['geometry'] as List)
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
    return RouteResult(
      distanceMeters: (json['distance_meters'] as num).toDouble(),
      durationSeconds: (json['duration_seconds'] as num).toDouble(),
      points: coords,
    );
  }
}
