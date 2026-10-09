# SmartShoppingListServer

Servidor del MVP configurado con Vapor 4.122.2, Fluent/PostgreSQL y Swift 6.4. Se utiliza la alternativa Vapor 4 autorizada después de que la combinación evaluada con Vapor 5.0.0-beta.2 fallara al compilar PostgresNIO en Linux. Implementa identidad Apple, sesiones, grupos, invitaciones, incorporación por lotes, consulta por tienda, compra atómica de los productos seleccionados, edición y cancelación. Conserva los registros comprados y cancelados como historial mínimo, sin una pantalla de historial. La plantilla Todo permanece como prueba local de infraestructura y no se registra en producción.

La unidad #33 incorporó administración transferible, consulta de miembros y salida con cierre explícito del último miembro. La unidad #35 añade pertenencias múltiples, listado paginado de los grupos de la cuenta y capacidades para crear o incorporarse conforme al [contrato 0.3.0](../docs/contracts/group-memberships.md). La autorización comprueba cada pertenencia; una cuenta puede administrar varios de sus grupos sin consumir plazas adicionales. La selección activa pertenece al cliente y no cambia permisos ni recibos.

La unidad #37 añade [cupos y archivo/restauración, contrato 0.4.0](../docs/contracts/store-quotas.md). La política predeterminada del servidor nuevo aplica **1 grupo por cuenta, 3 tiendas activas por grupo y 20 pendientes por tienda**. Las tiendas/productos usan el plan del administrador actual para todos los miembros; recibir una invitación no consume pertenencia y el rechazo de aceptación por cupo conserva el enlace sin consumir mientras siga vigente. El plan premium aprobado es 5 grupos en total, 10 tiendas activas y 100 pendientes; se inyecta únicamente en pruebas. No hay compras verificadas, pago ni acceso premium activado. El [informe de validación local de #37](../docs/validation/issue-37-store-product-quotas.md) registra build, pruebas, carreras, migración y límites de esta evidencia.

Solo el administrador puede archivar una tienda sin pendientes o restaurarla con una plaza disponible. El archivo conserva identidad normalizada, ID e historial; la consulta ordinaria devuelve solo activas. Un alta/movimiento hacia una archivada se rechaza sin restaurarla ni crear un duplicado. Las admisiones son completas y serializadas por grupo; un rechazo confirmado no deja tiendas huérfanas. Los recibos de rechazo requieren una nueva intención explícita tras liberar capacidad y los éxitos anteriores se reproducen exactamente.

Alcanzar el límite impide crecimiento y conserva contenido y pertenencias. El arranque aplica `AddStoreArchiving` después de `AddGroupMemberships` y `AddGroupAdministration`; todas las tiendas anteriores quedan activas aunque excedan el cupo gratuito. `users.group_id` sigue como proyección legacy sin autoridad. La reversión de archivo rechaza estados archivados para evitar reactivarlos al retirar la columna. Los clientes 0.3 requieren actualización para gestionar los nuevos conflictos de cupo; no se declara compatibilidad funcional completa por añadir campos.

La migración requiere detener las escrituras del backend anterior y reanudar únicamente con la versión nueva; no hay sincronización para escritores antiguos durante un despliegue mixto. Su reversión rechaza los estados que no pueden representarse fielmente mediante una sola pertenencia legacy, sin borrar datos. No ejecutar esta versión contra producción como parte de una prueba local.

El arranque inicial se entregó en [#1](https://github.com/JFrancoG/SmartShoppingList/issues/1); su [informe de validación](../docs/validation/issue-1-server-bootstrap.md) conserva los resultados por versión y entorno. El alcance del producto permanece en [la especificación](../docs/mvp-spec.md).

El recorrido compartido de [#4](https://github.com/JFrancoG/SmartShoppingList/issues/4), la compra de [#11](https://github.com/JFrancoG/SmartShoppingList/issues/11) y la edición/cancelación de [#22](https://github.com/JFrancoG/SmartShoppingList/issues/22) están integrados en `main`. Sus informes conservan la evidencia de [colaboración](../docs/validation/issue-4-shared-flow.md), [compra](../docs/validation/issue-11-purchase-flow.md) y [edición/cancelación](../docs/validation/issue-22-edit-cancel-items.md). La [configuración reproducible](../docs/setup/shared-shopping.md) y la [arquitectura](../docs/architecture/shared-shopping.md) describen PostgreSQL, HTTPS, identidad Apple y enlaces.

La [validación Release del 27 de septiembre](../docs/validation/server-release-2026-09-27.md) acredita compilación nativa macOS, 82 funciones de prueba en 8 suites aprobadas y arranque local del ejecutable en modo producción. El [CI de `6fd8452`](https://github.com/JFrancoG/SmartShoppingList/actions/runs/36314523700), completado el mismo día, acredita las 82 funciones en Linux arm64 Debug y los validadores de contrato/diseño. La [guía de CI](../docs/setup/ci.md) explica su reproducción y alcance. Estas comprobaciones no despliegan Railway ni acreditan una nueva imagen Linux Release, autenticación Apple real o restauración de backups.

## Requisitos

- macOS 26.2 o posterior y Swift 6.4 para ejecución nativa.
- Docker Desktop en ejecución para PostgreSQL y para compilar/ejecutar Linux.
- Puertos locales 5432 (desarrollo), 5433 (pruebas), 8080 (contenedor) y 8081 (ejemplo nativo) disponibles.

Los comandos siguientes se ejecutan desde `server/`. Las credenciales incluidas en Compose son exclusivamente para este entorno local. Los puertos se publican en loopback; una prueba posterior desde iPhone necesita configurar el acceso de red o el despliegue HTTPS.

## PostgreSQL y pruebas

```bash
docker desktop start
docker compose --profile testing up -d --wait db db-test
docker compose --profile testing ps
swift build --build-tests --force-resolved-versions
swift test --skip-build
```

`db` conserva los datos de desarrollo en el volumen `db_data`. `db-test` usa otro usuario, otra base, el puerto 5433 y almacenamiento temporal que se pierde al detenerlo. El test harness prepara sus migraciones por caso y vacía los datos de esa base exclusiva antes de revertirlas; así la limpieza no requiere una reversión con pérdida de pertenencias. Los tests de base de datos se ejecutan en serie.

| Variable | Desarrollo nativo | Pruebas |
|---|---|---|
| Host | `DATABASE_HOST=localhost` | `TEST_DATABASE_HOST=127.0.0.1` |
| Puerto | `DATABASE_PORT=5432` | `TEST_DATABASE_PORT=5433` |
| Usuario | `DATABASE_USERNAME=vapor_username` | `TEST_DATABASE_USERNAME=vapor_test` |
| Contraseña local | `DATABASE_PASSWORD=vapor_password` | `TEST_DATABASE_PASSWORD=vapor_test_password` |
| Base | `DATABASE_NAME=vapor_database` | `TEST_DATABASE_NAME=smartshoppinglist_testing` |

Son los valores por defecto. Para variar el puerto del contenedor de pruebas, exportar `TEST_DATABASE_PORT` antes de levantar Compose y ejecutar los tests. El resto de cambios de conexión requieren preparar la base correspondiente.

Las pruebas nunca heredan `DATABASE_*` como conexión. Rechazan nombres sin sufijo `_testing`, un nombre igual al de desarrollo, hosts fuera del entorno local y puertos inválidos. `configure` exige una configuración de base explícita para aplicaciones `.testing`. No ejecutar varias suites de integración a la vez contra la misma base.

La suite cubre operaciones HTTP con persistencia real, commit y rollback por fallo de restricción, propagación de errores de migración, guardas de configuración, sesiones, invitaciones concurrentes, compra, edición, cancelación, aislamiento e idempotencia. Las pruebas de identidad usan tokens y concesiones sintéticos, sin acceso a cuentas Apple. Los comandos anteriores compilan y ejecutan Debug; para Release, usar el [procedimiento validado del 27 de septiembre](../docs/validation/server-release-2026-09-27.md#compilación-y-pruebas), que compila el producto y ejecuta `swift test -c release --enable-testable-imports` por separado.

## Ejecución nativa

```bash
swift run --skip-build SmartShoppingListServer serve --hostname 127.0.0.1 --port 8081
```

Desde otra terminal:

```bash
curl --fail http://127.0.0.1:8081/hello
curl --fail http://127.0.0.1:8081/todos
```

El arranque aplica las migraciones registradas antes de servir peticiones; sus errores se propagan. El cierre termina primero las peticiones HTTP y después cierra el pool. El entrypoint de Vapor 4 usa `app.execute()` para ejecutar el comando `serve` y `app.asyncShutdown()` para liberar los recursos tanto al terminar como ante un error. No hay comandos independientes `migrate` o `revert` registrados en esta aplicación: la integración utiliza FluentKit directamente.

## Contenedor Linux

```bash
docker compose build app
docker compose up -d --wait app
curl --fail http://127.0.0.1:8080/hello
docker compose logs app
```

Compose espera a que PostgreSQL esté saludable y `--wait` comprueba el healthcheck HTTP de la app en `/hello`. Si se retira esa ruta, debe actualizarse también el healthcheck del Dockerfile. El contenedor utiliza la misma base de desarrollo, por lo que comparte los registros creados desde la ejecución nativa. En `--env production`, `/todos` devuelve 404; los datos del producto se consultan en `/v1` con una sesión válida.

Las imágenes oficiales de compilación `swift:6.4.0-noble` y ejecución `swift:6.4.0-noble-slim`, y la imagen PostgreSQL, están fijadas por digest. El ejecutable usa enlace dinámico con el runtime Swift correspondiente; el ensayo de enlace estático falló en Foundation con el toolchain Linux evaluado. Se comprobaron las bibliotecas del ejecutable, el arranque HTTP y la persistencia tras reiniciar la app y PostgreSQL.

`Package.resolved` se respeta en Linux y el build limita el paralelismo a cuatro trabajos para el entorno Docker local. Para cambiarlo explícitamente: `docker compose build --build-arg SWIFT_JOBS=4 app`. El comando del contenedor es `serve --env production --hostname 0.0.0.0 --port 8080`. Fijar las imágenes no convierte las instalaciones APT en una compilación idéntica bit a bit; una comprobación arm64 tampoco acredita amd64.

## Detener el entorno

```bash
docker compose --profile testing stop
```

Esto conserva el volumen de desarrollo y descarta los datos temporales de pruebas. La siguiente ejecución de tests vuelve a preparar sus migraciones. Evitar `down -v` salvo que se quiera borrar expresamente la base de desarrollo.

## Identidad Apple

`AppleIdentityTokenVerifier` recibe una instantánea confiable de las claves públicas de Apple y verifica firma RS256, identificador de clave, issuer, audience, caducidad, nonce y subject. Devuelve errores genéricos sin incluir el token.

El bloque 4 añade obtención y rotación de JWKS, challenge de un solo uso, canje del código, cifrado de refresh tokens, sesión persistente y revalidación diferida. La [guía de configuración](../docs/setup/shared-shopping.md) describe los secretos necesarios y el límite de una réplica. Las pruebas automáticas usan un gateway de Apple controlado; no acreditan acceso con dos Apple IDs reales.

JWTKit 5.7.1 emite un warning de deprecación en su manifiesto Swift 6.4 por declarar watchOS 8. El responsable del proyecto aceptó el 19 de septiembre la excepción temporal [EXC-001](../docs/dependency-exceptions.md), limitada a ese diagnóstico. El warning sigue visible y los targets propios mantienen warnings como errores. No se ha modificado el checkout ni se declara una resolución global libre de warnings.

## Referencias

- [Vapor 4.122.2](https://github.com/vapor/vapor/tree/4.122.2).
- [Imagen oficial de Swift](https://hub.docker.com/_/swift).
- [Orden de arranque y healthchecks en Compose](https://docs.docker.com/compose/how-tos/startup-order/).
- [Volúmenes de la imagen oficial PostgreSQL](https://hub.docker.com/_/postgres).
- [Verificación de identidad Apple](https://developer.apple.com/documentation/signinwithapple/verifying-a-user).
- [JWTKit 5.7.1](https://github.com/vapor/jwt-kit/tree/5.7.1).
