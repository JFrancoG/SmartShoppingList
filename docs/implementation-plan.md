# Plan de implementación

Fecha de creación: 18 de septiembre de 2026. Última revisión: 25 de septiembre de 2026.

Especificación de referencia: [MVP aprobado](mvp-spec.md). Este documento conserva las fases, dependencias y condiciones para avanzar; no amplía el contrato funcional ni registra el progreso de cada tarea.

## Organización y seguimiento

Una persona desarrolla con ayuda de Codex, con jornadas disponibles de 4–8 horas. La planificación no depende de disponer siempre de ocho horas ni trata la generación de código como sustituto de las comprobaciones reales.

| Lugar | Responsabilidad |
|---|---|
| [Especificación](mvp-spec.md) | Alcance aprobado, reglas funcionales y criterios de aceptación |
| [Contrato técnico](contracts/mvp-api.md) | Tipos y operaciones compartidos, integridad, sesiones, invitaciones y conflictos; ejemplos verificables |
| [Sistema de diseño](design-system.md) y [accesibilidad](accessibility.md) | Tokens y componentes, pares permitidos, criterios de interfaz y protocolo de comprobación; fuentes y ratios enlazados |
| Este plan | Fases, ventanas objetivo, dependencias y resultados esperados |
| [GitHub Issues](https://github.com/JFrancoG/SmartShoppingList/issues) | Plan de cada bloque, situación, bloqueos, decisiones de ejecución y evidencia de cierre |

GitHub Issues es el único seguimiento operativo. El [hito «MVP · September 27»](https://github.com/JFrancoG/SmartShoppingList/milestone/1) agrupa el trabajo de la entrega. Su fecha es un objetivo de planificación; el canal y la hora oficial de entrega deben confirmarse. El porcentaje del hito sólo representa las issues creadas, no todo el alcance del MVP.

Se detallan las unidades del bloque inmediato. Las fases posteriores permanecen aquí hasta que corresponda concretarlas en issues. No se crean tareas por conversación, archivo o commit, ni issues retrospectivas para trabajos ya entregados. Tampoco se mantiene una segunda lista de estados en un archivo de progreso.

Cada issue contiene resultado, fuentes, alcance, plan vigente identificado como Draft o Approved, dependencias, criterios de aceptación y validación prevista. Su descripción identifica si está pendiente, en curso o bloqueada; crearla no significa empezar la implementación. Al cambiar materialmente el plan se actualiza la descripción y se añade un comentario fechado con la decisión, su motivo y evidencia. Las decisiones duraderas se reflejan en la spec o en el documento técnico correspondiente.

La evidencia se registra en la issue con fecha, entorno, resultados y referencia al commit o PR. Los informes extensos pueden guardarse en archivos enlazados. Una issue se cierra cuando cumple sus criterios, se valida y sus cambios están entregados en `main`; compilar pruebas, abrir una PR o escribir un plan no equivale a completar el trabajo.

## CI mínimo antes de la entrega

El 25 de septiembre se autoriza [#26: CI mínimo de servidor y contrato](https://github.com/JFrancoG/SmartShoppingList/issues/26), con un máximo de una hora de configuración. GitHub Actions ejecutará las pruebas existentes del servidor con PostgreSQL temporal y los validadores de contrato y colores. La [configuración](setup/ci.md) mantiene separados este control automático, las pruebas físicas y el despliegue. CI de iOS queda para después del MVP; el resultado real y la entrega se registran en la issue.

## Fases y resultados

| Fase | Ventana objetivo | Resultado verificable |
|---|---|---|
| 0. Definición | 18–19 septiembre | Spec aprobada, requisitos de arranque y organización del trabajo concretados |
| 1. Preparación y pruebas iniciales | 19–20 septiembre | Entrada manual en físico, voz/IA con evidencia de su entorno y colaboración mínima desplegada por HTTPS |
| 2. Recorrido funcional | 21–23 septiembre | Las dos pestañas completan los flujos del grupo y las compras |
| 3. Validación y acabado | 24–25 septiembre | Casos de error, concurrencia, accesibilidad y persistencia comprobados |
| 4. Preparación de entrega | 26 septiembre | Código congelado, instrucciones verificadas y demostración reproducible |
| 5. Margen y entrega | 27 septiembre | Incidencias de cierre resueltas y repositorio entregado por el canal oficial |

Estas fechas son objetivos, no evidencia de trabajo realizado. Las pruebas acompañan a la implementación desde la fase 1. Se congelan funcionalidades al finalizar el 25; el 27 no se reserva para añadir nada nuevo.

## Bloques iniciales: fases 0 y 1

| Issue | Resultado | Dependencias |
|---|---|---|
| [#1: viabilidad de Vapor y PostgreSQL](https://github.com/JFrancoG/SmartShoppingList/issues/1) | Arranque, persistencia, pruebas ejecutadas, verificación técnica de identidad Apple y contenedor Linux | Entorno local y toolchain compatibles; coordinar identidad con #2 |
| [#2: contrato mínimo](https://github.com/JFrancoG/SmartShoppingList/issues/2) | Esquema y contrato de identidad, grupos, invitaciones y productos | Puede avanzar junto a #1; concreta reglas de sesión, reintentos y conflictos |
| [#3: entrada e interpretación en iOS](https://github.com/JFrancoG/SmartShoppingList/issues/3) | Borrador editable, adaptadores Speech/Foundation Models y reglas verificadas con Swift Testing | Tipos y límites de #2; validación real separada en #7 |
| [#7: validación real del borrador](https://github.com/JFrancoG/SmartShoppingList/issues/7) | Entrada manual física, voz/IA verificadas en su entorno y accesibilidad con interacción | Implementación de #3, dispositivo y modelos disponibles |
| [#4: recorrido compartido con dos usuarios](https://github.com/JFrancoG/SmartShoppingList/issues/4) | Identidad, invitación y producto compartido persistente, comprobados por HTTPS | #1 y #2; implementación de #3 y evidencia de #7 para cerrar la integración del borrador; capacidades Apple y alojamiento |

El primer bloque técnico es [#1](https://github.com/JFrancoG/SmartShoppingList/issues/1). El [contrato de #2](contracts/mvp-api.md) incluye OpenAPI, ejemplos y una matriz de aceptación para los bloques de implementación. El estado vigente y el siguiente paso concreto se consultan en cada issue.

El 19 de septiembre el usuario autorizó entregar y cerrar #3, manteniendo pendientes sus comprobaciones reales. Se separan expresamente en #7 los criterios físicos, voz, inferencia real y accesibilidad, con la [evidencia y limitaciones observadas](validation/issue-3-ios-draft.md). El cierre de la implementación no acredita esos criterios ni completa la fase 1 o el hito; su alcance y la condición de avance permanecen intactos.

La evaluación de Vapor 5 tiene un límite máximo de cuatro horas de trabajo técnico acumulado: resolución de dependencias, arranque, PostgreSQL/transacciones, viabilidad de verificar identidad Apple y ejecución Linux. Ante un bloqueo de compatibilidad confirmado se puede adoptar antes la alternativa Vapor 4 aprobada, manteniendo iOS 27 y el alcance. El bloque 1 fija Vapor 4.122.2; la decisión se conserva en [su informe de validación](validation/issue-1-server-bootstrap.md) y el seguimiento en #1. No se actualizan betas durante el cierre.

La preparación confirma el iPhone de prueba, un segundo cliente, firma/capacidades, Sign in with Apple, enlaces universales y disponibilidad de modelos. La estrategia de [validación acordada](mvp-spec.md#estrategia-de-validación-acordada) usa entrada manual en el iPhone físico sin Apple Intelligence y Foundation Models en un simulador compatible del Mac. La captura/transcripción de voz se comprueba por separado, identificando el entorno real. La prueba manual no sustituye voz/IA ni los resultados del simulador se atribuyen al iPhone.

Railway se contrata/configura cuando existe un backend mínimo listo para desplegar. Se acuerda el presupuesto antes de contratar y se configuran alertas; un límite estricto de gasto puede detener los servicios. La preparación de las issues no autoriza gastos.

**Condición para avanzar al finalizar el segundo día técnico:** demostrar tanto el borrador y su interpretación como identidad, invitación y datos compartidos persistentes por HTTPS. Si falla un recorrido, se registra la evidencia y se acuerda la corrección o reducción necesaria, sin retirar funcionalidades aprobadas unilateralmente.

## Fase 2: completar el MVP

El resultado de esta fase es el recorrido completo descrito en la spec:

- Onboarding y sesión conservada, invitaciones válidas e inválidas y guardado atómico del lote confirmado con reintentos seguros.
- Consulta de tiendas por voz y selector sobre datos reales del grupo; edición de pendientes y distinción entre compra y cancelación.
- Checks locales reversibles, contador y finalización con IDs explícitos: mantener pendientes los no seleccionados, conservar selección ante errores y resolver conflictos sin duplicar compras. El 25 se acuerda desmarcar automáticamente los afectados tras una carga válida y avisar para que puedan volver a seleccionarse; se elimina la deselección manual obligatoria, manteniendo intactos los envíos inciertos.
- Historial mínimo por entrada y nueva entrada para una nueva necesidad; estados de carga, vacío y error, refresco y consulta de la última lista recuperada.
- Preparar las nuevas pantallas para español e inglés y adaptar la selección de idioma de Speech/Foundation Models, evitando el español fijo del recorrido inicial. Comprobar disponibilidad real por idioma con #7; la traducción y revisión completas se consolidan en fase 3.

La primera unidad es [#11: selección y finalización segura de compra](https://github.com/JFrancoG/SmartShoppingList/issues/11), sobre el código compartido de #4. Comprende checks locales por tienda, compra atómica de IDs/versiones explícitos, recuperación del envío y conflictos. Su [diseño](architecture/shared-shopping.md#selección-y-finalización-de-compra-11) y [validación](validation/issue-11-purchase-flow.md) separan pruebas locales de activación alojada y ensayo físico. Abrir este bloque no cierra #4/#7 ni da por completa la fase 2.

La siguiente unidad, entregada mediante PR #23 y cerrada el 25 de septiembre, es [#22: edición y cancelación segura de pendientes](https://github.com/JFrancoG/SmartShoppingList/issues/22). Incluye las rutas de edición/cancelación, su cliente iOS y los conflictos con compra; las pruebas de #11 sobre filas modificadas previamente no acreditan estos endpoints. El historial mínimo se comprueba conservando registros, estados, autor y fechas según la spec; no exige una pantalla nueva ni una API analítica.

Tras cerrar #22, se implementa en `97b0997` [#24: consulta de tienda por voz dentro de Comprar](https://github.com/JFrancoG/SmartShoppingList/issues/24), autorizada el 25 de septiembre en `codex/issue-24-store-voice-query`. Se implementa captura Speech reutilizada, texto editable y coincidencias sobre las tiendas reales del grupo, con dictado inline iniciado desde el micro, apertura automática de la coincidencia única, elección solo ante ambigüedad y alternativa manual. El usuario confirma coincidencia y ausencia de tienda y autoriza PR, merge y cierre de #24; el resultado definitivo se registra en la issue. Después se realizará el recorrido conjunto con dos usuarios. La consulta por voz pertenece al MVP y es distinta del extra Siri/App Intents #10. Se reutiliza la evidencia vigente de acceso, invitaciones y recuperación; la regresión se concentra en transiciones, concurrencia, reintentos y persistencia afectados. La matriz visual extensa ES/EN se ejecuta tras aplicar el design system a las pantallas, conforme al acuerdo de #17.

La fecha objetivo del 25 no acredita el cierre: antes de congelar deben estar implementados y comprobados los recorridos anteriores. La issue #22 conserva su [evidencia de entrega y ensayo físico](validation/issue-22-edit-cancel-items.md). La [validación de #24](validation/issue-24-store-voice-query.md) recoge coincidencia y ausencia de tienda confirmadas por el usuario, y distingue las pruebas locales de la accesibilidad física pendiente; no requiere otro despliegue del servidor. La localización de las nuevas acciones y la accesibilidad focalizada acompañan a su implementación.

### Extra opcional después del recorrido de compra: Siri

El 22 de septiembre el usuario decidió planificar [#10: entrada al borrador con Siri y App Intents](https://github.com/JFrancoG/SmartShoppingList/issues/10) después de completar el recorrido de compra. La primera acción recibirá producto, tienda y cantidad opcional para añadir una entrada al borrador local, conservando los datos existentes y la revisión posterior. Se preparará para español e inglés y se validará con Siri/Atajos reales. La frase exacta de invocación y la ejecución con app cerrada necesitan validación; no se acreditan por habilitar Siri AI. Es un extra planificado, todavía no implementado, que no sustituye los criterios pendientes del MVP ni bloquea el cierre de #4/#7. Antes de iniciarlo se revisará el margen de entrega.

### Propuesta posterior al MVP: compra y cancelación por voz con Apple Intelligence

El 25 de septiembre el usuario propone órdenes como «Marca la leche de Aldi como comprada» o «Quita el pan de Mercadona», interpretadas con Foundation Models. Se registra como posibilidad posterior al MVP; podría reconsiderarse antes solo si el alcance comprometido, las validaciones y la entrega están resueltos con margen. No se inicia implementación ni se amplía #24 o el extra de alta al borrador #10.

Diseño preliminar: Speech transcribe; el modelo propone una acción estructurada (compra o cancelación), producto y tienda; la app resuelve IDs y versiones contra pendientes reales del grupo. Ante duplicados o ambigüedad pide concretar. Se propone una confirmación breve en la misma pantalla antes de modificar datos compartidos. «Quitar» usaría la cancelación existente, conservando historial y sin contar como compra. La ejecución reutilizaría permisos, transacciones, conflictos y reintentos actuales, sin delegar la autorización al modelo. Quedan por acordar el flujo de confirmación y la distinción entre marcar el check local y confirmar la compra.

Requiere Apple Intelligence disponible en dispositivo/idioma; conserva alternativa manual. La [documentación de Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models) respalda generación estructurada y comprobación de disponibilidad; no acredita esta función ni su precisión. Evaluar con modelos reales ES/EN, negaciones/correcciones, productos repetidos, cambios concurrentes y reconocimiento erróneo antes de activarla.

## Fase 3: validar y corregir

### Sistema de diseño y accesibilidad: decisión del 23 de septiembre

El usuario solicita un sistema coherente inspirado en el icono candidato, actualizado respecto a la referencia de iOS 26. La [definición visual](design-system.md) fija verde como acento, amarillo como apoyo, colores semánticos y cuatro variantes automáticas. La [revisión de actualidad](research/design-system-sources.md) incorpora las novedades de Apple para iOS 27 y las guías W3C recientes, manteniendo WCAG 2.2 como base estable. No se amplía el alcance funcional.

La revisión del 23 entrega documentación y [ratios reproducibles](validation/design-system-contrast.md). El 25 se autoriza [#20: base visual del sistema de diseño](https://github.com/JFrancoG/SmartShoppingList/issues/20) como unidad independiente: 21 tokens en assets con cuatro variantes, acceso directo mediante los símbolos que genera Xcode y `AppPrimary` como tinte global sin duplicar `AccentColor`. Los assets usan PascalCase sin prefijo, salvo `AppPrimary` y `AppSeparator` por colisiones nativas. Los tokens del acento pasan a llamarse `primary`, `on-primary` y `primary-soft`, conservando sus valores. El tinte global sí afecta a los controles nativos que lo heredan; esta unidad no completa la aplicación de colores a las pantallas ni su ensayo de accesibilidad. #7 conserva la validación del borrador y sus hallazgos, sin duplicar su seguimiento ni cerrar criterios por esta base.

Orden de ejecución previsto:

1. Preparar y comprobar en #20 los assets sRGB con cuatro variantes, acceso semántico y tinte global. Ejecutar el verificador de pares y comprobar la compilación de recursos, sin introducir librerías de UI. Esta base puede preceder al acabado del recorrido funcional.
2. Aplicar después los tokens mediante componentes reutilizables, tipografía, espaciado y estados al recorrido de Añadir/Comprar, sesión e invitación; conservar controles y materiales nativos donde proceda. Usar inferencia de tipo cuando sea suficiente, por ejemplo `.foregroundStyle(.primary)` para el estilo nativo y `.foregroundStyle(.appPrimary)` para el token propio. Mantener selección provisional, confirmación del servidor y reintentos del contrato.
3. Corregir los hallazgos de avisos/foco/recorte ya registrados y consolidar ES/EN. Preparar previews de estados y tamaños, con layouts adaptables a iOS 27.
4. Ejecutar la [matriz de accesibilidad](accessibility.md#ejecución-de-la-validación): cuatro apariencias, texto grande, controles alternativos, material y preferencias. Registrar evidencia por entorno/idioma en las issues e informes existentes; la página de invitación tiene evaluación web separada.
5. Revisar todos los criterios aplicables antes del congelado. Exigir ≥4,5:1 para texto normal propio, ≥7:1 en HC y ≥3:1 para gráficos esenciales, más los resultados del recorrido real. No afirmar AAA global ni publicar etiquetas de accesibilidad por pasar el cálculo.

### Interfaz y flujos abreviados: decisión del 25 de septiembre (#28)

Refinamiento acordado el 26: las filas pendientes muestran Editar/Quitar mediante swipe nativo desde trailing, con ayuda localizada y acciones accesibles del sistema. Se retiran los iconos permanentes, se desactiva full swipe y se conserva la confirmación estable de retirada. La comprobación se centra en gesto, editor, conservar producto y texto grande; la lógica y las pruebas de dominio no cambian.

El usuario autoriza [#28](https://github.com/JFrancoG/SmartShoppingList/issues/28): aplicar el sistema de diseño a Añadir, Comprar y Ajustes; mostrar el nombre real del grupo arriba; mover cuenta, invitaciones y cierre de sesión a Ajustes; usar iconos accesibles para micro/editar/quitar y cápsulas primary para acciones explícitas.

Refinamiento de Añadir acordado el 26: con Apple Intelligence disponible, el inicio muestra la pregunta y el micro centrados. Terminar el dictado interpreta automáticamente y presenta una propuesta con productos, cantidades y tiendas mediante Confirmar/Editar. Confirmar envía sólo ese lote; Editar, ausencia de productos, rechazo o error muestran texto, filas y entrada manual para recuperar el flujo. Reinterpretar sólo sustituye sugerencias intactas identificadas durante la sesión y conserva correcciones y otros borradores. La interpretación nunca envía por sí sola. Las tiendas exactas se resuelven sin otra revisión y la ambigüedad usa la elección existente. Persistencia, reintentos y confirmación del servidor siguen vigentes; el éxito conserva Ver lista/Cerrar aviso. El formulario manual envía sólo su producto, los dispositivos sin modelo priorizan esa entrada y Comprar conserva su consulta de tiendas por voz.

El 26 el usuario acepta el acabado visual observado y confirma el alta manual de una tienda nueva (Lidl) con su producto. Autoriza el atajo opcional «Ver lista» desde la confirmación de una sola tienda al comprobar que reutiliza la selección y carga de Comprar. Se usa el ID confirmado por el servidor y se conserva la posibilidad de cerrar y seguir añadiendo; no requiere otro endpoint ni una pantalla nueva. La prueba física del atajo se registra por separado.

Después confirma el funcionamiento de «Ver lista» y pide una jerarquía visual distinta para acción y cierre, los iconos de Cerrar a la izquierda y Refrescar a la derecha en Ajustes, contador centrado y «Confirmar compra · N» como acción única sin encabezado redundante. La ayuda inferior lleva un icono informativo. El límite de nombres pasa a 60 para productos y 40 para tiendas nuevas, con ayuda sólo ante exceso; este ajuste exige sincronizar validación iOS/servidor y preservar recibos históricos. Su activación alojada se documentará separadamente de la instalación visual.

La entrada universal por voz, el borrado/compra por órdenes y App Intents quedan fuera de esta unidad. El backend sólo cambia para sincronizar los nuevos límites de nombres, conservando los recibos anteriores; su despliegue queda identificado en la validación. La [validación de #28](validation/issue-28-shopping-ui.md) registra compilación, regresiones, previews e interacción física por separado. El siguiente paso tras integrar la UI es comprobar los recorridos cambiados y resolver defectos que bloqueen la entrega, reservando el resto del tiempo para documentación, demostración y congelado; no se amplía la funcionalidad por terminar antes el acabado visual.

El 26 queda aceptada la ronda focalizada de UI: recorridos físicos en iPhone 11 y 14, visibilidad de cambios al refrescar el otro dispositivo, errores por nombres demasiado largos y texto máximo en las pantallas probadas. Se suma la evidencia del iPad y la interpretación real con Apple Intelligence registrada en #28. Quedan pendientes el despliegue de los límites del servidor y la entrega Git de la rama; esta aceptación no cierra por sí sola la issue ni acredita el MVP completo. El intento opcional de App Intents #10 se valorará después de entregar esta unidad, según el margen restante.

### Alcance de comprobación de Comprar: decisión del 25 de septiembre

En [#17](https://github.com/JFrancoG/SmartShoppingList/issues/17), el usuario decide limitar las comprobaciones actuales a defectos concretos y recuperación funcional porque la UI cambiará al aplicar el design system. Se conserva la evidencia física en inglés del botón de compra a tamaño máximo, VoiceOver y pérdida/recuperación de conexión, junto con las pruebas de carga, vacío confirmado y error. La [validación del flujo](validation/issue-11-purchase-flow.md) detalla sus límites.

La matriz extensa ES/EN de tamaños, apariencias y foco/anuncios de éxito, conflicto y reintento se ejecutará sobre la UI integrada con el design system. El vacío confirmado cuenta ahora con prueba automatizada; su inspección física se incorpora a ese recorrido. Esta decisión limita el cierre de #17 a las correcciones y evidencia registradas; no acredita toda la accesibilidad ni cierra la fase 3 o el MVP.

### Iconos de la app: decisión del 24 de septiembre

[#16](https://github.com/JFrancoG/SmartShoppingList/issues/16) incorpora los archivos Icon Composer Brain y Check y los originales de `design/` aportados por el usuario. Brain es principal; Check se selecciona únicamente cuando Foundation Models informa hardware no compatible. iOS presenta un aviso nativo al cambiar de icono. La [evidencia](validation/issue-16-app-icons.md) distingue reglas probadas, bundles compilados y ensayo real. Esta entrega directa en `main`, autorizada por el usuario, incluye los ajustes recomendados de Xcode 27.2 y no cierra la fase ni integra los tokens de las pantallas.

### Comprobaciones de consolidación

La implementación bilingüe se concreta en [#13: localización ES/EN](https://github.com/JFrancoG/SmartShoppingList/issues/13), autorizada el 24 de septiembre en rama independiente sobre el recorrido de compra. Inglés es el idioma fuente; español conserva traducción completa. La [decisión técnica](architecture/ios-draft.md) conecta voz e IA con el idioma efectivo de la app; #7 conserva el ensayo real de ambos idiomas. Esta unidad no sustituye la integración visual ni los hallazgos de accesibilidad pendientes.

Las comprobaciones acompañan al desarrollo y se consolidan antes de congelar funcionalidades:

- Swift Testing para reglas y contratos críticos, sin pruebas que sólo reproduzcan la implementación; compilación sin warnings propios y únicamente con las [excepciones externas aceptadas](dependency-exceptions.md).
- Autorización por grupo e invitaciones caducadas, revocadas, consumidas o abiertas sin sesión.
- Altas concurrentes, lotes atómicos y reintentos sin duplicados. Finalizar tres de cinco pendientes compra sólo tres; las altas posteriores y los otros dos quedan intactos. Ediciones, compras o cancelaciones concurrentes no se sobrescriben ni generan doble compra.
- Checks sin escrituras, selección separada por tienda, conservación del borrador/selección ante errores y correcciones del usuario respetadas. Persistencia tras cierre/reapertura y reinicio del servidor.
- Micrófono/IA no disponibles, tiendas ambiguas, pérdida de red y reintento explícito; VoiceOver, texto grande y uso manual en la interfaz real.
- Conservar las comprobaciones físicas restantes de [consulta de tienda por voz #24](validation/issue-24-store-voice-query.md#remaining-physical-checks-for-phase-3): foco/anuncio con VoiceOver, scroll a tamaño máximo, ambigüedad, silencio e interrupciones. Los casos de coincidencia y ausencia de tienda ya confirmados no se repiten por registro. Las pruebas deterministas cubren las transiciones; no acreditan su ejecución física.
- Revisar la presentación de errores al confirmar un envío y de avisos de interpretación con borradores largos: el aviso debe percibirse desde la posición actual de la pantalla, sin obligar a hacer scroll hasta arriba o abajo y sin depender únicamente del color. El 22 de septiembre se confirmó que el aviso de interpretación queda oculto al final cuando ya hay varios productos. Hallazgo físico y aplazamiento acordado a esta fase en la [validación de #4](validation/issue-4-shared-flow.md#ensayo-físico-con-railway--21-de-septiembre-de-2026).
- Consolidar los estados de compra observados el 22 de septiembre en [#11](validation/issue-11-purchase-flow.md#ajustes-de-interfaz-registrados-para-fase-3): evitar los dos avisos repetidos ante falta de red, adaptar «sin duplicar productos» al tipo de operación y hacer perceptible el conflicto que aparece al final del formulario. Distinguir «No hay productos pendientes en esta tienda» tras una consulta vacía de una lista todavía no cargada o una consulta fallida. Revalidar con VoiceOver y scroll sin perder el envío recuperable.
- El 24 de septiembre se implementa en `codex/issue-7-speech-diagnostics` la presentación nativa de avisos del borrador/editor/grupo, almacenamiento y conflicto de selección. Se conserva el reintento pendiente y se evita competir con hojas en cierre. Tests técnicos superados; el usuario confirma en iPhone 14 lectura automática del error del editor y del permiso de micrófono, alerta del editor a tamaño máximo y recuperación del envío sin red con confirmación y sin duplicados. Evidencia y límites consolidados en la validación de localización/#7; no equivale a cerrar toda la matriz de accesibilidad. Los hallazgos de placeholder, retorno a la fila editada y estado vacío siguen separados.
- El reemplazo de avisos detectado durante esa validación se corrige aislando la identidad de cada presentación y sus callbacks. Ensayo en iPhone 17 simulado y confirmación del usuario: un segundo aviso pendiente se muestra al cerrar el primero, sin quedarse oculto. El fixture Debug no construye servicios reales; también permite verificar almacenamiento y ocultación/reactivación. La evidencia de texto máximo, IA inglesa con tiendas alternativas y límites de VoiceOver se conserva en [el informe de #7](validation/issue-13-localization.md).
- Comunicar automáticamente los errores de validación del editor a VoiceOver, mediante anuncio o foco apropiado y sin duplicaciones. Al pulsar Aplicar sin tienda, el ensayo del 22 de septiembre no anunció el error; solo pudo leerse al navegar hasta él. Conservar los datos y revalidar error/corrección en [#7](https://github.com/JFrancoG/SmartShoppingList/issues/7).
- Evitar que el ejemplo del campo de entrada se recorte con texto de accesibilidad al máximo: el ensayo del 22 de septiembre terminó el placeholder en «yo…» (yogures). Valorar un ejemplo más breve o ayuda multilínea; mantener una etiqueta accesible independiente. En la repetición del 24 de septiembre, el usuario confirma el ejemplo completo al tamaño máximo en inglés y español; el recorte no se reproduce y no se modifica el campo.
- Hallazgo distinto del 24 de septiembre: «Cantidad, opcional» se recorta al añadir manualmente. La primera etiqueta persistente superó lectura/edición con VoiceOver, pero generó demasiado espacio al volver a texto normal (captura 19:20:32). Se sustituye por el placeholder breve «Cantidad» / «Quantity»; el nombre accesible conserva «Cantidad, opcional» y el pie explica la opcionalidad. Previews EN/ES Large/XXX Large/AX5 y revisión independiente correctas. El usuario aprueba la opción compacta y confirma en iPhone 14 que se ve bien en todos los tamaños ensayados y VoiceOver anuncia «Cantidad, opcional». Ajuste incluido en la entrega de accesibilidad del editor de #7; el resultado remoto se registra en la issue.
- Restaurar el foco de VoiceOver al producto editado o a su acción Editar al cerrar el editor del borrador. El ensayo del 22 de septiembre desde Device Hub conectado al iPhone 14 devolvió el foco al encabezado Añadir, perdiendo la posición; registrar la revalidación en [#7](https://github.com/JFrancoG/SmartShoppingList/issues/7). El 24 de septiembre se reproduce de nuevo con Cancel y se implementa localmente la restauración al control Edit por UUID al terminar `onDismiss`; el usuario confirma después el retorno al Edit de origen con Cancel y Apply en iPhone 14.
- Ajustar la invitación pendiente cuando el usuario ya pertenece al grupo indicado: informar de esa pertenencia y permitir descartar el enlace, sin ofrecer una aceptación que el servidor rechazará. Evidencia y protección actual del servidor en la misma validación de #4.
- Completar localización español/inglés, requerida por el usuario el 21 de septiembre para el jurado bilingüe: interfaz, avisos, errores, permisos, accesibilidad y demostración. Revisar formatos y textos en inglés de Reino Unido/Estados Unidos y en español, conservando los datos introducidos por usuarios. Validar transcripción e interpretación en ambos idiomas por separado; traducir el catálogo no acredita voz ni IA. Objetivo de acabado: 24–25 de septiembre.

Las evidencias y limitaciones se enlazan desde las issues correspondientes, distinguiendo ejecución física, simulador, macOS y Linux.

## Fases 4 y 5: entrega reproducible y margen

El README debe permitir reproducir compilación, arranque, firma/capacidades, variables, servicios y recuperación de los datos persistentes, sin credenciales. La demostración con dos usuarios cubre invitación, alta, consulta, selección y finalización, conservando pendientes para otra visita. Se documentan voz/IA en el entorno acordado, el recorrido físico manual y los límites conocidos.

Una grabación breve puede servir de apoyo; no se trata como requisito publicado del evento ni sustituto del código funcional. Se confirma el canal y la hora de entrega, se comprueba el repositorio y se registra el envío efectivo. Que el repositorio ya sea público no acredita la entrega por el canal oficial.

Las propuestas posteriores al 27 permanecen en la sección de futuro de la spec. No se convierten en tareas de este MVP.
