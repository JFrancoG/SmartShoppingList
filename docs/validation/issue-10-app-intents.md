# Issue #10 · Entrada al borrador y a la lista con App Intents

Fecha: 26 de septiembre de 2026. Rama: `codex/issue-10-app-intents`, base `0e5ab1c` (`main`).

## Estado y alcance

Intento opcional autorizado por el propietario con un margen de 3–4 horas. El 27 de septiembre el propietario confirma el alta al borrador desde Atajos en el iPhone 14 y el recorrido básico de Siri tradicional con la app en primer plano, en segundo plano y cerrada: en este último caso Siri abre la app y añade el producto al borrador. Después autoriza una segunda acción que añade directamente a una tienda existente cuando existe una coincidencia exacta y única. **La ampliación pasa la validación automática y el propietario confirma que el recorrido mejorado funciona y lo acepta tras instalar la pregunta de cantidad**. Autoriza commit y push de la rama; la issue sigue abierta y PR, merge y cierre quedan como pasos posteriores. No se ha desplegado el servidor. Siri AI queda como ampliación posterior al MVP.

Una acción «Añadir producto al borrador» recibe producto y tienda obligatorios y cantidad literal opcional. Abre la app, requiere desbloqueo local y añade al borrador para revisar antes del envío al grupo. No invoca Foundation Models ni envía productos, compra o cancela. Funciona sobre la instancia de aplicación registrada en `AppDependencyManager`, sin escritor de archivo adicional.

El borrador conserva sus filas y texto, valida límites de 60/80/40 caracteres y 50 productos, rechaza operaciones incompatibles y espera su cola de persistencia antes de anunciar éxito. Un fallo de escritura deja la fila visible con un error que pide mantener la app abierta y revisar. La restauración local compartida no inicia solicitudes a la API; el refresco inicial de sesión puede continuar en paralelo sin modificar el borrador.

La protección frente al doble procesamiento acepta la **misma identidad interna** y conserva las últimas 100 en el snapshot, incluso después de consumir la fila. No es una promesa entre invocaciones nuevas de Siri: Apple no expone una identidad pública estable para esos reintentos. Dos ejecuciones independientes iguales pueden crear dos productos. El diálogo distingue una petición nueva de una ya procesada. Diseño y fuentes primarias en [arquitectura del borrador](../architecture/ios-draft.md#entrada-explícita-con-app-intents-10-26-de-septiembre).

## Ampliación aprobada: añadir directamente a una tienda existente

La nueva acción `AddShoppingItemIntent` se invoca con «Añade a mi lista de la compra en SmartShoppingList» o la variante anterior «Añade a mi lista en SmartShoppingList»; en inglés, `Add to my shopping list in SmartShoppingList` o `Add to my list in SmartShoppingList`. Tras el refinamiento descrito más abajo, solicita producto, cantidad literal y tienda por separado. La acción anterior y sus dos frases mantienen su comportamiento de borrador local.

La entrada se guarda antes de consultar la sesión y las tiendas del grupo. Una coincidencia exacta y única, normalizada sin distinguir mayúsculas, permite enviar sólo ese producto mediante la operación persistida existente. Una tienda desconocida o ambigua, o la falta de acceso, deja la fila editable en el borrador sin crear tiendas. No se utiliza un catálogo para resolver o sustituir nombres de productos. El resto de filas y texto del borrador se conserva.

Tras confirmar el servidor y completar la persistencia local, se presenta el aviso existente «Ver lista / Cerrar». «Ver lista» sólo navega y no vuelve a enviar. Un resultado incierto mantiene la operación original para su recuperación y no anuncia éxito ni afirma que no hubo envío. El identificador recibido evita reprocesar la misma petición interna; una nueva invocación independiente puede añadir otro producto con el mismo contenido.

Validación del 27 de septiembre, 01:38 (Europe/Madrid):

- Xcode 27.1 beta, Service MCP, SDK iOS 27.1, iPhone Duo Simulator iOS 27.1. Clean Build Folder seguido de build-for-testing satisfactorio; log completo y GetBuildLog sin warnings ni errores.
- Fast: **159 funciones / 280 ejecuciones**, 0 fallos, 0 omitidos y sin runtime warnings. Integration: **8 funciones / 12 ejecuciones**, mismos resultados. Cifras verificadas en los bundles nativos cerrados; el resumen agregado del MCP mezcla resultados de planes y no se usa como autoridad. Fast queda restaurado.
- Cobertura añadida: envío de una sola fila y conservación de las demás; tienda desconocida/ambigua; falta de sesión o error de consulta; carga inicial concurrente; resultado remoto incierto y fallo de limpieza local; identidad tras reconstrucción; exclusión de acciones concurrentes; cancelación durante consulta de tiendas. Se amplía a ambas acciones el rechazo ante una operación restaurada pendiente.
- Metadatos compilados: dos intents, tres frases por idioma, producto/tienda requeridos y cantidad opcional. La nueva frase española está asociada a `AddShoppingItemIntent`; las dos anteriores siguen asociadas a `AddDraftItemIntent`. Las ocho claves nuevas de presentación y diálogo tienen traducción española.
- Revisión independiente de dominio, adaptación del intent y presentación: sin hallazgos pendientes. Auditoría de estilo de los siete archivos Swift afectados por la ampliación: 0 candidatos; `git diff --check` correcto. No sustituye una prueba de voz o accesibilidad en dispositivo.

Evidencia local de la ampliación:

- Build-for-testing: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260927-013803.txt`.
- Fast: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/Test-SmartShoppingList-2026.09.27_01-38-14-+0200.xcresult`.
- Integration: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/Test-SmartShoppingList-2026.09.27_01-38-44-+0200.xcresult`.

El recorrido ajustado se acepta mediante la confirmación del propietario registrada más abajo. La variante específica con tienda desconocida → fila editable sin creación de tienda sigue sin confirmación física separada; su cobertura es automática. No se exige repetir los tres estados ya confirmados para la acción anterior.

Se selecciona `iPhone14 de Jesús` y se solicita RunProject sin debugger. La compilación física termina sin warnings/errores y contiene ambos intents y las tres frases ES/EN. El lanzamiento queda esperando al desbloqueo del dispositivo (`Unlock iPhone14 de Jesús to Continue`); todavía no se acredita una ejecución de esta versión. Log de compilación: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/GetBuildLog/F212D726-68CF-4425-A696-0361A33A2A6C.txt`.

### Refinamiento de frase y cantidad — 27 de septiembre, 02:05

El propietario propone «Añade a mi lista de la compra» y observa que responder «dos packs de seis unidades de leche» a la pregunta del producto guarda esa respuesta completa como nombre. Se añade la variante con el nombre de la app y se conserva la frase anterior. `AddShoppingItemIntent.quantity` pasa a ser texto requerido, sin default, con el diálogo «¿Qué cantidad quieres?» / `What quantity would you like?`. Producto, cantidad y tienda aparecen en el resumen de Atajos; así la cantidad deja de estar oculta entre parámetros opcionales. `AddDraftItemIntent` mantiene su cantidad opcional y los atajos existentes de borrador.

La intención es recibir producto «leche» y cantidad «dos packs de seis unidades» como valores distintos. No se interpreta ni corrige la respuesta al producto. Siri debe resolver los tres parámetros antes de `perform`; la declaración y el resumen siguen producto → cantidad → tienda, pero el orden efectivo y los diálogos hablados se comprobarán en el teléfono. No hay cambios en el envío, la persistencia ni los reintentos. Fuentes: [resolución de parámetros requeridos](https://developer.apple.com/documentation/appintents/adding-parameters-to-an-app-intent) y [ciclo de ejecución del intent](https://developer.apple.com/documentation/appintents/creating-your-first-app-intent).

Build físico Xcode 27.1 satisfactorio: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260927-020533.txt`. La validación de este ajuste se limita a compilación, metadatos y catálogos; las suites anteriores acreditan la lógica de dominio sin cambios, no las preguntas de Siri. Metadatos verificados: los tres parámetros de la acción de lista son requeridos; la cantidad del borrador sigue siendo opcional. El resumen muestra los tres campos y se extraen cuatro frases por idioma. Los recursos compilados en español contienen la pregunta de cantidad y el resumen actualizados. Revisión independiente sin hallazgos; auditoría de estilo de dos Swift, 0 candidatos, y `git diff --check` correcto.

A las 02:06 se instala y lanza la versión en `iPhone14 de Jesús`, sin debugger, mediante RunProject: PID `9367`, sesión `79009f2e80`; log `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunProject/RunProject-Log-20260927-020644.txt`. El lanzamiento es satisfactorio; la petición anterior que esperaba el desbloqueo agotó el tiempo del MCP y no se usa como evidencia. Pendiente ejecución por voz con la nueva frase y cantidad separada.

### Aceptación del recorrido y entrega de la rama — 27 de septiembre

Tras instalar la versión anterior y solicitar la prueba de la frase nueva con producto y cantidad separados, el propietario responde: «Ahora sí, mucho mejor. Yo creo que está bien» y autoriza commit y push. Se registra como confirmación y aceptación del recorrido ajustado en el iPhone 14. No se infieren de esa respuesta el orden exacto de todas las preguntas, una prueba inglesa, cancelación durante resolución, teléfono bloqueado ni la rama de tienda desconocida; esos detalles no se describieron individualmente.

Se actualizan README, plan y este informe antes del commit. Se reutilizan las 280 ejecuciones Fast y 12 Integration del dominio, que no ha cambiado después de esas pruebas, junto al build físico y los metadatos comprobados tras hacer requerida la cantidad. El alcance de entrega es commit y push de `codex/issue-10-app-intents`; la issue #10 conserva las variantes no acreditadas y sigue abierta. PR, merge, cierre y eliminación de rama no forman parte de esta autorización. El resultado definitivo de Git se registra en la issue con su enlace al commit.

## Compilación y metadatos de la acción inicial de borrador

- Xcode 27.2 beta `27B5019j`, Service MCP `xcode-27-2-beta`, scheme `SmartShoppingList`, SDK iOS 27.2, destino iPhone Duo Simulator iOS 27.1 (`24A94401`, arm64).
- App y build-for-testing satisfactorios. Logs completos finales sin `warning:` ni `error:`. No se modifican deployment target, flags de Swift ni dependencias.
- `Metadata.appintents/extract.actionsdata` contiene `AddDraftItemIntent`, parámetros `product`/`store` requeridos y `quantity` opcional, ejecución foreground/main y autenticación local. Contiene un App Shortcut con dos frases y su título.
- `ValidateAppShortcutStringsMetadata` completado; `AppShortcuts.xcstrings` genera las frases españolas y los recursos `nlu.appintents` para inglés y español. Las 11 claves nuevas de `Localizable.xcstrings` tienen traducción española; ninguna entrada previa cambia semánticamente.
- El primer intento con Xcode 27.0 falló en `ShoppingControlRegions.swift` por `GeometryProxy.reservedRegions`, API de la UI Duo ya integrada. Se continuó con la versión 27.2 que ya validó #30; no se alteró esa funcionalidad para este extra.
- EXC-002 deja de cubrir el target de app, que ahora declara intents y debe extraerlos correctamente. Se mantiene su alcance en los targets de pruebas/servidor sin adopción; el build-for-testing final de esta ejecución no emitió ese aviso. No se ejecutó el servidor.

Log de build-for-testing: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260926-231801.txt`.

El 27 de septiembre se corrige la agrupación de frases extraída por Xcode: el único `stringSet` conserva las dos frases inglesas y ahora incluye ambas españolas. La segunda traducción había quedado en una clave `stale`; se integra antes de eliminar esa clave. Xcode 27.1 compila para `iPhone14 de Jesús` (iOS 27.2) sin warnings ni errores. El producto contiene ambas traducciones en `es.lproj/AppShortcuts.strings` y dos utterances por idioma en `Metadata.appintents/root.ssu.yaml`, asociadas a `AddDraftItemIntent`. El catálogo conserva la agrupación tras extraerlo. No se repiten las suites de lógica por este cambio limitado al catálogo.

Log de esta corrección: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260927-004559.txt`. A las 00:46 se instala y lanza la versión corregida en el mismo iPhone mediante Xcode, sin debugger. La compilación y el lanzamiento no acreditan reconocimiento por Siri.

A las 00:48, Device Hub muestra la app relanzada con la fila `Pros-atajo`, cantidad `2`, tienda `Testshop`. Esta observación acredita que esa fila permanece tras el relanzamiento realizado desde Xcode; no se extiende la evidencia a otros borradores. El posterior lanzamiento desde Siri con la app cerrada se registra más adelante mediante confirmación del propietario.

## Swift Testing de la acción inicial de borrador

| Plan | Funciones ejecutadas | Casos ejecutados | Fallos / omitidos |
| --- | ---: | ---: | ---: |
| Fast | 151 | 267 | 0 / 0 |
| Integration | 8 | 12 | 0 / 0 |

Resultados comprobados con `xcresulttool get test-results summary` sobre ambos bundles cerrados. El MCP lista incorrectamente todos los tests como deshabilitados y su segundo resumen mezcla resultados previos (107 en lugar de 12); las cifras anteriores provienen del resultado nativo. El test de plantilla sin tag no pertenece a ninguno de estos planes. Se restaura Fast como plan activo.

Evidencia local:

- Fast: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/Test-SmartShoppingList-2026.09.26_23-18-24-+0200.xcresult`.
- Integration: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/Test-SmartShoppingList-2026.09.26_23-19-09-+0200.xcresult`.

Regresiones nuevas: preservación fría/caliente, identidades distintas con el mismo contenido, carga UI todavía pendiente, adición concurrente rechazada, límites exactos y valores inválidos, editor/interpretación/propuesta ocupados, fallo de guardado y reintento, escritura UI antigua suspendida que no puede sobrescribir la entrada nueva ni anticipar éxito, restauración local sin API con/sin sesión, refresco inicial suspendido, operación pendiente y credenciales irrecuperables. Persistencia real en archivo temporal: borrador JSON legado, nueva instancia tras guardar/consumir y archivo corrupto conservado byte a byte. No hay esperas temporizadas como oráculo ni acceso al backend real en estas pruebas.

## Ensayo del sistema

La instalación en el simulador finalizó correctamente. La inspección de aplicaciones confirma que iPhone Duo no incluye `com.apple.shortcuts`; `simctl appinfo` devuelve `Application not found`. `com.apple.ShortcutsActions` es un auxiliar, no la app Atajos. Además, la sesión de interacción MCP devuelta dejó de existir antes de la primera captura; el cierre confirmó que ya no existía. No se obtuvieron capturas ni se ejecutó el intent mediante el sistema. Evidencia: `/tmp/smartshoppinglist-shortcuts-simulator-evidence-20260926.txt`.

No se atribuyen estas comprobaciones a Siri, Atajos, desbloqueo, VoiceOver, dispositivo físico ni proceso frío del sistema. Los tests de carga fría reconstruyen los modelos con su persistencia; no sustituyen el lanzamiento externo de iOS. No se añadió un enlace o driver de depuración que pudiera confundirse con la acción real.

### Atajos en Mac: descubrimiento bloqueado

El propietario abrió la app con Xcode 27.1 en `My Mac (Designed for iPad)`, macOS 27.2 (`26B5091g`), SDK iOS 27.1. Es ejecución de la app iOS sobre el Mac, no un simulador. Apple admite estos intents en Atajos para apps iOS instalables en macOS: [WWDC25, Develop for Shortcuts and Spotlight with App Intents](https://developer.apple.com/videos/play/wwdc2025/260/), sección Automations on Mac.

El bundle ejecutado contiene `AddDraftItemIntent` y su App Shortcut. La búsqueda en el catálogo de acciones de Atajos, incluso tras reiniciarlo, no encuentra la app ni la acción. Se creó únicamente el atajo vacío `Prueba App Intents · SmartShoppingList`; no se ejecutaron otros atajos ni se añadieron productos.

El registro de `linkd` (`com.apple.appintents`) a las 23:30:27, 23:30:28, 23:30:30 y 23:30:34 muestra `Failed to generate bundleIdentity` y `LSApplicationRecord for com.plusprojects.SmartShoppingList:… is not trusted, rejecting`. La ruta corresponde al wrapper de desarrollo que está abierto. LaunchServices notificó su registro previamente. `codesign --verify --deep --strict` valida la firma y su Designated Requirement; esa comprobación no equivale a la confianza exigida por `linkd`.

Evidencia local filtrada exclusivamente por el bundle: `/tmp/smartshoppinglist-mac-intents-discovery-20260926.log`. El bloqueo se produce antes de invocar el intent. No demuestra un fallo de `perform()` ni una incompatibilidad general de App Intents con iOS-on-Mac. No se encontró una solución documentada por Apple para este rechazo; no se modificaron certificados, registros de LaunchServices ni cachés. La siguiente comprobación útil es Atajos en un iPhone físico.

## Descubrimiento y primera ejecución confirmados en iPhone 14

El 27 de septiembre, a las 00:20, se accede al iPhone 14 físico con iOS 27.2 mediante la pantalla de Device Hub de Xcode 27.1. En el catálogo de acciones de Atajos, la búsqueda de SmartShoppingList muestra la app y **Add product to draft**. Queda confirmado el descubrimiento del intent en este dispositivo; todavía no se añade ni ejecuta la acción. Se deja el resultado abierto para el propietario y se restaura la captura de teclado del Mac a su estado previo.

La interacción se realizó mediante la interfaz de Device Hub. El selector `DeviceInteractionStartSession` del MCP 27.1 rechaza este teléfono por nombre y UDID y ofrece solamente simuladores, aunque `devicectl` y el destino de Xcode confirman que está conectado. No se creó una sesión MCP. Esta limitación de la herramienta no afecta al descubrimiento observado en Atajos.

Posteriormente, el propietario añade la acción al atajo de prueba y configura producto y tienda. A las 00:25, Device Hub muestra la acción con `Pros-atajo` y `Testshop`; se despliega la flecha azul de su resumen para mostrar `Quantity`, que Atajos presenta como parámetro opcional, y se deja visible el botón de ejecución. El propietario ejecuta el atajo y confirma: «lo ha colocado en borrador correctamente». Esta confirmación acredita el alta básica desde Atajos en el iPhone 14. No confirma por sí sola relanzamiento frío, conservación de otros datos, persistencia tras reiniciar, errores ni Siri.

El propietario aclara que la experiencia que esperaba es dar la orden a Siri AI. La edición manual de un atajo se está usando como prueba técnica; la utilidad del extra queda condicionada a que el recorrido por voz ahorre esfuerzo frente a abrir la app. La invocación mediante las frases explícitas del App Shortcut y la comprensión de una orden libre por Siri AI se validarán por separado.

### Siri tradicional: error inicial y recorrido en los tres estados confirmado

Después de instalar la corrección de frases, el propietario prueba Siri y comunica que ofrece activar los atajos para ayudar con la petición. Al aceptar, Siri responde que ha habido un error y no ha podido; en el tercer intento ya no muestra el diálogo. No se han observado preguntas de producto/tienda ni el diálogo de guardado. Este resultado no confirma que el consentimiento se haya aplicado, ni permite atribuir el error a `perform()`.

La consola Xcode de la sesión de app no contiene entradas coincidentes con intent/shortcut/Siri/error. La extracción nativa del registro del iPhone, restringida a SmartShoppingList desde las 00:50 con límite de 5 MB, falla con `Must be root to collect logs from attached device` (exit 77). No se elevan privilegios ni se obtiene un registro del sistema; la ausencia de errores en la consola de la app no demuestra su ausencia en Siri.

Como ajuste acotado se añade `ShoppingAppShortcuts.updateAppShortcutParameters()` en `SmartShoppingListApp.init`, después de registrar la dependencia. El [sample oficial de Apple](https://developer.apple.com/documentation/appintents/acceleratingappinteractionswithappintents/) utiliza este patrón de registro, también para frases estáticas. Xcode 27.1 compila sin warnings/errores y lanza la app actualizada en el iPhone 14 a las 01:01; la nueva consola tampoco muestra errores coincidentes. Log: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260927-010108.txt`.

Se propone revisar el permiso específico de la app. La ruta general de Apple Siri → Acceso a apps no coincide con lo que ve el propietario: encuentra `Excluded Apps`, cuya lista está vacía. No se cambia ningún ajuste ni se interpreta esa lista como prueba del consentimiento. Apple documenta [ajustes por aplicación](https://support.apple.com/guide/iphone/change-siri-settings-iphc28624b81abc/27/ios/27) y distingue el [consentimiento de App Shortcuts de la autorización antigua de SiriKit](https://developer.apple.com/forums/thread/840647); el caso del foro es watchOS y no demuestra la causa del fallo inicial en iPhone. No se añaden SiriKit, entitlements ni permisos antiguos por inferencia.

Con la versión actualizada se indica una única prueba: abrir SmartShoppingList, mantenerla en primer plano y, con el iPhone desbloqueado y fuera de Device Hub, invocar «Añade un producto en SmartShoppingList». El propietario responde: «Sí, ha funcionado». Se registra como confirmación del recorrido básico de Siri tradicional en ese escenario. No se atribuye de forma concluyente la recuperación a la llamada de actualización: el registro, el consentimiento y el estado de la app no se han aislado experimentalmente. Esta confirmación no acredita lanzamiento frío, teléfono bloqueado, segunda frase ni inglés, y no requiere repetir el mismo ensayo caliente.

Después el propietario prueba con la app en segundo plano y confirma: «La he puesto en segundo plano y ahora sí ha funcionado». Queda acreditada también la invocación sin tener la app en primer plano. No equivale a arrancar con el proceso terminado. No se repite el escenario ya confirmado ni se extiende a Siri AI, al segundo idioma o a un teléfono bloqueado.

Finalmente el propietario confirma: «Ahora lo ha hecho con la app cerrada, la ha abierto y lo ha puesto en el borrador». Se registra la ejecución por Siri con la app cerrada según el ensayo físico del propietario, apertura de la app y alta en el borrador. No se capturó una traza del ciclo de vida del proceso; la evidencia es su confirmación del recorrido real. Con ello quedan validados los tres estados ensayados y no se solicitan nuevas repeticiones del mismo recorrido.

### Ensayo escrito con Siri AI en Mac

El 27 de septiembre el propietario abre Siri AI en el Mac y autoriza probarlo. Se escribe `Add a product in SmartShoppingList`; Siri pregunta qué producto se quiere añadir. Tras responder `Prueba Siri Mac`, indica que necesita abrir la aplicación porque no puede añadir elementos directamente y muestra SmartShoppingList. No solicita tienda, no devuelve el diálogo del intent y no se observa ejecución de la acción. No se considera un alta ni una validación de Siri tradicional. La primera pregunta conversacional, por sí sola, tampoco demuestra que haya resuelto `AddDraftItemIntent`.

Este resultado es compatible con el rechazo de registro de `linkd` ya observado, pero la respuesta de Siri no identifica su causa: no se atribuye causalidad adicional. No se cambian idioma, región, certificados ni cachés para prolongar el ensayo.

## Siri tradicional ahora y ampliación con Siri AI

Acuerdo del 27 de septiembre: conservar el acceso sencillo para dispositivos sin Apple Intelligence y documentar una futura experiencia conversacional, sin duplicar la lógica del borrador.

| Vía | Experiencia prevista | Estado real |
| --- | --- | --- |
| Siri tradicional · borrador | Decir «Añade un producto en SmartShoppingList» o «Añade a mi borrador en SmartShoppingList», responder producto y tienda, revisar la fila en la app. En inglés: `Add a product in SmartShoppingList` o `Add to my draft in SmartShoppingList`. | Alta desde Atajos y recorrido básico por Siri con la app en primer plano, segundo plano y cerrada confirmados por el propietario en iPhone 14. En el último caso confirma apertura y producto añadido al borrador. |
| Siri tradicional · lista | Decir «Añade a mi lista de la compra en SmartShoppingList»; responder producto, cantidad y tienda; tienda exacta y única → alta y aviso; desconocida o ambigua → borrador. | Implementado y validado automáticamente; el propietario confirma y acepta el recorrido tras añadir la pregunta de cantidad. Variantes físicas pendientes delimitadas en este informe. |
| Siri AI | Entender variantes de una orden que incluya producto, tienda y cantidad, y preguntar cuando falten datos. | Ampliación pendiente. El ensayo escrito en el Mac termina ofreciendo abrir la app, sin ejecutar el intent. |

El App Shortcut está preparado para su invocación directa; no se pretende que cada persona tenga que construir un atajo manual para el uso habitual. En la acción original de borrador, la cantidad sigue siendo opcional y editable en Atajos. La nueva acción de lista la solicita como texto requerido separado. Extraer la cantidad de una respuesta que mezcla producto y unidades no está implementado ni prometido. Si este recorrido no ahorra esfuerzo o su reconocimiento requiere cambios amplios, se aplaza el extra y se prioriza la entrega.

El propietario advierte que el micrófono del iPhone no funciona mientras está conectado a Device Hub. Por tanto, la prueba de voz se hará tras desconectarlo; escribir a Siri, si está disponible, sólo acreditaría el reconocimiento de la orden escrita. No se registra un fallo del intent por ausencia de audio en esa conexión.

### Disponibilidad y diseño de la ampliación

La [guía de Apple sobre Siri AI](https://support.apple.com/en-us/127893), consultada el 27 de septiembre y publicada el 22, distingue su disponibilidad de la de Apple Intelligence: Siri AI sigue sin estar disponible en iOS/iPadOS/watchOS en la UE; sí se ofrece en macOS/visionOS con los requisitos indicados, incluido inglés en la guía pública. iPhone 11 y 14 quedan fuera del hardware admitido para Siri AI. Esa restricción no impide implementar App Shortcuts para Siri tradicional. En el Mac de la prueba, Siri muestra interfaz y respuesta en español; se conserva esa observación sin inferir soporte general del idioma ni cambiar ajustes.

La documentación de Apple sobre [acciones descubribles por Apple Intelligence](https://developer.apple.com/documentation/appintents/making-actions-and-content-discoverable-by-apple-intelligence) describe esquemas con semántica definida. No se ha identificado uno que modele claramente el alta de un producto con tienda y cantidad en este borrador. El cercano [`reminders.createReminder`](https://developer.apple.com/documentation/appintents/appschema/remindersintent/createreminder) representa recordatorios y no se adopta forzando estos datos en campos ajenos. Añadir parámetros opcionales a un esquema no garantiza que Siri AI los entienda: Apple limita esos parámetros adicionales a Atajos.

Trabajo futuro, después del MVP o mediante una nueva decisión de alcance:

1. Revalidar disponibilidad de Siri AI por dispositivo, sistema, idioma y región, y resolver primero el descubrimiento/registro de la app en el entorno de prueba.
2. Verificar un esquema adecuado y el soporte de acciones personalizadas. Mantener el identificador del intent actual y la alternativa de Siri tradicional; añadir un adaptador sólo si la integración lo requiere.
3. Reutilizar `addDraftItemFromIntent` o `addShoppingItemFromIntent` según la acción solicitada, con sus validaciones, autenticación y guardado. Exponer entidades/consultas únicamente si ayudan a resolver productos o tiendas reales. No crear un escritor, almacenamiento o envío al grupo alternativos.
4. Validar órdenes completas, datos omitidos, ambigüedades, correcciones y cantidades literales en ES/EN realmente disponibles. El éxito debe corresponder a datos guardados y revisables, con todos los valores conservados. Registrar explícitamente lo que el sistema no interprete.
5. Conservar las dos semánticas: borrador local, o petición explícita de añadir a una tienda existente con recuperación al borrador. Siri AI no amplía por sí sola el alcance a comprar, cancelar, crear tiendas ni publicar otras filas del borrador.

## Variantes físicas no acreditadas

1. Conservación explícita de otro texto y filas previas durante una invocación, así como presentación física de errores de ocupado, valores vacíos y límites. Los casos de persistencia y validación automatizados anteriores no se presentan como esta prueba del sistema.
2. Segunda frase española e invocación inglesa. Las traducciones y metadatos compilados no acreditan esos recorridos. La cantidad opcional se configura en Atajos; la frase libre «añade pan a Mercadona» no está prometida.
3. Dispositivo bloqueado y autenticación. El éxito con teléfono desbloqueado no sustituye esa prueba.

El descubrimiento, el alta básica desde Atajos y el recorrido básico de borrador por Siri en los tres estados están confirmados en iPhone 14. También se acepta el recorrido mejorado de lista tras incorporar la pregunta de cantidad. No se repiten esas pruebas. Las variantes anteriores permanecen identificadas para decidir su tratamiento al entregar la rama; esta evidencia no cierra por sí sola la issue #10 ni acredita Siri AI.
