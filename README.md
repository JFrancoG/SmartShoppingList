# SmartShoppingList

MVP para ACoding Hackathon 2026. Alcance aprobado el 18 de septiembre y actualizado el 19 de septiembre de 2026; entrega el 27 de septiembre.

Una persona dicta lo que necesita comprar y dónde. Revisa los productos interpretados antes de guardarlos. Su grupo consulta los pendientes por tienda, marca productos durante la compra y confirma los seleccionados al terminar. Los no marcados siguen pendientes.

## Documentación

- [Especificación del MVP](docs/mvp-spec.md): comportamiento aprobado, criterios de aceptación y exclusiones.
- [Plan de implementación](docs/implementation-plan.md): fases, dependencias y condiciones para avanzar.
- [GitHub Issues](https://github.com/JFrancoG/SmartShoppingList/issues): seguimiento operativo, planes de cada bloque, bloqueos y evidencias.
- [Hito MVP · 27 septiembre](https://github.com/JFrancoG/SmartShoppingList/milestone/1): trabajo de la entrega; los primeros bloques son [servidor #1](https://github.com/JFrancoG/SmartShoppingList/issues/1), [contrato #2](https://github.com/JFrancoG/SmartShoppingList/issues/2), [entrada iOS #3](https://github.com/JFrancoG/SmartShoppingList/issues/3) y [colaboración #4](https://github.com/JFrancoG/SmartShoppingList/issues/4).
- [Preparación de Git](docs/git-setup.md): configuración local y referencia de la inicialización ya completada.
- [Servidor](server/README.md): requisitos y comandos de PostgreSQL, compilación, pruebas y ejecución.

## Estructura

- `ios/SmartShoppingList/`: proyecto Xcode de la app.
- `server/`: paquete Swift del servidor Vapor y su plantilla de pruebas.
- `docs/`: especificación, fases y documentación técnica compartidas.

Los tres directorios se versionan juntos desde esta raíz.

## Base del proyecto

El punto de partida, publicado el 19 de septiembre en el commit [c19d087](https://github.com/JFrancoG/SmartShoppingList/commit/c19d0872de623a712f2d640c3b0e31b7be27c623), contiene la definición funcional aprobada y las plantillas de iOS y Vapor: pantalla inicial en la app y ejemplo `Todo` en el servidor. El progreso posterior y sus evidencias se consultan en GitHub Issues.

Marco técnico: iOS 27 como versión mínima, SwiftUI, Swift 6 con concurrencia estricta, Speech y Foundation Models. Preferencia por Vapor 5 si supera la prueba inicial de viabilidad; Vapor 4 como alternativa autorizada. Propuesta de persistencia PostgreSQL y alojamiento Railway. La app no incorpora dependencias de terceros.

En ese punto de partida se comprobaron Xcode 27, SDK iOS 27 y Swift 6.4, con Vapor 5.0.0-beta.2 en `Package.resolved`. Se compiló el servidor junto con sus targets de pruebas en macOS, sin warnings ni errores reportados; esa comprobación no ejecutó las pruebas contra PostgreSQL.

La validación acordada combina entrada manual en el iPhone físico sin Apple Intelligence y Foundation Models en un simulador compatible del Mac, previa comprobación de disponibilidad. Voz e IA siguen dentro del alcance; cada prueba identificará su entorno según la [estrategia de validación](docs/mvp-spec.md#estrategia-de-validación-acordada).

## Compilación del servidor

Desde la raíz:

```bash
cd server
swift build --build-tests --force-resolved-versions
```

Este comando compila las pruebas, pero no las ejecuta. Los resultados de arranque con PostgreSQL, tests y Linux se registran en [#1](https://github.com/JFrancoG/SmartShoppingList/issues/1), y los de iOS y el recorrido compartido en [#3](https://github.com/JFrancoG/SmartShoppingList/issues/3) y [#4](https://github.com/JFrancoG/SmartShoppingList/issues/4).

Git está inicializado y el primer commit está publicado en este repositorio. Las instrucciones de ejecución y servicios se completarán conforme se comprueben en las issues correspondientes.
