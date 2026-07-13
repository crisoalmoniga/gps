class AppConfig {
  /// URL base del backend. En el emulador de Android, 10.0.2.2 apunta al
  /// localhost de la maquina host. Pasar --dart-define=API_BASE_URL=... para
  /// apuntar a un servidor real (ej. la VM de Oracle Cloud).
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8000',
  );

  static const String nominatimBaseUrl = 'https://nominatim.openstreetmap.org';
}
