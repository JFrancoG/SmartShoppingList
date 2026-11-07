# Entornos de distribución y compras

Fecha: 29 de octubre de 2026. Seguimiento: [#54](https://github.com/JFrancoG/SmartShoppingList/issues/54).

Estado vigente, **7 de noviembre de 2026**: implementación integrada en
`codex/issue-54-production-readiness`. El diagnóstico TestFlight **1.0 (1)** obtuvo
`Verificada / sandbox`. El build comercial **1.0 (4)** tiene aceptación física de arranque,
compra/restauración, notificaciones V2, controles, dictado/Siri, invitación y sincronización entre
los dos iPhone. La [evidencia fechada](../validation/issue-54-distribution-environments.md) delimita
cada resultado. Se consolidan las correcciones de [#49](../validation/ui-controls-and-refresh-review.md)
para comprobarlas en el siguiente build interno; App Review, sustitución desde/hacia App Store y
publicación mantienen sus comprobaciones propias.

**Decisión de producto aprobada el 29 de octubre:** el propietario confirma «Sí, mantener los datos
separados». TestFlight utiliza cuentas y listas de prueba; App Store recupera su contexto de
producción, sin trasladar datos ni derechos de prueba. La selección se realiza antes de construir
sesión, almacenamiento y servicios. La aceptación TestFlight no acredita el recorrido App Store.

## Problema y hechos comprobados

Apple documenta que [App Review evalúa las compras en Sandbox][review] y que
[las apps de TestFlight operan sus compras en Sandbox][testflight]. El archivo que se distribuye debe
permitir ese recorrido y el posterior uso comercial, sin recompilar para cambiar de destino.

La revisión del código parte de `main` en `e3d47c66ac57349cedfb518d3e9491e033d90387`:

| Frontera actual | Consecuencia para distribución |
|---|---|
| [Build Settings](../../ios/SmartShoppingList/SmartShoppingList.xcodeproj/project.pbxproj): Debug usa API/invitaciones Sandbox y Release usa Production; mismo bundle ID. El esquema archiva con Release. | El archivo actual no selecciona el recorrido de revisión. Cambiar permanentemente Release a Sandbox tampoco prepara la app comercial. |
| [configure.swift](../../server/Sources/SmartShoppingListServer/configure.swift): un gateway y una política de capacidad por proceso; Vapor `production` exige Apple `Production`. | El servidor rechaza correctamente compras Sandbox en producción. Se conserva esta guarda. |
| [AppStoreGateway](../../server/Sources/SmartShoppingListServer/Subscriptions/AppStoreGateway.swift): verifica firma, entorno, aplicación, productos, grupo comercial y evidencia actual de Apple. | Un resultado del cliente no concede derechos; no hay fallback entre las API de Apple. |
| [SubscriptionService](../../server/Sources/SmartShoppingListServer/Subscriptions/SubscriptionService.swift): `appAccountToken` es el UUID de la cuenta de esa base y se obtiene antes de comprar. | Comprar primero y elegir servidor después mezcla identidades. |
| [Migración de derechos](../../server/Sources/SmartShoppingListServer/Persistence/AddAccountPremiumAccess.swift) y [de compras](../../server/Sources/SmartShoppingListServer/Persistence/AddAppStoreSubscriptions.swift): derechos y recibos distinguen entorno, pero la elección gratuita vive en `users`. | Tener columnas de entorno en compras no separa todos los datos de la aplicación. |
| [StoreCapacity](../../server/Sources/SmartShoppingListServer/Shopping/StoreCapacity.swift): tiendas y pendientes usan el plan del administrador para todos los miembros. | Un derecho de prueba aplicado sobre un grupo real también afectaría a otros miembros. |
| [SharedAppStorage](../../ios/SmartShoppingList/SmartShoppingList/App/SharedAppStorage.swift): namespace estable por pareja de orígenes de API/invitaciones; producción conserva el histórico. | Ya permite separar sesiones, borradores y operaciones sin mover ni borrar datos. |
| [SharedAppFactory](../../ios/SmartShoppingList/SmartShoppingList/App/SharedAppFactory.swift) y [App](../../ios/SmartShoppingList/SmartShoppingList/App/SmartShoppingListApp.swift): construcción síncrona y registro de App Intents al arrancar. | La selección asíncrona requiere una fase explícita antes de componer ese contexto. |
| [Entitlements](../../ios/SmartShoppingList/SmartShoppingList/Resources/Configuration/SmartShoppingList.entitlements) y [parser de invitaciones](../../ios/SmartShoppingList/SmartShoppingList/Services/SharedAPI/SharedAPIConfiguration.swift): un dominio asociado y aceptación del origen exacto. | El archivo que soporte ambos recorridos necesita ambos dominios autorizados; cada recorrido sigue aceptando exclusivamente su origen. |

La [#39](https://github.com/JFrancoG/SmartShoppingList/issues/39) está cerrada y acredita su matriz Sandbox.
Su [conciliación final](../validation/issue-39-premium-subscriptions.md) conserva las fuentes y límites.
No acredita una instalación TestFlight ni convierte la infraestructura histórica en configuración vigente.
Esta revisión no consulta Railway, App Store Connect ni datos alojados.

## Propuesta: separar el recorrido completo

Reutilizar las dos API y bases independientes. Un contexto resuelto al arrancar contiene API, origen de
invitaciones, almacenamiento y entorno esperado de compras. Es inmutable durante esa ejecución.

| Recorrido propuesto | Datos, identidad y autoridad |
|---|---|
| Distribución con evidencia Sandbox compatible | API y PostgreSQL Sandbox; cuentas, grupos, `appAccountToken`, sesiones y cuotas propios. |
| Distribución con evidencia Production compatible | API y PostgreSQL Production; datos reales y derechos verificados de Production. |
| Debug de desarrollo | Destino Sandbox explícito existente; las herramientas y datos sintéticos siguen confinados al desarrollo. |
| Evidencia ausente, no verificada, desconocida o incompatible | Acceso compartido y compras pendientes de recuperación; sin seleccionar Production por defecto ni contactar al otro servidor. |

La misma identidad de Sign in with Apple puede autenticarse en ambos servidores, pero eso no vuelve
intercambiables sus UUID de cuenta, sesiones o tokens de compra. Cada servidor conserva su configuración
Apple y base. Ningún selector del cliente puede convertir evidencia Sandbox en un derecho Production.

La decisión de producto aprobada establece: **TestFlight usa listas de prueba y no muestra las listas
reales**. Instalar App Store recupera el contexto de producción; no importa las listas ni compras de prueba.
La app debe explicar con claridad el uso de datos de prueba, sin exponer detalles técnicos innecesarios.
Si se necesita colaborar sobre grupos reales desde TestFlight, hay que revisar esta propuesta: mezclar
datos exige definir primero cómo evitar que las compras de prueba alteren capacidades compartidas.

## Selección antes de iniciar sesión: evidencia TestFlight y límites pendientes

La candidata es [`AppTransaction.shared`][app-transaction], aceptando únicamente un resultado
verificado y consultando su [`environment`][app-environment]. Apple ofrece esta información desde el
primer lanzamiento sin exigir una compra dentro de la app. Describe el entorno que firma la transacción
de la aplicación; **no se considera aquí una garantía ya ensayada de identificación de App Review**.

El resultado propuesto es Sandbox → contexto Sandbox; Production → contexto Production. La observación
del diagnóstico distribuido confirma Sandbox en el ensayo TestFlight identificado abajo. El contexto
Production y el recorrido de revisión conservan su comprobación propia pendiente; no se deducen solo
de que las compras de App Review sean Sandbox. Si aparece una transacción
de compra de un entorno incompatible con el contexto, se conserva pendiente y se informa del problema;
no se cambia de API después de haber obtenido la cuenta o su `appAccountToken`.

`shared` es asíncrona y puede fallar; el arranque debe admitir cancelación, error de verificación,
indisponibilidad de red y reintento expreso. Una transacción verificada disponible localmente puede
resolver el contexto sin una llamada de red propia. No se introduce una preferencia persistida como
respaldo de autoridad: podría sobrevivir al reemplazo TestFlight ↔ App Store. Sin evidencia válida, se
conservan los archivos y no se carga una sesión o borrador de un origen elegido por suposición.

[`AppTransaction.refresh()`][app-refresh] puede solicitar autenticación y queda reservado a una acción
expresa del usuario. No se llama automáticamente para completar el arranque. No se usa el nombre de un
recibo, `DEBUG`, una invitación, una transacción histórica ni un error del backend para adivinar el canal
de un archivo distribuido. Tampoco se concede Premium a partir de `AppTransaction`: las compras conservan
la verificación del servidor y el [contrato 0.5](../contracts/premium-subscriptions.md).

**Evidencia técnica acotada:** el 29 de octubre a las 18:18 CET, el propietario abre desde TestFlight
`DistributionDiagnostics` **1.0 (1)** en su **iPhone 16 / iOS 27.2** y realiza una consulta manual.
La [captura conservada](../validation/evidence/issue-54-testflight-apptransaction-1.0-1.png) muestra
**Verificada / sandbox**. El diagnóstico no inicia sesión propia ni realiza compras; esta observación
permite avanzar a la integración del arranque que seleccione el contexto Sandbox antes de componer
sesión y datos. No es una prueba de cuenta sin historial de compras, funcionamiento sin red, App Review
ni descarga comercial de App Store. Los registros solo contendrán resultado de verificación, entorno y build; nunca JWS, identificadores
de cuenta, credenciales o claves. Si la evidencia no permite resolverlo antes del login, se reabre la
elección arquitectónica y no se debilitan las guardas del servidor.

La [primera comprobación local](../validation/issue-54-distribution-environments.md) compila y ejecuta
un fragmento con Xcode 27.1/iOS 27.0 Simulator: el fragmento clasifica el error como `unavailable`.
No se obtiene entorno verificado ni se infiere el canal de distribución. En aquella primera comprobación no se había modificado la composición de la app
comercial. Después, el propietario autoriza preparar el target independiente
`DistributionDiagnostics`: consulta manual de `AppTransaction.shared`, sin cargar sesión, listas,
compras ni App Intents de la app. Su [validación local y procedimiento de distribución](../validation/issue-54-distribution-environments.md#diagnóstico-distribuible-preparado)
conservan los límites de evidencia. El ensayo TestFlight posterior ya obtiene el resultado verificado,
pero el diagnóstico no implementa el enrutamiento propuesto.

## Composición, persistencia y operaciones

1. Incorporar una fase de arranque explícita con estados de resolución, listo y recuperación. Mantener
   `@MainActor` para el estado de presentación y la composición existentes; sin esperas bloqueantes,
   escapes de concurrencia ni una segunda instancia de la aplicación.
2. Resolver uno de los destinos HTTPS permitidos incluidos en el archivo. Construir después
   `SharedAPIConfiguration`, `SharedAppStorage`, borrador, Keychain, API y coordinación de compras.
   No restaurar sesión, emitir login, pedir catálogo ni publicar dependencias de App Intents antes.
3. Reutilizar exactamente los namespaces existentes. Conservar el de producción y el Sandbox actual;
   no crear otro namespace solo por instalar TestFlight ni migrar sus datos al pasar a App Store.
   Cambiar de distribución sustituye el binario del mismo bundle ID, no instala una segunda app.
4. Arrancar cada proceso con su contexto; no cambiarlo por un enlace, una compra o un resultado tardío.
   Los trabajos asíncronos, suscripciones a updates y resultados deben quedar ligados a esa instancia,
   con cancelación y descarte de resultados ajenos. App Intents espera resolución o devuelve recuperación
   explícita; no obtiene como respaldo la instancia de otro contexto.
5. [StoreKitSubscriptionStore](../../ios/SmartShoppingList/SmartShoppingList/Services/SharedAPI/StoreKitSubscriptionStore.swift)
   debe conservar el entorno verificado de cada transacción y filtrar compras/restauraciones/updates
   incompatibles antes de enviarlos. Esto complementa la verificación obligatoria del servidor.
   No finalizar una transacción incompatible ni marcarla verificada en otro contexto.
6. Mantener bearer, invitaciones pendientes, `operationId`, cuenta, grupo, payload y verificaciones
   pendientes dentro de su namespace. Una operación incierta conserva identidad y destino originales;
   no se reenvía al servidor del nuevo contexto ni se elimina para facilitar el cambio.
7. Incluir ambos Associated Domains en el artefacto distribuido y comprobar el AASA de cada origen.
   Si un enlace llega durante el arranque, esperar la resolución sin persistirlo en un origen supuesto;
   validar después el origen exacto. Un enlace del otro recorrido muestra una explicación y no provoca
   conmutación, aceptación ni traslado de sesión.

El nombre visible es **Smart List** en ambas configuraciones; Sandbox se identifica mediante el aviso
de datos de prueba. Release conserva la exclusión de herramientas DEBUG. Las nuevas experiencias
de arranque/recuperación y aviso de datos de prueba deben localizarse ES/EN y revisarse con accesibilidad.
No se elevan iOS 27.0, Swift 6, formato de proyecto o dependencias para introducir esta selección.

## Integración local autorizada el 29 de octubre

- `AppEnvironmentResolver` acepta exclusivamente evidencia verificada Sandbox/Production de
  `AppTransaction.shared` en Release. Debug conserva Sandbox explícito. No se usa un valor guardado,
  recibo, enlace o transacción IAP histórica como respaldo. Los dos pares de orígenes están definidos en
  `AppEnvironment`; la fábrica ya no obtiene el destino del par único antiguo de `Info.plist`.
- `AppBootstrap` comparte una resolución asíncrona entre UI y App Intents y compone una sola instancia
  de `SharedShoppingViewModel` después de resolver. No abre persistencia, Keychain ni servicios comerciales
  antes. Cancelar una espera individual no cambia el contexto; cancelar la preparación permite reintentar
  y descarta cualquier resultado anterior tardío antes de componer.
- Un fallo conserva los datos y muestra recuperación con reintento explícito. Se mantiene en memoria la
  última URL recibida durante la resolución, sin guardar una invitación hasta conocer el destino. Un enlace
  válido del otro entorno muestra una explicación y no se persiste ni cambia de contexto.
- La app indica **Datos de prueba** en Sandbox, con una explicación accesible al pulsar. El aviso es compacto
  para no desplazar el contenido con Dynamic Type. Arranque, recuperación, invitaciones y avisos de compras
  se localizan ES/EN.
- `SharedAppStorage` y sus namespaces no cambian. Se conservan el servicio y borrador históricos de
  Production y el hash existente de Sandbox, incluidos grupo seleccionado, ambos buzones y operaciones.
- `StoreKitSubscriptionStore` exige entorno esperado y filtra purchase, currentEntitlements, unfinished,
  updates y finish. `SharedPremiumViewModel` comprueba de nuevo el entorno antes de persistir/enviar.
  Los sobres antiguos sin entorno se conservan hasta reencontrar evidencia compatible de StoreKit;
  no se reenvían por suposición y mantienen exactamente el JWS original. El servidor conserva su guarda.
- El entitlement incluye ambos dominios concretos, sin el macro anterior duplicado. La asociación AASA de
  Production devolvió el bundle correcto y `/invite/*`. Sandbox respondió inicialmente HTTP 503 porque
  faltaba `INVITATION_ORIGIN`; después de autorizar el propietario la revisión y distribución, se configura
  su origen público y se redespliega solo Sandbox. El AASA devuelve HTTP 200 con el mismo bundle y ruta
  a las 19:30 CET. La [evidencia](../validation/issue-54-distribution-environments.md#causa-y-corrección-del-503)
  conserva el cambio exacto y sus límites. La aceptación posterior confirma el recorrido de invitación
  Sandbox en el iPhone 11; no acredita el dominio Production ni el estado global de la caché de Apple.

La [validación](../validation/issue-54-distribution-environments.md#integración-del-arranque-comercial--29-de-octubre)
registra compilaciones Debug/Release sin avisos, 441 ejecuciones Fast y 21 Integration correctas,
previews ES/EN y los límites del ensayo. Los tests de App Intents invocan `perform()` con dependencia
inyectada; no acreditan el cargador del sistema, Siri física ni una compra Apple distribuida.

## Servidores, notificaciones y alternativas

Para esta alternativa no se necesita aceptar ambos entornos en un servidor ni cambiar el esquema por
el mero hecho de distribuir. Sandbox mantiene `--env sandbox` y `APP_STORE_ENVIRONMENT=Sandbox`;
Production mantiene su configuración de producción. Las actualizaciones necesarias del backend real
se preparan aparte, incluido el inventario de migraciones y la parada de escritores antiguos que exige
el [README del servidor](../../server/README.md).

Las URL de Notifications V2 deben ser explícitas por entorno. Apple
[puede enviar Sandbox a la URL Production si falta la URL Sandbox][notifications]. Cada destino verifica
firma y entorno y persiste exclusivamente en su base. Se comprobarán las URL vigentes antes de modificar
configuración; una notificación TEST no sustituye un evento de compra real ni acredita el otro entorno.

| Alternativa | Evaluación |
|---|---|
| Dos API y bases, selección completa antes del login | Recomendada por reutilizar la separación existente. Exige acreditar la selección y aceptar datos de prueba separados. |
| Una entrada pública con dos contextos y almacenes internos completos | Puede conservar aislamiento, pero añade enrutamiento de identidad, sesiones, compras, enlaces y datos sin una ventaja demostrada para esta salida. |
| Una base con derechos según el cliente o petición | Requiere nuevas reglas de capacidades compartidas y separación de elecciones, operaciones, sesiones e invitaciones. Mayor alcance que permitir dos entornos en compras. |
| Release siempre Sandbox o cambio de URL después de comprar | No resuelve el mismo binario comercial y de revisión, o cambia el contexto cuando ya existe una compra vinculada. |

## Validación necesaria antes de dar por válido el recorrido

Las comprobaciones automatizadas nuevas deben ejercer el arranque y sus efectos observables con
resultados de StoreKit inyectables; no duplicar el `switch` del selector en las expectativas ni escribir
tests de estructura. Usar Swift Testing conforme a la estrategia existente. Las regresiones de #39 se
reutilizan; no se repite toda su matriz física sin un motivo introducido por este cambio.

| Caso | Resultado exigido y evidencia |
|---|---|
| Primer arranque sin compras | Diagnóstico TestFlight 1.0 (1): observado `verified / sandbox` sin login propio ni compra durante la consulta. La cuenta tenía historial Sandbox; quedan la integración antes de sesión/catálogo y el caso sin historial. Revisión de Apple conserva su evidencia específica pendiente. |
| Error, no verificado, entorno desconocido, cancelación y arranque sin red | Recuperación sin llamadas de autenticación/compras a un origen supuesto; datos persistidos intactos. Validar también el caso con evidencia verificada local disponible. |
| Mismo Release distribuido: catálogo, compra y restauración | Flujo completo, sin herramientas DEBUG, con `appAccountToken` de la cuenta del destino y reconocimiento durable antes de `finish`. Un build local no acredita TestFlight. |
| TestFlight ↔ App Store | Cada destino recupera su propio borrador, sesión, invitaciones, grupo y operación pendiente; no los copia al otro. Los datos de prueba no aparecen como datos comerciales. |
| Historial mezclado, unfinished, updates y respuestas tardías | Ninguna transacción del otro entorno cambia el contexto ni se envía/finaliza allí; ningún resultado de una cuenta anterior se aplica a la nueva. |
| Misma identidad Apple en los dos servidores | Cada base mantiene su cuenta/token y autorización; restaurar no reasigna una compra al otro token. |
| Invitación de cada dominio y enlace durante el arranque | Aceptar solo el origen del contexto resuelto; AASA y firma del archivo comprobados. |
| Intento Sandbox en Production y Production en Sandbox | Rechazo sin concesión ni cambios de cuotas. Incluir al administrador de un grupo: no ampliar ni reducir grupos reales por un evento de prueba. |
| Notifications V2 | TEST y evento Sandbox correlacionados con su base. La configuración y comprobación Production se evidencian en su gate, sin simular un cobro real como prueba comercial. |

La sustitución real desde/hacia App Store solo puede acreditarse cuando exista una versión descargable.
Antes de esa disponibilidad se comprueba automáticamente el aislamiento al reconstruir contextos y se
ensaya TestFlight; no se presenta una instalación de desarrollo como una descarga App Store. El ensayo
real de sustitución queda identificado entre las comprobaciones de la primera salida controlada. La
respuesta de App Review aporta después su evidencia propia; no se exige como resultado anterior al envío.

La separación de datos está aprobada, la propuesta tiene revisión independiente y la señal candidata
cuenta con evidencia TestFlight acotada. El arranque, la recuperación, la espera de App Intents y las
guardas de compras están integrados y comprobados localmente. **1.0 (4)** tiene las aceptaciones
físicas enumeradas al principio. El siguiente build interno comprobará las tres regresiones de #49:
invitación después de cambiar grupo, arranque sin red y refrescos al volver a primer plano.
App Review, activación de producción y publicación siguen las condiciones de #54 y necesitan sus
evidencias propias.

[review]: https://developer.apple.com/help/app-review/before-submitting-for-review/configure-in-app-purchases/
[testflight]: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/
[app-transaction]: https://developer.apple.com/documentation/storekit/apptransaction/shared
[app-environment]: https://developer.apple.com/documentation/storekit/apptransaction/environment
[app-refresh]: https://developer.apple.com/documentation/storekit/apptransaction/refresh()
[notifications]: https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications/
