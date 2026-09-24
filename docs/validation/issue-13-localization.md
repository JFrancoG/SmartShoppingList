# Localización de la app: inglés y español

Fecha: 24 de septiembre de 2026. Seguimiento operativo: [#13](https://github.com/JFrancoG/SmartShoppingList/issues/13). Base publicada: `335300b`, sobre el recorrido de compra de #11. El [plan](../implementation-plan.md) conserva los criterios de entrega y [#7](https://github.com/JFrancoG/SmartShoppingList/issues/7) los ensayos reales de voz/IA y accesibilidad.

## Estado del punto de control

Este punto de control reúne la localización y los ajustes de extracción en la rama de #13; no equivale al cierre de la issue ni de la fase 3. Última validación de código: Fast 71 pruebas únicas/127 ejecuciones, build sin warnings propios y solo EXC-002. Después se añaden exclusivamente resultados y consolidación documental; no se repiten suites por esas ediciones.

Ensayos comunicados por el usuario: recorrido manual inglés compartido en iPhone 11, dictado inglés y cancelación en iPhone 14, interpretación inglesa/española en Mac con conservación del borrador y VoiceOver inglés en el iPhone 14. Los detalles siguientes distinguen cada entorno y los fallos corregidos. El iPhone 11 no dispone del motor Speech en el entorno comprobado; la entrada manual funciona.

Los formatos de creación/caducidad de invitaciones UK/US y las dos secuencias ES/EN en la app del Mac están confirmados en las secciones posteriores. La revisión de entrega identificó dos precisiones documentales, corregidas aquí: actualizar este resumen y limitar la evidencia del placeholder. El usuario autoriza el 24 de septiembre publicar las correcciones e integrar #9 → #12 → #14, verificando cada base antes del merge y cerrando las issues y ramas correspondientes después de confirmar su entrega. El resultado definitivo se registra en GitHub; esta autorización no acredita por sí sola la ejecución. Se conserva el seguimiento de los cierres de Foundation Models observados en previews con el tratamiento acordado. Los hallazgos de visibilidad de avisos, foco y anuncio de errores conservan su seguimiento de fase 3; no se consideran resueltos por traducir la interfaz ni por el ensayo acotado de VoiceOver.

## Cambio y límites

- Inglés es el idioma fuente y de respaldo del proyecto. `Localizable.xcstrings` contiene 175 mensajes con traducción española completa, incluidos controles, estados, errores y accesibilidad. Las interpolaciones conservan valores de usuario y formatos nativos de fecha.
- `InfoPlist.xcstrings` traduce la explicación del permiso de micrófono a ES/EN. El nombre comercial SmartShoppingList no se traduce.
- El idioma efectivo procede de `Bundle.main.preferredLocalizations`. La composición inyecta el mismo locale a Speech y Foundation Models; ya no hay español fijo en los adaptadores. Los locales canónicos son `en-US` y `es-ES`; no se promete ortografía británica en el dictado.
- Las instrucciones de extracción exigen conservar el idioma y las palabras originales de producto, cantidad y tienda. Se mantienen las reglas contra nombres inventados, las correcciones humanas y el acceso manual cuando voz/IA no estén disponibles.
- El ejemplo de entrada se abrevia a «Por ejemplo: pan en Aldi» / «For example: bread at Aldi». Los previews ya no fuerzan español y pueden comprobarse con el selector de localización de Xcode.
- No cambian el contrato compartido, el backend ni los datos persistidos. La página web de invitación y los hallazgos generales de diseño/accesibilidad conservan su seguimiento separado.

## Comprobaciones locales

Entorno: Xcode 27.2 beta `27B5019j`, SDK iOS 27.2, simulador iPhone 18 Pro con iOS 27.2 (`24B5084k`), Swift 6. Compilación y ejecución a través del MCP oficial de esa instalación, en el proyecto del worktree independiente.

- Compilación inicial con targets de pruebas satisfactoria. El log completo solo muestra el diagnóstico externo de extracción de App Intents aceptado en [EXC-002](../dependency-exceptions.md); no se atribuye a una función Siri implementada.
- Ejecución inicial y repetición final `Fast` tras las correcciones: `.xcresult` cerrado con **69 pruebas únicas y 119 ejecuciones parametrizadas correctas**, cero fallos y cero warnings de runtime. Las pruebas nuevas verifican orden/fallback de idiomas y recuperación manual localizada en ES, en-GB y en-US conservando nombres y cantidades mixtos. Las aserciones españolas existentes ahora seleccionan explícitamente ese locale en vez de depender del idioma del runner. Resultado final: `Test-SmartShoppingList-2026.09.24_00-22-17-+0200.xcresult`; compilación previa de las 00:22:17 correcta, únicamente con EXC-002. Los seis «No result» de la lista MCP corresponden a tests fuera de este plan; el resumen nativo del resultado final registra 69/69 correctos.
- Catálogos inspeccionados después de la extracción de Xcode: 174/174 traducciones españolas, sin claves obsoletas ni desajustes de placeholders. Recursos de micrófono compilados en `en.lproj` y `es.lproj`, con sus textos correspondientes; 174 entradas compiladas en `es.lproj/Localizable.strings`. El texto fuente inglés se obtiene de las claves literales.
- Revisión independiente de estándares y de SwiftUI/localización. Se corrigió un aviso de compra con refresco fallido que el catálogo original no incluía; se añadieron comentarios específicos para traducción y se conservaron los datos de ejemplo sin traducirlos.

La revisión independiente de SwiftUI inspeccionó diez renders del MCP oficial, todos con `errors: []`, en iPhone 18 Pro/iOS 27.2:

| Vista, índice 0 | Idiomas | Dynamic Type |
|---|---|---|
| `AddItemsView` | EN y ES | Large, XXX Large y AX 5 |
| `SharedPurchaseSection` | EN y ES | Large |
| `SharedReviewView` | EN y ES | Large |

Los textos visibles —incluidos `LocalizedStringResource` e interpolaciones— cambian de idioma; los productos de ejemplo españoles se conservan en inglés. No se identificaron nuevos recortes o solapamientos en las áreas inspeccionadas. La captura AX 5 muestra el campo relleno: acredita el reflujo del texto introducido, no la visibilidad del placeholder. Su comprobación con el campo vacío permanece en la matriz visual de fase 3; no se ha demostrado un recorte actual del placeholder abreviado. Evidencia local de renders del 24 de septiembre, 00:18–00:21: `/tmp/ssl-preview-add-{en,es}-{large,xxx,ax5}.json`, `/tmp/ssl-preview-purchase-{en,es}-large.json` y `/tmp/ssl-preview-review-{en,es}-large.json`, con las rutas de imagen devueltas por Xcode.

Esta muestra no completa la matriz visual de fase 3: AX 5 acredita únicamente el viewport inicial, no el contenido inferior que requiere scroll. Las imágenes tampoco acreditan interacción con VoiceOver, controles alternativos, foco, permisos reales ni calidad de transcripción/inferencia. Los hallazgos previos de avisos/foco siguen abiertos en su seguimiento original.

Fuentes primarias verificadas para la selección del idioma: [Bundle.preferredLocalizations](https://developer.apple.com/documentation/foundation/bundle/preferredlocalizations), [SystemLanguageModel.supportsLocale](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/supportslocale(_:)) y [SpeechTranscriber.supportedLocale](https://developer.apple.com/documentation/speech/speechtranscriber/supportedlocale(equivalentto:)).

## Ensayo físico confirmado por el usuario

El 24 de septiembre, con el iPhone 11 configurado en inglés y la app ejecutada desde el worktree de #13, el usuario confirmó:

- La interfaz aparece en inglés; los nombres existentes de productos y tiendas conservan su texto original.
- El recorrido manual propuesto —añadir `Wholemeal bread`, cantidad `1 loaf`, tienda `Aldi`, revisar y confirmar su incorporación al grupo— funciona correctamente.
- Al actualizar en el otro iPhone, el producto aparece con los mismos datos. Esta comprobación acredita el recorrido manual compartido con entrada inglesa, sin traducción automática de los datos.

Son resultados comunicados por el usuario, no observación directa del agente. No se atribuyen a esta prueba dictado, Foundation Models, lectura de VoiceOver ni formatos regionales UK/USA. La versión/build exacta de iOS de este ensayo no se volvió a comunicar.

### Dictado en inglés: iPhone 11

Al pulsar Dictate, el usuario informó del aviso «Transcription is unavailable in the selected language…». La investigación del 24 de septiembre confirmó mediante el depurador de la app del worktree en el iPhone 11 físico (`remote-ios`, iOS 27.2 build `24B5089g`) que `Bundle.main.preferredLocalizations` es `["en"]` y `SpeechTranscriber.isAvailable` devuelve `false`. La captura se detiene antes de consultar `supportedLocale`, pedir permiso o descargar assets; no se atribuye a un fallo de selección del inglés ni a falta de permiso.

La comprobación previa con `RunCodeSnippet` se ejecutó en simulador pese al destino seleccionado y se descarta como evidencia del teléfono. La comprobación física posterior sí identifica el proceso remoto. Se reanudó el proceso después de leer esos valores.

El aviso agrupaba `.unavailable` y `.unsupportedLocale`. Se separan ambos casos en ES/EN: indisponibilidad del dispositivo e idioma no admitido tienen ahora mensajes distintos. El primero dice «Transcription is unavailable on this device…» / «La transcripción no está disponible en este dispositivo…». Esto corrige la explicación, no habilita el motor en el iPhone 11. El ensayo de transcripción inglesa queda pendiente en iPhone 14 o Mac compatible; la entrada manual del iPhone 11 sigue validada.

Verificación del ajuste: compilación con tests correcta (únicamente EXC-002); `Fast` cerrado de las 00:43:28 con **69 pruebas únicas, 121 ejecuciones correctas y cero fallos/warnings de runtime**. El caso de fallo de captura comprueba ahora permiso denegado, dispositivo no disponible e idioma no admitido: aviso específico y revisión manual conservando texto y productos corregidos. La selección focal de tests fue rechazada por MCP como deshabilitada en el plan basado en tags; se ejecutó el plan Fast completo. Revisión focal independiente de ES/EN sin hallazgos y catálogo 175/175 traducido. Tras las pruebas se restauró el destino iPhone 11 de Xcode; el nuevo mensaje requiere ejecutar la compilación actualizada en el dispositivo.

### Dictado e interpretación en inglés: iPhone 14 y Mac

El usuario confirmó el dictado inglés en iPhone 14, con confusión de `Aldi` por `all`. Confirmó también que Cancel dictation restaura exactamente el texto previo, eliminando únicamente lo transcrito durante esa captura. Esto acredita el flujo de voz/cancelación en ese dispositivo, no precisión perfecta con nombres comerciales.

En el Mac, después de configurar App Language en English mediante el esquema de Xcode, la interpretación de la lista generó los dos productos esperados con tienda `Ali`. El usuario aclaró que el texto de entrada ya decía `Ali`, por lo que no se atribuye ese cambio a Foundation Models. Al corregir el texto a `Aldi` y volver a interpretar, confirmó cuatro entradas: las dos anteriores con `Ali` y dos nuevas con `Aldi`, coherentes con la incorporación acumulativa al borrador.

La prueba negativa con «The weather is nice today and I am going for a walk.» mostró, según la captura del usuario de las 01:03:37, «The text could not be interpreted. Your draft is kept; you can retry or continue manually.». El aviso estaba fuera de la zona visible, al final del formulario. No se da por superada la prueba de detección de ausencia de productos: el mensaje es un fallo genérico, no `noProducts`; tampoco se deduce únicamente del aviso que las cuatro entradas se hayan conservado. Se solicitó confirmación de ese estado y se investiga la causa. La visibilidad reproduce el hallazgo de avisos fuera de pantalla pendiente en fase 3.

### Corrección de la propuesta totalmente vacía

La reproducción controlada con el MCP oficial y la misma frase inglesa se ejecutó en simulador (`iOSAppOnMac=false`, modelo disponible), no en el proceso del Mac del usuario. Antes del ajuste devolvió `.failed`. Al inspeccionar la salida del modelo con las mismas instrucciones y esquema, se observó una única fila con nombre `" "`, cantidad y tienda nulas. Esto acredita una causa reproducible del fallo genérico; no demuestra cuál fue la respuesta interna de la ejecución original del usuario.

El intérprete ahora normaliza la propuesta antes de validarla. Una propuesta sin contenido en ninguno de sus campos produce `.noProducts`; una fila sin nombre pero con cantidad/tienda, o una mezcla de filas válidas y vacías, sigue rechazando la propuesta completa con `.failed`. No se filtran filas para aceptar parcialmente una propuesta defectuosa. Se añaden casos parametrizados con espacios Unicode, campos significativos sin nombre y propuestas mixtas.

Validación del ajuste: compilación con targets de pruebas correcta, únicamente con EXC-002; resultado nativo cerrado `Test-SmartShoppingList-2026.09.24_01-10-07-+0200.xcresult`, **71 pruebas únicas y 127 ejecuciones correctas**, cero fallos y cero warnings de runtime. Los seis casos sin ejecutar que muestra MCP pertenecen a otros planes. La repetición controlada del intérprete con la misma frase después del ajuste devuelve `.noProducts`. La revisión independiente no encontró problemas funcionales; se aplicaron dos ajustes menores de disposición y `git diff --check` está limpio.

El usuario repitió la prueba en la app actualizada del Mac y confirmó el resultado mediante la captura del 24 de septiembre a las 01:15:45: «No products were found. You can rephrase the text or add them manually.». Después confirmó expresamente que se conservan las cuatro entradas anteriores, dos en Ali y dos en Aldi. Queda superada esta prueba negativa en inglés: aviso específico y borrador conservado. La posición inferior del aviso sigue siendo el hallazgo de visibilidad pendiente de fase 3; esta corrección no modifica su presentación.

### Repetición negativa en español

La captura del usuario del 24 de septiembre a las 01:18:32 confirma interfaz española y conservación de las cuatro entradas (milk y whole bread, dos en Ali y dos en Aldi), incluidos los nombres y cantidades originales en inglés. Sin embargo, el aviso mostrado es «No se ha podido interpretar el texto…», no el específico de ausencia de productos. Se acredita conservación del borrador y localización del fallo; queda pendiente el resultado específico `.noProducts` de esta prueba española.

La investigación aislada mediante `RunCodeSnippet`, en simulador y con locale `es-ES`, reproduce `.failed` para «Hoy hace buen tiempo y voy a pasear.». Una inspección posterior con las mismas instrucciones, espacios de la cadena, esquema y generación greedy devuelve una fila `name: "nada"`, cantidad y tienda nulas. Ese nombre no tiene una mención literal en la entrada; las reglas rechazan correctamente toda la propuesta antes de modificar el borrador. Esta reproducción no equivale a capturar la respuesta interna del proceso original del Mac.

Un primer sondeo de salida cruda conservaba espacios adicionales en las instrucciones y devolvió un array vacío, por lo que no se considera reproducción equivalente. Un intento posterior falló por cierre del servicio de previews y se repitió una vez. No se modifican las reglas para convertir nombres como «nada» en ausencia de productos ni para ocultar cualquier fallo como `.noProducts`. Sigue pendiente mejorar y validar la generación de ausencia de productos en español; los tests deterministas anteriores no acreditan ese comportamiento del modelo real.

### Salida explícita para ausencia de compra

Tras la petición del usuario de resolverlo ahora, la salida de Foundation Models pasa a un enum generable privado con dos casos: `noProducts` o `shopping(GeneratedShoppingDraft)`. El primero comunica ausencia sin obligar al modelo a completar una fila; el segundo conserva límite de 50 productos, normalización y rechazo completo de nombres sin respaldo literal. El presupuesto de tokens usa el esquema completo nuevo. Las instrucciones distinguen una compra/lista de productos de una entrada ajena a compras, sin ejemplos de la frase del ensayo ni reconocimiento especial de «nada»/«none». No se reinterpretan fallos del framework como ausencia de compra. La documentación oficial de [generación guiada](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation) confirma el soporte de enums con valores asociados. El esquema garantiza la forma, no la corrección semántica de la clasificación.

Comprobaciones del 24 de septiembre con Xcode 27.2 beta:

- Compilación de la app y tests satisfactoria para My Mac (Designed for iPad) y simulador iPhone 18 Pro 27.2. Logs completos de las 01:23:11 y 01:25:01: únicamente el diagnóstico App Intents aceptado por EXC-002.
- `Fast`: resultado nativo cerrado `Test-SmartShoppingList-2026.09.24_01-25-14-+0200.xcresult`, **71 pruebas únicas, 127 ejecuciones correctas**, cero fallos y cero warnings de runtime. Se mantienen las pruebas de rechazo íntegro y conservación ante `.noProducts`/`.failed`; no se añaden tests que solo construyan el enum ni tests automáticos dependientes del modelo real.
- Modelo real en el simulador de previews, mediante el intérprete de producción: las frases sobre clima/paseo ES/EN devuelven `.noProducts`; «Dos litros de leche y pan integral en Aldi» y su equivalente inglés producen dos productos, cantidad de leche y tienda correctos. Resultado local `/tmp/ssl-enum-model-probe.json`.
- Comprobaciones adicionales aisladas: «Mañana tengo una reunión a las diez.» e «I have a meeting tomorrow morning.» devuelven `.noProducts`. «Leche entera y leche sin lactosa en Aldi» y «Whole milk and lactose-free milk at Aldi» conservan las dos variantes y Aldi. Resultados locales `/tmp/ssl-enum-additional-single.json` y `/tmp/ssl-enum-additional-isolated.json`.
- Revisión independiente focal de estándares y estilo sin hallazgos; `git diff --check` limpio.

Límite de ejecución: dos intentos de la matriz adicional en lote cerraron el proceso de previews. Los informes `SmartShoppingList-2026-09-24-012423.ips` y `SmartShoppingList-2026-09-24-012450.ips` sitúan un `EXC_BREAKPOINT`/`_assertionFailure` dentro de FoundationModels en ese proceso. Las cuatro frases adicionales funcionan al ejecutarlas por separado. No se da el cierre por resuelto ni se atribuye a la app del usuario sin reproducirlo allí; queda registrado para seguimiento de la beta. Estas comprobaciones no acreditan el funcionamiento en un iPhone físico ni sustituyen la repetición manual en el Mac. El destino de Xcode se restaura a My Mac (Designed for iPad).

El usuario confirmó la repetición en la app actualizada del Mac con la captura del 24 de septiembre a las 01:29:18: «No se han encontrado productos. Puedes reformular el texto o añadirlos a mano.». La imagen muestra las cuatro entradas anteriores intactas, dos en Ali y dos en Aldi, conservando sus nombres y cantidades inglesas. Queda superada la prueba negativa española con el nuevo esquema.

En la repetición válida posterior, el usuario informó de una omisión: «Dos litros de leche y pan integral en Aldi.» añadió únicamente leche (cinco entradas totales) y retiró el aviso anterior. La desaparición del aviso es correcta, pero la extracción queda incompleta y el recorrido consecutivo no se da por superado. Una reproducción controlada con las instrucciones y esquema actuales, incluyendo el punto final, confirma una única fila `leche`, cantidad `dos litros`, tienda `Aldi` (`/tmp/ssl-missing-bread-baseline.json`). El ViewModel incorpora todas las sugerencias recibidas, sin filtrar ni deduplicar; la omisión se reproduce en la salida del modelo. Los ensayos positivos anteriores no incluían el punto final y no bastan para acreditar esa variante.

La prueba manual anterior no resuelve por sí sola los cierres observados en los lotes de previews. La visibilidad inferior del aviso sigue pendiente en fase 3.

### Corrección de la omisión del producto sin cantidad

Se refuerzan las instrucciones y la descripción de la colección para extraer todos los productos solicitados, incluidos los que no llevan cantidad. Las conjunciones solo separan productos cuando enumeran menciones distintas: se conservan los nombres compuestos. La cantidad pertenece únicamente al producto descrito. Se precisa además que una tienda que inequívocamente corresponde a toda la lista debe copiarse en todas sus filas. Se mantienen las reglas de ambigüedad, límites, cancelación y validación literal; no se añade un parser de conjunciones ni se quita el punto final.

La primera corrección recuperó el pan en la frase exacta, pero la variante española sin punto dejó su tienda vacía. Ese resultado no se dio por correcto: motivó precisar la instrucción de tienda común antes de repetir la matriz. La matriz final de doce textos, ejecutada mediante el intérprete de producción en el simulador de previews, obtiene:

| Casos | Resultado observado |
|---|---|
| Leche y pan con cantidad solo para la leche, ES/EN, con/sin punto (4) | Dos productos; cantidad en leche; Aldi en ambas filas |
| Frase de clima/paseo ES/EN (2) | `.noProducts` |
| Leche entera/sin lactosa ES/EN (2) | Dos variantes separadas, ambas en Aldi |
| Bocadillo de jamón y queso / mac and cheese (2) | Un producto compuesto, sin dividir por la conjunción, en Aldi |
| Leche en Aldi y pan en Lidl, ES/EN (2) | Dos productos, cada uno en su tienda |

Diez casos completaron el primer intento. El negativo español y las variantes inglesas sufrieron cierre de previews y completaron correctamente un único reintento aislado. Esto acredita los resultados funcionales observados, no resuelve la estabilidad del framework ni garantiza exhaustividad para cualquier texto. Evidencia local: `/tmp/ssl-complete-extraction-final.json` y `/tmp/ssl-complete-extraction-retry.json`. No se añaden tests que comparen el prompt consigo mismo: la calidad del modelo se comprueba en esos ensayos reales, separada de la regresión determinista.

Validación final: build con tests de las 01:38:36 correcto, únicamente EXC-002 en el log completo; `Fast` cerrado `Test-SmartShoppingList-2026.09.24_01-39-02-+0200.xcresult`, **71 pruebas únicas y 127 ejecuciones correctas**, cero fallos/warnings de runtime. Revisión independiente focal y auditoría de estilo sin hallazgos; `git diff --check` limpio. Se restaura My Mac (Designed for iPad) como destino de Xcode.

El usuario ejecutó la app actualizada en el Mac y confirmó «correcto, ya tengo 7» al repetir «Dos litros de leche y pan integral en Aldi.». Queda superada esta repetición manual: se incorporan los dos productos a las cinco entradas anteriores. Es evidencia comunicada por el usuario; no acredita estabilidad general del framework ni resuelve los cierres de previews. Los sondeos aislados no modificaron ni eliminaron su borrador.

### VoiceOver en inglés: iPhone 14

El usuario confirmó como correcto el recorrido solicitado con VoiceOver y la app en inglés en el iPhone 14: Añadir, controles de dictado/interpretación y revisión del borrador. Las etiquetas e indicaciones se leen en inglés y los nombres de productos y tiendas conservan su texto original. Es evidencia comunicada por el usuario, sin envío adicional al grupo. Este ensayo acredita la localización de los controles recorridos; no cierra los hallazgos de foco, anuncio automático de errores, avisos fuera de pantalla ni la matriz completa de accesibilidad de fase 3. No acredita formatos regionales UK/USA.

### Formatos UK/US en iPhone 11

El usuario aportó `IMG_0014.PNG` (región UK) e `IMG_0015.PNG` (región US), con la interfaz inglesa y las mismas invitaciones. La creación `22 Sep 2026 at 17:28:14` pasa a `Sep 22, 2026 at 5:28:14 PM`; la caducidad pasa de `23 Sep 2026 at 17:28` a `Sep 23, 2026 at 5:28 PM`. Las demás filas visibles conservan fechas, horas equivalentes y estados. Queda superada esta comprobación visual regional de creación/caducidad; no acredita cambios de zona horaria ni formatos no presentes en esta pantalla.

### Revisión de cierres de Foundation Models

Revisión del 24 de septiembre sobre el código publicado `5e3a2a0`, sin modificar el adaptador ni el modelo de vista:

- Se inspeccionaron seis informes locales `SmartShoppingList-2026-09-24-{011958,012423,012450,013505.000,013656,013719}.ips`. Todos identifican el bundle bajo `Xcode/UserData/Previews/Simulator Devices`, padre `launchd_sim`, `EXC_BREAKPOINT`/`SIGTRAP` y la misma secuencia de offsets: `_assertionFailure` en Swift seguido de once frames de FoundationModels. El primer frame del framework tiene offset `2397828`, UUID `78414d55-45d5-330e-81a2-25ac1ee0627e`. Los frames internos no están simbolicados; no hay mensaje de aserción en los informes. El sistema anfitrión registrado es macOS 27.2, build `26B5091g`; esto no identifica por sí solo el runtime del simulador.
- El cierre de las 01:19 precede al enum de clasificación. Por tanto, no se atribuye exclusivamente al nuevo enum. El script de la matriz final ejecuta cada sondeo de forma secuencial con `subprocess.run`; tampoco demuestra una causa por peticiones simultáneas. Se observaron cierres con distintas entradas, no solo negativas.
- El adaptador crea una sesión por interpretación y espera su respuesta; no reutiliza una sesión para varias peticiones simultáneas. El ViewModel impide iniciar otra interpretación mientras permanece ocupado y descarta resultados cancelados/obsoletos. No hay `fatalError`, `precondition`, aserciones ni `try!` propios en esta funcionalidad. Esto no descarta un defecto de integración que active una aserción interna. Un `catch` de errores Swift no recupera un proceso terminado por `SIGTRAP`.
- Sondeo nuevo y aislado mediante Xcode 27.2 beta, MCP GUI: modelo disponible, esquema de producción de 498 tokens, instrucciones mínimas de 51, entrada negativa de 11 y contexto de 8192. Completaron las tres llamadas de recuento. Las instrucciones mínimas son solo una sonda; esos números no representan el presupuesto completo del adaptador. Evidencia local: `/tmp/ssl-crash-review-token-probe.json`.
- Segundo sondeo, intérprete de producción, dos llamadas consecutivas en el mismo snippet: «Hoy hace buen tiempo y voy a pasear.» devuelve `.noProducts`; «Dos litros de leche y pan integral en Aldi.» devuelve leche y pan integral, Aldi en ambas filas y cantidad solo en leche. Evidencia local: `/tmp/ssl-crash-review-generation-probe.json`. Ambos sondeos indican `iOSAppOnMac=false`: siguen siendo previews en simulador, aunque el destino activo de Xcode permanezca en My Mac (Designed for iPad). No escriben en el borrador ni envían datos al grupo.
- Las notas consultadas de [macOS 27.2](https://developer.apple.com/documentation/macos-release-notes/macos-27_2-release-notes) y [Xcode 27.2](https://developer.apple.com/documentation/xcode-release-notes/xcode-27_2-release-notes) no identifican esta firma concreta. No se declara un fallo conocido confirmado por Apple ni una corrección disponible.

Conclusión: cierre real e intermitente localizado dentro de FoundationModels en el proceso de previews, con causa desencadenante todavía sin determinar. Los sondeos correctos no lo resuelven ni prueban que solo pueda ocurrir en previews. No hay una corrección de código propio justificada por estas trazas; no se cambian el esquema, el presupuesto ni las reglas para ocultarlo. EXC-002 se limita a metadatos App Intents y no cubre este cierre.

El usuario completó después las dos secuencias en la app ejecutada con My Mac (Designed for iPad), fuera de previews y sin enviar al grupo. En español confirmó el aviso específico de ausencia de productos y después la incorporación correcta de leche y pan. En inglés confirmó «No products…» y después milk y wholemeal bread. Comunica cuatro entradas finales, conservando ambas lenguas: cada interpretación añade al borrador, sin traducir ni deduplicar equivalencias entre idiomas. No comunicó cierres durante estas dos secuencias. Es evidencia manual acotada, no una prueba de estabilidad prolongada ni una reproducción instrumentada del fallo.

Tratamiento acordado el 24 de septiembre: conservar la incidencia como cierre observado en el entorno de previews, de causa no determinada, separado de las secuencias satisfactorias en la app del Mac. El usuario señaló la sensibilidad de previews a ediciones que temporalmente no compilan; no se ha demostrado que esa situación causara estos seis cierres. Se acuerda no modificar código ni bloquear la apertura de la PR únicamente por esa evidencia, manteniéndola visible para la revisión. No se amplía EXC-002 ni se declara solucionado el cierre o garantizada la estabilidad de la app. Si se reproduce fuera de previews, capturar consola y traza con el depurador antes de concluir sobre su alcance. No se han actualizado herramientas ni enviado informes a Apple.

El usuario restauró el idioma del esquema a la selección del sistema después de las pruebas. Se verificó que el esquema compartido no tiene diferencias respecto al commit publicado: no se entrega un override de inglés. La consolidación posterior a `5e3a2a0` solo cambia documentación; se reutilizan el build y las 71 pruebas únicas/127 ejecuciones del checkpoint anterior, sin atribuirles una repetición. La autorización actual alcanza commit, push y apertura de PR sobre la rama de compra, con revisión y merge posteriores en el orden #9 → #12 → localización.

## Dictado y conflicto con Device Hub: seguimiento de #7

El 24 de septiembre, durante la repetición de permiso denegado y posterior autorización en el iPhone 14 con iOS 27.2 e interfaz inglesa, la app mostraba `Listening` sin incorporar texto. El permiso estaba concedido y la entrada figuraba como micrófono integrado, sin mute. Con Device Hub mostrando el dispositivo físico, la instrumentación temporal recibió bloques de audio pero ningún resultado de Speech en varios intentos; el medidor permaneció en −120 dB. Configurar explícitamente la sesión como `.record`/`.measurement` no resolvió el fallo: 320 bloques y cero resultados. Esa variante se retiró antes de la comprobación final.

La [documentación de Apple sobre los conflictos de cámara y micrófono en Device Hub](https://developer.apple.com/documentation/xcode/interacting-with-your-app-in-device-hub#Handle-camera-and-microphone-access-conflicts-on-physical-devices) indica que la interacción con un dispositivo físico puede impedir el acceso de otras apps a esos sensores y producir audio silencioso. Tras salir de Device Hub, el usuario confirmó que la transcripción vuelve a aparecer, con la configuración de captura original. Los registros del mismo proceso confirman dos capturas con nueve resultados cada una, incluidos resultados finales y actualizaciones del texto en el ViewModel; el medidor deja de permanecer en −120 dB. Entorno: Xcode 27.2 beta, iPhone 14 físico, locale solicitado `en-US`, equivalente `en_US`; proceso 4334, binario `B60806E6-6FED-3E3B-8370-60086EB4AF31`, ensayos de las 13:18 CEST.

Se considera resuelto este bloqueo de la prueba por el entorno, sin corrección funcional de la app. El usuario también comunicó audios silenciosos en WhatsApp durante el uso de Device Hub; es una observación compatible con la limitación, no un ensayo instrumentado de esa app. Se retira la instrumentación temporal, que solo registraba estados, niveles, contadores y longitudes, sin guardar voz ni contenido transcrito. No se repiten suites por retirar esos registros y consolidar documentación; esta evidencia no cierra los hallazgos de avisos fuera de pantalla ni la matriz completa de #7.

**Condición para futuras pruebas físicas de micrófono o cámara:** terminar la interacción de Device Hub —para este ensayo, salir de Device Hub— y manejar el iPhone directamente. Xcode puede permanecer abierto para compilar y recoger registros. No confundir esta limitación de interacción remota con un permiso denegado, un fallo del idioma o una regresión de Speech. La configuración de audio de los simuladores se comprueba por separado.

### Bloqueo de pantalla y llamada entrante: iPhone 14

El 24 de septiembre, siguiendo el ensayo directamente en el iPhone 14 y con Device Hub cerrado, el usuario confirmó que bloquear la pantalla durante un dictado con texto visible detiene la captura, conserva el texto y los productos, y permite volver a dictar tras desbloquear. Es una variante de interrupción del ciclo de vida; no se exige repetirla por cada idioma. La salida a Inicio ya había sido validada el 22 de septiembre.

Después, el usuario confirmó el ensayo de llamada entrante desde el otro teléfono mientras dictaba: aceptar la llamada, colgar y volver a la app conserva el texto y los productos; la app no queda en `Listening` y un nuevo dictado vuelve a transcribir. Queda acreditada la interrupción por llamada y su recuperación en ese dispositivo. Son resultados manuales comunicados por el usuario, sin nueva captura de logs ni identificación adicional del binario; no acreditan cambio de entrada o desconexión de un micrófono externo. No se modificó código para estos ensayos y permanecen abiertos los hallazgos de accesibilidad.

## Matriz de ensayo y comprobaciones restantes

Usar la app compilada desde esta rama. Cambiar su idioma en la configuración de idioma por app de iOS y volver a abrirla; para simulador también se puede elegir Application Language en el esquema de ejecución de Xcode. No hace falta cambiar la región. El ajuste por app puede requerir tener ambos idiomas añadidos en los ajustes generales del sistema.

1. En español, comprobar Añadir/Comprar, editor, revisión, errores y confirmación con un borrador existente; nombres y cantidades deben conservarse al cambiar de idioma.
2. El recorrido manual inglés en iPhone 11, las etiquetas de VoiceOver del recorrido indicado en iPhone 14 y las fechas de invitación UK/US están confirmados arriba. Los datos introducidos se conservan en su idioma original; la prueba regional no acredita estabilidad de Foundation Models.
3. Dictar en el entorno que ya admite Speech: «Dos litros de leche y pan integral en Aldi» y «Two litres of milk and wholemeal bread at Aldi». En un iPhone físico, salir antes de Device Hub y usar directamente el dispositivo. Terminar conserva el texto; cancelar restaura exactamente el anterior. Revisar el permiso en el idioma de la app si se solicita por primera vez.
4. En el Mac/simulador con Foundation Models disponible, interpretar esas frases por separado. Verificar dos productos, tienda y cantidad, revisar y corregir antes de enviar. El iPhone sin Apple Intelligence debe seguir ofreciendo entrada manual.
5. Probar una frase sin compra en ambos idiomas: «Hoy hace buen tiempo y voy a pasear» / «The weather is nice today and I am going for a walk». No debe incorporar productos inventados.

Registrar entorno, idioma, resultado y cualquier texto incorrecto en #13/#7. La disponibilidad del modelo, los idiomas instalados del sistema y el consentimiento del micrófono se comprueban por separado; una traducción o un test determinista no los acredita. No se cierra la issue ni se declara el MVP bilingüe validado hasta completar sus criterios y entregar los cambios.


## Avisos visibles y validación del editor — seguimiento de #7 (24 de septiembre)

Cambio local autorizado: los avisos de dictado/interpretación, editor, operaciones compartidas, almacenamiento y conflicto de selección pasan a alerta nativa. Un único presentador raíz evita duplicación entre pestañas; editor, revisión e invitaciones suspenden la raíz hasta terminar `onDismiss`. Cerrar un aviso no altera campos, selección ni datos de reintento. El almacenamiento y los conflictos mantienen su explicación/acción persistente. Los tres títulos nuevos disponen de traducción española.

- Regresión previa: dos pruebas nuevas fallaron contra el descarte vacío del error del editor; los demás casos seguían correctos.
- Resultado final en My Mac (Designed for iPad), Xcode 27.2 beta, plan Fast: **74 tests únicos, 130 ejecuciones, cero fallos y cero warnings de runtime**, resultado cerrado `Test-SmartShoppingList-2026.09.24_14-22-46-+0200.xcresult`. Los seis «not run» del resumen MCP pertenecen a casos fuera del plan Fast; el resultado nativo no declara casos omitidos dentro del plan.
- Se verifica que cerrar el error conserva los campos y permite repetir Aplicar; un cierre antiguo no borra un error distinto; cerrar el error de red conserva la operación original en memoria y credenciales para reintentar; la alerta raíz espera al cierre de cada hoja.
- Build con tests `BuildProject-Log-20260924-142232.txt` correcto, solo el warning App Intents documentado por EXC-002.
- Revisión independiente estática de presentación/accesibilidad sin hallazgos pendientes tras completar las traducciones. Las previews detectaron una incompatibilidad del thunk con la referencia a método; el callback explicita `@MainActor @Sendable` y vuelve a compilar.
- Preview iPhone 18 Pro/iOS 27.2 muestra la alerta española del editor centrada y legible. Los renders posteriores EN/XXX Large y ES/AX5 capturan parcialmente la transición de la alerta; no se usan como evidencia de legibilidad ni contraste completos. Se conserva una preview determinista del mensaje largo de almacenamiento a AX5 para inspección interactiva.

Secuencia física de falta de conexión y recuperación completada, según las confirmaciones registradas a continuación. La alerta durante el cierre de revisión queda confirmada en el ensayo siguiente; la sustitución de avisos mientras otra alerta permanece abierta no se acredita con esa secuencia. AX5 del error del editor confirmado en el ensayo posterior; no equivale a validar todos los mensajes largos de almacenamiento. La conservación de campos tiene regresión automatizada; la confirmación manual siguiente acredita aparición y lectura del error del editor. El retorno del foco a la fila editada y el recorte de placeholders permanecen fuera de este ajuste. Esta validación no cierra #7; la entrega autorizada de este bloque se limita a commit y push de la rama.

App compilada e instalada en iPhone14 de Jesús mediante RunProject a las 14:23:36, proceso 4636. Arranque correcto; no sustituye la prueba física de alertas/VoiceOver.

El usuario confirma en el iPhone 14 el ensayo del editor: «correcto, sale el aviso las dos veces y lo lee automáticamente». Queda superada la aparición y lectura automática con VoiceOver al pulsar Aplicar sin tienda, cerrar el aviso y volver a pulsar Aplicar. Evidencia manual comunicada por el usuario sobre la app recién instalada; no acredita el retorno del foco a la fila, AX5 ni el resto de presentadores.

El usuario confirma «Correcto» en el ensayo posterior de permiso de micrófono denegado, con VoiceOver activo: al pulsar Dictate aparece la alerta y se lee automáticamente sin buscarla mediante scroll; al cerrarla se conservan el texto y los productos. Resultado manual comunicado, separado del funcionamiento de la captura de audio y de la recuperación del permiso ya ensayados anteriormente.

En el ensayo AX5 posterior, la captura de las 15:49:05 muestra la implementación antigua del aviso dentro del formulario, con icono azul y teclado visible. Se verificó mediante Xcode MCP que el proyecto original ejecutaba el proceso 4942 en el iPhone 14, mientras la sesión 4636 del worktree estaba terminada. Se detuvo esa ejecución y se lanzó el worktree corregido a las 15:50:46 (proceso 4975, arranque correcto). Esta captura no valida ni invalida la alerta nueva, y no demuestra un defecto causado por el teclado. AX5 pendiente de repetir sobre el binario corregido; no se modifica código por este resultado.

Repetido el ensayo AX5 en la versión corregida, el usuario confirma «sí, ahora sí; al cerrar vuelve a donde estaba, en el producto». Queda superada la lectura y cierre de la alerta del editor al tamaño máximo solicitado y la vuelta al producto tras cerrar ese aviso. Este resultado no acredita el hallazgo distinto de restaurar el foco a una fila de la lista tras cerrar la hoja completa de edición, ni todas las alertas largas de almacenamiento.

El usuario confirma «sí, correcto» al preparar la revisión con conexión, elegir tiendas, desactivar la red y confirmar el envío con VoiceOver activo. La revisión se cierra y la alerta de envío no confirmado aparece y se lee automáticamente. Al cerrarla se conservan el borrador y el control Retry submission. Queda superado este ensayo manual de presentación tras el cierre de la hoja. El reintento con red y su confirmación se comprobarán a continuación; no se infieren de este resultado.

El usuario confirma «correcto» tras recuperar la conexión y pulsar Retry submission sobre el mismo envío. La confirmación aparece y se lee con VoiceOver; al cerrarla desaparece la operación pendiente y los productos aparecen una sola vez en el grupo. Queda completada la secuencia manual falta de conexión → alerta tras cierre de revisión → reintento → confirmación, sin nuevo envío desde el borrador. No se ha cambiado código ni repetido la suite para registrar estos resultados. Permanecen separados el retorno de foco al cerrar la hoja completa del editor, placeholders, estado vacío de compra, mensajes largos de almacenamiento y sustitución de mensajes mientras una alerta sigue abierta. El usuario autoriza consolidar este bloque mediante commit y push; #7 permanece abierta para sus criterios restantes.


## Retorno del foco tras editar un producto — seguimiento de #7

El usuario repite el recorrido con VoiceOver sobre un producto existente del borrador y confirma «Vuelve a Add» al pulsar Cancel. Este resultado reproduce el hallazgo independiente de la alerta: la hoja completa se cierra y la lista pierde su contexto accesible.

Corrección local sobre `11ebbe6`: AddItemsView conserva el UUID del producto que abrió Edit y limpia el foco mientras presenta la hoja. Tras `onDismiss`, comprueba que el producto siga existiendo, desplaza lo mínimo necesario hasta el propio botón Edit y le devuelve el foco. El identificador del control es distinto de la identidad de ForEach, para evitar apuntar al contenedor de una fila que puede superar la altura disponible con AX5. Abrir un alta nueva limpia el origen; esta corrección no cambia ese recorrido. Cancel, Apply y cierre interactivo comparten el callback; un error de validación no cierra la hoja ni dispara esta restauración.

Se usan [AccessibilityFocusState](https://developer.apple.com/documentation/swiftui/accessibilityfocusstate) y [ScrollViewReader](https://developer.apple.com/documentation/swiftui/scrollviewreader), sin temporizadores, anuncios duplicados, cambios de modelo de datos ni reglas de negocio. No se añade un test unitario que pretenda demostrar el foco de VoiceOver: el fallo y su corrección requieren el ensayo físico. Build de las 18:54:22 correcto, solo EXC-002. Revisión independiente de los dos archivos Swift y auditoría de estilo sin hallazgos. La recuperación real de foco al cerrar con Cancel y con Apply queda pendiente de repetir en el iPhone 14, incluida una fila baja del formulario.

Previews de AddItemsView y DraftItemRow renderizadas e inspeccionadas en iPhone 18 Pro/iOS 27.2, variantes Large, XXX Large y AX5: seis renders correctos, controles de la fila separados y adaptados al texto grande, sin solapamiento observado. La captura de Añadir a AX5 muestra solo el inicio del formulario; la fila se inspecciona además en su preview propia. Esto valida la composición visible, no el desplazamiento y foco interactivos.

Ajuste instalado y arrancado en iPhone14 de Jesús a las 18:56:37, proceso 5110, desde el worktree de #7. Sin commit ni push; pendiente de confirmación del usuario en Edit → Cancel y posteriormente Apply.

El usuario confirma sobre el ajuste instalado: «correcto, ahora queda en el Edit que se pulsó». Queda superado el retorno del foco de VoiceOver al botón Edit del producto de origen tras abrir y cancelar la edición de una fila existente. Apply y cierre interactivo todavía no se acreditan con este resultado.

En la repetición con Apply, el usuario confirma «también ha vuelto al Edit que se pulsó». Queda confirmado el destino del foco de VoiceOver al cerrar la edición mediante Cancel y mediante Apply sobre una fila existente. El cierre interactivo no se ha ensayado por separado; comparte onDismiss, pero no se declara validado físicamente. El resultado comunicado se refiere al foco y no añade una verificación independiente de persistencia.

Comprobación posterior del placeholder: con el tamaño de accesibilidad al máximo y el campo Write or dictate vacío, el usuario comunica «se ve completo». No se reproduce el recorte en este ensayo y no se modifica el código del campo. El recorrido venía realizándose con controles ingleses; la respuesta no confirma expresamente un cambio de idioma. El recorte histórico fue observado en español, por lo que se solicita comprobar ese idioma por separado antes de cerrar el hallazgo bilingüe.

El usuario repite el campo vacío con la app en español y tamaño de accesibilidad máximo y confirma «se ve completo también». El recorte del placeholder no se reproduce en los ensayos actuales en inglés y español. No se ha aplicado una corrección al campo ni se atribuye una causa al recorte histórico. Se completa esta comprobación bilingüe acotada; la corrección de foco y su evidencia permanecen locales, pendientes de commit/push.

## Etiqueta de cantidad en el editor manual — seguimiento de #7

El usuario detecta después un campo diferente: al introducir un producto manualmente, el placeholder de cantidad muestra «Cantidad, op…». Se conserva la comprobación previa del ejemplo principal; no acredita este editor.

`DraftItemEditor` presenta «Quantity, optional» / «Cantidad, opcional» como etiqueta persistente que puede ocupar varias líneas. El campo conserva su título accesible localizado y un prompt vacío; la etiqueta visual se oculta a VoiceOver para no duplicarla. Se mantienen el binding, texto libre, carácter opcional y validación. No se reduce el tamaño de fuente ni se fija la altura. La preview «Producto nuevo» usa el fixture compartido `.shoppingDraft(.empty)`.

Build de las 19:11:32 correcto, solo el warning App Intents aceptado por EXC-002. Revisión independiente del diff sin hallazgos, API contrastada con el SDK beta y auditoría de estilo correcta. Previews renderizadas e inspeccionadas en iPhone 18 Pro/iOS 27.2 entre 19:12:34 y 19:12:39: EN/ES × Large/XXX Large/AX5. La etiqueta completa aparece en las seis; AX5 envuelve «opcional» / «optional» en una segunda línea. El pie del formulario queda parcialmente fuera del viewport a AX5; las snapshots no acreditan scroll ni interacción. La implementación final usa `Text(verbatim: "")` exclusivamente para el prompt vacío, evitando una clave de traducción sin contenido.

Pendiente de ensayo físico: localizar y activar la cantidad vacía, escribir y confirmar que la etiqueta permanece completa; con VoiceOver debe anunciarse una sola etiqueta. No se añaden tests unitarios que simulen una garantía de layout o foco. El ajuste y la evidencia continúan locales, junto con la corrección de foco anterior; sin commit/push nuevo.

Versión final compilada e instalada desde el worktree de #7 en iPhone14 de Jesús a las 19:13:42 mediante RunProject, proceso 5444, arranque correcto. Solo EXC-002 en el log de compilación. Esta instalación deja preparado el ensayo físico, sin darlo por superado.

Ensayo físico posterior confirmado por el usuario: la captura de las 19:14:56 muestra «Cantidad, opcional» completo en dos líneas con texto grande. Tras solicitar la comprobación con VoiceOver, el usuario confirma «sí, correctas ambas cosas»: la etiqueta se anuncia una sola vez, el campo se identifica y puede activarse/editarse, manteniendo la etiqueta y leyendo el valor. Queda superado este recorrido en español sobre el iPhone 14; no se declara una segunda ejecución física en inglés. El color diferente respecto a los placeholders se corresponde con la etiqueta secundaria persistente; la unificación visual de los campos queda para la integración del design system, según lo acordado. Sin cambios adicionales de código ni nueva ejecución de tests por esta confirmación.


### Revisión del campo al volver a tamaño normal

La captura física de las 19:20:32 muestra que la solución anterior deja una fila excesivamente alta: etiqueta encima de un campo vacío. Es una consecuencia del VStack, no evidencia de que Dynamic Type haya quedado bloqueado. Se reemplaza ese diseño por el mismo TextField vertical que Producto/Tienda con placeholder breve «Quantity» / «Cantidad». Su nombre accesible sigue siendo «Quantity, optional» / «Cantidad, opcional»; el pie ya explica visualmente que la cantidad es opcional. Se elimina el contenedor y no se fija tamaño ni se reduce tipografía. La clave nueva Quantity dispone de traducción española.

Build de las 19:22:05 correcto. Revisión independiente sin hallazgos. Se renderizan e inspeccionan seis previews del producto nuevo (19:22:23–19:22:28), EN/ES × Large/XXX Large/AX5: placeholder completo, filas consistentes y sin el hueco añadido. El código y las previews sustituyen la solución de etiqueta persistente documentada arriba. La confirmación previa de VoiceOver corresponde a esa versión anterior; pendiente de repetir sobre este campo compacto, junto con el cambio físico de texto grande a normal. Sin nuevo commit/push.

Instalada y arrancada la versión compacta desde el worktree en iPhone14 de Jesús a las 19:23:17, proceso 5470. El build conserva únicamente el warning aceptado EXC-002. Catálogo normalizado para conservar solo la nueva traducción y evitar cambios de formato generados por Xcode.

El usuario elige expresamente la opción compacta y confirma sobre esta versión: «sí, se ve bien en todos los tamaños y la locución dice cantidad opcional». Queda superada la comprobación física del aspecto a tamaño normal y grande, y del nombre accesible completo en español. Esta confirmación corresponde a la solución final con placeholder breve; no se extrapola a una repetición física en inglés ni a toda la matriz de accesibilidad. Evidencia consolidada localmente, pendiente de commit/push junto con el retorno del foco tras editar.


### Consolidación para entrega del editor

El usuario autoriza commit y push del retorno del foco y la solución compacta de cantidad. Se incluyen los tres archivos Swift, la traducción, changelog y esta evidencia. Revisión final del diff, estilo Swift y `git diff --check` correctos; se reutilizan los builds y previews del mismo código y los ensayos físicos confirmados arriba. Solo han cambiado documentos desde la última instalación. No se vuelve a ejecutar la suite de reglas de negocio por estos ajustes de presentación. La entrega se limita a `codex/issue-7-speech-diagnostics`; #7 y el hito continúan abiertos. Siguiente trabajo previsto: distinguir consulta vacía, todavía no cargada y fallida en Comprar. El hash y la confirmación del push se registran en el tracker tras verificar el remoto.


## Tiendas alternativas en inglés — seguimiento de #7 y PR #15

El usuario confirma en la app del Mac con interfaz inglesa que «I need bread and coffee.» añade bread y coffee sin cantidad ni tienda y conserva las entradas previas. El siguiente ensayo, «I need bread and coffee. I haven't decided whether to buy them at Aldi or Lidl.», muestra el aviso genérico de interpretación fallida en la captura de las 19:40:03. No se da por superado ni se infiere conservación del borrador solo del texto de la alerta. Xcode MCP identifica la app del worktree ejecutándose en Mac, proceso 44903. Se preserva el cambio del usuario en el scheme para idioma inglés.

Diagnóstico aislado con instrucciones exactas en en-US y esquema de producción: el modelo devuelve bread/Aldi, coffee/Aldi, bread/Lidl y coffee/Lidl. `DraftExtractionRules.validate` rechaza el tercer nombre porque ya consumió su única mención en el texto. Explica el fallo reproducido por el sondeo; la salida original de la app no se capturó. No se relacionan los logs de AppIntents/AX del arranque con esta interpretación sin evidencia.

Se precisan instrucciones y guía de tienda: ante alternativas no elegidas, conservar productos con tienda nula, sin multiplicarlos por cada tienda ni interpretar una referencia pronominal posterior como otra mención. Se mantiene intacta la validación literal y atómica; no se añade deduplicación, parser, retry silencioso ni cambio de mensaje. Revisión independiente aprueba el ajuste mínimo. La disponibilidad y el resultado de un modelo real no se prueban con tests que comparen el prompt; los sondeos funcionales y la regresión determinista se registran por separado.


Validación local del ajuste: build con targets de pruebas a las 19:42:56 correcto, solo EXC-002; auditoría de estilo de FoundationModelsDraftInterpreter sin hallazgos. Nueve sondeos con el intérprete de producción devuelven los resultados esperados: frase inglesa fallida con apóstrofo recto y tipográfico, inglesa sin tienda, ambigua española, tiendas explícitas diferentes, apples repetidos explícitamente con cantidades 2/3 en Aldi/Lidl, tienda común con cantidad parcial ES/EN y negativo inglés (`noProducts`). Seis completan el primer intento; apóstrofo tipográfico, frase sin tienda y apples repetidos interrumpen inicialmente con «Preview service no longer running» y completan un único reintento individual. No se borran esos fallos de infraestructura ni se declara corregida la estabilidad del servicio. Evidencias auxiliares `/tmp/ssl-ambiguous-raw-result.json`, `/tmp/ssl-ambiguous-regression.json` y `/tmp/ssl-ambiguous-retry.json`; los sondeos no escriben en el borrador del usuario.


Regresión automatizada sobre el código ajustado: plan Fast en My Mac (Designed for iPad), macOS 27.2 `26B5091g`, Xcode 27.2 beta. Resultado nativo cerrado `Test-SmartShoppingList-2026.09.24_19-45-22-+0200.xcresult`: 74 tests únicos / 130 ejecuciones, cero fallos, omitidos y warnings de runtime. Los seis `notRun` de MCP quedan fuera del plan Fast. La suite verifica reglas y coordinación con dobles, no la calidad de la inferencia real. La app ajustada se compila y arranca en My Mac a las 19:45:56, proceso 47142. Pendiente repetir la frase ambigua desde esa app y confirmar los productos anteriores; el resultado positivo del sondeo no sustituye esa interacción. No se ha hecho commit/push del ajuste ni merge de PR #15.

Repetición manual sobre la app actualizada del Mac: el usuario confirma «Ahora sí» al ensayo propuesto con la misma frase inglesa ambigua. Queda confirmado que añade bread y coffee sin cantidad ni tienda, conservando las entradas anteriores. Junto al caso sin tienda confirmado previamente, se completan los dos casos ingleses pendientes. Es evidencia manual comunicada por el usuario, separada de los sondeos de previews; no acredita estabilidad general del modelo. La corrección continúa local y PR #15 permanece en borrador mientras se comprueban los avisos restantes.


## Avisos largos en simulador — 24 de septiembre, 20:08

El usuario prueba en iPhone 17 simulado el aviso inglés de interpretación fallida con texto ampliado: puede leerlo completo mediante scroll y el botón Dismiss notice sigue accesible (captura 20:08:15). Confirma después que al cerrarlo vuelve al borrador con texto y productos conservados. Es evidencia manual de ese aviso; no se atribuye al mensaje de almacenamiento ni a VoiceOver. La preview anterior permitía cerrar, pero no mostraba escalado AX5 verificable, incluso con el override; no se usa como evidencia de tamaño máximo.

Se prepara una pantalla aislada `ShoppingNoticeValidationView`, exclusivamente Debug y activada con `-shopping-notice-validation`. Evita construir SharedAppFactory: sin borrador real, credenciales, red ni persistencia. Reutiliza ShoppingNoticeModifier y los mensajes localizados de producción. Primer botón: aviso de almacenamiento persistente (cerrarlo no borra su origen). Segundo: aviso de interpretación seguido, tras cinco segundos, de No products; cerrar el primero debe respetar el nuevo. Controles de diagnóstico en inglés verbatim, fuera de la interfaz distribuida; preview autocontenida sin almacenamiento. No se modifica el comportamiento del presenter.

Revisión independiente detecta y corrige el descarte del aviso persistente del fixture; segunda revisión sin hallazgos. Build Debug para iPhone 17/iOS 27.2 correcto, únicamente EXC-002. Xcode RunProject no activó el argumento recién escrito en el scheme; se retiró ese argumento temporal conservando language=en del usuario. Se relanza el binario compilado con simctl y el argumento explícito (proceso 55233); Device Hub confirma los dos botones de diagnóstico y Text Size=11. No hay cambios de datos ni de tamaño de texto. Los dos ensayos del fixture siguen pendientes de confirmación manual. Sin commit/push de estos cambios.


### Resultado manual y reproducción del reemplazo — 20:17–20:23

El usuario confirma el primer botón del fixture: aviso largo de almacenamiento completo mediante scroll, cierre y ausencia de reapertura espontánea. Junto al aviso de interpretación de 20:08 queda comprobada la lectura/cierre a tamaño máximo en iPhone 17 simulado; no se repite por cada mensaje ni se atribuye VoiceOver.

El segundo botón falla: después de esperar y cerrar el aviso de interpretación, vuelve directamente a la pantalla de diagnóstico. Reproducido mediante interacción en Device Hub. Se incorpora diagnóstico exclusivamente Debug: `Replacement delivered: true`, `Last dismissed: The text could not be interpreted…`, `Pending: No products were found…`. Confirma que el mensaje nuevo llega y permanece en el modelo; no se muestra después del cierre. Es un defecto de presentación, no pérdida del borrador ni fallo del temporizador de prueba. No se da por aprobado el criterio de reemplazo ni se cierra #7/PR #15.

Se ensaya reemplazar onChange(isPresented) por task(id:isPresented), sin pausas artificiales: compila y reproduce el mismo fallo. El experimento se retira del código. Apple documenta que los datos de una alerta ya presentada no se actualizan; el SDK 27.2 muestra que el overload item delega en isPresented/presenting, por lo que cambiar únicamente ese overload no acredita una solución. Pendiente corregir la coordinación de presentaciones y verificar el comportamiento; no son necesarias más repeticiones del scroll ya validado.


### Repetición positiva y contraste de tiempos — 20:52–20:53

El usuario rectifica su observación anterior tras repetir: ve primero el aviso genérico y después No products. Se registra esa repetición manual como correcta, sin inferir el instante exacto del primer cierre. La afirmación previa de fallo se acota: no falla toda secuencia de dos avisos.

Contraste autónomo en el mismo binario con ShoppingNoticeModifier original (experimento task retirado): dejando el primer aviso abierto 6,5 segundos, al cerrarlo y esperar otros 2 segundos no aparece el segundo; la acción de iniciar otra secuencia tampoco abre alerta. Tras relanzar el fixture, se inicia y descarta el primero inmediatamente mediante interacción de accesibilidad; al esperar 6,5 segundos aparece No products y se puede cerrar. Esto distingue un caso correcto (el segundo llega después del cierre) y uno fallido (llega mientras el primero sigue abierto). No demuestra que el usuario pulsara antes de cinco segundos ni invalida su resultado positivo. Queda pendiente resolver la presentación cuando hay un aviso nuevo ya pendiente al descartar el anterior. La lectura con scroll sigue validada.


### Corrección del reemplazo pendiente — 21:09–21:17

El usuario reproduce el fallo tanto con Device Hub expandido como compacto: el segundo mensaje queda en `Pending` sin alerta. No hay evidencia que permita atribuir este defecto a la expansión de Device Hub. Se mantiene el tamaño de texto mínimo solicitado para observar la secuencia.

Se aísla cada presentación mediante un identificador y un host de fondo. El binding de presentación y el botón de cierre ignoran callbacks de identidades anteriores; el formulario conserva su identidad. Cambiar solo la identidad del host no resolvió la reproducción: la protección del binding es parte necesaria de la solución verificada. No se añaden pausas a producción ni se modifica el descarte condicional de los modelos. Revisión independiente del modifier final sin hallazgos. Se documenta el motivo del binding calculado.

Dos ejecuciones controladas en iPhone 17/iOS 27.2, Device Hub compacto y texto pequeño: el primer aviso permanece abierto más de seis segundos; con `Replacement delivered: true`, cerrarlo muestra la alerta No products. Se cierran ambos; la primera ejecución acredita además el estado final `Last dismissed: No products…`, `Pending: none`. Esto cubre específicamente el orden que fallaba, no solo la llegada del segundo mensaje después del primer cierre.

Se amplía el fixture Debug con un tercer escenario: oculta el presentador tras cinco segundos y permite restaurarlo mediante un botón. Ensayo observado: primero alerta Draft storage; después `Presenter enabled: false`, ninguna alerta, `Last dismissed: none` y mensaje de almacenamiento conservado; Restore presenter vuelve a mostrar Draft storage. El mensaje persistente se mantiene en el modelo al cerrarlo. El temporizador pertenece solo al diagnóstico. La tarea captura escenario e identificador de ejecución y valida cancelación/vigencia antes de aplicar cambios. El propio fixture indica ejecutar este escenario después del segundo o desde un arranque limpio, porque volver a solicitar el mismo almacenamiento ya reconocido no debe reabrirlo.

Build y arranque finales con Xcode MCP a las 21:17:03 correctos, proceso 69605; log `RunProject-Log-20260924-211703.txt`, únicamente el warning de metadatos App Intents aceptado en EXC-002. Se relanza el fixture final con argumento explícito, proceso 69797, para confirmación del usuario. `git diff --check` correcto. No se repite la suite de reglas de negocio ni se atribuyen sus resultados anteriores a este cambio visual; la verificación relevante es la secuencia real de alertas. Lectura/foco VoiceOver del host final pendiente de confirmación; no se extrapola la evidencia del presentador anterior. Corrección y diagnóstico locales, sin commit/push, merge ni cierre de #7.


### Confirmación final y preparación de publicación — 24 de septiembre

Sobre el fixture final instalado, el usuario confirma «Correcto» a la secuencia completa: pulsar Replace while open, mantener el primer aviso abierto seis segundos, cerrarlo, ver No products, cerrar el segundo y terminar con Pending: none. Queda superado el criterio de reemplazo pendiente. Esta confirmación no incluye VoiceOver; la lectura/foco del nuevo host queda como comprobación acotada antes de la revisión final de cierre. No hay que repetir el scroll por cada texto.

El usuario autoriza actualizar la evidencia, commit y push. Se publican conjuntamente los hallazgos resueltos de esta validación: instrucciones para tiendas alternativas, coordinación de alertas y fixture Debug aislado. Auditoría de estilo de los cuatro Swift modificados sin hallazgos; mensajes literales de diagnóstico conservados como excepciones justificadas de longitud. Se reutiliza el build final de las 21:17:03 y las interacciones del mismo código; desde entonces solo cambia documentación. Se conserva fuera del commit language=en del scheme, cambio del usuario. La issue #7 y PR #15 permanecen abiertas, con merge/cierre fuera de esta autorización. El hash y resultado del push se registran en GitHub una vez verificados.
