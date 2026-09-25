# Edición y cancelación segura de pendientes · #22

Estado del 25 de septiembre de 2026: implementación validada localmente en `codex/issue-22-edit-cancel-items`, sobre `6e7a246`. El responsable ha autorizado commit, push, despliegue e instalación en ambos iPhone; activación en curso. La evidencia de despliegue e instalación se registrará en la issue #22. El ensayo físico y el cierre de la issue siguen pendientes; esta evidencia no constituye el cierre completo del MVP.

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

## Ensayo físico pendiente

iPhone 11 = A; iPhone 14 = B, con dos cuentas del mismo grupo. Registrar versión/commit y despliegue reales antes de empezar. Usar dos o tres productos de prueba identificables, sin resetear el grupo ni datos existentes.

1. A y B abren Comprar, eligen la misma tienda y refrescan. A marca un producto sin finalizar.
2. B desliza ese producto, pulsa Editar, cambia nombre/cantidad y guarda. A refresca: ve el cambio y debe revisar/desmarcar su selección antigua antes de finalizar.
3. Con otro producto marcado previamente en A, B abre «Ya no lo necesitamos». Primero cancela el diálogo: la fila sigue pendiente. Después confirma: desaparece de pendientes en B; al refrescar A tampoco aparece ni puede comprarse con el check antiguo.
4. Conflicto real sin refresco: ambos cargan otro producto; A mantiene su edición abierta, B lo compra. A intenta guardar: recibe conflicto, conserva su propuesta y no reabre ni sobrescribe el producto comprado.
5. Cambiar un pendiente a otra tienda; refrescar ambas tiendas en el otro teléfono y comprobar que aparece una sola vez en la nueva. Vaciar cantidad debe eliminarla, sin cambiar identidad.
6. Comprobación focalizada de accesibilidad: activar Editar y la confirmación, corregir un campo inválido, cerrar y recuperar el foco; comprobar que check y cancelación no se confunden. No se repite la matriz amplia antes de aplicar el design system.

Pendiente adicional: persistencia tras reinicio local controlado del proceso del servidor, y evidencia de la versión alojada. La pérdida de respuesta ya tiene prueba automatizada posterior al commit; cortar la red en un teléfono no demuestra por sí solo ese instante. No reiniciar producción para esta comprobación ni repetir el ensayo offline ya acreditado por #17 sin una regresión concreta.

La consulta de tienda por voz sigue como siguiente unidad obligatoria. App Intents #10 conserva su carácter opcional. Esta issue no cierra el MVP.
