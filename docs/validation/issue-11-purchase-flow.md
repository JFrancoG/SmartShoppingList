# Selección y finalización de compra — #11

Evidencia del 22 de septiembre de 2026. Seguimiento operativo: [issue #11](https://github.com/JFrancoG/SmartShoppingList/issues/11). Rama local `codex/issue-11-purchase-flow`, basada en `81b8128c8ec5e6a8ad053ae75c2217172cdb276a` de `codex/issue-4-shared-shopping-flow`. La PR #9 permanece como dependencia. Este informe recoge la validación previa al primer commit y push, autorizados después por el usuario; la confirmación de publicación y su SHA se registran en la issue. No acredita un despliegue propio.

## Alcance implementado

Selección local separada por tienda, contador, confirmación explícita y compra atómica de 1–50 IDs/versiones. Keychain conserva la intención antes del envío; un reintento o reapertura recupera la misma clave y selección. El servidor registra comprador/fecha/versiones, conserva recibos de éxito o conflicto y no modifica filas omitidas. Ante cambios concurrentes se conserva la selección original para revisión. Diseño en [arquitectura compartida](../architecture/shared-shopping.md#selección-y-finalización-de-compra-11).

No incorpora edición/cancelación desde la app, historial, selección de tienda por voz ni Siri. Los checks previos a Finalizar están en memoria; la persistencia comprobada corresponde al envío preparado/incierto. No se atribuye esta implementación al servicio que actualmente atiende Railway.

## Validación automatizada local

Xcode 27.2 beta (`27B5019j`), Swift 6, My Mac (Designed for iPad) para iOS y macOS para el servidor. PostgreSQL aislado `db-test`, con migraciones reiniciadas entre tests; no se modifica la base alojada.

| Ejecución | Resultado nativo | Invocaciones |
|---|---:|---:|
| iOS, plan Fast | 67 pruebas, 0 fallos | 109, incluidas parametrizadas |
| iOS, plan Integration | 5 pruebas, 0 fallos | 7, incluidas parametrizadas |
| Servidor, PostgreSQL real | 74 pruebas, 0 fallos | 113, incluidas parametrizadas |

Los recuentos proceden de `.xcresult` cerrados, no de la suma del estado histórico devuelto por MCP: Integration devolvía 56 resultados correctos acumulados pero su ejecución nativa contiene 5 pruebas / 7 invocaciones. No hay fallos ni pruebas omitidas en los resultados nativos. Fast e Integration no son una demostración física ni una autenticación real.

Las tres primeras regresiones de compra fallaron antes de implementar el endpoint (404); las tres de selección/reintento fallaron con las operaciones del cliente todavía vacías. Tras implementarlas pasan junto con la regresión existente. Se añadieron comprobaciones específicas para:

- Comprar tres de cinco, conservar omitidos y otra tienda, y atribuir comprador distinto del creador.
- Repetir el mismo recibo y dos envíos simultáneos con orden distinto; rechazar la reutilización de clave con otro contenido.
- Conflicto de versión sin compra parcial y dos compradores con selección solapada sin sobrescribir al ganador.
- Ocultar filas ajenas, impedir acceso de otro grupo, límites de selección y rollback de filas/recibo ante fallo de PostgreSQL.
- Checks reversibles por tienda sin mutación, recuperación del sobre exacto tras reapertura y revisión explícita de versiones cambiadas.
- Respuesta de conflicto incompleta o incoherente conservada como incierta; respuesta de éxito limitada a los IDs enviados.
- Compra confirmada seguida de fallo del refresco: retirar IDs comprados, bloquear la carga obsoleta y mostrar aviso específico.
- Persistir y recuperar el sobre de compra mediante Keychain real, conservándolo al borrar la sesión.

Artefactos locales de esta ejecución: `/tmp/ssl-purchase/`. Informes `ios-green-final-native.json`, `ios-integration-native.json` y `server-final-native.json`; resultados MCP correspondientes incluyen las rutas `.xcresult`. El informe servidor se leyó desde DerivedData porque la ruta copiada por MCP no contenía `Info.plist`.

Build iOS posterior a los ajustes de formato: correcto, incluidos tests. `GetBuildLog` final del servidor y cliente no muestra warnings. Esto no amplía las excepciones ni certifica que toda resolución desde cero carezca de avisos; [EXC-001 y EXC-002](../dependency-exceptions.md) mantienen su alcance aceptado. No se cambian dependencias ni toolchain.

## Linux Release

Swift 6.4.0 / Linux arm64: `swift test -c release --jobs 4 --force-resolved-versions` correcto, 74 pruebas en 8 suites, 4,419 segundos de ejecución después de compilar. Se reutilizó la etapa local `smartshoppinglistserver:review-builder-9e51e2c` con `Sources` y `Tests` actuales montados en solo lectura. Antes de ejecutar se compararon `Package.swift` y `Package.resolved` del contenedor byte a byte con el repositorio; coinciden. PostgreSQL: `db-test` aislado en la red local de Compose. Log `/tmp/ssl-purchase/linux-tests.log`, salida 0.

La compilación Release mantiene únicamente el diagnóstico del manifiesto JWTKit sobre watchOS 8, cubierto por EXC-001. No hay warnings propios. Esta prueba no genera una imagen final nueva ni acredita amd64, HTTP externo o Railway. Se retiró el contenedor de prueba y `db-test` volvió a su estado detenido; Xcode volvió a iPhone 11 y plan Fast.

## Revisión y presentación

Las revisiones independientes de arquitectura y UI cubren el diff local. Se corrigieron y reauditaron tres hallazgos: validación del conflicto completo, refresco fallido tras éxito y eliminación del constructor que omitía invariantes. Sin nuevos hallazgos después de las correcciones. Auditoría de estilo sobre los Swift cambiados y `git diff --check` correctos; literales de contrato/SQL se mantienen legibles sin reformatear el repositorio.

Previews oficiales de `SharedPurchaseSection` en iPhone 18 Pro / iOS 27.2 con un producto seleccionado: Large, XXX Large y AX 5. Inspección visual sin truncado de productos ni solapamientos en el área visible. En AX 5 la confirmación queda fuera del encuadre inicial: exige scroll y ensayo real. Las capturas/JSON están en `/tmp/ssl-purchase/preview-*.json` y en sus rutas `previewSnapshotPath`.

No se acredita VoiceOver, foco tras finalizar, comportamiento completo al desplazarse ni inglés traducido. Los avisos/reintento al principio del formulario pueden quedar fuera de pantalla al confirmar desde abajo; ese hallazgo ya aplazado permanece en fase 3 y también requiere comprobarse en compra.

## Activación y siguiente ensayo

Antes del ensayo alojado: desplegar el commit publicado de esta rama, comprobar el arranque del servidor y ejecutar la app actualizada. Un `/hello` correcto no prueba por sí solo la nueva ruta de compra.

1. Preparar cinco productos en Mercadona y tres en Aldi, con algún nombre repetido entre tiendas.
2. Marcar/desmarcar y cambiar de tienda; comprobar que los checks son locales y no aparecen como compras en el otro dispositivo.
3. Marcar tres de Mercadona y Finalizar. Refrescar ambos: dos pendientes en Mercadona y tres en Aldi.
4. Comprobar pérdida de red, reintento/reapertura y compra concurrente desde las dos cuentas. Distinguir interrupción antes del envío y pérdida de respuesta después del envío.
5. Revisar VoiceOver, texto máximo y visibilidad de éxito/conflicto/reintento durante la interacción.

La issue permanece abierta hasta entrega y criterios verificados. Los pendientes de invitaciones de #4/#7 continúan separados y no se dan por cerrados por esta compra.

## Preparación del commit y push

El usuario autorizó commit y push el 22 de septiembre. Se reutilizan los resultados anteriores del mismo código; durante la preparación de entrega solo se ajusta documentación y la entrada del changelog. La revisión final del diff y `git diff --check` pasan. La publicación se verifica contra la rama remota y se registra en #11; esta autorización no incluye PR, merge, cierre ni despliegue.
