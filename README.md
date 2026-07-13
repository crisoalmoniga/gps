# RutaSegura

App de navegación tipo Waze para AMBA que combina tiempo de viaje, seguridad
(zonas de riesgo reportadas por usuarios) y congestión predictiva. Ver la
especificación completa en [`docs/spec.md`](docs/spec.md).

Este repo implementa la **Fase 1 (MVP)**: mapa + ruteo estándar sobre AMBA,
reporte de zonas de riesgo de 1 tap (con opción retroactiva), y el backend
que lo sostiene. Las capas de Claude (clasificación automática de riesgo,
copiloto conversacional) llegan en las fases 2 y 3, ver sección 7 del spec.

## Estructura del repo

```
backend/   API en FastAPI (reportes de incidentes + proxy de ruteo a OSRM)
infra/     docker-compose (Postgres+PostGIS, OSRM) + script de datos de AMBA
mobile/    App Flutter (mapa, GPS, ruteo, reporte 1 tap/retroactivo)
docs/      Especificación del proyecto
```

## Backend + infraestructura

Requiere Docker.

1. Generar los datos de ruteo de OSRM para AMBA (una sola vez, tarda varios
   minutos y descarga ~200MB del extracto de Argentina):

   ```bash
   ./infra/osrm/prepare_data.sh
   ```

2. Levantar todo el stack:

   ```bash
   cd infra
   docker compose up --build
   ```

   Esto levanta:
   - `postgres` (PostgreSQL + PostGIS) en `localhost:5432`
   - `osrm` (motor de ruteo) en `localhost:5001`
   - `backend` (API FastAPI) en `localhost:8000`

3. Verificar que responde: `curl http://localhost:8000/health`

### Endpoints principales

- `POST /reports` — crea un reporte de riesgo con solo `lat`/`lon` (botón de 1 tap).
- `PATCH /reports/{id}` — agrega detalle opcional (tipo, gravedad, descripción).
- `GET /reports?min_lat=&min_lon=&max_lat=&max_lon=` — lista reportes (para pintar el mapa).
- `GET /route?from_lat=&from_lon=&to_lat=&to_lon=` — ruta estándar (proxy a OSRM).

## App móvil (Flutter)

El código Dart está en `mobile/lib/`. Como este entorno no tiene el SDK de
Flutter instalado, los proyectos de plataforma (`android/`, `ios/`, etc.) no
están generados todavía. Para correr la app en tu máquina con Flutter
instalado:

```bash
cd mobile
flutter create .          # genera android/ios/etc. sin tocar lib/ ni pubspec.yaml
flutter pub get
```

Después, agregá los permisos de ubicación en `android/app/src/main/AndroidManifest.xml`
(dentro de `<manifest>`, antes de `<application>`):

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
```

Correr contra el backend local (emulador Android usa `10.0.2.2` para llegar
al localhost del host):

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

Para apuntar a un backend real (ej. la VM de Oracle Cloud), pasar su URL en
`API_BASE_URL`.

## Deploy de referencia (fases siguientes)

- **Motor de ruteo + backend**: Oracle Cloud free tier (VM gratuita
  indefinida), corriendo el mismo `docker-compose.yml` de `infra/`.
- **Distribución a los primeros 4 usuarios**: Firebase App Distribution
  (gratis, sin pasar por Google Play).

## Qué falta (fuera de alcance de este MVP)

Según la sección 9 del spec, quedan como tareas de implementación (no de
diseño) para fases posteriores:

- Seleccionar las cuentas de X/Twitter a monitorear (sección 5.1).
- Confirmar los límites exactos del free tier de Oracle Cloud.
- Capa A de Claude (clasificación de riesgo, perfiles de congestión).
- Capa B de Claude (copiloto conversacional con tool use).
