# Política de privacidad de Smart List

> **Borrador de preparación — 9 de noviembre de 2026. No publicar todavía.**
> Este documento describe el tratamiento observado en el código e identifica las condiciones pendientes para la versión comercial. Las decisiones de grupos, conservación y recuperación de Premium se aprobaron el 9 de noviembre de 2026; su implementación y validación siguen pendientes. El correo `soporte@jesusfranco.dev` está previsto, pero todavía no funciona. Los bloques **PENDIENTE** son notas de preparación que deben resolverse antes de publicar; no deben ocultarse dejando afirmaciones sin verificar.

## 1. Quién es responsable

El responsable del tratamiento de los datos de Smart List es **Jesús Franco García**.

- Contacto previsto para soporte y privacidad: **soporte@jesusfranco.dev**.
- Web prevista: **https://jesusfranco.dev**.
- **PENDIENTE:** completar el domicilio de contacto y la identificación del titular que deban figurar en la información legal. El titular ha indicado que dispone de su domicilio particular; no ha autorizado su publicación. Debe decidirse y comprobarse qué dirección válida se publicará. No incorporar datos por suposición ni publicar documentación de identidad, ni presuponer una forma jurídica o alta profesional.
- **PENDIENTE:** activar y comprobar el correo antes de presentarlo como un canal disponible. Hasta entonces, esta política no está lista para su uso público.

Esta política se refiere a la app Smart List y a su servicio de listas compartidas. La futura web pública y el contacto por correo tienen tratamientos propios que se describen por separado en este documento cuando sean aplicables.

## 2. Qué datos utilizamos y de dónde proceden

### Datos que permanecen en el dispositivo

Smart List guarda un borrador con el texto que escribes o dictas, los productos, sus cantidades y las tiendas que estás preparando. El borrador permite revisar o completar una propuesta antes de añadirla a una lista compartida. También se conservan identificadores de solicitudes para evitar repetir acciones de Siri o Atajos.

El dispositivo guarda las credenciales de sesión, el grupo seleccionado, las invitaciones pendientes y las operaciones cuyo resultado necesita confirmación. Las credenciales y las operaciones pendientes se conservan en el almacén seguro del sistema. Una operación pendiente puede incluir productos o una transacción de suscripción firmada por Apple.

El borrador no se envía íntegramente al servidor para interpretar su contenido. Cuando confirmas una incorporación a la lista compartida, se envían los datos necesarios de los productos y de su destino. Siri y Atajos también pueden añadir un producto directamente a una tienda existente cuando has solicitado esa acción.

### Cuenta e inicio de sesión con Apple

Para utilizar las listas compartidas, Smart List usa **Iniciar sesión con Apple**. Apple proporciona la evidencia de autenticación y un identificador asociado a tu cuenta para esta app. Solicitamos tu nombre para mostrarlo dentro del servicio cuando Apple lo facilite. No solicitamos ni guardamos tu dirección de correo como un campo del perfil de Smart List.

El servidor conserva un identificador interno de cuenta, el identificador de Apple, el nombre disponible y la fecha de creación. También mantiene los datos necesarios para comprobar y revocar sesiones: credenciales de renovación de Apple cifradas, huellas de los tokens de sesión y fechas de validación, caducidad o revocación. No recibimos ni guardamos la contraseña de tu cuenta de Apple.

### Listas, grupos y actividad compartida

Conservamos los nombres de grupos y tiendas; los productos y cantidades que se añaden; su estado pendiente, comprado o cancelado; quién los creó y quién confirmó una compra, junto con las fechas correspondientes.

Para gestionar la colaboración también guardamos las pertenencias a grupos, el administrador y el creador histórico, las invitaciones y las propuestas de traspaso de administración. Estos registros incluyen sus estados y fechas. El secreto de una invitación se almacena como una huella; el enlace completo debe tratarse como un acceso privado que solo compartas con la persona que quieras invitar.

Los miembros del grupo pueden acceder al contenido compartido y a la información de miembros necesaria para colaborar. Otros miembros pueden aportar o modificar contenido y confirmar compras. Por ello, parte de la actividad que ves procede de esas personas, no exclusivamente de tus acciones.

Para reconocer un reintento sin duplicar cambios, el servidor conserva un identificador de operación, una huella de su contenido y su resultado. Ese resultado puede contener otra copia de datos de la lista.

### Suscripciones

Apple gestiona las compras de Premium. Smart List recibe los datos necesarios para verificar el acceso: identificadores de transacción y producto, fechas, estado de la suscripción y de su renovación y el entorno de compra. Un identificador de la cuenta de Smart List vincula la compra con la cuenta que la realizó.

El servidor consulta el estado en Apple y recibe sus notificaciones de cambios en la suscripción. Conserva los registros verificados y los datos mínimos para reconocer notificaciones repetidas. No recibimos el número de tu tarjeta, tus datos bancarios ni la contraseña que utilizas para comprar en Apple.

Para recuperar una suscripción tras una eliminación se comprueba también que la petición procede de una versión admitida de la app mediante App Attest de Apple. Se conservan temporalmente el desafío, la prueba necesaria para reintentar y el estado de la reasociación. Una respuesta externa incierta puede requerir conciliación antes de permitir otra asociación; no se recupera por ello la identidad ni las listas borradas.

### Datos técnicos y consultas de soporte

La app y el servidor generan diagnósticos técnicos para detectar errores y mantener el servicio, como el tipo de petición, su resultado y los códigos de error. Los diagnósticos HTTP propios utilizan plantillas sin credenciales, texto de listas ni identificadores de recursos. El detalle de un error del modelo puede contener texto y se marca como privado en el registro del sistema. Esto no permite afirmar que el proveedor de alojamiento no trate metadatos de conexión, como la dirección IP.

Cuando esté disponible el correo de soporte, recibiremos la dirección desde la que escribas, el contenido de tu consulta y los archivos que decidas adjuntar. No será necesario enviar contraseñas, códigos de acceso, información bancaria ni documentación de identidad para una consulta ordinaria.

**PENDIENTE:** inventariar los registros realmente generados por el alojamiento y los diagnósticos que puedan recibirse mediante las herramientas de distribución de Apple. Confirmar sus campos, accesos, finalidades y plazos antes de cerrar esta sección.

## 3. Dictado, Apple Intelligence y funciones del sistema

El dictado integrado utiliza las herramientas de reconocimiento de voz de Apple. Smart List pide permiso para utilizar el micrófono cuando eliges dictar; puedes continuar introduciendo productos a mano si no lo autorizas. La app procesa la entrada de audio mediante esas herramientas, no crea un archivo de grabación ni envía el audio a su servidor. Sí puede guardar el texto reconocido en tu borrador.

Para identificar productos, cantidades y tiendas, la app utiliza el modelo del sistema mediante Foundation Models cuando está disponible. Smart List no envía el texto a un proveedor externo de inteligencia artificial contratado por el desarrollador. El dispositivo puede necesitar descargar recursos de Apple para estas funciones. La disponibilidad depende del dispositivo, del idioma y de la configuración del sistema.

Siri, el dictado del teclado y otras funciones de iOS tienen sus propias opciones y condiciones de privacidad de Apple. Su tratamiento no debe confundirse con el dictado que Smart List inicia desde su propio botón. Puedes revisar sus permisos y configuración en los ajustes del dispositivo.

Smart List no toma fotografías, graba vídeo ni analiza imágenes. Tampoco solicita acceso a contactos ni a la ubicación para organizar las listas. La versión revisada no incorpora anuncios, identificadores publicitarios ni herramientas propias para seguir tu actividad entre apps o sitios web.

## 4. Para qué utilizamos los datos

| Finalidad | Base propuesta para la versión comercial |
|---|---|
| Crear y autenticar tu cuenta, gestionar pertenencias e invitaciones y prestar la lista compartida que solicitas. | Ejecución del servicio contratado, también cuando utilizas su modalidad gratuita. |
| Verificar compras, mantener el acceso Premium y recuperar un derecho vigente en una cuenta nueva después de eliminar la anterior. | Ejecución de la suscripción. La recuperación nueva requiere implementación y validación antes de publicarse. |
| Atender preguntas sobre el servicio o solicitudes previas a su uso. | Ejecución del servicio o atención de medidas previas solicitadas por ti, según el caso. |
| Prevenir accesos no autorizados, evitar operaciones duplicadas e investigar fallos. | Interés legítimo en proteger las cuentas y mantener la integridad del servicio, con datos limitados a esa finalidad. |
| Atender derechos de protección de datos y obligaciones legales concretas que resulten aplicables. | Cumplimiento de dichas obligaciones. |

Estas bases se proponen conforme al [artículo 6 del Reglamento General de Protección de Datos](https://eur-lex.europa.eu/eli/reg/2016/679/oj/spa). **PENDIENTE:** documentar la ponderación del interés legítimo para diagnósticos y prevención de abuso, y concretar cualquier obligación legal de conservación; no utilizarla como justificación genérica para guardar todos los datos.

El permiso de micrófono habilita una función opcional del dispositivo. No se utilizará como consentimiento general para finalidades ajenas al dictado. Las reglas de acceso y capacidad de Premium se aplican a partir del estado verificado de tu compra; la interpretación de texto propone productos que puedes revisar. No utilizamos estas funciones para elaborar perfiles publicitarios ni para tomar decisiones sobre tu empleo, crédito u otros ámbitos similares.

No necesitas crear una cuenta para preparar un borrador local. Para colaborar hacen falta la autenticación y los datos de lista que quieras compartir. El micrófono, la interpretación automática y una consulta de soporte son opcionales.

## 5. Quién puede tratar los datos

- **Las personas de tus grupos**, dentro de los permisos del servicio, acceden a las listas e información compartida para colaborar.
- **Apple** interviene en la autenticación, las compras, su verificación, la distribución de la app y las funciones del sistema que utilices. Sus servicios se rigen también por la información de privacidad que Apple te ofrece.
- **Railway** aloja la API y la base de datos de las listas compartidas. Su acceso técnico y el de sus proveedores deben quedar limitados por la configuración y los acuerdos aplicables.
- **OVHcloud**, una vez activado el buzón previsto, prestará el servicio de correo para las consultas enviadas a soporte. Ese buzón no es el almacenamiento de las listas de la app.
- **Cloudflare**, cuando se publique la web, prestará el alojamiento o la distribución de sus páginas. La visita a la web puede generar metadatos de conexión. La web prevista no es el backend de las listas; su configuración de registros y privacidad deberá revisarse antes de publicarla.
- Los datos podrán comunicarse a una autoridad cuando exista una obligación legal aplicable, atendiendo a su alcance.

**PENDIENTE:** identificar las entidades contractuales y comprobar los acuerdos de tratamiento de datos, los subencargados y los accesos de soporte de cada proveedor. No se da por acreditada esa revisión con la mera contratación del servicio.

En particular, debe comprobarse la formalización del [acuerdo de tratamiento de Railway](https://railway.com/legal/dpa), incluido su procedimiento de firma. No se ha inspeccionado el acuerdo de esta cuenta y este borrador no afirma que esté formalizado.

## 6. Dónde se tratan los datos

Los datos locales se mantienen en el dispositivo. Los datos compartidos se envían al servicio alojado en Railway; los servicios de Apple y el futuro correo y web pueden implicar otros lugares de tratamiento.

**PENDIENTE antes de publicar:** confirmar las regiones efectivas de la API, base de datos, registros y copias; los países de tratamiento o acceso de los proveedores; si existen transferencias fuera del Espacio Económico Europeo y qué garantías concretas las amparan, incluidos los medios para obtener información sobre ellas. Ubicar un servidor en Europa no permite afirmar por sí solo que no existen transferencias internacionales.

## 7. Cuánto tiempo se conservan

Cerrar sesión o salir de un grupo no elimina la cuenta. En la versión revisada, comprar o cancelar un producto lo retira de los pendientes, pero el servidor conserva el registro. Archivar una tienda o cerrar un grupo tampoco equivale a borrar su historial.

**Decisiones aprobadas, pendientes de implementación y comprobación:** la política siguiente distingue los datos necesarios para prestar el servicio de los que se retienen por una finalidad concreta. No se presenta como una purga ya ejecutada ni como una configuración comprobada del alojamiento.

| Datos | Criterio aprobado y comprobaciones pendientes |
|---|---|
| Cuenta y aportaciones propias, incluidas las compartidas. | Al aceptar la eliminación, bloquear el acceso inmediatamente y ejecutar la purga de datos operativos con un objetivo de **24 horas**. Informar del estado y confirmar la finalización; un fallo exige seguimiento, no conservar la cuenta indefinidamente. |
| Productos, historial, tiendas, grupos e invitaciones de cuentas vigentes. | Mientras sean necesarios para prestar el servicio. La eliminación de una cuenta retira sus aportaciones y conserva las ajenas. Todavía deben concretarse los criterios para historial comprado/cancelado y grupos cerrados sin utilidad actual; no se ha fijado un plazo general de 30 días para ese contenido. |
| Sesiones, concesiones de Apple y operaciones pendientes. | Limitar su conservación a autenticación, revocación y confirmación de operaciones; la fecha de caducidad no implica que la fila se borre automáticamente. |
| Transacciones, derechos Premium y notificaciones. | Conservar la información comercial mínima necesaria para gestionar y recuperar un derecho vigente, separada de la cuenta eliminada y sus listas. Al dejar de ser necesaria, borrarla salvo una obligación o reclamación concreta con alcance y plazo documentados. Los identificadores comerciales vinculables no se consideran anónimos. |
| Seguimiento de eliminación y revocación. | Comprobante hasta siete días desde el resultado; los trabajos activos no caducan sin resolver y requieren seguimiento si superan el objetivo operativo. Material cifrado de revocación: máximo siete días desde aceptación. La marca temporal de identidad se retira cinco minutos después del resultado para rechazar accesos iniciados antes del borrado. Huella de la sesión retirada para confirmar la limpieza en otros dispositivos: treinta días, sin acceso a la cuenta. |
| Registros técnicos. | Máximo de **30 días**, sin contenido de listas ni credenciales. Verificar también los registros que mantiene el proveedor. |
| Consultas de soporte. | **12 meses desde el cierre de la consulta**, salvo una reclamación u obligación específica que justifique otra conservación limitada. |
| Copias de seguridad. | Rotación con un máximo de **30 días**. Si se restaura una copia, volver a aplicar las supresiones antes de reanudar el servicio. Comprobar copias del proveedor y locales. |

Los plazos anteriores son decisiones de producto, no plazos generales impuestos por la normativa. No justifican guardar información que deje de ser necesaria antes. Las excepciones legales se documentarán por categoría, finalidad y duración; no se mantendrá el perfil completo para conservar una prueba comercial.

Para evitar repetir una acción ya ejecutada, pueden permanecer marcadores mínimos de operaciones de otros miembros, sin contenido ni referencias a la persona eliminada, mientras esas operaciones sean recuperables y exista la cuenta de ese otro miembro. Los recibos de la cuenta eliminada se borran. Esto no permite conservar copias completas de las listas con el pretexto de evitar duplicados.

**PENDIENTE:** programar las purgas, configurar las rotaciones y comprobarlas; concretar los criterios indicados para autenticación, historial y evidencia comercial. No se ha verificado una caducidad general de datos, registros o copias. Esta tabla sigue bloqueando la publicación hasta que corresponda al funcionamiento real.

## 8. Eliminación de cuenta — comportamiento aprobado, pendiente de implementación

La versión comercial deberá permitir iniciar la eliminación desde **Ajustes → Cuenta → Eliminar cuenta y mis datos**, con una explicación del alcance, comprobación de identidad y confirmación. Salir de un grupo conserva tu cuenta y permite entrar en otro conforme al cupo disponible; no inicia esta eliminación. Cerrar sesión tampoco borra la cuenta. El [diseño de eliminación](../architecture/account-deletion.md) recoge el comportamiento aprobado, que debe implementarse y probarse antes de convertir este apartado en una descripción de una función disponible.

La eliminación abarcará la cuenta, sus credenciales y sus datos y contenido propios, incluidos los compartidos. Conservará el contenido aportado por otras personas sin mantener vínculos personales innecesarios con la cuenta eliminada. No se utilizará la simple sustitución del nombre por una etiqueta como sustituto de borrar contenido propio. Si desaparece el último miembro, se purgará el grupo y su contenido.

Cuando el historial antiguo no permite demostrar quién escribió un nombre o una cantidad, la app lo advertirá antes de confirmar. Ese texto se retirará si la cuenta pudo aportarlo, conservando la estructura necesaria y el contenido ajeno de autoría comprobada. Esta limitación puede hacer que desaparezcan también textos antiguos de otros miembros.

Si quedan otros miembros y se elimina al administrador, el grupo quedará **pendiente de administración**. Los miembros podrán consultar, confirmar compras o cancelar productos pendientes conforme a sus permisos individuales; se pausarán incorporaciones, invitaciones y nuevas aportaciones o cambios de gestión. Cualquier miembro podrá asumir voluntariamente la administración sin necesitar Premium. Se aplicarán los límites de su plan conservando los datos existentes, aunque excedan esos límites. La eliminación de la cuenta anterior no dependerá de conseguir esa aceptación.

Antes de confirmar se deberá explicar qué ocurre con las listas, el borrador de este dispositivo, los restantes dispositivos y cualquier dato retenido por una obligación legal concreta, junto con los plazos aplicables. La aceptación bloqueará inmediatamente el acceso a la cuenta; la purga operativa tendrá el objetivo de 24 horas del apartado 7. Los datos de un dispositivo desconectado solo podrán limpiarse cuando la app compatible vuelva a ejecutarse y confirme la eliminación; cerrar sesión o un error de conexión no equivalen a esa confirmación. El recorrido seguirá los requisitos de [eliminación de cuenta de Apple](https://developer.apple.com/help/app-review/guideline-reference/5-1-1-account-deletion).

Eliminar la cuenta no cancelará por sí solo la suscripción facturada por Apple. El flujo incluirá acceso a su gestión y una advertencia clara, permitiendo continuar con la eliminación sin esperar a que termine el periodo pagado.

La decisión aprobada es permitir recuperar una suscripción que siga vigente en una nueva cuenta de Smart List, mediante **Restaurar compras** y la cuenta compradora del App Store. No se exigirán códigos de recuperación guardados por la persona. La operación recuperará únicamente el acceso pagado restante; no recuperará listas, grupos ni identidad borrados. Solo podrá existir una cuenta activa de Smart List vinculada a esa suscripción y la recuperación no trasladará derechos entre Sandbox y producción. Su implementación deberá verificar el derecho actual y la legitimidad de quien lo solicita; no basta con presentar un identificador antiguo. **PENDIENTE:** validar ese recorrido y la renovación posterior antes de publicarlo como disponible.

## 9. Tus derechos

Puedes solicitar acceso a tus datos, corregir los inexactos, pedir su supresión y, cuando corresponda, limitar u oponerte al tratamiento o solicitar su portabilidad. Si algún tratamiento se basa en tu consentimiento, podrás retirarlo para el futuro. Estos derechos no dependen de tener Premium.

El canal previsto es **soporte@jesusfranco.dev**, que deberá estar operativo antes de publicar esta política. La comprobación de identidad se limitará a lo necesario para proteger tus datos; no se pedirá documentación de identidad de forma automática para cualquier solicitud.

La regla general es responder en un mes; las prórrogas legalmente permitidas deberán comunicarse y justificarse. Puedes consultar el alcance de los derechos y reclamar ante la [Agencia Española de Protección de Datos](https://www.aepd.es/derechos-y-deberes/ejerce-tus-derechos).

**PENDIENTE:** preparar el procedimiento de atención, exportación y rectificación, verificar la identificación de una cuenta que no guarda email y concretar la entrega segura de respuestas. El correo de soporte no sustituirá la eliminación iniciada dentro de la app.

## 10. Versiones de prueba y cambios de esta política

TestFlight y las instalaciones de Sandbox usan cuentas, datos y compras de prueba separados de producción. La app los identifica como **Datos de prueba**. No traslada automáticamente esas listas ni sus derechos Premium al servicio comercial. Que los datos sean de prueba no elimina su carácter personal cuando contienen información de una persona real.

La versión final de esta política deberá indicar su fecha de entrada en vigor. Los cambios relevantes en finalidades, proveedores o condiciones del tratamiento deberán comunicarse de forma adecuada antes de aplicarse cuando corresponda.

**PENDIENTE:** definir el público y las condiciones de edad de la app, coherentes con los términos, la clasificación de la tienda y la base jurídica de cada tratamiento. No se presupone una edad mínima a partir de los dispositivos o cuentas usados durante las pruebas.

## Notas internas para cerrar el borrador

La publicación requiere resolver las notas anteriores y mantener coherencia con el [diseño de eliminación](../architecture/account-deletion.md) y los [Términos de uso](terms.es.md). La política debe corresponder al comportamiento que se vaya a distribuir, no solo a este documento.

La evidencia de código incluye: [identidad Apple](../../server/Sources/SmartShoppingListServer/Identity/AppleAuthenticationService.swift), [datos compartidos](../../server/Sources/SmartShoppingListServer/Persistence/CreateSharedShopping.swift), [suscripciones](../../server/Sources/SmartShoppingListServer/Persistence/AddAppStoreSubscriptions.swift), [borrador local](../../ios/SmartShoppingList/SmartShoppingList/Features/AddItems/DraftPersistence.swift), [dictado](../../ios/SmartShoppingList/SmartShoppingList/Features/AddItems/SpeechCaptureService.swift), [interpretación](../../ios/SmartShoppingList/SmartShoppingList/Features/AddItems/FoundationModelsDraftInterpreter.swift) y [almacenamiento de credenciales](../../ios/SmartShoppingList/SmartShoppingList/Services/SharedAPI/SharedKeychainStore.swift). Consultada el 9 de noviembre de 2026; no acredita por sí sola la configuración actual de los proveedores.
