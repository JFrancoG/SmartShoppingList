# Pertenencias múltiples y selección de grupo

Introducido en contrato **0.3.0**, 9 de octubre de 2026, para [#35](https://github.com/JFrancoG/SmartShoppingList/issues/35). Amplía [mvp-api.md](mvp-api.md) y [administración de grupo](group-administration.md). [OpenAPI](openapi.json), [ejemplos](examples.json) y [aceptación](acceptance.md) describen la misma API. La evolución [0.4.0 de cupos y archivo](store-quotas.md) añade límites compartidos y conserva estas reglas de pertenencia y selección. Es una definición implementable; no acredita migración desplegada, pagos, pruebas ejecutadas ni validación física de Siri.

## Pertenencia, selección y capacidad

La pertenencia es una relación entre cuenta y grupo. Una cuenta puede pertenecer a varios grupos y administrar varios de ellos; cada grupo abierto conserva exactamente un administrador que es miembro. Crear o incorporarse a un grupo adicional consume una plaza de la cuenta. Recibir administración de un grupo al que ya se pertenece no consume plazas. Salir elimina exclusivamente esa pertenencia y mantiene las reglas de traspaso y cierre de #33.

La selección activa pertenece al cliente, por cuenta y dispositivo. No hay un endpoint de selección ni se modifica la cuenta del servidor al cambiar de grupo. Toda lectura o escritura compartida lleva el grupo explícito de su ruta y el servidor comprueba esa pertenencia vigente, aunque sea distinto del grupo seleccionado localmente o de `User.group`.

La política de producción conserva **un grupo por cuenta**, tanto para administradores como para miembros. Solo las pruebas pueden inyectar una política con capacidad ampliada para verificar el recorrido completo. La unidad #35 no publicó una suscripción, una opción para fingir premium, una ampliación por variable de entorno ni cuotas de tiendas o productos. #37 aplica los cupos compartidos según [store-quotas.md](store-quotas.md), conservando producción gratuita; el plan premium de prueba permite hasta cinco pertenencias personales. Downgrade, periodos de gracia y selección de un grupo gratuito siguen pendientes de una unidad comercial posterior; este contrato no restringe compras ni administración de pertenencias existentes por superar el cupo de nuevas incorporaciones.

## API de cuenta y grupos

`GET /v1/groups` exige sesión y devuelve `200 {data: [Group], nextCursor: null|string}`. Admite `limit` 1–100, por defecto 50, y `cursor` opcional. Devuelve solo grupos abiertos con pertenencia vigente del solicitante; el orden es `(groups.created_at, groups.id)` ascendente. El cursor opaco se vincula a cuenta y recurso, se rechaza para otra cuenta o consulta y no concede acceso. Cada página vuelve a verificar la cuenta; no se promete un snapshot entre páginas. El cliente acumula por ID y no usa una descarga parcial para decidir la selección ni el número de pertenencias.

`GET /v1/me` y `login.user` conservan `{id, displayName, group}` y añaden el campo requerido `accountCapabilities`:

```json
{
  "membershipCount": 1,
  "canCreateGroup": false,
  "canJoinGroup": false,
  "limits": {
    "groupsPerAccount": { "maximum": 1, "enforced": true }
  }
}
```

`membershipCount` cuenta pertenencias vigentes a grupos abiertos, independientemente del rol o de la selección. Los booleanos indican capacidad para una pertenencia **nueva**, son verdaderos cuando el número es menor que el máximo y no autorizan escrituras por sí solos. `canJoinGroup: false` no impide aceptar una invitación válida a un grupo del que ya se es miembro. El máximo es un entero positivo; las pruebas pueden ampliarlo. `Group.capabilities` no existe: las capacidades de administración siguen en la respuesta de `/administration`. Su `limits.groupsPerAccount` coincide con el límite personal del solicitante, mientras `capacityOwnerUserId` identifica al administrador responsable de los límites compartidos de tiendas y pendientes, aplicados desde 0.4.0.

`POST /v1/groups` conserva `{operationId, name}` y su respuesta `201 Group`. Crea grupo y pertenencia de administrador atómicamente si queda capacidad. `POST /v1/invitations/{invitationId}/accept` conserva `{token}` y `200 Group`; añade la pertenencia sin quitar ninguna anterior. No cambia la selección de otro dispositivo. Tras una creación o incorporación confirmada, el cliente nuevo relee cuenta y todas las pertenencias antes de ofrecer el destino; un recibo histórico no sustituye esos datos.

| Situación de invitación con secreto válido | Resultado |
|---|---|
| Libre, vigente; usuario ajeno con capacidad | Añade una pertenencia y consume el enlace en la misma transacción. |
| Libre, vigente; usuario ya miembro | `200 Group`; consume para ese usuario, sin insertar otra pertenencia ni comprobar una plaza adicional. |
| Libre, vigente; usuario ajeno sin capacidad | `409 group_limit_reached`; conserva enlace sin consumir y todas las pertenencias. Puede reintentarse ese enlace si cambia la capacidad. |
| Consumida por el mismo usuario, que sigue siendo miembro | `200 Group`, incluso después de la caducidad; no consume plaza ni cambia la proyección antigua. |
| Consumida por otro o por el mismo usuario que salió | `410 invitation_consumed`; el enlace no permite reincorporarse. |
| Revocada o caducada sin consumir | Conserva `410 invitation_revoked` o `410 invitation_expired`. |
| Grupo cerrado o secreto incorrecto | `404 not_found`, sin revelar el grupo. |

`alreadyAccepted` en preview mantiene su significado: esa invitación fue consumida por el mismo usuario y todavía pertenece al grupo. No significa simplemente que el usuario ya sea miembro por otra vía.

## Cuota y recuperación

`409 group_limit_reached` usa el sobre estándar `{code, message, requestId}`. Es un rechazo definitivo de la intención actual, distinto de falta de permiso, `429` o respuesta incierta. En creación queda guardado en su recibo: repetir exactamente el mismo `operationId` devuelve ese mismo conflicto aunque después cambie la capacidad. Una nueva decisión de crear usa otro identificador. La aceptación de invitaciones no usa `operationId`: el rechazo de cupo no consume el enlace y admite reintento de su transición original.

Un éxito confirmado se reproduce sin consumir plaza ni volver a comprobar el límite. Conserva exactamente status y body originales, incluidas respuestas históricas sin `administratorUserId`, y no modifica `users.group_id`, la selección local ni otra pertenencia. Requiere sesión de la misma cuenta y pertenencia vigente al grupo abierto del resultado; se sustituye la antigua igualdad con `users.group_id` por esa comprobación. Los recibos históricos `already_in_group` no se reescriben y siguen devolviendo su conflicto para aquella intención. El recibo mínimo de salida propia mantiene la única excepción de pertenencia de #33; recuperarlo no elimina una reincorporación posterior.

El cliente conserva la cuenta, grupo, tienda, petición, identificador y snapshots de una operación pendiente. No permite cambiar de grupo mientras una mutación pueda seguir sin resolver y no redirige su reintento al grupo activo. Cambiar de grupo invalida tiendas, productos cargados, checks, editor, revisión, búsqueda por voz y permisos del destino anterior; las respuestas tardías se descartan por identidad de cuenta/grupo. El borrador local se conserva, pero requiere revisión y confirmación del destino actual antes de enviarse.

## Compatibilidad y selección local

`users.group_id` deja de representar la pertenencia única y se conserva solo para la proyección antigua `User.group`. La migración mantiene su valor. Una **nueva** creación o incorporación lo rellena únicamente si es nulo; aceptar una invitación siendo ya miembro o reproducir una operación confirmada no lo rellena. Al salir del grupo indicado se pone a nulo, sin seleccionar otra pertenencia. Salir de otro grupo lo conserva. `/me.group` solo devuelve ese grupo si sigue abierto y existe la pertenencia correspondiente; puede ser nulo aunque `membershipCount` sea mayor que cero.

El cliente anterior puede seguir usando su grupo proyectado, pero necesita actualizarse para descubrir y seleccionar otras pertenencias. No se lo traslada a otro grupo al salir. Las capacidades nuevas son aditivas; la política de permisos del backend no depende de que el cliente las entienda. El servidor se actualiza antes que el cliente nuevo. Si faltan el listado o las capacidades nuevas, el cliente conserva caché y operación pendiente, informa de la falta de actualización y no convierte `User.group` en una lista autoritativa.

El cliente nuevo guarda selección por cuenta/dispositivo y la valida frente al listado completo recuperado. Solo durante la configuración inicial sin selección previa puede elegir automáticamente si existe exactamente una pertenencia; con varias exige elección. Si se pierde el acceso al grupo seleccionado, lo limpia y requiere otra elección, incluso si queda solo uno. Esa pérdida se distingue de una instalación sin selección y se conserva al reabrir; una respuesta fallida no acredita pérdida de pertenencia. El grupo guardado y su administración en caché no habilitan mutaciones antes de verificar acceso.

Siri conserva dos recorridos distintos: `AddDraftItemIntent` solo guarda borrador; `AddShoppingItemIntent` puede añadir a una tienda conocida automáticamente **solo cuando la consulta vigente confirma una única pertenencia**. Si hay varias, guarda para revisión local y elección explícita del grupo/destino, aunque la app tenga grupo activo. No se añade un parámetro de grupo al App Intent en esta unidad, ni se usa el último grupo activo como decisión silenciosa. Los límites de conectividad y recuperación previos siguen aplicándose.

## Migración y coordinación

La migración adicional crea `group_memberships` con clave primaria `(group_id, user_id)` y claves foráneas a grupos y usuarios. Copia cada asignación vigente de `users.group_id`, sin alterar grupos, autores, administrador, tiendas, productos, transferencias, invitaciones, sesiones ni recibos. `joined_at` se inicializa con el reloj de migración: no inventa la fecha histórica de entrada ni cambia los órdenes de paginación. Sustituye la FK de administrador por `(groups.id, groups.administrator_user_id) → group_memberships(group_id, user_id)`, diferida hasta commit. Después retira la antigua unicidad `users(group_id, id)`. La restricción de grupo abierto con administrador permanece.

Una reversión se ejecuta en transacción con bloqueos que mantienen estable la comprobación hasta terminar el cambio de esquema. Exige correspondencia en ambos sentidos entre todas las pertenencias y la proyección singular: no basta con contar como máximo una por usuario. Si una pertenencia tiene proyección nula/distinta, una proyección no tiene pertenencia, o hay varias, rechaza sin alterar datos/esquema. Nunca elige una pertenencia para descartar las demás ni inventa relaciones al recuperar el esquema antiguo.

El despliegue necesita detener los escritores del backend anterior durante la migración y sustituirlos por la versión que usa `group_memberships`. No se permite convivencia de servidores que escriban solo `users.group_id` con servidores que autoricen por la relación nueva. Después se publica el cliente actualizado. Esta condición de despliegue no autoriza ni acredita ejecutarlo en producción.

El orden de trabajo sobre un grupo existente sigue siendo **grupo → cuenta del actor → recurso**. La cuenta se bloquea con `FOR NO KEY UPDATE`, que serializa admisiones de la misma cuenta sin impedir el `KEY SHARE` de las FK de proponente/destinatario. No se modifica una clave de usuario. Crear grupo comienza por la cuenta porque no existe aún el grupo; no bloquea después un grupo ya existente. Se eliminan autorizaciones basadas en igualdad con `users.group_id`, incluso en páginas, administración, invitaciones y recibos. La consulta de miembros mantiene el orden `(users.created_at, users.id)` usando la relación nueva.

Contar pertenencias y añadir una se realizan bajo el mismo bloqueo de cuenta. Dos altas de esa cuenta, incluso dirigidas a grupos distintos, no exceden el máximo. Aceptar obtiene previamente el grupo del enlace, bloquea grupo/cuenta/invitación y vuelve a comprobar secreto, pertenencia, estado, caducidad y capacidad. Salir borra solo `(grupo, actor)`; si cierra, no deja miembros y revoca enlaces como en #33. No asignar otra proyección al salir evita adquirir la FK de un segundo grupo después de bloquear la cuenta. Las propuestas cruzadas entre administradores de dos grupos deben probarse con solapamiento real, además de las carreras alta/alta y alta/salida.

Estas son decisiones de la aplicación sobre las restricciones y los [modos de bloqueo de PostgreSQL 18](https://www.postgresql.org/docs/18/explicit-locking.html), que distinguen `FOR NO KEY UPDATE` de `FOR UPDATE`. La definición de la migración y la validación JSON no sustituyen las pruebas de integridad, carreras, reintentos, selección ni aislamiento del cliente.
