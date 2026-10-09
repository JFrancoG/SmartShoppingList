# Cupos de tiendas y productos pendientes

Contrato **0.4.0**, 10 de octubre de 2026, para [#37](https://github.com/JFrancoG/SmartShoppingList/issues/37). Amplía [mvp-api.md](mvp-api.md), [pertenencias](group-memberships.md) y [administración](group-administration.md). [OpenAPI](openapi.json), [ejemplos](examples.json) y [aceptación](acceptance.md) describen la misma API. Define comportamiento implementable; no acredita pruebas ejecutadas, migración desplegada ni pagos disponibles.

## Titularidad y valores

| Plan personal | Pertenencias por cuenta | Tiendas activas por grupo administrado | Entradas pendientes por tienda |
|---|---:|---:|---:|
| Gratuito | 1 | 3 | 20 |
| Premium | 5 | 10 | 100 |

Los grupos consumen el cupo personal de quien se incorpora, tanto si administra como si es miembro. Las tiendas y sus pendientes usan el plan del administrador actual del grupo y todos sus miembros comparten esa capacidad. Recibir la administración de un grupo al que ya se pertenece no consume otra plaza. El premium de otro miembro no amplía el grupo y el premium de su administrador no concede pertenencias adicionales a los invitados.

Una cuenta gratuita puede recibir y previsualizar enlaces a otros grupos. Aceptar uno adicional responde `409 group_limit_reached` sin consumirlo; si posteriormente queda plaza, el mismo enlace puede aceptarse mientras siga válido. El enlace no reserva capacidad, no amplía su caducidad ni constituye otra pertenencia. Aceptar un enlace libre al propio grupo conserva la excepción sin consumo de plaza de #35. La app conserva una invitación pendiente según el flujo existente; esta unidad no crea una bandeja de invitaciones.

Se prepara una única suscripción personal, cuya compra y verificación pertenecen a la siguiente unidad. En esta entrega el proveedor de producción devuelve el plan gratuito. Las pruebas pueden inyectar planes premium por cuenta mediante una frontera confiable del servidor; no hay un booleano enviado por iOS, una compra simulada en producción ni una variable pública que conceda derechos.

Una tienda activa cuenta aunque esté vacía. Una archivada no cuenta. Cada fila `pending` cuenta una vez: «6 botellas» sigue siendo una entrada, y dos IDs con igual nombre cuentan dos. `purchased` y `cancelled` no cuentan. El borrador local no consume cuota. Se conservan los límites técnicos independientes: 50 entradas por operación, 100 por página, 128 KiB por petición y los máximos de nombres.

## Consultas y DTO

`GET /v1/groups/{groupId}/capacity` requiere pertenencia vigente a un grupo abierto y devuelve `200`:

```json
{
  "groupId": "00000000-0000-4000-8000-000000000010",
  "capacityOwnerUserId": "00000000-0000-4000-8000-000000000001",
  "activeStoreCount": 2,
  "limits": {
    "storesPerGroup": { "maximum": 3, "enforced": true },
    "pendingItemsPerStore": { "maximum": 20, "enforced": true }
  },
  "canCreateStore": true
}
```

Todos los campos son requeridos. `canCreateStore` significa que queda plaza para una tienda realmente nueva; no crea una ruta de alta independiente ni otorga administración. Cualquier miembro puede crearla mediante los flujos de incorporación o cambio de tienda existentes. Los conteos admiten exceso sobre el máximo; no se recortan para simular cumplimiento. El máximo personal de grupos sigue en `/me.accountCapabilities`; `/administration.capabilities.limits` conserva las tres dimensiones y publica los mismos límites compartidos efectivos. La política se evalúa a partir del administrador vigente una vez por operación; las capacidades son informativas y se revalidan al escribir.

`GET /v1/groups/{groupId}/stores` conserva `{stores: [Store], nextCursor: null|string}` y añade `state=active|archived`, opcional y con valor por defecto `active`. El filtro forma parte del ámbito del cursor: uno de activas no sirve para archivadas. Conserva orden `(stores.created_at, stores.id)`, límites y ausencia de snapshot entre páginas. Los miembros pueden consultar ambos estados. No se mezclan archivadas en los selectores de compra, alta o búsqueda por voz.

`Store` conserva `id`, `groupId` y `name`, y añade los campos requeridos:

```text
archivedAt: null | Timestamp
pendingItemCount: entero >= 0
capabilities: {
  canAddItems: boolean,
  canArchive: boolean,
  canRestore: boolean
}
```

- `canAddItems`: tienda activa y número de pendientes menor que el máximo compartido. Solo expresa posibilidad de crecimiento; no bloquea edición de nombre/cantidad, compra o cancelación. No depende de que el grupo pueda crear más tiendas.
- `canArchive`: solicitante administrador, tienda activa y cero pendientes.
- `canRestore`: solicitante administrador, tienda archivada y plaza para otra activa.

Una tienda archivada tiene cero pendientes por la regla de transición. `GET .../stores/{storeId}/items` sigue respondiendo `200` con página vacía para esa tienda accesible. No se añade una consulta de historial, reapertura automática ni eliminación de productos.

## Archivo y restauración

| Método y ruta bajo `/v1/groups/{groupId}` | Petición | Respuesta |
|---|---|---|
| `POST /stores/{storeId}/archive` | `{operationId: UUID}` | `200 Store` |
| `POST /stores/{storeId}/restore` | `{operationId: UUID}` | `200 Store` |

Una intención nueva requiere administración vigente. Archivar comprueba cero pendientes y asigna `archived_at` con el reloj del servidor. No cambia ID, grupo, nombre, clave normalizada, fecha de creación ni productos históricos. Restaurar comprueba una plaza libre y pone `archived_at = NULL` sobre la misma fila. La unicidad `(group_id, normalized_key)` incluye activas y archivadas: no se puede crear otra tienda con el mismo nombre normalizado para eludir la restauración.

Archivar una tienda ya archivada o restaurar una ya activa devuelve `200` sin modificarla ni renovar fechas. Este último caso no consume una plaza y no se rechaza por un exceso existente. Las capacidades describen acciones que cambian estado; ese no-op no obliga a presentar un botón redundante.

Una referencia `store.id` archivada o `store.newName` que coincide con una archivada devuelve `409 store_archived`. No la restaura, duplica ni añade pendientes implícitamente. La persona debe restaurarla expresamente mediante el administrador y confirmar después una nueva intención de alta o traslado. Un ID inexistente o ajeno conserva `404 not_found`, sin revelar datos de otros grupos.

## Admisión, exceso y traspaso

Antes de escribir un lote se resuelven IDs y nombres normalizados, se agrupan las entradas por tienda final y se calculan las tiendas realmente nuevas y los pendientes proyectados. Nombres equivalentes de un mismo lote consumen una sola tienda; cada entrada consume un pendiente. Se comprueba todo antes del primer INSERT. Si cualquier destino excede su límite, se rechaza la operación entera, sin tiendas huérfanas, productos parciales ni eliminación de borradores. Dividir un lote no elude el límite acumulado.

Editar en la misma tienda no aumenta su consumo, incluso si ya está excedida. Mover una entrada a otra tienda exige que el destino activo admita esa entrada; si hay que crear la tienda, exige también plaza de tienda. El decremento del origen y el incremento del destino se confirman juntos. El traslado no archiva automáticamente la tienda que queda vacía. Comprar o cancelar reduce pendientes y conserva el historial.

La migración y un cambio de administrador o plan pueden dejar uso superior al máximo. No se eliminan pertenencias, tiendas o productos, ni se elige qué archivar. Se bloquea exclusivamente el crecimiento de la dimensión afectada: superar tiendas no impide añadir a una activa que aún tenga capacidad de pendientes; superar pendientes no impide consultar, comprar, cancelar o corregir sin crecimiento. Restaurar aumenta tiendas activas y exige plaza. El traspaso a un miembro con menor capacidad sigue permitido, sin transferir la suscripción personal ni exigir un pago para aceptar o salir.

Antes de proponer y aceptar un traspaso, la app explica que la capacidad compartida pasa a depender del nuevo administrador, que los datos se conservan y que un exceso limita nuevas altas. No se añade un DTO predictivo del derecho futuro del destinatario. Tras confirmar se consultan de nuevo administración, capacidad y tiendas. La política comercial para pérdida de pertenencias premium, gracia y selección de un grupo gratuito sigue pendiente de pagos; #37 conserva las pertenencias y la regla de admisión de #35.

## Errores y recibos

Los nuevos códigos usan el sobre existente `{code, message, requestId}`:

| Status y código | Significado |
|---|---|
| `409 store_limit_reached` | Crear o restaurar otra tienda excedería el máximo activo del grupo. |
| `409 pending_item_limit_reached` | Añadir o mover pendientes excedería el máximo de al menos una tienda destino. |
| `409 store_archived` | Alta o traslado referencia una tienda archivada por ID o nombre normalizado. |
| `409 store_not_empty` | Se intenta archivar una tienda con pendientes. |
| `403 administrator_required` | Nueva intención de archivo/restauración de un miembro sin administración. |

Estos `409` son rechazos definitivos y se guardan con el recibo de la intención, igual que `group_limit_reached` al crear un grupo. Liberar capacidad, vaciar o restaurar una tienda no transforma ese recibo en éxito: una nueva confirmación explícita genera otro `operationId`. La persona conserva el borrador o la corrección propuesta. No se cambia una clave con resultado todavía incierto ni se reintenta automáticamente como una intención nueva.

Un éxito confirmado conserva exactamente status y body aunque la tienda se archive después, cambie su estado, se reduzca el límite o cambie el administrador. Replay requiere la misma cuenta y pertenencia vigente al grupo abierto, pero no vuelve a exigir rol de administrador, cupo ni estado actual para una escritura ya confirmada. La comprobación de pertenencia y del recibo precede a las restricciones de la nueva mutación. Conserva la excepción mínima de salida propia de #33. Un recibo de archivo/restauración es histórico: iOS refresca y no instala su Store como estado vigente.

## Migración, coordinación y compatibilidad

La migración añade `stores.archived_at` nullable; todas las tiendas anteriores quedan activas, incluso si el grupo excede el límite gratuito. Conserva IDs, nombres, normalización, fechas, referencias de productos y bytes de recibos. No añade contadores persistidos. Revertir exige comprobar bajo bloqueo, en la misma transacción del DDL, que no hay tiendas archivadas: eliminar esa columna no puede reactivarlas silenciosamente.

Todas las escrituras conservan el orden **grupo → cuenta del actor → recurso**, con `FOR NO KEY UPDATE` para la cuenta. La fila del grupo serializa altas de distintos miembros, movimientos, compras/cancelaciones, archivo/restauración y traspasos; conteo y escritura ocurren bajo ese mismo bloqueo. Un rechazo persistido no puede confirmar INSERTs provisionales ejecutados durante la resolución de tiendas: el preflight es de lectura. La autoridad de planes es del servidor y una integración futura de pagos deberá coordinar sus cambios con este protocolo.

Los campos nuevos son aditivos para lectores anteriores y los listados por defecto solo muestran activas. Sin embargo, los clientes 0.3 no reconocen los cuatro códigos `409` y pueden tratarlos como resultado incierto: requieren actualización para gestionar y resolver esos rechazos. No se afirma compatibilidad funcional completa por añadir campos. El cliente 0.4 reconoce los códigos como definitivos; una caché antigua sin capacidades de tienda queda como información desconocida, sin conceder nuevas acciones. Un servidor anterior sin `/capacity` tampoco acredita cuota vigente. Los sobres pendientes existentes conservan cuenta, grupo, destino y clave; los éxitos históricos siguen recuperándose sin reescribir sus cuerpos.

El despliegue del servidor y la migración, la distribución del cliente y la activación futura de pagos son pasos distintos. La evidencia de compilación, pruebas de PostgreSQL, carreras y recorridos iOS se registra en la issue y su informe de validación; los ejemplos y el validador estructural no sustituyen esas comprobaciones.
