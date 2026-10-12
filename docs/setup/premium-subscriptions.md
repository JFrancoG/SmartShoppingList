# Configurar y validar las suscripciones

La unidad [#39](https://github.com/JFrancoG/SmartShoppingList/issues/39) prepara StoreKit, verificación en servidor y vuelta al plan gratuito conforme al [contrato 0.5](../contracts/premium-subscriptions.md). Esta guía no acredita productos creados, credenciales disponibles, sandbox completado, notificaciones recibidas ni cobros activados. Esos pasos externos se registran con evidencia al realizarlos.

## Productos y entorno Apple

Crear una única oferta personal premium con dos productos de suscripción autorrenovable en **el mismo grupo de suscripciones de Apple**: mensual y anual, con el mismo nivel de servicio 5/10/100. Este identificador de Apple es distinto del UUID de un grupo de compra de Smart List. El servidor exige que las transacciones y el estado actual correspondan al grupo de suscripciones configurado. StoreKit debe devolver ambos productos, sus periodos esperados y pertenencia al mismo grupo antes de ofrecer la compra. Los IDs reales, precios, localizaciones, disponibilidad y aprobación de Apple se concretan antes de distribuir. No reutilizar los IDs `.example` de los ejemplos HTTP.

Mantener **Family Sharing desactivado** y elegir **No, don't allow multiseat purchases** en Purchase Options de ambos productos. Los derechos de esta unidad pertenecen a una cuenta del servicio y la capacidad compartida depende del administrador del grupo; no implementa reparto de asientos ni vinculación de compras compartidas por Apple. Las compras multiseat están habilitadas por defecto para nuevas suscripciones, por lo que hay que comprobar expresamente ese ajuste antes de distribuir una oferta personal. La [guía oficial de opciones de compra](https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-purchase-options-for-auto-renewable-subscriptions/) describe la configuración y su efecto sobre compras existentes.

El servidor entrega el catálogo permitido; iOS obtiene de StoreKit nombres, precios localizados y periodos. No hay un precio de producción fijado en código. Iniciar sesión en la cuenta del servicio antes de comprar para usar su `appAccountToken` estable; restaurar no cambia de titular ni reasigna una compra por presentar el JWS desde otra cuenta.

Crear una clave de **In-App Purchase** en App Store Connect y configurar sus identificadores. Es distinta de la clave de Sign in with Apple; ninguna clave `.p8` pertenece al cliente. Conservar los secretos en el gestor del alojamiento, sin logs de body ni valores. La familia de configuración es completa o ausente: una configuración parcial o una clave inválida impide arrancar en vez de aceptar compras sin verificar.

| Variable del servidor | Valor esperado |
|---|---|
| `APP_STORE_BUNDLE_ID` | Bundle ID real, coherente con la app y Apple; `com.plusprojects.SmartShoppingList` en este proyecto. |
| `APP_STORE_APP_ID` | Apple ID numérico de la app en App Store Connect, entero positivo. |
| `APP_STORE_ISSUER_ID` | UUID del emisor de la clave In-App Purchase. |
| `APP_STORE_KEY_ID` | Identificador de esa clave. |
| `APP_STORE_PRIVATE_KEY_PEM` | PEM multilínea de la clave `.p8`, secreto con saltos de línea reales. |
| `APP_STORE_PREMIUM_MONTHLY_PRODUCT_ID` | ID real del producto mensual autorizado. |
| `APP_STORE_PREMIUM_ANNUAL_PRODUCT_ID` | ID real del producto anual autorizado, distinto del mensual. |
| `APP_STORE_SUBSCRIPTION_GROUP_ID` | ID real del grupo de suscripciones de Apple al que pertenecen ambos productos; no es un UUID de Smart List. |
| `APP_STORE_ENVIRONMENT` | Exactamente `Sandbox` o `Production`; no hay entorno implícito ni aceptación cruzada. |

Con todas ausentes, una cuenta sin concesión de producción conserva el plan gratuito y la consulta expresa compras no configuradas. Un derecho de producción ya verificado conserva solo el final antes acreditado, sin ampliarlo por ausencia de configuración/conexión. Las variables preparan la conexión y catálogo, **no conceden premium**. El acceso requiere transacciones verificadas y vinculadas más su estado actual en Apple. No colocar una clave privada de prueba o un token premium en la imagen Docker para simularlo.

Los registros de concesión y las cadenas originales mantienen el entorno. Sandbox y Production no comparten derechos: cambiar o retirar variables no convierte el ensayo en una compra de producción. Sin configuración, la autoridad consulta únicamente el entorno Production. Antes de desplegar migraciones con datos reales, conservar la copia autorizada de PostgreSQL y verificar las guardas de reversión; no borrar elecciones, plazos o vínculos para volver al esquema anterior.

## Backend Sandbox separado en Railway

Usar un entorno persistente vacío llamado `sandbox`, con su propia API `SmartShoppingListSandbox` y PostgreSQL con volumen. El producto **Sandbox** del menú de servicios de Railway no sustituye a este entorno. No duplicar la base, variables ni credenciales de producción. El usuario puede configurar ambos servicios dentro del mismo proyecto; comprobar el selector de entorno antes de cada cambio. El presupuesto y las alertas se acuerdan antes de activar recursos de pago, conforme a la [guía de alojamiento](shared-shopping.md#https-y-alojamiento).

Conectar la API al repositorio y a una revisión que incluya el cierre de las rutas de infraestructura en entornos alojados. Configurar la raíz `server/` y su Dockerfile, una sola réplica, `PORT=8080`, el puerto del dominio 8080 y el healthcheck `/hello`. El Dockerfile arranca con `--env production` por defecto; para este servicio definir el **Custom Start Command** completo:

```sh
./SmartShoppingListServer serve --env sandbox --hostname 0.0.0.0 --port 8080
```

Railway [sustituye el ENTRYPOINT al definir ese comando](https://docs.railway.com/deployments/start-command), por lo que debe incluir el ejecutable. `sandbox` es el nombre del entorno de Vapor; `APP_STORE_ENVIRONMENT=Sandbox` selecciona el entorno de Apple. Ambos son necesarios: el servidor rechaza credenciales Sandbox cuando ejecuta en producción. No modificar esa guarda para conseguir que arranque. Las rutas de ejemplo `/todos` se registran únicamente en desarrollo y testing; GET, POST y DELETE deben devolver `404` en `sandbox` y producción.

La imagen debe conservar los bundles de recursos generados por SwiftPM junto al ejecutable. Swift 6.4 genera `SmartShoppingListServer_SmartShoppingListServer.bundle` en Linux; el certificado público `AppleRootCA-G3.cer` debe permanecer dentro de ese bundle. El Dockerfile copia los directorios `.bundle` y `.resources` y rechaza la construcción si falta el certificado obligatorio. No copiarlo suelto ni sustituir la raíz de confianza para resolver un error de arranque.

El job `Server runtime image (Linux amd64)` comprueba la imagen Release final con las nueve variables de compras completas, Sign in with Apple y el cifrado de tokens configurados mediante una clave P-256 y una clave AES de 32 bytes temporales, además de PostgreSQL aislado. La red de la prueba es interna: no usa secretos reales ni contacta con Apple. Comprueba carga de recursos, carga de las dos familias de identidad, migraciones, respuesta de `/hello`, autenticación requerida y cierre de `/todos`. Se puede ejecutar desde la raíz del repositorio:

```sh
docker build --tag smartshoppinglistserver:smoke server
bash scripts/check_server_image.sh smartshoppinglistserver:smoke
```

Esta comprobación local no acredita las credenciales selladas del alojamiento, su conexión TLS a PostgreSQL, login de Apple, compras ni notificaciones Sandbox.

Completar tres familias de variables antes del primer despliegue:

- **Base de datos:** `DATABASE_HOST`, `DATABASE_PORT`, `DATABASE_USERNAME`, `DATABASE_PASSWORD` y `DATABASE_NAME` referencian exclusivamente el PostgreSQL de `sandbox`. `DATABASE_CA_CERTIFICATE_PEM` contiene su CA pública, con verificación de cadena y del dominio privado conforme a la [guía de PostgreSQL](shared-shopping.md#https-y-alojamiento). No copiar claves privadas de la base.
- **Identidad:** `APPLE_CLIENT_ID`, `APPLE_TEAM_ID`, `APPLE_KEY_ID`, `APPLE_PRIVATE_KEY_PEM`, `APPLE_REFRESH_ACTIVE_KEY_VERSION` y `APPLE_REFRESH_KEYS_JSON`, siguiendo la [configuración de Sign in with Apple](shared-shopping.md). Usar una clave de identidad y claves de cifrado independientes de producción. El `.p8` de In-App Purchase no autentica usuarios. Configurar `INVITATION_ORIGIN` con el nuevo origen HTTPS y `LOG_LEVEL=info`.
- **Compras:** las nueve variables `APP_STORE_*` de la tabla anterior, con `APP_STORE_ENVIRONMENT=Sandbox` y los productos reales. Sellar los secretos multilínea con saltos de línea reales; el servidor no admite `APP_STORE_PRIVATE_KEY_PATH`.

Conservar la base Sandbox después de las compras: los UUID de cuenta, `appAccountToken` y vínculos verificados deben sobrevivir a renovaciones y restauraciones. El arranque aplica las migraciones; un servicio vacío o PostgreSQL Online todavía no acredita que la API esté desplegada.

Tras arrancar, comprobar `/hello`, el cierre de `/todos`, autenticación y catálogo. Configurar expresamente la **Sandbox Server URL** de App Store Connect con `https://<dominio-sandbox>/v1/app-store/notifications` y versión V2 antes de solicitar una notificación TEST. Apple puede [enviar notificaciones Sandbox a la URL de producción si falta la específica](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/enter-server-urls-for-app-store-server-notifications/).

Preparar después una instalación iOS aislada que use el nuevo origen HTTPS en `SHARED_API_BASE_URL` y `SHARED_INVITATION_ORIGIN`. Cambiar solo la URL conserva el Keychain y operaciones pendientes de la instalación habitual; no reutilizar ni borrar esos datos para un ensayo. La configuración concreta de aislamiento y su validación se registran antes de la primera compra. Las renovaciones Apple son aceleradas en Sandbox; los plazos propios de siete y treinta días siguen siendo días reales y se verifican por separado.

## Gracia de cobro y notificaciones

En App Store Connect, acordamos **16 días**, **Only Paid to Paid Renewals** y primero **Only Sandbox Environment** para Billing Grace Period. Tras validar, el titular podrá activar Production and Sandbox. La configuración afecta a la app y las fechas de sandbox son aceleradas; el servidor sigue el final acreditado por Apple. Un fallo de cobro sin gracia verificada no genera dieciséis días por cálculo local.

Configurar App Store Server Notifications **V2** con el origen HTTPS del entorno correspondiente y la ruta `/v1/app-store/notifications`. La ruta no usa bearer del usuario: verifica el `signedPayload`, la cadena de certificados de Apple, aplicación/entorno y evidencia anidada antes de reconciliar. Un `204` confirma procesamiento durable; un fallo temporal no se reconoce como éxito. Verificar el endpoint mediante Request a Test Notification y Get Test Notification Status, además del recorrido real de renovación; una respuesta local sintética no acredita notificaciones configuradas en Apple.

La integración distingue renovación cancelada de caducidad, gracia acreditada de transición de grupos y reembolso/revocación de fin ordinario. La política propia de siete días y treinta días se aplica en el servidor, con fechas persistidas compartidas entre dispositivos. No depende de configurar la gracia en Apple para conservar correctamente el grupo gratuito.

## Instalación iOS para el catálogo real de Sandbox

El target conserva `com.plusprojects.SmartShoppingList` y el equipo de firma de Apple. **Debug** usa
`https://smartshoppinglistsandbox-sandbox.up.railway.app` para API e invitaciones y se muestra como **Smart List Sandbox**.
**Release** conserva el origen de producción y el nombre **Smart List**. `SHARED_ASSOCIATED_DOMAIN` selecciona el dominio
correspondiente en los entitlements. Los valores pertenecen al artefacto compilado: abrir desde el icono o mediante Siri
no depende de variables temporales de ejecución de Xcode.

La fábrica separa sesión, ambas invitaciones, operación pendiente, verificación premium y borrador según los orígenes
normalizados de API e invitaciones. Producción conserva su servicio Keychain y archivo anterior sin migrarlos ni borrarlos.
Cada origen distinto utiliza un namespace estable; una configuración ausente usa uno separado y no conecta como respaldo a
producción. Mantener el mismo bundle ID sustituye el binario instalado; no permite conservar dos apps simultáneamente.
No eliminar la aplicación para cambiar de entorno: reinstalar una compilación Release recupera sus datos locales anteriores.
StoreKit mantiene su propia cuenta e historial de Apple; el namespace local no reinicia esos datos.

Para comprobar primero identidad y catálogo:

1. Conectar y desbloquear el iPhone elegido, completar confianza y activar modo desarrollador si iOS lo solicita.
2. Ejecutar el scheme `SmartShoppingList` con Debug, sin archivo `.storekit` seleccionado: necesitamos el catálogo real de Apple.
3. En **Ajustes** de la app, completar el botón nativo **Iniciar sesión con Apple** usando la cuenta Apple del dispositivo.
   El tester de compras Sandbox es una cuenta distinta, destinada a las compras de prueba.
4. Abrir **Premium** desde Ajustes. Deben aparecer las alternativas mensual y anual con nombres y precios de StoreKit.
   No comprar ni restaurar en esta primera comprobación. Si falta el catálogo, conservar el error y revisar configuración
   antes de iniciar una transacción.
5. Contrastar las respuestas de inicio de sesión y `/v1/account/subscription` en Railway **sandbox**, sin registrar tokens,
   códigos de autorización, cuerpos de autenticación ni claves privadas. Registrar por separado el resultado del catálogo.

La [guía de pruebas de Apple](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox)
describe el inicio de sesión del tester para compras. No cambiar la cuenta iCloud del dispositivo por ese tester.
Estas comprobaciones no acreditan aún compra, restauración o ciclo de renovación.

## Validación y activación separadas

1. Verificar configuración, criptografía, vinculación por cuenta, persistencia y recuperación con pruebas locales aisladas. Registrar los límites de las fuentes sintéticas y de StoreKit local.
2. Configurar productos y entorno **Sandbox**; comprobar compra mensual/anual, cancelación de compra, restauración tras reinstalar, cuenta distinta, renovación desactivada, gracia, caducidad y notificaciones duplicadas/tardías. Conservar los IDs de evidencia sin secretos.
3. Comprobar los grupos y cupos con usuarios de planes distintos; verificar que transición y elección son coherentes en dos dispositivos y que las operaciones pendientes recuperan su destino original.
4. Completar precio, acuerdos, datos bancarios/fiscales, privacidad, términos y revisión/disponibilidad de productos. Tramitar Small Business por separado si corresponde; presentar la solicitud no prueba aceptación ni fecha efectiva de comisión.
5. Autorizar y realizar despliegue/distribución y activación comercial después de la evidencia anterior. Un build, una PR o CI no efectúan esos pasos.

Los regalos de tres o seis meses siguen pendientes de decisión de destinatarios, elegibilidad y condiciones. No configurar ni distribuir códigos o conceder premium manual desde esta guía. La [política comercial](../architecture/group-access-and-limits.md) y el contrato conservan las decisiones aprobadas; la issue conserva los resultados y pendientes operativos.

## Fuentes oficiales

- [Configurar suscripciones autorrenovables](https://developer.apple.com/help/app-store-connect/manage-subscriptions/offer-auto-renewable-subscriptions/).
- [Configurar compra personal y multiseat](https://developer.apple.com/help/app-store-connect/manage-subscriptions/manage-purchase-options-for-auto-renewable-subscriptions/).
- [Generar claves In-App Purchase](https://developer.apple.com/help/app-store-connect/configure-in-app-purchase-settings/generate-keys-for-in-app-purchases/).
- [Configurar Billing Grace Period](https://developer.apple.com/help/app-store-connect/manage-subscriptions/enable-billing-grace-period-for-auto-renewable-subscriptions/).
- [Activar notificaciones de App Store](https://developer.apple.com/documentation/appstoreservernotifications/enabling-app-store-server-notifications).
- [Consultar el estado de suscripciones](https://developer.apple.com/documentation/appstoreserverapi/get-all-subscription-statuses).
- [App Store Small Business Program](https://developer.apple.com/app-store/small-business-program/).
