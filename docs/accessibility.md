# Accesibilidad: requisitos y protocolo de aceptación

23 de septiembre de 2026 · iOS 27 · español e inglés · fase 3 del MVP.

El [sistema de diseño](design-system.md) define los componentes y colores. Este documento define cómo comprobarlos y cómo aplicar las recomendaciones Apple/W3C al recorrido real. **El protocolo está preparado, no ejecutado**; el [informe de contraste](validation/design-system-contrast.md) sólo valida colores opacos. Los hallazgos físicos anteriores conservan su evidencia y no se consideran resueltos por escribir estas reglas.

## Alcance y criterio de cierre

Evaluar acceso con Apple, crear/aceptar grupo, invitaciones válidas e inválidas, entrada manual y voz, interpretación, editor y revisión, incorporación de lote, selector de tienda, selección provisional, finalización y recuperación de red/conflictos. Incluir edición/cancelación conforme se implementen y la página web mínima de invitación. Esta última se evalúa como contenido web, sin atribuirle la evidencia nativa.

Base: [WCAG 2.2](https://www.w3.org/TR/WCAG22/) A/AA, interpretada para software nativo mediante [WCAG2ICT](https://www.w3.org/TR/wcag2ict-22/), más HIG actuales. El contraste de texto de los componentes propios se eleva a 7:1 en HC. Ni cumplir 1.4.6 en unos pares ni pasar Accessibility Inspector equivale a AAA global. Los detalles de versión y las guías complementarias están en [fuentes](research/design-system-sources.md).

No se cierra el acabado mientras haya un bloqueo de un flujo esencial con tecnología de asistencia, texto imprescindible inaccesible, contraste requerido fallido, foco perdido, controles inalcanzables o confirmaciones falsas. Cada caso pendiente necesita evidencia y resolución, o una decisión explícita sobre la entrega; no basta con una excepción genérica. El seguimiento sigue en GitHub Issues y en los informes del bloque correspondiente.

## Comportamiento exigido

### Lectura, voz y foco

Controles semánticos (`Button`, `Toggle`, `TextField`, selectores nativos); las acciones no dependen de un gesto personalizado. El nombre accesible incluye la etiqueta visible para funcionar con Control por voz. El valor comunica la selección provisional, la tienda y la cantidad cuando aportan contexto; no repetir «botón» en una etiqueta cuyo rol ya lo anuncia.

La fila de compra puede agrupar nombre/cantidad/tienda como información, pero no absorber las acciones de seleccionar y editar. Orden: encabezado de tienda, estado de consulta, productos, selección y confirmación según el layout real. Los iconos decorativos se omiten de la lectura. No fusionar un contenedor entero si oculta descendientes interactivos.

Al abrir un editor, foco lógico en título o campo inicial; al cerrarlo, restaurarlo al producto o a Editar. Al eliminarse una fila tras confirmación del servidor, moverlo al siguiente producto o al estado vacío, nunca dejarlo apuntando a un elemento inexistente. Un error al pulsar Aplicar se anuncia o recibe foco de forma deliberada, sin anuncios duplicados ni saltos continuos con cada carácter escrito.

La captura de voz muestra texto y control Detener; la alternativa manual está siempre disponible. Ni un haptic ni un sonido son la única confirmación. No introducir una locución propia que compita con VoiceOver. Los estados de interpretación, guardado y recuperación permanecen visibles el tiempo necesario; los mensajes esenciales no desaparecen en un toast temporizado.

### Texto, tamaño y movimiento

Dynamic Type hasta Accessibility 5 y Texto en negrita, con contenido al menos duplicable respecto al tamaño de referencia. Comprobar realmente crecimiento, reflujo y lectura; una preview grande no demuestra que todos los textos escalen. Respetar orientación, área segura, teclado y anchura disponible. En el MVP no hay contenido bidimensional que justifique obligar a scroll horizontal para leer formularios/listas.

Etiquetas persistentes, ayuda multilínea y CTA completo. Ningún error sólo en placeholder. Los nombres largos de productos y tiendas no se truncan de modo que impida distinguirlos; ofrecer presentación completa en el flujo normal. Las traducciones no se encajan reduciendo la fuente.

Controles de al menos 44×44 pt por decisión del proyecto, con separación y hit areas sin solapamiento. Deslizar, arrastrar, sacudir o hablar nunca son la única forma de editar, quitar, refrescar o consultar. Activar botones al completar la pulsación, permitiendo cancelarla. Sin flashes ni animaciones ornamentales repetitivas; respetar Reducir movimiento y Reducir transparencia por separado.

### Español, inglés y claridad

String Catalogs para interfaz, permisos, errores y accesibilidad, con pluralización de productos y comentarios de traducción. Usar formatos del locale para fechas/cantidades, no concatenar fragmentos traducidos. Los nombres aportados por las personas no se traducen. La política de datos del MVP no cambia.

Ejemplos de intención, no traducciones ya integradas:

| Español | Inglés |
|---|---|
| Seleccionado, pendiente de confirmar | Selected, not yet confirmed |
| Finalizar compra · 3 productos | Finish shopping · 3 items |
| No hay productos pendientes en esta tienda | No pending items in this store |
| No se ha podido confirmar la compra. Reintentar | Couldn’t confirm the purchase. Retry |

Verificar ES, inglés de Reino Unido/Estados Unidos y plural singular/cero. Revisar RTL mediante pseudolocalización/layout, sin añadir un idioma nuevo al MVP. El idioma de lectura de nombres aportados no se adivina. Traducir etiquetas no acredita soporte real de Speech ni de Foundation Models.

## Matriz de trazabilidad A/AA

Inventario de aplicabilidad para revisión, **no resultados de un audit completado**. Las agrupaciones cubren los criterios A/AA de WCAG 2.2; los que dependen de contenido inexistente requieren confirmar su ausencia en la versión final. Para nativo se aplican las salvedades de WCAG2ICT; para la página de invitación se evalúan directamente los criterios web. 4.1.1 Parsing se retiró de WCAG 2.2 y no se presenta como requisito vigente.

| Criterios | Aplicación / evidencia que se requiere |
|---|---|
| 1.1.1 | Símbolos con sentido accesible; adornos omitidos; icono no sustituye el nombre de una acción |
| 1.2.1, 1.2.2, 1.2.3, 1.2.4, 1.2.5 | Sin medios pregrabados ni emisión audiovisual en el flujo actual: confirmar N/A. El dictado del usuario tiene transcripción y alternativa manual. Si se incorpora un vídeo de ayuda, reabrir evaluación de alternativas/subtítulos |
| 1.3.1, 1.3.2, 1.3.3 | Secciones, etiquetas y orden semántico; «seleccionado» no se describe sólo como «el verde» o por su posición |
| 1.3.4 | Recorrido usable en orientaciones y tamaños admitidos; no imponer orientación sin necesidad esencial |
| 1.3.5 | Identificación de propósito de datos personales cuando proceda; actualmente acceso oficial con Apple, sin formulario propio de contraseña. Revisar campos finales y página web |
| 1.4.1 | Selección/éxito/aviso/error distinguibles sin color mediante forma, texto y rol |
| 1.4.2 | No audio automático propio; verificar que voz y alertas no introducen reproducción incontrolable |
| 1.4.3 | Contraste de todos los textos y estados; tabla nominal más medición renderizada |
| 1.4.4, 1.4.10 | Texto ampliado y reflujo sin pérdida de información, controles ni scroll horizontal de lectura |
| 1.4.5 | Texto real en UI, no rasterizado en imágenes; icono de marca separado del contenido funcional |
| 1.4.11 | Check, perímetro y estado esencial ≥3:1 frente al fondo adyacente; vidrio se mide aparte |
| 1.4.12 | Evaluar espaciado de texto según aplicabilidad WCAG2ICT al software nativo; el layout no recorta. En web permitir los ajustes WCAG sin pérdidas |
| 1.4.13 | Si hay contenido al hover/foco, poder percibirlo, descartarlo y mantenerlo; no instrucciones esenciales sólo en tooltip |
| 2.1.1, 2.1.2, 2.1.4 | Acceso total con teclado, sin trampas ni atajos de una letra que interfieran con escritura/tecnologías de asistencia |
| 2.2.1, 2.2.2 | No avisos esenciales temporizados ni movimiento automático sin control. Revisar caducidad de invitación/sesión y recuperación preservando borrador; no declarar excepción temporal sin justificarla |
| 2.3.1 | Sin destellos; revisar indicadores de escucha/progreso y cualquier animación incorporada |
| 2.4.1, 2.4.2, 2.4.5 | Encabezados y navegación consistente; título de pantalla/página e identificación del contexto. Revisar salvedades de software y navegación web |
| 2.4.3, 2.4.4, 2.4.6 | Orden de foco, destino de enlaces y nombres de secciones/acciones comprensibles |
| 2.4.7, 2.4.11 | Foco visible y no totalmente oculto por teclado/barras/mensajes; objetivo propio: completamente visible |
| 2.5.1, 2.5.2, 2.5.4, 2.5.7 | Alternativas a gestos complejos, cancelación de pulsación, movimiento y arrastre; usar controles nativos |
| 2.5.3 | Nombre accesible contiene el texto visible; comprobar Control por voz |
| 2.5.8 | Verificar objetivos táctiles y separación; política propia 44×44 pt, revisar web en CSS px |
| 3.1.1, 3.1.2 | Idioma de UI/lectura y partes localizadas correctos, HTML lang en invitación; nombres de usuario preservados |
| 3.2.1, 3.2.2 | Enfocar o cambiar selector no confirma ni cancela una compra ni consume invitación |
| 3.2.3, 3.2.4, 3.2.6 | Navegación, nombres y ubicación de ayuda consistentes; si no hay ayuda repetida, documentar N/A de 3.2.6 |
| 3.3.1, 3.3.2, 3.3.3 | Error identificable, etiqueta/instrucción y corrección posible; conservar datos tras error |
| 3.3.4 | Revisar antes de añadir lote o finalizar; corregir selección. Cancelación y datos persistentes exigen prevención acorde a su reversibilidad |
| 3.3.7 | No volver a pedir datos ya disponibles en el mismo proceso; conservar enlace pendiente y borrador tras autenticación |
| 3.3.8 | Acceso oficial con Apple sin prueba cognitiva propia; verificar flujo y recuperación reales con asistencia |
| 4.1.2, 4.1.3 | Nombre/rol/valor, estado de selección, progreso y mensajes expuestos al sistema de accesibilidad |

Criterios AAA concretos adoptados como mejora, sin declaración global: contraste normal ≥7:1 en HC (1.4.6) y reducción del movimiento no esencial activado por interacción (2.3.3). Los umbrales de área táctil se conservan como política iOS en sus propias unidades.

## Ejecución de la validación

### Matriz mínima de entornos

| Eje | Valores / cobertura |
|---|---|
| Apariencia | Light, Dark, Light + Aumentar contraste, Dark + Aumentar contraste |
| Texto | Predeterminado, mayor tamaño estándar, Accessibility 5; además Texto en negrita |
| Idioma | ES y EN en todas las pantallas; revisar formatos en en-GB y en-US |
| Material | Normal y Reducir transparencia; extremos del ajuste Liquid Glass de iOS 27 donde esté disponible |
| Movimiento | Normal y Reducir movimiento |
| Percepción | Diferenciar sin color, formas/bordes de botones, escala de grises como apoyo a revisión |
| Interacción | Táctil, VoiceOver, Control por voz, Control por botón y Acceso total con teclado |
| Tamaño | Menor anchura soportada, orientación horizontal, teclado visible y ventana redimensionada donde aplique |

Cobertura: capturar cada pantalla/estado crítico en las **24 combinaciones de apariencia × tres tamaños de texto × dos idiomas**. No implica 24 ensayos físicos de todo el flujo: usar previews/simulador para cobertura visual y confirmar los casos límite en dispositivo. Ejecutar además el flujo completo con VoiceOver en ES/EN, cuatro apariencias, y repetir a texto máximo con transparencia/movimiento reducidos. Las tecnologías alternativas recorren todas las acciones esenciales; incluir una combinación adversa HC + Accessibility 5 + teclado o VoiceOver. Documentar selección de muestra y cualquier hueco conforme a WCAG-EM 2.0.

Registrar dispositivo y build exactos de iOS, versión Xcode/SDK, commit, idioma, ajustes y datos de prueba. Usar dos cuentas para colaboración; el ensayo de color no sustituye los criterios funcionales de servidor, voz o IA. Capturas de previews, simulador y físico se identifican por separado.

### Casos de aceptación

| ID | Procedimiento | Resultado necesario |
|---|---|---|
| A01 | Abrir acceso/grupo e invitación, válida e inválida, con VoiceOver | Contexto, acciones y resultado comprensibles; sin consumir el enlace al previsualizar |
| A02 | Dictar o introducir varios productos; denegar micrófono y simular modelo no disponible | Estado visible/accesible y alternativa manual; sin pérdida de borrador |
| A03 | Revisión larga, error de interpretación o envío con scroll a mitad | Aviso perceptible desde la posición actual; anuncio pertinente una vez; acción alcanzable |
| A04 | Editar, dejar tienda vacía y aplicar; corregir y cerrar | Error anunciado o enfocado; datos intactos y retorno de foco a la fila editada |
| A05 | Texto máximo y ES/EN con producto/tienda largos | Ejemplo sin «yo…», etiquetas/errores/CTA completos y sin solapamientos |
| A06 | Marcar 3 de 5 productos; navegar y volver; finalizar | Valor provisional correcto, CTA cuenta 3, no éxito anticipado, pendientes restantes legibles |
| A07 | Perder red durante confirmación y recuperar/reintentar | Un aviso por problema, mensaje específico de compra, selección recuperable y foco estable |
| A08 | Otro miembro edita, cancela o compra un seleccionado | Conflicto perceptible sin buscarlo al fondo; no anuncia compra parcial ni duplica feedback |
| A09 | Consulta vacía, carga inicial y fallo de consulta | Tres estados diferentes; sólo la consulta correcta afirma «No hay pendientes» |
| A10 | Cuatro apariencias y ajustes de materiales con scroll | Texto/contornos visibles contra el fondo real; ningún ratio se hereda de un HEX sin medir composición |
| A11 | Teclado, Control por botón y Control por voz | Todas las acciones accesibles, foco visible sin trampas, ninguna depende sólo de swipe/voz |
| A12 | Reducir movimiento, formas de botones y diferenciar sin color | Sin animación espacial no esencial; selección/error/acciones distinguibles sin matiz |
| A13 | Abrir enlace web de invitación sin app | Título, idioma, texto, enlace y reflujo accesibles en Safari; evaluación web separada |

Acciones del ensayo: usar Accessibility Inspector para inspeccionar etiquetas/traits, contraste y problemas detectables; medir pares renderizados con muestras del foreground/fondo reales; revisar tamaño hit-test y clipping. Conservar capturas y resultados, sin usar un pixel antialiasado aislado como sustituto de los colores de texto. Completar manualmente recorrido y escucha; las herramientas no prueban por sí solas el orden o la claridad de una operación.

### Hallazgos que deben revalidarse

Se mantienen los pendientes ya recogidos en el [plan de fase 3](implementation-plan.md#fase-3-validar-y-corregir): aviso oculto de interpretación, avisos de red duplicados, copy de reintento genérico, conflicto fuera de vista, validación del editor sin anuncio, placeholder recortado y retorno de foco al encabezado. Fuentes: [borrador/#7](validation/issue-3-ios-draft.md), [recorrido compartido](validation/issue-4-shared-flow.md) y [compra](validation/issue-11-purchase-flow.md). Este documento no vuelve a marcar como validados esos casos ni cambia el estado de las issues.

### Registro de evidencia

Añadir resultados al informe de validación del bloque/issue correspondiente con este esquema; no crear una segunda lista operativa aquí:

```text
Caso / criterio / pantalla:
Fecha, persona revisora, commit:
Dispositivo o simulador, iOS/build, Xcode/SDK:
Idioma, apariencia, contraste, texto y preferencias:
Datos / pasos / esperado / observado:
Resultado: pasa | falla | pendiente | no aplica (motivo)
Captura o grabación / medición de contraste / incidencia:
Limitaciones y revalidación necesaria:
```

No publicar claims de accesibilidad ni etiquetas de App Store a partir únicamente de un ratio, una captura o una compilación. El cierre exige revisar todos los criterios aplicables y el recorrido completo de la versión entregada.
