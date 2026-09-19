# SmartShoppingListServer

Servidor del MVP configurado con Vapor 4.122.2, Fluent/PostgreSQL y Swift 6.4. Se utiliza la alternativa Vapor 4 autorizada después de que la combinación evaluada con Vapor 5.0.0-beta.2 fallara al compilar PostgresNIO en Linux. El código funcional sigue siendo la plantilla Todo; este bloque comprueba la infraestructura necesaria antes de implementar el contrato del producto.

El seguimiento está en [la issue #1](https://github.com/JFrancoG/SmartShoppingList/issues/1) y los resultados, entornos y límites en [el informe de validación](../docs/validation/issue-1-server-bootstrap.md). Se ha comprobado esta configuración en macOS y en un contenedor Linux arm64 local. El alcance del producto permanece en [la especificación](../docs/mvp-spec.md).

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

`db` conserva los datos de desarrollo en el volumen `db_data`. `db-test` usa otro usuario, otra base, el puerto 5433 y almacenamiento temporal que se pierde al detenerlo. El test harness prepara y revierte sus migraciones por caso; los tests de base de datos se ejecutan en serie.

| Variable | Desarrollo nativo | Pruebas |
|---|---|---|
| Host | `DATABASE_HOST=localhost` | `TEST_DATABASE_HOST=127.0.0.1` |
| Puerto | `DATABASE_PORT=5432` | `TEST_DATABASE_PORT=5433` |
| Usuario | `DATABASE_USERNAME=vapor_username` | `TEST_DATABASE_USERNAME=vapor_test` |
| Contraseña local | `DATABASE_PASSWORD=vapor_password` | `TEST_DATABASE_PASSWORD=vapor_test_password` |
| Base | `DATABASE_NAME=vapor_database` | `TEST_DATABASE_NAME=smartshoppinglist_testing` |

Son los valores por defecto. Para variar el puerto del contenedor de pruebas, exportar `TEST_DATABASE_PORT` antes de levantar Compose y ejecutar los tests. El resto de cambios de conexión requieren preparar la base correspondiente.

Las pruebas nunca heredan `DATABASE_*` como conexión. Rechazan nombres sin sufijo `_testing`, un nombre igual al de desarrollo, hosts fuera del entorno local y puertos inválidos. `configure` exige una configuración de base explícita para aplicaciones `.testing`. No ejecutar varias suites de integración a la vez contra la misma base.

La suite cubre operaciones HTTP con persistencia real, commit y rollback por fallo de restricción, propagación de errores de migración y guardas de configuración. Las pruebas de identidad usan tokens sintéticos firmados externamente, sin acceso a cuentas Apple. La ejecución de cada versión y sus resultados se acreditan en el informe enlazado.

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
curl --fail http://127.0.0.1:8080/todos
docker compose logs app
```

Compose espera a que PostgreSQL esté saludable y `--wait` comprueba el healthcheck HTTP de la app en `/hello`. Si se retira esa ruta de la plantilla, debe actualizarse también el healthcheck del Dockerfile. El contenedor utiliza la misma base de desarrollo, por lo que comparte los registros creados desde la ejecución nativa.

Las imágenes oficiales de compilación `swift:6.4.0-noble` y ejecución `swift:6.4.0-noble-slim`, y la imagen PostgreSQL, están fijadas por digest. El ejecutable usa enlace dinámico con el runtime Swift correspondiente; el ensayo de enlace estático falló en Foundation con el toolchain Linux evaluado. Se comprobaron las bibliotecas del ejecutable, el arranque HTTP y la persistencia tras reiniciar la app y PostgreSQL.

`Package.resolved` se respeta en Linux y el build limita el paralelismo a cuatro trabajos para el entorno Docker local. Para cambiarlo explícitamente: `docker compose build --build-arg SWIFT_JOBS=4 app`. El comando del contenedor es `serve --env production --hostname 0.0.0.0 --port 8080`. Fijar las imágenes no convierte las instalaciones APT en una compilación idéntica bit a bit; una comprobación arm64 tampoco acredita amd64.

## Detener el entorno

```bash
docker compose --profile testing stop
```

Esto conserva el volumen de desarrollo y descarta los datos temporales de pruebas. La siguiente ejecución de tests vuelve a preparar sus migraciones. Evitar `down -v` salvo que se quiera borrar expresamente la base de desarrollo.

## Verificación de identidad: alcance de esta prueba

`AppleIdentityTokenVerifier` recibe una instantánea confiable de las claves públicas de Apple y verifica firma RS256, identificador de clave, issuer, audience, caducidad, nonce y subject. Devuelve errores genéricos sin incluir el token.

Esta prueba no autentica todavía usuarios reales. Obtención y rotación de JWKS, nonce de un solo uso, intercambio del código, sesión y revocación se integrarán conforme al contrato y al recorrido de [la issue #4](https://github.com/JFrancoG/SmartShoppingList/issues/4).

JWTKit 5.7.1 emite un warning de deprecación en su manifiesto Swift 6.4 por declarar watchOS 8. El responsable del proyecto aceptó el 19 de septiembre la excepción temporal [EXC-001](../docs/dependency-exceptions.md), limitada a ese diagnóstico. El warning sigue visible y los targets propios mantienen warnings como errores. No se ha modificado el checkout ni se declara una resolución global libre de warnings.

## Referencias

- [Vapor 4.122.2](https://github.com/vapor/vapor/tree/4.122.2).
- [Imagen oficial de Swift](https://hub.docker.com/_/swift).
- [Orden de arranque y healthchecks en Compose](https://docs.docker.com/compose/how-tos/startup-order/).
- [Volúmenes de la imagen oficial PostgreSQL](https://hub.docker.com/_/postgres).
- [Verificación de identidad Apple](https://developer.apple.com/documentation/signinwithapple/verifying-a-user).
- [JWTKit 5.7.1](https://github.com/vapor/jwt-kit/tree/5.7.1).
