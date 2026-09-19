# Excepciones de dependencias

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
