# Suscripción personal y vuelta al plan gratuito

Contrato **0.5.0**, 10 de octubre de 2026, para [#39](https://github.com/JFrancoG/SmartShoppingList/issues/39). Amplía [mvp-api.md](mvp-api.md), [pertenencias](group-memberships.md) y [cupos de tiendas](store-quotas.md). [OpenAPI](openapi.json), [ejemplos](examples.json) y [aceptación](acceptance.md) deben describir la misma API. Las decisiones de esta unidad están aprobadas para implementar; este documento no acredita compra real, configuración de App Store Connect, despliegue ni activación de cobros.

## Derecho personal y autoridad

Una única suscripción premium personal, mensual o anual, concede **5 pertenencias en total, 10 tiendas activas por grupo administrado y 100 pendientes por tienda**. El plan gratuito conserva **1 grupo, 3 tiendas activas y 20 pendientes**. Los periodos ofrecen las mismas capacidades y no se suman. El plan del administrador determina tiendas y pendientes para todos los miembros; el de cada persona determina su propio acceso a grupos.

StoreKit tramita compra y restauración; el servidor decide las capacidades mediante evidencia verificada de Apple vinculada a la cuenta del servicio. Un resultado local de compra, un booleano, una fecha del dispositivo, un producto arbitrario o un token sin verificar no conceden premium. Una suscripción no se transfiere junto a la administración ni se comparte entre cuentas del servicio. La integración usa `appAccountToken` para vincular la compra a la cuenta y conserva esa vinculación durante restauraciones y renovaciones; no reasigna a quien presenta el mismo recibo con otra sesión.

La configuración de Apple, los productos permitidos y el entorno son explícitos. Un entorno de producción no acepta compras de sandbox ni StoreKit local. Sin configuración completa de compras, el servicio conserva el recorrido gratuito y comunica indisponibilidad de las compras; no inventa productos, precios ni derechos. Un derecho de producción ya verificado conserva únicamente su final previamente acreditado, sin extenderlo por ausencia de conexión o configuración. Los ejemplos del contrato contienen exclusivamente identificadores y valores sintéticos.

Los productos mensual/anual pertenecen al mismo grupo de suscripciones de Apple, de nivel equivalente, y la verificación exige su identificador configurado. Ese grupo comercial de Apple no es un grupo de compra de Smart List. Family Sharing y multiseat se mantienen desactivados en la configuración externa de esta oferta personal; la unidad no vende ni distribuye asientos compartidos. Antes de ofrecer la compra, iOS comprueba ambos productos y sus metadatos coherentes de periodo/grupo.

Las concesiones y cadenas originales se guardan con su entorno de verificación. Una instantánea de sandbox no amplía permisos en producción, tampoco al retirar la configuración de compras. El servidor sin entorno de compras usa `Production` para sus lecturas de autoridad, sin reinterpretar como reales los ensayos persistidos.

## Plazos y estados

El reloj del servidor y las fechas verificadas de Apple deciden los plazos. Se evalúan al consultar y antes de una nueva escritura, sin depender de que la app permanezca abierta ni de un cron.

| Situación verificada | Premium y cupos | Acceso a pertenencias existentes |
|---|---|---|
| Periodo premium vigente, incluso con renovación cancelada | 5/10/100 hasta el final efectivo del periodo | Uso completo. |
| Renovación en gracia de cobro de Apple vigente | 5/10/100 hasta la fecha de gracia comunicada por Apple | Uso completo. |
| Fin ordinario del derecho | 1/3/20 desde el instante del fin | Siete días de transición para organizar los grupos existentes. |
| Transición terminada | 1/3/20 | Un grupo gratuito de uso completo; adicionales restringidos. |
| Reembolso o revocación | 1/3/20 desde la pérdida verificada | Sin iniciar otra transición de siete días; se conserva la consulta y resolución de responsabilidades. |

**Cancelar la renovación no es caducar.** La transición comienza cuando termina realmente el acceso verificado, incluida una gracia de cobro vigente. No se reinicia por abrir la app, reenviar una transacción vieja, restaurar sin nueva vigencia, volver a iniciar sesión o cambiar de dispositivo. Una renovación válida recupera premium; su eventual fin ordinario usa el nuevo final efectivo.

Se acuerda configurar la gracia de Apple en **16 días para renovaciones de pago a pago** de los productos mensual/anual. Esa configuración es de App Store Connect y no se activa desde el repositorio. El servidor respeta la fecha que Apple comunica; no añade dieciséis días a una fecha caducada ni concede una gracia propia si Apple no la acredita. Sandbox tiene tiempos acelerados y no prueba una espera de dieciséis días de producción.

Los **siete días de transición** afectan al uso de los grupos que ya se tenían. Durante ellos no se crea ni se acepta una pertenencia nueva. Las tiendas y los pendientes vuelven inmediatamente a los cupos gratuitos del administrador al acabar premium: los siete días no prolongan 10/100. El contenido, las pertenencias y los responsables se conservan; cada grupo puede resolver el exceso conforme a [#37](store-quotas.md#admisión-exceso-y-traspaso).

## Elección del grupo gratuito

La elección pertenece a la cuenta en el servidor, compartida por todos sus dispositivos. Es distinta de la selección local del grupo que se está consultando. Puede elegirse antes y durante la transición; recuperar premium conserva la elección para una futura vuelta al plan gratuito.

1. Si existe una elección anterior y sigue siendo una pertenencia vigente de un grupo abierto, conservarla.
2. Si falta una válida, usar la pertenencia más antigua; los empates se resuelven por ID estable. Con ninguna pertenencia, la elección es `null`.
3. La primera elección manual puede cambiar esa asignación inicial. El fallback automático no consume esa primera decisión.
4. Un cambio manual efectivo inicia un plazo móvil de **30 días** desde el reloj del servidor. Solicitar el mismo grupo es un no-op y no renueva el plazo. El plazo no depende del mes natural ni del dispositivo.
5. Si el grupo elegido desaparece de las pertenencias por una salida válida o un cierre, se permite sustituirlo para conservar un grupo utilizable. La sustitución excepcional mantiene el registro de cambios anterior; salir, reingresar o alternar excepciones no restablece la primera elección ni borra un plazo vigente.

La elección solo acepta un grupo abierto del que se es miembro. No invita, no incorpora, no cambia la administración, no transfiere premium y no evita los cupos de tiendas/productos. La sustitución y las admisiones se coordinan por cuenta para impedir dos elecciones simultáneas o cambios concurrentes que eludan el plazo.

## Datos conservados y grupos restringidos

Todas las pertenencias continúan visibles. Un grupo adicional restringido permite consultar los datos y resolver el traspaso, la salida y el cierre según las reglas ya existentes; la restricción no obliga a pagar para abandonar ni deja un grupo sin responsable. La migración y la caducidad no eliminan entradas, tiendas ni recibos y no archivan arbitrariamente una tienda.

| Acción en un grupo adicional restringido | Resultado |
|---|---|
| Consultar grupo, miembros, administración, tiendas, pendientes y capacidad | Permitida para miembros vigentes. |
| Proponer, aceptar, rechazar o retirar traspaso; abandonar; cerrar siendo el último miembro | Permitida con la autorización y las confirmaciones existentes. |
| Revocar una invitación; archivar una tienda vacía | Permitida al administrador. |
| Cancelar un pendiente | Permitida; libera capacidad y conserva el registro. |
| Recuperar un recibo ya confirmado | Permitida bajo la autorización vigente, sin repetir la mutación. |
| Añadir, editar, confirmar una nueva compra, restaurar una tienda o crear una invitación | `409 group_access_restricted`; no aplica la mutación. |

Cancelar permite reducir el exceso sin mantener el uso ordinario de compra de todos los grupos. La restricción no afecta a los demás miembros que tengan ese grupo como gratuito o premium vigente. El administrador restringido mantiene su responsabilidad; otro miembro autorizado puede seguir comprando y los cupos compartidos siguen el plan efectivo del administrador.

Las nuevas operaciones de uso ordinario vuelven a comprobar la capacidad del solicitante. El cambio de plan no modifica una intención incierta: conservar exactamente cuenta, grupo, ruta, cuerpo y `operationId`. Un recibo confirmado se recupera con su status y sus bytes originales bajo la autorización vigente, sin reinterpretar la capacidad histórica. Un rechazo comercial confirmado exige otra intención explícita cuando cambia la capacidad; nunca se convierte automáticamente en éxito ni se borra el borrador.

## Rutas y DTO

| Ruta | Petición | Resultado |
|---|---|---|
| `GET /v1/account/subscription` | Sesión válida | `200 Subscription` con estado y catálogo permitido del servidor. |
| `POST /v1/account/subscription/transactions` | `{signedTransaction: string}` y sesión válida | `200 {subscription: Subscription, acknowledgedTransactionId: string}` tras verificar y vincular. |
| `POST /v1/account/free-group` | `{operationId: UUID, groupId: UUID}` y sesión válida | `200 AccountCapabilities`, también en no-op o replay. |
| `POST /v1/app-store/notifications` | `{signedPayload: string}` de Apple, sin bearer de usuario | `204` sin body tras verificar, persistir y reconciliar. |

`Subscription` requiere `appAccountToken: UUID`, `isConfigured: boolean`, `productIDs: [string]`, `state: free|subscribed|in_grace_period|expired|revoked`, `expiresAt`, `gracePeriodExpiresAt`, `autoRenewEnabled` y `verifiedAt`. Las fechas son `null|Timestamp`; `autoRenewEnabled` es `null|boolean`. El catálogo no incluye precios: iOS muestra el precio localizado que devuelve StoreKit. `isConfigured` indica la preparación del servidor, no disponibilidad del producto en una tienda ni aprobación comercial. `acknowledgedTransactionId` identifica la transacción enviada que el servidor ha reconocido; se compara antes de terminarla en StoreKit.

`AccountCapabilities` conserva sus campos y añade `premiumActive: boolean`, `premiumExpiresAt: null|Timestamp`, `transitionEndsAt: null|Timestamp`, `freeGroupId: null|UUID`, `freeGroupChangeAvailableAt: null|Timestamp` y `canChangeFreeGroup: boolean`. `transitionEndsAt` es `null` mientras premium sigue activo; no se usa la fecha prevista de una futura caducidad como transición en curso. `canCreateGroup` y `canJoinGroup` son `false` durante la transición, incluso si se sale de todas las pertenencias; fuera de ella comprueban el máximo personal. Un plazo de cambio puede seguir constando aunque una sustitución excepcional sea posible.

Las consultas nuevas de `Group` incluyen `capabilities: {canUseShopping: boolean, isFreeGroup: boolean}`. `isFreeGroup` identifica la elección de la cuenta, no el grupo seleccionado en el dispositivo ni el plan del administrador. `canUseShopping` distingue uso ordinario de consulta/resolución de responsabilidades. La ausencia en un recibo histórico o caché antigua es desconocimiento; el cliente consulta autoridad nueva antes de habilitar acciones. Las capacidades de tienda y `/capacity.canCreateStore` incorporan también el acceso del solicitante: disponer de hueco no concede acceso ordinario al grupo.

Elegir grupo gratuito tiene recibo propio por cuenta, ruta, cuerpo e identidad. Un `409 free_group_change_cooldown` confirmado se conserva aunque pasen treinta días; para volver a elegir se confirma otra intención. La respuesta histórica de elección no se instala como permisos actuales: iOS refresca `/me` y grupos. La importación de Apple usa identidad de transacción y cadena original verificadas para deduplicar compras y renovaciones; no simula una intención de compra mediante un `operationId` de la aplicación.

| Status y código | Significado |
|---|---|
| `400 invalid_app_store_transaction` | Evidencia mal formada, firma, aplicación, entorno o producto no aceptados. No concede derecho. |
| `400 invalid_app_store_notification` | Notificación V2 no verificable o de otra aplicación/entorno. |
| `403 transaction_account_mismatch` | El vínculo de cuenta de Apple no corresponde a la sesión. |
| `409 transaction_already_bound` | La cadena original ya pertenece a otra cuenta y no puede reasignarse. |
| `409 free_group_change_cooldown` | Cambio manual de grupo antes de completar treinta días. |
| `409 group_access_restricted` | Nueva intención ordinaria en un grupo adicional restringido. |
| `503 subscription_unavailable` | Configuración o comprobación temporalmente indisponibles; no se presenta como compra rechazada ni éxito. |

Se conserva el sobre `{code, message, requestId}` y los errores generales. Un grupo ajeno, cerrado o del que se salió no se revela al elegirlo. Los códigos `409` de elección y acceso son definitivos cuando proceden de una operación idempotente nueva. La respuesta perdida, un error de transporte o una indisponibilidad conserva la identidad original y el borrador.

La importación de transacciones y las notificaciones consultan el estado actual en App Store Server API después de verificar la evidencia. La llegada de una transacción histórica no acredita que siga vigente. Las notificaciones se deduplican por identidad verificada y una entrega duplicada o fuera de orden no restaura un estado antiguo. `204` reconoce solo un procesamiento durable; `503 subscription_unavailable` deja el reintento pendiente. No se escriben JWS, claves, bearer ni datos Apple de cuenta en logs.

## Persistencia y migración

Se añade elección gratuita y fecha de cambio a la cuenta, y una instantánea de acceso por cuenta/entorno. Las cuentas existentes empiezan sin concesión comercial; su fallback usa las pertenencias ya guardadas y conserva identidad, roles, tiendas, entradas y recibos. Las cadenas originales y notificaciones se conservan en tablas de verificación específicas; ninguna compra modifica directamente miembros ni cambia el responsable de un grupo.

Las escrituras de grupo mantienen **grupo → cuenta del actor → recurso**. La elección bloquea el grupo destino antes de la cuenta; la importación de derechos bloquea primero el conjunto estable de grupos administrados, ordenado por ID, y después la cuenta. Si ese conjunto cambia mientras espera, libera y reintenta desde el principio; no adquiere después otro grupo. La exclusividad de una cadena y su actualización durable deben coordinar todas sus vías de entrada. No se mantienen contadores comerciales independientes del contenido.

Revertir no puede descartar elecciones, historial del plazo, concesiones o vínculos de transacciones/notificaciones que no admite el esquema anterior. Las guardas comprueban datos y DDL bajo el mismo bloqueo y transacción; rechazan un estado no representable sin borrar ni reactivar contenido. Un ensayo con base vacía no prueba reversión fiel de una base con derechos existentes. Desplegar cliente, migraciones, notificaciones y oferta comercial sigue siendo una secuencia separada.

## Configuración, promociones y evidencia

El precio, los identificadores reales de los productos, acuerdos fiscales/bancarios, aprobación comercial y configuración de notificaciones se completan antes de activar cobros. La inscripción en Small Business corresponde al titular de la cuenta Apple; no es una condición para implementar el recorrido y no se presupone aprobada por enviar una solicitud.

Los regalos de tres o seis meses y sus destinatarios siguen pendientes de decisión comercial. Esta unidad no concede derechos manuales, no crea campañas por fecha de descarga y no distribuye códigos. Un futuro regalo verificado podrá usar la misma frontera de derechos sin introducir un interruptor premium de confianza del cliente.

La evidencia de implementación debe distinguir pruebas automatizadas con evidencia sintética, StoreKit local, sandbox de Apple y producción. Ninguna de las tres primeras prueba cobros reales, notificaciones activadas o disponibilidad comercial.

## Fuentes oficiales consultadas

- [StoreKit `appAccountToken`](https://developer.apple.com/documentation/storekit/transaction/appaccounttoken): vínculo entre transacción y cuenta del servicio.
- [App Store Server API: estado de suscripciones](https://developer.apple.com/documentation/appstoreserverapi/get-all-subscription-statuses): consulta de estados actuales, incluida gracia de cobro.
- [Notificaciones App Store V2](https://developer.apple.com/documentation/appstoreservernotifications/responsebodyv2decodedpayload): evidencia firmada, identidad y fecha del evento.
- [Configurar Billing Grace Period](https://developer.apple.com/help/app-store-connect/manage-subscriptions/enable-billing-grace-period-for-auto-renewable-subscriptions): duración, pago a pago, entornos y ensayo previo en sandbox.
