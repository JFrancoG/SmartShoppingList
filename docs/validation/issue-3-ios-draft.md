# Bloque 3 · borrador iOS

19 de septiembre de 2026. Implementación desarrollada en `codex/issue-3-ios-draft-input`, partiendo de `14e7dcb`. El usuario autorizó commit, push, PR, merge y cierre de la [issue #3](https://github.com/JFrancoG/SmartShoppingList/issues/3). Sus comprobaciones reales pendientes se conservan en la [issue #7](https://github.com/JFrancoG/SmartShoppingList/issues/7), dentro del mismo hito. La referencia de entrega se registra en #3; este informe no acredita los criterios físicos, de voz/IA real o VoiceOver.

## Implementación

- Entrada manual de nombre, cantidad opcional y tienda, edición, eliminación y revisión local de 1–50 filas.
- Borrador recuperable como snapshot JSON escrito atómicamente por un actor. Una lectura corrupta conserva el archivo y comunica que los cambios de esa sesión no se guardarán; los errores de escritura no borran el estado en memoria.
- Propuestas Foundation Models mediante salida guiada y sesión nueva, sin inventar campos en código ni escribir en el backend. Una corrección o cancelación invalida cualquier respuesta tardía. Una propuesta que excedería 50 filas se rechaza completa.
- Captura española con `SpeechAnalyzer`, `SpeechTranscriber` y `CaptureInputSequenceProvider` del SDK 27. Permiso de micrófono al dictar, comprobación de disponibilidad/assets, cancelación, interrupciones y conservación del texto reconocido.
- Mensajes de alternativa manual, catálogo español, controles semánticos, previews aisladas y botones verticales en tamaños accesibles.
- Swift 6, aislamiento explícito, warnings tratados como errores en los tres targets y sin paquetes externos añadidos.

Las decisiones y límites se explican en [arquitectura del borrador](../architecture/ios-draft.md). La revisión local muestra expresamente que todavía no se ha enviado al grupo. El envío autenticado corresponde a #4.

## Pruebas deterministas e integración de disco

Entorno: Xcode 27.0 / Swift 6.4, macOS 27.0, iPhone 18 Pro Simulator iOS 27.0 (24A434), arm64. Planes compartidos en `ios/SmartShoppingList/TestPlans` y esquema `SmartShoppingList`.

| Plan | Casos ejecutados | Resultado |
|---|---:|---|
| Fast | 34 invocaciones de 24 tests | Correcto |
| Integration | 5 invocaciones de 3 tests | Correcto |

`Fast` selecciona el tag `fast`: límites Unicode y de lote, correcciones humanas, propuestas añadidas, cancelaciones, respuestas tardías, falta de IA/permisos y finalización de una captura antigua frente a una nueva. `Integration` selecciona `integration`: archivo real temporal, recuperación, reemplazo, compatibilidad del snapshot y rechazo de archivos corruptos/excesivos sin modificar sus bytes. No necesitan modelo, micrófono ni backend. El ejemplo vacío y los UI tests de la plantilla no se cuentan como cobertura.

Evidencia local, obtenida del `.xcresult` cerrado con `xcresulttool`:

- Fast: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/Test-SmartShoppingList-2026.09.19_13-53-09-+0200.xcresult`.
- Integration: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/Test-SmartShoppingList-2026.09.19_13-53-27-+0200.xcresult`.

No se usan los recuentos acumulados del resumen MCP: en esta sesión algunos incluían resultados de ejecuciones anteriores. Los bundles anteriores contienen respectivamente 34 y 5 invocaciones aprobadas, sin fallos ni runtime warnings.

TDD observado: reglas con stub, 22 fallos de 24 invocaciones; ViewModel con stub, 6/6 fallos; persistencia con stub, 5/5 fallos. Después se implementó y se comprobó GREEN. La regresión adicional de finalización de dictado surgió de revisión independiente y se ejecutó en GREEN tras corregir la generación de captura.

La regresión Unicode detectó que `precomposedStringWithCanonicalMapping` truncaba secuencias largas de U+0344 en este entorno. `String.applyingTransform` con `Any-NFC`, más comprobación de equivalencia, conserva los escalares. Las entradas de 33 y 80 caracteres originales conservan 66 y 160 escalares; 81 se rechaza por superar el límite normalizado. No se cambió el oráculo para aceptar pérdida de texto.

## Prueba real de IA y disponibilidad de voz

Se ejecutó el [probe reproducible](probes/Issue3ModelProbe.swift) con el adaptador real en el simulador anterior, sin dobles. Su copia temporal en el target se retiró tras la prueba; no forma parte de los planes automáticos. Para repetirlo, copiarlo al target de pruebas y seleccionarlo expresamente en un plan temporal.

Resultado a las 13:48:58 CEST:

- Foundation Models anunció `available`.
- La inferencia real con «Necesito 2 litros de leche, una barra de pan y café en Mercadona» falló en 0,813 segundos, sin productos.
- El log del sistema informó `com.apple.UnifiedAssetFramework`, código 5000, falta de assets del catálogo `com.apple.modelcatalog` para el consistency token. La disponibilidad declarada por la API no bastó para inferir.
- `SpeechTranscriber.isAvailable` devolvió `false`; no se encontró locale equivalente a `es-ES`.

Evidencia: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunSomeTests/Test-SmartShoppingList-2026.09.19_13-48-56-+0200.xcresult`, con salida de consola en el mismo directorio (`test-console-log-2026-09-19T13-48-56+02-00.txt`). Es una prueba de integración fallida por assets del entorno; **no** acredita extracción, calidad, casos ambiguos ni transcripción. La app conserva texto y borrador ante ese error y permite continuar manualmente.

Siguiente comprobación: revisar el estado de los modelos del Mac y la compatibilidad del runtime, repetir el probe hasta obtener salida real y después verificar ausencia/ambigüedad de tienda y cantidades. No se cambian ajustes de Apple Intelligence, versiones ni se descargan modelos por iniciativa de este bloque.

## Interfaz y accesibilidad

Previews renderizadas mediante Xcode en iPhone 18 Pro, con fixtures locales: pantalla principal en Large, XXX Large y AX 5; fila y editor en AX 5. La inspección detectó recorte de cantidad/acciones en la fila AX 5 y se corrigió con texto multilínea y acciones verticales. El nuevo render muestra completos «Cantidad no indicada», «Editar» y «Quitar».

Las snapshots verifican el contenido visible, no navegación, scroll efectivo, foco, rotor o anuncios. VoiceOver y el recorrido físico permanecen pendientes.

La interacción automatizada de Xcode devolvió una sesión inexistente, aunque otra sesión veía el dispositivo ocupado. Se intentó cerrar las sesiones; la herramienta respondió que ya no existían. La alternativa de interfaz macOS tampoco pudo inspeccionar Device Hub por timeout. No se atribuye a estas herramientas una prueba manual que no ocurrió. El arranque inicial de RunCodeSnippet falló en el runtime de previews; los renders posteriores desde la ventana GUI sí funcionaron.

## Compilación final y destino físico

La compilación final para pruebas en simulador completó el 19 de septiembre a las 14:08 CEST, después de la auditoría final de estilo de los 19 archivos Swift del bloque. La afirmación inicial «sin warnings» se corrige: la revisión posterior de los logs completos identificó el aviso de extracción de metadatos App Intents, omitido por el resumen MCP. Ese diagnóstico específico queda cubierto por [EXC-002](../dependency-exceptions.md#exc-002--extracción-de-metadatos-app-intents-sin-adopción), aceptada el 21 de septiembre; no se declara ausencia global de avisos. Log: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260919-140809.txt`.

Se seleccionó «iPhone14 de Jesús» (iOS 27.0) y se solicitó RunProject. El build `Debug-iphoneos`, incluida la firma automática, terminó correctamente. La operación quedó esperando el arranque; al detener la ejecución de prueba, la herramienta devolvió `The app failed to launch after building successfully`. No se confirmó instalación ni interacción física. Log: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20260919-135655.txt`. Se restauró el destino iPhone 18 Pro y quedó seleccionado el plan Fast.

## Validación real pendiente en #7

- Recorrido manual en el iPhone físico, cierre/reapertura, corrección y revisión.
- Captura y transcripción españolas reales, permiso denegado e interrupción de micrófono en el dispositivo disponible.
- Inferencia real y revisión de productos/tiendas/cantidades ambiguas con assets operativos.
- VoiceOver y texto grande con interacción real.

La separación de implementación y validación real permite el cierre de #3 solicitado por el usuario, conservando estos criterios abiertos en #7. No supone dar por terminada la fase 1, la integración de #4 ni el MVP.
