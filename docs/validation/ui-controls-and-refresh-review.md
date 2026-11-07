# Controles y revisión de refrescos — 16 de octubre de 2026

Seguimiento: [issue #49](https://github.com/JFrancoG/SmartShoppingList/issues/49).

## Estado vigente — 7 de noviembre: correcciones de #49 para el siguiente build

El propietario autoriza corregir los tres hallazgos antes de preparar el siguiente build. Se trabaja
en `codex/issue-54-production-readiness`, partiendo de `3dd5237` y conservando los cambios de distribución
anteriores. El propietario autoriza después consolidar #54/#49, hacer commit/push y preparar el
siguiente Archive interno. La [entrega de 1.0 (5)](testflight-1.0-5.md) registra su resultado y límites.

- **Invitación:** cambiar grupo vuelve a consultar la invitación guardada. Cada respuesta se vincula
  a petición, cuenta, sesión e invitación; una respuesta antigua, incluso 401/410, no sustituye un
  enlace nuevo ni invalida otra sesión. El borrado confirmado conserva cualquier enlace entrante.
  La UI distingue acceso cerrado, consulta y recuperación.
- **Sin conexión:** Añadir/Comprar distinguen grupos no verificados de una cuenta sin grupos.
  Conservan borrador y acceso; sólo ofrecen crear/unirse con sesión cerrada o vacío verificado.
  Las tiendas también necesitan verificación antes del mensaje de primera lista, y no se presenta
  un botón de publicar con el destino vacío.
- **Refrescos y avisos:** activación, consulta Premium y actualización manual comparten la carga.
  Con sesión verificada, el foreground reconcilia Premium y después obtiene una sola instantánea
  de cuenta/listas. Si una acción impide actualizar, se reanuda al terminar. Un caller cancelado no
  cancela la carga compartida. Los errores de lectura son inline con Actualizar en Añadir, Comprar,
  Ajustes y Premium; una cancelación no genera error. Los avisos de mutación, recuperación de la
  misma operación y sesión inválida conservan sus reglas. La recuperación explícita de compras
  distingue un GET previo fallido de una verificación realmente intentada.

El diagnóstico local registra disparador, método y plantilla de ruta, etapa, status/código de
transporte y presencia booleana de pendiente. No registra tokens, JWS, cuerpos, contenido de listas,
URLs completas ni identificadores de recursos. No identifica retrospectivamente la petición que
falló en el iPhone 16 con 1.0 (4); ese desencadenante histórico sigue sin medirse.

### Validación local

- Xcode MCP, **Xcode 27.1 (27A9274), SDK 27.1**, SmartShoppingList, iPhone 17 Simulator **iOS 27.0**:
  compilación de app y tests correcta, **0 errores y 0 warnings** en el log completo.
- **Fast: 481 ejecuciones correctas, 0 fallos, 0 omitidas.** La herramienta enumera aparte 14 tests
  sin resultado, fuera de la selección Fast; no se presentan como ejecutados. La consolidación posterior
  repite Fast y añade 21 ejecuciones Integration correctas; no cambia el servidor.
- Una pasada intermedia se detuvo por un fixture nuevo sin selección explícita de grupo: se corrigió
  el setup y se mantuvieron las expectativas. La pasada completa posterior supera todos los casos.
  La selección focalizada MCP rechazaba los tests etiquetados como deshabilitados; RunAllTests sí
  ejecutó la selección Fast sin modificar el plan.
- Regresiones: respuesta tardía/descartada y sesión sustituida, enlace entrante durante borrado,
  lectura offline y recuperación, sesión inválida, cancelación, consulta de tienda/Premium, espera
  compartida, activación diferida, aviso de mutación conservado y privacidad de las trazas. También
  pasan las recuperaciones idempotentes previas.
- Previews offline ES de Añadir y Comprar: Large y AX5; Comprar también XXX Large. Render real en
  iPhone 18 Pro Max / iOS 27.2, distinto del destino de tests elegido por el servicio de previews.
  Texto visible sin solapamientos; AX5 sólo acredita el viewport, no desplazamiento ni VoiceOver.
  Los estados nuevos de consulta/error de invitación tienen revisión estática, sin ensayo físico.
- Revisión independiente de concurrencia, SwiftUI/localización y estilo sin hallazgos pendientes;
  catálogo válido, diff-check correcto. Se conservan las modificaciones previas ajenas a #49.

Evidencia local de ejecución:
`/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/D1136A47-9CB4-4C13-A63B-EF4F518A7AE0.txt`.
Log de compilación:
`/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20261107-131757.txt`.

### Próxima aceptación física, sólo en el nuevo build

1. Con una invitación pendiente de prueba, cambiar grupo activo y comprobar que vuelve su vista
   previa sin Actualizar; no repetir la incorporación y sincronización ya aceptadas para probar esto.
2. Arrancar sin red: no sugerir crear/unirse por el fallo de consulta; recuperar Internet y comprobar
   la misma cuenta, grupo, tienda y productos, con el borrador conservado.
3. Volver varias veces desde segundo plano en Añadir, Comprar y Premium: sin modal de envío incierto
   por una lectura. Con un fallo de red, mostrar recuperación inline; después, cargar correctamente.
   Comprobar los controles modificados con texto grande y VoiceOver sin repetir la matriz anterior.

**#49 continúa abierta** hasta esa confirmación física y su entrega en main. El siguiente build se
asocia al commit publicado de la rama; no se repiten las compras ni los recorridos ya aceptados.

## Antecedente — 30 de octubre: aviso de envío al volver a primer plano

Durante la aceptación de **TestFlight comercial 1.0 (4)** de #54 en **iPhone 16**, el propietario informa
que cada retorno desde segundo plano presenta una alerta «Smart List / Aceptar» con el texto:

> No se ha podido confirmar el resultado. Conservamos el envío original para reintentarlo sin duplicar productos.

La captura de las **12:51** muestra el aviso sobre Premium activo con fin de periodo a las 13:03;
esa hora pertenece a la captura anterior a la renovación comprobada posteriormente, no acredita un
estado actual de Premium ni demuestra un error de compra. Se conserva el original sin editar en
[evidencia local](evidence/issue-49-foreground-submission-warning-testflight-1.0-4.png), SHA-256
`5cff8642c5a1ba28e8453b086f322eca4359b3d15318c845c607413bf67d8a65`.

**Hechos de fuente contrastados, sin cambio Swift:**

- `SharedErrorMessage.message(for:)` usa ese texto para `.transport` y `.invalidResponse` sin conocer
  método HTTP, ruta ni `pendingOperation`. Una consulta de lectura puede mostrarlo sin envío pendiente.
- `SharedRootView` llama `refresh()` y después `loadPremium()` al entrar en `.active`.
  Si Premium obtiene autoridad, `loadPremium()` vuelve a ejecutar `refreshSessionAndLists()` aunque
  no haya una nueva compra. Hay dos refrescos completos en serie; no se da por probada concurrencia de red.
- `refreshSessionAndLists()` y `loadActiveGroup()` consultan usuario, grupos, administración, capacidad,
  tiendas y productos. Sus errores pasan por `handle(error)` al mismo mensaje de envío incierto.
- El host conserva la instantánea de una alerta presentada: que una carga posterior ponga `notice=nil`
  no equivale a retirar la alerta que ya se está mostrando. Un primer fallo seguido de un segundo
  refresco correcto es una hipótesis compatible, no la causa física medida.
- `SharedHTTPAPI.exchange` propaga `CancellationError` y `URLError.cancelled` como cancelación;
  no los convierte en `.transport`. No se atribuye esta alerta exacta a cancelación pura. Los errores
  de transporte no cancelados y validaciones de respuesta/contrato siguen siendo candidatos distintos.

**Decisión de alcance:** registrar y priorizar en #49 la reproducción instrumentada y corrección antes
del siguiente build comercial de validación de #54. La compra, renovación, V2 y pruebas funcionales
anteriores conservan su evidencia; este síntoma no justifica reparar compras ni borrar la cola local.
No se modifica código ni se oculta globalmente la alerta a partir de una captura.

**Diagnóstico y aceptación pendientes:** identificar ruta/método, error subyacente y número de consultas
por ciclo background/foreground sin registrar tokens, JWS o contenido privado; distinguir fallo de GET
de mutación con resultado incierto y comprobar si existe realmente una operación persistida. Separar
los mensajes y coordinar las cargas equivalentes según la causa. Validar retornos repetidos sin aviso
espurio, feedback fiel ante GET fallido/offline, conservación de sesión/grupo y autoridad, y reintento
de mutación incierta con el mismo identificador/cuerpo y sin duplicados. La validación física del arreglo
en TestFlight sigue pendiente. En este registro sólo se revisa fuente, conserva evidencia y sincroniza
el seguimiento; no se ejecutan builds ni suites nuevas.

### Decisión de alcance tras valorar un arreglo inmediato

El propietario permite corregir ahora si es pequeño o resolverlo junto a los refrescos excesivos.
La revisión adicional mantiene la segunda opción: no se ha encontrado una incompatibilidad determinista
de DTO/contrato que explique el fallo físico. Una prueba local de GET fallido sin operación pendiente
demostraría el texto incorrecto, pero no identificaría la consulta real que falla en el teléfono.
Cambiar sólo el texto mantendría la alerta recurrente. Silenciarla en refrescos automáticos dejaría sin
feedback transversal a Premium/Añadir y al estado sin tienda seleccionada; el feedback inline existente
no cubre esos contextos. No se aplica ese cambio como supuesto arreglo.

La unidad de #49 abordará conjuntamente coordinación de refresco, distinción entre actualización
automática/acción manual/mutación incierta y feedback de lectura en todas las pantallas, preservando
identidad de alertas relevantes y recuperación idempotente. Permanece priorizada antes del siguiente
build comercial. Esta decisión no requiere otra compra ni modificar o borrar el estado del teléfono.

## 7 de noviembre — invitación pendiente sin vista previa al cambiar grupo

Durante #54, **TestFlight 1.0 (4), iPhone 11**, el propietario cierra y abandona A·2 para liberar una
de las cinco plazas Premium y selecciona B como grupo activo. La invitación pendiente a Test1 conserva
Descartar habilitado, pero desaparece Aceptar y aparece «Accede y actualiza para consultar el grupo
antes de aceptar».

La fuente identifica el hueco: `SharedShoppingViewModel.selectGroup` llama a `clearGroupPresentation`,
que borra `invitationPreview` sin borrar `pendingInvitation`; a continuación llama a `loadActiveGroup`
sin consultar otra vez la invitación. `SharedPendingInvitationSection` usa ese texto también cuando
hay sesión y sólo falta la vista previa. La salida del grupo sí intenta el refresco completo; elegir B
después puede volver a borrar la información recién consultada.

Un único **Actualizar en Ajustes** recorre `refreshSessionAndLists` → `previewPendingInvitation`.
El propietario confirma que reaparecen **Test1 + Aceptar invitación**. Se conserva esta recuperación
física como evidencia. A continuación confirma aceptación de Test1 y lectura de Aldi, Alpro y otros
dos productos en el iPhone 11, según el [registro de #54](issue-54-distribution-environments.md#7-de-noviembre--invitación-aceptada-y-lista-compartida-visible-en-el-iphone-11).
Después confirma también el alta desde el 11 visible una vez en el 16 y la compra confirmada desde
el 16 reflejada en el 11, conservando Alpro y los otros dos productos. La recuperación manual no
equivale a una corrección del defecto.

**Corrección pendiente:** revalidar la invitación conservada tras cambiar el grupo activo, con las
barreras de cuenta, identidad de invitación y respuesta tardía correspondientes, y distinguir falta
de sesión de carga/error de vista previa. No basta tratar este estado como límite comercial o pedir
otra compra. En la futura validación del cambio se comprobará que seleccionar otro grupo mantiene o
recupera la invitación sin exigir el refresco manual y que los fallos/caducidad tienen feedback fiel.
No se cambia Swift ni se ejecutan builds o suites en este registro.

## 7 de noviembre — ausencia de grupos no verificada durante el arranque sin red

En el ensayo de **TestFlight 1.0 (4), iPhone 11**, el propietario confirma que todavía está sin
conexión cuando Comprar pide configurar un grupo y Añadir propone unirse o crear uno, indicando
que los productos se guardan localmente hasta tener un grupo. Acaba de aceptar Test1 y comprobar
la sincronización con el iPhone 16; el mensaje offline no acredita que haya perdido sus pertenencias.

`SharedGroupView` presenta ese estado si `hasLoaded && !isBusy && groups.isEmpty`; `AddItemsView`
lo hace si `group == nil && groups.isEmpty`. Ninguno exige `groupsAreVerified` para interpretar el
vacío como ausencia de pertenencias. El arranque restaura la sesión y luego consulta usuario/grupos;
un error de transporte puede dejar esa colección sin cargar. No se atribuye a cierre de sesión sin
comprobar el resultado al recuperar conexión.

**Corrección pendiente:** diferenciar grupo inexistente, carga y verificación fallida/sin red, con
feedback que permita actualizar sin sugerir crear otra cuenta o grupo. Conservar las barreras de
autoridad para escrituras. El propietario confirma después recuperación automática al volver a
conectar, sin Actualizar manual ni avisos: Datos de prueba/Test1 y, al elegir Aldi, Alpro con los otros
dos productos. El [registro de #54](issue-54-distribution-environments.md#7-de-noviembre--recuperación-automática-tras-el-arranque-sin-red-confirmada)
conserva esa aceptación y sus límites; no mide el disparador exacto del refresco. El mensaje offline
sigue pendiente de corrección. No se cambia Swift ni se declara un arreglo validado.

## Implementación y validación

- Gestionar suscripción: nombre breve, sin tarjeta ni encabezado redundante.
- Mínimo táctil común de 44 puntos en `ShoppingControlMetrics`, conservando crecimiento vertical y controles nativos.
- Archivar desde la lista de una tienda sin pendientes, solo para el administrador: confirmación, revalidación
  de cuenta/grupo/selección, capacidad actual y operación idempotente existente. No borra historial ni borrador.
  No añade cargas de red al render; comprueba autoridad al confirmar. Comprados/cancelados no impiden archivar.

Build final Simulator: PASS, 4,552 s, sin warnings/errores. Fast: 232 funciones / 405 ejecuciones,
cero fallos, omitidas o runtime warnings. Tres casos nuevos prueban archivo correcto, ocupación concurrente y
cambio de administrador. Previews ES Large/XXXL/AX5 de gestión y archivo renderizadas e inspeccionadas.
Revisión independiente sin hallazgos funcionales; dos ajustes de estilo corregidos.
No se acredita recorrido físico de archivo ni VoiceOver. Actualización 12:50 CEST: Xcode compiló (6,722 s, sin warnings) e instaló/abrió la versión Debug
en el iPhone 11, proceso 1471, conservando datos. El Info.plist confirma ambos orígenes Sandbox.
El titular revisará botones y archivo desde la tienda. Sin entrega Git todavía.

## Refrescos y avisos: diagnóstico inicial, implementación pendiente

Actualización visual 13:02 CEST: secundaria habilitada con contorno de 2 puntos y texto primary;
deshabilitada con relleno apagado sin contorno. Archivo usa primary. Carga y estado vacío sin fondo de fila.
Previews inspeccionadas en claro, oscuro, contraste aumentado y XXXL; AX5 revisada en la zona visible,
sin acreditar el recorrido completo ni VoiceOver físico. Validador de diseño: 64 pares en cuatro modos,
21 assets en cuatro variantes, PASS. Build físico sin warnings/errores; instalada y abierta en iPhone 11
(proceso 1483). Se conserva el mínimo de 44 puntos. No se repitió Fast para este ajuste solo visual.


Hipótesis obtenidas de código, todavía sin una reproducción medida por pantalla:

- `SharedRootView` refresca sesión/listas y después Premium al volver a `.active`; la carga Premium que
  obtiene autoridad puede volver a refrescar sesión/listas. También carga al verificar sesión y abrir Premium.
- Las actualizaciones StoreKit aceptadas refrescan toda la sesión/lista. Las renovaciones rápidas de Sandbox
  pueden intensificar el problema, pero no prueban que todos los refrescos sean redundantes.
- `refreshSelectedStore` vacía `items` antes de recibir la respuesta; `refreshSessionAndLists` invalida
  identidad cargada y muestra loading. Separar revalidación de autoridad de presentación puede reducir parpadeo.
- Los avisos de operación confirmada y de selección reconciliada tienen causas distintas. Registrar texto,
  disparador y acción del usuario antes de deduplicar. No suprimir globalmente errores ni avisos de conflicto.

Orden de revisión propuesto: Premium (retorno de hojas Apple y renovaciones), Compra (refresco sin cambios,
compra/cancelación y archivo), Ajustes/Grupo gratuito, Añadir y borradores. Medir peticiones y estados visibles
en cada recorrido; agrupar cargas concurrentes equivalentes, conservar contenido durante revalidación y
reservar alertas modales para decisiones/errores que requieren acción. Mantener barreras de sesión/grupo,
idempotencia y restricciones mientras se desconoce la autoridad. Validar offline y cambios desde otro dispositivo.

## Reembolso #39

Consulta directa de Apple Sandbox a las 12:41 CEST: último periodo 12:25:08–12:30:08, estado expired,
auto-renovación desactivada, sin fecha de revocación. Historial de reembolsos vacío (`hasMore=false`).
Historial de notificaciones desde 12:15 devuelve DID_RENEW, DID_RENEW y EXPIRED; no REFUND ni REFUND_DECLINED.
No prueba un fallo del webhook de Railway ni confirma el reembolso. Mantener #39 abierta y revisar el recorrido
de la solicitud antes de repetir compras o confundir expiración con revocación.

## Alertas nativas comunes — revisión del 16 de octubre

- Decisión del titular: conservar alertas nativas; acción principal verde oscuro y texto blanco, Cancelar
  secundario y operaciones destructivas con su rol. Alineación del título y foco controlados por iOS.
- `ShoppingAlertActions` unifica uno/dos botones. `shoppingAlert` comparte el host nativo sin tintes
  heredados de Form o NavigationStack. Se mantienen identidad, instantáneas y guardas de reconocimiento.
- Título genérico «Smart List» en español/inglés, conservando títulos específicos.
- `NativeAccent` y `OnNativeAccent`: en la primera revisión el par sólido era 6,63:1 normal y 10,03:1 HC; el ajuste final de matiz se registra abajo. El contenido conserva
  `AppPrimary`: tintes locales en Picker/botones y selección de pestañas con UITabBarAppearance.
- Simulador iPhone 17 / iOS 27.2: archivo/cancelación en claro y oscuro, aviso único, confirmación
  destructiva y sustitución de un aviso mientras el anterior permanece abierto. Al cerrar el anterior
  se presenta el siguiente con el título nuevo. XXXL + contraste aumentado: acción legible y accesible.
- Navegación Atrás y toolbars mantienen sus controles nativos. Selección de grupo y pestañas revisadas
  en oscuro: tinta clara. Las cápsulas propias mantienen fondo claro y texto oscuro.
- Build Simulator sin errores ni warnings; verificador de diseño PASS, 65 pares × 4 modos y
  23 assets × 4 variantes. Revisión independiente sin hallazgos materiales pendientes.
- AX5 inspeccionado parcialmente: el contenido largo necesita desplazamiento nativo; no se acredita
  recorrido completo ni VoiceOver físico. No se han ejecutado nuevas compras ni operaciones de servidor.
  #39 continúa abierta. Estas comprobaciones no sustituyen la revisión en el iPhone físico.

- Revisión final: se descartó `UIView.appearance().tintColor` porque no admite el proxy de apariencia. `ShoppingWindowAccent` fija el color en la ventana real de cada escena desde `didMoveToWindow`. Compilación final sin errores y comprobación runtime de alerta nativa con verde oscuro y texto blanco, también con contraste aumentado y texto XXXL.

## Ajuste de etiquetas y matiz nativo (16 de octubre)

- Las confirmaciones de tiendas usan «Archivar»/«Restaurar»; los títulos y las acciones de entrada siguen identificando la tienda. Traducciones ES añadidas.
- NativeAccent deriva del primary Dark: #437C5A normal, #345F45 alto contraste. Blanco: 4,92:1 y 7,32:1. Color opaco, independiente del fondo.
- Build de simulador: PASS sin warnings. Validador: 65 pares × 4 modos, 23 assets × 4 variantes, PASS. Revisión independiente sin hallazgos.
- No se fuerza orientación de acciones: pertenece a la alerta nativa. No se ha confirmado visualmente la disposición de estas etiquetas nuevas: RocketSim dejó de responder y se cancelaron las consultas. Pendiente revisión física de este ajuste; no se ha reinstalado en iPhone en este paso.

## Aceptación física y preparación de entrega

El 16 de octubre el propietario confirma que los avisos y colores se ven bien en el iPhone 11, después de instalar y abrir la compilación Sandbox con las etiquetas cortas y el matiz definitivo (PID 1567; RunProject-Log-20261016-163802.txt). Build físico sin warnings. «Restaurar» es la confirmación de gestión de tiendas, no una acción dentro de una tienda archivada. No se acredita por esta aceptación una disposición horizontal concreta ni el recorrido completo de VoiceOver.

Autoriza commit, push, PR, CI, merge y eliminación de rama. #39 permanece abierta hasta completar Sandbox. #49 conserva pendiente la revisión por pantalla de refrescos/avisos redundantes; esta unidad no cambia esos disparadores. Se entrega también la herramienta de solicitud de reembolso Debug/Sandbox ya probada, sin afirmar decisión de Apple. El cambio previo del propietario al nombre visible de Release queda fuera del commit.

Auditoría independiente de 40 archivos Swift: sin hallazgos funcionales; corregidos dos ajustes de disposición de código antes de la validación final.

Validación final de entrega: plan Fast repetido el 16 de octubre a las 16:43 CEST en iPhone 17/iOS 27.2 Simulator: **232 funciones / 405 ejecuciones**, cero fallos, omitidas, fallos esperados o runtime warnings. Las 13 entradas de otros planes que MCP muestra sin resultado no son pruebas ejecutadas. Build de tests sin warnings. Resultado: `Test-SmartShoppingList-2026.10.16_16-43-03-+0200.xcresult`. Verificador de diseño: 65 pares × 4 modos, 23 assets × 4 variantes, PASS. Auditoría final de estilo: 40 Swift, cero hallazgos pendientes.

## Etiqueta de reconocimiento — 17 de octubre

- Avisos informativos comunes de una acción: «Aceptar» (`OK`); cuando se ofrece «Abrir lista», la alternativa es «Cerrar». Se mantienen roles nativos, identidad, descarte, tamaños y colores.
- Compilación iOS correcta, sin warnings, a las 10:17 CEST. Catálogo JSON válido y diff sin errores de espacios. Revisión independiente de localización, semántica y estilo: sin hallazgos.
- Preview de aviso único muestra «Aceptar». Las variantes solicitadas no acreditan por sí solas Dynamic Type: AX5 produjo una captura sin alerta; XXXL mostró la etiqueta pero no permite confirmar que el tamaño se aplicase al diálogo nativo. El preview aislado tampoco reproduce el tinte de la ventana de la app. Sin nueva validación física ni VoiceOver.
- Cambio local en `codex/issue-49-notice-acknowledgement`, sin commit ni instalación. Se elimina del diff el reordenado automático ajeno de Xcode del catálogo. Sin cambios al comportamiento del reembolso.

## Instalación de «Aceptar» — 17 de octubre, 10:25 CEST

Instalada y abierta la compilación Debug/Sandbox actualizada en iPhone 11 (iOS 27.2), mediante Xcode MCP con esquema SmartShoppingList y SDK 27.1. RunProject correcto, PID 2177, sin warnings ni errores en el log completo `RunProject-Log-20261017-102549.txt`. Backend configurado a Sandbox; pendiente aceptación visual del propietario. El catálogo conserva únicamente el cambio de etiquetas tras retirar el reordenado automático de Xcode.


## Aceptación y preparación de entrega — 19 de octubre

El propietario confirmó que «Aceptar» se ve correctamente en el iPhone 11. Se entrega junto a la corrección
del primer intento de reembolso, probada físicamente a las 05:15 CEST; evidencia de StoreKit en
`issue-39-premium-subscriptions.md`. Auditoría final de los siete Swift modificados/nuevos sin hallazgos;
el único candidato del escáner pertenece a código anterior. Se reutilizan Fast (233 funciones / 407 ejecuciones)
y la instalación/compilación sin warnings de las 05:11, sin cambios de código posteriores. Validador de diseño:
65 pares × 4 modos y 23 assets × 4 variantes, PASS. #39 y #49 permanecen abiertas para sus pruebas y seguimiento.
