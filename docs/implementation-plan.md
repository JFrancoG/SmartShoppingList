# Plan de implementación

Fecha de creación: 18 de septiembre de 2026. Última revisión: 19 de septiembre de 2026.

Especificación de referencia: [MVP aprobado](mvp-spec.md). Este documento conserva las fases, dependencias y condiciones para avanzar; no amplía el contrato funcional ni registra el progreso de cada tarea.

## Organización y seguimiento

Una persona desarrolla con ayuda de Codex, con jornadas disponibles de 4–8 horas. La planificación no depende de disponer siempre de ocho horas ni trata la generación de código como sustituto de las comprobaciones reales.

| Lugar | Responsabilidad |
|---|---|
| [Especificación](mvp-spec.md) | Alcance aprobado, reglas funcionales y criterios de aceptación |
| [Contrato técnico](contracts/mvp-api.md) | Tipos y operaciones compartidos, integridad, sesiones, invitaciones y conflictos; ejemplos verificables |
| Este plan | Fases, ventanas objetivo, dependencias y resultados esperados |
| [GitHub Issues](https://github.com/JFrancoG/SmartShoppingList/issues) | Plan de cada bloque, situación, bloqueos, decisiones de ejecución y evidencia de cierre |

GitHub Issues es el único seguimiento operativo. El [hito «MVP · 27 septiembre»](https://github.com/JFrancoG/SmartShoppingList/milestone/1) agrupa el trabajo de la entrega. Su fecha es un objetivo de planificación; el canal y la hora oficial de entrega deben confirmarse. El porcentaje del hito sólo representa las issues creadas, no todo el alcance del MVP.

Se detallan las unidades del bloque inmediato. Las fases posteriores permanecen aquí hasta que corresponda concretarlas en issues. No se crean tareas por conversación, archivo o commit, ni issues retrospectivas para trabajos ya entregados. Tampoco se mantiene una segunda lista de estados en un archivo de progreso.

Cada issue contiene resultado, fuentes, alcance, plan vigente identificado como Draft o Approved, dependencias, criterios de aceptación y validación prevista. Su descripción identifica si está pendiente, en curso o bloqueada; crearla no significa empezar la implementación. Al cambiar materialmente el plan se actualiza la descripción y se añade un comentario fechado con la decisión, su motivo y evidencia. Las decisiones duraderas se reflejan en la spec o en el documento técnico correspondiente.

La evidencia se registra en la issue con fecha, entorno, resultados y referencia al commit o PR. Los informes extensos pueden guardarse en archivos enlazados. Una issue se cierra cuando cumple sus criterios, se valida y sus cambios están entregados en `main`; compilar pruebas, abrir una PR o escribir un plan no equivale a completar el trabajo.

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
- Checks locales reversibles, contador y finalización con IDs explícitos: mantener pendientes los no seleccionados, conservar selección ante errores y resolver conflictos sin duplicar compras.
- Historial mínimo por entrada y nueva entrada para una nueva necesidad; estados de carga, vacío y error, refresco y consulta de la última lista recuperada.
- Preparar las nuevas pantallas para español e inglés y adaptar la selección de idioma de Speech/Foundation Models, evitando el español fijo del recorrido inicial. Comprobar disponibilidad real por idioma con #7; la traducción y revisión completas se consolidan en fase 3.

Las issues de esta fase se concretan al cerrar las incertidumbres iniciales, con dependencias y criterios de aceptación propios.

### Extra opcional después del recorrido de compra: Siri

El 22 de septiembre el usuario decidió planificar [#10: entrada al borrador con Siri y App Intents](https://github.com/JFrancoG/SmartShoppingList/issues/10) después de completar el recorrido de compra. La primera acción recibirá producto, tienda y cantidad opcional para añadir una entrada al borrador local, conservando los datos existentes y la revisión posterior. Se preparará para español e inglés y se validará con Siri/Atajos reales. La frase exacta de invocación y la ejecución con app cerrada necesitan validación; no se acreditan por habilitar Siri AI. Es un extra planificado, todavía no implementado, que no sustituye los criterios pendientes del MVP ni bloquea el cierre de #4/#7. Antes de iniciarlo se revisará el margen de entrega.

## Fase 3: validar y corregir

Las comprobaciones acompañan al desarrollo y se consolidan antes de congelar funcionalidades:

- Swift Testing para reglas y contratos críticos, sin pruebas que sólo reproduzcan la implementación; compilación sin warnings propios y únicamente con las [excepciones externas aceptadas](dependency-exceptions.md).
- Autorización por grupo e invitaciones caducadas, revocadas, consumidas o abiertas sin sesión.
- Altas concurrentes, lotes atómicos y reintentos sin duplicados. Finalizar tres de cinco pendientes compra sólo tres; las altas posteriores y los otros dos quedan intactos. Ediciones, compras o cancelaciones concurrentes no se sobrescriben ni generan doble compra.
- Checks sin escrituras, selección separada por tienda, conservación del borrador/selección ante errores y correcciones del usuario respetadas. Persistencia tras cierre/reapertura y reinicio del servidor.
- Micrófono/IA no disponibles, tiendas ambiguas, pérdida de red y reintento explícito; VoiceOver, texto grande y uso manual en la interfaz real.
- Revisar la presentación de errores al confirmar un envío y de avisos de interpretación con borradores largos: el aviso debe percibirse desde la posición actual de la pantalla, sin obligar a hacer scroll hasta arriba o abajo y sin depender únicamente del color. El 22 de septiembre se confirmó que el aviso de interpretación queda oculto al final cuando ya hay varios productos. Hallazgo físico y aplazamiento acordado a esta fase en la [validación de #4](validation/issue-4-shared-flow.md#ensayo-físico-con-railway--21-de-septiembre-de-2026).
- Comunicar automáticamente los errores de validación del editor a VoiceOver, mediante anuncio o foco apropiado y sin duplicaciones. Al pulsar Aplicar sin tienda, el ensayo del 22 de septiembre no anunció el error; solo pudo leerse al navegar hasta él. Conservar los datos y revalidar error/corrección en [#7](https://github.com/JFrancoG/SmartShoppingList/issues/7).
- Evitar que el ejemplo del campo de entrada se recorte con texto de accesibilidad al máximo: el ensayo del 22 de septiembre terminó el placeholder en «yo…» (yogures). Valorar un ejemplo más breve o ayuda multilínea; mantener una etiqueta accesible independiente.
- Restaurar el foco de VoiceOver al producto editado o a su acción Editar al cerrar el editor del borrador. El ensayo del 22 de septiembre desde Device Hub conectado al iPhone 14 devolvió el foco al encabezado Añadir, perdiendo la posición; registrar la revalidación en [#7](https://github.com/JFrancoG/SmartShoppingList/issues/7).
- Ajustar la invitación pendiente cuando el usuario ya pertenece al grupo indicado: informar de esa pertenencia y permitir descartar el enlace, sin ofrecer una aceptación que el servidor rechazará. Evidencia y protección actual del servidor en la misma validación de #4.
- Completar localización español/inglés, requerida por el usuario el 21 de septiembre para el jurado bilingüe: interfaz, avisos, errores, permisos, accesibilidad y demostración. Revisar formatos y textos en inglés de Reino Unido/Estados Unidos y en español, conservando los datos introducidos por usuarios. Validar transcripción e interpretación en ambos idiomas por separado; traducir el catálogo no acredita voz ni IA. Objetivo de acabado: 24–25 de septiembre.

Las evidencias y limitaciones se enlazan desde las issues correspondientes, distinguiendo ejecución física, simulador, macOS y Linux.

## Fases 4 y 5: entrega reproducible y margen

El README debe permitir reproducir compilación, arranque, firma/capacidades, variables, servicios y recuperación de los datos persistentes, sin credenciales. La demostración con dos usuarios cubre invitación, alta, consulta, selección y finalización, conservando pendientes para otra visita. Se documentan voz/IA en el entorno acordado, el recorrido físico manual y los límites conocidos.

Una grabación breve puede servir de apoyo; no se trata como requisito publicado del evento ni sustituto del código funcional. Se confirma el canal y la hora de entrega, se comprueba el repositorio y se registra el envío efectivo. Que el repositorio ya sea público no acredita la entrega por el canal oficial.

Las propuestas posteriores al 27 permanecen en la sección de futuro de la spec. No se convierten en tareas de este MVP.
