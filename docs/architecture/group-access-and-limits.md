# Acceso a grupos y límites comerciales

Fecha: 9 de octubre de 2026.

Estado: **decisiones funcionales y plan aprobados el 9 de octubre; implementación autorizada**. El usuario confirma premium solo para grupos adicionales, límites ampliables de tiendas y productos pendientes, y capacidad compartida según el plan del administrador. Autoriza publicar este plan antes de implementar la primera unidad. Los detalles de contrato y migración se concretan durante esa unidad; este documento no acredita código, migraciones, cobros ni restricciones desplegadas.

Esta ampliación complementa la [decisión del 27 de septiembre](multiple-groups.md). Su ausencia de un máximo estructural de grupos administrados se conserva; el acceso efectivo sí podrá limitarse según el plan. La [issue #33](https://github.com/JFrancoG/SmartShoppingList/issues/33) contiene el plan operativo de la primera unidad. El [contrato del MVP](../contracts/mvp-api.md) sigue describiendo la API entregada.

## Contexto y decisiones aprobadas

El modelo debe admitir varios grupos por persona y exactamente un administrador miembro por grupo, separando al creador histórico del responsable actual. La pertenencia, la administración y el derecho comercial son conceptos distintos: perder una compra o suscripción no borra automáticamente miembros, responsables ni contenido.

| Dimensión comercial | Ámbito | Regla acordada |
|---|---|---|
| Grupos | Cuenta | Un grupo gratuito, administrado o como miembro; premium permite grupos adicionales. Cupo premium pendiente. |
| Tiendas | Grupo | Límite configurable, ampliable mediante premium; cifras pendientes. |
| Productos pendientes | Tienda | Límite configurable, ampliable mediante premium; cifras pendientes. Comprados y cancelados quedan fuera. |

Administrar un grupo ya incluido entre las pertenencias no consume otro grupo ni exige un pago adicional. El traspaso conserva la aceptación explícita del sucesor y no debe convertirse en una compra obligatoria para aceptar, ceder o salir conforme a las reglas del grupo. Restringir el uso ordinario de un grupo conserva su administrador y el acceso necesario para resolver esas responsabilidades.

Los productos se cuentan como **entradas pendientes con identidad propia**. Una entrada con cantidad «6 botellas» cuenta una vez; dos entradas iguales con IDs distintos cuentan dos veces. No se introduce catálogo ni deduplicación por nombre. Comprar o cancelar libera capacidad sin borrar el historial; editar nombre o cantidad en la misma tienda no la consume. Mover una entrada afecta a la capacidad del destino y libera la del origen al confirmar la operación.

El borrador local no consume cuota compartida antes de enviarse. Los límites técnicos vigentes de 50 entradas por operación, 100 por página y 128 KiB por petición son independientes del plan comercial.

## Decisión: capacidad compartida según el administrador

**Aprobada por el propietario el 9 de octubre.** El plan personal del administrador actual determina los límites de tiendas y productos del grupo y todos los miembros comparten esa capacidad. Cada persona mantiene su propio límite de pertenencias, con independencia del plan de los administradores de los grupos a los que accede.

Ejemplo: quien administra «Casa» tiene premium y amplía su capacidad para todos. Un familiar con plan gratuito puede usarla si «Casa» es su único grupo habilitado. Que otro miembro tenga premium no amplía por sí solo el grupo. El plan del administrador tampoco concede pertenencias adicionales gratuitas a los demás miembros.

Esta opción ofrece reglas iguales a todos los colaboradores y evita introducir de entrada una suscripción por grupo. Su coste es que una bajada de plan o un traspaso puede reducir la capacidad de otras personas; la interfaz debe mostrar la consecuencia antes de aceptar el cambio. La compra personal permanece vinculada a su titular: traspasar la administración no transfiere el pago ni la suscripción.

Alternativas descartadas para esta iteración: un plan propio del grupo separa facturación y administración, pero añade titular de pago y ciclo de facturación independientes; usar el plan de quien añade el contenido hace que dos miembros tengan reglas diferentes sobre la misma lista. El cálculo de capacidad efectiva queda en una política pequeña para poder cambiar su origen sin rehacer las pertenencias.

## Propuesta de aplicación y conservación

- El servidor calcula capacidades efectivas a partir de pertenencia, rol, plan y recurso. iOS presenta acciones disponibles, uso, límite y motivo de restricción; no deduce permisos repartiendo condiciones de `isPremium` por las vistas. Las capacidades consultadas son informativas: la escritura vuelve a comprobarlas.
- Configurar el despliegue de la funcionalidad, configurar sus cupos y verificar un derecho de compra son responsabilidades distintas. Los valores de prueba no conceden premium en producción. Se puede preparar esta frontera antes de conectar los pagos, sin publicar aún un acceso premium funcional.
- Crear o aceptar otro grupo consume capacidad de la cuenta; un traspaso entre miembros existentes no añade pertenencias. Las restricciones comerciales no sustituyen la autorización ni habilitan acceso a un grupo ajeno.
- Las tiendas se crean también al enviar un lote o mover un producto. Deben contarse únicamente tiendas realmente nuevas tras la normalización, reutilizando las existentes. Propuesta: una tienda vacía sigue contando mientras exista. Antes de activar ese cupo debe definirse una forma segura de liberar capacidad; el MVP no ofrece borrado ni archivo de tiendas.
- Las admisiones comprueban el efecto completo de la operación dentro de la transacción. Un lote que excede cualquier cupo se rechaza entero, sin productos parciales ni tiendas huérfanas. Dividirlo no permite eludir el cupo acumulado.
- Como punto de partida técnico, coordinar las mutaciones por cuenta para pertenencias y por grupo para los recursos compartidos, con conteos SQL y orden uniforme de bloqueos. El bloqueo actual por usuario no basta ante dos miembros distintos. No se propone añadir contadores persistidos ni un motor genérico de reglas; el protocolo exacto se concretará con las migraciones y pruebas. Los [bloqueos de filas de PostgreSQL](https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-ROWS) ofrecen el mecanismo, pero todas las operaciones implicadas deben participar en el mismo protocolo.
- Un éxito confirmado conserva su recibo aunque después cambie el plan: recuperarlo no consume otro cupo ni vuelve a decidir su admisión comercial. Se mantiene la autorización vigente. Una respuesta incierta conserva cuenta, grupo, ruta, payload y `operationId` originales.
- El contrato debe distinguir rechazo de cuota confirmado de falta de permisos, rate limit y resultado incierto. El rechazo no pierde el borrador. Queda por fijar si se conserva un recibo de rechazo: si se conserva, liberar capacidad no modifica ese resultado y se necesita una nueva intención explícita. No cambiar la clave de una petición cuyo resultado siga siendo incierto.

### Pérdida de capacidad

**Propuesta pendiente de concretar antes de activar restricciones.** Si el acceso premium termina, se revoca o cambia el administrador, conservar datos, pertenencias y responsable. El exceso es un estado recuperable, no una orden de borrar.

Para tiendas y productos, bloquear el crecimiento del recurso que exceda su límite, permitiendo consultar, completar compras, cancelar y editar sin aumentar el uso, dentro de los grupos a los que se conserva acceso. Mover una entrada exige capacidad en el destino. Como el plan depende del administrador, aceptar un traspaso a alguien con menor capacidad sigue siendo posible y deja el grupo en este mismo estado de exceso.

Para varias pertenencias, proponer la elección explícita de un grupo con uso gratuito completo y acceso restringido a los adicionales. Deben cerrarse el plazo, los derechos restantes y las reglas para cambiar esa elección, evitando convertir el selector en una forma de usar todos los grupos gratuitamente. Bloquear solo nuevas incorporaciones no resuelve este caso.

Consultar y resolver las responsabilidades necesarias para traspasar o abandonar seguirá siendo posible en un grupo restringido. Cerrar un grupo cuando sale su último miembro y eliminar una cuenta necesitan una política de conservación y de acceso a su historial. No se activa el cobro antes de resolver estos recorridos. Precio, pago único o suscripción, períodos de gracia y cifras comerciales siguen sin decidirse.

## Secuencia y fronteras

1. **Primera unidad, #33:** cerrar contrato y migración; separar creador y administrador; propuesta/aceptación de traspaso y salida/cierre seguros; preparar la frontera de capacidades del servidor y su representación iOS. El contrato debe prever las tres dimensiones, sin implementar todas las cuotas dentro de esta unidad.
2. **Pertenencias múltiples:** migrar las pertenencias, creación e invitaciones adicionales, selector y aislamiento de datos/operaciones/borrador/Siri. Aplicar el límite de grupos por cuenta con política de acceso definida.
3. **Cupos de tiendas y productos:** implementar admisiones, recuperación del exceso y liberación de capacidad, con las cifras y reglas ya acordadas. No confundir preparar su diseño ahora con restringir los datos existentes.
4. **Pagos:** integrar compras verificadas y su ciclo de vida; después activar la oferta comercial. La [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi) proporciona información firmada de transacciones; la app no decide por sí sola el derecho del servidor.

Se conserva la arquitectura iOS existente, Swift 6 con concurrencia estricta, SwiftUI y Swift Testing. No se añaden dependencias, se cambia de persistencia ni se eleva la plataforma mínima por preparar estas capacidades.

## Validación prevista

La validación de cada entrega debe probar efectos observables, no solo valores de configuración:

| Caso | Resultado exigido |
|---|---|
| Primer grupo y administración de una pertenencia existente | Disponibles sin premium; no cuentan dos veces. |
| Dos altas compiten por la última capacidad | Solo se confirma la admisible; sin superar el cupo de cuenta o grupo. |
| Lote con tienda reutilizada y otras nuevas | Cuenta nombres normalizados nuevos; rechazo íntegro si falta capacidad. |
| Tienda al límite: comprar, cancelar, editar y mover | Las dos primeras liberan capacidad; editar sin crecimiento se permite; mover comprueba el destino. |
| Historial extenso y cantidad literal elevada | Solo cuentan filas pendientes, no historial ni unidades de la cantidad. |
| Pérdida de respuesta seguida de cambio de plan | Se recupera el resultado confirmado con la misma identidad y sin duplicados. |
| Traspaso a sucesor con menor plan | No transfiere el pago ni borra datos; conserva un responsable y permite resolver el exceso según la política elegida. |
| Rechazo de cuota o cliente antiguo | Borrador conservado; diagnóstico compatible y ninguna confirmación falsa o bloqueo por error desconocido. |

Antes de implementar #33 deben cerrarse su contrato/compatibilidad, la migración, la duración y cancelación de propuestas y la política de último miembro. Antes de implementar las admisiones comerciales se decidirá el recibo de rechazo; antes de activar cuotas, las cifras, el cómputo/liberación de tiendas y el detalle de pérdida de capacidad. Estas decisiones posteriores no bloquean el trabajo independiente sobre administración y traspaso. Las comprobaciones se distribuirán entre Swift Testing, PostgreSQL aislado y recorridos iOS ES/EN; no hay pruebas ejecutadas por este documento.
