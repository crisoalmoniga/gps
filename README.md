# RutaSegura

App de navegación tipo Waze para AMBA que combina tiempo de viaje, seguridad
(zonas de riesgo reportadas por usuarios) y congestión predictiva. Ver la
especificación completa en [`docs/spec.md`](docs/spec.md).

Este repo implementa las **Fases 1 y 2** (ver sección 7 del spec):

- **Fase 1 — MVP**: mapa + ruteo estándar sobre AMBA, reporte de zonas de
  riesgo de 1 tap con opción retroactiva.
- **Fase 2 — Capa A de Claude**: clasificación automática de reportes de
  texto en scores de riesgo, perfiles de congestión calculados desde
  trayectos reales, y el pipeline + scraper para menciones de X.

La **Fase 3 (Capa B — copiloto conversacional)** queda pendiente.

## Estructura del repo

```
backend/   API en FastAPI (reportes, ruteo, Capa A de Claude, menciones, trayectos)
infra/     docker-compose (Postgres+PostGIS, OSRM) + script de datos de AMBA + cron
scraper/   Microservicio aislado que sigue cuentas de X (seccion 5.1 del spec)
mobile/    App Flutter (mapa, GPS, ruteo con pesos ajustables, reportes, grabacion de viaje)
docs/      Especificación del proyecto
```

## Backend + infraestructura

Requiere Docker.

1. Generar los datos de ruteo de OSRM para AMBA (una sola vez, tarda varios
   minutos y descarga ~200MB del extracto de Argentina):

   ```bash
   ./infra/osrm/prepare_data.sh
   ```

2. (Opcional pero necesario para la Capa A de Claude) definir la API key:

   ```bash
   export ANTHROPIC_API_KEY=sk-ant-...
   ```

3. Levantar el stack:

   ```bash
   cd infra
   docker compose up --build
   ```

   Esto levanta:
   - `postgres` (PostgreSQL + PostGIS) — solo accesible desde otros
     contenedores de la red interna, no publicado al host.
   - `osrm` (motor de ruteo) — idem, solo lo consume `backend` internamente.
   - `backend` (API FastAPI) en `localhost:8000` — el único puerto expuesto,
     porque es el único que necesita ser alcanzable desde afuera (la app
     móvil, o internet en el caso de un deploy real).

   El scraper de X es un servicio aparte, ver sección propia más abajo —
   no se levanta por defecto (`docker compose up` no lo incluye).

4. Verificar que responde: `curl http://localhost:8000/health`

### Endpoints principales

**Reportes y ruteo (Fase 1)**

- `POST /reports` — crea un reporte de riesgo con solo `lat`/`lon` (botón de 1 tap).
- `PATCH /reports/{id}` — agrega detalle opcional (tipo, gravedad, descripción).
- `GET /reports?min_lat=&min_lon=&max_lat=&max_lon=` — lista reportes crudos (para pintar el mapa).
- `GET /route?from_lat=&from_lon=&to_lat=&to_lon=&peso_seguridad=&peso_congestion=` —
  pide alternativas a OSRM y elige la de menor costo combinado tiempo +
  seguridad + congestión (fórmula de la sección 4 del spec).

**Capa A de Claude y datos derivados (Fase 2)**

- `POST /trips` — sube el historial de velocidad de un trayecto completado
  (fuente de la congestión histórica, sección 5 del spec).
- `GET /risk-zones?hour=` — zonas de riesgo agregadas por celda/franja horaria.
- `POST /mentions` — ingesta de posteos crudos de X (la usa el scraper).
- `POST /analysis/classify-reports` — corre Claude sobre reportes de usuarios sin clasificar.
- `POST /analysis/process-mentions` — corre Claude sobre menciones de X pendientes.
- `POST /analysis/congestion-profiles` — recalcula perfiles de congestión (cálculo estadístico, sin Claude).

Estos tres últimos están pensados para correr por cron, no en cada
request — ver `infra/cron/run_analysis.sh` (incluye un ejemplo de crontab
para correrlos cada noche, como sugiere la sección 3.1 del spec).

## Scraper de X/Twitter (Fase 2, sección 5.1)

Microservicio aislado en `scraper/`, separado a propósito del backend
porque es la pieza más frágil del sistema (depende de scraping, no de una
API oficial paga).

**Importante — cuentas a monitorear todavía sin definir**: se investigó
qué cuentas comunitarias de AMBA reportan inseguridad (tarea de la sección
9 del spec), pero la búsqueda no permitió confirmar una lista de 5-8
cuentas *comunitarias* (no oficiales) con cobertura y actividad
verificadas — solo aparecen cuentas oficiales de policía, que el spec ya
trata como una fuente aparte. `scraper/accounts.py` queda con la lista
vacía a propósito; completarla a mano siguiendo las instrucciones que
están en ese archivo antes de levantar el scraper.

Para levantarlo (una vez completada la lista de cuentas):

```bash
cd infra
docker compose --profile scraper up --build scraper
```

Corre en loop (cada `POLL_INTERVAL_SECONDS`, 30 min por defecto), scrapea
con `snscrape` (sin API key), y postea cada mención nueva a `POST
/mentions` del backend. Si X cambia su estructura y rompe `snscrape`, solo
falla este servicio — el resto de la app sigue funcionando.

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

Funcionalidad ya implementada en la app:

- Mapa con ubicación GPS y ruteo con origen y destino explícitos: por
  defecto el origen es la ubicación actual, pero se puede buscar una
  dirección de origen, tocar el mapa (fija destino) o mantener presionado
  (fija origen) para elegir otro punto de partida/llegada.
- Sliders de "priorizar seguridad" / "evitar congestión" que ajustan los
  pesos de la fórmula de costo en cada recálculo de ruta.
- Capa de zonas de riesgo (círculos coloreados por score) sobre el mapa.
- Botón de reporte de 1 tap + modo de reporte retroactivo (tap en el mapa
  o búsqueda de dirección), con detalle opcional no bloqueante.
- "Iniciar viaje" / "Finalizar viaje": graba velocidad GPS durante el
  trayecto y la sube a `/trips` al terminar, para alimentar los perfiles
  de congestión.

## Deploy en Oracle Cloud (free tier)

El backend corre en una VM **Ampere A1 (arm64)** del Always Free tier de
Oracle Cloud — no la VM AMD (`VM.Standard.E2.1.Micro`), que solo tiene 1GB
de RAM (muy poco para Postgres+OSRM+backend juntos). La imagen oficial de
OSRM en Docker Hub solo existe para amd64, así que en la VM Ampere se
compila desde código fuente (ver `infra/oracle-cloud-init.sh`) — el propio
Dockerfile del proyecto ya soporta arm64 nativamente, solo hay que
construirlo ahí. Esto es automático via cloud-init, pero tarda entre
**30 y 90 minutos** en el primer arranque (compila Boost/TBB desde cero).

### 1. Crear la cuenta

Entrar a [cloud.oracle.com](https://www.oracle.com/cloud/free/) y crear una
cuenta gratuita. Pide verificación de identidad y una tarjeta (no cobra
nada mientras te quedes en los límites "Always Free").

### 2. Crear la instancia de cómputo

En la consola de OCI: **Compute → Instances → Create Instance**.

- **Name**: `rutasegura-backend` (o lo que prefieras).
- **Image**: Ubuntu 24.04 (o 22.04), variante **aarch64**.
- **Shape**: cambiar a **Ampere · VM.Standard.A1.Flex**, y subir a
  **4 OCPUs / 24 GB de RAM** (el máximo permitido en Always Free) — así el
  build de OSRM es lo más rápido posible y sobra memoria para el resto.
- **Add SSH keys**: subí tu clave pública (`~/.ssh/id_ed25519.pub` o la que
  uses) para poder entrar por SSH vos mismo más adelante. Si no tenés una,
  generala con `ssh-keygen -t ed25519` antes de este paso.
- **Show advanced options → Management → Cloud-init script**: pegar el
  contenido completo de [`infra/oracle-cloud-init.sh`](infra/oracle-cloud-init.sh).

Crear la instancia y anotar la **IP pública** que le asigna Oracle.

### 3. Abrir el puerto 8000

Por defecto solo el puerto 22 (SSH) está abierto. Hay que agregar una regla
de ingreso para el puerto 8000 (el backend):

**Networking → Virtual Cloud Networks → (tu VCN) → Security Lists** (o
**Network Security Groups** si la instancia usa uno) → **Add Ingress Rules**:

- Source CIDR: `0.0.0.0/0`
- IP Protocol: TCP
- Destination Port Range: `8000`

El cloud-init script también abre el puerto en el firewall interno de la
VM (`iptables`), que en las imágenes Ubuntu de Oracle viene bloqueando todo
excepto SSH por defecto — hace falta lo uno *y* lo otro.

### 4. Esperar el bootstrap y verificar

Conectate por SSH (`ssh ubuntu@<IP-PUBLICA>`) y mirá el progreso:

```bash
tail -f /var/log/rutasegura-setup.log
```

Cuando termine (línea `RutaSegura: bootstrap terminado`), probar desde
cualquier navegador (incluido el del celular):

```
http://<IP-PUBLICA>:8000/health
```

Debería devolver `{"status":"ok"}`.

### 5. Apuntar la app al backend real

Reconstruir el APK con la IP real (ver sección de la app móvil más abajo
o pedirle a Claude que dispare el workflow de `Build APK` con
`api_base_url=http://<IP-PUBLICA>:8000`).

### Actualizaciones futuras

Este deploy es manual (sin CI/CD): para actualizar el backend después de
un cambio de código, entrar por SSH y correr:

```bash
cd /opt/rutasegura && git pull && cd infra && docker compose up -d --build
```

### Distribución a los primeros usuarios

Firebase App Distribution (gratis, sin pasar por Google Play) para los 4
usuarios iniciales — ver sección 8 del spec.

## Qué falta

- Completar `scraper/accounts.py` con cuentas verificadas manualmente (ver más arriba).
- Confirmar los límites exactos del free tier de Oracle Cloud al momento de crear la cuenta.
- **Fase 3 — Capa B de Claude**: copiloto conversacional (voz/texto) con
  tool use para ajustar `peso_seguridad`/`peso_congestion` y disparar
  recálculo de ruta en lenguaje natural, en vez de los sliders manuales.
- **Fase 4**: distribución más formal (Play Store) una vez validado con el grupo cercano.
