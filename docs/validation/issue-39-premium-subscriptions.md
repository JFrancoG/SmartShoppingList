# Suscripción premium y vuelta al plan gratuito — validación de #39

Fecha: 10 de octubre de 2026. [Issue #39](https://github.com/JFrancoG/SmartShoppingList/issues/39).

Unidad implementada en la rama local `codex/issue-39-premium-subscriptions`, creada desde `main` limpio y sincronizado en `2ec7f574`. Este informe registra validación local anterior a la entrega Git. La issue conserva el plan operativo y el resultado definitivo de publicación e integración cuando se realicen. El [contrato 0.5](../contracts/premium-subscriptions.md), la [política comercial](../architecture/group-access-and-limits.md) y la [guía de configuración](../setup/premium-subscriptions.md) delimitan comportamiento y activación externa.

## Alcance comprobado

- Una suscripción personal premium, mensual o anual: 5 pertenencias, 10 tiendas activas por grupo administrado y 100 entradas pendientes por tienda. El plan gratuito mantiene 1/3/20. Los cupos compartidos dependen del administrador actual; las pertenencias dependen de cada cuenta.
- StoreKit entrega metadatos y transacciones verificadas del dispositivo; el servidor comprueba evidencia, aplicación, productos, grupo de suscripciones, entorno, vínculo de cuenta y estado actual en Apple antes de persistir derechos. Las pruebas criptográficas usan una PKI sintética independiente; las pruebas HTTP/SQL sustituyen el gateway mediante su interfaz de producción. No acreditan una compra Apple real.
- Cancelar la renovación conserva premium hasta finalizar el periodo acreditado. La gracia de cobro conserva premium completo mientras Apple la confirme. La configuración acordada, todavía externa, es **16 días y Only Paid to Paid Renewals**; el servidor usa el final verificado, sin inventar dieciséis días ante una consulta fallida.
- Después del fin ordinario del derecho, incluidos los días de gracia acreditados, hay **7 días** para organizar las pertenencias existentes, sin altas nuevas. Los cupos de tiendas/productos regresan a 3/20 al terminar premium. Reembolso/revocación no concede esta transición de cortesía.
- El grupo gratuito conserva una elección válida; el fallback es la pertenencia abierta más antigua. Un cambio efectivo manual consume un plazo de **30 días**, persistido por cuenta. Confirmar el mismo grupo no renueva ese plazo. Sustituir una elección ya no disponible permite organizarse conservando el plazo anterior.
- Los grupos adicionales restringidos conservan consulta, retirada de pendientes, archivo de tiendas vacías, revocación de invitaciones, traspaso, salida/cierre y recuperación de recibos. No admiten altas, edición, confirmación de compras, restauración de tiendas ni creación de invitaciones. No se eliminan membresías, roles o contenido por caducidad.
- Sandbox y Production tienen vínculos y concesiones separados. Una configuración ausente o una interrupción no convierte pruebas en derechos de producción ni amplía fechas conocidas. Las notificaciones se deduplican de forma durable; un estado anterior o una revisión igual no reactiva una cadena revocada.
- iOS conserva por separado el envío de compra compartida y la verificación de suscripción pendiente. Se mantiene la cuenta y la intención originales; el recibo de elección gratuita requiere refrescar autoridad actual. La transacción StoreKit se finaliza tras el reconocimiento durable del servidor.

## Resultados

| Comprobación | Resultado | Entorno y límite |
|---|---|---|
| Contrato y ejemplos | 31 operaciones, 125 ejemplos positivos y 47 peticiones negativas: PASS | JSON Schema 2020-12 y formatos; no equivale a meta-validación completa OpenAPI ni a probar todos los recorridos reales. |
| Sistema de diseño | 64 pares × 4 modos y 21 assets × 4 variantes: PASS | Valores y recursos canónicos; no certifica contraste renderizado de toda la UI. |
| Servidor | 145 funciones en 9 suites: PASS, 48,118 s | Servidor nativo y PostgreSQL 18.6 aislado. Build funcional final: 3,50 s; recompilación tras formato: 5,10 s. Sin warnings propios; EXC-001 conserva la excepción del manifiesto JWTKit. |
| iOS, build para tests | PASS, 4,869 s; cero errores y warnings | Xcode MCP 27.2, SmartShoppingList, iPhone 17 / Simulator 27.2, build 24B5089g. Recompilación posterior de formato: PASS, 3,788 s, también sin warnings. |
| iOS, Fast | 227 funciones / 388 ejecuciones: PASS | Su `xcresult` informa 0 fallos, 0 omitidas y 0 runtime warnings. |
| iOS, Integration | 10 funciones / 18 ejecuciones: PASS | Regresión de las operaciones anteriores con Keychain del simulador y reapertura. 0 fallos, 0 omitidas y 0 runtime warnings; no acredita la nueva verificación premium en Keychain real. |
| Revisiones independientes | Sin hallazgos estáticos pendientes | Contrato, arquitectura/concurrencia, recuperación, SwiftUI/accesibilidad y estilo: 52 Swift, 25 iOS y 27 servidor. |
| Localización | 43 claves nuevas, 413 entradas totales: PASS | Español, comentarios y placeholders coherentes. No prueba VoiceOver ni StoreKit real. |
| Previews | 8 snapshots renderizados e inspeccionados, también por un revisor independiente | Datos sintéticos, apariencia Light. Solo se acredita contenido visible; detalle siguiente. |
| Consistencia documental | 205 enlaces locales, 28 anchors y 403 referencias OpenAPI: PASS | 14 Markdown; 71 destinos OpenAPI distintos. `git diff --check` limpio. |

Los conteos de los planes iOS proceden de `xcresulttool get test-results summary` de cada artefacto, con **406 ejecuciones** en total. No se emplean los contadores agregados de MCP como sustituto de esos resultados.

Las correcciones finales de formato en cuatro archivos del servidor y en `AddItemsView` conservaron tokens y literales, incluidos SQL y aserciones. Se recompilaron los targets afectados y se reutilizan las suites recientes al no cambiar comportamiento. No se declara limpieza global de DerivedData ni ejecución de CI.

## Previews y accesibilidad

Todas las imágenes están en `ActionArtifacts/default/RenderPreview/` de esta máquina. El agente principal las inspeccionó con `view_image`; un revisor independiente inspeccionó las mismas ocho, sin volver a compilar.

| Snapshot, CEST | Estado / idioma / tamaño | Destino |
|---|---|---|
| 02:17:52 | Premium, transición · ES · Large | iPhone 18 Pro Max, render inicial |
| 02:19:30 | Premium activo, catálogo ilustrativo · ES · Large | iPhone 17 |
| 02:19:51 | Grupo restringido · EN · AX5 | iPhone 17 |
| 02:20:01 | Gracia de cobro · EN · AX5 | iPhone 17; el entorno explícito AX5 de la preview prevaleció sobre el intento de override Large |
| 02:20:07 | Transición · ES · XXXL | iPhone 17 |
| 02:20:16 | Verificación pendiente · ES · AX5 | iPhone 17; parte superior del formulario |
| 02:20:38 | Grupo gratuito, fechas · EN · AX5 | iPhone 17 |
| 02:20:44 | Grupo gratuito, acción y pie completos · ES · XXXL | iPhone 17 |

No se observaron solapamientos ni truncamiento horizontal del texto dentro del área visible. Algunos formularios continúan bajo el pliegue: el snapshot de verificación pendiente no acredita visualmente su aviso ni los controles inferiores. No se ejecutó scroll completo, interacción, VoiceOver, Control por voz, Switch Control ni teclado. Las imágenes Light no acreditan todas las combinaciones de contraste/apariencia.

La revisión estática verificó el presentador nativo para errores de acciones premium, la fecha específica de final de gracia, la conservación de identificadores ante nombres de grupo iguales y el texto que no promete reiniciar treinta días en una sustitución excepcional. Los estados de preview utilizan catálogo ilustrativo y servicios locales; no hacen compras ni consultan una cuenta Apple real.

## Casos y correcciones relevantes

PostgreSQL verifica expiración ordinaria, revocación, plazos persistidos, sustitución excepcional, aislamiento de entornos, migraciones y guardas de reversión. Las pruebas HTTP comprueban reconocimiento de compras históricas según el estado actual, titularidad inmutable, gracia, caída de verificación, recepción durable de notificaciones y estados duplicados/tardíos. La carrera entre revocación y crecimiento usa el mismo bloqueo de grupo para aplicar los cupos del administrador que corresponde.

Las pruebas iOS verifican catálogo mensual/anual y un único grupo Apple, ausencia de concesión local, compras pendientes, errores, reconocimiento y finalización. La recuperación premium por cuenta y reapertura de su coordinador utilizan la interfaz de credenciales en memoria; las pruebas Integration existentes comprueban las operaciones anteriores con Keychain real del simulador. No se acredita aún el nuevo valor de verificación premium en Keychain real ni tras reinstalar la app. La falta de catálogo no impide recuperar una verificación guardada ni invalida un derecho ya confirmado. Esta evidencia sintética no constituye un ensayo del SDK con productos reales o notificaciones Apple.

Los preflight detectaron y corrigieron el formato PEM de los certificados sintéticos de prueba y el harness que exigía HTTP 409 para errores que contractualmente son 403, 400 o 503. Se mantuvieron los códigos exactos y se exigió el status correcto. Una denegación de creación por debajo del cupo ahora es legítima en un grupo restringido; la prueba de respuesta contradictoria utiliza una concesión de crecimiento con el cupo lleno. Las aserciones de seguridad y comportamiento permanecen exigentes. Las suites finales completas pasaron después de esas correcciones.

## Reproducción y artefactos locales

La base `smartshoppinglist_testing` estuvo en el contenedor exclusivo `smartshoppinglist-issue39-db`, con PostgreSQL 18.6 y el digest fijado en `server/docker-compose.yml`, puerto loopback 55439 y almacenamiento temporal `tmpfs`. El contenedor propio fue retirado al finalizar; los contenedores preexistentes permanecen detenidos. Se restauraron Fast e iPhone 11 y se cerró únicamente el workspace de esta tarea, conservando el workspace preexistente de FranAlonso.

Con una base temporal equivalente preparada, desde `server/`:

```sh
swift build --build-tests --force-resolved-versions --jobs 4
TEST_DATABASE_HOST=127.0.0.1 \
TEST_DATABASE_PORT=55439 \
TEST_DATABASE_USERNAME=vapor_test \
TEST_DATABASE_PASSWORD=vapor_test_password \
TEST_DATABASE_NAME=smartshoppinglist_testing \
swift test --skip-build
```

Las credenciales son exclusivamente de prueba; no ejecutar sobre otra base ni en paralelo con otra suite que comparta esa base.

Artefactos temporales, disponibles únicamente en esta máquina:

- Servidor: `/tmp/smartshoppinglist-issue39-server-tests-final.log` y `/tmp/smartshoppinglist-issue39-server-build-style.log`.
- Build iOS: `ActionArtifacts/default/BuildProject/BuildProject-Log-20261010-021841.txt` y `BuildProject-Log-20261010-022146.txt`.
- Logs iOS sin diagnósticos de warning/error: `ActionArtifacts/default/GetBuildLog/0B120CF3-AD04-45DD-BBBC-5F0CE90F0805.txt` y `C42C8423-3643-4D57-B632-AEF98BAA9976.txt`.
- Fast: `Test-SmartShoppingList-2026.10.10_02-18-41-+0200.xcresult`.
- Integration: `Test-SmartShoppingList-2026.10.10_02-18-54-+0200.xcresult`.
- La raíz de `ActionArtifacts` es `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/`; los `.xcresult` están en `RunAllTests/` y las imágenes de la tabla, en `RenderPreview/`.

## Límites y siguiente entrega

La unidad queda implementada y validada localmente. No se realizaron commit, push, PR, CI, merge, despliegue, migración de producción ni cobros. No se ejecutó Release ni un recorrido real de StoreKit/App Store Sandbox, restauración entre dispositivos físicos o notificaciones Apple. Los recibos y contratos previos se conservan; los clientes anteriores requieren actualización para interpretar las nuevas capacidades/restricciones y recuperar las nuevas operaciones.

Quedan por configurar y validar externamente los productos, grupo de suscripciones Apple, precios, credenciales, gracia de cobro, notificaciones y distribución conforme a la guía. Tampoco se han activado regalos/códigos de oferta ni el programa Small Business. La solicitud de Small Business es independiente de esta implementación y su presentación no acredita aceptación o comisión efectiva. La issue registra esos límites y la entrega Git cuando se autorice.
