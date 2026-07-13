class IncidentReport {
  final int? id;
  final double lat;
  final double lon;
  final String? incidentType;
  final String? severity;
  final String? description;
  final bool isRetroactive;
  final DateTime? occurredAt;
  final DateTime? createdAt;

  const IncidentReport({
    this.id,
    required this.lat,
    required this.lon,
    this.incidentType,
    this.severity,
    this.description,
    this.isRetroactive = false,
    this.occurredAt,
    this.createdAt,
  });

  factory IncidentReport.fromJson(Map<String, dynamic> json) {
    return IncidentReport(
      id: json['id'] as int?,
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      incidentType: json['incident_type'] as String?,
      severity: json['severity'] as String?,
      description: json['description'] as String?,
      isRetroactive: json['is_retroactive'] as bool? ?? false,
      occurredAt: json['occurred_at'] != null
          ? DateTime.parse(json['occurred_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toCreateJson() {
    return {
      'lat': lat,
      'lon': lon,
      'is_retroactive': isRetroactive,
      if (occurredAt != null) 'occurred_at': occurredAt!.toIso8601String(),
    };
  }
}

/// Tipos de incidente sugeridos para el formulario de detalle opcional.
const List<String> kIncidentTypes = [
  'asalto',
  'robo_de_auto',
  'zona_oscura_sin_gente',
  'disturbio',
  'otro',
];

const List<String> kSeverityLevels = ['baja', 'media', 'alta'];
