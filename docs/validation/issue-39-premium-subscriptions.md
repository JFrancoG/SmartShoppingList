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

## Seguimiento del 12 de octubre: preparación del backend Sandbox

La implementación anterior está integrada mediante [PR #40](https://github.com/JFrancoG/SmartShoppingList/pull/40) en `f03a6ae`, con CI de la PR y de `main` superado. #39 permanece abierta por decisión del propietario hasta completar las pruebas Apple Sandbox. La preparación externa y sus resultados concretos se registran en la issue; no convierten esta evidencia local en una compra o despliegue validado.

La preparación de un entorno Vapor `sandbox` detectó que la condición anterior, distinta de `production`, publicaba las rutas de infraestructura `/todos` sin autenticación. El ajuste en `codex/issue-39-sandbox-backend` registra esas rutas únicamente en `development` y `testing`, conservando `/hello` y las rutas de producto. La guía concreta raíz Docker, comando de arranque completo, PostgreSQL persistente propio con TLS verificado, configuración independiente de identidad/compras y aislamiento del cliente.

| Comprobación del ajuste | Resultado | Alcance |
|---|---|---|
| Demostración previa | 4 fallos esperados, únicamente en Sandbox | GET, POST y DELETE publicados, además de cambios de persistencia; producción ya los rechazaba. |
| Regresión tras el ajuste | 1 función parametrizada, 2 casos: PASS, 0,342 s | GET/POST/DELETE devuelven 404 en Sandbox y producción, conservan datos y mantienen healthcheck y autorización de rutas de producto. |
| Suite completa | 146 funciones en 9 suites: PASS, 37,767 s | Servidor nativo y PostgreSQL aislado; HTTP en memoria, sin TCP ni alojamiento. |
| Compilación | Build limpio: PASS, 88,69 s; incremental final: PASS, 3,32 s | Sin warnings propios; el build limpio conserva únicamente EXC-001 del manifiesto JWTKit. |
| Revisiones independientes | PASS | Ambos Swift, comportamiento/persistencia, serialización de la suite, estilo y guía; `git diff --check` limpio. |

Las fuentes y la prueba permanecen sin cambios desde esta validación. Se reutilizan estos resultados para la entrega; CI verificará por separado la revisión publicada en Linux. El contenedor y volumen exclusivos de esta prueba se retiraron sin alterar los preexistentes. No se ejecutaron compras Apple, login real, notificaciones ni despliegue desde estas pruebas. La publicación Git y el resultado de CI quedan en #39; en el momento de esta validación, Deploy permanecía pendiente por instrucción del propietario.

## Seguimiento del 12 de octubre: recursos en la imagen Linux

El propietario inició los despliegues Sandbox tras completar los permisos GitHub de Railway. El primer intento terminó con `AppStoreGatewayError.invalidConfiguration`. Tras volver a pegar la clave, el segundo alcanzó un punto diferente: `resource_bundle_accessor.swift:44: Fatal error: unable to find bundle named SmartShoppingListServer_SmartShoppingListServer`. No se atribuye este segundo fallo a las claves.

La reproducción aislada utiliza Swift 6.4.0-noble y su runtime slim fijados por digest, Linux arm64, Release y el mismo nombre de paquete y declaración `.process`. SwiftPM genera un bundle plano `.bundle` con el certificado público en su raíz. El staging anterior, que copiaba solo `.resources`, reproduce el fatal con salida 133. Con ambos sufijos, el runtime encuentra y lee el certificado de 583 bytes, idéntico al original, con salida 0. El runtime solo tiene acceso a `/app`, sin el árbol de compilación; ambos contenedores se ejecutan sin red y se retiran.

La corrección conserva los bundles completos y comprueba el certificado obligatorio durante el build. El verificador Swift, las raíces de confianza, las claves y las guardas de entorno permanecen sin cambios. Se incorpora un job de imagen final Release Linux amd64 y `scripts/check_server_image.sh`: compras configuradas con P-256 temporal, red Docker interna, PostgreSQL propio, healthcheck, autenticación y `/todos` cerrado. Así la comprobación ejercita la carga real del bundle fuera del árbol de compilación.

| Comprobación | Resultado | Alcance |
|---|---|---|
| Reproducción mínima anterior/corregida | Salidas 133 / 0 | Release Linux arm64 y runtime slim, sin árbol de compilación ni red; mismo fatal antes y certificado leído tras conservar el bundle. |
| Build de la imagen completa | PASS; compilación 113,33 s | Dockerfile real, Release Linux arm64; solo el warning previamente aceptado EXC-001 de JWTKit, sin warnings propios. |
| Arranque de la imagen completa | PASS | Configuración de compras activa con clave efímera, carga del certificado, migraciones PostgreSQL reales, `/hello` con cuerpo esperado, rutas de cuenta sin sesión 401 y GET/POST `/todos` 404. |
| Aislamiento y limpieza | PASS | Red interna sin puertos publicados; contenedores, volúmenes anónimos y red propios retirados; los tres contenedores anteriores siguen detenidos. |
| Sintaxis y revisión | PASS | Shell, YAML, propagación de fallos del pipeline y diff; revisión independiente del staging y smoke, con límites de conexión/respuesta incorporados. |

La imagen local `smartshoppinglistserver:issue39-resources` es Linux arm64, digest `sha256:3e3532af9a5f74ffd329d051196b6d5dd9367d9322e8eddcfb5a9fc1bdf0ab78`. Los logs de build y arranque están fuera del repositorio en `/tmp/smartshoppinglist-issue39-resources-image-build.log` y `/tmp/smartshoppinglist-issue39-resources-image-startup.log`. La reproducción mínima conserva su resultado y logs sanitizados fuera de Git.

No cambia código Swift ni el contrato; no se repite la suite nativa previamente validada por este ajuste de empaquetado. La publicación y el nuevo job CI deben confirmar por separado la imagen Linux amd64; todavía no se acredita CI nuevo, arranque remoto, TLS con la base Railway, identidad, compras ni notificaciones Apple. #39 permanece abierta.

## Seguimiento del 12 de octubre: diagnóstico de identidad al arrancar

La corrección de recursos quedó integrada mediante PR #42 en `670ed11`, con CI de PR y `main` superado, incluidas 146 pruebas en 9 suites y el arranque de la imagen Release Linux amd64. El propietario lanzó después **Deploy latest commit** en Railway Sandbox. El despliegue `74a271d3-5111-4f38-b6bb-121b77dc96b3` usa exactamente esa revisión, construye la imagen en 6 min 29 s y falla al arrancar: los logs repiten `AppleGatewayError.invalidConfiguration` desde las 20:50:35 hasta las 20:52:44 CEST. El fallo de healthcheck es consecuencia de ese rechazo; ya no aparece el fallo de empaquetado anterior.

Las variables públicas de identidad, su versión activa `v1` y la ausencia de `APPLE_PRIVATE_KEY_PATH` se comprobaron en el despliegue y en el servicio. Sus valores coinciden exactamente, sin caracteres sobrantes. El archivo local de Sign in with Apple supera la comprobación de OpenSSL; el JSON local es un objeto con entrada `v1`, base64 válido y claves de 32 bytes. Se imprimieron solo resultados de validación, nunca los contenidos. El propietario confirma que pegó el PEM y el JSON completos. Los valores sellados alojados no se pueden deducir de esas comprobaciones.

El error actual también identifica el rechazo de `RefreshTokenVault`, por lo que el log genérico no distingue firma y cifrado. El ajuste en `codex/issue-39-apple-startup-diagnostics` conserva el mismo error y las reglas existentes y añade diagnósticos fijos con variable y motivo. No incorpora valores, versiones o rutas suministradas, secretos ni errores internos del parser. Las familias ausentes siguen permitiendo el bootstrap local no configurado.

La prueba de la imagen se amplía para activar compras, Sign in with Apple y el vault con claves desechables, en la red interna y base aislada existentes. Esa activación comprueba el arranque de las tres familias y no representa un login o una transacción de Apple.

| Comprobación del diagnóstico | Resultado | Alcance |
|---|---|---|
| Compilación nativa del servidor y pruebas | PASS, 29,85 s | Swift 6.4, warnings como errores en targets propios; únicamente EXC-001 del manifiesto JWTKit. |
| Suite completa | 156 pruebas en 9 suites: PASS, 45,815 s | PostgreSQL 18.6 propio con tmpfs y puerto loopback 50855; rechazo previo, diagnóstico único y seguro, firma y cifrado válidos. |
| Imagen Release completa | PASS, compilación 115,77 s | Dockerfile real, Linux arm64; las tres familias Apple se activan en el smoke con claves temporales. |
| Arranque de la imagen | PASS | Recursos IAP, firma de identidad y vault cargados, migraciones, `/hello` esperado, cuentas sin sesión 401 y GET/POST `/todos` 404. |
| Revisión independiente y sintaxis | PASS | Siete Swift, script, workflow, documentación y changelog; sin hallazgos, shell/YAML y `git diff --check` correctos. |
| Limpieza | PASS | Contenedores y red propios del smoke retirados, base nativa tmpfs retirada; los tres contenedores preexistentes siguen detenidos. |

La imagen `smartshoppinglistserver:issue39-identity-diagnostics` es Linux arm64, digest `sha256:14685104b15961390111ac985e53a78fd067650a93e6699c3eee1dadc3ae407e`. Los logs locales se conservan fuera de Git en `/tmp/smartshoppinglist-issue39-identity-build.log`, `/tmp/smartshoppinglist-issue39-identity-tests.log`, `/tmp/smartshoppinglist-issue39-identity-image-build.log` y `/tmp/smartshoppinglist-issue39-identity-image-startup.log`.

Al finalizar esta validación local, la publicación, CI de esta nueva revisión y otro despliegue alojado permanecían pendientes; la issue registra su entrega posterior. La prueba local no determina cuál de los valores sellados falla en Railway; el nuevo diagnóstico permitirá identificarlo en el siguiente arranque. El intento alojado actual no acredita conexión/migraciones de la base Railway, TLS, login, compras ni notificaciones. #39 permanece abierta.

## Seguimiento del 12 de octubre: instalación física Sandbox, identidad y catálogo

La preparación continúa en `codex/issue-39-ios-sandbox`, desde `main` sincronizado en `12169fb`. Debug selecciona
API, invitaciones, dominio asociado y nombre visible de Sandbox; Release conserva producción. El bundle ID y Team ID
permanecen iguales. La fábrica conserva las ubicaciones locales originales de producción y separa los demás orígenes
normalizados, incluida la configuración ausente, sin migrar o borrar credenciales ni borradores.

| Comprobación | Resultado y límite |
|---|---|
| Build Debug para iPhone 11 | PASS; primera compilación 9,544 s y compilación/instalación final 4,416 s. |
| Build con pruebas para iPhone 17 Simulator, iOS 27.2 | PASS, 12,956 s; recompilación final tras revisión 9,313 s. |
| Plan Integration final antes de entrega | 12 funciones / 20 ejecuciones aprobadas, 0 fallos, omitidas o fallos esperados; 3,824 s. Incluye los dos casos nuevos de aislamiento y conservación. El resultado nativo acredita Passed y ningún runtime warning. |
| Diagnósticos de compilación | Sin warnings ni errores en los logs de los builds y en GetBuildLog. |
| Revisión independiente final | Tres Swift, proyecto, entitlements, guías y changelog; sin hallazgos. `git diff --check` limpio. |
| Artefacto Debug firmado | `Smart List Sandbox`, bundle `com.plusprojects.SmartShoppingList`, Team `NWN8JUE438`, ambos orígenes Sandbox, Sign in with Apple y único dominio asociado Sandbox. Firma de desarrollo con `get-task-allow=true`. |
| Instalación física | RunProject confirmó lanzamiento en el iPhone 11, PID 1400. No se eliminó la app ni sus datos. |
| Identidad real | Railway Sandbox: POST `/v1/auth/challenges` 201 a las 23:43:55 CEST; POST `/v1/auth/apple` 200 a las 23:44:20, 540 ms; GET `/v1/me` 200 a la misma hora. |
| Estado y catálogo | GET `/v1/account/subscription` 200 a las 23:44:29, 20 ms. El propietario confirma el acceso y aporta captura de Premium a las 23:45:28: Premium Mensual 5,99 € al mes y Premium Anual 49,99 € al año, con plan gratuito. |

GetTestList marcó incorrectamente las pruebas como deshabilitadas y RunSomeTests rechazó la selección. RunAllTests con el
plan Integration sí ejecutó las pruebas. La primera copia `.xcresult` de ActionArtifacts estaba incompleta y la consola
terminaba con resultado indeterminado; el original de DerivedData conserva un resultado nativo Passed. La pasada final de
las 23:51:20, posterior al ajuste del inicializador y sus accessors, cerró correctamente también la copia de ActionArtifacts.
`xcresulttool get test-results summary` confirma 12 funciones / 20 ejecuciones, cero fallos y cero runtime warnings.
No se ejecutaron las 228 pruebas de otros planes.

Artefactos fuera de Git: el resultado final es
`/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/Test-SmartShoppingList-2026.10.12_23-51-20-+0200.xcresult`;
en ese directorio se conservan el resumen `7C7D477C-B419-4AEE-991A-7D6D95C94EC7.txt` y la consola
`test-console-log-2026-10-12T23-51-20+02-00.txt`. La recompilación con targets de prueba de esa pasada fue incremental
(0,121 s), sin warnings/errores en su log ni en GetBuildLog. Se restauraron el plan Fast y el destino iPhone 11.

La captura es evidencia del catálogo mostrado por StoreKit en ese dispositivo y storefront, no aprobación de precios
definitivos para lanzamiento. No se compró ni restauró, ni se validaron renovación, gracia, caducidad o revocación.
El namespace local no separa el historial o la cuenta propios de StoreKit. No se cambiaron secretos ni se desplegó servidor.
El dominio asociado está en la firma; no se acredita Universal Links: el GET de AASA observado devuelve 503 y ese recorrido
queda fuera de la comprobación de identidad y catálogo. Release conserva sus ajustes, pero no se recompiló en esta sesión.

La captura y los logs completos permanecen fuera de Git. La issue registra la entrega Git y sus resultados de CI por
separado de esta validación local. #39 permanece abierta para la matriz comercial real.

## Seguimiento del 14 de octubre: compra mensual y renovación firmada anticipadamente

El propietario confirma una compra mensual con el tester Sandbox en iPhone 11, seguida de restauración y nuevos
intentos al recibir el aviso «Apple no ha podido verificar esta compra». Ese texto corresponde al error del servidor
`invalid_app_store_transaction`; no acredita que StoreKit cancelara la compra. La confirmación inicial de activación
en la pantalla Premium sigue pendiente.

Railway Sandbox registra la notificación inicial con `204` a las 16:06:48 CEST y el envío del cliente con `400` a las
16:06:50. Los envíos posteriores a las 16:09:51, 16:10:05 y 16:10:39 devuelven `200`. PostgreSQL conserva una cadena
mensual Sandbox vinculada al usuario, con el periodo inicial 16:06:46–16:11:46. Una consulta autenticada a App Store
Server API confirma independientemente la aplicación, producto, grupo, vínculo de cuenta y renovaciones posteriores.
Los periodos de cinco minutos coinciden con la velocidad de pruebas descrita por
[Apple](https://developer.apple.com/help/app-store-connect/test-in-app-purchases/manage-sandbox-apple-account-settings/).

El historial original de Apple identifica la notificación `DID_RENEW` del periodo siguiente: `signedDate` es
`2026-10-14T14:10:52.809Z`, mientras `purchaseDate` es `2026-10-14T14:11:46.000Z`. El periodo empieza **53,191 segundos
después de firmarse**. La firma JWS y cadena hasta la raíz Apple incluida coinciden; los identificadores de aplicación,
entorno, producto, grupo y cuenta también. Apple registra `UNSUCCESSFUL_HTTP_RESPONSE_CODE`, que corresponde al `400`
de Railway a las 16:10:53 CEST. La comprobación local de esas firmas no sustituye la política completa del servidor
ni acredita el procesamiento de esa renovación.

`AppStoreTransaction.verify` exigía `purchaseDate <= signedDate`, una relación que Apple no declara entre
[la fecha de compra](https://developer.apple.com/documentation/appstoreserverapi/purchasedate) y
[la fecha de firma](https://developer.apple.com/documentation/appstoreserverapi/signeddate). Su
[verificador oficial](https://github.com/apple/app-store-server-library-python/blob/main/appstoreserverlibrary/signed_data_verifier.py)
tampoco la exige. La regla explica el rechazo de esa renovación auténtica. No se capturó el JWS exacto del primer
envío del cliente rechazado; no se atribuye concluyentemente ese primer `400` a la misma causa.

La corrección en `codex/issue-39-sandbox-renewal-verification`, desde `main` sincronizado `b25faa8`, elimina únicamente
esa comparación. Conserva firma, raíz y propósito de los certificados, política OCSP, identidad y propiedad personal,
comprobaciones de contexto y consulta del estado actual de Apple antes de acreditar acceso. No añade tolerancias
temporales calculadas por la aplicación ni concede derechos a partir de fechas del dispositivo.

| Validación local | Resultado y límite |
|---|---|
| Regresión antes de corregir | Los dos casos, verificación histórica y online, fallan con `.rejected`, como requiere la evidencia observada. |
| Build de todos los targets del paquete | PASS, 9,55 s tras corregir; sin warnings propios. El primer build conserva únicamente EXC-001 de JWTKit. |
| Suite del verificador | 8 funciones, incluidas las dos ejecuciones de la nueva regresión: PASS. Los certificados son sintéticos; el caso online no acredita una consulta OCSP real. |
| Suite completa del servidor | 157 funciones en 9 suites: PASS, 48,159 s; PostgreSQL 18.6 aislado con tmpfs y puerto loopback 59281. |
| Revisión independiente | Sin hallazgos de seguridad o estilo en los dos Swift modificados; el recall inspecciona 2 archivos y encuentra 0 candidatos. `git diff --check` correcto. |

Los logs y proyecciones sanitizadas permanecen fuera de Git. No se guardan JWS, JWT, claves ni datos de autenticación
en esta documentación. El backend alojado conserva todavía el código anterior: su fila `account_premium_access`
seguía acreditando solo el final inicial 16:11:46 e inició transición aunque Apple confirmaba otra renovación activa.
No se modificó manualmente la concesión ni se borró el historial del tester. Al cerrar esta validación local, la entrega
Git, CI y despliegue Sandbox de la corrección estaban pendientes; la issue registra su estado posterior. Después del
despliegue hay que recuperar la compra existente y comprobar Premium activo, la vigencia persistida y las notificaciones
de renovación. #39 permanece abierta.
