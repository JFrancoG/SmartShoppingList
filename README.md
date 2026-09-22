# SmartShoppingList

MVP para ACoding Hackathon 2026. Alcance aprobado el 18 de septiembre y actualizado el 19 de septiembre de 2026; entrega el 27 de septiembre.

Una persona dicta lo que necesita comprar y dónde. Revisa los productos interpretados antes de guardarlos. Su grupo consulta los pendientes por tienda, marca productos durante la compra y confirma los seleccionados al terminar. Los no marcados siguen pendientes.

## Documentación

- [Especificación del MVP](docs/mvp-spec.md): comportamiento aprobado, criterios de aceptación y exclusiones.
- [Plan de implementación](docs/implementation-plan.md): fases, dependencias y condiciones para avanzar.
- [Contrato técnico del MVP](docs/contracts/mvp-api.md): operaciones OpenAPI, modelo, reintentos y ejemplos verificables para implementar cliente y servidor.
- [GitHub Issues](https://github.com/JFrancoG/SmartShoppingList/issues): seguimiento operativo, planes de cada bloque, bloqueos y evidencias.
- [Hito MVP · 27 septiembre](https://github.com/JFrancoG/SmartShoppingList/milestone/1): trabajo de la entrega; los primeros bloques son [servidor #1](https://github.com/JFrancoG/SmartShoppingList/issues/1), [contrato #2](https://github.com/JFrancoG/SmartShoppingList/issues/2), [entrada iOS #3](https://github.com/JFrancoG/SmartShoppingList/issues/3) y [colaboración #4](https://github.com/JFrancoG/SmartShoppingList/issues/4).
- [Preparación de Git](docs/git-setup.md): configuración local y referencia de la inicialización ya completada.
- [Servidor](server/README.md): requisitos y comandos de PostgreSQL, compilación, pruebas y ejecución.
- [Borrador iOS](docs/architecture/ios-draft.md): decisiones de entrada, revisión y conservación local.
- [Recorrido compartido](docs/architecture/shared-shopping.md): identidad, grupos, persistencia y reintentos.
- [Configurar el acceso compartido](docs/setup/shared-shopping.md): Apple, orígenes HTTPS, enlaces universales y ensayo con dos usuarios.
- [Validación de la compra](docs/validation/issue-11-purchase-flow.md): selección, reintentos, conflictos y activación pendiente.
- [Validación del bloque 4](docs/validation/issue-4-shared-flow.md): pruebas locales y requisitos reales pendientes.
- [Validación del borrador](docs/validation/issue-3-ios-draft.md): pruebas, disponibilidad real de modelos y comprobaciones pendientes.
- [Validación del arranque](docs/validation/issue-1-server-bootstrap.md): versiones evaluadas, resultados y límites de la prueba técnica del servidor.
- [Excepciones de dependencias](docs/dependency-exceptions.md): diagnósticos externos aceptados expresamente, alcance y condiciones de retirada.

## Estructura

- `ios/SmartShoppingList/`: proyecto Xcode de la app.
- `server/`: servidor Vapor, migraciones PostgreSQL y pruebas HTTP del contrato.
- `docs/`: especificación, fases y documentación técnica compartidas.

Los tres directorios se versionan juntos desde esta raíz.

## Base del proyecto

El punto de partida, publicado el 19 de septiembre en el commit [c19d087](https://github.com/JFrancoG/SmartShoppingList/commit/c19d0872de623a712f2d640c3b0e31b7be27c623), contiene la definición funcional aprobada y las plantillas de iOS y Vapor: pantalla inicial en la app y ejemplo `Todo` en el servidor. El progreso posterior y sus evidencias se consultan en GitHub Issues.

Marco técnico: iOS 27 como versión mínima, SwiftUI, Swift 6 con concurrencia estricta, Speech y Foundation Models. El servidor usa Vapor 4.122.2, la alternativa autorizada tras los fallos de compilación Linux de la combinación evaluada con Vapor 5.0.0-beta.2. Se ha comprobado el servidor en macOS y Linux arm64 local, con PostgreSQL; la evidencia y los límites se conservan en el informe enlazado. El alojamiento propuesto es Railway. La app no incorpora dependencias de terceros.

En ese punto de partida se comprobaron Xcode 27, SDK iOS 27 y Swift 6.4, con Vapor 5.0.0-beta.2 en `Package.resolved`. Se compiló el servidor junto con sus targets de pruebas en macOS, sin warnings ni errores reportados; esa comprobación no ejecutó las pruebas contra PostgreSQL.

La validación acordada combina entrada manual en el iPhone físico sin Apple Intelligence y Foundation Models en un simulador compatible del Mac, previa comprobación de disponibilidad. Voz e IA siguen dentro del alcance; cada prueba identificará su entorno según la [estrategia de validación](docs/mvp-spec.md#estrategia-de-validación-acordada).

## Compilación y pruebas iOS

Abrir `ios/SmartShoppingList/SmartShoppingList.xcodeproj` con Xcode 27, seleccionar el esquema compartido `SmartShoppingList` y un iPhone o simulador con iOS 27. Ejecutar la app para preparar el borrador local. Para las pruebas, seleccionar el plan `Fast` o `Integration` y ejecutar Test; ambos usan Swift Testing y no requieren IA ni micrófono.

La entrada manual permite añadir nombre, cantidad opcional y tienda. Con el acceso compartido configurado, la revisión exige confirmar las tiendas antes de incorporar el lote al grupo. La pestaña Comprar permite acceder con Apple, crear un grupo o aceptar una invitación y consultar sus pendientes por tienda. Sin configurar el servidor, el borrador local sigue disponible. La selección local por tienda y la finalización atómica de compra se implementan en #11; requieren desplegar el servidor de esa rama antes del ensayo alojado. Edición, cancelación, historial y consulta de tienda por voz siguen pendientes de fase 2. Las pruebas reales de voz, Foundation Models y físico tienen requisitos y evidencia separados en los informes enlazados.

## Compilación del servidor

Desde la raíz:

```bash
cd server
swift build --build-tests --force-resolved-versions
```

Este comando compila las pruebas, pero no las ejecuta. El [README del servidor](server/README.md) explica cómo preparar PostgreSQL, ejecutar Swift Testing y arrancar Vapor 4 mediante `serve`. Los resultados de arranque con PostgreSQL, tests y Linux se registran en [#1](https://github.com/JFrancoG/SmartShoppingList/issues/1), y los de iOS y el recorrido compartido en [#3](https://github.com/JFrancoG/SmartShoppingList/issues/3) y [#4](https://github.com/JFrancoG/SmartShoppingList/issues/4).

Git está inicializado y el primer commit está publicado en este repositorio. El README del servidor contiene los comandos del entorno local; el despliegue HTTPS se aborda en el bloque del recorrido compartido.
