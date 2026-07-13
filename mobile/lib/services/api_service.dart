import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config.dart';
import '../models/incident_report.dart';
import '../models/route_result.dart';

class ApiService {
  final String baseUrl;

  ApiService({String? baseUrl}) : baseUrl = baseUrl ?? AppConfig.apiBaseUrl;

  Future<IncidentReport> createReport({
    required double lat,
    required double lon,
    bool isRetroactive = false,
    DateTime? occurredAt,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reports'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'lat': lat,
        'lon': lon,
        'is_retroactive': isRetroactive,
        if (occurredAt != null) 'occurred_at': occurredAt.toIso8601String(),
      }),
    );
    if (response.statusCode != 201) {
      throw Exception('No se pudo crear el reporte (${response.statusCode})');
    }
    return IncidentReport.fromJson(jsonDecode(response.body));
  }

  Future<void> addReportDetail(
    int reportId, {
    String? incidentType,
    String? severity,
    String? description,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/reports/$reportId'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (incidentType != null) 'incident_type': incidentType,
        if (severity != null) 'severity': severity,
        if (description != null) 'description': description,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('No se pudo guardar el detalle (${response.statusCode})');
    }
  }

  Future<List<IncidentReport>> fetchReports({LatLngBounds? bounds}) async {
    final params = <String, String>{};
    if (bounds != null) {
      params['min_lat'] = bounds.southWest.latitude.toString();
      params['min_lon'] = bounds.southWest.longitude.toString();
      params['max_lat'] = bounds.northEast.latitude.toString();
      params['max_lon'] = bounds.northEast.longitude.toString();
    }
    final uri = Uri.parse('$baseUrl/reports').replace(queryParameters: params);
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('No se pudieron cargar los reportes (${response.statusCode})');
    }
    final list = jsonDecode(response.body) as List;
    return list.map((e) => IncidentReport.fromJson(e)).toList();
  }

  Future<RouteResult> fetchRoute({required LatLng from, required LatLng to}) async {
    final uri = Uri.parse('$baseUrl/route').replace(queryParameters: {
      'from_lat': from.latitude.toString(),
      'from_lon': from.longitude.toString(),
      'to_lat': to.latitude.toString(),
      'to_lon': to.longitude.toString(),
    });
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('No se pudo calcular la ruta (${response.statusCode})');
    }
    return RouteResult.fromJson(jsonDecode(response.body));
  }
}
