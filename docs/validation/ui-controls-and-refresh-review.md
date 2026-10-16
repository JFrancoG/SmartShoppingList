# Controles y revisión de refrescos — 16 de octubre de 2026

Seguimiento: [issue #49](https://github.com/JFrancoG/SmartShoppingList/issues/49).

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
