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

## Gracia de cobro y notificaciones

En App Store Connect, acordamos **16 días**, **Only Paid to Paid Renewals** y primero **Only Sandbox Environment** para Billing Grace Period. Tras validar, el titular podrá activar Production and Sandbox. La configuración afecta a la app y las fechas de sandbox son aceleradas; el servidor sigue el final acreditado por Apple. Un fallo de cobro sin gracia verificada no genera dieciséis días por cálculo local.

Configurar App Store Server Notifications **V2** con el origen HTTPS del entorno correspondiente y la ruta `/v1/app-store/notifications`. La ruta no usa bearer del usuario: verifica el `signedPayload`, la cadena de certificados de Apple, aplicación/entorno y evidencia anidada antes de reconciliar. Un `204` confirma procesamiento durable; un fallo temporal no se reconoce como éxito. Verificar el endpoint mediante Request a Test Notification y Get Test Notification Status, además del recorrido real de renovación; una respuesta local sintética no acredita notificaciones configuradas en Apple.

La integración distingue renovación cancelada de caducidad, gracia acreditada de transición de grupos y reembolso/revocación de fin ordinario. La política propia de siete días y treinta días se aplica en el servidor, con fechas persistidas compartidas entre dispositivos. No depende de configurar la gracia en Apple para conservar correctamente el grupo gratuito.

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
