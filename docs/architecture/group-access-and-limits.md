# Acceso a grupos y límites comerciales

Fecha: 9 de octubre de 2026. Ampliación aprobada: 10 de octubre de 2026.

Estado: **decisiones funcionales y plan aprobados el 9 de octubre; implementación autorizada**. El usuario confirma premium solo para grupos adicionales, límites ampliables de tiendas y productos pendientes, y capacidad compartida según el plan del administrador. Autoriza publicar este plan antes de implementar la primera unidad. Los detalles de contrato y migración se concretan durante esa unidad; este documento no acredita código, migraciones, cobros ni restricciones desplegadas.

Esta ampliación complementa la [decisión del 27 de septiembre](multiple-groups.md). Su ausencia de un máximo estructural de grupos administrados se conserva; el acceso efectivo sí podrá limitarse según el plan. La [issue #33](https://github.com/JFrancoG/SmartShoppingList/issues/33) contiene el plan operativo de la primera unidad. El [contrato del MVP](../contracts/mvp-api.md) sigue describiendo la API entregada.

Seguimiento del 9 de octubre: #33 está integrada mediante PR #34. El propietario autoriza la segunda unidad, [#35: pertenencias múltiples y selección de grupo](https://github.com/JFrancoG/SmartShoppingList/issues/35). Su [contrato](../contracts/group-memberships.md) separa pertenencias, proyección compatible y selección local por cuenta/dispositivo. La política conserva una admisión inicial de un grupo; la ampliación de capacidad se inyecta en pruebas hasta disponer de derechos verificados. El selector no cambia el plan ni concede pertenencias. Cifras premium, pérdida de capacidad y activación comercial permanecen pendientes; no se presentan como resueltas por esta unidad.

Decisión del 10 de octubre: tras integrar #35 mediante PR #36, el propietario aprueba las cifras siguientes, una única suscripción premium personal con alternativas mensual/anual y la tercera unidad, [#37: cupos y archivo/restauración de tiendas](https://github.com/JFrancoG/SmartShoppingList/issues/37). Autoriza issue, rama e implementación. Los pagos, derechos comerciales verificados y despliegue quedan para entregas posteriores. El estado operativo y la evidencia de esta unidad pertenecen a la issue.

Después de integrar #37 mediante PR #38, aprueba [#39: suscripciones verificadas y vuelta al plan gratuito](https://github.com/JFrancoG/SmartShoppingList/issues/39). Autoriza implementar los siete días de transición de grupos desde el fin ordinario efectivo, la elección por cuenta y sus cambios cada treinta días, con sustitución segura del grupo perdido. La [ampliación del contrato 0.5](../contracts/premium-subscriptions.md) concreta la matriz de acceso, las fechas y la autoridad de Apple. Precios, regalos, configuración comercial, inscripción en Small Business y activación de cobros siguen separados de esta implementación.

## Contexto y decisiones aprobadas

El modelo debe admitir varios grupos por persona y exactamente un administrador miembro por grupo, separando al creador histórico del responsable actual. La pertenencia, la administración y el derecho comercial son conceptos distintos: perder una compra o suscripción no borra automáticamente miembros, responsables ni contenido.

| Dimensión comercial | Ámbito | Gratis | Premium |
|---|---|---:|---:|
| Grupos, en total | Cuenta | 1 | 5 |
| Tiendas activas | Grupo | 3 | 10 |
| Entradas pendientes | Tienda | 20 | 100 |

Las cifras son configurables y constituyen la propuesta inicial aprobada, no un compromiso de capacidad ilimitada. Un único plan premium reúne las tres ampliaciones; las modalidades mensual y anual ofrecen las mismas capacidades y no se acumulan. No se implementan compras separadas por tienda o producto. La unidad #37 aplica el plan gratuito en el servidor nuevo y comprueba el ampliado mediante una política confiable inyectada en pruebas; ningún campo o ajuste de iOS concede premium.

Recibir una invitación no consume una pertenencia. Aceptarla para un grupo nuevo comprueba el cupo personal del invitado, aunque el administrador de ese grupo tenga premium. El rechazo `group_limit_reached` conserva el enlace sin consumir; se puede reintentar tras liberar capacidad o ampliar el plan mientras siga vigente. Su caducidad normal de 24 horas y su posible revocación siguen aplicándose. Una cuenta gratuita puede recibir varios enlaces, pero solo puede aceptar un grupo nuevo si aún no pertenece a ninguno. La app conserva el flujo de una invitación pendiente; no incorpora una bandeja con todos los enlaces. Aceptar una invitación al grupo del que ya se es miembro no cuenta otra vez.

Administrar un grupo ya incluido entre las pertenencias no consume otro grupo ni exige un pago adicional. El traspaso conserva la aceptación explícita del sucesor y no debe convertirse en una compra obligatoria para aceptar, ceder o salir conforme a las reglas del grupo. Restringir el uso ordinario de un grupo conserva su administrador y el acceso necesario para resolver esas responsabilidades.

Los productos se cuentan como **entradas pendientes con identidad propia**. Una entrada con cantidad «6 botellas» cuenta una vez; dos entradas iguales con IDs distintos cuentan dos veces. No se introduce catálogo ni deduplicación por nombre. Comprar o cancelar libera capacidad sin borrar el historial; editar nombre o cantidad en la misma tienda no la consume. Mover una entrada afecta a la capacidad del destino y libera la del origen al confirmar la operación.

El borrador local no consume cuota compartida antes de enviarse. Los límites técnicos vigentes de 50 entradas por operación, 100 por página y 128 KiB por petición son independientes del plan comercial.

## Decisión: capacidad compartida según el administrador

**Aprobada por el propietario el 9 de octubre.** El plan personal del administrador actual determina los límites de tiendas y productos del grupo y todos los miembros comparten esa capacidad. Cada persona mantiene su propio límite de pertenencias, con independencia del plan de los administradores de los grupos a los que accede.

Ejemplo: quien administra «Casa» tiene premium y amplía su capacidad para todos. Un familiar con plan gratuito puede usarla si «Casa» es su único grupo habilitado. Que otro miembro tenga premium no amplía por sí solo el grupo. El plan del administrador tampoco concede pertenencias adicionales gratuitas a los demás miembros.

Esta opción ofrece reglas iguales a todos los colaboradores y evita introducir de entrada una suscripción por grupo. Su coste es que una bajada de plan o un traspaso puede reducir la capacidad de otras personas; la interfaz debe mostrar la consecuencia antes de aceptar el cambio. La compra personal permanece vinculada a su titular: traspasar la administración no transfiere el pago ni la suscripción.

Alternativas descartadas para esta iteración: un plan propio del grupo separa facturación y administración, pero añade titular de pago y ciclo de facturación independientes; usar el plan de quien añade el contenido hace que dos miembros tengan reglas diferentes sobre la misma lista. El cálculo de capacidad efectiva queda en una política pequeña para poder cambiar su origen sin rehacer las pertenencias.

## Aplicación y conservación de tiendas y productos

- El servidor calcula capacidades efectivas a partir de pertenencia, rol, plan y recurso. iOS presenta acciones disponibles, uso, límite y motivo de restricción; no deduce permisos repartiendo condiciones de `isPremium` por las vistas. Las capacidades consultadas son informativas: la escritura vuelve a comprobarlas.
- Configurar el despliegue de la funcionalidad, configurar sus cupos y verificar un derecho de compra son responsabilidades distintas. Los valores de prueba no conceden premium en producción. Se puede preparar esta frontera antes de conectar los pagos, sin publicar aún un acceso premium funcional.
- Crear o aceptar otro grupo consume capacidad de la cuenta; un traspaso entre miembros existentes no añade pertenencias. Las restricciones comerciales no sustituyen la autorización ni habilitan acceso a un grupo ajeno.
- Las tiendas se crean también al enviar un lote o mover un producto. Deben contarse únicamente tiendas activas realmente nuevas tras la normalización, reutilizando las existentes. Una tienda activa vacía sigue contando hasta archivarla expresamente. Solo el administrador actual puede archivar una tienda sin pendientes; comprado y cancelado no lo impiden. El archivo conserva ID, nombre normalizado, historial y recibos. No se archiva automáticamente al terminar una compra.
- Restaurar es una acción explícita del administrador y exige una plaza de tienda activa. Recupera el mismo ID y la misma identidad normalizada. Un alta o movimiento hacia una tienda archivada se rechaza como `store_archived`: no la reactiva ni crea otra con el mismo nombre. El cliente conserva el producto/borrador y dirige a la gestión para restaurar. Las consultas y selectores ordinarios, incluida la resolución de Siri, solo incluyen activas; el listado de archivadas se solicita expresamente.
- Las admisiones comprueban el efecto completo de la operación dentro de la transacción. Un lote que excede cualquier cupo se rechaza entero, sin productos parciales ni tiendas huérfanas. Dividirlo no permite eludir el cupo acumulado.
- Como punto de partida técnico, coordinar las mutaciones por cuenta para pertenencias y por grupo para los recursos compartidos, con conteos SQL y orden uniforme de bloqueos. El bloqueo actual por usuario no basta ante dos miembros distintos. No se propone añadir contadores persistidos ni un motor genérico de reglas; el protocolo exacto se concretará con las migraciones y pruebas. Los [bloqueos de filas de PostgreSQL](https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-ROWS) ofrecen el mecanismo, pero todas las operaciones implicadas deben participar en el mismo protocolo.
- Un éxito confirmado conserva su recibo aunque después cambie el plan: recuperarlo no consume otro cupo ni vuelve a decidir su admisión comercial. Se mantiene la autorización vigente. Una respuesta incierta conserva cuenta, grupo, ruta, payload y `operationId` originales.
- El contrato distingue rechazo de cuota confirmado de falta de permisos, rate limit y resultado incierto. Los rechazos `store_limit_reached`, `pending_item_limit_reached`, `store_archived` y `store_not_empty` se conservan como recibos definitivos de la intención. Liberar capacidad o cambiar el estado no modifica ese resultado: se necesita una nueva intención explícita y otra clave. El rechazo no pierde el borrador; una respuesta incierta mantiene exactamente su clave, cuenta, grupo, ruta y payload. Un replay de éxito requiere pertenencia vigente y reproduce los bytes originales sin volver a comprobar cupo, archivo ni rol actual de administrador.

### Pérdida de capacidad

**Tiendas y productos: regla aprobada el 10 de octubre.** Si el acceso premium termina, se revoca o cambia el administrador, conservar datos, pertenencias y responsable. El exceso es un estado recuperable, no una orden de borrar ni archivar arbitrariamente tiendas. El cálculo toma el plan del administrador actual; antes de proponer o aceptar el traspaso el cliente explica ese cambio y la conservación de datos.

Para tiendas y productos, bloquear el crecimiento del recurso que exceda su límite, permitiendo consultar, completar compras, cancelar, archivar y editar sin aumentar el uso, dentro de los grupos a los que se conserva acceso. Mover una entrada exige capacidad en el destino y libera la del origen atómicamente. El exceso de tiendas no bloquea nuevas entradas en una tienda con plaza para pendientes, ni el exceso de pendientes bloquea la edición en esa misma tienda. Como el plan depende del administrador, aceptar un traspaso a alguien con menor capacidad sigue siendo posible y deja el grupo en este mismo estado de exceso.

**Pertenencias: regla aprobada para #39.** Tras el fin ordinario de premium se conservan siete días de uso de las pertenencias existentes para organizarse; no se admite otra durante ese plazo. No prolonga cupos de tiendas/productos: pasan a 3/20 al terminar premium. Cancelar la renovación conserva el periodo contratado. La gracia de cobro de Apple vigente conserva 5/10/100 hasta su fecha acreditada; se acuerda configurarla en dieciséis días solo para renovaciones de pago a pago. Reembolso/revocación no inicia otra cortesía.

La cuenta elige un grupo gratuito de uso completo, independiente del selector del dispositivo. Se conserva una elección válida anterior; sin ella, fallback a la pertenencia más antigua, con desempate por ID. El fallback no consume la primera elección manual. Un cambio manual efectivo exige treinta días móviles; elegir el mismo grupo no renueva el plazo. Salida válida/cierre permite reemplazar una elección perdida manteniendo el historial del plazo, sin impedir resolver responsabilidades ni reiniciar la primera elección por salir/reingresar.

Los adicionales siguen visibles para consulta, traspaso, salida/cierre, revocación de invitaciones, archivo de una tienda vacía y cancelación de pendientes conforme al rol. Una intención nueva de alta, edición, compra, restauración o creación de invitación exige uso ordinario y se rechaza de forma definitiva si falta. Los demás miembros mantienen el acceso que les corresponde y los límites siguen el plan del administrador. Los recibos confirmados se recuperan antes de evaluar la nueva restricción, bajo autorización vigente. Ninguna bajada de plan borra contenido, administra por sustitución automática ni exige pagar para salir.

El cierre del último miembro conserva el historial conforme a #33; acceso posterior y eliminación de cuenta mantienen su política separada. La compra se vincula a la cuenta del servicio, verificada por servidor, con productos/entorno permitidos y evidencia actual de Apple; restaurar una transacción vieja no la hace vigente. Precio y promociones siguen pendientes sin impedir desarrollar el recorrido verificado. La configuración comercial y la activación de cobros requieren completar y validar los pasos externos; #39 no los ejecuta.

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

Los contratos de #33 y #35 concretan migración, compatibilidad, traspaso, salida y cierre. La unidad #37 concreta cupos, archivo/restauración, exceso de tiendas/productos y recibos de rechazo. La unidad #39 concreta derechos verificados, transición y elección gratuita; su [matriz de aceptación](../contracts/acceptance.md#suscripción-transición-y-grupo-gratuito) distingue evidencia criptográfica, HTTP/persistencia, carreras y recorrido iOS. Las comprobaciones se distribuyen entre Swift Testing, PostgreSQL aislado, StoreKit y recorridos iOS ES/EN; este documento de decisiones no acredita su ejecución.
