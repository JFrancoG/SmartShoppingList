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

## Revisión tras actualizar el entorno — 22 de septiembre de 2026

Entorno verificado: macOS 27.2 (`26B5091g`), Xcode 27.2 beta (`27B5019j`) y destino activo iPhone 18 Pro Max Simulator con iOS 27.2. La conexión MCP habitual apuntaba al servicio de Xcode 27.0; se abrió una conexión temporal al MCP oficial del proceso de Xcode beta para inspeccionar la sesión real, sin cambiar `xcode-select` ni la configuración persistente de Codex.

- En la app, con «Dos litros de leche y seis huevos de Mercadona», un breakpoint antes de traducir el error confirmó `NSError`, dominio `FoundationModels.LanguageModelError`, código `-1`, con error subyacente `ModelManagerServices.ModelManagerError 1026`. La conversión `error is FoundationModels.LanguageModelError` dio `false` y la disponibilidad del intérprete seguía siendo `.available`. Se reanudó la app y se verificó que no quedaron breakpoints temporales.
- Esa sesión también contiene un error anterior, de las 07:57:20 CEST, por ausencia de assets de `com.apple.modelcatalog` (`UnifiedAssetFramework 5000`). No se atribuye automáticamente ese mismo diagnóstico interno a todos los reintentos.
- Un probe independiente ejecutado directamente en el Mac con el toolchain beta devolvió `SystemLanguageModel.default.availability = .unavailable(.modelNotReady)` y `supportsLocale(es_ES) = true`. El intento de contar tokens falló con `NSError`, dominio `FoundationModels.LanguageModelError`, código `-1`, subyacente `ModelManagerError 1019`; no llegó a generar una respuesta. Esto acredita que el modelo del host no estaba listo en ese momento, no un fallo de soporte del español. No se ha identificado el significado de los códigos internos mediante API pública.
- `interpretationMessage` agrupa `.unavailable`, `.failed` y errores ajenos al dominio en `default`. El adaptador anterior convierte los errores no reconocidos en `.failed`. Conviene distinguir la indisponibilidad y conservar diagnóstico técnico; ampliar casos del enum público no convierte el `NSError` observado en un caso conocido ni resuelve la disponibilidad del modelo. Esta revisión no modifica el código.

Se revisaron las etiquetas estables publicadas de los 35 paquetes de `server/Package.resolved`. Las cuatro dependencias directas conservan la última versión estable encontrada. Hay actualizaciones transitivas candidatas de [AsyncHTTPClient 1.35.0 a 1.36.1](https://github.com/swift-server/async-http-client/releases/tag/1.36.1) y [swift-configuration 1.2.0 a 1.2.1](https://github.com/apple/swift-configuration/releases/tag/1.2.1); no se han aplicado ni validado. [swift-crypto 5.0.0](https://github.com/apple/swift-crypto/releases/tag/5.0.0) también está publicado, pero los manifiestos actuales de Vapor, JWTKit, PostgresNIO y swift-certificates restringen la resolución a versiones inferiores a 5. Se mantiene 4.5.2.

JWTKit sigue en 5.7.1 en el pin y el manifiesto por defecto; `.watchOS(.v8)` continúa en el manifiesto externo específico de Swift 6.4. El cambio local del usuario en `server/Package.swift` introduce `JWT_KIT_URL`, `JWT_KIT_BRANCH` y `JWT_KIT_REVISION`, pero no acredita una actualización de versión. Se conserva sin alterar durante esta revisión; debe reconciliarse con EXC-001 antes de entregarlo, porque permite cambiar la procedencia o revisión según el entorno. EXC-002 no se amplía automáticamente a Xcode 27.2; no se ha certificado una compilación de todos los targets con este toolchain.

### Ajustes autorizados después de la revisión

El usuario pidió aplicar los ajustes recomendados el 22 de septiembre. Se retiraron los overrides de JWTKit del manifiesto raíz y se restauró también el manifiesto original de su checkout de Xcode, donde había un parche local a watchOS 9. JWTKit queda en la versión oficial 5.7.1, manteniendo EXC-001. Se actualizaron exclusivamente los pins de AsyncHTTPClient a 1.36.1 y swift-configuration a 1.2.1; los otros 33 no cambiaron.

`interpretationMessage` ahora enumera todos los errores del dominio y el caso de error ajeno (`.none`), con un mensaje específico para `.unavailable`. El intérprete registra dominio y código en OSLog antes de traducir los errores del framework; el detalle original está marcado como privado porque puede incluir texto del usuario o generado. Los errores desconocidos continúan usando `.failed`, sin inferir significados de códigos internos de Apple. Se añadió una regresión Swift Testing para indisponibilidad durante una solicitud, conservación del borrador/mensaje y reintento posterior; su ejecución aprobada consta a continuación, sin atribuir un ciclo RED observado.

Compilaciones con targets de pruebas en Xcode 27.2 beta: iOS completó (`BuildProject-Log-20260922-082633.txt`); servidor completó a las 08:32:51 tras recuperar en la caché de Xcode la revisión oficial de swift-configuration y volver a resolver (`BuildProject-Log-20260922-083251.txt`). Los primeros intentos del servidor mostraban éxito global pese a un fallo previo de resolución y no se consideran validación de las versiones nuevas. Se comprobó después el estado de paquetes de Xcode: AsyncHTTPClient 1.36.1, swift-configuration 1.2.1 y JWTKit 5.7.1.

Los logs finales completos mantienen únicamente el aviso de metadatos App Intents, además del aviso de JWTKit observado durante la resolución SwiftPM. No se certifica una compilación global sin avisos. El responsable aceptó explícitamente el 22 de septiembre ampliar EXC-002 al mismo diagnóstico y alcance para Xcode 27.2 beta (`27B5019j`), según el registro de excepciones. Revisión manual y script de estilo en los tres Swift del cambio sin hallazgos; los literales de mensajes y logging permanecen como expresiones atómicas. `git diff --check` pasa. No hay commit, push ni nueva validación Linux de estas dependencias. El reintento manual de IA posterior se registra a continuación.

### Validación tras aceptar EXC-002 en la beta

El 22 de septiembre el usuario confirmó que, al reintentar Interpretar, se incorporaron correctamente los dos productos al borrador. Es evidencia manual de una interpretación real satisfactoria en español en el entorno de simulador recién actualizado; no se registraron duración ni valores completos de los campos en ese reintento. El estado `modelNotReady` anterior deja de describir un bloqueo permanente del ensayo. No se atribuye la recuperación del modelo a los cambios del mensaje o del logging de la app, ni se acreditan todavía inglés, voz o el conjunto de casos de #7.

Ensayo manual adicional confirmado por el usuario: «Necesito pan y café» añadió dos productos al borrador, con cantidad y supermercado vacíos. Acredita conservación de datos ausentes sin inventarlos en ese caso español; no completa por sí solo la matriz de interpretación de #7.

Segundo ensayo manual adicional confirmado: «Dos litros de leche de Mercadona y pan de Lidl» añadió leche con cantidad «Dos litros» y tienda Mercadona, y pan con cantidad vacía y tienda Lidl. Acredita asignación separada de tiendas explícitas y conservación de la cantidad ausente en ese caso español.

Tercer ensayo manual adicional confirmado: «Necesito pan y café. Aún no he decidido si comprarlos en Mercadona o en Lidl» añadió ambos productos con cantidad y supermercado vacíos. Acredita que el intérprete no elige una tienda ante alternativas ambiguas en este caso español.

Ensayo negativo fallido, comunicado el 22 de septiembre a las 10:40: «Hoy hace buen tiempo y voy a dar un paseo.» añadió `producto1` y `producto2`, ambos sin cantidad ni tienda, en lugar de mostrar el aviso de ausencia de productos. La captura del usuario acredita el fallo; no se considera aprobada la extracción de texto ajeno a una compra. La protección aplicada y sus límites se registran más abajo.

Pruebas ejecutadas mediante MCP oficial de Xcode 27.2 beta (`27B5019j`) y contrastadas con sus bundles nativos cerrados:

| Suite | Resultado | Bundle |
|---|---|---|
| iOS Fast, iPhone 18 Pro Max, iOS 27.2 (`24B5084k`) | 49 tests únicos / **81 invocaciones**, 0 fallos, 0 omitidos y 0 runtime warnings | `Test-SmartShoppingList-2026.09.22_09-47-36-+0200.xcresult` |
| Servidor, macOS 27.2 (`26B5091g`), PostgreSQL local de pruebas en 5433 | 61 tests únicos / **98 invocaciones**, 0 fallos, 0 omitidos y 0 runtime warnings | `Test-SmartShoppingListServer-2026.09.22_09-47-05-+0200.xcresult` |

El MCP rechazó la selección de siete tests iOS porque los marcaba deshabilitados, pese al tag `fast` en el plan. Se ejecutó el plan Fast completo, que sí corrió la regresión nueva junto con los otros tests del plan. Su resumen MCP incluía cinco casos ajenos no ejecutados; los recuentos de la tabla proceden de `xcresulttool get test-results summary`, no de sumar entradas históricas del MCP. Para el servidor, la copia del artefacto MCP quedó incompleta, por lo que se leyó el bundle cerrado bajo `DerivedData/SmartShoppingListServer-gglgzaxldexmsodyegvupaqgkklo/Logs/Test/`. El bundle iOS cerrado está también en `DerivedData/SmartShoppingList-cnedcbvxlssppmejeutmxomopscm/Logs/Test/`.

Los logs de compilación conservan el aviso de App Intents cubierto por la EXC-002 ampliada. La resolución de paquetes conserva el diagnóstico de JWTKit cubierto por EXC-001. No se han suprimido avisos ni rebajado warnings-as-errors. Estos resultados validan los ajustes locales y las dependencias actualizadas en macOS; no cierran #4/#7 ni sustituyen la validación funcional bilingüe restante.

### Protección ante nombres inventados — 22 de septiembre

Se añadió `DraftExtractionRules` al adaptador antes de devolver la propuesta: cada nombre debe tener una mención completa, distinta y ordenada en el texto de entrada. Se toleran mayúsculas, equivalencia canónica Unicode y espacios; no se sustituyen nombres ni se deducen equivalencias. Cualquier nombre sin respaldo rechaza el lote entero con `.failed`, conserva texto y borrador y muestra el aviso de interpretación fallida. Una respuesta vacía conserva el aviso específico `.noProducts`. Las instrucciones y la guía del nombre también aclaran la copia literal y la respuesta vacía; la protección no depende solo del prompt ni de prohibir `producto1`/`producto2`.

Validación local mediante Xcode MCP 27.2 beta: compilación correcta; plan Fast aprobado con **56 tests únicos / 92 invocaciones**, 0 fallos, 0 omitidos y 0 runtime warnings, contrastados con `xcresulttool` sobre `Test-SmartShoppingList-2026.09.22_10-50-37-+0200.xcresult`. Incluye el caso comunicado, rechazo atómico de una propuesta mixta, límites de palabra, menciones repetidas, Unicode, espacios y conservación del borrador ante `.failed` y `.noProducts`. El log completo `BuildProject-Log-20260922-105000.txt` conserva solo el aviso de App Intents admitido por EXC-002. La revisión de estilo de los cuatro Swift modificados no deja hallazgos tras ajustar un bloque `if`; el cambio posterior a las pruebas fue exclusivamente de formato. No se atribuye un ciclo RED observado.

**Reintento manual confirmado por el usuario el 22 de septiembre:** al repetir «Hoy hace buen tiempo y voy a dar un paseo.» apareció el aviso y el usuario confirmó el comportamiento esperado, sin nuevas filas. Se acredita este caso negativo en la app después del ajuste. No se recogió el texto exacto del aviso ni la respuesta bruta del modelo, por lo que no se distingue entre extracción vacía y propuesta rechazada por la validación. La ejecución auxiliar anterior con `RunCodeSnippet` había devuelto `.unavailable`; su resultado se conserva como evidencia separada.

**Hallazgo de interfaz del reintento:** con varios productos en el borrador, el aviso queda al final y solo se ve al hacer scroll. Se añade al trabajo de fase 3 ya acordado para comunicar errores desde la posición actual de la pantalla, sin depender del color ni obligar a buscar el mensaje. No se modifica la interfaz en esta validación.

El guard comprueba respaldo literal, no intención de compra ni relaciones semánticas entre campos. Este caso aprobado no completa #7. No se han eliminado las filas existentes del usuario, cerrado la issue ni hecho commit/push de estos ajustes.

Ensayo manual de menciones repetidas confirmado por el usuario el 22 de septiembre, después de la protección de nombres: «2 manzanas en Mercadona y 3 manzanas en Lidl.» añadió dos filas independientes de manzanas, con cantidades 2 y 3 y sus respectivas tiendas. No se fusionaron las menciones. Es evidencia de este caso español en el entorno de simulador del ensayo; no acredita alternativas de tienda vinculadas para una única compra.

Ensayo manual de variantes confirmado por el usuario el 22 de septiembre: «2 litros de leche sin lactosa y 1 litro de leche entera en Mercadona.» generó dos entradas con sus variantes diferenciadas. El usuario confirmó el resultado esperado del ensayo; se registra conservación de «sin lactosa» y «entera», sin fusionar los productos.

### Intento de dictado en simulador — 22 de septiembre

Tras pulsar Dictar, el usuario no obtuvo transcripción y comunicó mensajes de consola. Se inspeccionó mediante Xcode MCP la sesión real de SmartShoppingList (PID 33874, en ejecución), iPhone 18 Pro Max Simulator, iOS 27.2 (`24B5084k`). Los mensajes de inicio provienen de QuartzCore/CoreAnimation y BoardServices/PointerUI; `AddInstanceForFactory` proviene de CoreFoundation/CFBundle. Esos logs aislados no identifican la causa del dictado fallido.

La inspección directa con Device Hub mostró que la app había vuelto a Dictar y, al desplazar el borrador, el aviso «La transcripción en español no está disponible en este dispositivo. Puedes escribir el texto o añadir los productos a mano.». En el código actual, ese aviso corresponde a `.unavailable` o `.unsupportedLocale`; ambas comprobaciones se realizan antes de pedir permiso de micrófono, instalar assets o abrir la captura. No se ha distinguido cuál de las dos comprobaciones falla, ni se acredita un problema de permiso o de selección de entrada de audio. No se cambiaron ajustes, permisos ni código, y no se obtuvo transcripción real. El aviso volvió a quedar fuera de la zona inicialmente visible, reforzando el hallazgo de interfaz pendiente.

Siguiente ensayo propuesto: dictado en el iPhone 14 físico, verificando primero la transcripción sin pulsar Interpretar. La ausencia de Apple Intelligence no es una condición que nuestro adaptador Speech compruebe; su disponibilidad se valida por separado. No se acredita todavía el dictado en físico ni se cierra el criterio de voz de #7.

Confirmación posterior del usuario, 22 de septiembre: en el iPhone 11 físico tampoco se pidió permiso de micrófono; tras hacer scroll encontró el mismo aviso de transcripción española no disponible. Se registra dictado no disponible con la configuración actual, sin distinguir todavía `.unavailable` de `.unsupportedLocale`, que comparten texto. No se ha probado inglés ni se ha confirmado el resultado del iPhone 14. El adaptador en producción usa `es-ES` explícito y solicita automáticamente la instalación de assets después de comprobar soporte y permiso.

### Micrófono en Mac (Designed for iPad) — 22 de septiembre

El usuario habilitó el destino Mac (Designed for iPad) y ejecutó la app en macOS 27.2 con Xcode 27.2 beta. Se preserva su cambio `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = YES`. La sesión real (PID 38563) llegó a `.permissionDenied`; por el orden del adaptador, las comprobaciones de disponibilidad de Speech y locale español habían pasado, sin acreditar todavía descarga o transcripción.

El registro `tccd` de las 12:14:27 atribuyó el rechazo a la política de Hardened Runtime: faltaba `com.apple.security.device.audio-input`. La firma original contenía el flag `runtime` y el Info.plist contenía la descripción de uso del micrófono. El target iOS tenía `ENABLE_HARDENED_RUNTIME = YES` tanto en Debug como en Release. Se probó añadir el entitlement y habilitar Audio Input, pero las compilaciones MCP, incluida una tras Clean Build Folder, no lo incorporaron a la firma iOS. Se retiraron esos ajustes al no acreditar una solución. No se han cambiado permisos TCC ni reiniciado autorizaciones.

Apple DTS indica que Mac (Designed for iPad) sigue las convenciones iOS, sin requerir Hardened Runtime: https://developer.apple.com/forums/thread/825449. El usuario aprobó explícitamente desactivarlo solo en **Debug** del target iOS: `ENABLE_HARDENED_RUNTIME = NO`. Release conserva `YES`, y se mantienen App Sandbox y los permisos de privacidad del sistema.

Tras una primera compilación cancelada, el usuario autorizó continuar. Xcode 27.2 beta compiló correctamente a las 12:37 para My Mac (Designed for iPad). Se verificó la firma del producto Debug: `flags=0x0(none)`, sin `runtime`, con fecha de firma 12:37:36. El log conserva el aviso de extracción de AppIntents contemplado en EXC-002. Xcode MCP lanzó correctamente la app a las 12:38 (PID 41460). Se acredita la compilación, la firma corregida y el lanzamiento; quedan pendientes la aparición del diálogo de permiso y la transcripción real al pulsar Dictar.

### Crash al crear la captura de audio en Mac — 22 de septiembre

Tras superar la comprobación de permiso, la sesión PID 41460 se detuvo a las 12:44:46 en `SpeechCaptureService.prepareCapture`, llamada a `CaptureInputSequenceProvider.providerWithSession`. Xcode MCP confirmó una excepción Objective-C no capturada: `NSInvalidArgumentException`, `-[AVCaptureAudioDataOutput setAudioSettings:]: unrecognized selector sent to instance`. El stack sitúa la llamada dentro de Speech. El header del SDK 27.2 declara `audioSettings` no disponible para iOS; la evidencia apunta a una incompatibilidad de la factoría en la ejecución iOS sobre macOS 27.2 beta. No es un error Swift que el `catch` actual pueda recuperar ni prueba un fallo del idioma.

Se limita el ajuste a `ProcessInfo.processInfo.isiOSAppOnMac`: crear explícitamente `AVCaptureSession`, su entrada y la salida proporcionada por `CaptureInputSequenceProvider.init(session:analyzerFormat:priority:)`, usando un formato obtenido de `SpeechAnalyzer.bestAvailableAudioFormat`. Se mantiene la propiedad de los recursos en el actor, la conversión del proveedor y el ciclo existente de finalización/cancelación. iPhone y simulador conservan la factoría anterior. La API está documentada por Apple: https://developer.apple.com/documentation/speech/captureinputsequenceprovider/init(session:analyzerformat:priority:).

Validación: Xcode 27.2 beta compiló correctamente a las 12:48, sin errores de concurrencia ni nuevos warnings; únicamente el aviso de AppIntents aceptado en EXC-002. Auditoría de estilo del diff Swift sin hallazgos. La app volvió a abrirse en My Mac (Designed for iPad), PID 42622. En ese punto quedaba pendiente repetir la captura real; la compilación por sí sola no acreditaba la solución.

El usuario confirmó después dos ensayos reales en ese Mac: ambos mostraron «Escuchando…» y el botón «Terminar dictado», y produjeron transcripción sin repetir el crash. En el primero se reconoció «Albi» en lugar de «Aldi», con el resto correcto; en el segundo se transcribió correctamente la frase propuesta («Dos yogures naturales y un paquete de arroz en Mercadona»). Se acredita el inicio de captura y la transcripción en español en iOS sobre Mac, con una confusión observada de nombre de tienda. No se acredita precisión general ni dictado en iPhone, simulador o inglés. La cancelación y la posterior reanudación requieren un ensayo explícito; la aparición del botón Terminar no se registra por sí sola como validación independiente de su finalización.

### Cancelar dictado restaura el texto anterior — 22 de septiembre

El usuario confirmó que la cancelación y el reinicio del dictado funcionaban en Mac, pero señaló que Cancelar debía descartar lo transcrito. Se acordó restaurar exactamente el texto anterior al inicio de esa captura, incluido el campo vacío, conservar productos del borrador y mantener la transcripción al pulsar Terminar. El usuario autorizó la corrección.

El ViewModel conserva el texto previo por captura, invalida los identificadores antes de restaurarlo y persiste la restauración mediante el mecanismo existente. Las interrupciones por segundo plano o edición siguen deteniendo la captura sin descartar el texto recibido. La instantánea se libera al finalizar o cancelar, y una finalización tardía no afecta al siguiente dictado.

Se reprodujo el defecto con Swift Testing antes de la corrección. Tras aplicarla, el plan Fast pasó en My Mac (Designed for iPad), macOS 27.2 (26B5091g), Xcode 27.2 beta: **59 pruebas únicas / 97 ejecuciones, 0 fallos, 0 omitidas y 0 warnings de runtime**, según el resultado nativo `Test-SmartShoppingList-2026.09.22_13-08-33-+0200.xcresult`. Incluye restauración exacta de texto vacío/con espacios/ya interpretado y su persistencia, conservación de productos, Terminar seguido de otra captura cancelada, finalización tardía y paso a segundo plano. Los cinco casos de Integration quedan fuera de Fast. La compilación conserva únicamente el aviso de AppIntents aceptado en EXC-002. Auditoría de estilo de los dos archivos Swift afectados sin hallazgos. **Validación manual confirmada por el usuario:** en el Mac, cancelar desde un campo inicialmente vacío lo deja vacío; cancelar tras escribir «Pan» restaura exactamente «Pan». Se acredita la restauración visible en ambos casos. La persistencia de esa restauración está verificada por las pruebas automatizadas; no se atribuye a esta confirmación una reapertura manual adicional.

### Recorrido voz → interpretación → borrador en Mac — 22 de septiembre

El usuario confirmó el ensayo indicado en My Mac (Designed for iPad), con la versión local posterior al ajuste de cancelación: vaciar el campo, dictar «Tres tomates y dos botellas de agua en Lidl», pulsar Terminar dictado y después Interpretar texto. Se añadieron las dos entradas esperadas (tomates, cantidad 3; agua, cantidad 2 botellas), ambas en Lidl, conservando los productos anteriores del borrador. Se acredita el recorrido integrado real en español en ese Mac, incluida la finalización del dictado. Esta prueba no envía productos al grupo ni acredita inglés, voz en iPhone, rechazo de permisos o accesibilidad. No se midió la latencia.

### Micrófono sin permiso en Mac — 22 de septiembre

En el ensayo de permiso desactivado en My Mac (Designed for iPad), el usuario confirmó que al pulsar Dictar aparece el aviso de que el micrófono no tiene permiso y se conservan correctamente el texto y los productos del borrador. Se acredita la gestión visible del permiso denegado y la conservación del contenido en ese entorno. El usuario confirmó después la recuperación: tras volver a habilitar el permiso, cerrar y abrir la app, reapareció «Escuchando…», se obtuvo transcripción y se pudo terminar el dictado. Se acredita el recorrido de denegación y recuperación del permiso en ese Mac. Esta confirmación no acredita por separado una nueva edición manual ni el comportamiento en iPhone.

### Dictado en iPhone 14 físico — 22 de septiembre

El usuario confirmó el ensayo propuesto con la versión actual de la app en el iPhone 14: dictar «Pan y leche en Mercadona» y terminar el dictado. La transcripción funciona y el control Interpretar texto permanece deshabilitado, según lo esperado en ese dispositivo. Se acredita captura y transcripción real en español en el iPhone 14; no se acredita inferencia de Foundation Models en él. La comprobación posterior de Xcode MCP identifica el destino activo «iPhone14 de Jesús», iOS 27.2 (sin registrar el build exacto). Ante un aviso de que Cancelar no retiraba lo transcrito, el usuario aclaró que no había lanzado la app y confirmó que sí lo hace tras lanzarla. Se registra la cancelación correcta en el iPhone con la app actual, sin introducir otro cambio de código. Quedan por comprobar las interrupciones de captura y los restantes criterios de inglés y accesibilidad.

### Interrupción por segundo plano en iPhone 14 — 22 de septiembre

El usuario confirmó el ensayo en iPhone 14 con iOS 27.2: iniciar un dictado, esperar texto visible, salir a Inicio y volver a la app. La captura se detuvo conservando lo transcrito y permitió iniciar otro dictado. Se acredita la interrupción por segundo plano y la recuperación en ese dispositivo, diferenciadas de Cancelar, que restaura el texto anterior. Esta evidencia no acredita interrupciones por llamada, cambio de entrada ni desconexión de micrófono.

### Primera comprobación de accesibilidad mediante Device Hub — 22 de septiembre

El usuario precisó que utiliza el iPhone 14 desde Device Hub expandido, con los controles laterales de accesibilidad, y que allí ha probado VoiceOver. Comunicó que Interpretar texto y Revisar borrador se anuncian como «atenuado». Se registra esa locución observada del estado no disponible, sin tratar la diferencia respecto de «deshabilitado» como un error de traducción. El código deshabilita Revisar borrador si no hay productos o existe una actividad en curso; no se confirmó cuál de esas condiciones concurría al escucharlo. Después de añadir manualmente un producto con nombre y tienda y volver al borrador sin dictado activo, el usuario confirmó que Revisar borrador ya no se anuncia como «atenuado». Se acredita la actualización del anuncio de estado desde Device Hub; esta confirmación no acredita por sí sola su activación ni el recorrido completo de revisión.

Esta evidencia corresponde a la comprobación asistida desde Device Hub conectado al iPhone 14; no se presenta como un recorrido completo mediante gestos directamente en el teléfono. Los resultados del editor y su retorno de foco se detallan a continuación; siguen pendientes los anuncios dinámicos, el scroll y el resto del recorrido con VoiceOver. No se da por completado el criterio de accesibilidad.

**Hallazgo de foco al cerrar el editor:** en el mismo ensayo asistido desde Device Hub, el usuario indicó que al volver de editar el foco pasó a «Añadir, encabezamiento». Se registra pérdida de la posición del producto en el borrador. Objetivo para fase 3: devolver el foco al producto editado o a su acción Editar, con una alternativa coherente si ese elemento ya no existe. La inspección de `AddItemsView` muestra una sheet sin restauración explícita mediante `AccessibilityFocusState`; esto no prueba por sí solo la causa del comportamiento del sistema. Pendiente corrección y revalidación con VoiceOver. El usuario confirmó después que se anuncian correctamente nombre, cantidad, tienda y los botones del editor, y que pudo modificar la cantidad y guardar. Al volver aplicando los cambios, el foco también pasó a «Añadir, encabezamiento». Se acredita ese recorrido de edición asistido desde Device Hub; la restauración del foco continúa siendo un hallazgo abierto.

### Texto grande: ejemplo de entrada truncado — 22 de septiembre

En la comprobación solicitada con el tamaño máximo de accesibilidad, dentro del ensayo asistido desde Device Hub conectado al iPhone 14, el usuario indicó que el único texto recortado era el placeholder de entrada: se corta en «yo…», correspondiente a «yogures». No comunicó otros recortes. Se registra un hallazgo de presentación del ejemplo, no pérdida del texto introducido ni de los productos. La inspección del código confirma que el campo tiene la etiqueta de accesibilidad «Texto de la compra» independiente del placeholder. No se da por completada toda la accesibilidad a partir de esta observación. En fase 3 se revisará un ejemplo más breve o ayuda que admita varias líneas a tamaños de accesibilidad.

### Error del editor sin anuncio automático — 22 de septiembre

En el ensayo con VoiceOver mediante Device Hub conectado al iPhone 14, se pidió añadir «Pan», dejar la tienda vacía y pulsar Aplicar. El usuario informó de que tras pulsarlo no se anuncia nada más; para leer el aviso debe desplazarse hasta él. Se acredita que el mensaje es alcanzable y se lee al enfocarlo, pero el fallo de validación no se comunica automáticamente desde la acción Aplicar. No se infiere de esta respuesta una comprobación adicional de todos los valores del formulario.

Hallazgo abierto para fase 3: comunicar el error de validación con VoiceOver al producirse, mediante un anuncio o gestión de foco apropiada, sin obligar a buscar el aviso ni duplicar su lectura; mantener el editor y los datos para corregir el campo. Revalidar con VoiceOver al aplicar sin tienda y después al corregirla. El criterio de accesibilidad de #7 sigue abierto.

### Punto de control para publicación — 22 de septiembre

El usuario autorizó commit y push de las correcciones y resultados acumulados, manteniendo la PR #9 en borrador y #4/#7 abiertas. El código iOS y sus pruebas están en `ee9aefa`; las dependencias del servidor, en `9c27684`. Se reutiliza la validación nativa del mismo código descrita arriba (iOS: 59 pruebas / 97 ejecuciones; servidor macOS: 61 / 98), sin atribuir una repetición ni una nueva prueba Linux. La auditoría final del diff de siete archivos Swift no detectó hallazgos de estilo y `git diff --check` pasó. La confirmación del push se registra en las issues después de verificar `origin`.

Se planifica [#10: entrada al borrador con Siri y App Intents](https://github.com/JFrancoG/SmartShoppingList/issues/10) después del recorrido de compra, por elección explícita del usuario. Es un extra sin implementar; no se cierra la validación de App Intents ni se retira EXC-002 por esta propuesta.

## Revisión de PR #9 y Linux — 22 de septiembre, 15:58 CEST

Revisión del HEAD publicado `9e51e2c29184ff733dc9020fc58b3c7c3fcd9276`, sin modificar código de producción ni pruebas. Se revisaron las fronteras de autenticación, autorización, transacciones, recibos, transporte y conservación de estado del cliente, y las correcciones recientes de voz/interpretación. El pase automático de estilo abarcó los 58 Swift del diff: un candidato dentro de un literal SQL, descartado como falso positivo; se conserva la evidencia anterior de revisión manual de estilo. `git diff --check origin/main...HEAD` pasó. No se presenta esta revisión como una aprobación independiente ni como validación física nueva.

### Validación nueva

- **Docker Release Linux arm64: PASS**, Dockerfile e imágenes fijadas del repositorio, Swift 6.4.0. Imagen `smartshoppinglistserver:review-9e51e2c`, ID `sha256:e3d20ba662e2b991cb4a81e215b6a23de268df4fdd1c0a688427e7604d261c31`, usuario `vapor:vapor`. Log: `/tmp/smartshoppinglist-sep22-linux-build.log`.
- **Swift Testing en Linux: 61 pruebas en 8 suites, PASS**, 2,907 segundos de ejecución tras compilar Release. Comando en la etapa de compilación: `swift test -c release --jobs 4 --force-resolved-versions`; PostgreSQL aislado `db-test`. Código de salida 0. El `Package.resolved` del contenedor coincide byte a byte con el repositorio: incluye AsyncHTTPClient 1.36.1 y swift-configuration 1.2.1. Log: `/tmp/smartshoppinglist-sep22-review/linux-tests.log`. Este recuento es el resumen de Swift Testing en Linux; no se atribuyen las 98 invocaciones del informe macOS a este resultado.
- Único warning de compilación/resolución identificado: manifiesto de JWTKit 5.7.1, cubierto por EXC-001. EXC-002 permanece relevante para Xcode; no se declara ausencia global de avisos.
- **HTTP real local: resultado parcial, con fallo reproducido de autenticación.** Pasaron arranque/migraciones, `/hello`, exclusión de `/todos` en producción, challenge válido, creación de grupo, preview sin consumo, aceptación, rechazo de enlace inválido/revocado/caducado/consumido por otro usuario, aislamiento, normalización Unicode de tiendas, lote/replay, conflicto de clave reutilizada, rollback de productos/tiendas/recibo tras fallo SQL, reinicio del proceso con persistencia y logout válido. Cinco comprobaciones negativas de autenticación fallaron con 500 donde correspondía 400/401.
- El probe usa identidades/sesiones sintéticas insertadas directamente en una base temporal distinta, `smartshoppinglist_review_testing`, y HTTP por `127.0.0.1:8093`. No añade bypass al servidor ni contacta Apple/Railway. Script y logs: `/tmp/smartshoppinglist-sep22-review/smoke.py`, `smoke.log`, `runtime.log`. Se retiraron contenedor y base temporal. No acredita amd64, TLS público, credenciales Apple reales ni un despliegue nuevo.

### Hallazgo que impide recomendar el merge

**P2 — El middleware genérico intercepta los errores de autenticación.** En `server/Sources/SmartShoppingListServer/configure.swift:46`, `APIErrorMiddleware` se inserta al principio, por fuera del `ErrorMiddleware` predeterminado de Vapor. Este último convierte el error en una respuesta antes de que llegue al traductor del contrato. Las rutas de compras tienen otro `APIErrorMiddleware` dentro del grupo y no presentan este fallo; `AppleAuthenticationRoutes` depende del global.

Reproducciones sobre la imagen de producción:

| Petición | Esperado | Obtenido |
|---|---|---|
| `GET /v1/me` sin bearer | 401, `invalid_session` | 500, `error/reason` |
| `GET /v1/me` con sesión revocada | 401, `invalid_session` | 500, `error/reason` |
| `DELETE /v1/session` sin bearer | 401, `invalid_session` | 500, `error/reason` |
| `POST /v1/auth/challenges` con campo desconocido | 400, `invalid_request` | 500, `error/reason` |
| `POST /v1/auth/apple` con `{}` | 400, `invalid_request` | 500, `error/reason` |

El cliente solo reconoce la sesión inválida mediante status y código contractuales; un 500 genérico conserva la sesión como error incierto y no activa la recuperación prevista. La corrección propuesta es colocar el traductor contractual dentro del middleware genérico, y añadir regresiones a través de las rutas y la configuración reales, incluyendo sesión revocada y los cuerpos de error. Los tests directos del servicio no verifican esta cadena. **Hallazgo pendiente de implementar; no se ha aplicado una corrección en esta revisión.**

### Ensayos manuales restantes, sin repetir lo acreditado

1. Entrega del enlace por Mail/Mensajes: comprobar apertura de la app y conservación del fragmento; AirDrop ya está acreditado.
2. Rechazos alojados de enlace alterado, caducado sin consumir y consumido por otra identidad. El revocado ya se comprobó; los tres restantes tienen pruebas locales, pero no evidencia manual alojada. Para caducidad, usar una invitación realmente vencida, sin modificar el reloj o la base de producción. Reabrir con el mismo aceptante es recuperación válida, no el caso negativo de enlace consumido.
3. Completar el tramo **interpretación real → revisión/corrección → envío → consulta en el segundo cliente**. La prueba de voz/IA del Mac llegó al borrador; el envío compartido acreditado se hizo con entrada manual. Se pueden reutilizar los dispositivos/cuentas del ensayo existente.

Inglés y los hallazgos de accesibilidad siguen en #7 y en las fases previstas; esta revisión no elimina esa dependencia ni da por cerrada #4. El siguiente trabajo técnico es corregir el middleware y añadir la regresión antes de proponer el merge. La PR permanece en borrador; no se hizo commit, push, merge ni cierre de issues.

## Pendiente para acreditar el bloque completo

El fallo histórico de assets del 21 de septiembre (23:38 CEST, `com.apple.UnifiedAssetFramework`, código 5000, seguido de `ModelManagerError`) dejó de bloquear los ensayos en español: el 22 de septiembre se confirmó interpretación real, dictado y el recorrido integrado en Mac, además de dictado en iPhone 14. Sus entornos y límites están registrados arriba. Esa evidencia no completa inglés ni los hallazgos de accesibilidad pendientes.

- Completar la evidencia específica desde Mail/Mensajes y rechazos de invitaciones inválidas, caducadas o consumidas; conservar la distinción respecto de las pruebas automatizadas ya aprobadas, del enlace revocado y de la conservación durante el acceso mediante AirDrop descritos arriba.
- Completar voz/IA, permisos y accesibilidad con interacción, conservando la dependencia #7 y la evidencia física del borrador ya descrita. La configuración iOS y esta evidencia están publicadas en `d2bd13b`; hardware y versiones principales de los clientes constan arriba.
- Mantener explícito el presupuesto del alojamiento antes de cualquier contratación o ampliación; el despliegue de prueba no autoriza gastos nuevos.
- Revisión y merge de la PR, cierre de issues y retirada de rama pendientes de completar los criterios y recibir la autorización de entrega. Una PR en borrador permite revisar el trabajo sin acreditar esos pasos.

La issue permanece abierta. El 19 de septiembre se autorizó guardar y publicar este punto de control mediante commit y push en `codex/issue-4-shared-shopping-flow`, y continuar con los pendientes antes de lanzar la PR. La publicación verificada y su commit se registran en la issue; este documento no acredita el cierre del bloque. EXC-002 quedó aceptada por decisión separada del 21 de septiembre; la PR #9 continúa en borrador.
