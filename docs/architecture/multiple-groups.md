# Varios grupos y traspaso de administración

Fecha de decisión: 27 de septiembre de 2026.

Estado: **reglas funcionales aprobadas para después del MVP; diseño técnico pendiente**. El usuario acuerda documentarlas para retomarlas dentro de unos días, sin fijar fecha de inicio. Este documento no activa su implementación ni modifica el contrato vigente de la entrega del 27.

## Decisión aprobada

- Una persona puede pertenecer a varios grupos.
- Cada grupo activo tiene exactamente un administrador, que debe ser miembro del grupo.
- Una persona puede administrar ninguno, uno o varios de los grupos a los que pertenece. No se impone un máximo de un grupo administrado por cuenta.
- Los permisos se comprueban dentro de cada grupo: administrar uno no concede privilegios sobre los demás.
- Se conserva la distinción sencilla entre miembro y administrador. Esta ampliación no incorpora varios administradores simultáneos por grupo ni roles personalizados.
- Se separan el creador histórico del grupo y su administrador actual. Un traspaso cambia la responsabilidad, sin atribuir la creación a otra persona.

Ejemplo: una persona administra «Casa» y «Viaje» y participa como miembro en «Familia». Podrá recibir la administración de otro grupo al que ya pertenece, aunque ya administre los dos primeros.

Se descarta limitar la administración a un grupo por persona porque bloquearía ese traspaso y obligaría a ceder otro grupo previamente. Esa restricción acoplaría grupos independientes sin simplificar los permisos de cada uno.

## Traspaso de administración

1. El administrador actual propone como sucesor a otro miembro del mismo grupo.
2. El destinatario debe aceptar expresamente. Mientras no lo haga, el administrador actual conserva su responsabilidad y permisos.
3. Al aceptar, el servidor vuelve a comprobar la propuesta vigente, quién administra el grupo y que el destinatario sigue siendo miembro.
4. El cambio se confirma de forma atómica: el destinatario pasa a administrador y el anterior permanece como miembro. No hay un intervalo con dos administradores ni con ninguno.
5. Administrar otros grupos no impide recibir el traspaso. Las responsabilidades en esos otros grupos no cambian.
6. El administrador debe resolver el traspaso antes de abandonar un grupo que sigue activo. El caso del último miembro y el posible cierre del grupo requieren una política específica antes de implementarse.

Si la operación falla o su resultado es incierto, la interfaz no anuncia un traspaso completado. La propuesta, su aceptación y los reintentos deberán tener identidad y reglas de concurrencia verificables; el mecanismo concreto queda por diseñar.

## Punto de partida e impacto técnico

El MVP conserva [una cuenta con un único grupo y gestión reservada al creador](../contracts/mvp-api.md#grupo-e-invitaciones). La [arquitectura implementada](shared-shopping.md) y sus operaciones siguen siendo la referencia de la versión entregada.

La futura migración debe contemplar:

- **Persistencia y autorización:** sustituir la pertenencia singular `users.group_id` por pertenencias múltiples y separar la administración actual de `groups.creator_user_id`. Hoy este último campo es único por usuario; la migración deberá retirar esa restricción de producto sin perder al creador histórico. El esquema definitivo y las restricciones que garantizan un administrador miembro por grupo siguen pendientes.
- **Datos existentes:** cada pertenencia actual debe conservarse y cada creador pasar a ser el administrador inicial de su grupo, preservando identificadores, productos, tiendas, invitaciones e historial. Revisar compatibilidad entre versiones de app y API antes del despliegue.
- **Cliente iOS:** hacer inequívoco el grupo sobre el que se consulta o actúa y separar sus permisos, cargas, selecciones y estados de edición. Cambiar de grupo no puede aplicar una respuesta tardía ni una selección al destino nuevo.
- **Operaciones pendientes:** conservar cuenta y grupo de origen de cada mutación y reintento. Cambiar el grupo visible no puede redirigir una compra, edición o alta pendiente; la pertenencia y los permisos vigentes se comprueban también al reintentar.
- **Invitaciones y Siri:** aceptar un grupo adicional no debe expulsar al usuario de los anteriores. La resolución de tiendas y las acciones de Siri necesitan un grupo de destino inequívoco, especialmente si dos grupos tienen tiendas con el mismo nombre.

Estos puntos describen impactos que revisar, no endpoints, migraciones o capacidades ya implementados. Los documentos OpenAPI y de aceptación del MVP permanecen sin cambios por esta decisión.

## Decisiones pendientes antes de implementar

- Cómo elegir, mostrar y recordar el grupo activo; qué hacer al perder su pertenencia y cómo resolver el destino en Siri/Atajos. No asumir silenciosamente el último grupo usado para una orden ambigua.
- Duración, rechazo, retirada y sustitución de una propuesta de traspaso; número de propuestas pendientes permitidas y forma de comunicar su recepción.
- Qué sucede si el destinatario deja de ser miembro antes de aceptar, si cambia el administrador o si dos aceptaciones compiten. Todas las variantes deben conservar un único administrador autorizado.
- Efecto del traspaso sobre invitaciones ya emitidas y control de su consulta o revocación por el nuevo administrador.
- Salida del grupo, último miembro, cierre del grupo y eliminación de cuenta: resolver los grupos administrados sin dejar grupos activos sin responsable. Estas operaciones no se dan por diseñadas ni implementadas con este acuerdo.
- Relación del borrador local con el grupo de destino y recuperación de operaciones pendientes al cambiar de grupo o perder acceso.
- Contrato API, errores, migración y compatibilidad con clientes que todavía esperan un único grupo.

## Casos que deben validarse

| Caso | Resultado exigido |
|---|---|
| Una persona pertenece a tres grupos y administra dos | Accede como miembro al tercero y solo administra los dos que le corresponden. |
| El sucesor ya administra otro grupo | Puede aceptar el traspaso sin renunciar a su responsabilidad anterior. |
| El sucesor todavía no acepta | El administrador actual conserva la gestión y no puede abandonarla dejando el grupo sin responsable. |
| Traspaso aceptado | El sucesor administra; el anterior sigue como miembro; el creador histórico no cambia. |
| Solicitante sin permisos o destinatario ajeno al grupo | Se rechaza el traspaso sin modificar pertenencias ni administración. |
| Propuesta obsoleta, dos aceptaciones o reintento tras pérdida de respuesta | No se aplica una propuesta invalidada ni se generan administradores duplicados; el resultado confirmado se puede recuperar con seguridad. |
| Cambio de grupo durante una carga o con una mutación pendiente | Los datos y efectos permanecen vinculados a su grupo original; no se filtra información ni se redirige la operación. |
| Migración de los datos del MVP | Se conservan pertenencias, responsables iniciales, identificadores e historial. |
| Dos grupos con la misma tienda en una orden por Siri | Se resuelve o solicita el grupo antes de escribir; no se elige por coincidencia de tienda únicamente. |

La futura validación combinará Swift Testing para reglas, autorización y concurrencia; migración con datos representativos; y recorridos iOS en español e inglés con VoiceOver. Es una previsión de cobertura, no evidencia ejecutada.

## Cómo retomar el trabajo

Tras cerrar el MVP, revisar las decisiones pendientes y concretar el contrato y la migración. La secuencia propuesta es separar primero creador y administrador e incorporar el traspaso, y después ampliar pertenencias y selección de grupo, diseñando ambas partes sin imponer el límite de un grupo administrado.

Antes de implementar, consultar el estado real del repositorio y GitHub, reutilizar o abrir la unidad de trabajo correspondiente y acordar su plan. El [plan general](../implementation-plan.md#después-del-mvp-varios-grupos-y-traspaso) enlaza esta decisión; GitHub Issues seguirá siendo el único seguimiento operativo. Documentar este tema no inicia trabajo programado ni crea una fecha de entrega.
