# Servidor Release — 27 de septiembre de 2026

## Resultado

**Producto Release compilado y suite completa aprobada: 82 funciones de prueba en 8 suites, 0 fallos y 0 omitidas.** El ejecutable Release arranca contra PostgreSQL temporal, completa sus migraciones y se cierra con código 0 tras SIGTERM.

Se utiliza Swift 6.4 de Xcode 27.2 beta (`27B5019j`), SwiftPM con su motor `swiftbuild` y macOS arm64. Los 54 archivos versionados de `server/` mantienen sus hashes durante la validación; no se modifica código ni dependencias. La base Git es `3fdae1b9bfddddcb7de1509622a11fa1411dc71d`, con los cambios locales de iOS/documentación fuera del servidor.

## Compilación y pruebas

Desde `server/`, con Docker Desktop iniciado:

```bash
docker compose --profile testing up -d --wait db-test
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  swift build -c release --force-resolved-versions \
  --product SmartShoppingListServer --jobs 4
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
TEST_DATABASE_HOST=127.0.0.1 TEST_DATABASE_PORT=5433 \
TEST_DATABASE_USERNAME=vapor_test TEST_DATABASE_PASSWORD=vapor_test_password \
TEST_DATABASE_NAME=smartshoppinglist_testing \
  swift test -c release --enable-testable-imports \
  --force-resolved-versions --jobs 4
docker compose --profile testing stop db-test
```

Las credenciales del ejemplo corresponden exclusivamente al contenedor temporal de Compose. Solo se arranca `db-test`; no se inicia la base de desarrollo. El harness prepara y revierte las migraciones por caso y serializa los tests que modifican tablas.

El primer intento con `swift build -c release --build-tests` falló al resolver el módulo del ejecutable desde `@testable import SmartShoppingListServer`. La compilación separada del producto y `swift test` con acceso testable habilitado completaron correctamente, sin cambios de código. La opción es predeterminada en `swift test`; el resultado no acredita por sí solo la causa interna del fallo del primer comando.

La suite cubre HTTP y persistencia real, autorización, aislamiento, transacciones, concurrencia, idempotencia, invitaciones, edición, cancelación, compra, configuración de base/TLS, cierre y componentes de identidad Apple. El resumen de Swift Testing confirma 82 funciones en 8 suites en 9,895 segundos; no se presenta esa cifra como número de casos parametrizados. La identidad utiliza fixtures, sin cuentas Apple reales.

El único diagnóstico de compilación observado en la ejecución correcta es el del manifiesto JWTKit 5.7.1 sobre watchOS 8, cubierto por [EXC-001](../dependency-exceptions.md#exc-001--manifiesto-swift-64-de-jwtkit-571). No aparecen otros warnings ni errores. Se conservan warnings como errores en los targets propios. La compilación separada del producto no emite diagnósticos, pero no se afirma que toda la resolución y ejecución estén libres de avisos.

## Arranque del ejecutable

Se conserva una copia del producto antes de compilar los tests. Esa copia arranca con `serve --env production`, en loopback y un puerto libre, desde un directorio temporal sin archivos `.env`. Recibe únicamente la conexión a `smartshoppinglist_testing` en el puerto 5433 y la configuración local de logs. No utiliza claves Apple ni datos de desarrollo o producción.

| Comprobación | Resultado |
|---|---|
| Migraciones | `CreateTodo`, `CreateSharedShopping` y `CreateAppleAuthentication` completadas |
| `GET /hello` | 200, `Hello, world!` |
| `GET /todos` | 404; ruta de infraestructura no registrada en producción |
| Consulta de tiendas sin sesión | 401, `invalid_session` |
| SIGTERM | Cierre con código 0 |

Después del ensayo se detiene el proceso y `db-test`, descartando su almacenamiento temporal. Docker Desktop queda iniciado.

## Evidencia y límites

Evidencia local temporal en `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/smart-list-server-release.ugx5i1uw/`: `build-product-release.log`, `tests-release.log`, `runtime-release.log`, sus códigos de salida, `runtime-results.json`, `validation-summary.json`, `source-hashes.json` y hash del ejecutable. El primer diagnóstico se conserva en `build-release.log`. La ejecución añadió `--xunit-output` apuntando a `tests-release.xml`; SwiftPM generó `tests-release-swift-testing.xml`, con 82 casos, 0 errores, 0 fallos y 0 omitidos. El XML agrupa el resultado en una suite de reporte; el log completo de Swift Testing confirma las 8 suites del código y la ejecución termina con código 0.

El [CI de la misma base](https://github.com/JFrancoG/SmartShoppingList/actions/runs/36283280423) ya acredita la suite en Linux arm64 **Debug**. Este ensayo añade Release nativo macOS y arranque local en modo producción; no recompila el contenedor Linux Release ni despliega Railway. Tampoco acredita autenticación Apple real, restauración de backups o carga sostenida del servicio alojado.
