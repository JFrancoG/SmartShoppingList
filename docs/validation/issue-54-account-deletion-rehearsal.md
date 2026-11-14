# #54 — Ensayo de eliminación de cuenta y recuperación de Premium

**Ensayo físico del 10–11 de noviembre de 2026.** En el iPhone 11 con Smart List 1.0 (6) de TestFlight Internal Only, la cuenta recreada recuperó la mensual de Sandbox, recibió su siguiente renovación y volvió al plan gratuito al caducar. El ensayo de Premium está cerrado. Se identificaron dos fallos de Ajustes al terminar el borrado.

### Resultados del build 6

A es la cuenta eliminada y B la cuenta creada después con la misma identidad de Sign in with Apple. Ambas usaron el mismo comprador Sandbox. La entrega inicial del build 6 y del servidor Sandbox correspondió a `9b58cca`. Horas de Madrid.

| Caso | Resultado observado |
|---|---|
| Borrado y alta de B | **Aprobado para el grupo exclusivo de A.** Al cancelar la vista previa se conservó el producto pendiente. Al confirmar el borrado, el servidor completó la purga y confirmó la revocación de Sign in with Apple. Se eliminaron A, su grupo, su tienda y su producto. La mensual quedó sin titular. B se creó con un identificador nuevo, sin grupos y con plan gratuito. |
| Primer intento de recuperar Premium | **Fallido (403).** Con la mensual vigente, el servidor emitió el desafío de App Attest (201) y rechazó la recuperación sin reasignar la compra. El registro de esa petición no permite identificar la comprobación exacta. En `4e823cb` se corrigió la lectura del recibo firmado de Apple en el servidor Sandbox y se mantuvo la comprobación de firma. |
| Restauración con la compra vigente | **Aprobado tras la corrección.** El periodo del intento anterior había caducado. El comprador reactivó la misma mensual desde los ajustes de Sandbox. Con esa cadena aún sin titular, B pulsó **Restaurar compras** una vez. El servidor aceptó el desafío (201), completó una única recuperación y respondió 200 a las 13:03. Apple y PostgreSQL coincidieron en que B era la única titular, con Premium hasta las 13:57. El contenido eliminado siguió ausente. |
| Reapertura y segunda restauración | **Aprobado.** Premium ya estaba activo al reabrir. Pulsar **Restaurar compras** conservó el mismo periodo y el mismo titular. El servidor seguía teniendo un solo trabajo de recuperación completado. |
| Renovación automática | **Aprobado.** La notificación V2 firmada `DID_RENEW` coincidió con el recibo guardado en Sandbox. La siguiente transacción amplió el periodo de B hasta las 14:57:52. Al entrar en Premium, el iPhone mostró las 14:57 sin intervención adicional. |
| Cancelación y fin del derecho | **Aprobado.** El servidor registró `AUTO_RENEW_DISABLED` y mantuvo Premium hasta el final del periodo. A las 14:57:52 caducó la mensual sin gracia. La notificación firmada `EXPIRED / VOLUNTARY` coincidió con el recibo de las 14:57:56. B tenía cero derechos Premium vigentes y el iPhone mostró **Plan gratuito**. Una última restauración mantuvo ese plan y mostró «No se ha encontrado una suscripción activa para esta cuenta de compras de Apple». |

### Incidencias de Ajustes observadas en el build 6

- Desde **Cuenta eliminada**, pulsar **Atrás** dejaba Ajustes en «Consultando el grupo…» y bloqueaba el acceso con Apple. Reabrir el resultado y pulsar **Hecho** permitió entrar. En el siguiente build se comprobará que, una vez completados el borrado y la limpieza local, **Atrás**, el gesto de volver y **Hecho** permiten iniciar sesión desde Ajustes.
- Al entrar como B, **Crear un grupo** conservaba el nombre que A había escrito en el formulario. PostgreSQL confirmó que el grupo anterior se había eliminado y que B no pertenecía a ningún grupo. En el siguiente build se comprobará que el campo aparece vacío para B.

### Corrección y prueba de la 1.0 (7)

En la 1.0 (7), Ajustes permite iniciar sesión cuando el servidor ha completado la eliminación y la app ha terminado su limpieza local. Un resultado guardado por el build 6 también se puede consultar desde Ajustes. **Hecho** cierra el resultado y tiene el mismo estilo que las demás acciones de la cuenta. El nombre escrito en **Crear un grupo** se borra al terminar la sesión y se conserva durante un refresco de la misma cuenta.

Xcode 27.2 ejecutó los planes Fast (517 ejecuciones) e Integration (22) en el simulador iPhone 18 Pro con iOS 27.0, sin fallos. Las regresiones cubren el acceso con un justificante completado guardado, la lectura o retirada fallida del justificante y la separación del texto del formulario entre cuentas.

**Prueba física del 14 de noviembre, iPhone 11, TestFlight 1.0 (7).** Se creó un grupo de prueba en lugar de dejar únicamente su nombre escrito; el ensayo continuó con una sola eliminación. Tras confirmar la solicitud y volver a Ajustes, quedó «Consultando el grupo…» y el botón de Apple no respondió. Deslizar para actualizar no cambió ese estado. Al reabrir **Eliminar cuenta**, aparecieron **Cuenta eliminada** y **Hecho**. Volver con **Atrás**, sin pulsar Hecho, permitió abrir la ventana de Apple y cancelarla. Después se comprobó el gesto de volver, se cerró el mismo resultado con **Hecho** y se inició sesión con la misma identidad Apple: el campo **Nombre del grupo** estaba vacío. Los dos arreglos del resultado completado quedan aprobados en ese dispositivo, sin repetir compras ni restauraciones.

El recorrido detectó otro caso: una solicitud enviada cuyo resultado aún no se ha actualizado bloquea el acceso, pero Ajustes la representa como una carga de grupos y su refresco no consulta la eliminación. Reabrir el detalle sí reconsulta el estado. El primer estado remoto no se capturó en el dispositivo; la revisión de código confirma que `refresh()` y la activación de la app descartan este refresco por el bloqueo genérico o por la ausencia de sesión. La corrección debe conservar la protección mientras el borrado o la limpieza local sigan pendientes y ofrecer su estado y una consulta explícita en Ajustes.

### Corrección del estado pendiente — 14 de noviembre

Actualizar desde Ajustes o volver a primer plano consulta ahora la solicitud enviada antes de aplicar el bloqueo genérico de la sesión. Ajustes muestra el estado de eliminación, su error cuando lo hay y **Comprobar el estado de eliminación**; solo presenta progreso durante una consulta real. El resultado completado permanece visible hasta retirar el comprobante. El acceso con Apple sigue protegido hasta que también termina la limpieza local. La pantalla de eliminación explica que primero se verifica la identidad con Apple y sus acciones tienen un estilo de botón visible.

Se reprodujo la regresión en el mismo ViewModel: sesión válida → solicitud aceptada → limpieza local → refresco manual o activación → finalización. Las cuatro ejecuciones iniciales fallaron porque no se consultaba el estado. Tras corregirlo, Xcode 27.2 (27B52) ejecutó **523 casos Fast y 22 Integration**, en iPhone 18 Pro con iOS 27.0, sin fallos, omisiones, avisos de ejecución ni diagnósticos de compilación. Los seis casos nuevos también cubren error de red, consultas solapadas y fallo/reintento de escritura local, sin repetir la solicitud de borrado. La revisión independiente de Swift, concurrencia y accesibilidad estática no dejó hallazgos.

La preview normal de Ajustes se inspeccionó en iPhone 18 Pro Max con iOS 27.2. Se generó también AX5 en iOS 27.0, pero su encuadre inicial no llega a los controles de eliminación. Otras variantes fallaron antes de ejecutar la app con `Library not loaded: /usr/lib/libSystem.B.dylib` en el runtime de previews. **Pendientes antes del siguiente build:** completar la inspección visual de los controles con texto grande y preparar un nuevo Archive. Esta corrección adicional aún no se ha distribuido ni probado físicamente; no modifica el servidor ni producción.

Base técnica: [validación local](issue-54-account-deletion-local.md), [diseño de eliminación](../architecture/account-deletion.md), [entornos de distribución](../architecture/distribution-environments.md), [servidor](../../server/README.md) y [configuración de compras](../setup/premium-subscriptions.md). La evidencia local y la de builds anteriores no sustituyen este ensayo.

## Alcance y condiciones de entrada

El ensayo no modifica la API, PostgreSQL, variables, despliegue, DNS, URL de notificaciones ni datos de producción. Tampoco utiliza cuentas reales para demostrar un efecto de revocación sobre producción. La preparación de este documento no ejecuta ninguna acción externa. Antes de la ventana se identificarán el commit y los recursos concretos incluidos en el ensayo autorizado.

| Condición | Evidencia necesaria antes de continuar | Estado al preparar el ensayo (9 de noviembre) |
|---|---|---|
| Revisión entregada | SHA de PR revisada y CI correcta sobre ese SHA; relación entre SHA de servidor y Archive. | Pendiente |
| Recursos Sandbox | Proyecto/entorno, API, PostgreSQL y volumen exactos, revisión desplegada y destino de sus referencias. Confirmar que cualquier despliegue automático queda dentro del alcance aprobado. | Pendiente |
| Identidades seguras | Matriz privada de SIWA, acceso TestFlight y comprador Sandbox; ninguna autorización de producción o de otra app real puede verse afectada por las identidades que se eliminarán. | Pendiente |
| Datos destinados a prueba | Inventario de todas las pertenencias y aportaciones de A, incluidas antiguas/cerradas; todos sus efectos de purga están aceptados para este ensayo. | Pendiente |
| Copia recuperable | Copia Sandbox cifrada, restaurada y comprobada en una base aislada antes de migrar; ubicación y retención privadas. | Pendiente |
| Entrega coordinada | Backend y clientes 0.6, sin escritores del servidor anterior; instalación compatible preparada para ambos iPhone. | Pendiente |
| Apple y firma | Configuración Sandbox y App Attest comprobada, perfil de distribución válido, Archive y build procesado como Internal Only. | Pendiente |
| Observación | Acceso de lectura a estado de trabajo, propiedad de la suscripción y recepción V2, sin exportar credenciales ni payloads firmados. | Pendiente |

### Identidades: tres funciones distintas

| Alias privado | Función | Restricción |
|---|---|---|
| `TF16` / `TF11` | Cuenta Apple real que descarga el build desde TestFlight. | Tester interno con acceso a `core`. No confundir con la identidad de Smart List ni con el comprador. |
| `SIWA-A` | Identidad de Sign in with Apple para crear A y, después del borrado, B. | Identidad dedicada sin uso en producción ni autorizaciones reales en apps agrupadas. B tendrá un UUID nuevo aunque use la misma identidad Apple. |
| `SIWA-C` | Identidad del otro miembro, si se ensaya el grupo compartido en el iPhone 11. | También dedicada; sus datos son sintéticos y se conservan al borrar A. |
| `BUYER-1` | Tester de compras Sandbox que compra para A y restaura para B. | Mantener el mismo comprador durante el recorrido; registrar su renovación acelerada vigente sin asumir la duración histórica. |
| `BUYER-2` | Otro tester Sandbox para el control negativo posterior. | No debe poseer la cadena comprada por `BUYER-1`. |

**La separación de bases no aísla la revocación SIWA.** El proyecto distribuye el mismo bundle ID y utiliza Sign in with Apple, cuya revocación llama a Apple, no a un servicio de identidad Sandbox independiente. Revisar en Apple Developer el App ID primario y su agrupación, sin modificarlos. El [diseño del proyecto](../architecture/account-deletion.md#entornos-y-sign-in-with-apple) trata como posible efecto la invalidación de autorizaciones del otro entorno o de apps agrupadas; no se presupone un alcance menor al token presentado. [Apple TN3194](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple) documenta la revocación y su alternativa manual.

Los correos y las cuentas usados en pruebas anteriores **no quedan seleccionados automáticamente**. Antes de eliminar, el propietario identificará una cuenta SIWA dedicada que no use producción ni apps reales relacionadas. Si los iPhone 16 y 11 no pueden utilizar esas identidades sin alterar su uso personal, el ensayo destructivo se detiene hasta disponer de una preparación segura de dispositivos. No cerrar la sesión principal de iCloud, borrar una cuenta existente ni cambiar la agrupación SIWA para resolverlo de forma improvisada. Elegir un tester de compras nuevo, por sí solo, no resuelve esta condición.

## Preparar Sandbox y el build

### Copia, migración y compatibilidad

1. Inventariar la revisión, las migraciones aplicadas y los datos de Sandbox. Verificar qué usuarios dependen de este backend: la actualización 0.6 afectará también a testers ajenos al ensayo que sigan con un cliente anterior.
2. Crear una copia lógica consistente de **Sandbox**, por ejemplo en formato `pg_dump -Fc`, usando credenciales por un canal privado. Cifrar el archivo fuera del repositorio, conservar su checksum y comprobar que se dispone de las versiones de claves necesarias para una recuperación autorizada. Confirmar la disponibilidad actual de copias del proveedor; no suponer que el plan contratado las ofrece.
3. Restaurar esa copia en PostgreSQL aislado, sin endpoints públicos, clientes ni salida a Apple. Comparar migraciones, tablas, recuentos y comprobaciones de integridad. No arrancar contra esa copia un worker con credenciales Apple reales: podría revocar autorizaciones o modificar asociaciones comerciales. Ensayar allí las nuevas migraciones y la purga con datos sintéticos o expresamente destinados a prueba; registrar duración y resultado.
4. Preparar el Archive y su distribución interna compatible antes de retirar el servicio antiguo. En la ventana Sandbox, detener sus escritores, tomar la copia final consistente y desplegar una única revisión nueva. El arranque ejecuta migraciones: no mezclar procesos antiguos y nuevos ni dar por segura una reversión de esquema.
5. Verificar `/hello`, cierre de `/todos`, esquema y worker. Una petición controlada sin contrato a `/v1/me` debe obtener `426 client_update_required`; con `X-SmartList-Contract: 0.6` y sin sesión válida debe obtener el error de autenticación esperado. La excepción es `/v1/app-store/notifications`, que conserva su verificación Apple sin ese header. No usar un bearer real en comandos o logs públicos.
6. Instalar el cliente compatible en los dos dispositivos del ensayo. Los builds anteriores, incluido el 1.0 (5) histórico, no acreditan compatibilidad con 0.6. No desbloquearlos quitando el middleware ni añadiendo un header desde un proxy.

### Configuración verificable

Comprobar presencia, coherencia y resultado sin imprimir secretos. Completar las variables únicamente en el servicio Sandbox durante su ventana autorizada.

| Elemento | Valor o comprobación |
|---|---|
| Vapor y base | Arranque `--env sandbox`; referencias de `DATABASE_*` y CA únicamente al PostgreSQL Sandbox. |
| Origen de API e invitaciones | `https://smartshoppinglistsandbox-sandbox.up.railway.app`, confirmado contra los recursos actuales. Release debe resolver Sandbox mediante `AppTransaction` verificada antes de cargar la sesión. |
| SIWA y cifrado | Familia `APPLE_*` completa, client ID correcto y claves de cifrado disponibles. Claves separadas no crean por sí solas aislamiento de autorización SIWA. |
| Compras | Familia `APP_STORE_*` completa y `APP_STORE_ENVIRONMENT=Sandbox`; productos mensual/anual y grupo comercial correctos. La clave In-App Purchase es distinta de la de SIWA. |
| Notificaciones | Sandbox Server URL de App Store Connect apunta al endpoint Sandbox `/v1/app-store/notifications` con V2. No cambiar la URL de producción ni depender del fallback hacia ella. |
| App Attest | `APP_ATTEST_APP_ID` igual al `application-identifier` firmado: prefijo real de diez caracteres y `com.plusprojects.SmartShoppingList`. Verificar el prefijo del perfil, no asumir que siempre coincide con Team ID. |
| Build mínimo | `APP_ATTEST_MIN_BUILD` igual al primer build distribuido y comprobado que contiene este recorrido. Determinarlo tras consultar App Store Connect y verificar el Archive. |
| Desarrollo | `APP_ATTEST_ALLOW_DEVELOPMENT=false`. No relajar la validación si falla TestFlight. |
| Recursos del servidor | Imagen contiene las raíces públicas App Attest y Apple G3 en el bundle SwiftPM; arranque y recuperación configurados sin fallback a un JWS sin atestación. |

TestFlight usa **App Attest de producción**, aunque las compras y los datos de Smart List sean Sandbox. Es el servicio de atestación de Apple, no una compra ni una escritura en nuestro backend de producción. [Apple documenta este comportamiento de distribución](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.devicecheck.appattest-environment).

### Archive, carga e instalación

1. Consultar App Store Connect para elegir un número libre; registrar versión/build y SHA exactos. No usar el diagnóstico antiguo ni asignar aquí el siguiente número.
2. Crear Archive Release del target comercial con Xcode. Inspeccionar firma y perfil: bundle ID, `application-identifier`, Sign in with Apple, App Attest y dominios asociados previstos. Confirmar que el nombre visible sigue siendo **Smart List** y que el Archive contiene eliminación y restauración verificadas.
3. Cargar por **TestFlight Internal Only**, esperar procesamiento y revisar los avisos de Apple. Añadir el build concreto a `core`; no presentarlo a App Review, pruebas externas ni App Store. Confirmar la asignación y la versión instalada en cada iPhone.
4. Descargar desde TestFlight con la cuenta real autorizada. Para controlar el comprador Sandbox, después de instalar seguir el recorrido de Apple: cerrar únicamente **Contenido y compras**, acceder al tester en **Desarrollador → Cuenta de Apple de Sandbox** y abrir Smart List desde su icono. No intentar acceder a TestFlight con el tester Sandbox. Volver a entrar en Contenido y compras cambia la atribución de compras de TestFlight; no hacerlo a mitad de la prueba. [Instrucciones oficiales de Sandbox para TestFlight](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox).
5. Comprobar **Datos de prueba**, acceso al entorno esperado y catálogo Sandbox. Si no puede verificarse el entorno, detenerse antes de iniciar sesión o comprar; no forzar la URL de producción como respaldo. No desinstalar la app ni borrar el Keychain para recuperar un estado dudoso.

## Recorrido mínimo: compra A → borrado A → alta B → restauración → V2

Usar alias en el informe y nombres sintéticos, por ejemplo `Ensayo eliminación`, `Tienda ensayo`, `Producto A` y `Producto C`. No reutilizar `Test1`, Aldi, Alpro ni grupos históricos sin revisar todos sus datos y acordar expresamente su eliminación.

| Paso | Acción física y observación privada del backend | Resultado exigido |
|---|---|---|
| 1. Crear A | En el dispositivo preparado para A, iniciar sesión con `SIWA-A`; anotar privadamente su UUID. Confirmar que no aparece contenido previo inesperado. | Cuenta nueva de Sandbox, sin datos reales ni operaciones heredadas. |
| 2. Comprar | Comprar mensual con `BUYER-1`, una vez. Comprobar Premium, periodo vigente, entorno y asociación comercial de la cadena con A. Esperar o consultar la V2 de compra sin inventar que ya llegó. | Backend y UI concuerdan; derecho Sandbox atribuido a A, sin concesión manual. |
| 3. Preparar contenido | A crea un grupo con un producto propio. Si el iPhone 11 usa `SIWA-C`, C se une y añade `Producto C`; después A crea un grupo solo suyo con texto sintético. Anotar contenido esperado de cada autor. | Todo lo que puede verse afectado está destinado a prueba; se podrá distinguir purga propia, conservación de C y eliminación del grupo sin otros miembros. |
| 4. Previsualizar y cancelar | A abre Ajustes → eliminación de cuenta. Revisar grupos, efectos y aviso de que la suscripción no se cancela. Con VoiceOver y texto máximo comprobar lectura y controles. Cancelar la preparación una vez, volver a abrir y revisar el impacto actualizado. | Cancelar antes de aceptar mantiene cuenta y datos; no queda un trabajo aceptado oculto. Si aparece texto histórico incierto o un grupo no inventariado, parar. |
| 5. Aceptar | Reautenticar a `SIWA-A` y confirmar una sola vez. Registrar hora y comprobante únicamente en el almacén privado. Cerrar/reabrir la app y consultar **la misma solicitud** si no se conoce el resultado. | Estado durable; cuenta bloqueada desde `accepted`; no se crea una segunda solicitud tras pérdida de respuesta. |
| 6. Verificar purga | Esperar resultado y consultar estado del job. Comprobar ausencia de A, sesiones/grants utilizables y contenido propio; cadena comercial desvinculada sin recuperar identidad. En iPhone 11, C comprueba su producto y el grupo pendiente de administración; puede asumirla una vez. | `completed` con resultado Apple explícito. Para cerrar el recorrido automático se exige `confirmed`; `manual_action_required` acredita un resultado distinto y requiere resolverlo antes de continuar. Grupo exclusivo eliminado; aportaciones comprobadas de C conservadas. |
| 7. Alta B | Tras completar, solicitar un nuevo acceso SIWA con la misma identidad dedicada. Registrar que UUID B es diferente de A. | Cuenta vacía: sin pertenencias, borrador ni operaciones de A. Un desafío nuevo puede entrar inmediatamente; los anteriores no deben recrear A. |
| 8. Recuperar Premium | Mantener `BUYER-1`; pulsar **Restaurar compras** una vez, sin comprar de nuevo. Observar resultado de recuperación, propietario de la misma cadena y periodo actual. | App Attest real aceptada; job comercial `completed`, cadena exclusivamente vinculada a B y Premium vigente. No reaparecen listas ni grupos de A; no se inicia un periodo por cálculo local. |
| 9. Reabrir/restaurar | Cerrar/reabrir Smart List en B y restaurar una vez más. | Mismo titular y derecho, sin compra nueva, duplicados ni cambio de cuenta. |
| 10. Renovación V2 | Esperar una renovación real según el ritmo actual de `BUYER-1`. Correlacionar tipo/fecha de V2, procesamiento durable, estado firmado actual de Apple y periodo mostrado. | Renovación atribuida a B; A sigue ausente. Un TEST o un `204` aislado no acredita esta renovación ni su asignación. |

La reasociación utiliza [Set App Account Token](https://developer.apple.com/documentation/appstoreserverapi/set-app-account-token). Mantener la misma cadena y el mismo comprador; no editar `appAccountToken` en PostgreSQL ni llamar manualmente a esa API para hacer pasar el ensayo.

### Comprobaciones siguientes, después del recorrido principal

| Caso | Preparación y criterio |
|---|---|
| Otro comprador | En una cuenta de servicio de ensayo sin derecho, usar `BUYER-2`: Restaurar no debe recibir la cadena de `BUYER-1` ni cambiar a B. No provocar una compra adicional para disimular un rechazo. |
| Cadena con titular activo | Con B todavía activa, intentar restaurar su cadena desde C y `BUYER-1`, solo si la preparación segura del segundo dispositivo lo permite. Debe conservar a B como titular; el JWS del comprador no autoriza trasladarla. |
| Otro dispositivo | Con el mismo build y cuentas correctas, abrir B en el segundo dispositivo y restaurar. Debe mantener titular y periodo. La posibilidad real de seleccionar esa identidad SIWA se comprueba antes; no se improvisa un cambio de iCloud. |
| Limpieza remota | En un ciclo separado, preparar la misma cuenta A de prueba en ambos dispositivos **antes** de eliminar. Tras aceptar desde uno, el otro conectado confirma eliminación y limpia solo ese contexto. Un fallo de red conserva lo necesario para comprobarla después y bloquea envíos. No mezclar este montaje con C como miembro observador. |
| Red y estado incierto | En un ciclo dedicado, interrumpir solo la conexión del iPhone, nunca el backend ni Apple. Reabrir y consultar la misma eliminación o repetir Restaurar con su prueba persistida. Si aparece `subscription_recovery_pending_review`, parar y conciliar; no borrar el estado ni crear sucesivos titulares. |
| Fin del derecho | Caducidad por cancelación y restauración posterior **aprobadas** en el build 6. La revocación o el reembolso son casos distintos. |

Quedan pendientes el grupo con otro miembro y sus aportaciones, los controles con otro comprador o una cadena que ya tenga titular, el segundo dispositivo, la limpieza remota y los fallos de red. La comprobación física de VoiceOver y texto máximo en la vista previa de eliminación también queda pendiente. No repetir compras ni eliminaciones de una matriz ya acreditada salvo que el cambio o un fallo concreto lo justifique.

## Evidencia y criterios de parada

Informe público mínimo: fecha/huso, SHA, versión/build, dispositivo/iOS, alias A/B/C, paso ejecutado, resultado observado, capturas recortadas y limitaciones. Mantener **fuera del repositorio, PR y logs públicos** correos, Apple subject, UUID de cuenta, IDs de transacción, comprobantes/secrets, bearers, tokens, JWS, atestaciones, claves y copias de base. Usar correlaciones privadas para demostrar `A ≠ B`, misma cadena y entorno; publicar solo la conclusión comprobada. No activar logging de cuerpos para investigar un fallo.

Detener compras, nuevas eliminaciones y reasociaciones si ocurre cualquiera de estos hechos:

- Identidad SIWA compartida con producción, entorno indeterminado/Production, datos no destinados a prueba o configuración de notificaciones que pueda caer en producción.
- No existe copia restaurada, no está claro el destino de una credencial/referencia, hay escritores antiguos o no se puede instalar el cliente 0.6.
- Fallo de firma/App Attest, `503` persistente, revocación manual inesperada, trabajo que no progresa, o imposibilidad de correlacionar UI y estado durable.
- Se restaura A, reaparece contenido eliminado, se pierde contenido ajeno comprobado, dos cuentas reciben la misma cadena o una V2 cambia el titular incorrectamente.
- Recuperación en cuarentena, aceptación incierta o error de persistencia local: conservar la evidencia y consultar la misma operación; no «resetear» claves, Keychain, jobs ni base.

El reintento de consultas puede ser seguro; una nueva compra, nuevo borrado o liberación de una reserva no se deduce de que haya transcurrido tiempo. Una espera de cinco minutos tampoco demuestra por sí sola purga, revocación ni renovación.

## Recuperación operativa y cierre

- Antes de aceptar una eliminación, se puede cancelar la preparación. Después de `accepted`, la eliminación es irreversible; cerrar la app o restaurar una copia no la cancela.
- Ante un fallo del despliegue Sandbox, detener sus escritores y elegir una corrección hacia delante que preserve trabajos, comprobantes y reservas. No arrancar un servidor anterior sobre el esquema nuevo ni eludir sus guardas de reversión.
- Una restauración se ensaya primero en una base aislada. No exponer una copia que devuelva cuentas o contenido ya eliminados: hay que acreditar cómo reaplicar las supresiones aceptadas y reconciliar las operaciones posteriores a la copia antes de admitir tráfico. Si no puede demostrarse, no abrir esa restauración.
- PostgreSQL no revierte la revocación SIWA ni un `Set App Account Token` ya ejecutado en Apple. Un backup anterior tampoco permite liberar una reserva incierta: contrastar el estado actual de Apple y resolver la cuarentena mediante un procedimiento específico, sin reactivar A.
- Mantener la copia y evidencia privada según la retención aprobada y destruirlas al vencer. No conservar dumps ni datos eliminados como fixtures permanentes. Registrar cuándo se han retirado las credenciales de prueba de los dispositivos, sin cambiar sus cuentas personales de forma automática.

El cierre registrará cada paso como **aprobado, fallido o no ejecutado**, las incidencias encontradas y los límites de evidencia. Este ensayo puede acreditar el recorrido distribuido Sandbox; no autoriza ni acredita una migración, eliminación, compra, envío a App Review o publicación en producción.
