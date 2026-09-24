# Selección y finalización de compra — #11

Evidencia del 22 de septiembre de 2026. Seguimiento operativo: [issue #11](https://github.com/JFrancoG/SmartShoppingList/issues/11). Rama local `codex/issue-11-purchase-flow`, basada en `81b8128c8ec5e6a8ad053ae75c2217172cdb276a` de `codex/issue-4-shared-shopping-flow`. La PR #9 permanece abierta en borrador como dependencia. El código está publicado y desplegado en el commit `5e65c563dd73cbbc9f8741498f107f1249a8b684`. Este informe reúne la validación automatizada inicial, la comprobación del estado de despliegue y los resultados físicos comunicados por el responsable. La publicación de esta consolidación documental y su commit se referencian en la issue.

## Alcance implementado

Selección local separada por tienda, contador, confirmación explícita y compra atómica de 1–50 IDs/versiones. Keychain conserva la intención antes del envío; un reintento o reapertura recupera la misma clave y selección. El servidor registra comprador/fecha/versiones, conserva recibos de éxito o conflicto y no modifica filas omitidas. Ante cambios concurrentes se conserva la selección original para revisión. Diseño en [arquitectura compartida](../architecture/shared-shopping.md#selección-y-finalización-de-compra-11).

No incorpora edición/cancelación desde la app, historial, selección de tienda por voz ni Siri. Los checks previos a Finalizar están en memoria; la persistencia comprobada corresponde al envío preparado/incierto. La activación de esta versión y su ensayo alojado se detallan más abajo.

## Validación automatizada local

Xcode 27.2 beta (`27B5019j`), Swift 6, My Mac (Designed for iPad) para iOS y macOS para el servidor. PostgreSQL aislado `db-test`, con migraciones reiniciadas entre tests; no se modifica la base alojada.

| Ejecución | Resultado nativo | Invocaciones |
|---|---:|---:|
| iOS, plan Fast | 67 pruebas, 0 fallos | 109, incluidas parametrizadas |
| iOS, plan Integration | 5 pruebas, 0 fallos | 7, incluidas parametrizadas |
| Servidor, PostgreSQL real | 74 pruebas, 0 fallos | 113, incluidas parametrizadas |

Los recuentos proceden de `.xcresult` cerrados, no de la suma del estado histórico devuelto por MCP: Integration devolvía 56 resultados correctos acumulados pero su ejecución nativa contiene 5 pruebas / 7 invocaciones. No hay fallos ni pruebas omitidas en los resultados nativos. Fast e Integration no son una demostración física ni una autenticación real.

Las tres primeras regresiones de compra fallaron antes de implementar el endpoint (404); las tres de selección/reintento fallaron con las operaciones del cliente todavía vacías. Tras implementarlas pasan junto con la regresión existente. Se añadieron comprobaciones específicas para:

- Comprar tres de cinco, conservar omitidos y otra tienda, y atribuir comprador distinto del creador.
- Repetir el mismo recibo y dos envíos simultáneos con orden distinto; rechazar la reutilización de clave con otro contenido.
- Conflicto de versión sin compra parcial y dos compradores con selección solapada sin sobrescribir al ganador.
- Ocultar filas ajenas, impedir acceso de otro grupo, límites de selección y rollback de filas/recibo ante fallo de PostgreSQL.
- Checks reversibles por tienda sin mutación, recuperación del sobre exacto tras reapertura y revisión explícita de versiones cambiadas.
- Respuesta de conflicto incompleta o incoherente conservada como incierta; respuesta de éxito limitada a los IDs enviados.
- Compra confirmada seguida de fallo del refresco: retirar IDs comprados, bloquear la carga obsoleta y mostrar aviso específico.
- Persistir y recuperar el sobre de compra mediante Keychain real, conservándolo al borrar la sesión.

Artefactos locales de esta ejecución: `/tmp/ssl-purchase/`. Informes `ios-green-final-native.json`, `ios-integration-native.json` y `server-final-native.json`; resultados MCP correspondientes incluyen las rutas `.xcresult`. El informe servidor se leyó desde DerivedData porque la ruta copiada por MCP no contenía `Info.plist`.

Build iOS posterior a los ajustes de formato: correcto, incluidos tests. `GetBuildLog` final del servidor y cliente no muestra warnings. Esto no amplía las excepciones ni certifica que toda resolución desde cero carezca de avisos; [EXC-001 y EXC-002](../dependency-exceptions.md) mantienen su alcance aceptado. No se cambian dependencias ni toolchain.

### Ampliación de criterios — 22 de septiembre, 23:29 CEST

Se añaden dos tests de integración, con tres casos, en `ShoppingFlowTests.swift`:

- **Alta posterior:** después de preparar una compra de tres de cinco, otro miembro añade Fresas a Mercadona mediante el endpoint real de lotes. La compra original confirma exactamente los tres IDs seleccionados; quedan cuatro pendientes (dos omitidos, uno de Aldi y el alta nueva). Fresas conserva versión 1, autor y ausencia de comprador/fecha de compra.
- **Edición entre selección y compra:** un cambio ya confirmado deja Pan integral, cantidad «2 bolsas» y versión 2. La petición con versión 1 devuelve `409 item_conflict`, razón `version_mismatch`, e informa los valores actuales.
- **Cancelación entre selección y compra:** el producto pasa a `cancelled`, versión 2. La misma selección obsoleta devuelve `409 item_conflict`, razón `not_pending`.

En los dos conflictos se compara una instantánea completa de todas las filas del grupo antes y después del endpoint: ningún producto cambia, incluidos los otros dos seleccionados. La edición/cancelación se prepara directamente en PostgreSQL aislado, porque sus rutas e interfaz todavía no forman parte de este bloque. Esto acredita la protección de compra ante un cambio previo a su transacción; no una carrera simultánea con futuros endpoints de edición/cancelación ni un ensayo físico de esas funciones.

Xcode 27.2 beta, esquema/plan `SmartShoppingListServer`, My Mac: build de tests correcto y ejecución dirigida **2 pruebas / 3 casos, 0 fallos, 0 omitidos**, confirmada en el `.xcresult` nativo cerrado. Artefactos: `/tmp/ssl-purchase-followup/targeted.json`, `targeted-native.json`, `build.json` y `build-warnings.json`. El log completo contiene únicamente el aviso App Intents del bundle de tests cubierto por **EXC-002**, aunque el resumen de `GetBuildLog` no lo muestra. Sin warnings propios; auditoría de estilo del Swift añadido y `git diff --check` correctos.

No cambia código de producción, dependencias ni configuración. Los resultados completos anteriores de iOS, servidor y Linux siguen siendo su evidencia histórica; no se presentan como una nueva ejecución con estos tests. El catálogo actual contiene 76 funciones de test, pero esta ampliación solo ejecuta las dos nuevas. `db-test` vuelve a su estado detenido y no se cambia el esquema/destino/plan de iOS. El commit y la publicación de esta ampliación se verifican y referencian en #11.

Tras el ajuste final de formato se repiten únicamente esas dos pruebas a las 23:32 CEST: **3 casos correctos**, mismo aviso aceptado y ningún diagnóstico adicional. Evidencia final: `targeted-final.json`, `targeted-final-native.json` y `build-warnings-final.json` en el mismo directorio de artefactos.

## Linux Release

Swift 6.4.0 / Linux arm64: `swift test -c release --jobs 4 --force-resolved-versions` correcto, 74 pruebas en 8 suites, 4,419 segundos de ejecución después de compilar. Se reutilizó la etapa local `smartshoppinglistserver:review-builder-9e51e2c` con `Sources` y `Tests` actuales montados en solo lectura. Antes de ejecutar se compararon `Package.swift` y `Package.resolved` del contenedor byte a byte con el repositorio; coinciden. PostgreSQL: `db-test` aislado en la red local de Compose. Log `/tmp/ssl-purchase/linux-tests.log`, salida 0.

La compilación Release mantiene únicamente el diagnóstico del manifiesto JWTKit sobre watchOS 8, cubierto por EXC-001. No hay warnings propios. Esta prueba no genera una imagen final nueva ni acredita amd64, HTTP externo o Railway. Se retiró el contenedor de prueba y `db-test` volvió a su estado detenido; Xcode volvió a iPhone 11 y plan Fast.

## Revisión y presentación

Las revisiones independientes de arquitectura y UI cubren el diff local. Se corrigieron y reauditaron tres hallazgos: validación del conflicto completo, refresco fallido tras éxito y eliminación del constructor que omitía invariantes. Sin nuevos hallazgos después de las correcciones. Auditoría de estilo sobre los Swift cambiados y `git diff --check` correctos; literales de contrato/SQL se mantienen legibles sin reformatear el repositorio.

Previews oficiales de `SharedPurchaseSection` en iPhone 18 Pro / iOS 27.2 con un producto seleccionado: Large, XXX Large y AX 5. Inspección visual sin truncado de productos ni solapamientos en el área visible. En AX 5 la confirmación queda fuera del encuadre inicial: exige scroll y ensayo real. Las capturas/JSON están en `/tmp/ssl-purchase/preview-*.json` y en sus rutas `previewSnapshotPath`.

Las previews no acreditan VoiceOver, foco tras finalizar, comportamiento completo al desplazarse ni inglés traducido. El ensayo físico posterior tampoco se realizó como auditoría de accesibilidad. Los avisos/reintento al principio del formulario pueden quedar fuera de pantalla al confirmar desde abajo; ese hallazgo ya aplazado permanece en fase 3 y también requiere comprobarse en compra.

## Despliegue y ensayo físico — 22 de septiembre de 2026

El responsable confirmó el despliegue correcto en Railway. Se verificó además el deployment de GitHub `6599823733`, entorno `SmartShoppingList / production`, SHA `5e65c563dd73cbbc9f8741498f107f1249a8b684`, con estado `success` registrado a las **22:23:34 CEST**. Esta comprobación vincula el servidor al commit; no identifica por sí sola el build instalado en cada iPhone. URL de servicio: [SmartShoppingList en Railway](https://smartshoppinglist-production.up.railway.app/).

El ensayo se hizo con los **iPhone 14 e iPhone 11**, dos cuentas Apple y el mismo grupo del recorrido anterior. No se volvió a verificar el número exacto de build iOS de cada dispositivo. Los resultados siguientes son confirmaciones del usuario durante el recorrido guiado; no una ejecución automatizada ni una inspección directa de los teléfonos por Codex. Se prepararon varios productos en **Mercadona y Aldi**, incluidos **papel higiénico y Alpro repetidos en ambas tiendas**. El número total inicial no se registró: la compra física seleccionó dos productos y no debe presentarse como una repetición exacta del caso automatizado de tres de cinco.

| Caso | Acción y resultado confirmado |
|---|---|
| Selección local y por tienda | En iPhone 14 se marcaron papel higiénico y Alpro en Mercadona: contador 2. Aldi mostraba 0 y ambos sin marcar. Al volver a Mercadona seguían seleccionados. Tras actualizar el iPhone 11, los mismos productos seguían pendientes y sin checks locales. |
| Compra compartida y aislamiento de tienda | Finalizar los dos de Mercadona los retiró de pendientes en iPhone 14 y, tras refrescar, en iPhone 11. Los otros productos se conservaron; papel higiénico y Alpro de Aldi siguieron pendientes en ambos. |
| Fallo sin conexión | En iPhone 14 se marcó otro pendiente, se activó modo avión y se desactivó Wi-Fi antes de Finalizar. Aparecieron el aviso de resultado no confirmado y el bloque de envío pendiente con Reintentar envío. El usuario confirmó selección conservada y producto aún pendiente en iPhone 11 tras refrescar. |
| Reintento al recuperar conexión | Reintentar confirmó la compra, retiró el bloque de envío pendiente y el producto desapareció de ambos clientes tras refrescar el 11. Apareció el aviso esperado «La compra se ha confirmado. Los productos no seleccionados siguen pendientes». |
| Selección desactualizada por compra del otro usuario | Se marcó el mismo pendiente de la misma tienda en ambos. Tras finalizar en iPhone 11, el intento en iPhone 14, sin refresco manual previo, mostró «Hay productos seleccionados que han cambiado o ya no están pendientes». Desmarcar los cambiados dejó contador 0 y Finalizar deshabilitado; tras refrescar ambos, el comprado siguió fuera de pendientes y los demás se conservaron. |
| Recuperación tras cerrar y reabrir | Se preparó otro envío sin conexión en iPhone 14, se cerró completamente la app, se recuperó la red y se abrió de nuevo. El usuario confirmó Reintentar envío y selección conservados. El reintento posterior confirmó y eliminó el bloque pendiente; ambos clientes quedaron sin productos cargados en la tienda consultada porque era su último pendiente. No se acredita con ello que todas las tiendas estuvieran vacías. |

La captura aportada **«Captura 2026-09-22 a las 23.00.47.png»** muestra el modo avión, los dos mensajes y Reintentar envío. Es evidencia visual del estado presentado; la selección fuera del encuadre y el resultado del otro dispositivo se basan en la confirmación posterior del usuario. La captura no se incorpora al repositorio.

### Límites de estas confirmaciones

- El corte de conexión se hizo **antes** del envío. No se forzó pérdida de respuesta después de un commit remoto. El replay exacto, el doble envío y la atomicidad mantienen su evidencia automatizada separada.
- La prueba entre teléfonos fue una compra seguida de una selección obsoleta en el otro cliente. No se capturó el HTTP `409` ni se midió simultaneidad real. La carrera de dos transacciones con un único ganador está cubierta por PostgreSQL en las pruebas automatizadas.
- La interfaz confirma estados observables; no se inspeccionaron manualmente comprador, fecha, versiones o recibos en producción. Estos campos se verifican en las pruebas del servidor.
- No se ensayaron físicamente límites 0/50/51, alta posterior a la selección, edición/cancelación concurrente ni VoiceOver de compra. El caso exacto de tres de cinco y los límites de petición tienen evidencia automatizada. La ampliación anterior comprueba el alta posterior y el rechazo atómico ante edición/cancelación ya confirmadas entre selección y compra, con los límites allí indicados.

## Ajustes de interfaz registrados para fase 3

1. **Avisos repetidos:** el fallo de red muestra simultáneamente el aviso y el estado del envío pendiente. Son dos presentaciones del mismo intento, no evidencia de dos compras. Unificar la información preservando la acción de reintento y la distinción entre aviso descartable y operación pendiente.
2. **Texto adecuado a la operación:** «sin duplicar productos» procede del alta de productos y resulta impreciso al finalizar una compra. Adaptar el mensaje a la operación, o usar un texto común como «sin repetir la operación».
3. **Visibilidad y accesibilidad:** el usuario localizó el aviso de selección desactualizada abajo. Revisar éxito, conflicto y reintento para que se perciban desde la posición actual y con VoiceOver, dentro del pendiente general de avisos fuera de pantalla.
4. **Vacío confirmado:** tras agotar los pendientes, ambos mostraron «Sin productos cargados». Distinguir una consulta completada y vacía («No hay productos pendientes en esta tienda») de una lista aún no cargada o un fallo de consulta; no cambiar el texto indiscriminadamente.

## Situación después del ensayo

El recorrido físico guiado está confirmado dentro de los límites anteriores y los casos automatizados pendientes de este bloque están completados. El seguimiento vigente y el cierre de criterios se conservan en #11; no se declara completada la fase 2. El responsable autoriza commit, push y apertura de PR de compra contra la rama de PR #9. El merge y cierre de #11 quedan para después de integrar #9, cambiar la base de la PR de compra a `main` y revisar su diff y comprobaciones finales. Los ajustes de interfaz quedan en fase 3, y las invitaciones de #4/#7, edición/cancelación, historial, voz para tiendas y Siri mantienen su planificación independiente.

## Preparación del commit y push

El usuario autorizó commit y push el 22 de septiembre. Se reutilizan los resultados anteriores del mismo código; durante la preparación de entrega solo se ajusta documentación y la entrada del changelog. La revisión final del diff y `git diff --check` pasan. La publicación se verifica contra la rama remota y se registra en #11; esta autorización no incluye PR, merge, cierre ni despliegue.
