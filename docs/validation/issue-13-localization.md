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

## Matriz de ensayo y comprobaciones restantes

Usar la app compilada desde esta rama. Cambiar su idioma en la configuración de idioma por app de iOS y volver a abrirla; para simulador también se puede elegir Application Language en el esquema de ejecución de Xcode. No hace falta cambiar la región. El ajuste por app puede requerir tener ambos idiomas añadidos en los ajustes generales del sistema.

1. En español, comprobar Añadir/Comprar, editor, revisión, errores y confirmación con un borrador existente; nombres y cantidades deben conservarse al cambiar de idioma.
2. El recorrido manual inglés en iPhone 11, las etiquetas de VoiceOver del recorrido indicado en iPhone 14 y las fechas de invitación UK/US están confirmados arriba. Los datos introducidos se conservan en su idioma original; la prueba regional no acredita estabilidad de Foundation Models.
3. Dictar en el entorno que ya admite Speech: «Dos litros de leche y pan integral en Aldi» y «Two litres of milk and wholemeal bread at Aldi». Terminar conserva el texto; cancelar restaura exactamente el anterior. Revisar el permiso en el idioma de la app si se solicita por primera vez.
4. En el Mac/simulador con Foundation Models disponible, interpretar esas frases por separado. Verificar dos productos, tienda y cantidad, revisar y corregir antes de enviar. El iPhone sin Apple Intelligence debe seguir ofreciendo entrada manual.
5. Probar una frase sin compra en ambos idiomas: «Hoy hace buen tiempo y voy a pasear» / «The weather is nice today and I am going for a walk». No debe incorporar productos inventados.

Registrar entorno, idioma, resultado y cualquier texto incorrecto en #13/#7. La disponibilidad del modelo, los idiomas instalados del sistema y el consentimiento del micrófono se comprueban por separado; una traducción o un test determinista no los acredita. No se cierra la issue ni se declara el MVP bilingüe validado hasta completar sus criterios y entregar los cambios.
