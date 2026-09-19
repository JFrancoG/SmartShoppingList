# Plan de implementación

Fecha de creación: 18 de septiembre de 2026. Última revisión: 19 de septiembre de 2026.

Especificación de referencia: [MVP aprobado](mvp-spec.md). Este documento organiza la ejecución; no amplía el contrato funcional.

## Estado actual

- [x] Elegir SmartShoppingList como proyecto del MVP.
- [x] Cerrar el alcance funcional con el usuario.
- [x] Elegir inicio de sesión con Apple e invitación mediante enlace compartido.
- [x] Persistir la especificación y este plan.
- [x] Incorporar a la especificación checks provisionales y confirmación al finalizar; mantener pendientes los no seleccionados.
- [x] Fijar iOS 27 con confirmación del usuario sobre la autorización de los organizadores; preferir Vapor 5 con alternativa Vapor 4.
- [x] Crear las plantillas de iOS y Vapor y comprobar la compilación macOS del servidor y sus targets de pruebas con Swift 6.4.
- [x] Preparar archivos de versionado y [guía de Git](git-setup.md) para un repositorio común en la raíz.
- [ ] Confirmar entorno, dispositivos y configuración de servicios.
- [ ] Preparar repositorio y proyectos ejecutables.
- [ ] Implementar y validar los recorridos técnicos iniciales.

Existen las plantillas de iOS y Vapor, todavía con la pantalla inicial y el ejemplo `Todo`. Se ha comprobado Xcode 27, SDK iOS 27 y Swift 6.4. `swift build --build-tests --force-resolved-versions` compila el servidor y sus targets de pruebas en macOS sin warnings ni errores reportados; no ejecuta los tests ni valida PostgreSQL, Linux o los recorridos del MVP.

La inicialización de Git y el primer commit quedan para ejecución manual siguiendo la guía. No se ha contratado Railway, desplegado servicios, creado un repositorio remoto, activado un tracker ni ejecutado validación funcional.

## Organización

Una persona desarrolla con ayuda de Codex, con jornadas disponibles de 4–8 horas. La planificación no depende de disponer siempre de ocho horas ni trata la generación de código como sustituto de las comprobaciones reales.

Se mantiene un único alcance, descrito en la spec, y una sola lista operativa de trabajo. La elección de tracker se resolverá al preparar el repositorio; no se introducirán simultáneamente GitHub Issues y Linear ni se crearán tareas externas por cada conversación.

## Fases y resultados

| Fase | Ventana objetivo | Resultado verificable |
|---|---|---|
| 0. Definición | 18–19 septiembre | Spec aprobada y requisitos técnicos de arranque identificados |
| 1. Preparación y pruebas iniciales | 19–20 septiembre | Interpretación por voz en dispositivo y colaboración mínima desplegada por HTTPS |
| 2. Recorrido funcional | 21–23 septiembre | Las dos pestañas completan los flujos del grupo y las compras |
| 3. Validación y acabado | 24–25 septiembre | Casos de error, concurrencia, accesibilidad y persistencia comprobados |
| 4. Preparación de entrega | 26 septiembre | Código congelado, instrucciones verificadas y demostración reproducible |
| 5. Margen y entrega | 27 septiembre | Incidencias de cierre resueltas y repositorio entregado por el canal oficial |

Estas fechas son objetivos, no evidencia de trabajo realizado. Las pruebas acompañan a la implementación desde la fase 1. Se congelan funcionalidades al finalizar el 25; el 27 no se reserva para añadir nada nuevo.

## Fase 0: cierre técnico breve

- [ ] Identificar iPhone de demo con iOS 27, disponibilidad de Apple Intelligence y segundo cliente compatible para colaboración.
- [ ] Verificar acceso a la configuración necesaria de Sign in with Apple y enlaces universales.
- [ ] Comprobar Xcode/SDK para iOS 27 y el toolchain necesario para el servidor. Elegir el perfil de desarrollo con evidencia del entorno real; no dar por instalada una herramienta por haber aprobado el objetivo.
- [ ] Evaluar Vapor 5 durante un bloque de hasta cuatro horas: resolución de dependencias, arranque, PostgreSQL/transacciones, verificación de identidad Apple y compilación del contenedor Linux. Fijar versión exacta si pasa; usar Vapor 4 si aparecen bloqueos que exceden ese bloque, sin abrir una tarea de mantenimiento del framework.
- [ ] Concretar esquema mínimo, contrato de API y pertenencia al grupo.
- [ ] Fijar caducidad y revocación de invitaciones, sesión segura y contrato de finalización con IDs explícitos, transacción, reintentos y conflictos concurrentes.
- [ ] Elegir límites razonables de entrada y tratamiento de tiendas ambiguas a partir de ejemplos reales.
- [ ] Preparar repositorio y organización de trabajo siguiendo las instrucciones que se establezcan para él.

### Evidencia para elegir Vapor

Comprobación documental del 19 de septiembre; todavía no es evidencia de compilación o despliegue:

- La versión candidata es [Vapor 5.0.0-beta.2](https://github.com/vapor/vapor/releases/tag/5.0.0-beta.2), publicada el 16 de septiembre. Corrige un problema de resolución de dependencias de la beta anterior. Su [manifiesto](https://github.com/vapor/vapor/blob/5.0.0-beta.2/Package.swift) exige Swift 6.4.
- La [plantilla oficial para Vapor 5](https://github.com/vapor/template/blob/1bda1eb08dfeec76ffa6d7078c5d95c7134628ca/Package.swift) integra FluentKit y el driver de base de datos directamente. No se trasladará automáticamente la configuración de paquetes de Vapor 4.
- El [paquete vapor/jwt 5.1.2](https://github.com/vapor/jwt/blob/5.1.2/Package.swift) todavía depende de Vapor 4. Para Vapor 5 se evaluará JWTKit directamente y se verificará la integración de Sign in with Apple; compartir el número mayor de versión no acredita compatibilidad.
- Existe un [Dockerfile oficial de referencia](https://github.com/vapor/template/blob/1bda1eb08dfeec76ffa6d7078c5d95c7134628ca/Dockerfile). Compilar y ejecutar nuestra combinación concreta en Linux sigue pendiente; no se da por compatible sólo por existir la plantilla.

El bloque inicial limita el tiempo dedicado a resolver estas incertidumbres. Si se activa la alternativa Vapor 4, el objetivo iOS 27 y el alcance funcional permanecen iguales. Se registrará la versión finalmente probada y fijada, sin actualizar betas durante el cierre de la entrega.

## Fase 1: demostrar lo incierto

### Recorrido A: voz y revisión

- [ ] Capturar una frase en español en el dispositivo real.
- [ ] Transcribirla y generar productos/tienda mediante Foundation Models.
- [ ] Revisar y corregir el borrador, sin guardado compartido previo.
- [ ] Comprobar nombres de tiendas, cantidades, variantes de productos y datos ausentes.
- [ ] Verificar entrada manual cuando no están disponibles micrófono o IA.
- [ ] Registrar resultados y tiempos observados; no atribuir al dispositivo mediciones obtenidas sólo en simulador.

### Recorrido B: identidad, invitación y datos compartidos

- [ ] Ejecutar Vapor y persistencia localmente.
- [ ] Validar identidad Apple y crear grupo para el primer usuario.
- [ ] Crear enlace, conservarlo durante autenticación y aceptar la invitación con el segundo usuario.
- [ ] Incorporar y consultar un producto desde ambos clientes.
- [ ] Desplegar la prueba en Railway y repetirla por HTTPS.
- [ ] Comprobar persistencia después de reiniciar el servidor.

Railway se contrata/configura cuando existe un backend mínimo listo para desplegar. Se acuerda el presupuesto antes de contratar y se configuran alertas; un límite estricto de gasto puede detener los servicios. No es necesario contratar alojamiento para la definición ni para el desarrollo local.

**Punto de decisión al finalizar el segundo día técnico:** ambos recorridos deben estar demostrados. Si fallan, se informa con evidencia y se acuerda la corrección o reducción necesaria. No se oculta el problema desarrollando pantallas alrededor ni se retira una funcionalidad aprobada unilateralmente.

## Fase 2: completar el MVP

- [ ] Completar onboarding, sesión conservada e invitaciones válidas/inválidas/revocadas.
- [ ] Integrar guardado del lote confirmado, transacción e identificador de reintento.
- [ ] Consultar tiendas por voz y selector, con datos reales del grupo.
- [ ] Editar pendientes y diferenciar compra de cancelación.
- [ ] Implementar checks locales reversibles, contador y «Finalizar compra» para confirmar sólo los productos seleccionados.
- [ ] Mantener pendientes los no seleccionados; conservar la selección ante error y evitar duplicados en reintentos.
- [ ] Conservar historial por entrada y tratar correctamente nuevas compras del mismo producto.
- [ ] Incorporar carga, vacío, error, refresco y consulta de última lista recuperada.

## Fase 3: validar y corregir

Comprobaciones centradas en comportamiento:

- [ ] Swift Testing para reglas y contratos críticos; sin pruebas que sólo reproduzcan la implementación.
- [ ] Accesos sin pertenencia e invitaciones caducadas, revocadas, consumidas o abiertas sin sesión.
- [ ] Dos altas simultáneas conservadas, un envío reintentado sin duplicados y dos finalizaciones sobre el mismo artículo sin doble compra.
- [ ] Marcar/desmarcar no escribe en el servidor. Finalizar tres de cinco pendientes registra tres compras y conserva los otros dos.
- [ ] Las altas posteriores de otros miembros quedan intactas. Los conflictos con productos editados, comprados o cancelados durante la selección se presentan sin sobrescribirlos.
- [ ] Cambiar de tienda no mezcla selecciones; una finalización fallida conserva los checks y permite un reintento seguro.
- [ ] Guardado atómico, correcciones respetadas y conservación del borrador ante error.
- [ ] Persistencia tras cierre/reapertura y reinicio del servidor.
- [ ] Micrófono/IA no disponibles, tienda ambigua, pérdida de red y recuperación mediante reintento explícito.
- [ ] VoiceOver, texto grande y uso manual de los controles principales en la interfaz real.
- [ ] Compilación sin warnings y revisión del código conforme al alcance aprobado.

La evidencia se añadirá a este plan o a un registro enlazado cuando se ejecute. Ninguna casilla pendiente equivale a un resultado satisfactorio.

## Fase 4: hacer la entrega reproducible

- [ ] README con requisitos, ejecución, firma/capacidades, variables y servicios; sin credenciales.
- [ ] Reproducir la compilación y arranque a partir de las instrucciones.
- [ ] Verificar la configuración y recuperación de los datos persistentes.
- [ ] Ensayar con dos usuarios el recorrido de invitación, alta por voz, consulta, selección y finalización de compra, dejando productos pendientes para la siguiente visita.
- [ ] Preparar una grabación breve de apoyo si resulta útil; no tratarla como requisito publicado del evento ni sustituto del código funcional.
- [ ] Documentar límites conocidos y diferenciar funcionamiento real de ejemplos o datos de demostración.
- [ ] Confirmar canal de entrega y hora con margen; verificar el repositorio antes de enviarlo.

Publicar el repositorio y enviar su enlace son acciones de entrega, no realizadas por escribir este plan.

## Siguiente trabajo

Confirmar los requisitos materiales del arranque y diseñar el contrato mínimo de identidad, grupo, invitación y productos. A continuación, preparar los proyectos y ejecutar los dos recorridos de la fase 1.

Las propuestas posteriores a la entrega permanecen en la sección de futuro de la spec. No se convierten en tareas de este plan.
