# Especificación: App de Navegación Inteligente (nombre provisional: "RutaSegura")

## 0. Decisiones confirmadas

- **Plataforma**: Flutter (Dart).
- **Área inicial**: AMBA (Área Metropolitana de Buenos Aires).
- **Reporte de zonas de riesgo**: modelo híbrido — botón de 1 tap ("esto se siente inseguro") para reporte inmediato sin fricción, con opción de agregar detalle (tipo de incidente, hora, gravedad) después, de forma opcional y no bloqueante.
- **Fuentes externas de datos**: crowdsourcing propio + monitoreo de redes sociales (X/Twitter). Scraping de noticias policiales evaluado a futuro.
- **Presupuesto**: $0 al inicio, stack 100% gratuito/open source.
- **Motor de ruteo**: self-hosted (OSRM o Valhalla).
- **Monitoreo de X/Twitter**: sin presupuesto para API paga; seguimiento de cuentas comunitarias vía scraping/RSS.
- **Reporte de riesgo**: 1 tap en el momento o retroactivo sobre el mapa.
- **Alcance geográfico del MVP**: AMBA completo (CABA + conurbano) desde el día 1.
- **Primeros usuarios**: grupo cercano de no más de 4 usuarios (familia/amigos).
- **Hosting del motor de ruteo**: Oracle Cloud free tier.
- **Validación de reporte retroactivo**: pin manual en el mapa + buscador de dirección.
- **Distribución**: Firebase App Distribution (evita el fee de USD 25 de Google Play).

## 1. Visión general

App de navegación tipo Waze (Flutter, Android primero) que optimiza rutas considerando:

1. Tiempo de viaje
2. Seguridad (evitar zonas de riesgo/criminalidad)
3. Congestión predictiva

## 2-3. Arquitectura y las dos capas de Claude

- **Capa A — Analista de fondo (batch, asíncrono)**: clasificación de zonas de riesgo desde reportes de texto, detección de patrones de congestión, resumen de anomalías. Vía API estándar de Claude (`/v1/messages`), salida JSON.
- **Capa B — Copiloto conversacional (tiempo real)**: el usuario le habla/escribe a la app mientras maneja; Claude responde en lenguaje natural y puede disparar recálculo de ruta vía tool use.

## 4. Motor de ruteo

Base OSRM/Valhalla con función de costo combinada:

```
costo_segmento = tiempo_base
               + (peso_seguridad * score_riesgo_segmento)
               + (peso_congestion * prediccion_congestion_hora_actual)
```

Pesos ajustables por el usuario (slider o vía el copiloto conversacional).

## 5. Fuentes de datos

| Dato | Fuente inicial | Fuente ideal a futuro |
|---|---|---|
| Mapas/calles | OpenStreetMap | — |
| Zonas de riesgo | Reporte híbrido de usuarios | Datos públicos de policía CABA/PBA |
| Zonas de riesgo (externo) | Monitoreo de menciones en X/Twitter | Scraping de noticias policiales |
| Congestión histórica | Registrada por la app (velocidad GPS) | API de tráfico (HERE/TomTom) |
| Congestión en vivo | Promedio de velocidad de usuarios activos | Mismo, a escala |

## 6. Stack tecnológico (100% gratuito/open source para el MVP)

- App móvil: Flutter (Dart)
- Mapas: OSM + Flutter Map
- Backend: Python + FastAPI
- Base de datos: PostgreSQL + PostGIS
- Motor de ruteo: OSRM, self-hosted en Oracle Cloud free tier
- Datos de mapas: extracto OSM de AMBA de Geofabrik
- IA: Claude API (único costo variable)
- Scraper de X: microservicio propio en Python
- Infraestructura: Docker Compose

## 7. Fases sugeridas

1. **MVP compartido con usuarios cercanos**: mapa + ruteo estándar sobre AMBA, registro manual de zonas de riesgo, botón de reporte 1 tap + retroactivo, distribución a un grupo cercano.
2. **Capa A de Claude**: clasificación automática de zonas de riesgo, perfiles de congestión, scraper de X + pipeline de extracción.
3. **Capa B de Claude (copiloto)**: interfaz conversacional, tool use conectado al motor de ruteo.
4. **Escalar más allá del círculo cercano**: distribución más formal (Play Store).

## 8. Distribución a usuarios cercanos

Firebase App Distribution: gratis, builds de prueba a grupo cerrado, sin pasar por Play Store.

## 9. Estado del documento

Todas las decisiones de diseño principales están tomadas. Tareas pendientes para el momento de implementación:

- Investigar y seleccionar las cuentas específicas de X a monitorear (sección 5.1).
- Confirmar los límites exactos del free tier de Oracle Cloud al momento de crear la cuenta.

---

*Documento completo (con diagramas de arquitectura) disponible en el PDF original provisto por el usuario.*
