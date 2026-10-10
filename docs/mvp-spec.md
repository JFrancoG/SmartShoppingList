# Especificación del MVP

Estado: **alcance funcional aprobado** por el usuario el 18 de septiembre de 2026.

Revisión del 19 de septiembre: selección provisional de productos y confirmación al finalizar la compra; iOS 27 como versión mínima y preferencia por Vapor 5, con Vapor 4 como alternativa autorizada si la versión 5 no resulta viable.

Revisión de diseño del 23 de septiembre: sistema visual semántico y accesibilidad en cuatro apariencias, documentados para su implementación y validación en el acabado del MVP. No amplía funcionalidades ni acredita validación de la interfaz.

Entrega: **27 de septiembre de 2026, antes de las 23:30 CET**, según el correo final de la organización facilitado por el usuario el día 27. Esta comunicación actualiza la referencia anterior de las bases a las 23:00 CET. Se entrega mediante el formulario enlazado en ese correo, con el repositorio GitHub público y el email del registro; solo se evalúan commits anteriores al cierre. Se conserva margen sin interpretar la zona horaria como tiempo adicional en Madrid.

Esta especificación recoge el acuerdo de la conversación. Las decisiones técnicas que aún requieren una prueba se distinguen del comportamiento comprometido.

Precisión de entrega del 27 de septiembre: el nombre visible de la app es **Smart List**; el repositorio y el proyecto Xcode conservan SmartShoppingList, y el bundle ID sigue siendo `com.plusprojects.SmartShoppingList`. Los destinos de la app son iPhone e iPad. Las decisiones y ensayos fechados conservan sus nombres y entornos originales; las instrucciones actuales están en el [README](../README.md), y la evidencia de cierre se enlaza desde el [plan](implementation-plan.md#fases-4-y-5-entrega-reproducible-y-margen).

## 1. Objetivo

Preparar y consultar una lista de compra compartida, organizada por tiendas, usando voz y revisión humana antes del guardado.

Recorrido principal:

1. La persona inicia sesión con Apple y crea un grupo o acepta una invitación.
2. Dicta productos y tienda, o utiliza la entrada manual.
3. Revisa la propuesta interpretada y la corrige si es necesario.
4. Confirma su incorporación a los pendientes del grupo.
5. Cualquier miembro consulta una tienda, marca provisionalmente lo que va comprando y confirma los productos seleccionados al finalizar.

El MVP debe completar este recorrido con dos usuarios reales. Los datos simulados no acreditan colaboración ni funcionamiento de la IA.

### Idiomas de la entrega

El 21 de septiembre el usuario establece español e inglés como requisito de la entrega, dado que el jurado incluye evaluadores españoles y de Reino Unido/Estados Unidos. La interfaz, errores, permisos, textos de accesibilidad y recorrido de demostración deben poder utilizarse en ambos idiomas. Los nombres de productos, tiendas y grupos introducidos por las personas se conservan, sin traducción automática de los datos compartidos.

La transcripción y la interpretación se preparan y prueban en español e inglés, comprobando por separado el soporte real de Speech y Foundation Models en el entorno disponible. La disponibilidad de Siri AI no acredita la de estos frameworks. Cualquier limitación real de idioma o modelos se registra y requiere una decisión explícita; no se considera resuelta solo por traducir la interfaz o actualizar macOS.

## 2. Acceso y grupo

- Autenticación mediante **Iniciar sesión con Apple**. No se implementan contraseñas propias.
- El backend verifica la identidad recibida y mantiene la sesión de la aplicación.
- La sesión se conserva de forma segura para evitar repetir el acceso en cada apertura. Si deja de ser válida, se solicita autenticación.
- Una cuenta pertenece a un grupo en el MVP.
- Una persona autenticada sin grupo puede crearlo, indicando su nombre, o incorporarse mediante una invitación.
- La familia o grupo es una entidad propia de la app; no depende de «En familia» de Apple.
- El creador gestiona las invitaciones. Los miembros pueden añadir, consultar, editar y marcar productos del grupo.
- El backend comprueba pertenencia en las operaciones sobre datos compartidos. No basta con conocer un identificador de grupo, tienda o producto.
- Una invitación a otro grupo no traslada silenciosamente a una persona que ya pertenece a uno. La gestión de múltiples grupos queda fuera.

### Invitaciones

- El creador solicita una invitación y comparte su enlace mediante la hoja nativa del sistema, por ejemplo por Mail o Mensajes.
- La aplicación no envía correos automáticamente ni mantiene una infraestructura de email.
- Cada invitación tiene un identificador secreto no predecible, caducidad y un único uso; el creador puede revocarla.
- Quien abre el enlace se identifica con Apple si es necesario, ve el nombre del grupo y confirma la incorporación.
- Abrir el enlace, o una previsualización del mismo, no consume la invitación. Se consume al aceptar la incorporación.
- La invitación no se vincula al email destinatario. Quien posea un enlace válido puede aceptarlo; una vez utilizado no admite otro miembro.
- Se usa la identidad estable de Apple para reconocer al usuario, sin exigir que su email coincida con el medio de entrega.
- Los enlaces caducados, revocados o ya utilizados muestran un resultado comprensible y no conceden acceso.
- Si hay que iniciar sesión, se conserva la invitación pendiente hasta completar el flujo.
- Con la app instalada, el enlace debe abrir la incorporación mediante un enlace universal. Sin la app, una página mínima informa de esa necesidad; no se implementa incorporación web ni un flujo automático posterior a la instalación.

La duración de las invitaciones y los detalles de sesión se concretan en el [contrato técnico](contracts/mvp-api.md). No cambian el alcance funcional.

## 3. Pestaña «Añadir»

La voz forma parte del MVP. Con Apple Intelligence disponible, Añadir comienza con una pregunta y un micrófono centrados, sin mostrar un formulario vacío ni una revisión adicional. La persona inicia y termina la captura mediante el control visible. La entrada escrita y manual se conserva en la recuperación; sin modelo, la entrada manual es el recorrido principal.

Ejemplo de aceptación: «Comprar jabón, cerveza y yogures en Mercadona» produce tres productos asociados a Mercadona.

Flujo:

1. Speech transcribe el audio; al terminar el dictado con una transcripción no vacía, se inicia automáticamente la interpretación.
2. Foundation Models interpreta el texto y propone productos, cantidades cuando se indiquen y tienda. Si los datos están completos, una alerta muestra esos detalles y ofrece «Confirmar» o «Editar».
3. «Confirmar» envía únicamente el lote de esa interpretación, sin incorporar otros productos del borrador ni volver a interpretar los valores. Una coincidencia exacta de tienda no añade otra revisión; una ambigüedad real usa la elección explícita existente.
4. «Editar» muestra el texto, las filas corregibles y la entrada manual. La persona puede corregir productos, cantidades y tienda o quitar una entrada antes de pulsar Añadir. En esta recuperación, el texto conserva su acción de interpretar.
5. Si no se encuentran productos, el modelo rechaza la entrada o falla la captura/interpretación, se explica el resultado y se muestran los mismos controles de recuperación, conservando los datos.
6. Sólo después de la confirmación del servidor aparece el aviso de alta; para una sola tienda ofrece «Ver lista» o «Cerrar aviso».

Reglas:

- Antes de confirmar no se crean productos compartidos.
- Los datos incompletos o ambiguos se hacen visibles para corregirlos; no se inventan cantidades, tiendas ni equivalencias entre unidades.
- La app no fusiona silenciosamente productos distintos ni elimina variantes como «sin lactosa». Al reinterpretar, sólo sustituye sugerencias anteriores de la sesión que continúen intactas; conserva entradas manuales, corregidas y otros borradores. No infiere ese origen al restaurar un borrador de otra ejecución.
- El backend valida el lote y lo guarda de forma atómica: completo o sin altas parciales.
- Un mismo envío conserva su identificador al reintentarse. Un timeout o una doble pulsación no genera productos duplicados.
- Dos altas voluntarias son distintas de un reintento del mismo envío; la deduplicación semántica queda fuera del MVP.
- Sólo se comunica «guardado» cuando existe confirmación del servidor.
- Tras añadir a una sola tienda, el aviso permite «Ver lista» para abrir Comprar con esa tienda seleccionada, también si acaba de crearse. Es opcional: cerrar el aviso mantiene la pantalla actual. El atajo requiere un destino confirmado y disponible en el grupo actual; los envíos a varias tiendas conservan el aviso sin elegir una por el usuario.
- Un error conserva el borrador y permite reintentar. La transcripción y la interpretación no autorizan por sí mismas cambios en los datos compartidos.
- La entrada manual permite indicar producto, cantidad opcional y tienda sin depender de la IA. Con grupo activo, «Añadir producto» envía únicamente ese producto directamente, sin una segunda revisión y sin incluir otros borradores. Sin grupo, se conserva como borrador local. Editar una propuesta existente solo corrige el borrador hasta su alta explícita. Esta alternativa no sustituye la validación de voz e IA.
- Una coincidencia exacta única de tienda se resuelve automáticamente; un nombre nuevo visible en el formulario o propuesta expresa su creación al confirmar el alta. Solo una ambigüedad real pide elegir. Se conservan acentos y puntuación según el contrato.
- Las nuevas altas y ediciones admiten hasta 60 puntos de código Unicode en el nombre del producto y 40 en una tienda nueva; la cantidad conserva su límite de 80. Se comprueban texto recibido y normalizado. La ayuda de longitud aparece bajo el campo afectado, en rojo y con explicación textual, sólo mientras se excede su límite. No se recortan los datos guardados ni se invalidan recibos ya confirmados bajo el contrato anterior.
- Si la IA no está disponible, Añadir prioriza la entrada manual y oculta los controles que dependen del modelo. Un texto con icono de información explica si el dispositivo no es compatible, Apple Intelligence está desactivada, el modelo aún no está listo, el idioma no es compatible o hay una indisponibilidad temporal. No se muestra un botón genérico de comprobar disponibilidad. Una transcripción conservada sigue siendo legible y editable en su propia sección. La consulta por voz de tiendas en Comprar no depende de Apple Intelligence.

### Organización visual acordada el 25 de septiembre (#28)

Añadir y Comprar comparten el nombre real del grupo como título y un acceso a Ajustes. Cuenta, identificación con Apple, creación de grupo e invitaciones se presentan en Ajustes, incluido cerrar sesión. La recepción de una invitación dirige a ese espacio y conserva las protecciones de presentación y recuperación existentes.

Los controles de micrófono, editar y quitar usan iconos con nombre accesible; las acciones explícitas usan cápsulas primary. Se aplican los tokens del sistema de diseño en sus cuatro apariencias, preservando controles y alertas nativas. Se reserva espacio para la lista y el formulario, sin repetir «Grupo / Tu grupo / nombre» en las pantallas principales.

Esta simplificación no incorpora un micrófono universal para añadir, consultar y borrar ni autoriza mutaciones automáticas por voz. Esa propuesta se aplaza hasta después del MVP.

## 4. Pestaña «Comprar»

- La persona puede decir «Dame la lista de Mercadona» o elegir una tienda mediante un selector.
- La interpretación identifica la tienda solicitada; los productos proceden de los datos del grupo, no de una respuesta inventada por el modelo.
- Si hay ambigüedad, se ofrecen las coincidencias para elegir.
- Se muestran los productos pendientes incorporados por todos los miembros.
- La tienda reconocida permanece visible y puede corregirse sin volver a hablar.
- La pantalla permite editar productos pendientes, seleccionarlos mediante checks y confirmar los seleccionados con «Confirmar compra».
- Editar y Quitar aparecen al deslizar la fila hacia la izquierda, con una ayuda breve bajo la lista y acciones nativas para VoiceOver. El gesto completo no ejecuta ninguna acción; Quitar mantiene la confirmación existente. Los nombres disponen del ancho liberado por los iconos de acción.
- Un producto seleccionado sigue visible, diferenciado del resto, hasta confirmar. El contador situado sobre «Confirmar compra» muestra cuántos productos se enviarán; la etiqueta accesible del botón también conserva esa cantidad.
- Se actualiza al entrar, tras las operaciones propias y mediante refresco explícito. No se promete presencia ni actualización instantánea entre dispositivos.

## 5. Compra, cancelación e historial

- Cada producto pendiente tiene un check de selección provisional. Marcar o desmarcar sólo cambia el borrador local de esa compra; no modifica todavía el estado compartido ni crea historial.
- Antes de enviar, una pulsación accidental se corrige desmarcando el producto.
- «Confirmar compra» envía los identificadores concretos de los productos seleccionados de esa tienda. El backend confirma sus cambios en una transacción; no se actualiza una tienda completa mediante un filtro general.
- Los productos confirmados pasan a comprados y salen de pendientes, conservando sus registros. Se guarda quién confirmó la compra y cuándo; puede ser una persona distinta de quien los añadió.
- Los productos no seleccionados permanecen pendientes para la próxima visita. Para el MVP se adopta la simplificación permitida por el usuario: mantenerlos automáticamente, sin preguntar en cada compra si se eliminan.
- Sin productos seleccionados no se envía una finalización vacía.
- Decisión del 25 de septiembre: al refrescar correctamente, se desmarcan automáticamente solo los productos seleccionados que cambiaron de versión o ya no están pendientes en esa tienda. Un aviso invita a revisar y volver a marcar los que se quieran comprar; no hay un paso obligatorio de deselección. Los demás checks se conservan. Esto no modifica la intención de un envío con resultado incierto.
- La finalización conserva un identificador estable para reintentos del mismo envío. Una doble pulsación o una respuesta perdida no registra dos compras.
- Un reintento repite exactamente la selección enviada. Modificarla no permite reutilizar el identificador anterior; si su resultado aún se desconoce, debe resolverse antes de iniciar una finalización distinta.
- Un error de envío conserva la selección y permite reintentar. La pantalla sólo presenta la compra como confirmada cuando el servidor lo acredita.
- Cambiar de pantalla o pasar a segundo plano no confirma la compra. La selección pertenece a una tienda y no se aplica a otra por cambiar el selector.
- «Ya no lo necesitamos» es una cancelación, no una compra. No debe alimentar futuras estadísticas de compras.
- Volver a necesitar el mismo producto crea una nueva entrada. No se recicla el registro de una compra anterior para representar otra distinta.
- Dos finalizaciones concurrentes que contienen el mismo producto no generan dos compras ni sobrescriben al comprador de la primera transición válida. Si un miembro compró, canceló o editó un producto seleccionado entretanto, se concilia con el estado del servidor y se informa del conflicto; el contrato técnico concretará la respuesta.
- Finalizar una compra no elimina ni marca como compradas las altas concurrentes de otros miembros ni los productos que no se enviaron expresamente.
- **Se incluye la confirmación conjunta de los productos marcados; no se incluye «seleccionar todo», vaciar ni resetear la lista**.

Historial mínimo por entrada:

| Dato | Finalidad |
|---|---|
| Identificador, grupo y tienda | Pertenencia e identidad de la entrada |
| Producto y cantidad si existe | Conservar lo que la persona confirmó |
| Autor y fecha de incorporación | Origen de la petición |
| Estado pendiente, comprado o cancelado | Separar necesidad, compra y cancelación |
| Comprador y fecha de compra | Registrar la compra efectiva |

El [contrato técnico](contracts/mvp-api.md) define el modelo lógico para las migraciones y los conflictos. No se compromete una pantalla analítica de historial, un catálogo maestro ni un registro de cada edición.

## 6. Conectividad y errores

- Las operaciones compartidas requieren conexión y confirmación del backend.
- Puede consultarse la última lista recuperada, indicando que puede estar desactualizada.
- Se conservan los borradores de entrada ante errores.
- Los checks de una compra son un borrador local, separado del estado compartido. Marcar productos no promete reservarlos ni avisar a otros miembros; la sincronización ocurre al confirmar y recuperar datos del servidor.
- No se implementa una cola general de modificaciones offline ni sincronización automática posterior de cualquier cambio.
- Una operación fallida no se presenta como completada. Las actualizaciones optimistas, si se utilizan, deben reflejar el error y recuperar un estado coherente.
- El cierre o reapertura de la app no pierde datos que el servidor ya confirmó.

## 7. Marco técnico

- App: iOS 27 como versión mínima, SwiftUI, Swift 6 y concurrencia estricta.
- Sin dependencias de código de terceros en la app.
- Voz: evaluar SpeechAnalyzer/SpeechTranscriber en el dispositivo e idioma reales.
- Interpretación: Foundation Models con salida estructurada y revisión humana.
- Comunicación: URLSession sobre HTTPS.
- Backend: Vapor 4.122.2 y PostgreSQL, tras comprobar el bloqueo de la combinación Vapor 5 evaluada en Linux y aplicar la alternativa autorizada. La decisión y sus límites se documentan en [la validación del bloque 1](validation/issue-1-server-bootstrap.md). El servicio compartido está desplegado en Railway; la [guía de configuración](setup/shared-shopping.md) describe su identidad Apple, HTTPS y persistencia.
- Pruebas unitarias y de integración en Swift Testing; no introducir XCTest unitario ni Core Data.
- Warnings tratados como errores en el código propio; las excepciones externas expresamente aceptadas se delimitan en [el registro de dependencias](dependency-exceptions.md).
- Verificar Xcode/SDK, toolchain del servidor y dispositivos compatibles antes de implementar. El objetivo iOS 27 no determina por sí solo la versión de Swift disponible en Linux.

La FAQ pública consultada el 19 de septiembre aún indica sistemas 26. El usuario confirma expresamente que dispone de autorización de los organizadores para exigir iOS 27; ésa es la aclaración aplicable a este proyecto. No se presenta como un cambio ya publicado en la FAQ.

El cliente y el backend se implementan desde cero para el evento. La elección de una herramienta no acredita un despliegue ni una validación ya realizados.

### Sistema de diseño y accesibilidad

El [sistema de diseño](design-system.md) es la referencia de tokens, tipografía, espaciado, componentes y estados. Se inspira en el verde y amarillo del icono candidato aportado el 23 de septiembre: verde como acento interactivo y amarillo como apoyo con tinta oscura. Los estados de selección provisional, éxito, aviso y error se distinguen con texto, forma y semántica, además del color. El 24 de septiembre el usuario aprueba incorporar los iconos Icon Composer Brain (principal) y Check (alternativo para hardware no compatible con Apple Intelligence), conservando el material de diseño original. Esta incorporación no completa la aplicación del sistema de diseño a las pantallas.

El 25 de septiembre el usuario autoriza [#20](https://github.com/JFrancoG/SmartShoppingList/issues/20): preparar los 21 tokens en assets con cuatro variantes y acceso directo mediante los símbolos que genera Xcode. Los assets usan PascalCase sin prefijo, salvo `AppPrimary` y `AppSeparator` por colisiones nativas. `primary` es el color interactivo y tinte global, sin un `AccentColor` redundante. `.appPrimary` identifica el token propio; `.primary` conserva el estilo nativo de SwiftUI cuando sea el apropiado. Se utiliza inferencia de tipo siempre que sea suficiente. La aplicación a las pantallas y su validación quedan como trabajo posterior.

- Soportar Light, Dark, Light con Aumentar contraste y Dark con Aumentar contraste, siguiendo las preferencias del sistema. Texto informativo propio ≥4,5:1 en normal y ≥7:1 en alto contraste; información gráfica esencial ≥3:1 frente al fondo adyacente real. Los pares autorizados y su [validación matemática](validation/design-system-contrast.md) son parte del contrato visual.
- Mantener superficies sólidas en contenido propio y presentación nativa de navegación/controles; verificar por separado los materiales y su personalización en iOS 27, incluyendo Reducir transparencia. Respetar Reducir movimiento, Diferenciar sin color y las formas de botones.
- Usar estilos tipográficos semánticos, Dynamic Type hasta el mayor tamaño de accesibilidad, Texto en negrita, reflujo y objetivos táctiles propios ≥44×44 pt. Las vistas se adaptan al espacio disponible sin perder acciones con teclado, traducciones o texto grande.
- Aplicar el [protocolo de accesibilidad](accessibility.md) a los recorridos en español e inglés, con VoiceOver, controles alternativos, errores perceptibles y foco conservado. Los pendientes físicos ya registrados siguen abiertos hasta revalidarse.
- Tomar WCAG 2.2 A/AA como base, interpretada para software nativo con WCAG2ICT y complementada por HIG actuales. El objetivo de 7:1 en HC no significa conformidad AAA global. La [revisión de fuentes](research/design-system-sources.md) incorpora WWDC26 y documentación W3C posterior a la referencia de iOS 26; WCAG 3 continúa como borrador.

La documentación, los assets y los ratios no acreditan que los colores estén aplicados a todas las pantallas ni que la app cumpla todos los criterios. La aceptación requiere medición de la interfaz renderizada y evidencia del recorrido completo. Este trabajo se integra en fase 3 sin añadir funciones al MVP.

### Estrategia de validación acordada

- En el iPhone físico sin Apple Intelligence se comprobará la entrada manual de producto y tienda con «Añadir producto» como única acción explícita de guardado; no se exige una segunda revisión. Con IA, la propuesta ofrece Confirmar/Editar; Editar y los errores conservan la recuperación editable. Se comprobará que Confirmar envía sólo el lote propuesto, que interpretar no envía nada y que se conservan otros borradores.
- Foundation Models se probará en un simulador compatible del Mac, tras comprobar que el entorno y el modelo están disponibles. La compatibilidad y disponibilidad no se dan por garantizadas.
- La voz y la IA siguen dentro del alcance. Se registrará por separado la evidencia de captura y transcripción, interpretación con Foundation Models y funcionamiento del recorrido manual.
- Cada resultado identificará el dispositivo o simulador utilizado. Una prueba de Foundation Models en simulador no acredita su funcionamiento ni sus tiempos en el iPhone físico; la entrada manual tampoco acredita voz ni interpretación.
- Este reparto de pruebas no declara validado ninguno de los recorridos. Las comprobaciones que no puedan completarse quedarán identificadas con su limitación y evidencia disponible.

## 8. Criterios de aceptación de la entrega

1. Dos usuarios distintos se identifican y comparten un grupo mediante una invitación válida.
2. Invitaciones inválidas y accesos ajenos al grupo no conceden acceso.
3. El ejemplo de voz genera un borrador corregible; ninguna alta llega al grupo antes de confirmar.
4. Las correcciones prevalecen en los datos guardados y el lote no se duplica al reintentar.
5. La consulta por voz y el selector muestran los pendientes reales de la tienda y del grupo.
6. Altas concurrentes de distintos miembros se conservan.
7. Marcar y desmarcar no modifica el backend; «Confirmar compra» confirma sólo los seleccionados. Por ejemplo, de cinco pendientes con tres checks, se registran tres compras y los otros dos siguen pendientes.
8. Reintentar una finalización o confirmar concurrentemente un mismo producto no cuenta dos compras. Una nueva alta de otro miembro queda intacta; cancelar no cuenta como comprar. Los errores conservan la selección sin presentar éxito falso.
9. Reiniciar app y servidor conserva los datos confirmados.
10. Fallos de micrófono, IA o red tienen estados comprensibles y no presentan éxito falso.
11. Los recorridos esenciales funcionan con VoiceOver, texto de accesibilidad al máximo y controles alternativos en español e inglés, con foco y mensajes de error perceptibles, comprobados según el [protocolo de accesibilidad](accessibility.md).
12. El repositorio incluye instrucciones verificadas para ejecutar cliente y servidor, configurar servicios y reproducir la demostración, sin secretos.
13. El sistema de diseño se aplica de forma coherente en las cuatro apariencias; los pares sólidos y los componentes renderizados cumplen sus objetivos de contraste. Se verifican preferencias de accesibilidad, materiales y reflujo en iOS 27, sin presentar una validación de paleta como conformidad global del producto.

## 9. Fuera de la entrega del 27

No forman parte del MVP: sugerencias, predicción de reposición, estadísticas de compra, recetas, precios, comparación comercial, inventario doméstico, múltiples grupos por persona, roles personalizados, varias plataformas, presencia en tiempo real, sincronización offline completa, envío automático de correos, seleccionar toda la tienda automáticamente, vaciar pendientes al terminar y órdenes de modificación o borrado por voz. La confirmación conjunta de los checks sí forma parte del MVP.

El 27 de septiembre se aprueba como evolución posterior al MVP la pertenencia a varios grupos, con un único administrador miembro por grupo y posibilidad de que una persona administre ninguno, uno o varios. Se descarta limitar la administración a un grupo por cuenta. El traspaso exige aceptación de otro miembro, conserva al responsable actual hasta completarse y convierte al anterior en miembro sin cambiar el creador histórico. Las reglas aprobadas, los casos de aceptación y las decisiones aún abiertas se conservan en [varios grupos y traspaso de administración](architecture/multiple-groups.md). Se documenta para retomarlo dentro de unos días; no se incorpora a esta entrega ni se inicia su implementación.

El 9 de octubre, terminado el hackatón, el usuario autoriza retomar esta evolución: un grupo gratuito por cuenta, que se puede administrar; premium para grupos adicionales y para ampliar futuros límites de tiendas por grupo y productos pendientes por tienda. Comprados y cancelados no consumen el cupo de productos. Pertenencias y responsabilidades se conservan separadas del acceso comercial; recibir la administración de una pertenencia existente no requiere otro pago. El usuario aprueba que el plan del administrador determine la capacidad compartida y autoriza implementar el plan. La [decisión de acceso y límites](architecture/group-access-and-limits.md) recoge estas reglas y los detalles pendientes de cifras, pérdida de acceso y migración. [#33](https://github.com/JFrancoG/SmartShoppingList/issues/33) desarrolla la primera unidad; los pagos y la activación de restricciones son posteriores. Esta ampliación no altera retrospectivamente el contrato entregado del MVP.

Tras integrar #33 mediante PR #34, el propietario autoriza [#35](https://github.com/JFrancoG/SmartShoppingList/issues/35): migrar pertenencias múltiples y cambiar explícitamente de grupo, con selección local por cuenta/dispositivo y conservación del borrador y de cada operación pendiente en su destino original. La admisión sigue limitada por la política autoritativa del servidor; las capacidades ampliadas se prueban por inyección sin activar una oferta premium. El [contrato de pertenencias](contracts/group-memberships.md) concreta compatibilidad y aislamiento. El estado de implementación y la evidencia pertenecen a la issue; no se declara despliegue en producción.

El 10 de octubre, después de integrar #35 mediante PR #36, aprueba [#37](https://github.com/JFrancoG/SmartShoppingList/issues/37): cupos gratuitos de 1 grupo por cuenta, 3 tiendas activas por grupo y 20 productos pendientes por tienda; ampliaciones premium de 5 grupos en total, 10 tiendas y 100 pendientes mediante una única suscripción personal. La capacidad compartida sigue el plan del administrador. El archivo explícito de una tienda sin pendientes libera capacidad y conserva historial e identidad; solo el administrador puede archivar/restaurar y la restauración requiere plaza. Se conserva el contenido al superar cupos y se limita su crecimiento, permitiendo resolver el exceso. Se autoriza implementar cupos y gestión de tiendas, dejando compras verificadas y cobro para la siguiente unidad. La [decisión de acceso y límites](architecture/group-access-and-limits.md) conserva las reglas; no cambia retrospectivamente el alcance del MVP ni acredita activación comercial o despliegue.

Tras integrar #37 mediante PR #38, el propietario aprueba e inicia [#39](https://github.com/JFrancoG/SmartShoppingList/issues/39): compra/restauración de una única suscripción mediante StoreKit y derechos verificados por el servidor, con siete días de transición para los grupos existentes desde el final ordinario efectivo de premium y sin nuevas admisiones. Los cupos del administrador bajan inmediatamente a 3/20; cancelar la renovación conserva el periodo vigente y una gracia de cobro verificada de Apple mantiene premium hasta su final comunicado. Se acuerdan dieciséis días de gracia de Apple para pago a pago, sujetos a configuración externa. Reembolso/revocación no reinicia cortesía.

La cuenta conserva o elige un grupo gratuito de uso completo; sin elección válida se usa la pertenencia más antigua sin consumir la primera decisión manual. Cambiarla exige treinta días móviles, con sustitución segura cuando se pierde la pertenencia/grupo y sin borrar el plazo previo. Los adicionales conservan consulta y acciones para traspasar, salir/cerrar, revocar invitaciones, archivar tiendas vacías, cancelar pendientes y recuperar recibos; nueva alta/edición/compra/restauración/invitación exige uso ordinario. No se borra contenido ni se cambia el administrador automáticamente. El [contrato de suscripciones](contracts/premium-subscriptions.md) fija API, autorización, recuperaciones y matriz de aceptación. Precios, regalos de lanzamiento, inscripción Small Business, configuración comercial y activación de cobros quedan separados; este acuerdo permite implementar y validar sin ejecutar esos pasos ni alterar retrospectivamente el MVP.

El 25 de septiembre se propone estudiar compra y cancelación de productos por voz con Apple Intelligence. Sigue fuera del MVP; solo se reconsiderará como extra si la entrega obligatoria está resuelta y sobra tiempo. El [plan](implementation-plan.md) conserva el diseño preliminar y sus decisiones pendientes. No equivale a autorizar su implementación ahora.

Tras la entrega podrán estudiarse sugerencias de productos frecuentes por tienda, reutilización de compras anteriores y otras mejoras. Son posibilidades, no compromisos ni tareas activas. Cualquier ampliación anterior al cierre exige acordar explícitamente qué se sustituye o se retira del MVP.

El 22 de septiembre se acuerda aplazar hasta después del MVP la posibilidad de asociar una única necesidad de compra a varias tiendas alternativas (por ejemplo, «fresas en Aldi o Mercadona») y resolverla al comprar en cualquiera de ellas. En el MVP cada entrada pertenece a una sola tienda; repetir un producto en tiendas distintas crea entradas independientes. La ampliación queda como posibilidad por estudiar, sin implementación ni tarea activa en esta entrega.

El 22 de septiembre el usuario aprueba planificar como extra opcional la entrada al borrador mediante Siri/App Intents, después del recorrido de compra ([#10](https://github.com/JFrancoG/SmartShoppingList/issues/10)). La primera versión se limita a producto, tienda y cantidad opcional en el borrador local, con revisión posterior y sin envío al grupo. No modifica el alcance base ni convierte la frase libre de ejemplo en una capacidad ya validada. Tras integrar el recorrido principal, el 26 de septiembre se autoriza un intento acotado de 3–4 horas; se aplaza lo pendiente hasta después del MVP si compromete la entrega. La acción abre la app, recibe parámetros explícitos y conserva la revisión local. La cantidad opcional se configura en Atajos; la frase genérica con el nombre de la app puede solicitar producto y tienda. Una nueva invocación es una petición nueva, incluso si repite los mismos valores; no se promete deduplicación entre ejecuciones de Siri, que no proporcionan una identidad pública estable.

El 27 de septiembre se acuerda conservar dos vías sobre la misma operación de borrador: Siri tradicional con frases explícitas y preguntas, cuyo recorrido básico en español con la app en primer plano, segundo plano y cerrada confirma el propietario en iPhone 14, y una ampliación futura de comprensión conversacional mediante Siri AI cuando existan disponibilidad y soporte adecuados. Con la app cerrada confirma que Siri la abre y añade el producto al borrador. Apple Intelligence no es un requisito de la primera vía. El ensayo de Siri AI en Mac no ha ejecutado la acción; no se incorpora esa capacidad al MVP ni se promete que disponer de Siri AI baste para resolver órdenes libres. El [plan de evolución y sus criterios](validation/issue-10-app-intents.md#siri-tradicional-ahora-y-ampliación-con-siri-ai) queda documentado.

Ampliación aprobada del extra #10 el 27 de septiembre, después de validar la acción local: una segunda acción explícita «Añadir a la lista» recibe una única entrada y permite enviarla al grupo cuando la tienda existe y hay una coincidencia exacta única según la normalización vigente. La orden de añadir es la confirmación de esa entrada; no incluye otras filas ni texto del borrador. Se verifica la sesión y el grupo, se conserva la operación para reintentos y sólo se anuncia el alta tras confirmación del servidor. El aviso existente ofrece «Ver lista / Cerrar». Sin coincidencia o ante varias tiendas posibles, se abre el borrador con los datos recibidos, sin crear una tienda automáticamente. La ausencia de acceso o los errores conservan datos recuperables y no se presentan como un alta compartida correcta. Se mantiene «Añadir al borrador» con su contrato y frases anteriores. No hay catálogo de productos ni puntuación de confianza de Siri: la regla se basa en validación de campos y coincidencia de tienda. No se amplía a comprar, cancelar ni interpretar frases libres con Siri AI.

Refinamiento de #10 aprobado el 27 de septiembre: añadir la frase «Añade a mi lista de la compra en SmartShoppingList», conservando «Añade a mi lista en SmartShoppingList». La nueva acción pide producto, cantidad y tienda como campos separados; la cantidad es texto requerido sin valor por defecto, para que Siri la solicite antes de ejecutar. Permite cantidades literales como «dos packs de seis unidades», sin extraerlas automáticamente del nombre ni convertirlas a un número. La acción anterior de borrador conserva la cantidad opcional. El nombre de la app forma parte de las frases publicadas; no se promete resolver la orden genérica sin él.

Tras el cambio de nombre visible del mismo día, las frases actuales usan **Smart List**, por ejemplo «Añade a mi lista de la compra en Smart List» / «Add to my shopping list in Smart List». La [compilación Release](validation/release-2026-09-27.md) verifica sus metadatos en ES/EN. El usuario confirma después el [recorrido de lista desde cero en español e inglés con Smart List](validation/issue-10-app-intents.md#siri-con-smart-list-en-español-e-inglés); son confirmaciones posteriores al renombrado, independientes de los ensayos con el nombre anterior.

## 10. Fuentes y decisiones

- [Bases públicas del evento](https://acoding.academy/hackaton26/).
- Aclaración de organizadores aportada por el usuario: se admite cualquier plataforma Apple y consumir APIs propias o ajenas mediante networking nativo; la app no puede incorporar dependencias externas.
- [SpeechAnalyzer, WWDC25](https://developer.apple.com/videos/play/wwdc2025/277/).
- [Verificación de identidad Apple](https://developer.apple.com/documentation/signinwithapple/verifying-a-user).
- [Dominios asociados y enlaces universales](https://developer.apple.com/documentation/xcode/supporting-associated-domains).

Decisiones de la conversación del 18 de septiembre: el usuario elige Sign in with Apple e invitaciones compartidas mediante enlace, y aprueba el alcance funcional descrito para el día 27, dejando las ampliaciones para después.

Decisiones del 19 de septiembre: el usuario sustituye la compra inmediata por check por una selección provisional y un envío al finalizar. Los no marcados se mantienen pendientes; se usa la simplificación expresamente permitida de omitir la pregunta de eliminación. También solicita iOS 27, confirma autorización de los organizadores para exigirlo, y elige Vapor 5 si es viable, o Vapor 4 en caso contrario.

Acuerdo de validación del 19 de septiembre: utilizar entrada manual de productos y tienda en el iPhone físico sin Apple Intelligence y comprobar Foundation Models en un simulador compatible del Mac, distinguiendo las evidencias de ambos entornos y manteniendo voz e IA en el alcance.

Decisión documental del 23 de septiembre, a petición del usuario: definir una identidad coherente inspirada en el icono candidato y accesible en los cuatro modos, comprobar fuentes actuales Apple/W3C y conservar tokens, pares permitidos y protocolo en `docs`. La integración y el ensayo pertenecen a fase 3; esta revisión no los declara completados.
