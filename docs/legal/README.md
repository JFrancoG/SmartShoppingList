# Preparación de Privacidad, Términos y eliminación de cuenta

**9 de noviembre de 2026 · Decisiones de producto aprobadas; textos pendientes de publicación · [#54](https://github.com/JFrancoG/SmartShoppingList/issues/54)**

Documentos preparados para revisión, todavía sin publicar. Base de código inspeccionada: `4596c2f` (`main`, PR #55); rama de trabajo: `codex/issue-54-privacy-account-deletion`. El titular ha aprobado las decisiones de grupos, conservación y recuperación de Premium descritas aquí y ha autorizado su implementación. Esa aprobación no acredita que el contrato 0.5, el código distribuido o la infraestructura ya las cumplan, ni publica estas condiciones.

La implementación local del contrato **0.6** incluye el proceso persistente de eliminación, reautenticación específica, purga de contenido propio e histórico incierto, grupos pendientes de administración, limpieza en la app y recuperación protegida de Premium. El [diseño](../architecture/account-deletion.md) y la [validación local](../validation/issue-54-account-deletion-local.md) delimitan el resultado. El recorrido con Apple real, los plazos de infraestructura y la distribución todavía necesitan validación antes de publicar estos textos.

## Documentos

- [Política de privacidad, borrador español](privacy.es.md).
- [Condiciones de uso, borrador español](terms.es.md).
- [Diseño de eliminación de cuenta](../architecture/account-deletion.md), con estados, datos afectados, recuperación y casos de aceptación.

Los bloques editoriales y los datos pendientes impiden publicar los textos directamente. La versión inglesa se preparará sobre la redacción aprobada, antes de distribuir la app con enlaces legales en ambos idiomas. No copiar estos archivos a la raíz publicable de la web hasta resolver los pendientes.

## Decisiones aprobadas

El titular confirma que el responsable será **Jesús Franco García**. El contacto público elegido es `soporte@jesusfranco.dev`; su activación y las pruebas de correo siguen pendientes de OVH. El dominio elegido es `jesusfranco.dev`.

El 9/11 el titular aclara que **salir de un grupo debe conservar la cuenta y permitir incorporarse a otro con el cupo disponible**. Se mantiene el comportamiento existente. El borrado completo será una acción distinta, **Ajustes → Cuenta → Eliminar cuenta y mis datos**. No se llama «abandonar la app» ni se asocia al botón de salir de un grupo.

| Acción | Efecto |
|---|---|
| Salir de un grupo | Quita esa pertenencia y conserva la cuenta; si administra y quedan miembros, requiere el traspaso ordinario. Conserva el contenido según el estado del grupo, salvo la purga advertida al salir el último miembro de un grupo pendiente de administración. La plaza liberada puede usarse conforme al plan. |
| Cerrar sesión | Revoca la sesión actual; no borra cuenta, grupos ni el borrador. |
| Eliminar cuenta y mis datos — implementación local | Borra la cuenta del entorno actual y sus aportaciones, revoca acceso y trata todos sus grupos y dispositivos. No cancela la suscripción facturada por Apple. |

Se recomienda mantener la **EULA estándar de Apple** para la licencia de la app y unas condiciones propias para el servicio y Premium. La [documentación de Apple](https://developer.apple.com/help/app-store-connect/manage-app-information/provide-a-custom-license-agreement/) explica que la EULA estándar se aplica si no se configura una personalizada; este documento no afirma haber comprobado o cambiado ese ajuste en App Store Connect.

El 9/11 el titular aprueba estas reglas para su implementación:

- **Grupos:** cuando quien elimina su cuenta administra un grupo con otros miembros, se conservan las aportaciones ajenas y el grupo queda **pendiente de administración**. Los miembros mantienen consulta, confirmación de compras y cancelación de pendientes conforme a sus permisos individuales; se pausan las incorporaciones, invitaciones y nuevas aportaciones o cambios de gestión. Cualquier miembro puede asumir voluntariamente la administración sin necesitar Premium; se aplica su plan y se conserva el contenido que exceda sus límites. La eliminación no espera esa aceptación. Si no quedan miembros, se purga el grupo. La salida de grupos administrados conserva sus reglas. Si el último miembro sale de un grupo que ya está pendiente de administración, la app advierte que elimina ese grupo y su historial.
- **Legado:** se retira el texto histórico cuya autoría no pueda demostrarse cuando la cuenta pudo aportarlo, con advertencia previa de que también puede afectar a textos antiguos de otros miembros. Se conserva el contenido ajeno de autoría demostrada y la estructura necesaria del grupo. No se inventan atribuciones.
- **Datos:** se bloquea el acceso al aceptar la eliminación, con objetivo de purga operativa en **24 horas**. Se aprueban un máximo de **30 días** para copias de seguridad y registros técnicos, y **12 meses** desde el cierre para consultas de soporte. Las copias restauradas deben volver a aplicar las supresiones antes de servir tráfico. Los registros técnicos no contendrán textos de listas ni credenciales. Cualquier excepción debe tener finalidad, alcance y plazo justificados.
- **Premium:** después de completar la eliminación, una nueva cuenta podrá recuperar un derecho todavía vigente mediante **Restaurar compras**, usando la cuenta compradora del App Store. No se exigirán códigos de recuperación guardados por la persona. Una suscripción solo se podrá vincular a una cuenta activa de Smart List; no recuperará los datos borrados ni cruzará Sandbox y producción. Se conservará únicamente la información comercial necesaria para gestionar el derecho o una obligación concreta, separada del perfil y las listas.

Los plazos son objetivos y límites de producto aprobados, **no una configuración ya verificada ni plazos impuestos de forma general por la ley**. La recuperación segura de Premium debe probarse antes de prometerla públicamente: Apple permite [actualizar el vínculo de cuenta de una suscripción](https://developer.apple.com/documentation/appstoreserverapi/set-app-account-token), pero esa API por sí sola no autentica a quien solicita recuperarla.

## Información del titular pendiente

El titular dispone de domicilio particular, pero todavía no ha decidido qué dirección publicar. No se ha incorporado domicilio, NIF ni teléfono a estos archivos ni se ha inferido una situación de alta fiscal.

La [LSSI, artículo 10](https://www.boe.es/buscar/act.php?id=BOE-A-2002-13758#a10), contempla residencia/domicilio o establecimiento, contacto e identificación fiscal para los prestadores incluidos en su ámbito. Usar una dirección particular supone hacerla pública. Una eventual domiciliación debe ser válida para esa actividad; un simple buzón no se da por equivalente a un establecimiento. [Apple admite dirección o apartado postal para comerciantes individuales](https://developer.apple.com/help/app-store-connect/manage-compliance-information/manage-european-union-digital-services-act-trader-requirements/), pero eso no resuelve por sí solo la identificación exigible en la web española. Confirmar la información legal aplicable y la declaración de comerciante antes de publicar; la existencia de suscripciones es relevante y la escasez de ingresos no determina por sí sola el resultado.

## Hechos contrastados con la base `4596c2f`, anterior a esta implementación

| Tratamiento | Evidencia y límite |
|---|---|
| Cuenta Apple y nombre opcional | [Acceso iOS](../../ios/SmartShoppingList/SmartShoppingList/Features/SharedShopping/SharedShoppingViewModel.swift), [autenticación](../../server/Sources/SmartShoppingListServer/Identity/AppleAuthenticationService.swift). Se solicita nombre, no email como dato de perfil. El servidor guarda sujeto Apple y UUID; no la contraseña Apple. |
| Credenciales y sesiones | [Esquema de autenticación](../../server/Sources/SmartShoppingListServer/Identity/CreateAppleAuthentication.swift). Refresh tokens cifrados; hash de bearer; sesiones de 30 días. La caducidad lógica no acredita purga física. |
| Listas y colaboración | [Esquema inicial](../../server/Sources/SmartShoppingListServer/Persistence/CreateSharedShopping.swift), [pertenencias](../../server/Sources/SmartShoppingListServer/Persistence/AddGroupMemberships.swift). Se conserva contenido, actividad y autoría. Una tienda no tiene autor registrado y una edición no identifica a su editor; esto impide asumir atribución histórica completa. |
| Historial y reintentos | Productos comprados/cancelados, grupos cerrados y recibos JSON se conservan. Los recibos pueden duplicar datos de otra persona; borrar solo la fila de producto no basta. |
| Voz e interpretación | [Speech](../../ios/SmartShoppingList/SmartShoppingList/Features/AddItems/SpeechCaptureService.swift), [Foundation Models](../../ios/SmartShoppingList/SmartShoppingList/Features/AddItems/FoundationModelsDraftInterpreter.swift). No se envía audio al backend propio ni se llama a una API externa de IA. No extrapolar esto a todas las funciones de Siri o del teclado. |
| Datos del dispositivo | [Borrador](../../ios/SmartShoppingList/SmartShoppingList/Features/AddItems/DraftPersistence.swift), [Keychain](../../ios/SmartShoppingList/SmartShoppingList/Services/SharedAPI/SharedKeychainStore.swift), [aislamiento](../../ios/SmartShoppingList/SmartShoppingList/App/SharedAppStorage.swift). El borrador pertenece al entorno local, no exclusivamente a una cuenta. |
| Premium | [Esquema](../../server/Sources/SmartShoppingListServer/Persistence/AddAppStoreSubscriptions.swift), [servicio](../../server/Sources/SmartShoppingListServer/Subscriptions/SubscriptionService.swift). UUID de cuenta como `appAccountToken`; vínculo exclusivo de cadena y entorno. No se guardan tarjetas ni cuentas bancarias del comprador. |
| Diagnósticos | [HTTP iOS](../../ios/SmartShoppingList/SmartShoppingList/Services/SharedAPI/SharedHTTPAPI.swift), [servidor](../../server/Sources/SmartShoppingListServer/configure.swift). Revisar adicionalmente logs de proveedor, soporte y datos recibidos por TestFlight; el código no acredita ausencia de IP en infraestructura. |
| Eliminación | No hay endpoint de supresión ni revocación Apple implementados. Cerrar sesión revoca un bearer; cerrar grupo conserva datos. La función nueva requiere migración y comprobaciones propias. |

La revisión no encuentra SDK propios de publicidad o seguimiento entre apps, geolocalización, contactos, fotos, vídeo, OCR ni push de usuario. Las notificaciones V2 son eventos de compras recibidos por el servidor. No declarar «ningún dato recogido» en App Store Connect: cuenta, contenido compartido y compras sí se procesan fuera del dispositivo.

## Información mínima en la app

Propuesta de primera capa junto al acceso Apple, con enlaces visibles y sin casilla de consentimiento global:

> Jesús Franco García usa tu identidad de Apple y el nombre que facilites para crear tu cuenta y compartir listas con las personas de tus grupos. El servicio verifica con Apple las compras de Premium. Consulta Privacidad para conocer los datos, su conservación y tus derechos, y Términos para las condiciones del servicio.

El consentimiento del micrófono y la lectura de Privacidad no se presentan como una autorización general para otros usos. Los enlaces se podrán consultar sin iniciar sesión.

| Lugar | Enlaces y acciones previstos |
|---|---|
| Ajustes → Información y soporte | Privacidad, Términos, soporte y versión. |
| Acceso con Apple | Primera capa, Privacidad y Términos antes del acceso. |
| Premium, antes de comprar | Producto, duración, precio StoreKit, renovación, Restaurar compras, Gestionar suscripción y enlaces legales. |
| Ajustes → Cuenta | Cerrar sesión y, separada, Eliminar cuenta y mis datos. No situar el borrado en «Miembros y administración». |
| Web de Smart List y metadatos App Store | Mismos textos/versiones públicos; EULA estándar enlazada según las instrucciones de Apple. |

Rutas propuestas, **todavía no publicadas ni configuradas en la app**: `https://jesusfranco.dev/smart-list/privacidad/` y `https://jesusfranco.dev/smart-list/terminos/`. Un aviso legal común de `jesusfranco.dev` podrá reunir la identificación del titular para sus futuras apps.

## Condiciones para convertir el borrador en texto publicable

1. **Responsable y público:** completar dirección e identificación legal por un canal adecuado, decidir territorios y condiciones de edad; revisar comerciante DSA. No publicar datos personales del titular por inferencia.
2. **Correo:** entrega de Zimbra, alta de `soporte@jesusfranco.dev` y prueba de envío/recepción. La respuesta de OVH del 9/11 confirma retraso de entrega sin estimación; no se da por resuelto.
3. **Proveedores:** verificar entidades, DPA, subencargados, regiones de datos/copias/logs y transferencias. El [DPA público de Railway](https://railway.com/legal/dpa) describe un procedimiento de formalización; su publicación no prueba que el acuerdo de esta cuenta esté formalizado. Revisar también OVH y la futura web Cloudflare. No se firma ningún contrato en esta preparación.
4. **Conservación efectiva:** aplicar y medir los plazos aprobados de 24 horas, 30 días y 12 meses; comprobar todas las copias, incluidas las del proveedor y las locales. Las sesiones de 30 días y las invitaciones de 24 horas no prueban borrado. Concretar los criterios todavía pendientes para productos terminados, grupos cerrados, recibos, autenticación y compras; no se ha aprobado una purga general del historial a los 30 días. Los marcadores mínimos de operaciones de otros miembros deben impedir reejecuciones sin conservar contenido ni referencias a la persona eliminada.
5. **Eliminación:** validar la implementación local mediante distribución, revocación real y recuperación de suscripción tras recrear cuenta. Ensayar las migraciones y recuperación antes de ofrecer el flujo. No confundir anonimización con conservar UUID, hashes o transacciones vinculables.
6. **Derechos:** preparar acceso/exportación/rectificación y verificación de identidad para cuentas sin email de perfil, con entrega segura. El correo no será requisito para iniciar la eliminación dentro de la app.
7. **Publicación:** aprobar ES, preparar EN equivalente, publicar URLs accesibles, integrar enlaces y textos en app, revisar declaraciones de privacidad de App Store Connect y probar el flujo distribuido. Fijar fecha de vigencia real y conservar versiones.

## Fuentes y validación de esta preparación

Las fuentes oficiales consultadas el 9/11/2026 incluyen [RGPD](https://eur-lex.europa.eu/eli/reg/2016/679/oj/spa), [AEPD: información](https://www.aepd.es/derechos-y-deberes/conoce-tus-derechos/derecho-de-informacion), [AEPD: derechos](https://www.aepd.es/derechos-y-deberes/ejerce-tus-derechos), [Apple: eliminación](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion), [TN3194: revocación Apple](https://developer.apple.com/documentation/technotes/tn3194-handling-account-deletions-and-revoking-tokens-for-sign-in-with-apple) y [Apple: suscripciones](https://developer.apple.com/app-store/subscriptions/). Los textos contienen sus referencias específicas.

La revisión del código acredita qué hay implementado; las propuestas no son resultados de pruebas. Se han realizado revisión independiente de coherencia legal/Apple y revisión de arquitectura con el perfil de mantenimiento. Se corrigieron el resultado terminal cuando Apple no confirma la revocación y los avisos que podían atribuir acceso de compra a miembros restringidos; se acotó la limpieza en otros dispositivos para no interpretar un `401` como una orden de borrar. Los enlaces locales y el formato se comprueban sobre los documentos nuevos y modificados.

La evidencia local de implementación y Swift Testing está enlazada arriba. Continúan pendientes CI tras entregar los cambios, el ensayo de infraestructura y una ronda física acotada; la aceptación anterior de TestFlight no se presenta como prueba de borrado.
