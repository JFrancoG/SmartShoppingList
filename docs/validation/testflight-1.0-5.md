# Preparación de TestFlight 1.0 (5)

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
- Se comprueba el método **TestFlight Internal Only** en el asistente. Se cancela antes de Distribute:
  no se ha subido ni exportado un IPA, ni añadido build 5 al grupo core. La preparación solicitada queda
  completa; el mismo Archive validado está listo para la siguiente subida autorizada.
- SHA-256 del ejecutable: `5c28f0761eea2ea0aabca2c738b1d5774bf4298044d0d5032b26b0549b88a899`.

## Siguiente gate

La preparación del Archive está completa. El siguiente paso es subir **este mismo Archive 1.0 (5)**
mediante **TestFlight Internal Only**, comprobar su procesamiento y disponibilidad en core. La
validación de Apple no equivale a subida ni aceptación física. #49 y #54 permanecen abiertas;
no se ha fusionado la rama ni desplegado producción.
Tras instalar el build nuevo, comprobar sólo los tres recorridos de
[regresión de #49](ui-controls-and-refresh-review.md#próxima-aceptación-física-sólo-en-el-nuevo-build).
No repetir compra, salida del grupo A·2, incorporación a Test1 ni sincronización ya aceptadas.

## Texto preparado para probar el siguiente build

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
