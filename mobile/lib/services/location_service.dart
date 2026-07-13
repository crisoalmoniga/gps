import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  Future<LatLng> getCurrentLocation() async {
    final permission = await _ensurePermission();
    if (!permission) {
      throw Exception('Permiso de ubicacion denegado');
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    return LatLng(position.latitude, position.longitude);
  }

  Stream<LatLng> watchLocation() async* {
    yield* watchPositions().map((position) => LatLng(position.latitude, position.longitude));
  }

  /// Stream de posiciones crudas (incluye velocidad en m/s), usado para
  /// grabar el historial de congestion de un trayecto (seccion 5 del spec).
  Stream<Position> watchPositions() async* {
    final permission = await _ensurePermission();
    if (!permission) {
      throw Exception('Permiso de ubicacion denegado');
    }

    yield* Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    );
  }

  Future<bool> _ensurePermission() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}
