# Administración transferible, salida y capacidades

Introducido en contrato **0.2.0**, 9 de octubre de 2026, para [#33](https://github.com/JFrancoG/SmartShoppingList/issues/33). Complementa [mvp-api.md](mvp-api.md), [OpenAPI](openapi.json), [ejemplos](examples.json) y [aceptación](acceptance.md). La evolución [0.3.0 de pertenencias](group-memberships.md) sustituye el modelo singular, conservando estas reglas de administración; [0.4.0](store-quotas.md) aplica cupos de tiendas y pendientes según el administrador. Define el comportamiento que deben implementar servidor e iOS; este documento no acredita migraciones desplegadas, pruebas ejecutadas ni una oferta de pago disponible.

## Alcance y autoridad

La unidad #33 mantuvo `users.group_id` como pertenencia singular; [#35](group-memberships.md) la sustituye por `group_memberships` y conserva aquel campo solo como proyección antigua. Separa `creatorUserId`, autor histórico inmutable, de `administratorUserId`, administrador vigente. Cada grupo activo tiene exactamente un administrador que pertenece a él. Un usuario que sale puede crear otro grupo; haber creado uno anteriormente no ocupa su pertenencia actual.

La capacidad comercial y el rol son conceptos independientes. Recibir la administración del grupo actual, cederla y salir no requiere premium. El administrador es el titular de la capacidad compartida de tiendas y pendientes; la compra personal no se transfiere al sucesor. Los productos comprados y cancelados quedan fuera del cómputo de pendientes por tienda. El diseño comercial vive en [acceso y límites](../architecture/group-access-and-limits.md).

La unidad #33 no activó multigrupo; #35 añade el modelo y selector con máximo de producción uno y capacidad ampliada solo en pruebas. #37 aplica cupos de tiendas/productos y archivo explícito según [su contrato](store-quotas.md). No se activa StoreKit, precios, cobro ni reducción de acceso por caducidad. La política de capacidades del servidor es la autoridad; el cliente no deduce permisos del creador, del aspecto de una pantalla ni de un booleano local de premium.

## API

Todas las rutas exigen sesión vigente. Los UUID son los IDs de negocio existentes, no sujetos Apple ni emails. Las rutas de grupo requieren pertenencia vigente a un grupo abierto, incluso para reproducir recibos; la única excepción acotada es el recibo de salida propia explicado abajo.

| Método y ruta bajo `/v1` | Entrada | Respuesta satisfactoria |
|---|---|---|
| `GET /groups/{groupId}/members` | `limit` 1–100, por defecto 50; `cursor` opcional | `200` con `{data: [Member], nextCursor: null|string}` |
| `GET /groups/{groupId}/administration` | Sin body | `200` con `{group, memberCount, pendingTransfer: null|Transfer, capabilities}` |
| `POST /groups/{groupId}/administration-transfers` | `{operationId, recipientUserId}` | `201` con `{group, transfer}` |
| `POST /groups/{groupId}/administration-transfers/{transferId}/accept` | `{operationId}` | `200` con `{group, transfer}` |
| `POST /groups/{groupId}/administration-transfers/{transferId}/reject` | `{operationId}` | `200` con `{group, transfer}` |
| `POST /groups/{groupId}/administration-transfers/{transferId}/withdraw` | `{operationId}` | `200` con `{group, transfer}` |
| `POST /groups/{groupId}/departure` | `{operationId, confirmClosure: boolean}`; ambos obligatorios | `200` con `{userId, groupId, leftAt, groupClosed: boolean}` |

`Group` añade `administratorUserId: UUID` requerido y no nulo para grupos activos, conservando `id`, `name`, `creatorUserId` y `createdAt`. No se entrega el grupo cerrado como un `Group` accesible.

`Member` contiene exclusivamente `{id: UUID, displayName: null|string}`. `displayName` tiene los límites existentes de usuario y nunca autoriza. El listado usa cursor opaco ligado al grupo/recurso, orden estable `(created_at, id)` y límite acotado; no expone la cuenta Apple ni el grupo de terceros. `memberCount` es el total vigente y no se infiere del tamaño de una página.

`Transfer` contiene todos estos campos:

```text
id: UUID
groupId: UUID
proposerUserId: UUID
recipientUserId: UUID
status: pending | accepted | rejected | withdrawn | expired | invalidated
createdAt: Timestamp
expiresAt: Timestamp
resolvedAt: null | Timestamp
```

`resolvedAt` es nulo únicamente mientras la propuesta está pendiente. `pendingTransfer` solo devuelve una propuesta utilizable y no es un histórico de transferencias.

## Propuesta y aceptación

Solo el administrador vigente propone a otro miembro actual del mismo grupo; no puede proponerse a sí mismo. Hay como máximo una propuesta pendiente por grupo y caduca a los siete días según el reloj del servidor. Para cambiar de destinatario primero se retira la propuesta. Una propuesta no altera permisos ni administración.

Solo el destinatario acepta o rechaza; solo el administrador proponente vigente retira. Al aceptar se comprueba de nuevo que ambos siguen perteneciendo al grupo y que el proponente sigue siendo su administrador. La aceptación cambia administrador y estado de propuesta en una única transacción; el creador permanece intacto. El anterior administrador sigue como miembro hasta solicitar su salida por separado. Desde 0.4.0, antes de proponer y aceptar se explica que la capacidad compartida dependerá del nuevo administrador. Una reducción conserva datos y permite el traspaso, bloqueando solo crecimiento excedido; no transfiere la suscripción. Tras confirmar se refrescan administración, capacidad y tiendas.

Rechazar o retirar termina la propuesta sin cambiar la administración. La caducidad libera la posibilidad de proponer de nuevo y hace que aceptar, rechazar o retirar con una intención nueva responda `transfer_not_pending`. Salir como destinatario invalida la propuesta pendiente en la misma transacción; no se transfiere el cargo a alguien que ya salió.

## Salida y cierre

Un miembro que no administra puede salir. El administrador con otros miembros debe completar un traspaso antes: la salida responde `409 transfer_required`, aunque haya una propuesta pendiente. No hay elección automática de sucesor.

El último miembro, necesariamente administrador, debe confirmar el cierre mediante `confirmClosure: true`. Con `false` se devuelve `409 closure_confirmation_required` y no hay cambios. Una salida válida elimina la pertenencia al grupo y pone `users.group_id = NULL` únicamente si era su proyección antigua, sin elegir otro grupo; si era el último miembro, marca el grupo cerrado y anula la administración activa. El cierre es lógico: conserva grupo, tiendas, productos, autorías y fechas para no destruir el historial. La API deja de conceder acceso al grupo cerrado y sus invitaciones no permiten reincorporarse. No se ofrece reapertura ni recuperación del historial en esta entrega.

La app advierte del cierre y de la pérdida de acceso antes de enviar. `groupClosed` refleja lo confirmado por el servidor; no se presupone a partir de una pantalla desactualizada. Una nueva incorporación concurrente puede impedir el cierre y exigir traspaso.

## Capacidades de esta entrega

`capabilities` contiene obligatoriamente los siguientes campos; este ejemplo gratuito refleja los límites aplicados desde 0.4.0 (en 0.2.0/0.3.0 los compartidos estaban inactivos):

```json
{
  "canManageInvitations": true,
  "canProposeTransfer": true,
  "canAcceptTransfer": false,
  "canRejectTransfer": false,
  "canWithdrawTransfer": false,
  "canLeave": false,
  "requiresClosureConfirmation": false,
  "capacityOwnerUserId": "00000000-0000-4000-8000-000000000001",
  "limits": {
    "groupsPerAccount": { "maximum": 1, "enforced": true },
    "storesPerGroup": { "maximum": 3, "enforced": true },
    "pendingItemsPerStore": { "maximum": 20, "enforced": true }
  }
}
```

El ejemplo representa al administrador de un grupo con otros miembros y sin propuesta. Los booleanos dependen del solicitante y estado actuales: gestionar invitaciones requiere administrar; proponer requiere otro miembro y ausencia de propuesta utilizable; aceptar/rechazar requiere ser destinatario; retirar requiere ser administrador proponente. `canLeave` es verdadero para un miembro ordinario o para el último miembro, sujeto en este último caso a `requiresClosureConfirmation: true`. El administrador con otros miembros recibe `canLeave: false`.

`capacityOwnerUserId` coincide con el administrador vigente y representa la titularidad de los límites compartidos de tiendas y pendientes. `limits.groupsPerAccount` expresa el límite personal del solicitante, también disponible en `accountCapabilities`; producción conserva máximo uno. En los contratos 0.2.0/0.3.0, `maximum: null` con `enforced: false` indicaba una cuota no activada, sin prometer uso ilimitado. Desde 0.4.0 tiendas/pendientes son 3/20 para gratuito y 10/100 para premium de prueba, aplicados; producción permanece gratuita hasta verificar compras. El cupo personal premium es cinco grupos. Los límites de transporte, nombre, lote y paginación existentes siguen aplicándose. La política se recalcula tras aceptar un traspaso y para cada acción del servidor; una respuesta anterior de capacidades no concede autorización permanente.

## Errores de negocio

Se conserva el sobre `{code, message, requestId}` y los errores estándar del contrato.

| HTTP | Código | Condición |
|---|---|---|
| `403` | `administrator_required` | Un miembro intenta gestionar invitaciones, proponer o retirar sin ser administrador vigente. Sustituye `creator_required` en estas rutas. |
| `403` | `transfer_recipient_required` | Un miembro distinto del destinatario intenta aceptar o rechazar. |
| `409` | `invalid_transfer_recipient` | El destinatario es el propio administrador o no es miembro vigente del mismo grupo. No se revela su cuenta. |
| `409` | `transfer_pending` | Ya existe una propuesta pendiente utilizable. |
| `409` | `transfer_not_pending` | La propuesta ya terminó, caducó o fue invalidada. |
| `409` | `transfer_required` | El administrador intenta salir y quedan otros miembros. |
| `409` | `closure_confirmation_required` | El último miembro intenta salir sin confirmar el cierre. |
| `404` | `not_found` | Grupo desconocido, cerrado o ajeno; propuesta inexistente o perteneciente a otra ruta de grupo. |
| `409` | `idempotency_key_reused` | La misma clave se usa con distinta intención, ruta o contenido. |

La comprobación de pertenencia y de que el recurso pertenece a la ruta precede al diagnóstico de su estado: los errores no sirven para inspeccionar grupos ajenos.

## Transacciones, recuperación y migración

Todas las mutaciones nuevas usan `operationId` y el protocolo de recibos existente. Un reintento exacto devuelve el resultado original, incluido el estado del grupo en aquel resultado; el cliente refresca la administración para conocer el estado actual. Una intención nueva sobre una propuesta terminal obtiene el conflicto correspondiente. Los conflictos terminales `409` quedan asociados a la intención; tras corregir o confirmar una decisión se crea un `operationId` nuevo.

El recibo de **salida propia** es la única excepción a la pertenencia para replay: con sesión válida de la misma cuenta se admite recuperar exclusivamente ese recibo, con la misma ruta, operación y huella de `{confirmClosure}`. Contiene solo `{userId, groupId, leftAt, groupClosed}`. No devuelve el grupo ni autoriza ninguna lectura posterior. Otro usuario o una intención distinta no recupera ese recibo. Todos los demás replays de grupo, incluidos crear grupo, compras y transferencias, requieren pertenencia vigente al grupo abierto del resultado.

Los recibos `createGroup` confirmados antes de 0.2.0 conservan exactamente su cuerpo original, que puede carecer de `administratorUserId`. No se reescriben al migrar ni se añade retrospectivamente el administrador actual. OpenAPI permite `HistoricalGroupReceipt` exclusivamente para ese replay; no es la forma de una creación nueva. El cliente no infiere rol del creador y refresca el estado autoritativo antes de gestionar.

El orden de bloqueo compartido es **grupo → cuenta del actor → recurso** (invitación, transferencia o productos en orden estable de ID). En #35, la cuenta usa `FOR NO KEY UPDATE` y la pertenencia se comprueba en `group_memberships`; `users.group_id` no autoriza. Las comprobaciones de pertenencia, rol, estado y caducidad se repiten después de adquirir los bloqueos. Aceptar una invitación obtiene antes su `group_id` sin bloquear, después bloquea grupo/cuenta/invitación y vuelve a verificar ID, secreto, estado y grupo. Crear un grupo bloquea primero la cuenta porque el grupo todavía no existe; no debe adquirir después el bloqueo de un grupo existente en orden inverso. Las operaciones ordinarias de productos participan también en este protocolo para no escribir tras una salida o cierre concurrentes.

La migración de #33 añade administrador vigente y estado de cierre, rellena la administración con el creador de los grupos actuales y preserva todos los IDs y autorías. Elimina la unicidad de `groups.creator_user_id`: un antiguo creador que salió puede crear otro grupo. La FK que asegura que el administrador pertenece al grupo es diferida hasta el commit, para permitir crear grupo y asignar la pertenencia en la misma transacción. Un grupo abierto requiere administrador; uno cerrado no mantiene administración activa. La tabla de transferencias conserva proponente/destinatario, fechas y estados y garantiza como máximo una propuesta pendiente por grupo. Caducidad e invalidación se resuelven bajo el bloqueo del grupo, sin depender de un cron para autorizar correctamente. #35 traslada la FK diferida del administrador desde `users(group_id, id)` a `group_memberships(group_id, user_id)` y preserva todos esos datos.

## Compatibilidad y entrega

El despliegue del backend precede a la actualización del cliente. `administratorUserId` es una adición a las respuestas existentes; el cliente anterior que ignora campos desconocidos puede seguir con el flujo de compra, pero su gestión basada en creador deja de representar correctamente los permisos tras un traspaso. Gestionar el ciclo nuevo requiere actualizar la app; el backend nunca conserva permisos de creador por compatibilidad.

El cliente nuevo que lea una caché antigua o un servidor sin `administratorUserId` no infiere administración desde `creatorUserId`. Mantiene los datos conservados y espera una respuesta autoritativa compatible antes de ofrecer gestión. Las acciones pendientes siguen ligadas al usuario/grupo original y no se reasignan al salir o crear otro grupo. La evidencia de compilación, pruebas, migración y comportamiento de UI debe registrarse por separado del éxito del validador de esquemas.
