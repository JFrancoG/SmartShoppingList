# Casos de aceptación del contrato del MVP

Referencia funcional: [MVP, secciones 2–6](../mvp-spec.md). Esta matriz define resultados
observables para revisar el contrato de la [issue #2](https://github.com/JFrancoG/SmartShoppingList/issues/2)
y derivar las pruebas de implementación. Revisar ejemplos, esquemas o este documento no
acredita llamadas reales, persistencia, concurrencia ni comportamiento de iOS: las pruebas
de backend y cliente descritas aquí quedan para sus bloques de implementación.

La columna «Bloque» asigna la comprobación futura: [#3](https://github.com/JFrancoG/SmartShoppingList/issues/3)
para entrada y borrador iOS; [#4](https://github.com/JFrancoG/SmartShoppingList/issues/4) para el primer
recorrido de identidad, invitación y datos compartidos; **Fase 2** para completar el resto del
MVP en backend e iOS. La evidencia y el estado operativo pertenecen a las issues, no a esta matriz.

Preparación común: A y B son usuarios distintos del grupo G; C pertenece a otro grupo H.
S y T son tiendas distintas de G. Cuando se indiquen cinco pendientes, son exactamente
`p1`, `p2`, `p3`, `p4` y `p5`, todos de S, con versión inicial `1`. Las identidades y claves
son datos de prueba, nunca credenciales reales.

La finalización descrita abajo usa una transacción para **toda la selección**:
si cualquier entrada presenta un conflicto de versión o estado, responde `409` y no compra
ninguna. Si cambia esta decisión del contrato, deben ajustarse
juntos contrato, OpenAPI, ejemplos y los casos C05–C07.

## Identidad, autorización e invitaciones

| ID | Preparación | Acción | Resultado observable | Bloque |
|---|---|---|---|---|
| I01 | Identidad Apple válida de A; aún sin grupo. | Iniciar sesión, crear G y abrir otra vez la app con la sesión conservada. | Se reconoce la misma cuenta y su grupo; no se crea otro usuario ni se exige otra autenticación mientras la sesión siga válida. | #4 |
| I02 | Sesión caducada o invalidada; borrador local sin enviar. | Consultar o intentar guardar con esa sesión. | El servidor rechaza con `401`; no cambia datos. iOS solicita autenticación, conserva el borrador y no muestra éxito. | #4; conservación iOS en #3 |
| I03 | A conoce IDs de grupo, tienda y producto pertenecientes a H. | Intentar leer, añadir, editar, cancelar o comprar usando esos IDs, también dentro de un lote de G. | No se revelan ni modifican datos de H. La validación de pertenencia cubre cada referencia; un lote que contiene una referencia ajena no produce escrituras parciales. | #4 para lectura/alta; Fase 2 para las demás operaciones |
| I04 | A crea G; B es miembro sin ser creador. | B intenta crear o revocar invitaciones. | Se rechaza la gestión de invitaciones de B; se mantienen sus permisos ordinarios sobre productos. | #4 |
| I05 | Invitación válida de G y B sin grupo. | Abrir el enlace y su previsualización varias veces, sin aceptar. | El enlace sigue utilizable; ninguna apertura crea pertenencia ni consume su único uso. Tras identificarse, B ve el nombre de G antes de confirmar. | #4 |
| I06 | B recibe el enlace por un medio cuyo email difiere del usado con Apple. | B se identifica y acepta expresamente. | Se incorpora la identidad estable de Apple de B; no se exige coincidencia de email. A y B recuperan el mismo G. | #4 |
| I07 | Invitaciones caducada sin consumir, revocada y consumida por otro usuario, como tres preparaciones independientes. | Intentar aceptar cada enlace. | No se concede acceso y se comunica un resultado comprensible. Reabrir la app o el enlace no recupera su validez. | #4 |
| I08 | Dos usuarios sin grupo poseen la misma invitación válida. | Ambos aceptan simultáneamente. | Se incorpora exactamente uno; el otro recibe un resultado de invitación ya utilizada. No existen dos miembros incorporados por un único uso. | #4 |
| I09 | Una invitación válida; B acepta mientras A la revoca. | Ejecutar ambas operaciones con solapamiento controlado. | Hay un único orden efectivo: si prevalece la revocación no entra B; si prevalece la aceptación entra una vez y revocar después no deshace su pertenencia. | #4 |
| I10 | C ya pertenece a H y abre una invitación de G. | C intenta confirmar la incorporación. | No se traslada a C ni se añade una segunda pertenencia. Su grupo sigue siendo H. | #4 |
| I11 | App instalada, B sin sesión y enlace universal válido. | Abrir el enlace, completar el acceso con Apple y volver al flujo. | Se conserva la invitación pendiente; B ve G y puede confirmar. La autenticación no consume el enlace por sí sola. | #4 |
| I12 | Dispositivo sin la app instalada. | Abrir el enlace universal. | La página mínima informa de que se necesita la app; no incorpora al usuario ni consume la invitación. No se exige un flujo automático tras instalar. | #4 |
| I13 | B aceptó la invitación y sigue en G; se perdió la respuesta. | Repetir la aceptación con el mismo ID/secreto, también después de la caducidad. | Devuelve `200` con el mismo grupo; no crea otra pertenencia. Preview devuelve `alreadyAccepted: true`. | #4 |

## Borrador, tiendas y altas

| ID | Preparación | Acción | Resultado observable | Bloque |
|---|---|---|---|---|
| A01 | Micrófono e interpretación disponibles en el entorno identificado. | Decir «Comprar jabón, cerveza y yogures en Mercadona» y revisar el borrador. | Aparecen tres productos corregibles y la tienda; antes de confirmar no hay altas compartidas. Las correcciones humanas, incluidas variantes como «sin lactosa», son las que se envían. | #3; guardado real en #4 |
| A02 | Micrófono denegado o Apple Intelligence no disponible. | Introducir productos, cantidades opcionales y supermercado a mano; revisar y confirmar. | Puede completarse el mismo guardado sin IA; no se inventan cantidades o tienda. La prueba manual física se registra por separado de transcripción y Foundation Models en simulador. | #3; integración en #4 |
| A03 | Texto de tienda ambiguo o que no determina una tienda existente. | Revisar la propuesta antes de guardar o consultar. | Se solicita una elección humana entre opciones pertinentes o la creación explícita de una tienda; no se asigna una por parecido. La elección permanece visible y puede corregirse sin hablar otra vez. | #3; consulta completa en Fase 2 |
| A04 | Una tienda `Café` en G; entradas de nombre `CAFÉ` y `Café` con acento descompuesto. | Resolver o crear la tienda siguiendo la normalización contractual NFC y casefold. | Las formas equivalentes identifican la misma tienda de G; no crean duplicados por mayúsculas o representación Unicode. `Cafe` sin acento o una errata distinta no se fusionan mediante coincidencia difusa. | #4 |
| A05 | Lote de tres entradas revisadas, una inválida según los límites del contrato. | Enviar el lote. | Se rechaza el lote completo: cero altas, ninguna tienda creada solo por el intento fallido y borrador conservado para corregir. | #4 |
| A06 | Lote válido y clave K; doble pulsación o dos peticiones simultáneas idénticas. | Enviar ambas con K y el mismo contenido. | Hay un único lote persistido y los mismos IDs en su resultado; no se duplica ninguna entrada. El cliente solo comunica guardado al recibir confirmación. | #4; cliente en #3 |
| A07 | El servidor confirmó K, pero se pierde la respuesta antes de llegar a iOS. | Reintentar con K y exactamente el contenido enviado. | Se recupera el resultado de esa operación con sus IDs; no se crea otro lote ni se presenta éxito antes de resolverlo. | #4; cliente en #3 |
| A08 | Lote anterior confirmado; la persona vuelve a necesitar los mismos productos. | Confirmar voluntariamente otra alta con una clave nueva. | Se crean entradas nuevas con IDs distintos aunque sus textos coincidan. No hay deduplicación semántica ni reutilización del historial anterior. | #4 |
| A09 | Clave K ya asociada a un envío. | Reutilizar K cambiando productos, cantidades o tienda. | Se rechaza la reutilización con contenido distinto; el resultado original permanece intacto y el envío modificado no se guarda. | #4 |
| A10 | A y B tienen sendos borradores válidos, con claves distintas. | Ambos confirman altas mientras el otro conserva una lista anterior. | Tras refrescar se recuperan todas las altas de ambos usuarios; ninguna escritura sustituye la lista completa del grupo. | #4 |

## Checks, finalización y conflictos

| ID | Preparación | Acción | Resultado observable | Bloque |
|---|---|---|---|---|
| C01 | Cinco pendientes de S; se observan peticiones y datos del servidor. | Marcar `p1`, `p3`, `p5` y desmarcar `p3`. | Solo cambia el borrador local: quedan dos checks y contador dos. No hay escritura, reserva, historial ni cambio visible para B por esos checks. | Fase 2 |
| C02 | Tres checks en S. | Cambiar de pantalla, pasar a segundo plano y elegir T. | No se confirma compra; la selección de S no se aplica a T. El usuario puede revisar la selección correspondiente antes de enviar. | Fase 2 |
| C03 | Cinco pendientes de S; seleccionados exactamente `p1`, `p3`, `p5`, versión `1`. | Finalizar con esos tres IDs y sus `expectedVersion`. | Se compran exactamente esos tres, conservando sus registros y anotando comprador y fecha. `p2` y `p4` siguen pendientes; contador y resultado reflejan tres compras. | Fase 2 |
| C04 | La misma selección; B añade `p6` después de cargar la lista de A. | A finaliza `p1`, `p3`, `p5` y refresca. | `p6`, `p2` y `p4` permanecen pendientes. El servidor actúa sobre los IDs expresos, sin actualizar toda S por filtro. | Fase 2 |
| C05 | A seleccionó `p1`, `p3`, `p5`; B edita `p3` y aumenta su versión antes del envío. | A finaliza usando la versión antigua de `p3`. | `409` y cero compras del lote: `p1` y `p5` siguen pendientes. Se informa del conflicto y se recupera la versión vigente de `p3`, sin sobrescribirla. | Fase 2 |
| C06 | A seleccionó tres productos; B cancela uno antes del envío. | A finaliza con el estado anterior. | `409` sin compras parciales. El cancelado continúa cancelado y no obtiene comprador ni fecha de compra; iOS no presenta el lote como confirmado. | Fase 2 |
| C07 | A selecciona `p1`, `p3`; B selecciona `p3`, `p5`, con las mismas versiones iniciales. | Ambos finalizan concurrentemente con claves distintas. | Solo una transacción gana; la otra responde `409` sin comprar su producto no solapado. `p3` tiene una única compra y conserva al comprador de la primera transición válida. | Fase 2 |
| C08 | Una edición o cancelación parte de una versión antigua; otro miembro ya editó, compró o canceló la entrada. | Enviar la modificación con `expectedVersion` desactualizado. | Se rechaza el conflicto; no se sobrescribe el cambio vigente, no se reabre un registro terminal y no se reemplaza al comprador. Se requiere conciliación visible antes de una nueva decisión. | Fase 2 |
| C09 | Finalización confirmada con clave K; respuesta perdida o doble pulsación. | Repetir K y la misma selección con las mismas versiones. | Se devuelve el resultado original sin nuevas compras, sin alterar fechas ni comprador y sin tratar el propio éxito anterior como un nuevo conflicto de versión. | Fase 2 |
| C10 | Finalización K enviada, cuyo resultado aún se desconoce. | Intentar cambiar la selección o reutilizar K con otro contenido. | K no admite otro contenido. iOS conserva el envío original y resuelve su resultado antes de iniciar una finalización distinta; no crea otra compra para «probar otra vez». | Fase 2 |
| C11 | Ningún producto seleccionado, o selección enviada con IDs duplicados, de otra tienda o de otro grupo. | Intentar finalizar. | iOS no envía una selección vacía. El backend rechaza selecciones inválidas sin compras parciales, también si se evita la validación del cliente. | Fase 2 |
| C12 | Un producto pendiente deja de ser necesario. | Cancelarlo; más tarde volver a añadir ese producto. | La primera entrada conserva estado cancelado y no cuenta como compra. La nueva necesidad tiene otro ID; no recicla el registro cancelado o comprado. | Fase 2 |

## Red, consulta y persistencia

| ID | Preparación | Acción | Resultado observable | Bloque |
|---|---|---|---|---|
| R01 | Lista recuperada anteriormente y conexión perdida. | Consultar esa lista e intentar una operación compartida. | La lista indica que puede estar desactualizada; el fallo conserva borrador o selección y no se muestra como guardado. No se encola una sincronización general silenciosa. | #3 para borrador; Fase 2 para compra/consulta |
| R02 | B ha modificado los pendientes de S. | A entra en Comprar, termina una operación propia o pide refresco explícito. | Recupera pendientes reales de G y S; voz y selector consultan esos datos. No se exige actualización instantánea mientras A permanece sin refrescar. | #4 para consulta compartida; Fase 2 para todos los disparadores |
| R03 | Altas y pertenencias confirmadas; después, compras y cancelaciones confirmadas. | Cerrar/reabrir iOS y reiniciar el servidor usando la base persistente. | Se conservan IDs, grupo, tienda, estados, autores y fechas confirmados. Comprados/cancelados no reaparecen como pendientes; la reapertura no repite escrituras ya confirmadas. | #4 para altas/grupo; Fase 2 para transiciones |

## Evidencia necesaria al implementar

Las pruebas del backend deben atravesar rutas, autorización y PostgreSQL aislado, con
resultados observables obtenidos mediante nuevas lecturas. Los casos de concurrencia requieren
solapamiento controlado y comprobar ambos órdenes relevantes; ejecutarlos secuencialmente no
acredita exclusión mutua. La respuesta perdida se simula después del commit y antes de la
recepción del cliente, no mediante un fallo que impida enviar la petición.

Las pruebas iOS deben verificar controles, estado visible, conservación del borrador y
peticiones emitidas. La comprobación de checks locales necesita demostrar ausencia de
escrituras, además de observar la pantalla. La integración con dos usuarios y las pruebas
físicas/simulador se identifican con su entorno y resultado; ningún ejemplo OpenAPI ni doble
de prueba sustituye esas evidencias.
