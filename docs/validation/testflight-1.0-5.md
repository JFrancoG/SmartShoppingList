# Distribución de TestFlight 1.0 (5)

Fecha: 7 de noviembre de 2026. Issues [#54](https://github.com/JFrancoG/SmartShoppingList/issues/54)
y [#49](https://github.com/JFrancoG/SmartShoppingList/issues/49).
Rama: `codex/issue-54-production-readiness`, base de consolidación `3dd5237`.
Código publicado: [`464118d`](https://github.com/JFrancoG/SmartShoppingList/commit/464118df78da93b22636a1c5665ba088c2a688d8).

## Alcance y revisión

El propietario autoriza revisar/consolidar, hacer commit y push y preparar el siguiente build para
TestFlight Internal Only. Se conserva el bundle comercial, versión 1.0 y separación de datos; el
build pasa de 4 a 5 mediante Xcode. Al iniciar esta preparación, el último Archive local y build
distribuido acreditado era 1.0 (4).
Tras recuperar la sesión, App Store Connect confirma que el último build cargado es 1.0 (4),
En pruebas e Internos para core; no existe build 5 al preparar este Archive.

Se consolidan bootstrap previo a sesión/datos, aislamiento de App Intents/compras/invitaciones,
diagnóstico separado, metadatos de privacidad de cámara y marcador Sandbox; también las tres
correcciones de #49 (invitación tras cambiar grupo, presentación offline y refrescos/avisos).
La revisión independiente de aislamiento, compras, SwiftUI/localización y estilo no deja hallazgos.
Se corrigen dos detalles de estilo sin ampliar el comportamiento. Evidencia gráfica y archivos nuevos
revisados sin secretos; los resúmenes documentales incorporan las aceptaciones físicas existentes.

## Validación del conjunto

- Fast final mediante Xcode MCP: **481 ejecuciones correctas**, 0 fallos, 0 omitidas y 0 esperadas.
  Los 14 resultados no ejecutados pertenecen a la selección excluida y no cuentan como pruebas pasadas.
  iPhone 17 Simulator, iOS 27.0, SDK 27.1. Compilación sin errores ni warnings.
- Integration real desde Xcode GUI: **21 ejecuciones correctas** de 13 declaraciones, 0 fallos,
  0 omitidas ni avisos de runtime. iPhone 17 Simulator, iOS 27.2. Instalación Xcode 27.1 (27A9275).
  El servicio MCP indicaba Integration pero ejecutó Fast; se detectó al contrastar los casos y se
  eligió el plan en Product → Test Plan antes del ensayo real. No se alteraron los planes.
- Validador de contrato: 31 operaciones, 125 ejemplos positivos y 47 peticiones negativas correctas.
- Sistema de diseño: 65 pares × 4 modos y 23 assets × 4 variantes correctos.
- Catálogos JSON y `git diff --check` correctos. No cambia código/contrato del servidor; no se
  repite CI de servidor ni se despliega Railway.
- Se reutilizan las previews offline ES Large/AX5 y las revisiones documentadas de #49: sólo
  la compactación equivalente de un modificador visual cambia después de esas capturas.

Evidencia local:

- Fast: `ActionArtifacts/default/RunAllTests/DF40E8F9-FB81-42DA-842E-A6A8BCDA44AC.txt`.
- Log sin warnings: `ActionArtifacts/default/GetBuildLog/6AEF1C5A-F310-49EB-A61D-78E2EFC0061D.txt`.
- Integration: `~/Library/Developer/Xcode/DerivedData/SmartShoppingList-cnedcbvxlssppmejeutmxomopscm/Logs/Test/Test-SmartShoppingList-2026.11.07_13-39-50-+0100.xcresult`.

## Archive comercial

Creado con **Product → Archive**, esquema SmartShoppingList y configuración Release, a las
**13:46 CET** desde el commit publicado `464118df78da93b22636a1c5665ba088c2a688d8`:

`~/Library/Developer/Xcode/Archives/2026-11-07/SmartShoppingList 07-11-2026, 13.46.xcarchive`

- Versión **1.0 (5)**, nombre visible **Smart List**, bundle `com.plusprojects.SmartShoppingList`.
- Xcode 27.1 **27A9275**, SDK **iphoneos27.1**, mínimo **iOS 27.0**, arm64.
- Sign in with Apple y los dos dominios explícitos de invitación en los entitlements.
- Descripción de cámara base/EN/ES presente; firma verificada con `codesign --verify --deep --strict`.
- Firma de desarrollo del Archive, previa al nuevo firmado de distribución; `get-task-allow=true`
  no se presenta como entitlement de un IPA distribuido.
- Log **del Archive**: `~/Library/Developer/Xcode/DerivedData/SmartShoppingList-cnedcbvxlssppmejeutmxomopscm/Logs/Build/48DD0105-4CCD-427A-873C-5B70FC2FA6BD.xcactivitylog`.
  Finaliza a las 13:46:16 CET: configuración Release, optimización `-O`, sin `-D DEBUG`, 0 errores
  y 0 warnings. El GetBuildLog del servicio corresponde a Fast y no se usa como prueba del Archive.
- Composición: 101 fuentes (97 comerciales y 4 generadas), ninguna de DistributionDiagnostics.
  Los puntos de entrada a fixtures y reembolso de pruebas están protegidos por `#if DEBUG`, excluido
  por los flags Release comprobados. El ejecutable está stripped: la ausencia de símbolos por sí sola
  no prueba esa exclusión. Conserva literales de argumentos usados por AppIconController para inhibir
  el cambio de icono; no son puntos de entrada a fixtures.
- UUID arm64 de app y dSYM coincidente: `22F38F7F-82C2-38A4-8699-7AA11B6B8A83`.
- **Validate App** de Xcode termina correctamente a las **13:48 CET**: “SmartShoppingList 1.0 (5)
  validated — Your app successfully passed all validation checks.” Organizer conserva Validation succeeded.
- Al terminar la preparación se comprueba **TestFlight Internal Only** y se cancela antes de Distribute.
  La autorización posterior de subida y su resultado se registran a continuación.
- SHA-256 del ejecutable: `5c28f0761eea2ea0aabca2c738b1d5774bf4298044d0d5032b26b0549b88a899`.

## Subida autorizada — 7 de noviembre de 2026

El propietario autoriza subir **1.0 (5)** mediante **TestFlight Internal Only** para **core**. Se
reutiliza el mismo Archive validado y se verifica su hash antes de distribuir; no se recompila.
Xcode confirma **SmartShoppingList 1.0 (5) uploaded**, con evento de subida correcto a las
**14:07:52 CET**, sin errores ni warnings. El asistente confirma explícitamente
**Upload for TestFlight (Internal Testing Only)**.

[Confirmación de Xcode](evidence/issue-54-commercial-build-5-upload-complete.png).
App Store Connect recibe la carga a las **14:07 CET** y finaliza el procesamiento. Se completa el
cuestionario técnico de cifrado con **Ninguno de los algoritmos mencionados anteriormente**: se
conserva el uso exclusivo de servicios Apple auditado en los builds 3/4 (CryptoKit/SHA-256 para
namespaces, Keychain, HTTPS/URLSession, autenticación Apple y StoreKit), sin criptografía propia
ni bibliotecas externas. Se contrasta de nuevo con la
[tabla de Apple](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/).
No se añade una declaración persistente al proyecto ni se aceptan acuerdos nuevos.

A las **14:16 CET**, **core** confirma **2 testers / 4 compilaciones**, incluida
**1.0 (5) · Internos · En pruebas**, con 90 días de disponibilidad. La distribución automática
existente incorpora el build; se conservan los dos testers asociados a iPhone 16 e iPhone 11,
sin nuevas invitaciones ni permisos. «Qué se debe probar» queda guardado con instrucciones ES/EN
para estas tres regresiones en el campo de Inglés (EE. UU.), único idioma habilitado en el formulario.

- [Build 1.0 (5)](https://appstoreconnect.apple.com/teams/69a6de96-c6fd-47e3-e053-5b8c7c11a4d1/apps/6814161606/testflight/ios/d3950308-8434-4ba4-9d4b-fe5549269864).
- [Disponibilidad comprobada en core](evidence/issue-54-commercial-build-5-testflight-core.jpg).

La disponibilidad por sí sola no acredita instalación ni aceptación física; los resultados informados
por el propietario se recogen a continuación.

## Aceptación física de esta ronda

### Retornos desde segundo plano — iPhone 16

En la ronda solicitada para 1.0 (5), el propietario confirma que ha salido a la pantalla de inicio
del iPhone y vuelto a Smart List desde **Añadir, Comprar y Premium**: **no aparece el aviso** y
**Test1 y sus productos se conservan**. Se acepta este recorrido visible con conexión; no hace
falta repetirlo. La instalación/número de build no se ha inspeccionado independientemente.

Este resultado no mide el número de peticiones ni, por sí solo, acepta fallos de lectura sin conexión,
arranque offline/recuperación, vista previa de invitación tras cambiar grupo o accesibilidad de
los estados modificados. El ensayo offline posterior se recoge a continuación.

### Arranque sin conexión y recuperación — iPhone 11

El propietario confirma que, sin conexión, la app indica que **todavía no se han comprobado los
grupos**. Al recuperar Internet vuelven **Test1**, **Aldi al seleccionarlo** y **los productos**,
**sin avisos**. Se acepta la presentación de grupos sin verificar y la recuperación observada;
no hace falta repetir este recorrido. No se informa del contenido del borrador ni de VoiceOver
en este estado, por lo que no se amplía esa evidencia.

### Vista previa al cambiar grupo — iPhone 11

Tras abrir un enlace de Test1 y ver **Invitación pendiente → Test1**, el propietario confirma
que cambia el grupo activo **Test1 → B** y la invitación vuelve a mostrar **Test1 automáticamente**,
**sin pulsar Actualizar, aceptar ni descartar**. Se acepta la reconsulta de la vista previa después
del cambio de grupo. No se repite la incorporación ni se cambia la pertenencia del usuario.

### Error de lectura, accesibilidad y recuperación — iPhone 11

En Comprar, el propietario confirma que **VoiceOver lee el error y el botón Actualizar** y que
con **texto al máximo no se tapa nada**. Al recuperar Internet, **desaparece el error y vuelven
los mismos productos, sin avisos**. Queda aceptado el feedback de lectura observado, su legibilidad
y la recuperación. No se infiere que haya activado Actualizar con VoiceOver: sólo se informó de su
lectura, y la recuperación puede producirse automáticamente al volver a primer plano.

Los tres recorridos funcionales y esta comprobación accesible completan la ronda acotada de #49
en los iPhone. No se solicitan más repeticiones de estas pruebas ni de compra, salida del grupo A·2,
incorporación a Test1 o sincronización ya aceptadas. No equivale a una auditoría global de accesibilidad.

### Corrección del guion y límites

Corrección del guion: el propietario señala que Añadir a mano incorpora el producto directamente.
La fuente lo confirma: DraftItemEditor llama a addManualItem cuando añade directamente al grupo;
la petición de preparar un borrador con ese recorrido era incorrecta, no un defecto observado de
la app. No se pide fabricar un borrador, cambiar acceso o repetir incorporaciones para este ensayo.

No se acredita conservación física de un borrador en esta ronda ni medición física de peticiones HTTP.
Se conservan las pruebas automatizadas previas de persistencia/coordinación y sus límites; el código
del Archive no cambia durante esta aceptación y no se repiten suites por actualizar documentación.

Siguiente gate: revisión mediante PR, CI e integración autorizada en main. #49 permanece abierta
hasta su entrega; #54 conserva requisitos de publicación dentro de la app, preparación de producción,
App Store Connect, App Review y sustitución por App Store. Esta ronda no acredita esos recorridos.
No se fusiona la rama ni se despliega Railway al registrar la aceptación.

## Resumen del alcance publicado en «Qué se debe probar»

**ES** — Comprobar la invitación pendiente al cambiar de grupo, sin actualización manual; arranque
sin red sin sugerencias incorrectas de crear/unirse a un grupo y recuperación de los datos al conectar;
retornos a primer plano en Añadir, Comprar y Premium, con y sin red, sin avisos falsos de envío.
Revisar texto grande y VoiceOver en los estados modificados. Las compras y la sincronización ya
aceptadas no necesitan repetirse.

**EN** — Check the pending invitation after switching groups without a manual refresh; offline launch
without incorrect create/join suggestions and recovery after reconnecting; returning to Add, Shop
and Premium with and without network, without misleading submission alerts. Check large text and
VoiceOver in the changed states. Previously accepted purchase and synchronization tests need not
be repeated.
