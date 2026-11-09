# Eliminación de cuenta

**Estado: implementación local; validación distribuida pendiente · 9 de noviembre de 2026.** Trabajo de [#54](https://github.com/JFrancoG/SmartShoppingList/issues/54), rama `codex/issue-54-privacy-account-deletion`, base inspeccionada `4596c2f`.

El propietario aprueba las decisiones de grupos, conservación y recuperación de suscripciones y autoriza actualizar los textos e iniciar la implementación. Este documento fija el comportamiento objetivo y distingue las comprobaciones técnicas pendientes. **La aprobación no activa la eliminación ni autoriza purgas de producción.** La implementación local amplía el contrato a **0.6**; los servicios y builds distribuidos siguen su versión desplegada hasta una entrega separada; los textos públicos no deben anunciar esta función como disponible hasta comprobarla en el build distribuido.

## Resultado esperado

Una persona puede iniciar y confirmar la eliminación desde Ajustes, sin enviar un correo ni esperar la aceptación de otro miembro. El proceso elimina su cuenta y el contenido asociado que corresponda, invalida sus sesiones, revoca Sign in with Apple y conserva los datos propios de las demás personas. Una suscripción activa no bloquea la eliminación inmediata. La acción no cancela por sí misma la facturación de Apple.

Eliminar no equivale a cerrar sesión, abandonar un grupo, ocultar el nombre ni marcar indefinidamente una cuenta como inactiva. Una nueva alta recibe una identidad nueva; no recupera listas, pertenencias ni operaciones borradas.

**Aclaración de alcance confirmada por el propietario el 9/11/2026:** salir de un grupo para entrar en otro no debe borrar la cuenta ni requerir desinstalar la app. Se mantienen tres acciones diferentes:

| Acción | Alcance |
|---|---|
| **Salir del grupo** | Quita esa pertenencia y libera su plaza; conserva la cuenta y el resto de grupos. Mantiene las reglas de traspaso/cierre en grupos administrados; la salida del último miembro de un grupo pendiente de administración elimina ese grupo y su historial con aviso previo. |
| **Cerrar sesión** | Termina el acceso de esa sesión; no elimina la cuenta ni sus datos del servidor. |
| **Eliminar cuenta y mis datos** | Solicitud expresa para eliminar la cuenta completa de ese entorno y sus datos conforme a este diseño. |

La eliminación introduce `pending_administration` y la purga descrita abajo. La salida ordinaria de grupos administrados conserva sus reglas; si después sale el último miembro de un grupo pendiente de administración, ese grupo y su historial se purgan con advertencia previa. El 9/11/2026 el propietario aprueba también retirar texto histórico de autoría incierta con aviso previo, aunque pueda incluir aportaciones de otros miembros. Se conserva la estructura necesaria y el contenido ajeno de autoría demostrada. Esta decisión autoriza la implementación; no ejecuta ninguna eliminación real.

## Evidencia de la base `4596c2f`, anterior a esta implementación

| Código/contrato inspeccionado en la base | Consecuencia para la implementación |
|---|---|
| [AppleAuthenticationRoutes](../../server/Sources/SmartShoppingListServer/Identity/AppleAuthenticationRoutes.swift), líneas 24–26; [AppleAuthenticationService](../../server/Sources/SmartShoppingListServer/Identity/AppleAuthenticationService.swift), líneas 140–146 | `DELETE /v1/session` solo revoca el bearer presentado. No hay endpoint de eliminación. |
| [AppleGateway](../../server/Sources/SmartShoppingListServer/Identity/AppleGateway.swift), líneas 8–12 y 47–55 | Existen intercambio y validación de tokens; falta revocación mediante `/auth/revoke`. |
| [AppleAuthenticationService](../../server/Sources/SmartShoppingListServer/Identity/AppleAuthenticationService.swift), líneas 70–96 | El login hace upsert por `apple_subject`. No sirve como confirmación de eliminación: podría recrear o actualizar la cuenta. |
| [CreateSharedShopping](../../server/Sources/SmartShoppingListServer/Persistence/CreateSharedShopping.swift); [CreateAppleAuthentication](../../server/Sources/SmartShoppingListServer/Identity/CreateAppleAuthentication.swift) | Hay múltiples FK a `users`, sin borrado en cascada; identificadores personales también aparecen dentro de recibos JSON. |
| [Administración de grupos](../contracts/group-administration.md); [GroupAdministrationService](../../server/Sources/SmartShoppingListServer/Shopping/GroupAdministrationService.swift), líneas 224–264 | La salida de un administrador exige traspaso; el cierre actual es lógico y conserva historial. Ninguna de esas operaciones cumple por sí sola este diseño. |
| [StoreWritePlan](../../server/Sources/SmartShoppingListServer/Shopping/StoreWritePlan.swift), líneas 15–20; [ShoppingService](../../server/Sources/SmartShoppingListServer/Shopping/ShoppingService.swift), edición de productos | Tiendas sin creador registrado y modificaciones sin autoría suficiente. No es posible atribuir todo el contenido histórico con certeza. |
| [SubscriptionService](../../server/Sources/SmartShoppingListServer/Subscriptions/SubscriptionService.swift), líneas 12–16, 78–86 y 238–302 | Compras y restauraciones están vinculadas al UUID de cuenta; una notificación de un UUID inexistente no concede acceso. Conservar una fila de usuario borrado sin cambiar estas guardas permitiría seguir procesando derechos. |
| [SharedKeychainStore](../../ios/SmartShoppingList/SmartShoppingList/Services/SharedAPI/SharedKeychainStore.swift), líneas 19–63; [SharedAppStorage](../../ios/SmartShoppingList/SmartShoppingList/App/SharedAppStorage.swift) | Hay sesión, enlaces, operaciones y verificaciones pendientes, además del borrador por entorno; la limpieza debe cubrirlos expresamente. |

## Recorrido de producto

1. **Ajustes → Cuenta → Eliminar cuenta y mis datos.** Disponible para cuentas gratuitas y Premium, aunque hayan agotado cupos o solo tengan acceso restringido a grupos adicionales. La entrada muestra el entorno resuelto; en TestFlight la explicación aclara que afecta a la cuenta y los datos de prueba.
2. El servidor prepara una vista del impacto: grupos administrados, grupos donde es miembro, contenido propio que se retirará y texto antiguo de autoría incierta. La advertencia sobre suscripciones siempre aparece, sin presumir su cancelación. Una consulta fallida no se presenta como ausencia de grupos o de compras. Sin conexión se puede leer la explicación, pero no confirmar una eliminación que no se ha enviado.
3. La persona puede gestionar su suscripción y, opcionalmente, usar el traspaso de administración existente. **Eliminar ahora** sigue disponible; no se exige cancelar, esperar a la caducidad ni conseguir que un tercero acepte el traspaso.
4. Confirmación clara y autenticación reciente, ligada a esa cuenta y a ese propósito. La confirmación muestra el efecto sobre sus contribuciones compartidas y los grupos pendientes de administración. No requiere escribir el nombre de la cuenta ni un motivo.
5. La app conserva la identidad de la solicitud y su comprobante antes de enviar. Una aceptación durable lleva a «Eliminación en curso», cierra el uso normal de la cuenta y limpia sus datos locales según la fase confirmada. Una respuesta perdida se consulta con el mismo comprobante; no se supone éxito ni se crea otra solicitud.
6. El servidor completa la purga y registra el resultado mínimo. La app distingue «Cuenta eliminada» de «Eliminación en curso» y de un error previo a aceptar. No vuelve a abrir la cuenta para resolver un fallo de revocación Apple.

La eliminación desde un dispositivo invalida todas las sesiones del mismo backend. No se puede borrar a distancia un archivo que permanezca en un dispositivo desconectado: una versión compatible lo limpia al volver a ejecutar/conectar la app y confirmar que pertenece a la cuenta eliminada. Un `401` genérico, un fallo de red o el acceso con una cuenta distinta no bastan para afirmar eliminación ni para borrar el borrador. Ante sesión inválida se bloquean los envíos; los datos anteriores quedan aislados hasta resolver su identidad y obtener una señal terminal verificable de eliminación. El contrato 0.6 incorpora `POST /v1/account/deletion-session-status`: el bearer original consulta una señal explícita de aceptación irreversible, retenida treinta días desde la aceptación y renovada al purgar, sin devolver identidad ni datos. La ausencia de señal no acredita eliminación. La señal de aceptación permite limpiar el dispositivo sin afirmar que el servidor ya terminó la purga; evita perder la referencia al recibir un 401 durante esos primeros segundos. El borrador por entorno sin autoría permanece aislado en otros dispositivos; no se reenvía automáticamente desde la nueva cuenta. El cliente nunca reasigna automáticamente una operación pendiente al UUID nuevo.

El borrador actual se almacena por entorno, no por persona. La confirmación del dispositivo iniciador explicará que también borra ese borrador local, incluido lo preparado sin iniciar sesión. Para otras cuentas/dispositivos se necesita identificar la pertenencia de las operaciones y separar material local sin autoría; cambiar de cuenta o salir de un grupo no es una orden de borrarlo.

## Grupos compartidos

**Decisión aprobada:** ampliar el ciclo de grupo con `pending_administration` cuando el administrador elimina su cuenta y quedan otros miembros. La asunción de administración es voluntaria; se conservan las aportaciones ajenas y la eliminación no depende de una respuesta externa.

| Situación al confirmar bajo bloqueo | Resultado aprobado |
|---|---|
| Miembro que no administra | Retirar pertenencia y contenido propio, sin cambiar la administración. |
| Último miembro | Eliminar grupo y su contenido, no conservar un cierre lógico indefinido. |
| Administrador con otros miembros y traspaso ya aceptado | Salida como miembro ordinario; la suscripción personal no se transfiere. |
| Administrador con otros miembros sin traspaso aceptado | Retirar su pertenencia y contenido; grupo en `pending_administration`, sin administrador ni capacidad Premium heredada. Invalidar transferencias pendientes e invitaciones utilizables. |
| La persona creó un grupo que ahora administra otra | Borrar su identidad y contenido propio, retirar la atribución histórica y el nombre aportado cuando corresponda; el grupo de terceros continúa. No se asigna falsamente la autoría al administrador actual. |

En `pending_administration`, los miembros existentes pueden **consultar, confirmar compras, cancelar productos y salir**. Se permite reducir contenido y resolver responsabilidades; no añadir productos/tiendas, editar contenido de terceros, restaurar tiendas, invitar ni incorporar nuevas pertenencias. El estado del grupo no concede acceso personal adicional: se conservan las restricciones de acceso de cada cuenta, con la excepción explícita de poder asumir administración y salir. Los cupos de referencia son gratuitos (3 tiendas activas y 20 pendientes por tienda), sin borrar excedentes; como no se permite crecimiento, el exceso no impide consumir o reducir.

Un miembro existente y con cuenta activa puede **Asumir administración** mediante aceptación explícita. Se bloquea el grupo y se revalida pertenencia/estado; exactamente uno gana si hay solicitudes simultáneas. No consume una nueva pertenencia ni requiere Premium. Tras aceptar, se aplican el plan del nuevo administrador y las reglas existentes de reducción sin pérdida de datos. La operación no restaura contenido borrado, enlaces antiguos ni la suscripción del administrador anterior.

La complejidad añadida se concentra en un estado, capacidades y aceptación atómica. Requiere modificar la invariante SQL actual «grupo abierto = administrador miembro no nulo», DTO y clientes; no puede desplegarse como un `NULL` inesperado. La alternativa de cierre expreso del grupo completo es más simple, pero borra acceso y potencialmente contenido de otras personas; no se recomienda como efecto automático de eliminar una cuenta.

## Contenido y matriz de eliminación

La regla no es «conservar todo lo compartido con un nombre anónimo». Apple pide eliminar también el contenido generado por la persona. El texto libre puede identificarla aunque se quite su UUID. Conservar datos propios de terceros exige distinguir contenido, atribución y estado funcional.

| Recurso | Tratamiento propuesto |
|---|---|
| `users` | Borrar UUID operativo, `apple_subject`, nombre y preferencias después de ejecutar las dependencias. Puede existir un estado transitorio `deleting` durante el trabajo, nunca una cuenta esqueleto permanente. |
| `app_sessions`, `apple_grants` | Invalidar inmediatamente todas las sesiones; borrar hashes y concesiones. El trabajo de revocación retiene temporalmente solo el token cifrado imprescindible, separado de la cuenta y con caducidad. |
| `group_memberships`, elección gratuita y `account_premium_access` | Eliminar; recalcular capacidades desde datos vigentes. |
| Productos y texto propio | Retirar nombre y cantidad atribuibles y la identidad del creador. Si no quedan aportaciones ajenas que conservar, eliminar el producto; si las hay, conservar únicamente ese contenido y su contenedor funcional, con una etiqueta neutra cuando falte el nombre. Haber creado el producto no autoriza borrar los cambios posteriores de otros miembros. Incluir pendientes, comprados y cancelados, así como contenido de grupos de los que ya salió o cerrados. No recuperar versiones anteriores del texto. |
| Productos de otro usuario comprados por el eliminado | Conservar, cuando proceda, el estado «comprado» de la lista ajena y retirar la identificación del comprador. Cambiar el CHECK que hoy obliga `purchased_by` no nulo cuando comprado; no volverlo pendiente ni inventar otro comprador. |
| Tiendas y nombres de grupo | Retirar el texto y la atribución propios. Cuando hay contenido ajeno que depende del contenedor, conservar su ID funcional con una etiqueta neutra del sistema; un administrador vigente podrá nombrarlo de nuevo. No afirmar que una tienda es ajena por ausencia de autor. |
| Invitaciones y transferencias | Invalidar enlaces utilizables afectados; retirar sujetos y secretos/huellas cuando termine su necesidad. Eliminar historia personal salvo excepción documentada y acotada. |
| Recibos de mutación | Borrar los de la cuenta: su UUID no se reutiliza. En recibos de otras cuentas retirar cuerpo, fingerprint y toda referencia al eliminado. Sustituir por un marcador de la operación del tercero ya procesada, nunca por una operación disponible para ejecutar otra vez. |
| Compras y notificaciones V2 | Eliminar derechos de cuenta y vínculo operativo. Una notificación tardía no recrea usuario ni Premium. Solo conservar evidencias mínimas justificadas para recuperación/fraude/reembolso durante un plazo aprobado; no guardar JWS completos por comodidad. |
| Dispositivo iniciador | Borrar sesión, enlaces pendientes/entrantes, operación pendiente, verificación de compra, selección, borrador del entorno y estado en memoria. Invalidar tareas, generaciones y App Intents antes de que puedan volver a escribir. |
| Otros dispositivos | Revocar autorización de servidor de inmediato; limpiar el contexto local al detectar eliminación. Las tareas antiguas no pasan a la identidad nueva. |
| Logs, soporte y copias | Aplicar las retenciones aprobadas y las excepciones legalmente necesarias; excluir contenido y credenciales de logs. Toda restauración de una copia reaplica eliminaciones antes de servir tráfico. |

**Decisión de legado aprobada el 9/11/2026:** antes de confirmar se cuenta y avisa sobre el texto cuya autoría no puede demostrarse. La purga retira ese texto en grupos donde la cuenta pudo contribuir, conservando la estructura y los campos de autoría ajena comprobada. Pueden retirarse textos antiguos de otras personas: es una limitación explícita del historial disponible, no una atribución ficticia. No se borran datos reales durante esta implementación.

La reconstrucción solo acepta una cadena completa de recibos exitosos desde la versión 1, con actor y versiones consecutivas, transiciones permitidas y coincidencia exacta con el registro actual. Un hueco, ambigüedad o discrepancia mantiene la autoría desconocida. La atribución verificada se conserva antes de retirar los recibos; no se recuperan textos anteriores.
La implementación inicial añade `stores.created_by`, `items.name_author_user_id` e `items.quantity_author_user_id`, sin duplicar el contenido. Los datos anteriores permanecen con procedencia desconocida (`NULL`); el creador de producto ya existente no prueba quién escribió el texto actual. Un alta nueva registra autoría de los campos presentes y de las tiendas que crea. Una edición cambia la autoría únicamente del campo cuyo valor cambia; mover de tienda o reenviar texto idéntico no convierte a la persona en autora de ese texto. Quitar la cantidad elimina también su atribución. Reintentos y conflictos no cambian la procedencia. La reversión de esta migración se rechaza si perdería atribuciones conocidas.

Los recibos históricos de edición contienen actor, versión y resultado, pero no el valor anterior de cada campo; no permiten por sí solos distinguir texto nuevo de texto reenviado sin cambios. La atribución de campos históricos requiere una cadena completa y verificable de versiones. Los recibos de productos tampoco distinguen de forma suficiente la creación de una tienda de su reutilización. Una auditoría posterior debe clasificar evidencia acreditada y desconocida; esta migración no reconstruye autores automáticamente por fechas ni por primer uso observado.

### Esquema y compatibilidad necesarios

- Introducir estado de cuenta transitorio y un trabajo durable separado. Todas las lecturas/escrituras y la ingesta de suscripciones comprueban cuenta activa; borrar finalmente la fila, no conservar el sujeto Apple como mecanismo de recuperación.
- Grupo con estados explícitos `active`, `pending_administration` y el cierre histórico mientras exista. `active` mantiene exactamente un administrador miembro; `pending_administration` exige administrador nulo y al menos un miembro, comprobado transaccionalmente. El último miembro dispara la purga correspondiente.
- Autoría nullable para contenedores que permanezcan por datos de terceros y una representación explícita de atribución retirada. Cambiar `creatorUserId` y `purchasedBy` en contrato/cliente sin UUID ficticios ni usuarios globales «eliminados».
- Añadir procedencia de nuevas tiendas y contribuciones editadas, con minimización y sin conservar versiones de texto personal indefinidamente para facilitar una futura purga.
- Separar los recibos de operación de sus cuerpos de respuesta. El resultado retirado es terminal y obliga a refrescar; no devuelve el contenido eliminado ni ejecuta nuevamente la intención.
- Versionar capacidades y mutaciones. Los clientes antiguos que no entiendan estos estados deben recibir una actualización requerida para escribir; no pueden coexistir como escritores que presupongan un administrador no nulo o recreen contenido retirado. Ensayar la migración con copia y restauración, y aprobar por separado el despliegue real.

## Autenticación, estado durable y recuperación

### Confirmación de identidad

Crear un desafío de reautenticación de corta duración, con nonce, sesión, cuenta, entorno y propósito `accountDeletion`. Verificar firma, audiencia y sujeto Apple contra la cuenta existente. Consumirlo una vez. **No llamar a la ruta de login con upsert** ni aceptar el UUID del cliente como identidad. Una sesión nueva creada en paralelo no evita una eliminación ya aceptada; el login debe comprobar el estado bajo bloqueo.

Si ya no existe token de revocación, se puede obtener mediante reautenticación cuando esté disponible. La ausencia del token no permite negar indefinidamente una eliminación legítimamente confirmada: seguir las alternativas de TN3194, borrar los datos y explicar la revocación manual de Apple cuando sea necesaria. No convertir esto en una obligación general de contactar con soporte.

### Máquina de estados implementada localmente

| Estado | Garantía |
|---|---|
| `prepared` | Operación persistida con hash del secreto, revisión y desafío de cinco minutos. No se ha solicitado eliminar nada. Caduca a los treinta minutos. |
| `cancelled` | Preparación cancelada o caducada. No elimina datos; la aceptación concurrente comprueba este estado antes de su commit. |
| `accepted` | Solicitud e intención persistidas atómicamente, cuenta bloqueada para uso y nuevas sesiones. La app ya puede recuperar el estado aunque pierda la respuesta. |
| `purging` | Trabajo reanudable retira contenido y dependencias; cada fase deja un punto durable. |
| `data_deleted` | Cuenta y contenido operativo eliminados; puede quedar revocación Apple en curso o retención mínima excepcional, identificada por separado. |
| `completed` | Purga operativa finalizada y trabajo de revocación concluido con resultado explícito: `confirmed` o `manual_action_required`. El segundo no afirma que Apple haya revocado. Se informa aparte del agotamiento de copias y de las excepciones aprobadas. |

Un fallo de red anterior al commit mantiene la cuenta como estaba; uno posterior no devuelve a `prepared`. Un fallo parcial conserva el trabajo y el estado cerrado al uso, registra un error técnico sin datos personales y reintenta con límites. Las validaciones de concesiones y los intercambios de login tienen un marcador durable mientras Apple responde. La purga espera su plazo acotado y recoge el token nuevo; si el resultado queda incierto, conserva una indicación irreversible de revocación manual. Un login iniciado antes de aceptar se invalida y no puede recrear el perfil después. La revocación externa nunca se ejecuta dentro de una transacción SQL. No se promete que el proceso completo sea una sola transacción ni que «cancelar» revierta una eliminación ya aceptada.

La app genera y guarda antes de enviar un secreto aleatorio de seguimiento y el `operationId`; el servidor guarda su hash. Así puede consultar una solicitud cuya respuesta se perdió incluso cuando la sesión ya fue revocada. El recurso expone únicamente estado y resultado de revocación; los límites de petición y la protección de abuso del borde deben comprobarse al desplegar; ni datos de cuenta, ni acciones comerciales, ni restauración. No registrar el secreto, ponerlo en URLs o usarlo como bearer general. Una repetición exacta devuelve el estado del mismo trabajo; una intención diferente con el mismo identificador se rechaza.

### Frontera HTTP 0.6, incluida en OpenAPI

| Ruta | Autorización y resultado |
|---|---|
| `GET /v1/account/deletion-preview` | Sesión de cuenta activa; impacto y estado conocido de suscripción, versión del resumen y su vigencia. No realiza cambios. |
| `POST /v1/account/deletion-challenges` | Sesión activa; desafío para confirmar esa cuenta y propósito, sin iniciar sesión ni crear otra cuenta. |
| `POST /v1/account/deletions` | Sesión activa y prueba reciente de identidad; `operationId`, revisión de impacto y secreto de seguimiento. `202` solo después de aceptación durable. Un cambio material de impacto devuelve conflicto y un resumen actualizado para confirmar de nuevo, sin exigir que un tercero actúe. |
| `POST /v1/account/deletions/status` | Identificador de solicitud y secreto de seguimiento en cuerpo protegido por HTTPS; no usa una sesión de cuenta ya revocada. Solo estado mínimo. Se puede recuperar tras perder la respuesta o reiniciar la app. |
| `POST /v1/account/deletions/cancel` | Comprobante; cancela únicamente `prepared`, o devuelve el estado aceptado sin revertirlo. |
| `POST /v1/account/deletion-session-status` | Bearer original; devuelve únicamente `deletionAccepted`. Señal positiva tras el commit de aceptación, nunca un `401` como prueba. |
| `POST /v1/groups/{groupId}/administration-claim` | Sesión de miembro actual y `operationId`; aceptación atómica del cargo únicamente si el grupo sigue pendiente de administración. |

Si la preparación nunca llegó al servidor, cancelar con el comprobante crea un marcador privado `cancelled`: una preparación retrasada con el mismo identificador no puede reabrirla. Un `404` por sí solo nunca libera el estado local.

Una retransmisión después de la aceptación usa el recurso de estado y el comprobante, sin reejecutar con un bearer revocado. Conservar lo necesario para que una respuesta perdida antes del commit pueda distinguir «todavía no aceptada» de «aceptada» sin revelar cuentas por UUID; nunca concluir borrado a partir de `404`. No registrar cuerpos, secretos ni credenciales de estas rutas. El contrato tipado y sus ejemplos fijan caducidades, estados y errores. Todas las rutas `/v1` requieren `X-SmartList-Contract: 0.6`, excepto las notificaciones firmadas de Apple; los clientes anteriores reciben `426 client_update_required`.

Si se pierde también el comprobante local, reautenticación durante el trabajo puede devolver solo «eliminación en curso», sin upsert, mientras exista el vínculo temporal necesario. Después de completar y purgar ese vínculo, no se ofrece recuperar la cuenta eliminada. La nueva alta no debe esperar indefinidamente a conservar una marca del sujeto Apple.

### Bloqueos y cobertura de datos históricos

Las transacciones ordinarias toman primero una barrera advisory compartida de PostgreSQL y conservan el orden de bloqueos por fila existente. La preparación, aceptación y purga toman esa barrera en exclusiva antes de leer o bloquear filas. Esto estabiliza el conjunto afectado sin adquirir grupos nuevos después de cuentas ya bloqueadas. La exclusividad dura solo el trabajo SQL; ninguna petición externa a Apple mantiene la barrera.

El conjunto afectado incluye pertenencias, grupos administrados, autoría histórica, compras, transferencias, invitaciones y recibos, también de grupos abandonados o cerrados. La cuenta activa se revalida dentro de la transacción. Login e ingesta de compras/V2 participan en la misma coordinación; un callback tardío no recrea la cuenta. Esta decisión serializa brevemente una purga frente a todas las operaciones de la base: medir con volumen representativo antes de desplegar y dividirla por fases solo si se demuestra necesario, manteniendo las mismas garantías.
### Retención acotada e idempotencia

Los recibos del usuario eliminado se borran: no quedan sesiones válidas y su UUID nunca se asigna a una nueva cuenta. Para recibos de terceros afectados se conserva solo `(user_id del tercero, operation_id, operation_type, estado result_removed)`, sin cuerpo, fingerprint, grupo, producto ni identificador del eliminado. Un replay devuelve un resultado terminal «el resultado ya no está disponible; actualiza», sin comparar el contenido borrado ni volver a ejecutar la operación. El marcador pertenece a la operación del tercero, no es una cuenta esqueleto ni una huella de la persona eliminada.

La conservación se limita a la vida de esa cuenta y sus operaciones recuperables; se purga también cuando esa cuenta se elimina. No se fija arbitrariamente un TTL de 30 días: con UUIDv4 actuales, olvidar un marcador y admitir ese UUID como nuevo puede repetir una compra o una incorporación. Si posteriormente se requiere caducidad temporal absoluta, habrá que diseñar una ventana de operación verificable por el servidor o una generación de idempotencia que rechace operaciones antiguas. Esa evolución queda fuera de esta unidad; no se introducen firmas o épocas adicionales aquí.

Los objetivos de purga, copias, logs y soporte están aprobados como decisiones de producto. Los límites internos de tokens/comprobantes concretan el diseño técnico. Todos deben configurarse y medirse antes de convertirse en compromisos públicos; no son plazos atribuidos al RGPD:

| Material/proceso | Objetivo de implementación, aún no configurado |
|---|---|
| Purga de datos operativos tras aceptación | Objetivo de 24 horas; probar volumen y recuperación antes de prometerlo. El bloqueo de acceso ocurre al aceptar. |
| Token cifrado necesario para revocar Apple | Reintentos durante un máximo de 7 días; después borrar el token y explicar la alternativa manual si no pudo confirmarse. No confundir este resultado con revocación confirmada. |
| Comprobante de seguimiento | Siete días desde el resultado terminal. Una preparación abandonada caduca; un trabajo aceptado que no termina no se borra por TTL y requiere escalado al superar el objetivo operativo. No restaurar acceso ni perder el comprobante justo al terminar un trabajo retrasado. |
| Marca temporal de identidad para impedir login durante el trabajo | Durante la revocación, como máximo siete días desde aceptación, y cinco minutos adicionales tras completar para rechazar desafíos de login anteriores al resultado. Los desafíos nuevos permiten un alta nueva inmediatamente tras completar; no se conserva un HMAC permanente. El TTL de cinco minutos de los desafíos impide que un login antiguo reaparezca después de retirar esa marca. |
| Huella de sesión retirada para confirmar limpieza en otro dispositivo | Treinta días desde la aceptación, renovados al purgar, sin vínculo al UUID ni contenido; no permite autenticarse. Se purga automáticamente. |
| Marcador de recibo retirado de otro usuario | Mientras exista la cuenta del tercero y se pueda recuperar esa operación; se elimina con esa cuenta. No contiene datos ni referencias del usuario eliminado. |
| Copias de seguridad | Máximo aprobado de 30 días, pendiente de configurar y verificar proveedor, copias locales y restauración. Reaplicar eliminaciones antes de admitir tráfico tras una restauración. Si no puede cumplirse, resolverlo antes de publicar ese compromiso. |
| Registros técnicos | Máximo aprobado de 30 días; excluir textos de listas, credenciales y transacciones firmadas completas. Verificar también los registros de proveedores. |
| Consultas de soporte | Máximo aprobado de 12 meses desde el cierre; una reclamación pendiente justifica únicamente los datos y el plazo específicos necesarios. |
| Evidencia comercial | Registro mínimo separado del perfil mientras exista un derecho de suscripción o una obligación concreta documentada; retirar al finalizar esa necesidad. No conservar identidad de acceso, listas ni grupos por este motivo. Es información seudónima, no anónima. |

La expiración de un comprobante no debe hacer desaparecer el trabajo antes de completarse. Los errores prolongados requieren intervención operativa y comunicación adecuada. Cualquier excepción legal de conservación se documenta por categoría, finalidad y duración; este diseño no determina por sí solo obligaciones fiscales ni permite retener todos los datos «por seguridad».

## Suscripción, notificaciones y nueva alta

La pantalla advierte que borrar la cuenta **no cancela la suscripción de Apple** y ofrece su gestión nativa. La app no puede declarar la renovación cancelada por haber abierto ese panel. No transfiere Premium al grupo, a otro miembro ni a producción al borrar Sandbox.

Al aceptar la eliminación se bloquea nueva concesión de derechos. La ingesta de compra, consulta de estado y V2 revalida la cuenta activa después de sus bloqueos. Cuando el UUID ya no existe, una notificación válida puede reconocerse sin recrearlo; deduplicación y mínima evidencia tienen su propia retención. Desconocer la cuenta nunca autoriza asignarla a la sesión de quien presente un JWS.

**Decisión aprobada: restauración nativa tras recrear cuenta.** Una vez confirmada la eliminación de la cuenta anterior, una cuenta nueva podrá recuperar mediante **Restaurar compras** el derecho que siga vigente usando la cuenta de compras de Apple original. No requiere guardar un código de recuperación. La nueva cuenta conserva un UUID nuevo: no recupera identidad, grupos, listas, borradores ni operaciones eliminados. La cuenta de compras de Apple y la identidad de Sign in with Apple no se presumen iguales.

Una cadena de suscripción pertenece como máximo a una cuenta Smart List activa. Restaurar no puede trasladarla desde otra cuenta todavía existente. La cancelación de renovación conserva el periodo vigente; una caducidad o revocación no genera un periodo nuevo. Se mantienen los estados válidos acreditados por Apple y las reglas de gracia del contrato vigente, sin reiniciar cortesías al recrear cuentas. Ninguna recuperación cruza Sandbox y producción.

Apple ofrece **Set App Account Token** para sustituir la asociación: modifica la renovación actual y futuras, no las transacciones pasadas, y no admite transacciones Family Shared. `appTransactionID` identifica una cuenta de compras y app, pero no es un secreto de autenticación. Un JWS válido acredita datos firmados; ni presentarlo ni invocar esta API demuestra por sí solo que el solicitante sea el comprador. La reasignación requiere evidencia actual y una petición protegida contra suplantación/replay, además de exclusividad, entorno y estado verificados en servidor. La implementación vincula un desafío a cuenta nueva, JWS exacto, entorno y clave App Attest. La app comprueba StoreKit y su `deviceVerification` antes de atestar; el servidor verifica la prueba, la identidad/build admitidos y el estado actual de Apple. La ruta ordinaria de restauración nunca acepta por sí sola una cadena desvinculada.

**Condición de validación antes de publicar:** el código local implementa la reasociación y su reserva persistente, pero falta acreditar el recorrido con Apple real y un build distribuido. Probar compra en A → eliminación A → alta B → restauración con el mismo comprador → renovación V2; repetir desde otro dispositivo, con otro comprador y con una cadena todavía vinculada a una cuenta activa. Cubrir notificaciones antiguas, caída de red durante reasignación, caducidad, revocación y concurrencia. En TestFlight no imponer sin comprobar la igualdad de identificadores entre cuenta de descarga y tester Sandbox. Una notificación antigua nunca vuelve a crear A ni cambia el titular nuevo. La evidencia comercial mínima sigue la retención anterior, sin conservar un HMAC permanente del sujeto Apple.

## Entornos y Sign in with Apple

La purga de datos y almacenamiento se limita al backend/namespace resuelto. Eliminar la cuenta de prueba no borra la cuenta, borrador ni listas de producción. Sin embargo, ambos recorridos usan la misma aplicación de Apple: la revocación de SIWA puede invalidar autorizaciones usadas en el otro entorno o aplicaciones agrupadas para SIWA. No prometer independencia total de autenticación. Verificar el alcance real en Sandbox y revisar la agrupación Apple antes de entregar; el resultado esperado ante una revocación externa es pedir de nuevo acceso, conservando los datos del entorno no eliminado.

### Reserva comercial y respuesta externa incierta

La reserva se persiste antes de enviar `Set App Account Token`. Los reintentos de la misma cuenta y prueba son idempotentes; una cadena todavía vinculada a otra cuenta activa no se puede trasladar. Si esa nueva cuenta se elimina mientras una reasociación está en vuelo o tuvo respuesta incierta, la reserva se anonimiza y queda en cuarentena. No se abre automáticamente la cadena a otra cuenta: una respuesta tardía de Apple podría sobrescribir su asociación. La cuarentena solo conserva entorno e identificador comercial; exige conciliación operativa antes de permitir otro titular. El borrado de datos no se bloquea por ello. Esta excepción debe explicarse con un error específico, sin afirmar que basta con reintentar.

La activación requiere `APP_ATTEST_APP_ID` y `APP_ATTEST_MIN_BUILD` del build que comprueba la transacción local. TestFlight utiliza atestación de producción aunque sus compras sean Sandbox. Sin configuración válida la recuperación falla de forma cerrada; no se sustituye por aceptar un JWS presentado por el cliente.

## Textos de interfaz propuestos

Los textos describen el comportamiento que se implemente y pruebe; cantidades y nombres de grupos proceden del servidor, con pluralización y localización. El aviso de suscripción siempre aparece, aunque no se pueda determinar su estado exacto.

| Contexto | Español | English |
|---|---|---|
| Entrada | Eliminar cuenta y mis datos | Delete account and my data |
| Explicación de prueba | Esta acción elimina tu cuenta y tus datos de prueba. | This action deletes your test account and test data. |
| Explicación | Se eliminarán tu cuenta y tus aportaciones a las listas compartidas. No podrás recuperarlas. | Your account and your contributions to shared lists will be deleted. You cannot recover them. |
| Grupos administrados | Los grupos con otros miembros quedarán pendientes de que uno de ellos acepte administrarlos. Podrán consultar y realizar las acciones permitidas por su acceso, además de salir del grupo. | Groups with other members will wait for someone to accept administration. Members can view and perform the actions allowed by their access, and leave the group. |
| Suscripción | Eliminar tu cuenta no cancela tu suscripción de Apple. Puedes gestionarla antes de continuar. | Deleting your account does not cancel your Apple subscription. You can manage it before continuing. |
| Acción de suscripción | Gestionar suscripción | Manage subscription |
| Acción final | Eliminar ahora | Delete now |
| Proceso durable | Eliminación en curso. Tu cuenta ya no puede utilizarse. | Deletion in progress. Your account can no longer be used. |
| Respuesta desconocida | No hemos podido confirmar el estado. Consulta la misma solicitud para comprobarlo. | We could not confirm the status. Check the same request to find out. |
| Recuperación | Comprobar eliminación | Check deletion status |
| Final | Cuenta eliminada | Account deleted |
| Apple no confirmado | Tus datos se han eliminado. No hemos podido confirmar la revocación del acceso con Apple; consulta cómo retirarlo desde tu cuenta de Apple. | Your data has been deleted. We could not confirm revocation of Sign in with Apple; see how to remove access from your Apple Account. |
| Grupo sin administrador | Este grupo necesita un administrador. Puedes asumir la administración; se aplicarán los límites de tu plan y tu acceso al grupo. | This group needs an administrator. You can accept administration; your plan limits and group access will apply. |
| Acción de grupo | Asumir administración | Accept administration |

El lector de pantalla anuncia progreso, errores y resultado; el foco vuelve a un destino estable. Usar confirmación nativa, contraste y orden de acciones claros, sin depender del rojo. Dynamic Type no puede ocultar la explicación ni «Cancelar». No repetir alertas cada vez que se recupera el primer plano.

## Casos de aceptación

La [validación local](../validation/issue-54-account-deletion-local.md) identifica los casos cubiertos con pruebas automatizadas y dobles. Esta lista también guía el ensayo distribuido y de infraestructura pendiente; no afirma que cada caso siga sin probar localmente.

- Cuenta sin grupos, miembro ordinario, último miembro, administrador multigrupo y contribuciones a grupos abandonados/cerrados.
- Purga de UGC propio en tablas y recibos ajenos; conservación de datos de terceros; procedencia antigua incompleta detectada, sin atribuciones inventadas.
- Repetición exacta, respuesta perdida antes/después del commit, caída del proceso entre fases, expiración del comprobante y petición antigua después de purgar su marcador.
- Login, alta de grupo, invitación, traspaso, edición, compra y notificación V2 concurrentes: sin escrituras después del cierre de acceso, deadlocks ni resurrección de datos.
- Dos miembros aceptando administración a la vez: uno gana, sin transferir suscripción ni consumir otra pertenencia; cupos gratuitos/excedidos y luego plan del nuevo administrador.
- Apple `/auth/revoke` 200, token ya inválido, ausencia de token, timeout y fallo permanente: resultados honestos y eliminación sin espera indefinida.
- Nueva cuenta con la misma identidad Apple; transacciones y V2 antiguas; restauración comercial según el mecanismo finalmente aprobado y probado.
- Borrado local con tareas/atajos en vuelo, otro dispositivo desconectado, Keychain bloqueado y cambio TestFlight/App Store: sin contaminar entornos ni reasignar operaciones.
- Restauración de copia con eliminaciones posteriores: las cuentas borradas no vuelven a ser accesibles antes de abrir el servicio.
- VoiceOver, texto máximo, cancelación, pérdida de red y retorno de segundo plano en ambos iPhone mediante distribución. Los tests de lógica de implementación usarán Swift Testing; estas comprobaciones aún no se han realizado.

## Implementación y condiciones de activación

Las decisiones de producto y el tratamiento del legado quedan aprobados el 9/11/2026. Las rutas y el worker están implementados localmente; no se ejecutan purgas sobre servicios alojados. El despliegue exige copia y restauración ensayadas, ventana sin escritores antiguos, configuración Apple y cliente 0.6 disponible.

1. Añadir y probar la frontera de revocación SIWA, conservando la distinción entre respuesta confirmada, token inválido y fallo temporal.
2. Registrar procedencia suficiente para futuras contribuciones y resolver el contenido histórico sin autoría verificable. Revisar la migración antes de activar el borrado; no inventar autores ni destruir aportaciones ajenas por inferencia.
3. Implementar esquema y estados, coordinación de escrituras, reautenticación con propósito, trabajo durable y seguimiento independiente de sesión. Adaptar recibos retirados de terceros y grupos pendientes de administración.
4. Completar la recuperación segura de Premium y su validación Apple; comprobar copias, logs, soporte y restauración con los plazos aprobados.
5. Versionar contrato/OpenAPI/DTO y conectar la UI accesible/localizada con limpieza local confirmada. Validar primero con datos de prueba. La publicación requiere textos coherentes con el resultado, identidad legal completa y un canal de soporte operativo.

No se ha aprobado una caducidad general de 30 días para productos comprados/cancelados o grupos cerrados por una salida ordinaria. Su contrato vigente se conserva; el borrado propio solicitado sí abarca esos registros. Los marcadores sin contenido de operaciones de terceros siguen su regla específica de idempotencia, no el plazo de logs.

### Evidencia histórica del primer bloque local — 9/11/2026

- [AppleGateway](../../server/Sources/SmartShoppingListServer/Identity/AppleGateway.swift) añade revocación mediante formulario firmado a `/auth/revoke`. Solo un `200` vacío confirma el resultado; redirecciones, errores OAuth, timeouts y respuestas inesperadas permanecen sin confirmar. No hay rutas que invoquen todavía esta operación ni cambios de login/cierre de sesión.
- [AddContentProvenance](../../server/Sources/SmartShoppingListServer/Persistence/AddContentProvenance.swift), registrada al arrancar, y las escrituras de tiendas/productos implementan la autoría por campo descrita arriba. No modifican los DTO públicos, no purgan datos ni atribuyen el legado. La reversión protege las atribuciones conocidas. Un despliegue no puede mantener escritores antiguos, aunque la API siga en 0.5.
- `swift build --build-tests --force-resolved-versions` y `swift test --skip-build`, desde `server/`, correctos con Apple Swift 6.4.2 en macOS y PostgreSQL local aislado: **170 pruebas en 10 suites**, incluidas 6 nuevas de procedencia y 5 de revocación (11 casos en estas últimas). La primera compilación de la suite nueva requirió añadir el import explícito `VaporTesting`; la repetición completa pasó. Se conserva únicamente el aviso externo [EXC-001 de JWTKit](../dependency-exceptions.md); sin nuevos warnings propios.
- Las pruebas de revocación verifican firma, campos, respuesta incierta y repetición mediante un oráculo local; no contactan Apple real. Las de procedencia recorren HTTP y PostgreSQL para comprobar altas, campos cambiados/idénticos, cantidades retiradas, tiendas nuevas/reutilizadas, replay, conflicto, rollback y preservación del legado. El ensayo de revocación registró fallos de comportamiento antes de implementar y pasó después.
- Validadores de contrato (31 operaciones, 125 ejemplos positivos y 47 negativos) y diseño correctos. Revisión independiente de arquitectura, pruebas y estilo sobre los 11 archivos Swift afectados, sin hallazgos tras corregir la referencia documental a la base histórica.

Esta evidencia corresponde al primer bloque local, todavía sin commit/push/despliegue. No acredita eliminación completa, revocación real de una cuenta, recuperación de compras tras borrado, configuración de retención, cliente iOS nuevo ni publicación de textos. El bloque posterior integra el contrato y la ejecución durable descritos arriba. La [validación final local](../validation/issue-54-account-deletion-local.md) se registra por separado; esta evidencia histórica no se extrapola a los cambios posteriores.

## Fuentes oficiales

Consultadas el 9 de noviembre de 2026:

- [Apple: Offering account deletion in your app](https://developer.apple.com/support/offering-account-deletion-in-your-app/): acceso en la app, datos asociados/contenido compartido, suscripciones y opción inmediata.
- [Apple TN3194: Handling account deletions and revoking tokens for Sign in with Apple](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple): revocación, tokens ausentes y estado de credenciales.
- [Apple: Token revocation](https://developer.apple.com/documentation/signinwithapplerestapi/revoke-tokens): contrato de la frontera de revocación usada por la implementación.
- [Apple: Set App Account Token](https://developer.apple.com/documentation/appstoreserverapi/set-app-account-token): reasociación de renovación actual y futuras; no modifica transacciones pasadas ni acredita titularidad por sí sola.
- [Apple: appTransactionID](https://developer.apple.com/documentation/storekit/apptransaction/apptransactionid): identificador estable de cuenta Apple y app, distinto de la identidad del servicio.
- [RGPD, artículos 5, 12, 17 y 19](https://eur-lex.europa.eu/eli/reg/2016/679/oj): minimización, información, supresión y comunicación a destinatarios. Las retenciones concretas aprobadas arriba son decisiones de producto pendientes de verificación operativa, no plazos atribuidos a esos artículos.
