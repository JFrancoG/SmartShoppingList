# Evidencia del recorrido compartido

Evidencia local inicial: 19 de septiembre de 2026, CEST; ensayo físico ampliado el 21 de septiembre. Trabajo en `codex/issue-4-shared-shopping-flow`, iniciado sobre `2f3ee14`. Seguimiento: [#4](https://github.com/JFrancoG/SmartShoppingList/issues/4). Las secciones distinguen pruebas locales, comprobaciones HTTP y resultados físicos comunicados por el usuario; no acreditan entrega en `main`.

## Resultado implementado

- Backend: challenge y canje Apple, JWKS, concesiones cifradas, sesiones persistentes, grupo, invitaciones, lotes atómicos con recibos idempotentes, tiendas y pendientes paginados. PostgreSQL conserva las restricciones y arbitra las carreras.
- iOS: acceso nativo, Keychain, conservación del enlace durante carga/SIWA/aceptación, grupo e invitaciones, confirmación explícita de tiendas, envío del borrador y consulta con refresco. Una respuesta incierta conserva el sobre original, incluido usuario y `operationId`.
- AASA y página de invitación pasiva; configuración Apple/orígenes documentada y override Docker opcional. Sin valores reales, el acceso compartido permanece sin activar y se puede preparar el borrador manual.
- `/todos` se conserva en desarrollo/pruebas y no se registra en producción. La fase 2 sigue siendo responsable de edición, cancelación, selección/finalización e historial.

Las decisiones están en [arquitectura](../architecture/shared-shopping.md) y los pasos reproducibles en [configuración](../setup/shared-shopping.md).

## Pruebas automatizadas

Entorno: Xcode 27 (`27A266a`), Swift 6.4, macOS 27 arm64; iPhone 18 Pro con iOS Simulator 27 (`24A434`). PostgreSQL 18.6 en el servicio local aislado `db-test`, puerto 5433, almacenamiento temporal. Se ejecutaron las pruebas de Xcode mediante MCP oficial; el resultado se comprobó después en cada `.xcresult` cerrado con `xcresulttool`.

| Suite | Resultado nativo | Bundle local |
|---|---|---|
| iOS Fast, 15:22:11 | 48 tests, **80 invocaciones**, 0 fallos y 0 runtime warnings | `Test-SmartShoppingList-2026.09.19_15-22-11-+0200.xcresult` |
| iOS Integration, 15:02:35 | 4 tests, **6 invocaciones**, 0 fallos y 0 runtime warnings | `Test-SmartShoppingList-2026.09.19_15-02-35-+0200.xcresult` |
| Servidor, 15:22:14 | 50 tests, **72 invocaciones**, 0 fallos y 0 runtime warnings | `Test-SmartShoppingListServer-2026.09.19_15-22-14-+0200.xcresult` |

Los bundles iOS están bajo `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/`. El del servidor está bajo `/Users/jesusf/Library/Developer/Xcode/DerivedData/SmartShoppingListServer-gglgzaxldexmsodyegvupaqgkklo/Logs/Test/`; la ruta de artefacto devuelta por MCP para ese servidor no existía, por lo que se verificó el bundle real. El resumen MCP arrastra algunos resultados anteriores y no coincide con las invocaciones del plan activo; los números de la tabla proceden de los bundles nativos.

Casos nuevos relevantes:

- Challenge reclamado una sola vez, nonce/subject del canje, sesión y logout, revalidación concurrente, fallo transitorio, expiración tras espera e invalidación selectiva de concesiones. AES-GCM rechaza ciphertext alterado o vinculado a otra concesión/versión. El canje firmado y los errores de Apple usan transporte controlado.
- Autorización entre grupos, gestión reservada al creador, invitaciones caducadas/revocadas/consumidas y recuperación de una aceptación confirmada. Dos aceptantes compiten por la misma fila. Aceptar/revocar se comprueba en **ambos órdenes efectivos**.
- Repetición simultánea de una clave devuelve los mismos IDs y un solo recibo; otra intención con esa clave se rechaza. Dos miembros crean tiendas compartidas en orden inverso sin perder sus lotes. Las carreras esperan bloqueos observados mediante `pg_blocking_pids`; no usan una pausa temporal como prueba de solapamiento.
- Un CHECK temporal provoca un fallo en el segundo producto después de escribir el primero: la transacción revierte productos, tiendas nuevas y recibo. Una referencia de otro grupo tampoco produce escritura parcial.
- Parser de enlaces estricto, transporte sin redirecciones, límites, páginas sin ciclos y respuestas ajenas rechazadas. `state` incorrecto no envía credenciales; una cuenta distinta no reproduce un sobre pendiente.
- Enlaces recibidos durante carga, SIWA o aceptación se conservan; la promoción no borra otro enlace que llega durante la escritura de Keychain. Errores desconocidos y mensajes de error incompletos no descartan una operación ni una invitación.
- Reapertura de Keychain conserva sesión, invitación y operación; la confirmación elimina solo filas del borrador que coinciden con las enviadas, manteniendo correcciones o altas posteriores.

Se observó RED antes de activar la implementación del parser, del transporte y reintento del cliente, de once casos de negocio, de ocho regresiones de conservación del cliente, de tres respuestas de error incompletas y del origen HTTPS con `/` final. El resto son comprobaciones de comportamiento/integración; no se atribuye un ciclo RED previo a todos los tests añadidos.

## Linux y transporte real local

`docker compose build app` completó Release arm64 con Swift 6.4 y las imágenes fijadas del repositorio. Log local: `/tmp/smartshoppinglist-block4-linux-build.log`. Las dependencias mantienen sus versiones; solo se añade el producto FluentSQL del paquete ya incorporado.

Se ejecutó una prueba HTTP de extremo a extremo del servidor sobre `127.0.0.1:8092`, con un contenedor temporal y una base distinta `smartshoppinglist_block4_testing`. Se sembraron tres identidades/sesiones **sintéticas directamente en esa base de prueba**, sin añadir un endpoint de autenticación ficticia. El ensayo completó:

1. Arranque, migraciones, challenge y exclusión de `/todos` en producción.
2. Creación de grupo e invitación; GET pasivo, preview y aceptación de un segundo usuario; rechazo de un tercer aceptante.
3. Lote, reproducción exacta, consulta por ambos miembros y rechazo de un usuario ajeno o sin bearer.
4. Reinicio real del proceso/contenedor de la app; mismos productos, IDs, pertenencias y resultado idempotente al consultar/reintentar después.
5. Logout y rechazo de la sesión revocada.
6. Comparación de logs contra bearer, nonce y secreto de invitación de las fixtures con `LOG_LEVEL=trace`: no aparecen después de corregir la configuración del logger HTTP y el de base de datos.

El probe local fue `/tmp/smartshoppinglist-block4-smoke.py`; terminó con `PASS`. Se retiraron su contenedor y su base temporal. No se usó ni se borró el volumen de desarrollo. Este ensayo acredita HTTP real y persistencia entre procesos; **no** acredita TLS público, iOS contra el alojamiento, Apple real ni persistencia tras reiniciar PostgreSQL en este bloque.

## Pantallas y revisión

Revisión independiente de estándares iOS, accesibilidad estática y backend. Se corrigieron los hallazgos de pérdida de enlaces, eliminación prematura ante respuestas desconocidas, origen HTTPS con barra final y navegación a Comprar al recuperar una invitación. Las previews poseen modelos y servicios ficticios independientes; los contextos compartidos contienen solo valores.

Renderizados e inspeccionados en iPhone 18 Pro: raíz con ambas pestañas, revisión de tiendas y gestión de invitaciones en tamaño estándar, acceso con texto XXX Large y revisión/invitación en AX5. Los textos inspeccionados se redistribuyen sin truncación horizontal; el Form requiere desplazamiento en los tamaños de accesibilidad. Las capturas iniciales con spinner se sustituyeron por fixtures preparadas antes del render. Los artefactos están en `.../ActionArtifacts/default/RenderPreview/`, entre las 15:12 y las 15:14.

La auditoría final de estilo cubrió los 50 archivos Swift modificados o nuevos del bloque, con revisión manual y script de candidatos. Se normalizaron las construcciones señaladas, se comprobó `git diff --check` y se repitieron las compilaciones y las suites Fast/servidor después del pase; los bundles de la tabla corresponden a ese resultado final.

Una captura no prueba desplazamiento, orden de foco, VoiceOver ni entrega de enlaces desde otra app. Esas comprobaciones siguen pendientes y se coordinan con [#7](https://github.com/JFrancoG/SmartShoppingList/issues/7).

## Compilación y diagnósticos

Las compilaciones de iOS y servidor con targets de pruebas completaron correctamente. No se identificaron warnings del código Swift propio y se mantiene warnings-as-errors. **No se declara una compilación global sin avisos:** los logs completos de Xcode incluyen `Metadata extraction skipped, no AppIntents.framework dependency found`, emitido por `appintentsmetadataprocessor` para targets sin App Intents; el resumen MCP no lo enumeraba. También consta en el log previo del bloque 3 de las 14:08, con una tarea de las 13:57. Esto corrige la interpretación anterior basada en el resumen de herramientas.

Logs de referencia: `.../ActionArtifacts/default/BuildProject/BuildProject-Log-20260919-152149.txt` para iOS y `BuildProject-Log-20260919-152155.txt` para servidor. El aviso sigue visible, sin flags de supresión, y queda cubierto exclusivamente por [EXC-002](../dependency-exceptions.md#exc-002--extracción-de-metadatos-app-intents-sin-adopción), aceptada el 21 de septiembre. No se declara ausencia global de avisos. La excepción [EXC-001](../dependency-exceptions.md) solo cubre el manifiesto de JWTKit 5.7.1 al resolver dependencias; no incluye este diagnóstico.

Swift 6.4 también falló internamente al compilar el override asíncrono Objective-C de redirección de URLSession. Se usa el callback oficial `@Sendable`, con rechazo inmediato, manteniendo async/await en el transporte. No se rebaja la concurrencia ni se añade `@unchecked Sendable`.

## Preparación del alojamiento después del punto de control

Tras publicar [e446b8e](https://github.com/JFrancoG/SmartShoppingList/commit/e446b8efc88a3ea74982cfddc8ef892fe14c6fe0), se adaptaron dos entradas de configuración necesarias para Railway: `APPLE_PRIVATE_KEY_PEM` como alternativa excluyente al archivo `.p8`, y `DATABASE_CA_CERTIFICATE_PEM` para exigir TLS y verificar la CA y el hostname de PostgreSQL. Se retiró el cache mount del Dockerfile que requería un ID específico del servicio y se concretaron puerto, referencias entre servicios y variables en la guía de entorno. No se cambiaron paquetes, pins ni contrato HTTP.

- Auditoría independiente de los cuatro Swift modificados o añadidos: perfil maintenance, estilo y pruebas de comportamiento, sin hallazgos.
- Build Xcode del servidor con tests: PASS, log `BuildProject-Log-20260919-164216.txt`. Conserva únicamente el diagnóstico de metadatos ya descrito; no hay nuevos warnings Swift identificados.
- Swift Testing del servidor: **61 tests únicos / 98 invocaciones**, cero fallos y cero runtime warnings. Bundle nativo: `/Users/jesusf/Library/Developer/Xcode/DerivedData/SmartShoppingListServer-gglgzaxldexmsodyegvupaqgkklo/Logs/Test/Test-SmartShoppingListServer-2026.09.19_16-42-36-+0200.xcresult`.
- Las nuevas pruebas verifican firma ES256 y claims con PEM directo y archivo, rechazos de configuración incompleta/ambigua/inválida y rechazo de CA inválida. La pareja de claves de pruebas es sintética y pública. No se atribuye un ciclo RED observado a estas pruebas.
- Probe TLS real con el ejecutable macOS recién compilado y PostgreSQL 18.6 en un contenedor temporal: arranque, migraciones y `/hello` con CA correcta; rechazo al arrancar con CA ajena (`CERTIFICATE_VERIFY_FAILED`), nombre incorrecto (`failedToValidateHostname`) y servidor sin TLS (`sslUnsupported`). El caso sin TLS no vuelve a texto plano. Probe: `/tmp/smartshoppinglist-block4-tls-probe.py`; resultado final: cuatro PASS. Se retiraron contenedor, base y certificados sintéticos.
- Docker Release Linux arm64: PASS con el Dockerfile ajustado, log `/tmp/smartshoppinglist-block4-railway-linux-build.log`. No acredita aún amd64 ni un despliegue en Railway.
- Se reutilizan las pruebas iOS del punto de control: estas adaptaciones no modifican cliente ni contrato.

El 19 de septiembre se preparó [EXC-002](../dependency-exceptions.md#exc-002--extracción-de-metadatos-app-intents-sin-adopción); el responsable del proyecto la **aceptó explícitamente el 21 de septiembre**, sin ampliar su alcance. El aviso permanece visible y no se aplican flags de silencio. Las comprobaciones de esta sección acreditan la preparación local; el ensayo alojado posterior se registra por separado a continuación.

## Ensayo físico con Railway — 21 de septiembre de 2026

Backend del punto de control `04ba09d`, con configuración de Railway ajustada por el usuario. Durante el ensayo, el cliente usó esa rama más cambios locales de URL y Associated Domains en el proyecto Xcode y los entitlements; esta configuración se incorpora al repositorio junto con el informe ampliado. Dispositivos comunicados por el usuario: primer cliente iPhone 11 con iOS 27; segundo cliente iPhone 14 con iOS 27. No se registraron los números de build del sistema.

Consolidación autorizada por el usuario: resultados y criterios actualizados en [#4](https://github.com/JFrancoG/SmartShoppingList/issues/4#issuecomment-5763487624) y evidencia manual del borrador en [#7](https://github.com/JFrancoG/SmartShoppingList/issues/7#issuecomment-5763488486). Ambas issues permanecen abiertas. El usuario autorizó después commit y push de la configuración y la evidencia; el enlace definitivo de publicación se registra en las issues.

- El usuario confirmó `Deployment successful` y `Hello, world!` en el endpoint HTTPS público `/hello`.
- Comprobación HTTP directa: `/.well-known/apple-app-site-association` respondió 200, JSON con `NWN8JUE438.com.plusprojects.SmartShoppingList` y `/invite/*`.
- El usuario confirmó dos dispositivos con Apple IDs distintos en el mismo grupo después del recorrido de invitación indicado. Precisó que compartió las invitaciones mediante AirDrop y que el recorrido funcionó sin problemas. Es evidencia manual de recepción y apertura mediante AirDrop; no se probó Mail/Mensajes ni se inspeccionó el nonce del canje real. No recuerda con certeza si el segundo cliente ya tenía sesión al recibir la primera invitación.
- En un ensayo posterior, siguiendo los pasos de cerrar sesión en el iPhone 14, recibir por AirDrop una invitación nueva y volver a iniciar sesión, el usuario confirmó que la invitación seguía apareciendo. Acredita conservación del enlace durante el acceso con una cuenta ya miembro; no una nueva incorporación sin sesión previa.
- Ambos incorporaron manualmente un producto a Mercadona y vieron los dos productos tras confirmar el envío y actualizar. La ausencia inicial de tiendas se resolvió completando la confirmación del borrador; no se acreditó un fallo de carga.
- Tras cerrar completamente y reabrir ambas apps, el usuario confirmó la recuperación de sesión, grupo y consulta de productos.
- Tras el ensayo indicado de cerrar sesión y volver a acceder con el mismo Apple ID en un iPhone, el usuario observó primero «Preparar acceso con Apple», después el botón de inicio de sesión y, al acceder, los productos anteriores. Acredita la recuperación visible de la lista tras autenticarse de nuevo; no se confirmó expresamente en este paso el estado de la sesión del segundo dispositivo.
- Tras el reinicio indicado del servicio SmartShoppingList en Railway, manteniendo PostgreSQL en ejecución, el usuario confirmó que ambos clientes conservaron sesión, grupo y todos los productos sin duplicados al actualizar. Es evidencia manual comunicada por el usuario; no acredita un reinicio de PostgreSQL.
- Después del ensayo indicado de crear, compartir y revocar una nueva invitación antes de abrirla en el segundo iPhone, el usuario confirmó el aviso de invitación revocada con indicación de solicitar un enlace nuevo. Se acredita el rechazo visible del enlace revocado con un usuario ya miembro; no una incorporación rechazada de una tercera identidad.
- Ante el ensayo indicado de modo avión, confirmación sin red, recuperación de conexión y reintento, el usuario comunicó que todo fue correcto: operación conservada, producto compartido una sola vez y resolución del borrador. No equivale a una prueba de pérdida de respuesta después de que el servidor haya confirmado la escritura.
- Borrador local en un iPhone: tras añadir dos productos, corregir uno, eliminar el otro y cerrar completamente sin enviar, el usuario confirmó que al reabrir se conservó únicamente el producto corregido. Al actualizar Comprar en el otro dispositivo, ese producto no apareció. Acredita edición/eliminación y persistencia física del borrador, y separación entre preparación local e incorporación explícita al grupo; aporta evidencia parcial a #7.

**Hallazgo de interfaz:** al confirmar desde el final del formulario, el error se presentó arriba, fuera de la zona visible y con poco énfasis. El usuario tardó en localizarlo. Acordó aplazar su corrección junto con la revisión de interfaz a la fase 3; la comunicación del fallo debe ser visible desde el punto de interacción y accesible, sin depender únicamente de rojo. No se han implementado cambios de interfaz en este ensayo ni se dan por evaluados los demás ajustes que el usuario quiere revisar.

**Segundo hallazgo de interfaz:** después de conservar la invitación durante el acceso, se ofrece «Aceptar invitación» aunque la cuenta ya pertenece a ese grupo. La inspección de `SharedGroupView` confirma que el botón no comprueba esa pertenencia. Para una invitación nueva, `ShoppingService` rechaza la aceptación con `already_in_group` antes de actualizar la membresía o consumir el enlace. Se anota para la revisión de fase 3: mostrar que ya pertenece al grupo y ofrecer descartar el enlace, sin una aceptación innecesaria. No se ha ejecutado ni se atribuye una prueba física de pulsar Aceptar en este caso.

## Pendiente para acreditar el bloque completo

- Completar la evidencia específica desde Mail/Mensajes y rechazos de invitaciones inválidas, caducadas o consumidas; conservar la distinción respecto de las pruebas automatizadas ya aprobadas, del enlace revocado y de la conservación durante el acceso mediante AirDrop descritos arriba.
- Completar voz/IA, permisos y accesibilidad con interacción, conservando la dependencia #7 y la evidencia física del borrador ya descrita. La configuración iOS y esta evidencia están publicadas en `d2bd13b`; hardware y versiones principales de los clientes constan arriba.
- Mantener explícito el presupuesto del alojamiento antes de cualquier contratación o ampliación; el despliegue de prueba no autoriza gastos nuevos.
- Revisión y merge de la PR, cierre de issues y retirada de rama pendientes de completar los criterios y recibir la autorización de entrega. Una PR en borrador permite revisar el trabajo sin acreditar esos pasos.

La issue permanece abierta. El 19 de septiembre se autorizó guardar y publicar este punto de control mediante commit y push en `codex/issue-4-shared-shopping-flow`, y continuar con los pendientes antes de lanzar la PR. La publicación verificada y su commit se registran en la issue; este documento no acredita el cierre del bloque. EXC-002 quedó aceptada por decisión separada del 21 de septiembre; la PR #9 continúa en borrador.
