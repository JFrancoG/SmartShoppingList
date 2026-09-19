# SmartShoppingList

MVP para ACoding Hackathon 2026. Alcance aprobado el 18 de septiembre y actualizado el 19 de septiembre de 2026; entrega el 27 de septiembre.

Una persona dicta lo que necesita comprar y dónde. Revisa los productos interpretados antes de guardarlos. Su grupo consulta los pendientes por tienda, marca productos durante la compra y confirma los seleccionados al terminar. Los no marcados siguen pendientes.

## Documentación

- [Especificación del MVP](docs/mvp-spec.md): comportamiento aprobado, criterios de aceptación y exclusiones.
- [Plan de implementación](docs/implementation-plan.md): fases, dependencias, comprobaciones y siguiente paso.
- [Preparación de Git](docs/git-setup.md): configuración local, revisión del primer commit y conexión posterior con GitHub.

## Estructura

- `ios/SmartShoppingList/`: proyecto Xcode de la app.
- `server/`: paquete Swift del servidor Vapor y su plantilla de pruebas.
- `docs/`: especificación y plan operativo compartidos.

Los tres directorios se versionan juntos desde esta raíz.

## Estado actual

Definición funcional aprobada y plantillas de iOS y Vapor creadas. La app conserva su pantalla inicial y el servidor conserva el ejemplo `Todo`; los recorridos del MVP siguen pendientes.

Marco técnico: iOS 27 como versión mínima, SwiftUI, Swift 6 con concurrencia estricta, Speech y Foundation Models. Preferencia por Vapor 5 si supera la prueba inicial de viabilidad; Vapor 4 como alternativa autorizada. Propuesta de persistencia PostgreSQL y alojamiento Railway. La app no incorpora dependencias de terceros.

Entorno comprobado el 19 de septiembre: Xcode 27, SDK iOS 27 y Swift 6.4. El servidor tiene Vapor 5.0.0-beta.2 en `Package.resolved`. Se ha compilado el servidor junto con sus targets de pruebas en macOS, sin warnings ni errores reportados; las pruebas no se han ejecutado contra PostgreSQL.

## Compilación comprobada del servidor

Desde la raíz:

```bash
cd server
swift build --build-tests --force-resolved-versions
```

Este comando compila las pruebas, pero no las ejecuta. La validación del arranque con PostgreSQL, del contenedor Linux, de la app iOS y de los recorridos funcionales sigue pendiente.

Los archivos de preparación de Git están listos; todavía quedan por ejecutar `git init`, el primer commit y la conexión/publicación en GitHub. Las instrucciones de ejecución y servicios se completarán conforme se comprueben.
