# Validación del arranque del servidor — issue #1

Fecha: 19 de septiembre de 2026. Trabajo asociado a [la issue #1](https://github.com/JFrancoG/SmartShoppingList/issues/1).

Este documento conserva evidencia técnica; el plan vigente y el seguimiento operativo permanecen en la issue. Distingue la evaluación inicial de Vapor 5.0.0-beta.2 de la migración posterior a Vapor 4.122.2 sobre la rama `codex/issue-1-vapor-postgres-linux`, con base `c19d0872de623a712f2d640c3b0e31b7be27c623` y cambios todavía sin commit en el momento de ejecutar las comprobaciones. No acredita una entrega en `main`; cada resultado corresponde a la versión indicada.

La configuración resultante usa Vapor 4.122.2: 21 tests en 4 suites satisfactorios y servidor Linux arm64 validado con PostgreSQL, persistencia tras reinicio y cierre ordenado. El warning del manifiesto de JWTKit permanece visible y fue aceptado expresamente el 19 de septiembre mediante [EXC-001](../dependency-exceptions.md). La issue conserva el estado y los enlaces de entrega. Las secciones siguientes separan los intentos previos de la evidencia final.

## Resultado observado con Vapor 5

El servidor y sus pruebas compilan en macOS; Swift Testing ejecutó satisfactoriamente 20 tests en 3 suites. PostgreSQL estuvo disponible en contenedores separados para desarrollo y pruebas. La comprobación del recorrido nativo registró escritura, lectura y conservación del registro de desarrollo después de los tests y de reiniciar PostgreSQL y la aplicación.

La compilación Linux arm64 falló con dos imágenes Swift 6.4 distintas. Por tanto, esta evaluación de Vapor 5 no demuestra una imagen ejecutable del servidor, atención HTTP desde Linux ni despliegue. El tramo posterior documenta la alternativa Vapor 4 autorizada y las comprobaciones independientes de esa migración.

## Entorno y versiones evaluadas

| Componente | Versión o configuración |
|---|---|
| Host | macOS 27.0, build `26A428`, arm64 |
| Toolchain nativo | Apple Swift 6.4, `swiftlang-6.4.0.34.1`, target `arm64-apple-macosx27.0.0` |
| Docker | Cliente y motor 29.3.1; motor Linux arm64 |
| Vapor | `5.0.0-beta.2`, revisión `5dfe8b81197d9edfe0298a3961ee119c11e413fd` |
| Persistencia | FluentKit `1.57.0`, FluentPostgresDriver `2.12.0`, PostgresNIO `1.33.1` |
| Identidad | JWTKit `5.7.1` |
| PostgreSQL | `18.6-alpine3.24`, imagen fijada por digest en Compose |
| Base de desarrollo | Servicio `db`, volumen persistente, puerto local 5432 |
| Base de pruebas | Servicio `db-test`, usuario y base distintos, puerto local 5433, almacenamiento temporal |

La resolución inicial está conservada en el `Package.resolved` del snapshot de Vapor 5; el tramo posterior identifica los cambios de Vapor 4. Las pruebas Linux se dirigieron a `aarch64`/arm64; no se ejecutó una compilación amd64 y los resultados no se extrapolan a esa arquitectura.

## Vapor 5: compilación y ejecución nativas

Desde `server/`, se utilizaron los comandos:

```bash
docker compose --profile testing up -d --wait db db-test
swift build --build-tests --force-resolved-versions
swift test --skip-build
swift run --skip-build SmartShoppingListServer --hostname 127.0.0.1 --port 8081
```

`postgres-start.log` registra ambos servicios como saludables. `macos-build-4.log` termina con `Build complete! (3,87 secs)` y no contiene diagnósticos de warning o error. Esa invocación incremental compila; la ejecución de los tests se acredita por separado en `macos-tests-2.log`, a las 10:37 del 19 de septiembre, hora de Madrid.

El resumen de Swift Testing es `Test run with 20 tests in 3 suites passed after 0.222 seconds`. El número 20 corresponde a tests declarados, algunos parametrizados; no equivale al número de combinaciones de argumentos. Las suites cubren:

- Operaciones HTTP de la plantilla `Todo` con PostgreSQL real, conservación de registros ajenos a una eliminación, transacción confirmada, rollback completo por una restricción y propagación de un fallo de migración.
- Rechazo de configuraciones de prueba inseguras o implícitas antes de utilizar una base de datos.
- Verificación criptográfica y de claims de identidad mediante fixtures sintéticos, incluidos los casos malformados descritos abajo.

El diagnóstico de error `Issue1ExpectedFailingMigration` que aparece en el log forma parte del test de rechazo deliberado de la migración; el test y la suite terminan satisfactoriamente. Los tiempos registrados describen esa ejecución local y no son una medida de rendimiento del producto.

`macos-server.log` y `macos-server-restarted.log` registran el arranque nativo en `127.0.0.1:8081` y las peticiones del recorrido. `persistence-result.json` conserva resultados `PASS` para `native_and_postgres_restart` y `development_data_after_tests`: el registro sentinela siguió disponible después de reiniciar PostgreSQL y el servidor, y la limpieza de pruebas no borró los datos de desarrollo. Esta evidencia corresponde al servidor nativo conectado a PostgreSQL en Docker, no al ejecutable del servidor dentro de Linux.

## Verificación de identidad y límites

Los fixtures RSA se firmaron externamente con OpenSSL. Las pruebas comprueban firma, selección de clave, algoritmo permitido, issuer de Apple, client ID, caducidad, nonce y subject. Incluyen tokens alterados, clave desconocida o ausente, caducidad en el instante límite, claims incorrectos y errores genéricos sin exponer el token.

Se añadieron regresiones para audiencias malformadas sin firma, una audiencia vacía con firma válida y un header RS384 firmado con RSA/SHA256. El parseo previo inspecciona exclusivamente el header; la audiencia del payload se decodifica como el client ID de Apple después de verificar la firma, evitando el `precondition` de `AudienceClaim` ante una lista vacía en JWTKit 5.7.1.

Esto demuestra la viabilidad del verificador con claves y tokens sintéticos confiables. No se ha autenticado una cuenta Apple real. Recuperación y rotación de JWKS, emisión y consumo único del nonce, intercambio del código, sesión y revocación pertenecen a [la issue #4](https://github.com/JFrancoG/SmartShoppingList/issues/4), conforme al contrato pendiente de concretar. No hay una ruta pública de autenticación implementada por esta prueba.

JWTKit 5.7.1 emite durante la resolución un warning en `Package@swift-6.4.swift:10` por `.watchOS(.v8)`: Swift 6.4 considera watchOS 9 la versión mínima soportada. Se observa en `resolve.log` y en los builds Linux. No se ha parcheado el checkout ni suprimido el diagnóstico. Los targets propios mantienen warnings como errores, pero el build incremental satisfactorio no permite afirmar que toda la resolución de dependencias esté libre de warnings.

## Vapor 5: intentos de compilación Linux

Los builds respetaron `Package.resolved`, utilizaron configuración Release, cuatro trabajos y enlace estático del runtime Swift con jemalloc. Ninguno de estos intentos produjo una imagen ejecutable validada:

| Evidencia | Variante | Resultado |
|---|---|---|
| `linux-build.log` | `swiftlang/swift:nightly-6.4.x-noble`, digest `77b7c64fd73b13d72b11cbfe2b8e763f7cff3e47b4f2d498f0ce43422673ba45` | Falla en PostgresNIO: uso ambiguo de `elementsEqual(_:by:)` |
| `linux-build-stable.log` | `swift:6.4.0-noble`, digest `64bab762bc73a3fda6d9ebc559258bd6d7660c10a705bb25ecacad2f99d066f9` | Reproduce la ambigüedad en el mismo punto de PostgresNIO |
| `linux-import-visibility-probe.log` | Prueba temporal con `MemberImportVisibility` aplicado globalmente | Falla por imports ausentes en PostgresNIO, incluidos Foundation y Dispatch |
| `linux-per-file-probe.log` | Prueba temporal con `-no-whole-module-optimization` | Falla al abrir el archivo de dependencias `NIOHTTPCompression-primary.d` |

Los dos primeros logs localizan la ambigüedad en `PostgresNIO/New/Connection State Machine/ConnectionStateMachine.swift:1272`. Los ensayos con flags fueron diagnósticos temporales en Dockerfiles externos al repositorio; no se adoptaron como solución ni se modificaron las dependencias. Estos resultados no prueban una incompatibilidad general de Vapor 5 con Linux: delimitan el fallo de la combinación y arquitectura evaluadas.

## Trazabilidad de la evidencia

Los logs crudos y el snapshot de Vapor 5 se conservaron fuera del repositorio en `/tmp/smartshoppinglist-issue1.RuQszw/`; son artefactos locales temporales, no adjuntos persistentes de GitHub. El subdirectorio `vapor5-snapshot/` conserva la implementación evaluada antes de migrar; `vapor4-probe/` conserva el ensayo aislado de dependencias. Este documento resume sus resultados y la issue contiene las decisiones de ejecución.

| Archivo | SHA-256 del registro consultado |
|---|---|
| `macos-build-4.log` | `554247c2c69a146ea41e031d8f182a27b96f4ebace8b0ac5b5c91f9437ec7335` |
| `macos-tests-2.log` | `d4d44c1729fa558b576543251e740a85eea4f1916479122be1208b23039b28d5` |
| `persistence-result.json` | `6d539b5dae1285d262dd649b0af459486ddbf05de383335d3eb15725b68174b0` |
| `linux-build.log` | `5c9221e7541f2fd10c7ad720fab6c17322c486e42e32afdc3130200a2cfd82af` |
| `linux-build-stable.log` | `e2ddad7635e61f78ded3c9ee54ee7db1433426d3c403e4239b30ceb210fee179` |
| `linux-import-visibility-probe.log` | `86235d2307ba91a0a4b6855bd1491e021613d8bcfc3b2701f31488dc7eb47d86` |
| `linux-per-file-probe.log` | `1008b58b09021612293645520ad3869c0ee54f3513abe1cfcda8a85fe63ec0b6` |
| `vapor4-resolve.log` | `611d35f61283ed2ae9323270b76805aa35291ad9c3e017a96c6b90b7ab27afcd` |
| `vapor4-resolve-2.log` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` |
| `vapor4-macos-build.log` | `141d94af33d068bdd316adb7f0807419e51797ed73c185bbf4e31c46327d3cd0` |
| `vapor4-macos-tests.log` | `a8941070989bd1929181ae89a96eccedc575829a94bf2085e71e503882530ea0` |
| `vapor4-native-result.json` | `c1c90261edd95ccc00547f97cc004132a4f467cbe0d3937d1a67c0d9605e99bd` |
| `vapor4-probe-build.log` | `610ec4e9acd32bc4a7865e72ae64356cd452c90095ebe212a0b3a62bd3430ab1` |
| `vapor4-probe-dynamic-build.log` | `d4bfbddfc2e5f6b5ef5ac30c77ebe6870b6bedbf7b80536177e060cfdd7fe713` |
| `vapor4-probe-run.log` | `0d2d7f3eef5aa4ceec780e8b3d863e46f9c428bb35712163434c2ce1044b1dd8` |
| `vapor4-linux-build-final.log` | `6f6dc81cb00bfcf9042ca62c77f2bc18a0cae2a1ce713aafde70be1d0888371f` |
| `vapor4-linux-start.log` | `565bd4e3c908b6ec9289b98b7fb715e52f6220c497d3181e8b9686447ce3fe4e` |
| `vapor4-linux-ldd.log` | `96c4a18d73892224a75d8669325337028a7992db30f9b0987f13fcf0cd0e7272` |
| `vapor4-linux-result.json` | `f3ac3cc16ec0e845e9b52b0810840fc7da1ef04085360db406f5c3e153d5bf89` |
| `vapor4-linux-runtime.log` | `0a2a1acc695b9d3c9930c2a804f76d49090a9fe97177a9915f727ad7ea25d23b` |
| `vapor4-macos-tests-final.log` | `d8d5b22db9640f5dbbdf73cc7712ec7b1eb1362a90a2902e1330818ec90085f7` |
| `vapor4-shutdown-negative-control.log` | `bc5b1003a929a5777c36e5c54fa9c0d8cc81e9b2137b36dbf64a8732516c6704` |
| `vapor4-final-verification.log` | `c220917ef07e7d9ddbf180a715e6f3dede8a893a1b5275051022f002e299faec` |

Las instrucciones de ejecución y las fuentes técnicas se mantienen en [el README del servidor](../../server/README.md#referencias), incluida la [verificación de identidad de Apple](https://developer.apple.com/documentation/signinwithapple/verifying-a-user).

## Vapor 4: decisión y validación nativa de la migración

Se adoptó la alternativa autorizada Vapor 4.122.2, revisión `33e61d0a02a9ddc9f025f8398a0dc24774f6cbe1`, después de los fallos reproducidos con Vapor 5 y de comprobar por separado la combinación de dependencias de Vapor 4. La ventana registrada de esta sesión fue el 19 de septiembre de 08:22 a 09:08 UTC, aproximadamente 46 minutos transcurridos. No hay una medida completa del tiempo técnico de las sesiones anteriores y no se declara agotado el máximo acordado de cuatro horas.

### Ensayo de runtime Linux

`vapor4-probe-build.log` registra un fallo de enlace estático en Foundation, con referencias no resueltas a CoreFoundation, como `CFCharacterSetGetPredefined`. Al retirar `--static-swift-stdlib`, `vapor4-probe-dynamic-build.log` termina satisfactoriamente y exporta la imagen del probe. La ejecución del probe dinámico terminó con código 0 y su salida está conservada en `vapor4-probe-run.log`.

El probe solo importa Vapor, FluentKit, FluentPostgresDriver y JWTKit y emite una línea de identificación; no arranca un servidor ni conecta con PostgreSQL. Su resultado permite elegir enlace dinámico, pero no acredita el servidor completo. El Dockerfile real combina las imágenes oficiales fijadas `swift:6.4.0-noble` para compilar y `swift:6.4.0-noble-slim` para ejecutar, con digest de runtime `460e6eab278b1695fb4b04bc20c77c68dc6f0b4e422aa867e465d6805bc1eeca`.

### Resolución del repositorio real

La primera resolución después del cambio de versión falló por metadatos de traits de Vapor 5 todavía presentes: `MacroRouting`, `WebSockets`, `Multipart` y `HTTPClient` no existen como traits de Vapor 4. El segundo intento regeneró los metadatos y terminó con código 0 sin parches de dependencias. Su log `vapor4-resolve-2.log` está vacío; el resultado se acompaña de la resolución concreta y de la compilación posterior, no se interpreta el archivo vacío como prueba autónoma de éxito.

Respecto al snapshot de Vapor 5, el `Package.resolved` real cambia Vapor a 4.122.2, ConsoleKit a 4.16.1, MultipartKit a 4.7.1 y RoutingKit a 4.9.3; añade WebSocketKit 2.16.2 y retira `swift-http-api-proposal`, `swift-http-server` y `swift-syntax`. Conserva las versiones de las demás dependencias, incluidas FluentKit 1.57.0, FluentPostgresDriver 2.12.0, PostgresNIO 1.33.1, AsyncHTTPClient 1.35.0 y JWTKit 5.7.1.

### Compilación, tests y conservación de datos

En el repositorio real, `swift build --build-tests --force-resolved-versions` terminó con código 0 y `Build complete! (23,56 secs)` en `vapor4-macos-build.log`. `swift test --skip-build` terminó con código 0 y `Test run with 20 tests in 3 suites passed after 0.215 seconds`, a las 10:59 del 19 de septiembre, hora de Madrid. El recuento mantiene la distinción entre tests declarados y argumentos parametrizados. Estos resultados son propios de Vapor 4; no se reutiliza como validación suya la ejecución de Vapor 5.

La ejecución nativa utiliza ahora:

```bash
swift run --skip-build SmartShoppingListServer serve --hostname 127.0.0.1 --port 8081
```

`vapor4-native-result.json` registra `PASS` para la respuesta `/hello`, la conservación del registro creado con Vapor 5 después de los tests y del cambio de versión, y la creación de un registro nuevo desde Vapor 4. No se borró ni reinicializó la base de desarrollo para obtener este resultado.

El warning upstream de JWTKit también figura en `vapor4-resolve.log` y en el ensayo Linux. El éxito de las invocaciones posteriores no elimina esa limitación ni autoriza afirmar que todo el proceso esté libre de warnings.

### Regresión del cierre ordenado y control negativo

Se añadió una cuarta suite con una petición TCP real a un puerto efímero. El test mantiene la petición activa hasta que comienza el cierre HTTP y entonces ejecuta `SELECT 42`; requiere respuesta HTTP 200 y cuerpo `42`. No crea ni revierte tablas, por lo que no depende de los esquemas que utiliza la suite de la aplicación. `vapor4-macos-tests-final.log` registra 21 tests en 4 suites satisfactorios en 0.213 segundos, incluido este recorrido.

Para comprobar que la regresión detecta el defecto, se retiró temporalmente solo `await application.server.shutdown()` del lifecycle y se ejecutó esa suite. `vapor4-shutdown-negative-control.log` registra compilación satisfactoria y fallo del test con código de proceso 1: la petición recibió HTTP 500 y el servidor notificó `noDatabaseConfigured`, porque el pool se había cerrado antes de terminar la petición. El warning de runtime pertenece a ese control negativo esperado; es distinto del warning de compilación del manifiesto de JWTKit, que también permanece visible en ese log.

La línea de producción se restauró al terminar el control. Después se ejecutó `swift test --force-resolved-versions` sobre la fuente restaurada y el proceso terminó con código 0: `vapor4-final-verification.log` registra `Build complete! (2,97 secs)` y 21 tests en 4 suites satisfactorios en 0.223 segundos, a las 11:06:42 del 19 de septiembre, hora de Madrid. El control negativo no forma parte del código entregable ni convierte el fallo intencionado en una regresión pendiente del estado final.

### Validación Linux del servidor completo

El build final del servidor completo terminó con código 0 en `vapor4-linux-build-final.log`; contiene `Build complete! (3.87 secs)` y la exportación de `smartshoppinglistserver:local`. Es una compilación incremental con caché, no una medición de tiempo desde cero. Incluye la corrección que espera al cierre del servidor HTTP antes de cerrar el pool de base de datos y el healthcheck HTTP de `/hello` utilizado por Compose.

`vapor4-linux-start.log` registra PostgreSQL y la aplicación como saludables después de `docker compose up -d --wait app`. La inspección `ldd` del ejecutable dentro de la imagen, conservada en `vapor4-linux-ldd.log`, resuelve sus bibliotecas dinámicas y no contiene dependencias `not found`.

`vapor4-linux-result.json` registra resultados `PASS` para `/hello`, la lectura desde Linux de los registros creados por los servidores nativos y la creación y lectura de un registro nuevo desde Linux. Después de detener la aplicación y reiniciar PostgreSQL y la aplicación, se conservaron los tres registros sentinela: el de Vapor 5 nativo, el de Vapor 4 nativo y el de Vapor 4 Linux. El cierre de la aplicación terminó con código 0. `vapor4-linux-runtime.log` conserva los arranques y las peticiones de ese recorrido.

La imagen comprobada es `sha256:eda4c17b6b8b1581ba91c89a4eefa29ae342f107369e048d13ffb673e7f73207`, arquitectura arm64, usuario `vapor:vapor` y healthcheck `healthy`. Esta evidencia valida el arranque y la persistencia de la plantilla del servidor completo en Linux arm64 con PostgreSQL; no es un despliegue Railway ni una comprobación amd64.

Al finalizar se comprobó que la última ejecución de tests había conservado los datos de desarrollo y se eliminaron exclusivamente los tres registros creados para esta validación. `validation-cleanup.json` registra sus IDs y la conservación del volumen; los servicios Docker de desarrollo y pruebas siguen disponibles. La ejecución nativa auxiliar se detuvo.

### Decisión y límites del resultado

Se fija Vapor 4.122.2 con el runtime dinámico oficial Swift 6.4.0 para esta base del servidor. La decisión se apoya en las comprobaciones nativas y Linux del repositorio real, además del diagnóstico fallido con Vapor 5. Se conservan los resultados anteriores para explicar la elección sin presentar como compatibles combinaciones que no se ejecutaron correctamente.

El resultado final comprende 21 tests en 4 suites sobre la fuente restaurada y el servidor completo ejecutado en Linux arm64. El warning del manifiesto de JWTKit permanece visible; [EXC-001](../dependency-exceptions.md) permite entregar este bloque con ese único aviso externo. No se han validado autenticación Apple real, despliegue HTTPS ni los recorridos del MVP. El cierre y los enlaces definitivos de entrega se registran en la issue después de verificar la integración en `main`.

## Comprobaciones previas a la entrega con EXC-001

El 19 de septiembre se aprobó expresamente la excepción de JWTKit y la entrega completa. La auditoría independiente de `swift-source-style` revisó los 13 archivos Swift modificados o nuevos; cinco ajustes de distribución de líneas quedaron aplicados y la segunda revisión terminó sin hallazgos. No cambió el comportamiento de producción ni las aserciones.

La compilación nativa posterior terminó correctamente en 4,45 segundos. El primer intento de tests falló por conexión a PostgreSQL: los tres servicios Docker estaban detenidos con código 0 desde las 09:24:52 UTC. Se levantaron con `docker compose --profile testing up -d --wait app db-test` y la repetición `swift test --skip-build` ejecutó satisfactoriamente 21 tests en 4 suites en 0.216 segundos.

La imagen Linux arm64 volvió a compilar en Release (5.62 segundos de compilación); el nuevo contenedor pasó su healthcheck y respondió correctamente a `/hello` y `/todos`. Su ID es `sha256:c7c8ce7f561a78cbd54109e8ad74677ca2274542621a32fe31aa1fda61336484`. La evidencia previa de transacciones, reinicios y control negativo de cierre se conserva: los cambios posteriores son de formato y documentación. GitHub no tiene workflows de CI configurados; estos resultados corresponden a validación local.

Los registros temporales de esta comprobación están en `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/smartshoppinglist-delivery-_1w5_525`:

| Archivo | SHA-256 |
|---|---|
| `swift-test.log` | `62aece7e3d6b79d28c8d8533e305f3f69b173b25e39d4d6f9a249c165156955d` |
| `swift-test-ready.log` | `8ea327b64f2ec20b3730254e20d706d740c6602cddd2adc37994f41d7ebcb96e` |
| `linux-build.log` | `d281366d3c6c88b44b8229f6e427b8d3736d2d4acaffa4da81ea357c79d89189` |
| `delivery-result.json` | `01086814f729934966aed55c2e6183f674cbaf93d56e5d023f6e05352d06b464` |
