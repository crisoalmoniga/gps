class TripPointRecord {
  final double lat;
  final double lon;
  final double speedKmh;
  final DateTime recordedAt;

  const TripPointRecord({
    required this.lat,
    required this.lon,
    required this.speedKmh,
    required this.recordedAt,
  });

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'speed_kmh': speedKmh,
        // Explicito a UTC: DateTime.now() es hora local del dispositivo y
        // toIso8601String() no incluye offset, lo que seria ambiguo para
        // el backend al calcular la hora del dia en AMBA.
        'recorded_at': recordedAt.toUtc().toIso8601String(),
      };
}
