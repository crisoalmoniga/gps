import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config.dart';

class GeocodingResult {
  final String displayName;
  final LatLng point;

  const GeocodingResult({required this.displayName, required this.point});
}

/// Geocodificacion de direcciones via Nominatim (gratis, sin API key) para
/// ayudar a ubicar el pin en el reporte retroactivo (seccion 0 del spec).
class GeocodingService {
  Future<List<GeocodingResult>> search(String query) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse('${AppConfig.nominatimBaseUrl}/search').replace(
      queryParameters: {
        'q': query,
        'format': 'json',
        'limit': '5',
        'countrycodes': 'ar',
        'viewbox': '-59.3,-34.2,-58.0,-35.3',
        'bounded': '1',
      },
    );

    final response = await http.get(
      uri,
      headers: {'User-Agent': 'RutaSegura/0.1 (app de navegacion AMBA)'},
    );
    if (response.statusCode != 200) {
      throw Exception('No se pudo buscar la direccion (${response.statusCode})');
    }

    final list = jsonDecode(response.body) as List;
    return list.map((e) {
      return GeocodingResult(
        displayName: e['display_name'] as String,
        point: LatLng(double.parse(e['lat']), double.parse(e['lon'])),
      );
    }).toList();
  }
}
