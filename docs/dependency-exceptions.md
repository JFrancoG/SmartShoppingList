# Excepciones de dependencias y herramientas

Las excepciones requieren un acuerdo explícito y se limitan al diagnóstico, versión y entorno indicados. No desactivan la política de warnings como errores de los targets propios ni permiten aceptar otros avisos.

## EXC-001 · Manifiesto Swift 6.4 de JWTKit 5.7.1

Aceptada por el responsable del proyecto el 19 de septiembre de 2026 para entregar [el bloque 1](https://github.com/JFrancoG/SmartShoppingList/issues/1).

- **Diagnóstico permitido:** `'v8' is deprecated: watchOS 9.0 is the oldest supported version`, emitido por `.watchOS(.v8)` en `Package@swift-6.4.swift:10` de JWTKit 5.7.1 durante la resolución del paquete con Swift 6.4.
- **Motivo:** la declaración afecta al mínimo de watchOS del paquete externo. Nuestro servidor se ejecuta en macOS y Linux; su compilación, pruebas y ejecución con PostgreSQL están comprobadas. No hay una versión oficial corregida disponible en la fecha de aceptación.
- **Alcance:** exclusivamente ese diagnóstico del manifiesto y esa versión fijada. No incluye warnings del código propio, de otras dependencias ni nuevos diagnósticos de JWTKit. No constituye una garantía general sobre la biblioteca.
- **Tratamiento:** conservar el warning visible y JWTKit 5.7.1 fijado. No parchear `.build`, introducir un fork ni añadir flags de supresión. Se mantiene `.treatAllWarnings(as: .error)` en los targets propios.
- **Cierre de #1:** este aviso concreto deja de impedir la entrega por acuerdo explícito. El resultado se informa como validado con EXC-001, sin afirmar una resolución global libre de warnings.
- **Retirada:** al evaluar una versión oficial que corrija el manifiesto, revisar su diff, ejecutar las pruebas de identidad y el resto de Swift Testing, compilar y arrancar Linux y confirmar que el diagnóstico desaparece. Actualizar entonces la dependencia y retirar esta excepción en el mismo cambio.
- **Revisión:** comprobar su vigencia en la próxima actualización de dependencias y durante la revisión de entrega del 26 de septiembre. Cualquier ampliación requiere un nuevo acuerdo.

La corrección que se puede proponer al proyecto original es declarar `.watchOS(.v9)` en su manifiesto específico de Swift 6.4. Documentar esta propuesta no implica que se haya enviado una issue o PR a ese repositorio.

Referencias: [manifiesto de la versión fijada](https://github.com/vapor/jwt-kit/blob/5.7.1/Package%40swift-6.4.swift#L10), [release 5.7.1](https://github.com/vapor/jwt-kit/releases/tag/5.7.1) e [informe de validación](validation/issue-1-server-bootstrap.md).

## EXC-002 · Extracción de metadatos App Intents sin adopción

**Estado: aceptada explícitamente por el responsable del proyecto el 21 de septiembre de 2026.** La propuesta se redactó el 19 de septiembre. La aceptación mantiene el alcance original, no modifica EXC-001 y no completa por sí sola la entrega del bloque 4.

- **Diagnóstico permitido:** `Metadata extraction skipped, no AppIntents.framework dependency found`, emitido por `appintentsmetadataprocessor` de Xcode 27.0 (27A266a).
- **Alcance:** exclusivamente ese mensaje en los targets `SmartShoppingList`, `SmartShoppingListTests` y el bundle de pruebas de `SmartShoppingListServer`, mientras no utilicen App Intents. No abarca otros diagnósticos, otras versiones de Xcode ni errores de extracción de una funcionalidad real.
- **Motivo:** estos targets no declaran App Intents ni dependen del framework. SwiftBuild prepara la extracción para targets compatibles que contienen Swift, sin exigir una adopción previa de App Intents. No hay metadatos de esa funcionalidad que generar en el MVP actual. El aviso también aparece en el log del bloque 3; no se atribuye su introducción al bloque 4.
- **Evidencia:** las compilaciones y pruebas nativas del bloque 4 completaron, sin warnings Swift propios identificados. Los logs completos y sus límites constan en el [informe de validación](validation/issue-4-shared-flow.md#compilación-y-diagnósticos). El resumen MCP omite este diagnóstico y no sustituye esos logs.
- **Tratamiento acordado:** conservar el aviso visible y warnings-as-errors en el código propio. No añadir una dependencia ficticia de AppIntents, flags de silencio ni cambios globales del entorno. No describir el resultado como una compilación global sin avisos.
- **Alternativas evaluadas:** `LM_FILTER_WARNINGS=YES` pasa `--quiet-warnings` al procesador y solo oculta avisos. `LM_SKIP_METADATA_EXTRACTION=YES` evita la tarea completa, pero la herramienta oficial de configuración de Xcode lo rechaza como ajuste desconocido; tampoco proporciona una configuración persistente equivalente para el target de pruebas generado por SwiftPM. No se ha aplicado ninguna de estas opciones.
- **Efecto de la aceptación:** únicamente este aviso deja de bloquear el criterio de compilación del bloque 4. El resultado se expresa como validado con las excepciones aceptadas, no como ausencia global de avisos. HTTPS, acceso Apple real y recorrido compartido con dos clientes ya se comprobaron; las invitaciones se ensayaron mediante AirDrop. Permanecen las validaciones específicas alojadas y de #7 descritas en el [informe](validation/issue-4-shared-flow.md#pendiente-para-acreditar-el-bloque-completo). La aceptación no autoriza merge, cierre de issues ni eliminación de rama.
- **Revisión y retirada:** revisar al cambiar Xcode, antes de incorporar App Intents a cualquiera de esos targets y durante la revisión de entrega del 26 de septiembre. Retirar cuando la herramienta deje de emitirlo o exista una configuración oficial aplicable que elimine la tarea innecesaria; comprobar los logs completos tras compilar y ejecutar las suites afectadas. Cualquier ampliación requiere nuevo acuerdo.

Referencias primarias: [creación de tareas en SwiftBuild](https://github.com/swiftlang/swift-build/blob/main/Sources/SWBApplePlatform/AppIntentsMetadataCompiler.swift#L70-L74) y [condición de extracción](https://github.com/swiftlang/swift-build/blob/12ac09ae1e3e344ce4dc085ee79306b2ccecb3e9/Sources/SWBApplePlatform/AppIntentsMetadataTaskProducer.swift#L50-L57). La especificación `AppIntentsMetadata.xcspec` instalada con Xcode confirma el argumento `--quiet-warnings` de `LM_FILTER_WARNINGS`.
