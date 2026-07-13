import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart' show Position;
import 'package:latlong2/latlong.dart';

import '../models/incident_report.dart';
import '../models/risk_zone.dart';
import '../models/route_result.dart';
import '../models/trip_point_record.dart';
import '../services/api_service.dart';
import '../services/geocoding_service.dart';
import '../services/location_service.dart';
import '../widgets/report_detail_sheet.dart';

enum MapMode { ruta, reportarRetroactivo }

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const _fallbackCenter = LatLng(-34.6037, -58.3816); // Obelisco, CABA

  final _mapController = MapController();
  final _apiService = ApiService();
  final _locationService = LocationService();
  final _geocodingService = GeocodingService();
  final _searchController = TextEditingController(); // busqueda de direccion en modo "reportar"
  final _originController = TextEditingController();
  final _destinationController = TextEditingController();

  MapMode _mode = MapMode.ruta;
  LatLng? _currentLocation;

  /// Origen de la ruta. null significa "usar mi ubicacion actual" (el
  /// comportamiento por defecto); si el usuario busca o marca un origen
  /// distinto, se guarda aca.
  LatLng? _origin;
  LatLng? _destination;
  LatLng? _retroactivePin;
  RouteResult? _route;
  List<IncidentReport> _reports = [];
  List<RiskZone> _riskZones = [];
  bool _searching = false;

  // Pesos ajustables por el usuario (seccion 4 del spec). En Fase 3, el
  // copiloto conversacional podra ajustar estos mismos valores.
  double _pesoSeguridad = 1.0;
  double _pesoCongestion = 1.0;

  bool _isNavigating = false;
  String? _tripId;
  final List<TripPointRecord> _tripBuffer = [];
  StreamSubscription<Position>? _positionSubscription;

  @override
  void initState() {
    super.initState();
    _initLocation();
    _loadReports();
    _loadRiskZones();
  }

  Future<void> _initLocation() async {
    try {
      final location = await _locationService.getCurrentLocation();
      if (!mounted) return;
      setState(() => _currentLocation = location);
      _mapController.move(location, 15);
    } catch (_) {
      // Sin permiso o sin GPS: seguimos con el centro por defecto.
    }
  }

  Future<void> _loadReports() async {
    try {
      final reports = await _apiService.fetchReports();
      if (!mounted) return;
      setState(() => _reports = reports);
    } catch (_) {
      // Falla silenciosa: los reportes son un plus visual, no bloquean el uso del mapa.
    }
  }

  Future<void> _loadRiskZones() async {
    try {
      final zones = await _apiService.fetchRiskZones();
      if (!mounted) return;
      setState(() => _riskZones = zones);
    } catch (_) {
      // Falla silenciosa: es una capa informativa (Capa A de Claude), no bloquea el mapa.
    }
  }

  Future<void> _handleOriginSearch(String query) async {
    if (query.trim().isEmpty) return;
    final point = await _geocodeOrNull(query);
    if (point == null) return;
    setState(() => _origin = point);
    await _calculateRoute();
  }

  Future<void> _handleDestinationSearch(String query) async {
    if (query.trim().isEmpty) return;
    final point = await _geocodeOrNull(query);
    if (point == null) return;
    setState(() => _destination = point);
    await _calculateRoute();
  }

  Future<void> _handleRetroactiveSearch(String query) async {
    if (query.trim().isEmpty) return;
    final point = await _geocodeOrNull(query);
    if (point == null) return;
    setState(() => _retroactivePin = point);
    _mapController.move(point, 16);
  }

  Future<LatLng?> _geocodeOrNull(String query) async {
    setState(() => _searching = true);
    try {
      final results = await _geocodingService.search(query);
      if (results.isEmpty) {
        _showSnackBar('No se encontro esa direccion');
        return null;
      }
      return results.first.point;
    } catch (e) {
      _showSnackBar('Error buscando direccion: $e');
      return null;
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _resetOriginToCurrentLocation() {
    setState(() {
      _origin = null;
      _originController.clear();
    });
    _calculateRoute();
  }

  Future<void> _calculateRoute() async {
    final origin = _origin ?? _currentLocation;
    if (origin == null || _destination == null) return;
    try {
      final route = await _apiService.fetchRoute(
        from: origin,
        to: _destination!,
        pesoSeguridad: _pesoSeguridad,
        pesoCongestion: _pesoCongestion,
      );
      if (!mounted) return;
      setState(() => _route = route);
      _fitToPoints(route.points);
    } catch (e) {
      _showSnackBar('No se pudo calcular la ruta (¿el backend esta desplegado y accesible?): $e');
      // Aunque falle el calculo de ruta, centramos el mapa para que origen y
      // destino sean visibles (si no, el pin de destino puede quedar fuera
      // de la vista actual y parecer que "no paso nada").
      _fitToPoints([origin, _destination!]);
    }
  }

  void _fitToPoints(List<LatLng> points) {
    if (points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.first, 15);
      return;
    }
    _mapController.fitCamera(
      CameraFit.bounds(bounds: LatLngBounds.fromPoints(points), padding: const EdgeInsets.all(60)),
    );
  }

  Future<void> _startNavigation() async {
    if (_route == null) return;
    final tripId = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _isNavigating = true;
      _tripId = tripId;
      _tripBuffer.clear();
    });

    try {
      _positionSubscription = _locationService.watchPositions().listen((position) {
        if (!mounted) return;
        setState(() => _currentLocation = LatLng(position.latitude, position.longitude));
        _tripBuffer.add(TripPointRecord(
          lat: position.latitude,
          lon: position.longitude,
          speedKmh: position.speed * 3.6,
          recordedAt: DateTime.now(),
        ));
      });
      _showSnackBar('Viaje iniciado: grabando velocidad para mejorar los datos de congestion.');
    } catch (e) {
      setState(() => _isNavigating = false);
      _showSnackBar('No se pudo iniciar la grabacion del viaje: $e');
    }
  }

  Future<void> _stopNavigation() async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

    final tripId = _tripId;
    final points = List<TripPointRecord>.from(_tripBuffer);
    setState(() {
      _isNavigating = false;
      _tripId = null;
      _tripBuffer.clear();
      _route = null;
      _origin = null;
      _destination = null;
      _originController.clear();
      _destinationController.clear();
    });

    if (tripId != null && points.isNotEmpty) {
      try {
        await _apiService.uploadTrip(tripId: tripId, points: points);
        _showSnackBar('Trayecto guardado (${points.length} puntos de velocidad).');
      } catch (e) {
        _showSnackBar('No se pudo subir el historial del trayecto: $e');
      }
    }
  }

  void _handleMapTap(TapPosition tapPosition, LatLng point) {
    if (_mode == MapMode.reportarRetroactivo) {
      setState(() => _retroactivePin = point);
      return;
    }
    // Modo ruta: un tap fija el destino (igual que en Waze/Google Maps).
    setState(() {
      _destination = point;
      _destinationController.clear();
    });
    _calculateRoute();
  }

  void _handleMapLongPress(TapPosition tapPosition, LatLng point) {
    if (_mode != MapMode.ruta) return;
    // Mantener presionado fija el origen, para no pisar el gesto de tap = destino.
    setState(() {
      _origin = point;
      _originController.clear();
    });
    _calculateRoute();
  }

  Future<void> _submitOneTapReport() async {
    if (_currentLocation == null) {
      _showSnackBar('No se pudo obtener tu ubicacion todavia');
      return;
    }
    await _createReportAndOfferDetail(point: _currentLocation!, retroactive: false);
  }

  Future<void> _confirmRetroactiveReport() async {
    if (_retroactivePin == null) return;
    await _createReportAndOfferDetail(point: _retroactivePin!, retroactive: true);
    setState(() {
      _retroactivePin = null;
      _mode = MapMode.ruta;
    });
  }

  Future<void> _createReportAndOfferDetail({required LatLng point, required bool retroactive}) async {
    try {
      final report = await _apiService.createReport(
        lat: point.latitude,
        lon: point.longitude,
        isRetroactive: retroactive,
      );
      _showSnackBar('Reporte guardado. Gracias por avisar.');
      await _loadReports();

      if (!mounted) return;
      final detail = await showReportDetailSheet(context);
      if (detail != null && report.id != null) {
        await _apiService.addReportDetail(
          report.id!,
          incidentType: detail.incidentType,
          severity: detail.severity,
          description: detail.description,
        );
        await _loadReports();
      }
    } catch (e) {
      _showSnackBar('No se pudo guardar el reporte: $e');
    }
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final center = _currentLocation ?? _fallbackCenter;

    return Scaffold(
      appBar: AppBar(title: const Text('RutaSegura')),
      body: Column(
        children: [
          _buildModeToggle(),
          if (_mode == MapMode.ruta && !_isNavigating) _buildRouteSearchFields(),
          if (_mode == MapMode.reportarRetroactivo) _buildRetroactiveSearchBar(),
          if (_mode == MapMode.ruta && !_isNavigating) _buildWeightSliders(),
          if (_mode == MapMode.ruta && _route != null) _buildRouteInfoBar(),
          if (_mode == MapMode.reportarRetroactivo) _buildRetroactiveBanner(),
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: center,
                    initialZoom: 14,
                    onTap: _handleMapTap,
                    onLongPress: _handleMapLongPress,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.rutasegura.app',
                    ),
                    CircleLayer(circles: _buildRiskCircles()),
                    if (_route != null)
                      PolylineLayer(polylines: [
                        Polyline(points: _route!.points, strokeWidth: 5, color: Colors.blue),
                      ]),
                    MarkerLayer(markers: _buildMarkers()),
                  ],
                ),
                Positioned(
                  right: 16,
                  bottom: 16 + MediaQuery.of(context).padding.bottom,
                  child: FloatingActionButton.extended(
                    heroTag: 'one_tap_report',
                    onPressed: _submitOneTapReport,
                    backgroundColor: Colors.red,
                    icon: const Icon(Icons.warning_amber_rounded),
                    label: const Text('Esto se siente inseguro'),
                  ),
                ),
                Positioned(
                  left: 16,
                  bottom: 16 + MediaQuery.of(context).padding.bottom,
                  child: FloatingActionButton(
                    heroTag: 'recenter',
                    onPressed: _initLocation,
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    if (_currentLocation != null) {
      markers.add(Marker(
        point: _currentLocation!,
        width: 40,
        height: 40,
        child: const Icon(Icons.navigation, color: Colors.blue, size: 32),
      ));
    }

    if (_origin != null) {
      markers.add(Marker(
        point: _origin!,
        width: 40,
        height: 40,
        child: const Icon(Icons.trip_origin, color: Colors.purple, size: 32),
      ));
    }

    if (_destination != null) {
      markers.add(Marker(
        point: _destination!,
        width: 40,
        height: 40,
        child: const Icon(Icons.location_on, color: Colors.green, size: 36),
      ));
    }

    if (_retroactivePin != null) {
      markers.add(Marker(
        point: _retroactivePin!,
        width: 40,
        height: 40,
        child: const Icon(Icons.push_pin, color: Colors.orange, size: 36),
      ));
    }

    for (final report in _reports) {
      markers.add(Marker(
        point: LatLng(report.lat, report.lon),
        width: 28,
        height: 28,
        child: Icon(
          Icons.circle,
          color: Colors.red.withOpacity(0.7),
          size: 16,
        ),
      ));
    }

    return markers;
  }

  List<CircleMarker> _buildRiskCircles() {
    return _riskZones.map((zone) {
      final color = _riskColor(zone.score);
      return CircleMarker(
        point: LatLng(zone.lat, zone.lon),
        radius: 60,
        useRadiusInMeter: true,
        color: color.withOpacity(0.25),
        borderColor: color,
        borderStrokeWidth: 2,
      );
    }).toList();
  }

  Color _riskColor(double score) {
    if (score >= 70) return Colors.red;
    if (score >= 40) return Colors.orange;
    return Colors.yellow.shade700;
  }

  Widget _buildWeightSliders() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, size: 18),
              Expanded(
                child: Slider(
                  value: _pesoSeguridad,
                  min: 0,
                  max: 3,
                  divisions: 6,
                  label: 'Priorizar seguridad: ${_pesoSeguridad.toStringAsFixed(1)}',
                  onChanged: (value) => setState(() => _pesoSeguridad = value),
                  onChangeEnd: (_) => _calculateRoute(),
                ),
              ),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.traffic_outlined, size: 18),
              Expanded(
                child: Slider(
                  value: _pesoCongestion,
                  min: 0,
                  max: 3,
                  divisions: 6,
                  label: 'Evitar congestion: ${_pesoCongestion.toStringAsFixed(1)}',
                  onChanged: (value) => setState(() => _pesoCongestion = value),
                  onChangeEnd: (_) => _calculateRoute(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRouteInfoBar() {
    final route = _route!;
    final minutes = (route.durationSeconds / 60).round();
    final km = (route.distanceMeters / 1000).toStringAsFixed(1);

    return Container(
      width: double.infinity,
      color: Colors.blue.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$km km · ~$minutes min · riesgo prom. ${route.avgRiskScore.toStringAsFixed(0)}/100',
            ),
          ),
          if (!_isNavigating)
            FilledButton(onPressed: _startNavigation, child: const Text('Iniciar viaje'))
          else
            OutlinedButton(onPressed: _stopNavigation, child: const Text('Finalizar viaje')),
        ],
      ),
    );
  }

  Widget _buildModeToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SegmentedButton<MapMode>(
        segments: const [
          ButtonSegment(value: MapMode.ruta, label: Text('Ruta'), icon: Icon(Icons.map)),
          ButtonSegment(
            value: MapMode.reportarRetroactivo,
            label: Text('Reportar en el mapa'),
            icon: Icon(Icons.push_pin_outlined),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (selection) {
          setState(() {
            _mode = selection.first;
            _retroactivePin = null;
          });
        },
      ),
    );
  }

  Widget _buildRouteSearchFields() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          TextField(
            controller: _originController,
            decoration: InputDecoration(
              hintText: 'Origen: mi ubicacion actual',
              prefixIcon: const Icon(Icons.trip_origin, color: Colors.purple),
              suffixIcon: _origin != null
                  ? IconButton(
                      icon: const Icon(Icons.my_location),
                      tooltip: 'Usar mi ubicacion actual',
                      onPressed: _resetOriginToCurrentLocation,
                    )
                  : null,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: _handleOriginSearch,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _destinationController,
            decoration: InputDecoration(
              hintText: 'Destino',
              prefixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : const Icon(Icons.location_on, color: Colors.green),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: _handleDestinationSearch,
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Tip: toca el mapa para el destino, mantene presionado para el origen.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRetroactiveSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Buscar direccion del incidente...',
          prefixIcon: _searching
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : const Icon(Icons.search),
          border: const OutlineInputBorder(),
        ),
        onSubmitted: _handleRetroactiveSearch,
      ),
    );
  }

  Widget _buildRetroactiveBanner() {
    return Container(
      width: double.infinity,
      color: Colors.orange.shade100,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Expanded(
            child: Text('Toca el mapa (o busca una direccion) para marcar donde paso algo.'),
          ),
          if (_retroactivePin != null)
            FilledButton(
              onPressed: _confirmRetroactiveReport,
              child: const Text('Confirmar'),
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _originController.dispose();
    _destinationController.dispose();
    _positionSubscription?.cancel();
    super.dispose();
  }
}
