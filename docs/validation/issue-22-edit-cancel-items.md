# Edición y cancelación segura de pendientes · #22

Estado del 25 de septiembre de 2026: implementación `db32534` publicada en `codex/issue-22-edit-cancel-items`, desplegada en Railway e instalada en ambos iPhone. Edición y cancelación entre dispositivos confirmadas por el responsable. El ensayo detectó avisos redundantes y una alerta vacía; corrección iOS y evidencia descritas abajo. La issue permanece abierta; esto no constituye el cierre completo del MVP.

## Alcance comprobado

- Rutas reales PATCH edición y POST cancelación, autenticación por grupo, control de versión y transición `pending`.
- Edición de nombre/cantidad/tienda; cancelación persistida sin borrar ni inventar comprador/fecha de compra. Identidad, creador y fecha de alta conservados.
- Replay exacto; otra intención con la misma clave rechazada; autorización actual antes de replay. Rollback de producto, tienda nueva y recibo ante un fallo SQL posterior a la resolución de tienda.
- Cuatro carreras controladas en PostgreSQL: edición/compra y cancelación/compra, con ambos órdenes de llegada bloqueados y observados antes de liberar. Gana la primera transición; nunca hay compra parcial ni se sobrescribe el estado terminal.
- Cliente HTTP rechaza respuesta de versión incorrecta. La cantidad nula se transmite explícitamente.
- ViewModel conserva la propuesta y el sobre ante pérdida de respuesta simulada después del commit del servicio de prueba; reapertura y reintento usan la misma intención. Un 409 exige revisión antes de una nueva clave. Éxito seguido de fallo de refresco se anuncia sin habilitar una lista obsoleta. Los checks conservan las versiones elegidas.
- Keychain real aislado por servicio de prueba: reapertura conserva exactamente edición (incluida tienda nueva y cantidad nula) y cancelación, incluso tras quitar la sesión.

Los tests ejecutan rutas/servicios o ViewModel/cliente/persistencia de producción según su frontera. No utilizan cuentas Apple ni datos alojados reales. No se acredita TDD rojo-verde: los primeros tests de rutas se incorporaron junto a la implementación y se ejecutaron después.

## Ejecución

Xcode MCP Service 27.0; macOS 27.2. Servidor en My Mac con PostgreSQL `db-test` local aislado (5433). iOS en iPhone 17 Simulator, iOS 27.2. Builds para pruebas correctos, sin diagnósticos Swift propios; aparece el warning aceptado EXC-002 de extracción de App Intents. No se han alterado dependencias, targets, migraciones ni excepciones.

| Validación | Resultado |
|---|---|
| Servidor, 12:17 | 123 ejecuciones aprobadas; 0 fallos |
| iOS Fast final, 12:29 | 88 funciones / 151 ejecuciones aprobadas; 0 fallos |
| iOS Integration, 12:23 | 6 funciones / 9 ejecuciones aprobadas; 0 fallos |

Los elementos “not run” del resumen MCP pertenecen a otros tags o al test de plantilla. Los resultados nativos verifican los planes ejecutados. Incidencia de herramienta: `XcodeSwitchTestPlan` anunciaba Integration, pero la primera ejecución seguía usando Fast. Se seleccionó temporalmente Integration como plan por defecto del esquema, se reabrió el workspace y se ejecutó mediante MCP. Después se restauró el esquema original byte a byte. La copia de `.xcresult` de esa ejecución que devuelve MCP carece de `Info.plist`; se verificó el bundle cerrado original en DerivedData. No se han cambiado filtros para simular cobertura.

Evidencia local:

- Servidor: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/Test-SmartShoppingListServer-2026.09.25_12-17-34-+0200.xcresult`.
- Fast: `/Users/jesusf/Library/Developer/Xcode/DerivedData/SmartShoppingList-cnedcbvxlssppmejeutmxomopscm/Logs/Test/Test-SmartShoppingList-2026.09.25_12-29-49-+0200.xcresult`.
- Integration: `/Users/jesusf/Library/Developer/Xcode/DerivedData/SmartShoppingList-cnedcbvxlssppmejeutmxomopscm/Logs/Test/Test-SmartShoppingList-2026.09.25_12-23-50-+0200.xcresult`.
- Logs build: `BuildProject-Log-20260925-122929.txt` (servidor) y `BuildProject-Log-20260925-122923.txt` (iOS), en `ActionArtifacts/default/BuildProject` del mismo directorio temporal.

## UI y revisión

Editor y acción de cancelación con textos ES/EN, controles nativos y confirmación destructiva explícita; deslizar el producto sin permitir full swipe o abrir su menú contextual. Vista de editor con preview usando el trait aislado existente. Preview ES normal y AX5 inspeccionadas; se corrigieron campos de una línea con `axis: .vertical` y título inline. En AX5 el valor del selector nativo de tienda se abrevia visualmente; el selector permite abrir las opciones completas. Esto no acredita VoiceOver ni el foco tras cerrar.

Revisiones independientes de arquitectura/contrato y SwiftUI/accesibilidad: se corrigieron la serialización del fixture, mensajes que confundían carga/fallo con ausencia, diagnóstico visible de validación y validación indebida de un campo de tienda oculto. Las regresiones de campo oculto y límite de escalares tras NFC pasan en Fast. Las revisiones finales no mantienen hallazgos abiertos. Revisión de estilo limitada al diff, sin reformatear código histórico.

## Ensayo físico y corrección de avisos

iPhone 11 = A; iPhone 14 = B, con dos cuentas del mismo grupo. Baseline instalado: `db32534`; Railway activo `089d0da8-422a-40bc-9d6a-646fd466c2c3` con ese mismo SHA y healthcheck correcto a las 12:43 CEST. Ambos teléfonos en inglés. Usar dos o tres productos de prueba identificables, sin resetear el grupo ni datos existentes.

1. **Confirmado por el responsable:** A y B abren Comprar, eligen la misma tienda y refrescan. A marca un producto sin finalizar.
2. **Confirmado por el responsable:** B desliza ese producto, pulsa Editar, cambia nombre/cantidad y guarda. A refresca: ve el cambio y debe revisar/desmarcar su selección antigua antes de finalizar.
3. **Confirmado por el responsable:** Con otro producto marcado previamente en A, B abre «Ya no lo necesitamos». Primero cierra el popover tocando fuera (en esa presentación nativa no aparece «Keep product»): la fila sigue pendiente. Después confirma: desaparece de pendientes en B; al refrescar A tampoco aparece ni puede comprarse con el check antiguo.
4. Conflicto real sin refresco: ambos cargan otro producto; A mantiene su edición abierta, B lo compra. A intenta guardar: recibe conflicto, conserva su propuesta y no reabre ni sobrescribe el producto comprado.
5. Cambiar un pendiente a otra tienda; refrescar ambas tiendas en el otro teléfono y comprobar que aparece una sola vez en la nueva. Vaciar cantidad debe eliminarla, sin cambiar identidad.
6. Comprobación focalizada de accesibilidad: activar Editar y la confirmación, corregir un campo inválido, cerrar y recuperar el foco; comprobar que check y cancelación no se confunden. No se repite la matriz amplia antes de aplicar el design system.

Pendiente adicional: persistencia tras reinicio local controlado del proceso del servidor. La pérdida de respuesta ya tiene prueba automatizada posterior al commit; cortar la red en un teléfono no demuestra por sí solo ese instante. No reiniciar producción para esta comprobación ni repetir el ensayo offline ya acreditado por #17 sin una regresión concreta.

La consulta de tienda por voz sigue como siguiente unidad obligatoria. App Intents #10 conserva su carácter opcional. Esta issue no cierra el MVP.


### Incidencia de avisos · 25 de septiembre

En iPhone 11, una edición confirmada mostraba éxito, alerta vacía con OK y selección antigua. En iPhone 14, la compra posterior encontraba conflicto y encadenaba alerta vacía y selección antigua, además del bloque inline. El responsable confirma que los datos y el bloqueo son correctos. Este orden acredita edición antes de compra; el caso 4, compra antes de guardar la edición abierta, sigue pendiente.

Corrección: snapshot de alerta conservado durante el cierre; sin confirmación modal de éxito normal de edición/cancelación/compra; sin fallback modal de selección. Se conserva un único aviso de conflicto y la recuperación en pantalla. Un refresh explícito solo avisa al descubrir una selección antigua nueva y si no existe otro error. Los fallos de red, el resultado incierto y el éxito con refresco fallido conservan su aviso.

Regresión rojo-verde: las dos variantes nuevas (editar/cancelar) fallaron a las 13:26 por exigir un OK después del éxito. Tras el cambio, Fast a las 13:33:39 pasa 89 funciones / 153 ejecuciones, cero fallos. También verifica éxito de compra sin aviso, y que refrescar de nuevo una selección ya obsoleta no repite el aviso. EXC-002 continúa siendo el único warning observado. Backend e Integration reutilizan la evidencia anterior: esta corrección no cambia esas fronteras.

Resultado Fast: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/Test-SmartShoppingList-2026.09.25_13-33-39-+0200.xcresult`.

La validación del presentador utiliza un fixture DEBUG aislado, sin credenciales ni red. El recorrido corregido entre ambos teléfonos y VoiceOver siguen pendientes de confirmación física.


Fixture final EN en iPhone 17 Simulator/iOS 27.2: 3/3 escenarios correctos, sin alerta vacía. El primer aviso conserva su contenido hasta cerrarlo y entonces aparece el segundo; ocultar/restaurar conserva el aviso sin reconocerlo. Capturas y jerarquías en `ActionArtifacts/default/DeviceInteractionSynthesize/`, prefijo `Verify Notice Dismissal-`: reemplazo `13_34_18_560`, `13_34_38_266`, `13_34_54_490`, `13_35_06_415`; almacenamiento `13_35_29_020`, `13_35_42_390`; ocultación/restauración `13_36_49_166`, `13_37_07_966`, `13_37_21_432`, `13_37_37_482`. La sesión se cerró al terminar. Revisión independiente del diff final sin hallazgos; no acredita lectura ni retorno de foco con VoiceOver.

Cliente corregido instalado y arrancado en iPhone 11 a las 13:38 mediante RunProject, PID 3775. Instalación del iPhone 14 y SHA final se registran en la issue tras completarse. Backend sin cambios: permanece desplegado `db32534`.


### Ajuste final del ensayo · deselección automática

El 25 de septiembre, tras confirmar que solo aparece una alerta, el responsable considera confuso tener que pulsar «Deselect changed products» y autoriza desmarcar automáticamente los afectados con un aviso para volver a marcarlos si aún los quiere. Este criterio sustituye la revisión manual obligatoria documentada en los ensayos anteriores.

Después de una carga válida (refresh o regreso a tienda), solo se conservan checks cuyo ID y versión siguen pendientes en esa tienda/grupo. Se informa de las retiradas una vez, sin bloque persistente ni botón adicional. Un conflicto definitivo refresca y concilia sin enviar otra compra; una operación incierta conserva sobre y selección original. Un fallo de carga no concilia. Cambiar un check sigue sin escribir en el servidor.

Regresión: cuatro ejecuciones fallan antes del cambio (refresh, regreso a tienda, conflicto y desaparición); Fast de 15:48:45 pasa 156 ejecuciones, cero fallos. Comprueba reelección con versión actual, conservación de checks ajenos al cambio, ausencia de reenvío automático y reintento exacto tras refresh de una operación incierta. Se mantienen las regresiones de carga fallida. Resultado nativo: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/Test-SmartShoppingList-2026.09.25_15-48-45-+0200.xcresult`.

Pendiente de confirmación física de este último ajuste: marcar dos productos; editar uno desde el otro teléfono; refrescar. Debe quedar marcado solo el que no cambió, aparecer un aviso sin bloque persistente, y poder volver a marcar el editado. El presentador de alertas no cambia; se reutiliza su comprobación visual anterior. Instalación y SHA final se registran en #22. Backend sin cambios.


Fast final tras revisión: 91 funciones / 157 ejecuciones PASS, cero fallos, a las 15:51:52; incluye pérdida de tienda durante conciliación del conflicto sin silenciar el aviso. Resultado nativo con sufijo `Test-SmartShoppingList-2026.09.25_15-51-52-+0200.xcresult` en el mismo directorio de evidencia. Revisión independiente de contrato/UI/estilo completada, hallazgos corregidos. EXC-002 es el único warning observado.

Instalación corregida completada mediante Xcode MCP RunProject: iPhone 11 a las 15:52:18, PID 3809; iPhone 14 a las 15:52:32, PID 7098. Ambos arranques correctos; destino iPhone 11 restaurado. No se reinstala desde cero ni se borran datos. Esta instalación no acredita el ensayo manual pendiente descrito arriba.
