# Contrato técnico del MVP

Versión **0.2.0**, 9 de octubre de 2026. Unidades: contrato original [#2](https://github.com/JFrancoG/SmartShoppingList/issues/2) y administración transferible [#33](https://github.com/JFrancoG/SmartShoppingList/issues/33). Alcance funcional: [spec, secciones 2–6](../mvp-spec.md). Este contrato define lo que implementarán cliente y servidor; no acredita endpoints disponibles ni pruebas de colaboración ejecutadas.

## Cómo utilizarlo

- Este documento fija las reglas de identidad, integridad, transacciones y recuperación.
- [group-administration.md](group-administration.md) concreta administración transferible, salida, cierre y capacidades; conserva una pertenencia por cuenta en esta entrega.
- [openapi.json](openapi.json) fija rutas, tipos JSON, límites estructurales, autorización y respuestas HTTP. Usa OpenAPI 3.2.1 y JSON Schema 2020-12.
- [examples.json](examples.json) contiene peticiones y respuestas de referencia, además de entradas estructuralmente inválidas. Los UUID, dominios `.example`, códigos Apple y secretos son ficticios. Los casos son escenarios independientes salvo los pares de reintento nombrados; no son una secuencia de llamadas contra un servidor.
- [acceptance.md](acceptance.md) describe la evidencia de comportamiento que deberá aportar la implementación. Validar JSON no demuestra transacciones, autorización ni idempotencia.

El contrato concreta parámetros técnicos que la spec dejaba abiertos: invitaciones de 24 horas, propuestas de administración de siete días, sesión de 30 días, lotes y selecciones de hasta 50 productos. La finalización es atómica para toda la selección: si uno cambió, se devuelve conflicto y se revisa antes de confirmar.

## Transporte y convenciones

API bajo `/v1`, HTTPS, cuerpos `application/json` en UTF-8. El dominio real de API y enlaces se fijará en #4; `.example` no es un entorno. Tamaño máximo de body: **128 KiB**, antes de decodificar. Una propiedad desconocida se rechaza, para detectar discrepancias de contrato; no se aplica un cambio parcial ignorando campos.

Los UUID se transmiten en minúsculas con guiones. El servidor genera los IDs persistentes; el cliente genera un UUID nuevo para cada intención de escritura idempotente (`operationId`). Las fechas son RFC 3339 en UTC con sufijo `Z`, admitiendo fracciones de segundo; el reloj del servidor determina caducidad y compra. `version` empieza en 1, aumenta en cada cambio confirmado y no supera 2^53−1, dentro de un `BIGINT` de PostgreSQL. Todos los campos requeridos y los `null` se especifican en OpenAPI; cantidad ausente se representa con `quantity: null`.

| Entrada | Límite |
|---|---|
| Nombre de producto nuevo o editado | 1–60 puntos de código Unicode recibidos y tras normalizar |
| Nombre de tienda nueva | 1–40 puntos de código Unicode recibidos y tras normalizar |
| Nombre de grupo | 1–80 puntos de código Unicode recibidos y tras normalizar |
| Nombre visible de usuario | 1–160; nombre visible opcional |
| Cantidad literal | `null` o 1–80; no se transforma en una unidad inventada |
| Lote confirmado / selección de compra | 1–50 entradas |
| Página de consulta | 50 por defecto; 1–100 solicitado |
| Nonce, token de sesión, secreto de invitación | 32 bytes aleatorios criptográficos; 43 caracteres base64url sin padding |

Primero se comprueba el límite de transporte y de cada string recibido; después se normaliza y se rechazan nombres vacíos o fuera del límite. Los límites cuentan puntos de código, no bytes ni `String.count` de grafemas de Swift. Normalización de nombres: NFC, recortar espacios Unicode externos y reducir cada secuencia interna de espacios Unicode a un espacio ASCII. Rechazar controles no espaciales. Preservar acentos, mayúsculas y calificativos como «sin lactosa». No reinterpretar texto confirmado.

La cantidad literal sigue la misma normalización de espacios/NFC; si no existe se envía `null`, no texto vacío o solo espacios. El cliente muestra los límites antes de confirmar: no corta ni divide automáticamente un lote o una selección mayor de 50, porque eso cambiaría la unidad atómica confirmada.

### Compatibility with names saved before version 0.1.1

The 60-scalar product and 40-scalar store limits apply to new writes, including edits. Existing product names up to 160 scalars and store names up to 80 scalars remain unchanged in storage and responses; no migration or truncation is performed. Existing stores can still be referenced by ID, and existing products can be purchased or cancelled without renaming them.

An exact replay of an operation already committed under the earlier limits returns its original receipt. The server therefore parses the historical 160/80 envelope, authorizes membership, checks the operation fingerprint and receipt, and only then validates 60/40 before a new write. Both received and normalized lengths are checked. A request above the current limits with a new operation ID is rejected without retaining a receipt or creating stores/items. Unconfirmed old submissions must be corrected before creating a new intent. OpenAPI request schemas describe new writes; response schemas retain the historical bounds for saved data and recovered receipts.

### Tiendas y ambigüedad

Una tienda pertenece a un grupo. El cliente consulta tiendas reales y muestra su nombre; la voz/IA solo ayuda a encontrar candidatas. Si faltan datos o hay varias coincidencias, la persona elige antes del envío. `store` acepta exclusivamente `{ "id": UUID }` o `{ "newName": "Nombre confirmado" }`. Un ID ajeno se rechaza; no se convierte en una nueva tienda.

El backend mantiene `normalized_key`: normalización anterior y *Unicode Default Case Folding*, independiente de la configuración regional, volviendo a NFC. No elimina diacríticos ni puntuación y no hace coincidencia difusa. La implementación del servidor es la autoridad de esta clave; el cliente no envía ni reproduce claves persistentes. La versión de normalización usada se mantiene estable para los datos y se revisa explícitamente si cambia el runtime.

| Nombres | Resultado |
|---|---|
| ` Mercadona `, `MERCADONA` | Misma clave; reutilizar ID, conservar el nombre visible existente |
| `Mercadona   Centro`, `mercadona centro` | Misma tienda |
| `Día` precompuesto / la misma secuencia descompuesta | Misma tienda tras NFC |
| `Día`, `Dia` | Distintas claves; la app puede proponerlas, debe pedir elección |
| `Mercadona Centro`, `Mercadona Norte` | Tiendas distintas |

Si `newName` coincide exactamente por clave con una tienda existente, se reutiliza dentro de la transacción. Dos altas simultáneas de esa tienda no crean dos IDs. No existe catálogo global ni fusión, renombrado o borrado de tiendas en este contrato. Un lote puede contener tiendas distintas, cada una confirmada explícitamente. Editar un pendiente puede cambiar su tienda e incrementa su versión.

## Identidad y sesión

### Acceso nativo con Apple

1. `createChallenge` entrega `id`, nonce y caducidad a cinco minutos. El servidor conserva temporalmente el nonce y el estado del intento para proporcionar el valor esperado a su verificador; no acepta un `expectedNonce` elegido junto al token. El nonce no es un bearer: se restringe su acceso, no se registra en logs y se borra al terminar o caducar el intento.
2. La app genera un `state` aleatorio por intento, conserva el challenge y envía **exactamente** el nonce recibido en la solicitud Apple, sin aplicar otro hash. Comprueba el `state` devuelto antes de enviar credenciales al backend.
3. `loginWithApple` recibe `challengeId`, ID token nativo y `authorizationCode`. El backend reclama el challenge mediante transición atómica de disponible a en proceso, comprobando su caducidad. Solo una petición puede canjearlo. Nunca mantiene una transacción de base de datos abierta durante la llamada a Apple.
4. Verifica firma con las claves oficiales de Apple, algoritmo permitido, `iss`, `aud`, `exp`, sujeto no vacío y nonce contra el challenge almacenado. Se reutiliza la base validada en #1; aquellos tests con claves ficticias no acreditan un login real.
5. Canjea el código en `https://appleid.apple.com/auth/token`, con `grant_type=authorization_code`, `client_id` y `client_secret`. El formulario no incluye `nonce`. Para este cliente nativo, `client_id` es **`com.plusprojects.SmartShoppingList`**, verificado en el proyecto Xcode; no es el Team ID ni un Services ID web.
6. Verifica también el ID token devuelto por el canje: firma/claims/nonce esperado y el mismo `sub` que el token nativo. Solo entonces crea o recupera al usuario por el sujeto estable de Apple y emite una sesión propia.

**Prueba técnica pendiente en #4:** exigir el nonce en el ID token del canje es una decisión de vinculación de este contrato, no una garantía específica del canje que se haya encontrado explícita en la documentación. Debe comprobarse con SIWA nativo real antes de activar este flujo. Si Apple no lo devuelve, se revisará el vínculo criptográfico y el contrato; no se omitirá la comprobación silenciosamente ni se considerará suficiente comparar solo `sub`.

El código Apple es de un solo uso. Una vez reclamado el challenge no vuelve a disponible; un fallo, timeout o caída durante el canje requiere un challenge nuevo y otro acceso con Apple. Tampoco se reproduce una respuesta de login perdida almacenando bearer tokens en claro. La app conserva la invitación pendiente. Los intentos en proceso abandonados terminan como consumidos, sin sesión utilizable por un segundo envío.

`displayName` es una etiqueta opcional no confiable, útil si Apple la facilita en el primer acceso. No identifica ni autoriza; su ausencia posterior no borra el nombre guardado. No se usa email para emparejar cuentas o destinatarios. El `sub` no se expone en la API de la app.

### Sesión propia y revocación

La respuesta de login incluye bearer opaco y vencimiento absoluto a **30 días**. PostgreSQL guarda únicamente su hash SHA-256 y su vínculo con usuario/concesión Apple; nunca el bearer en logs, URLs o recibos de operaciones. La app lo conserva en Keychain con `WhenUnlockedThisDeviceOnly`. El ID token de Apple no funciona como bearer de esta API. No hay endpoint de renovación de la sesión propia; al caducar se inicia SIWA de nuevo.

Cada concesión conserva el refresh token de Apple **cifrado y recuperable**, porque el servidor debe enviarlo a Apple; un hash no serviría. Antes de autorizar una petición, si han pasado 24 horas desde la última validación satisfactoria, revalida esa concesión con Apple mediante `grant_type=refresh_token`. Peticiones concurrentes de la concesión comparten la comprobación. Se persiste cualquier refresh token rotado. Esta comprobación valida la concesión; no repite el challenge ni el canje de código de un solo uso.

`invalid_grant` revoca esa concesión y sus sesiones propias. Errores de transporte o indisponibilidad producen `503`, preservan credenciales y permiten reintentar con espera progresiva; no conceden acceso mientras esa revalidación requerida siga pendiente. Una revalidación no prolonga los 30 días. El intervalo es una política propia del MVP, no una obligación diaria impuesta por Apple. No necesita cron ni webhooks; queda una ventana de hasta 24 horas para detectar cambios de Apple, mientras la revocación local es inmediata.

`logout` revoca la sesión presentada y borra el token local una vez confirmado; no borra la cuenta ni revoca todas sus sesiones. Para un bearer bien formado ya caducado, revocado o desconocido, devuelve `204`, sin necesidad de revalidar Apple. Si falla la red, la app no afirma haber revocado la sesión en el servidor. Una sesión vigente y no revocada se comprueba en **cada** operación, junto con la pertenencia actual antes de datos compartidos o reproducción de recibos.

Configuración necesaria en #4: capacidad Sign in with Apple y App ID compatibles; Team ID, Key ID y clave `.p8` exclusivamente en backend para firmar `client_secret` ES256 con vigencia aceptada por Apple; almacenamiento cifrado y clave de cifrado fuera de PostgreSQL/Git; audiencia exacta, fuente JWKS de Apple y entorno HTTPS. No se crean credenciales ni se contrata alojamiento en este bloque.

## Grupo e invitaciones

Un usuario tiene `group_id` nulo o un único grupo en esta entrega. `createGroup` bloquea la fila del usuario y crea grupo/asignación en una transacción. `creatorUserId` conserva la autoría histórica; `administratorUserId` identifica al administrador vigente, que debe ser miembro del grupo abierto y gestiona invitaciones. El creador no conserva permisos por haber creado el grupo. Un miembro puede consultar y modificar los productos compartidos. Un UUID conocido no concede acceso.

La administración se propone a otro miembro y requiere su aceptación antes de cambiar el cargo. El anterior administrador permanece como miembro hasta salir por separado. La salida del administrador con otros miembros exige traspaso; la del último miembro exige confirmación de cierre lógico, conserva datos y termina el acceso. Las rutas, capacidades y reintentos exactos se definen en [administración de grupo](group-administration.md). El primer grupo sigue disponible sin premium; tiendas y pendientes publican cuotas comerciales inactivas (`maximum: null`, `enforced: false`), sin prometer uso ilimitado ni activar cobro.

Crear una invitación devuelve su UUID público, metadatos y enlace **una sola vez**:

```text
https://links.smartshoppinglist.example/invite/<invitationId>#token=<secret>
```

Se guarda solo el hash del secreto, con caducidad **24 horas** desde la creación. La creación no garantiza idempotencia: si la respuesta se pierde, el administrador puede listar metadatos, revocar invitaciones no identificadas y crear otro enlace. No se reconstruye el secreto desde el hash. Listar nunca devuelve secretos; no se almacena un enlace en los recibos de mutaciones.

El fragmento no se transmite en la petición HTTP de la página de aterrizaje; no convierte el enlace en un secreto protegido de quien pueda copiarlo. La app acepta únicamente el origen HTTPS configurado, la ruta exacta y un único parámetro `token` de formato válido. Conserva ID/secreto pendientes en Keychain durante SIWA, sin logs, analítica ni restauración insegura de UI. Un fallo transitorio conserva el enlace; aceptar, descartar explícitamente o confirmar invalidez terminal elimina el pendiente.

El dominio publica AASA para el App ID `TeamID.com.plusprojects.SmartShoppingList` y ruta `/invite/*`, sin excluir el fragmento. La app configura Associated Domains y `onOpenURL`. Sin app instalada la página informa de la necesidad de instalarla; su GET no revela grupo ni consume nada. El fragmento y la entrega por Mail/Mensajes requieren prueba real en #4; no hay flujo web de incorporación ni incorporación automática posterior a instalación.

`previewInvitation` y `acceptInvitation` exigen sesión. Envían el secreto en el body; primero verifican su hash, después revelan estado/nombre. Para ID inexistente o secreto incorrecto responden el mismo `404 not_found`. Con secreto correcto:

| Estado | Vista previa / aceptación |
|---|---|
| Válida, sin consumir | Preview muestra nombre y vencimiento, sin escritura; aceptar asigna grupo y consume |
| Consumida por ese usuario, que sigue en el grupo | `200` con el mismo grupo; preview indica `alreadyAccepted: true`, incluso tras vencer |
| Consumida por otro | `410 invitation_consumed` |
| Revocada / caducada | `410 invitation_revoked` / `410 invitation_expired` |
| Usuario ya en un grupo por otra operación | Preview válido puede mostrar el nombre; aceptar devuelve `409 already_in_group`, sin consumo ni traslado |

Aceptar obtiene previamente el grupo de la invitación sin bloquear y adquiere los bloqueos en orden **grupo → cuenta del actor → invitación**. Vuelve a comprobar secreto, grupo abierto, estado, pertenencia y caducidad **después** de adquirir los bloqueos. Asignación y consumo se confirman juntos. Dos aceptantes no ganan la misma invitación. Revocar compite con aceptar sobre la misma fila: gana la primera transición confirmada. Revocar de nuevo devuelve `204`; revocar una consumida da `409 invitation_consumed` y no expulsa a su miembro. El administrador no puede revocar enlaces de otro grupo. Un grupo cerrado responde `404 not_found` al previsualizar o aceptar, sin revelar su nombre ni permitir reincorporarse.

## Datos persistentes e integridad

Modelo lógico del contrato; no acredita ejecución de migraciones. La evolución de #33 se define en [administración de grupo](group-administration.md#transacciones-recuperación-y-migración). Claves UUID, fechas con zona (`timestamptz`) y restricciones además de autorización en el servicio.

| Entidad | Campos y restricciones esenciales |
|---|---|
| `users` | `id`, `apple_subject UNIQUE NOT NULL`, `display_name?`, `group_id? FK groups`, `created_at`. Un solo campo de grupo evita pertenencias múltiples. |
| `groups` | `id`, `name`, `creator_user_id FK users` inmutable y sin unicidad, `administrator_user_id?`, `closed_at?`, `created_at`. Grupo abierto exige administrador miembro; cerrado no mantiene administración activa. FK de administrador/pertenencia diferida hasta commit para crear y asignar en una transacción. |
| `group_administration_transfers` | `id`, `group_id`, `proposer_user_id`, `recipient_user_id`, `status`, `created_at`, `expires_at`, `resolved_at?`. Como máximo una propuesta pendiente por grupo; proponente y destinatario distintos. Estados y validez descritos en administración de grupo. |
| `stores` | `id`, `group_id FK groups`, `name`, `normalized_key`, `created_at`; UNIQUE `(group_id, normalized_key)` y `(group_id, id)`. |
| `items` | `id`, `group_id`, `store_id`, `name`, `quantity?`, `status`, `version`, `created_by FK users`, `created_at`, `purchased_by? FK users`, `purchased_at?`. FK compuesta `(group_id, store_id)` a tiendas. |
| `invitations` | `id`, `group_id`, `secret_hash UNIQUE`, `created_at`, `expires_at`, `revoked_at?`, `accepted_by?`, `accepted_at?`. Aceptante/fecha presentes juntos; revocada y aceptada son estados mutuamente excluyentes. |
| `auth_challenges` | `id`, nonce temporal, `expires_at`, estado disponible/en proceso/consumido, fechas. Reclamo atómico; un intento no vuelve a disponible. |
| `apple_grants` | `id`, `user_id`, refresh token cifrado, identificador de versión de clave de cifrado, `last_validated_at`, `revoked_at?`. Vincular la revocación a la concesión comprobada. |
| `app_sessions` | `id`, `user_id`, `apple_grant_id`, `token_hash UNIQUE`, `created_at`, `expires_at`, `revoked_at?`. Hash y concesión no salen en respuestas. |
| `mutation_receipts` | UNIQUE `(user_id, operation_id)`, tipo/ruta/grupo, huella del DTO canónico, status/body del resultado, `created_at`. Recibo y escritura confirmados en la misma transacción. |

`items.status` solo admite `pending`, `purchased`, `cancelled`. Una restricción exige comprador/fecha cuando está comprado y ambos `NULL` en los otros estados. Autor y fecha de creación son inmutables; no se aceptan desde el body del cliente. El servicio y las FK impiden cruzar grupos; las FK por sí solas no autentican al solicitante. No borrar por cascada entradas confirmadas. Índices de consulta `(group_id, store_id, status, created_at, id)` y de cada FK operativa.

No se crea una tabla de catálogo de productos ni de cada edición. El registro comprado conserva producto, cantidad, tienda, autor, fecha de alta, comprador y fecha de compra. Cancelar no es comprar; ambos estados son terminales. Una nueva necesidad crea una nueva fila, aunque su texto coincida. No hay deduplicación semántica ni unicidad por nombre/cantidad.

## Escrituras, concurrencia y recuperación

### Operaciones idempotentes

Usan `operationId`: crear grupo, añadir lote, editar, cancelar, finalizar compra, proponer/aceptar/rechazar/retirar administración y salir del grupo. Aceptar/revocar invitaciones y logout tienen reintento definido por su propia transición; login y crear invitación tienen las excepciones descritas arriba.

1. Autorizar sesión y acceso vigente al grupo abierto de la ruta. Para crear grupo se autoriza identidad y se busca primero el recibo, antes de rechazar una pertenencia resultante de esa misma creación; reproducir ese recibo también exige acceso vigente al grupo del resultado. Los recibos de creación anteriores a 0.2.0 pueden omitir `administratorUserId` y conservan su cuerpo original; eso no autoriza gestión. La única excepción de pertenencia es recuperar el recibo mínimo de salida propia: misma cuenta autenticada, ruta, operación y huella exactas, sin devolver datos del grupo.
2. Validar estructura, normalizar texto y construir representación canónica del DTO: tipo de operación, ruta con IDs, grupo y todos sus valores. Claves JSON ordenadas, UUID normalizados, opcionales representados explícitamente, sin números fraccionarios. La selección se ordena por ID; se rechazan IDs repetidos, aunque sus versiones difieran. El orden de las entradas de un lote se conserva. No incluir bearer ni `operationId` en la huella; este último identifica el recibo.
3. Reservar UNIQUE `(user_id, operation_id)` dentro de la transacción. Una llamada concurrente espera el resultado de la primera; mismo DTO devuelve exactamente su status/body original, sin repetir escritura ni modificar fechas/versiones. Distinto DTO/tipo/ruta con la misma clave devuelve `409 idempotency_key_reused`.
4. Ejecutar la mutación o determinar un conflicto de negocio y guardar su respuesta en la misma transacción. Se conservan éxitos y conflictos terminales `409` del dominio. Fallos previos de formato/autenticación no crean recibo. Un fallo transitorio revierte tanto mutación como reserva; no queda un recibo de éxito anticipado.

Se retienen recibos durante el MVP, sin purga automática que convierta un reintento antiguo en una operación nueva. El hash SHA-256 usa la representación canónica producida por el servidor, no los bytes del JSON recibido. Cambiar espacios u orden de propiedades no altera intención. La autorización actual precede a la reproducción: no devuelve datos de un grupo al que ya no se tiene acceso. El recibo mínimo de salida propia no devuelve el grupo y admite el replay acotado indicado arriba; su confirmación debe poder recuperarse después de terminar la pertenencia.

Una respuesta perdida o resultado desconocido se resuelve repitiendo **misma ruta, operationId y payload**. La app conserva ese sobre de operación hasta resolverlo, también tras pasar a segundo plano/reabrir; no habilita una confirmación diferente del mismo borrador mientras desconoce el resultado anterior. No necesita una cola general offline ni un endpoint adicional de estado. Dos intenciones nuevas usan IDs distintos y ambas se conservan, aunque el texto sea igual.

Ante un `409` confirmado, la app muestra el conflicto, refresca y permite revisar el borrador/selección. Una confirmación revisada lleva un `operationId` nuevo. Repetir la clave que ya produjo un conflicto devuelve ese mismo conflicto, aunque el estado haya cambiado después. Recibos antiguos no sustituyen al refresco actual de la lista.

### Lote y edición

`addItems` recibe únicamente valores revisados, sin audio, transcripción ni propuesta original de IA. Valida todo el lote, resuelve tiendas e inserta entradas más recibo en una transacción. Un error en cualquier entrada revierte también tiendas nuevas creadas para ese lote. Se devuelven entradas en el orden enviado y cada una empieza pendiente con versión 1.

`editItem` exige la representación completa de campos editables (`name`, `quantity`, `store`) y `expectedVersion`. Solo admite pendiente con esa versión; cambiar de tienda también aumenta versión. `cancelItem` exige pendiente y versión; deja los datos de compra nulos. Ni edición ni cancelación hacen escrituras si detectan conflicto. El resultado de cada operación incluye la fila/version confirmada.

### Finalizar compra

`finalizePurchase` recibe `storeId` e IDs/versiones de 1–50 seleccionados. No acepta un filtro «todos los pendientes» ni campos comprador/fecha. Marcar checks no genera peticiones.

En una transacción, el servidor bloquea grupo y cuenta del actor y comprueba pertenencia vigente; después bloquea las filas de productos correspondientes exclusivamente a los IDs enviados, en orden estable por ID. Tras bloquear, verifica existencia, tienda, estado pendiente y versión de **todos**. La prioridad de diagnóstico por ID es: ausente/no accesible, tienda distinta, no pendiente, versión distinta. Si algún seleccionado no cumple, devuelve `409 item_conflict` con todos los conflictos detectados y no compra ninguno de esta petición. El recibo de conflicto sí puede confirmarse.

La respuesta incluye estado actual solo de productos accesibles del propio grupo. Un ID ajeno o inexistente se representa igual, con `reason: not_found` y `current: null`. No filtra si existe en otro grupo. Un grupo/tienda de la ruta inexistente o ajeno responde `404` antes de operar.

Si todos cumplen, establece `purchased`, comprador autenticado, una misma fecha de confirmación del servidor y versión +1, guardando resultado/recibo atómicamente. Devuelve filas ordenadas por ID. **Tres IDs de cinco pendientes cambian tres filas.** Los dos omitidos y cualquier alta concurrente siguen pendientes. Ningún camino sobrescribe una compra, cancelación o edición previamente confirmada.

| Carrera | Resultado |
|---|---|
| Dos finalizaciones, claves distintas, un ID común | Primera transición válida gana; la otra selección completa recibe conflicto, sin sobrescribir comprador |
| Misma clave/payload simultáneos | Un commit; ambas respuestas tienen los mismos IDs, fecha y versiones |
| Editar antes de finalizar | Nueva versión; finalización antigua entra en conflicto |
| Finalizar antes de editar/cancelar | Estado comprado; edición/cancelación entra en conflicto |
| Cancelar antes de finalizar | Estado cancelado; no aparece como compra |
| Alta distinta durante finalización | Se conserva pendiente; nunca entra por un filtro implícito |

PostgreSQL `READ COMMITTED` más restricciones, versiones y `SELECT … FOR UPDATE` cubre estas operaciones acotadas; no se presupone aislamiento serializable de toda la app. El orden compartido es grupo → cuenta del actor → recurso; crear un grupo nuevo empieza por la cuenta porque el grupo aún no existe. Las operaciones de invitación, transferencia, salida y productos siguen ese protocolo y revalidan acceso después de los bloqueos para evitar escrituras tras salir o cerrar. No se adquiere un grupo existente después de bloquear primero la cuenta. Después de `INSERT … ON CONFLICT DO NOTHING` del recibo, consultar el resultado en otra sentencia: el snapshot de la sentencia original puede no ver la fila concurrente que causó el conflicto. Caducidades de invitación/transferencia/challenge se comprueban con tiempo actual después de esperar bloqueos (`clock_timestamp()`), no con una marca congelada al inicio de transacción. Deadlocks/fallos transitorios revierten la operación; un reintento conserva su clave.

## Consulta, selección y errores

`listStores`, `listInvitations`, `listPendingItems` y `listGroupMembers` usan cursor opaco de servidor y límite acotado. Orden `(created_at, id)` ascendente; el cursor se vincula a grupo/recurso/filtros y se rechaza si es inválido o se reutiliza en otra consulta. `listPendingItems` devuelve solo pendientes de la tienda autorizada. `listGroupMembers` devuelve identidades mínimas `{id, displayName}` dentro de `{data, nextCursor}`; nunca datos Apple ni emails. Una tienda válida sin pendientes devuelve lista vacía, no `404`.

Las páginas no forman un snapshot entre peticiones; puede cambiar el contenido concurrentemente. El cliente acumula por ID, conserva la versión más reciente y vuelve a consultar desde el inicio al entrar, refrescar o confirmar operaciones. No anuncia que una lista local esté al día sin respuesta; cambiar de tienda no aplica los checks anteriores a la siguiente. La selección local conserva IDs/versiones hasta resolver una operación incierta. Al refrescar una selección sin envío en curso, los elementos cambiados se señalan para revisión explícita; no se sustituyen sus versiones y se compran automáticamente.

`Error` contiene `code` estable, mensaje legible de diagnóstico y `requestId` para correlación. La app localiza mensajes por código. `fields` identifica entradas inválidas; `conflicts` corresponde a `item_conflict`. No incluir credenciales ni datos de otros grupos en errores/logs. El validador comprueba su forma, no la correspondencia semántica de cada código con el status.

| HTTP | Significado y recuperación |
|---|---|
| `400` | JSON/parámetros inválidos, campos desconocidos, duplicados o cursor inválido. Corregir entrada. |
| `401` | Sesión ausente/caducada/revocada o Apple/challenge inválido. Conservar borrador e iniciar acceso. |
| `403` | Miembro sin administración vigente (`administrator_required`) o distinto del destinatario de una transferencia (`transfer_recipient_required`). |
| `404` | Recurso inexistente, cerrado o ajeno; ID/secreto de invitación incorrectos. No revelar más. |
| `409` | Estado/versión cambiado, grupo ya asignado, challenge consumido o clave reutilizada; propuesta pendiente/terminal, destinatario inválido, traspaso o confirmación de cierre necesarios. Ver códigos de [administración](group-administration.md#errores-de-negocio). Reconciliar; una decisión revisada requiere clave nueva. |
| `410` | Secreto de invitación auténtico pero caducado, revocado o consumido por otro. |
| `413` | Body demasiado grande; no se procesa parcialmente. |
| `429` | Esperar `Retry-After` en segundos; el mismo envío mantiene su clave. |
| `503` / timeout / pérdida de conexión | Resultado potencialmente desconocido. Conservar sobre y repetir según la regla de esa operación; en login iniciar otro intento. |

No añadir funcionalidad a partir de los errores: sin selección automática de todos, compra parcial automática, sincronización general offline, historial analítico, coadministradores ni multigrupo en esta entrega.

## Comprobar el contrato

Desde la raíz, Python 3.10 o posterior. La dependencia es una herramienta de validación local; no se incorpora a iOS ni a Vapor. Usar un entorno temporal fuera del repositorio:

```bash
contract_venv=$(mktemp -d "${TMPDIR:-/tmp}/smartshoppinglist-contract.XXXXXX")
python3 -m venv "$contract_venv/venv"
"$contract_venv/venv/bin/python" -m pip install -r scripts/requirements-contract.txt
"$contract_venv/venv/bin/python" -B scripts/validate_contract.py
git diff --check
```

El script valida referencias locales, seguridad explícita por operación, operationIds únicos, esquemas y formatos JSON Schema, cobertura de todas las operaciones, peticiones/respuestas positivas y rechazo de negativos. Los parámetros de ejemplo ya están decodificados y tipados; no prueba serialización HTTP ni bearer reales. La comprobación estructural OpenAPI es **parcial**, no una metavalidación completa de la especificación. Las reglas que necesitan estado (normalización, repetición de ID con distinta versión, autorización, transacciones) se revisan en la matriz y se comprobarán con Swift Testing contra implementación real.

Cambiar el contrato exige actualizar ejemplos/matriz y ejecutar este comando. Los resultados concretos y el estado de entrega se registran en la issue correspondiente (#33 para esta evolución), sin duplicar un archivo de progreso.

## Fuentes técnicas y decisiones propias

- [OpenAPI 3.2.1](https://spec.openapis.org/oas/v3.2.1.html): formato del documento, con dialecto JSON Schema declarado.
- [Unicode NFC](https://www.unicode.org/reports/tr15/) y [Default Case Folding, capítulo 3](https://www.unicode.org/versions/Unicode17.0.0/core-spec/chapter-3/): equivalencia canónica y clave de tiendas, sin coincidencia difusa.
- [Verificar un usuario Apple](https://developer.apple.com/documentation/signinwithapple/verifying-a-user), [nonce](https://developer.apple.com/documentation/authenticationservices/asauthorizationopenidrequest/nonce), [state](https://developer.apple.com/documentation/authenticationservices/asauthorizationopenidrequest/state) y [canje/validación de tokens](https://developer.apple.com/documentation/signinwithapplerestapi/generate-and-validate-tokens): autenticación. TTL de challenge, sesión propia y política diferida son decisiones de este contrato.
- [TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple): concesiones y revocación; logout local no equivale a borrar cuenta Apple.
- [Keychain WhenUnlockedThisDeviceOnly](https://developer.apple.com/documentation/security/ksecattraccessiblewhenunlockedthisdeviceonly): custodia local de sesión y enlace pendiente.
- [Associated Domains](https://developer.apple.com/documentation/xcode/supporting-associated-domains), [onOpenURL](https://developer.apple.com/documentation/swiftui/view/onopenurl(perform:)) y [RFC 3986 §3.5](https://www.rfc-editor.org/rfc/rfc3986#section-3.5): entrega y fragmento del enlace. Los ensayos reales y sus límites se conservan en la [validación del recorrido compartido](../validation/issue-4-shared-flow.md).
- PostgreSQL 18: [aislamiento](https://www.postgresql.org/docs/18/transaction-iso.html), [bloqueos explícitos](https://www.postgresql.org/docs/18/explicit-locking.html) y [reloj de transacción](https://www.postgresql.org/docs/18/functions-datetime.html). La combinación transaccional descrita es diseño de la app y requiere pruebas de carreras.
