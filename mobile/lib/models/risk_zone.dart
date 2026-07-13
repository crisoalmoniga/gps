class RiskZone {
  final int id;
  final double lat;
  final double lon;
  final int hourBucket;
  final double score;
  final double confidence;
  final String? category;
  final int incidentCount;

  const RiskZone({
    required this.id,
    required this.lat,
    required this.lon,
    required this.hourBucket,
    required this.score,
    required this.confidence,
    required this.category,
    required this.incidentCount,
  });

  factory RiskZone.fromJson(Map<String, dynamic> json) {
    return RiskZone(
      id: json['id'] as int,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      hourBucket: json['hour_bucket'] as int,
      score: (json['score'] as num).toDouble(),
      confidence: (json['confidence'] as num).toDouble(),
      category: json['category'] as String?,
      incidentCount: json['incident_count'] as int,
    );
  }
}
