"""Cuentas comunitarias de AMBA a monitorear (seccion 5.1 del spec).

IMPORTANTE: esta lista arranca vacia a proposito. Se investigo (via
busqueda web, seccion 9: "tarea concreta para el momento de
implementacion") pero no se pudo confirmar una lista de 5-8 cuentas
*comunitarias* (no oficiales) de AMBA con cobertura y actividad
verificadas — las busquedas solo devuelven cuentas oficiales de policia
(@PoliciaCiudadBA, @policiapba, @minsegcba) o de medios, que el spec ya
trata como fuentes separadas, no como "cuenta comunitaria que reporta
inseguridad en tiempo real".

Antes de activar el scraper en produccion, completar esta lista a mano:
1. Buscar en x.com "alerta" / "seguridad" + nombre de barrio o partido.
2. Verificar que la cuenta postee reportes de incidentes con regularidad
   (no solo una vez cada tanto) y tenga cobertura de la zona que interesa.
3. Agregar el @handle (sin el @) a la lista de abajo.
"""

ACCOUNTS: list[str] = []
