# Entornos de distribución — comprobaciones de #54

Fecha: 29 de octubre–7 de noviembre de 2026. [Issue #54](https://github.com/JFrancoG/SmartShoppingList/issues/54).
Rama local: `codex/issue-54-production-readiness`; base `e3d47c66ac57349cedfb518d3e9491e033d90387`.

**Estado actual:** el ensayo físico de la app comercial **1.0 (3)** detecta que el aviso Sandbox oculta
Ajustes. La corrección está validada visual e interactivamente en Simulator; **1.0 (4)** tiene Archive
validado, está procesada y **En pruebas** en TestFlight Internal Only para **core**, con Jesús Franco como
tester. El ensayo posterior muestra Gratis incluso después de restaurar con autenticación Sandbox.
El 30/10 Apple y la base Sandbox confirman que la cadena previa del iPhone 16 caducó el 29/10 a las
19:58:41 CET, sin gracia ni autorrenovación; su vínculo de cuenta coincide. Ese resultado es coherente
con Gratis. Se conservan Test1 → Aldi → Alpro. Una nueva compra mensual en **1.0 (4)** obtiene Premium:
Apple y el backend confirman el periodo **30/10 12:33:33–13:03:33 CET**, renovación activa, registro de
transacción y titular coincidentes. El propietario confirma después que cerrar/reabrir conserva los
datos y Premium con la misma fecha; restaurar una vez mantiene Premium. También confirma Ajustes y
Datos de prueba accesibles, sin solaparse, desde Añadir y Comprar con texto al máximo. El dictado reconoce
el producto de prueba y Aldi; se añade a Test1 y Alpro permanece intacto. Siri abre la app y añade el
producto confirmado directamente a Comprar → Test1 → Aldi. El 7/11 también confirma la aceptación de
Test1 en el iPhone 11 y la lectura de Aldi, Alpro y otros dos productos. También confirma el alta de
un producto desde el 11 visible una sola vez en el 16 y su compra confirmada desde el 16 reflejada
en el 11, conservando los otros tres productos. En el arranque sin red, el 11 abre Añadir/Comprar y
muestra mensajes de crear/unirse a un grupo mientras sigue offline. Al recuperar conexión, vuelve
automáticamente a Datos de prueba/Test1 y carga Aldi/Alpro con los otros dos productos, sin Actualizar
manual ni avisos. El mensaje offline y los otros dos hallazgos de #49 se corrigen localmente el 7/11;
Fast supera 481 ejecuciones y queda su aceptación en el siguiente build. El propietario también confirma
VoiceOver físico: lee completa la explicación de Datos de prueba, abre y cierra ese aviso y Ajustes
desde Añadir y Comprar, sin perder ni atrapar el foco. Continúan pendientes los otros recorridos de
distribución y el feedback al restaurar sin acceso activo.
El 503 de AASA Sandbox
está corregido y verificado por HTTPS.
El propietario comunica después un aviso de envío incierto en cada retorno a primer plano: queda
priorizado en [#49](https://github.com/JFrancoG/SmartShoppingList/issues/49) antes del siguiente build;
no se deduce de ese texto que exista una operación pendiente real. El propietario confirma después
la instalación de **1.0 (4)** y **Datos de prueba** en el iPhone 11. El **7/11** comunica que no puede
aceptar la invitación a **Test1** por el cupo de grupos: primero ambos teléfonos muestran Gratis;
después informa de Premium en el 11, pero el bloqueo continúa. Confirma **cinco pertenencias: A·1,
A·2, B (grupo gratuito), C y D**. Ese bloqueo corresponde al máximo Premium vigente de cinco grupos;
el propietario cierra y abandona **A·2** y selecciona **B**. Desaparece la información de la invitación
y el botón Aceptar; un único Actualizar recupera **Test1 + Aceptar invitación**. Se identifica en fuente
que cambiar grupo activo borra la vista previa sin recargarla; queda registrado con los refrescos de #49.
Después acepta Test1 y observa Aldi, Alpro y otros dos productos: incorporación y lectura inicial
confirmadas físicamente. No se repiten instalación, compra, salida de A·2 ni aceptación de la invitación.
La V2 de la compra queda correlacionada a las **12:56:04 CET**: Apple devuelve **SUBSCRIBED / RESUBSCRIBE**,
resultado **SUCCESS**, con el mismo UUID y hash del recibo persistido en Sandbox a las **12:33:35 CET**.
La primera renovación también queda contrastada: periodo **13:03:33–13:33:33 CET**, Premium activo y
V2 **DID_RENEW / SUCCESS** correlacionada con SQL por UUID y hash.
El diagnóstico **1.0 (1)** obtuvo **Verificada / sandbox** en el iPhone 16 a las **18:18 CET**. Fast e
Integration pasan; queda completar el recorrido comercial físico, App Review y Production.
Los apartados siguientes conservan la secuencia y los límites de cada comprobación.

Actualización del **7/11**: [corrección local y guion acotado de #49](ui-controls-and-refresh-review.md)
para invitaciones al cambiar grupo, presentación sin conexión y coordinación de refrescos/avisos.
La consolidación posterior autorizada de #54/#49, commit/push y preparación del nuevo Archive se
registra en [TestFlight 1.0 (5)](testflight-1.0-5.md). Las aceptaciones de 1.0 (4) se conservan como
evidencia histórica; no se atribuyen a los cambios nuevos.

## Decisión y alcance

El propietario confirma mantener separados los datos de TestFlight y App Store: cuentas/listas de prueba
en Sandbox y contexto real independiente en Production, sin importar datos ni derechos de prueba.
La decisión está recogida en el [diseño](../architecture/distribution-environments.md).

Primero se realiza una comprobación local de la API candidata antes de cambiar la composición de la app.
Esa primera comprobación no modifica código Swift, configuración del target, servicios, datos alojados
ni credenciales. La implementación posterior del diagnóstico se registra al final de este informe.
El snippet no compra, restaura, inicia sesión, consulta catálogo ni llama a las API propias.
No invoca `AppTransaction.refresh()`, `AppStore.sync()` ni secuencias de transacciones.

## Entorno y ejecución

- Conexión oficial Xcode MCP estable; instalación local Xcode **27.1 (27A9275)**.
- Workspace descubierto por ruta: `ios/SmartShoppingList/SmartShoppingList.xcodeproj` del checkout principal.
- Esquema `SmartShoppingList`; destino temporal **iPhone 17 Simulator, iOS 27.0**.
- Contexto de fuente: `SmartShoppingList/SmartShoppingList/Services/SharedAPI/StoreKitSubscriptionStore.swift`.
- Herramienta `RunCodeSnippet`, timeout de 60 segundos. El destino original **iPhone16 de Jesús** queda
  restaurado tras la comprobación; no se instala la app en ese teléfono en este paso.

La primera compilación del fragmento señaló un `switch` no exhaustivo sobre `AppStore.Environment`.
Se contrastó la interfaz pública del SDK instalado: es un `struct RawRepresentable` con valores estáticos,
por lo que corresponde `default`, no `@unknown default`. `VerificationResult` es un enum `@frozen`.
Se corrigió exclusivamente el fragmento y se ejecutó una vez; no se cambió el archivo del proyecto.

Fragmento final reproducible con la misma herramienta y contexto:

```swift
import StoreKit

print("distribution_probe scope=local_xcode_snippet")
do {
    let verification = try await AppTransaction.shared
    try Task.checkCancellation()
    switch verification {
    case .verified(let transaction):
        let environment: String
        switch transaction.environment {
        case .sandbox:
            environment = "sandbox"
        case .production:
            environment = "production"
        case .xcode:
            environment = "xcode"
        default:
            environment = "unknown"
        }
        print("distribution_probe outcome=verified environment=\(environment)")
    case .unverified:
        print("distribution_probe outcome=unverified")
    }
} catch is CancellationError {
    print("distribution_probe outcome=cancelled")
} catch {
    print("distribution_probe outcome=unavailable")
}
```

## Resultado observado

```text
distribution_probe scope=local_xcode_snippet
distribution_probe outcome=unavailable
```

El fragmento final **compiló y se ejecutó**. La consulta lanzó un error que se clasifica sin publicar
el objeto ni su descripción. No se obtuvo un entorno verificado. El resultado no identifica la causa
concreta: no se atribuye a falta de sesión, red o limitaciones del simulador sin evidencia adicional.

No hay fallback a Production ni reinterpretación del resultado como Sandbox. No se insiste con más
intentos equivalentes ni se solicita autenticación mediante refresh. Solo se imprimen categorías
conocidas; no se imprimen transacciones, JWS, IDs de cuenta, claves ni valores desconocidos del SDK.

## Qué acredita y qué queda pendiente

La comprobación acredita la disponibilidad y ejecución de la API en ese contexto local, y muestra un
caso de indisponibilidad que el arranque deberá tratar de forma recuperable. No acredita un selector
implementado: la app sigue construyendo su contexto con la configuración compilada actual.

No es un ensayo TestFlight ni App Review, no observa el valor de su `AppTransaction.environment` y no
acredita el funcionamiento en iPhone físico. Tampoco es una ejecución de Swift Testing, un Archive ni
una compilación completa certificada sin warnings. Las fuentes y límites de la API están en el diseño.

Siguiente paso identificado tras el fragmento: preparar una comprobación ejecutable en distribución antes de completar el
enrutamiento de sesión/datos. Necesita un artefacto identificable y evidencias de TestFlight; la subida,
distribución, compras y configuración externa mantienen sus pasos propios. La decisión de datos ya
está aprobada y no debe volver a solicitarse.

## Diagnóstico distribuible preparado

El 29 de octubre el propietario autoriza la implementación acotada. Informa de que mantiene la app
Sandbox en iPhone 16 y iPhone 11; en el 16 una suscripción mensual Premium renueva cada 30 minutos.
Es contexto aportado por el propietario, no una nueva consulta a Apple o Railway. Ningún paso de esta
preparación instala, desinstala o ejecuta el diagnóstico en esos teléfonos.

Se añade [DistributionDiagnostics](../../ios/SmartShoppingList/DistributionDiagnostics) como target de app
independiente, sin dependencia del target comercial. El [esquema compartido](../../ios/SmartShoppingList/SmartShoppingList.xcodeproj/xcshareddata/xcschemes/DistributionDiagnostics.xcscheme)
usa Release para Run, Profile y Archive. Para trabajar con previews se cambia temporalmente Run a Debug
y se restaura después; Archive conserva Release. No hay configuración StoreKit local en el esquema.

- Bundle ID: `com.plusprojects.SmartShoppingList`; nombre visible: **SSL Diagnostics**.
- iOS 27.0, iPhone/iPad, Swift 6, concurrencia completa, warnings como errores.
- Versión/build locales: **1.0 (1)**. No se ha consultado su disponibilidad en App Store Connect.
- Solo consulta `AppTransaction.shared` al pulsar el botón. Normaliza verificación y entorno; muestra
  versión/build sin JWS, identificadores de cuenta ni errores completos. `unknown` no se convierte en Sandbox.
- No inicia sesión, accede a almacenamiento propio, crea clientes de backend, registra App Intents,
  consulta productos, compra, restaura, finaliza transacciones ni consume sus secuencias.
- La verificación de la transacción de la app **no acredita una compra ni concede Premium**. Tampoco
  los entitlements de firma identifican el entorno comercial de StoreKit.
- Interfaz nativa localizada ES/EN. Previews aisladas de StoreKit para inicial, verificado, error y carga.

El icono es una copia local de Check, asignada exclusivamente al target diagnóstico. El bundle Release
contiene `CFBundleIconName=AppIcon`. La lista de compilación incluye cinco fuentes del diagnóstico y
dos fuentes generadas por Xcode; ninguna fuente comercial. La compilación de la app comercial incluye
sus 96 fuentes y ninguna del diagnóstico. Se conserva sin cambios su esquema original.

### Compilación y comprobaciones locales

Xcode 27.1 (27A9275), SDK iOS/iOS Simulator 27.1, mediante Xcode MCP. Se inspeccionan los registros
completos, además del resultado resumido de la herramienta:

| Comprobación | Resultado | Registro de BuildProject |
|---|---|---|
| Diagnóstico Debug, iPhone 17 Simulator/iOS 27.0 | Correcto; cero errores y warnings | `BuildProject-Log-20261029-165301.txt` |
| Diagnóstico Release, destino genérico Any iOS Device (arm64) | Correcto; cero errores y warnings; sin instalación | `BuildProject-Log-20261029-165527.txt` |
| Diagnóstico Release, iPhone 17 Simulator/iOS 27.0 | Correcto; cero errores y warnings | `BuildProject-Log-20261029-165633.txt` |
| App comercial Debug, iPhone 17 Simulator/iOS 27.0 | Correcto; cero errores y warnings | `BuildProject-Log-20261029-165547.txt` |

Los logs están en los artefactos locales de Xcode MCP (`ActionArtifacts/default/BuildProject`). Estas
comprobaciones son builds, no Archive, validación de App Store Connect ni distribución. Se restaura
el esquema **SmartShoppingList**, plan **Fast**, destino **iPhone16 de Jesús** sin ejecutar la app.

El target sin App Intents producía un aviso de extracción de metadatos. Se configura únicamente en
este target `LM_SKIP_METADATA_EXTRACTION=YES`: [Swift Build evita generar esa tarea](https://github.com/swiftlang/swift-build/blob/0126b771ebe0f8281322cdb5126752196eedc341/Sources/SWBApplePlatform/AppIntentsMetadataTaskProducer.swift#L55-L57).
Se contrastó el macro con el Xcode instalado y se comprobó que desaparece la tarea del log final.
No se filtran warnings, no se importa AppIntents artificialmente ni se amplían las excepciones del repo.
El MCP de ajustes no reconoce este macro; se añadió como ajuste del target desde la UI de Xcode.

La revisión independiente detectó que recrear la vista podía duplicar una lectura suspendida. Se
añadió una guarda de ejecución adquirida antes del `await`, aislada en MainActor. El
[probe reproducible](probes/Issue54DiagnosticConcurrencyProbe.swift) se ejecutó con `RunCodeSnippet`
en el contexto de `DistributionDiagnosticsViewModel.swift`, usando un lector local suspendible:

```text
idleDoesNotRead=true
singleFlight=true, stillBusy=true
cancellationKeepsFlight=true
cancelled=true, clearedEnvironment=true, released=true
retryWorked=true, readerCalls=2
```

Comprueba ausencia de lectura inicial, exclusión de llamadas simultáneas, descarte del resultado tras
cancelar y recuperación para reintentar. No llama a Apple ni al backend y no se presenta como una
suite de Swift Testing. No se han añadido pruebas que reproduzcan el switch de entornos; la evidencia
que falta requiere la distribución real. Las revisiones independientes de iOS, estilo y SwiftUI no
dejan hallazgos funcionales pendientes.

Se renderizan e inspeccionan previews ES/EN en Large, XXX Large y AX5, distribuidas entre los cuatro
estados. El destino efectivo del canvas es **iPhone 18 Pro Max / iOS 27.2**, distinto del destino de
BuildProject. Se acorta el título tras observar un recorte en XXX Large. Los valores de estado se
traducen correctamente; en AX5 el formulario continúa fuera del viewport. Las capturas no acreditan
scroll completo, VoiceOver físico, foco, anuncio del resultado ni Control por voz. Un fallo transitorio
de enlace JIT tras añadir la preview de carga se resuelve al recompilar; los renders finales pasan.

### Procedimiento definido antes del Archive

1. Consultar App Store Connect y elegir un build number válido y no utilizado antes de archivar.
   Registrar revisión Git, target/esquema, versión/build y ruta del Archive exacto. Mantener el esquema
   comercial separado del diagnóstico.
2. Archivar `DistributionDiagnostics` en Release para dispositivo genérico. Revisar bundle ID, icono,
   metadatos, firma y contenido del Archive; el build local no sustituye esa inspección.
3. En la futura subida elegir exclusivamente **TestFlight Internal Only**. Es la
   [restricción de distribución que impide presentar ese build a App Review/App Store](https://developer.apple.com/tutorials/develop-in-swift/test-your-beta-app),
   no el nombre del esquema ni una variable de lanzamiento. No se ha subido ningún build en este paso.
4. Acordar el dispositivo del ensayo antes de instalar: **el mismo bundle ID reemplaza el binario
   Sandbox existente**, aunque el nombre y target sean distintos. No es necesario borrar la app ni
   datos para preparar el ensayo. La aclaración posterior del propietario se recoge abajo.
5. Desde la instalación TestFlight identificada, abrir el diagnóstico y pulsar la consulta; registrar
   procedencia, versión/build, verificación y entorno. Si no hay evidencia válida, conservar el resultado
   y reintentar expresamente; no hacer fallback, refresh, login ni compras para forzar una respuesta.
6. Usar esa observación solo como evidencia del build ensayado. No extrapolarla a App Review ni a la
   descarga comercial. Después se decide la implementación del selector antes de sesión/datos, con
   las pruebas de aislamiento descritas en el diseño.

Al terminar esta etapa permanecían pendientes Archive, subida, instalación TestFlight, App Review,
routing comercial y los demás bloques de #54. Las etapas posteriores se registran a continuación.

## Archive local — 29 de octubre, 17:12 CET

El propietario autoriza continuar con App Store Connect y el Archive. Aclara que las instalaciones
Sandbox ya no necesitan conservarse para repetir las pruebas terminadas. No se requiere desinstalarlas
para este paso: se podrán sustituir al instalar TestFlight. El borrado de la app y la gestión de la
suscripción de prueba son operaciones independientes; no se ejecutan aquí.

La pestaña de App Store Connect presenta el inicio de sesión. Se solicita al propietario autenticarse
para consultar los builds existentes y, mientras tanto, se crea el Archive local con **1.0 (1)** como
identidad provisional. La disponibilidad del número se registra después de consultar la cuenta.

Se usa **Product → Archive** de Xcode 27.1, esquema `DistributionDiagnostics`, destino genérico
`Any iOS Device (arm64)` y configuración Release. El MCP oficial no ofrece acción Archive; se usa la
UI nativa y el MCP para recuperar el registro completo. No se configura Xcode Cloud.

Artefacto local:

```text
/Users/jesusf/Library/Developer/Xcode/Archives/2026-10-29/DistributionDiagnostics 29-10-2026, 17.12.xcarchive
```

| Inspección sobre el Archive exacto | Resultado |
|---|---|
| Bundle/ejecutable | `com.plusprojects.SmartShoppingList` / `DistributionDiagnostics` |
| Nombre y versión | `SSL Diagnostics`, `1.0 (1)` |
| Plataforma | arm64, iOS 27.0 mínimo, SDK `iphoneos27.1`, Xcode `27A9275` |
| Fuentes del Archive | Cinco del diagnóstico y dos generadas; cero de la app comercial; target sin dependencias |
| Icono/localización | `AppIcon`, recursos del icono y `en.lproj`/`es.lproj` presentes |
| Recursos StoreKit/App Intents | Sin `.storekit` ni `Metadata.appintents` |
| Firma local | `codesign --verify --deep --strict` correcto; App ID/equipo coincidentes |
| Perfil del Archive | Desarrollo, `get-task-allow=true`, caduca el 16-10-2027; la operación de distribución debe volver a firmar |
| Símbolos | UUID del ejecutable y dSYM coincidentes: `38FA591C-EEB1-395D-94E1-BC350322C77A` |
| Log completo | Cero errores y warnings; corresponde a `ArchiveIntermediates/DistributionDiagnostics` |

Log local: `ActionArtifacts/default/GetBuildLog/D15A7990-D72F-440B-B4FA-CF1FE3908C24.txt`.
El ejecutable archivado tiene SHA-256
`02d065e7e3d4aabdbb6dae7b6a87ee37e84bc4c217982facbd3a7451c635345b`.
La base Git sigue siendo `e3d47c66ac57349cedfb518d3e9491e033d90387`, con los cambios locales de #54
sin commit. `/tmp/issue-54-diagnostic-archive-manifest.json` conserva las huellas de catorce archivos
de fuentes/recursos/esquema en el momento de la inspección. No incluye secretos, certificados ni UDIDs.

La firma de desarrollo del Archive no se presenta como firma de distribución. La creación del Archive
no equivale a validación de App Store Connect, exportación, subida ni procesamiento de TestFlight.

### Validación de App Store Connect desde Xcode

Se ejecuta **Validate App** sobre ese Archive, utilizando la cuenta ya disponible en Xcode. El diálogo
termina con **“DistributionDiagnostics 1.0 (1) validated”** y **“Your app successfully passed all
validation checks.”** Tras cerrarlo, Organizer conserva el estado **Validation succeeded / Validated**.
La inspección independiente del paquete y su log tampoco encuentra hallazgos.

Esta es una validación de Apple del Archive, no una subida de build a TestFlight. Al terminar esta
validación no se había abierto **Distribute App**. La sesión web continuaba pendiente del acceso del
propietario para consultar el historial de builds; no se deduce dicho historial del éxito de Validate.
La futura operación de subida debe seleccionar **TestFlight Internal Only**, comprobar la identidad
final tras la gestión de firma/build de Xcode y verificar después el procesamiento.

Se restaura el workspace a **SmartShoppingList / Fast / iPhone16 de Jesús**. No se instala ni elimina
ninguna app de los teléfonos, no se cambia la renovación Sandbox y no se realiza commit/push.

### Historial de builds y preparación de la subida — 29 de octubre

Tras el inicio de sesión del propietario se consulta la cuenta en Chrome. La ficha de
**Shopping Smart List**, Apple ID `6814161606`, muestra el bundle registrado
`com.plusprojects.SmartShoppingList`, coincidente con el Archive. La versión comercial 1.0 está
en preparación para el envío. La página TestFlight muestra **“No hay compilaciones”** y
**“Envía una compilación para empezar las pruebas”**; no aparecen grupos bajo Pruebas internas,
solo el control Nuevo grupo. No se encuentra conflicto visible para **1.0 (1)** ni un grupo
existente que distribuya automáticamente este build. Esto describe la consulta actual, no reserva
el número frente a futuras subidas.

Se abre **Distribute App** del Archive validado y se selecciona **TestFlight Internal Only**.
La pantalla conserva `DistributionDiagnostics`, el bundle esperado y **1.0 (1)**, con el texto
“Use recommended settings to distribute for internal testing with TestFlight”. No se pulsa el
botón final **Distribute**: la subida del binario a Apple queda preparada para su autorización.
Captura local del estado revisable: `/tmp/issue-54-testflight-internal-only.png`.

La continuación debe registrar la identidad final y firma de distribución, comprobar procesamiento
e indicador Internal en App Store Connect y resolver cualquier requisito de exportación que Apple
presente. Antes de repartir el build se concretará el tester/grupo interno; la modalidad Internal Only
no limita por sí misma la distribución a un único usuario. El diagnóstico solo consulta el estado
verificado y entorno normalizado de `AppTransaction.shared`; no requiere login ni ejecuta compras,
restauración, sincronización, listas o backend. Su observación no acreditará App Review ni App Store.

La consulta de App Store Connect es de lectura. Los teléfonos y la renovación Sandbox permanecen
sin cambios; no se ha subido ningún build ni modificado la configuración externa.

### Guion preparado para la comprobación física

Texto propuesto para las instrucciones internas, aún sin asignar testers ni instalar el build:

**ES:** Instala desde TestFlight, comprueba la versión **1.0 (1)** y pulsa **Consultar transacción de
la app**. Comparte los valores de **Verificación** y **Entorno**. Se espera observar `Verificada` y
`sandbox`; cualquier otro resultado también debe registrarse. Si falla, conserva el resultado antes
de reintentar manualmente. Este diagnóstico no accede a listas ni suscripciones y no permite iniciar
sesión, comprar o restaurar.

**EN:** Install through TestFlight, confirm version **1.0 (1)**, then tap **Check app transaction**.
Report **Verification** and **Environment**. We expect to observe `Verified` and `sandbox`; please
record any other result as well. If unavailable, record it before retrying manually. This diagnostic
does not access shopping lists or subscriptions and does not offer sign-in, purchases or restoration.

Registrar modelo, versión de iOS, fecha/hora, procedencia TestFlight, versión/build y captura del
resultado. Antes de la consulta deben aparecer Sin consultar / Sin determinar; durante ella, el botón
permanece deshabilitado. No forzar una respuesta mediante autenticación, compras o restauración.
Solo `Verificada + sandbox` constituye la observación esperada de este build, sin extrapolarla a
Premium, App Review ni la descarga de App Store.

## Subida autorizada a TestFlight — 29 de octubre, 17:29 CET

El propietario autoriza expresamente: **“sube el diagnóstico 1.0 (1) a TestFlight Internal Only”**.
Se ejecuta Distribute con esa modalidad sobre el Archive ya identificado. Xcode termina con
**“App upload complete: DistributionDiagnostics 1.0 (1) uploaded”**; Organizer registra
**Uploaded to Apple**, build **1**, a las **17:29**. App Store Connect recibe **1.0 (1)** y muestra
inicialmente **Procesando** en Cargas de compilaciones, con fecha **29 de octubre, 17:29**.

Captura de la finalización de Xcode: `/tmp/issue-54-testflight-upload-complete.png`.
Se exportan los artefactos de la propia operación a `/tmp/issue-54-testflight-1.0-1/` para inspección
local: `DistributionDiagnostics.ipa`, `DistributionSummary.plist`, `ExportOptions.plist` y
`Packaging.log`. La revisión independiente confirma:

| Evidencia del paquete distribuido | Resultado |
|---|---|
| Bundle / nombre / versión | `com.plusprojects.SmartShoppingList` / SSL Diagnostics / **1.0 (1)** |
| Firma | Apple Distribution; `codesign --verify --deep --strict` correcto |
| Entitlements relevantes | `get-task-allow=false`, `beta-reports-active=true` |
| Opciones de exportación | `method=app-store-connect`, `destination=upload`, `testFlightInternalTestingOnly=true` |
| Gestión automática | `manageAppVersionAndBuildNumber=true`; el IPA y DistributionSummary conservan build **1** |
| Packaging.log | Cero errores y warnings |
| SHA-256 del IPA | `f71e3e48a26c9370886717c99de2659241e68f1326e99c6416113c6d6f8abfd3` |

Esta evidencia acredita la subida y las opciones del paquete final. El procesamiento de Apple y la
disponibilidad para testers se verifican por separado. No se han creado grupos, enviado invitaciones,
instalado el diagnóstico en los teléfonos ni modificado backend, suscripciones o configuración comercial.

### Procesamiento finalizado y disponible para pruebas — 17:33 CET

App Store Connect termina el procesamiento. La ficha del binario muestra **Validado**, bundle y
versión coincidentes, símbolos incluidos, idiomas español/inglés y iOS mínimo 27.0. El listado
identifica la compilación **1 — Internos**.

Apple solicita inicialmente la información de exportación. El cuestionario pregunta qué algoritmos
implementa la app y distingue algoritmos propios/no estándar, algoritmos estándar ajenos o adicionales
a los del sistema operativo y ninguno de los anteriores. Tras revisar las cinco fuentes del target
y confirmar que únicamente se consume la verificación de `StoreKit.AppTransaction.shared`, se guarda
**“Ninguno de los algoritmos mencionados anteriormente”** para este build. No hay implementación
criptográfica propia, biblioteca criptográfica de terceros ni transporte HTTP propio en el diagnóstico.
La [referencia de Apple](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)
indica que el cifrado limitado al sistema operativo de Apple no necesita documentación en App Store
Connect. Esta respuesta se limita al diagnóstico; no clasifica la futura app comercial.

Estado final observado: carga **Finalizado**, compilación **Internos / Lista para las pruebas**,
con caducidad en 90 días. No queda el aviso de información de exportación. La fecha de creación de la
carga es 17:29 y la ficha del binario muestra carga a las 17:30; ambas pertenecen a **1.0 (1)**.

- [Build en App Store Connect](https://appstoreconnect.apple.com/teams/69a6de96-c6fd-47e3-e053-5b8c7c11a4d1/apps/6814161606/testflight/ios/c56ba87d-e75d-4dad-b370-5d2d49dd6124).
- Captura local del resultado: `/tmp/issue-54-testflight-ready.jpg`.

La subida autorizada está completada. Falta asignar el build a un tester/grupo interno y realizar la
consulta física del guion anterior. No se han enviado invitaciones ni instalado el diagnóstico; no
hay todavía una observación de AppTransaction desde TestFlight. El diseño comercial sigue Draft.

## Inicio del ensayo en iPhone 16 — 29 de octubre, 17:54–17:55 CET

El propietario autoriza añadirse como tester interno y probar el diagnóstico en su iPhone 16.
Al consultar App Store Connect, el grupo interno **core** ya existe con **Jesús Franco**, un tester y
una compilación. El build asignado es **1.0 (1) — Internos / Lista para las pruebas**. Se verifica
esa configuración sin crear un grupo duplicado ni reenviar la invitación; la tabla aún muestra
Invitado en esa lectura. El grupo tiene distribución **Automática para compilaciones de Xcode**;
se registra sin modificarla y deberá tenerse en cuenta en futuras subidas.

La captura aportada por el propietario, `Captura 2026-10-29 a las 17.54.34.png`, muestra el diagnóstico
con retorno a TestFlight, versión **1.0**, build **1**, **Sin consultar / Sin determinar** y el botón
de consulta disponible. La barra del teléfono marca 17:55. SHA-256 de la captura original:
`3d172599c81e4b6a83864939bbbfbe0c9359120624dcb3a429a5967b1d8f211c`.
El dispositivo se identifica como iPhone 16 por el propietario; la consulta de destinos de Xcode
reconoce **iPhone16 de Jesús / iOS 27.2**, sin ejecutar ni instalar nada desde Xcode.

Este estado acredita la apertura del diagnóstico, pero no su entorno. Se solicita una consulta
explícita mediante **Consultar transacción de la app** y la captura del resultado. La verificación
y el entorno real permanecen pendientes hasta recibir esa evidencia.

### Incidencia de consulta en TestFlight y contraste Release local

El propietario pulsa varias veces en **1.0 (1)** y comunica que continúa **Sin consultar / Sin
determinar**, con el botón azul y un destello al pulsar. En ese momento aún no se dispone de captura
posterior a esa pulsación, por lo que no se da por aprobado el ensayo ni se deduce ningún entorno.

Se revisan acción, Observation, `.task(id:)`, exclusión de lecturas y cancelación, sin modificar Swift
ni configuración. La propiedad `let viewModel` no constituye por sí misma un defecto de observación.
La prueba anterior del modelo no ejercitaba la conexión real entre pulsación y tarea de SwiftUI.

Se ejecuta el diagnóstico original en **Release**, Xcode 27.1, **iPhone 17 Simulator / iOS 27.2**:

- La ejecución con depurador queda en blanco. Xcode informa posteriormente del cierre de su servidor
  LLDB RPC. Ese intento es inconcluyente y no se atribuye al síntoma del iPhone físico.
- Al lanzar **sin depurador**, la pantalla inicial aparece correctamente. Una pulsación real del botón
  mediante Device Hub cambia **Sin consultar** a **No disponible**. El registro de StoreKit informa de
  `noAccount` en ese simulador; no se presenta como evidencia de entorno verificado.
- Los logs completos de ambas compilaciones Release no contienen errores ni warnings. Captura local:
  `/tmp/issue-54-release-simulator-unavailable.png`. Registros RunProject:
  `RunProject-Log-20261029-180215.txt` y `RunProject-Log-20261029-180618.txt`.

El contraste acredita el enlace botón → lectura → actualización visual en ese simulador. No reproduce
el síntoma físico. Se pide cerrar y reabrir una vez el diagnóstico desde TestFlight, pulsar una vez y
conservar una captura posterior antes de decidir si hace falta instrumentación. No se aplica una
corrección especulativa ni se fuerza refresh, login o compras.

Se detiene la ejecución local y se restaura **SmartShoppingList / Fast / iPhone16 de Jesús**.
No se sustituye la instalación TestFlight, no se sube otro build y no se cambia el código del diagnóstico.

## Resultado físico verificado — 29 de octubre, 18:18 CET

El propietario comunica que cierra la app, vuelve a abrirla desde TestFlight y pulsa una sola vez.
Observa **Consultando** durante aproximadamente medio segundo; esta duración es una estimación del
propietario, no una medición instrumentada. La captura final muestra:

| Dato observado | Evidencia |
|---|---|
| Versión / build | **1.0 / 1**, sin una nueva subida ni cambios de código |
| Verificación | **Verificada** |
| Entorno | **sandbox** |
| Procedencia | Retorno a TestFlight visible; instalación TestFlight comunicada por el propietario y build asignado en ASC |
| Dispositivo | iPhone 16, identificado por el propietario; Xcode había confirmado su destino con iOS 27.2 |
| Hora | 18:18 visible en la captura del 29 de octubre |

Se conserva sin modificaciones la [captura original](evidence/issue-54-testflight-apptransaction-1.0-1.png),
aportada como `Captura 2026-10-29 a las 18.18.22.png`.
SHA-256: `49b11b8785dafac5ccd7cda1eb73193a202fe7142e94781b709905731eab4628`.

La pantalla final **no vuelve a Sin consultar / Sin determinar**: conserva el resultado verificado
y vuelve a habilitar el botón para una consulta explícita posterior. Se da por completada la obtención
de evidencia física TestFlight de `AppTransaction.shared` para este build y ejecución. El relato
anterior no establece una causa reproducida ni una corrección: entre ambos intentos no se cambia código.
No es necesario preparar otro build o realizar una compra para obtener esta misma evidencia.

El diagnóstico no ejecuta login propio, catálogo, compra, restauración, refresh ni llamadas al backend.
El resultado verifica la transacción de la app; no acredita Premium, compras o selección comercial.
La cuenta tenía historial Sandbox: el ensayo no demuestra el caso de una cuenta sin compras previas.
Tampoco acredita el funcionamiento sin red, App Review o una descarga comercial de App Store.

La señal TestFlight permite avanzar a concretar e integrar la resolución del contexto antes de
sesión/datos y App Intents. El [diseño comercial](../architecture/distribution-environments.md) conserva
el alcance y los límites de esa integración, autorizada posteriormente y registrada en el apartado siguiente. #54 permanece abierta.


## Integración del arranque comercial — 29 de octubre

El propietario autoriza expresamente: «Integra la selección del entorno antes de cargar la sesión y
los datos, manteniendo separados Sandbox y producción». Se continúa en la misma issue/rama, sin commit.

### Comportamiento implementado

`AppEnvironmentResolver` obtiene evidencia verificada de la transacción de la app en Release y elige
Sandbox o Production. Debug mantiene Sandbox explícito. `AppBootstrap` comparte la espera entre UI y
App Intents; solo después construye API, almacenamiento, Keychain, borrador y StoreKit con un contexto
inmutable. Los errores no abren un almacén provisional ni eligen Production. Se ofrecen cancelación y
reintento explícitos; una respuesta abandonada no puede componer ni sustituir el contexto del reintento.

Se conservan los namespaces previos, la sesión/grupo y todos los sobres de trabajo. El arranque retiene
la última URL en memoria hasta resolver y comprueba el origen antes de persistirla. Una invitación válida
del otro contexto muestra una explicación sin cambiar de destino. La UI Sandbox presenta el botón
**Datos de prueba**, con explicación de la separación; textos nuevos traducidos al español e inglés.

Las transacciones IAP conservan su entorno verificado. La tienda y el coordinador filtran entornos
incompatibles antes de guardar/enviar o finalizar; no cambian de backend. Un sobre antiguo sin metadato
de entorno requiere reencontrar evidencia compatible de StoreKit antes de reenviar el JWS original.
Si esa evidencia falta, conserva el sobre y ofrece refrescar; un mismatch confirmado explica volver a
la versión original. No se recomienda una restauración deshabilitada por una operación pendiente.

### Compilación y pruebas automáticas

Conexión oficial Xcode 27.1 (27A9275), Swift 6, aislamiento por defecto nonisolated, concurrencia estricta
complete; se conservan iOS mínimo 27.0 y dependencias. No se usa xcodebuild ni se cambian servidores.

- Clean Build Folder desde Xcode y compilación Debug para tests: log `BuildProject-Log-20261029-183740.txt`,
  cero errores/warnings. Los tests posteriores se recompilan con los cambios finales de pruebas e interfaz.
- Release Simulator: `BuildProject-Log-20261029-183902.txt`; Release arm64 para dispositivo:
  `BuildProject-Log-20261029-185130.txt`; ambos logs completos sin errores/warnings, compilación optimizada
  sin `DEBUG`. Firma local de desarrollo válida; ambos dominios están en los entitlements firmados.
  No son un Archive ni una exportación App Store. El esquema temporal de validación se elimina al terminar.
- El inventario MCP marca incorrectamente todos los tests deshabilitados y rechaza RunSomeTests, incluso
  al retirar temporalmente el filtro de tags. Se restaura el plan Fast exactamente; las ejecuciones reales
  se realizan con RunAllTests. Los planes conservan sus etiquetas y no se entrega ningún cambio temporal.
- La primera ejecución Fast cae en la lectura de `@Dependency` del nuevo test de App Intents, fuera del
  cargador del sistema. Los crash reports identifican AppIntents → `perform()` antes del bootstrap. No se
  atribuye a StoreKit ni al simulador. El test se corrige inyectando el wrappedValue mediante el setter
  público, conserva `perform()` real y vuelve a ejecutar espera/error sin crear servicios prematuramente.
- Los recuentos siguientes proceden del **xcresult final** leído con xcresulttool, no de los contadores
  agregados del MCP (Integration mostraba 172/99, que no correspondían a esa ejecución).

| Plan / ejecución final | Funciones | Ejecuciones de casos | Suites | Fallos / omitidos |
|---|---:|---:|---:|---:|
| Fast, 18:49:08 CET | 249 | 441 | 17 | 0 / 0 |
| Integration, 18:49:22 CET | 13 | 21 | 6 | 0 / 0 |

Los dos resultados terminan Passed en **iPhone 17 Simulator / iOS 27.2 (24B5089g)**, sin runtimeWarnings.
Bundles de evidencia bajo el directorio temporal de ActionArtifacts/default/RunAllTests:

- `Test-SmartShoppingList-2026.10.29_18-49-08-+0100.xcresult`
- `Test-SmartShoppingList-2026.10.29_18-49-22-+0100.xcresult`

El nuevo bootstrap aporta siete funciones/once casos: composición única ante espera concurrente,
fallos sin efectos y recuperación explícita, cancelación de un caller, cancelación/reintento con resultado
antiguo tardío, reapertura de borradores aislados e invitaciones durante arranque o del contexto opuesto.
Se ejecutan ambos `perform()` con dependencia inyectada, los dos SharedAppStorageTests y cuatro funciones/
nueve casos de Keychain. Las regresiones Premium incluyen compra compatible/incompatible, restauración
mixta, updates y sobre heredado. No llaman a servidores ni ejecutan una compra real de Apple.

### Interfaz, distribución y límites

Previews renderizadas en iPhone 18 Pro Max / iOS 27.2: recuperación EN/ES, preparación y estado Sandbox;
se inspecciona ES con AX5. La primera propuesta de banner largo ocupaba demasiado espacio en AX5 y se
sustituye por el botón compacto. Capturas conservadas:

- [Sandbox en español, AX5](evidence/issue-54-bootstrap-sandbox-es-ax5.png).
- [Recuperación en inglés](evidence/issue-54-bootstrap-recovery-en.png).

La vista de recuperación es desplazable; la captura AX5 no acredita el recorrido completo de scroll ni
VoiceOver físico. El nuevo aviso y las alertas requieren su comprobación física junto al build distribuido.
Las revisiones independientes de iOS, SwiftUI/accesibilidad, concurrencia y estilo finalizan sin hallazgos.

Un lanzamiento Release sin depurador en iPhone 17 Simulator obtiene StoreKit `noAccount` a las 18:53:15;
no se deduce Sandbox de ese error. La inspección visual adicional no se completa porque el Mac queda
bloqueado; las previews y pruebas anteriores son la evidencia visual/funcional disponible. Se detiene
el proceso local. La instalación TestFlight 1.0 (1) del iPhone 16 no se sustituye.

Los entitlements contienen exactamente los dos dominios. Lectura AASA por HTTPS sin modificar servicios:
Production devuelve `NWN8JUE438.com.plusprojects.SmartShoppingList` y `/invite/*`; Sandbox devuelve HTTP 503
en dos consultas. Queda pendiente su disponibilidad/asociación y el ensayo físico de enlaces. No se da por
resuelto un problema de infraestructura a partir de un build.

Pendientes: Archive comercial con build nuevo, TestFlight de identidad/catálogo/compra/restauración e
invitaciones, cuenta sin historial, evidencia offline verificada, cargador real de App Intents/Siri,
App Review y reemplazo desde/hacia una versión App Store disponible. No se han hecho compras, despliegues,
cambios de suscripción, commit/push ni otra subida durante esta integración.


### Cierre de configuración y artefacto local

La inspección final detecta que `INFOPLIST_KEY_CFBundleDisplayName` producía **Smart List Sandbox**
también en Release, aunque la configuración del backend y la compilación eran Release. Se corrige mediante
la herramienta oficial de settings: el nombre visible pasa a **Smart List** en ambas configuraciones;
Debug conserva Sandbox como destino y el aviso de datos de prueba lo identifica dentro de la app.
No se cambia bundle ID, equipo, versión ni build. El catálogo InfoPlist vuelve a su contenido previo.

Build final arm64 `BuildProject-Log-20261029-190128.txt`: éxito, cero errores/warnings en log completo,
`CFBundleDisplayName = Smart List` en el producto final y firma local válida. Esta recompilación incluye
el último ajuste léxico de closures de la vista. No se ha exportado ni subido este producto.

Se restaura el esquema **SmartShoppingList** y el plan **Fast**, se elimina el esquema temporal y se deja
la app detenida. El destino original iPhone 16 ya no figura disponible; queda **iPhone 17 (27.2)**, sin
instalar ni ejecutar en iPhone 11. El bloqueo del Mac no impide completar estas comprobaciones mediante
las herramientas oficiales; la inspección visual interactiva de ese último lanzamiento conserva su límite.

## Sandbox y distribución comercial 1.0 (2) — 29 de octubre

El propietario autoriza revisar el 503, preparar y subir el build comercial a **TestFlight Internal Only**
para probarlo en iPhone 16. Se reutilizan las pruebas Fast/Integration y las revisiones anteriores.
Desde el artefacto local final de las 19:01 no se cambia Swift; se incrementa el build comercial a **2**
mediante Xcode.

### Causa y corrección del 503

La comprobación inicial distingue `/hello` **200** del AASA **503** con error propio `service_unavailable`.
El healthcheck configurado es `/hello`; `/health` no existe. Railway muestra **23 variables** en
`SmartShoppingListSandbox`, entorno `sandbox`: `APPLE_TEAM_ID=NWN8JUE438` es válido, pero falta
`INVITATION_ORIGIN`. La guarda de `InvitationWebsite` explica el 503 y también afecta al origen usado
para crear invitaciones.

Se añade exclusivamente la variable pública:

```text
INVITATION_ORIGIN=https://smartshoppinglistsandbox-sandbox.up.railway.app
```

El resumen de Railway contiene **1 change / 1 Variable**, sin otros cambios pendientes. Se aplica al
servicio Sandbox. El deployment anterior `6f35b555-0863-4867-8fd4-390b58bad47f` usaba
`bc7f2e2591ad8f3c78942e4a933277af68f462e1`; el nuevo
`66f4ac61-564a-40ed-90d9-a2be53e4f789` toma `e3d47c66ac57349cedfb518d3e9491e033d90387` (#53).
La revisión nueva solo incorpora documentación: ambos árboles `server/` son idénticos
(`eb372537b7bbf211924c1e8e84ce4c1f597e864a`), incluidos Docker, arranque y las ocho migraciones
registradas. No se consulta el ledger SQL ni se cambia la definición del esquema. No se modifica producción.

Después de **ACTIVE / Deployment successful**, las peticiones HTTPS de las **19:30:25 CET** confirman:

| Petición GET Sandbox | Resultado |
|---|---|
| `/hello` | 200, `Hello, world!` |
| `/.well-known/apple-app-site-association` | 200 JSON, `NWN8JUE438.com.plusprojects.SmartShoppingList`, `/invite/*` |
| `/todos` | 404, ruta de infraestructura cerrada |

[Evidencia HTTP pública](evidence/issue-54-sandbox-aasa-fixed.json). La respuesta del origen no acredita
por sí sola la caché CDN de Apple ni la apertura de un enlace en el iPhone; ese ensayo sigue pendiente.

### Archive, validación y subida

Xcode **27.1 (27A9275)**, esquema **SmartShoppingList**, destino **Any iOS Device (arm64)**,
acción **Product → Archive**, configuración **Release**, versión/build **1.0 (2)**:

```text
/Users/jesusf/Library/Developer/Xcode/Archives/2026-10-29/SmartShoppingList 29-10-2026, 19.26.xcarchive
```

Se comprueba la app comercial única, nombre **Smart List**, bundle `com.plusprojects.SmartShoppingList`,
SDK iOS 27.1, iOS mínimo 27.0, firma local válida, Sign in with Apple y ambos dominios asociados.
El log completo `GetBuildLog/240C5503-1BE4-4831-8ACB-F190DBB850DB.txt` no contiene errores ni warnings;
compila Release sin `DEBUG` y sin fuentes `DistributionDiagnostics`.
SHA-256 del ejecutable del Archive:
`28fde589c09bc83eb82d19a9691ba9d94c0b054d8749ed7842a7e7d17fbb22c1`.

**Validate App** termina correctamente a las **19:28 CET**. Se selecciona visualmente
**TestFlight Internal Only** y se ejecuta la subida autorizada; Organizer confirma
**SmartShoppingList 1.0 (2) uploaded**, con hora de subida **19:30 CET**.
[Confirmación de Xcode](evidence/issue-54-commercial-upload-complete.png).

El Archive inicial usa firma de desarrollo; la distribución vuelve a firmar el paquete. El export
de la operación completada se conserva en `/tmp/issue-54-commercial-1.0-2-testflight/`:

- `SmartShoppingList.ipa`, SHA-256 `b18f007b15d96e3a443b57252e3754d4abc0fa5e0321e862a8b5602e6afed5d8`.
- `ExportOptions.plist`: `method=app-store-connect`, `destination=upload`,
  `testFlightInternalTestingOnly=true`, símbolos incluidos y gestión automática de versión/build.
- `DistributionSummary.plist`: **Cloud Managed Apple Distribution**, perfil Store, build **2**,
  `get-task-allow=false`, `beta-reports-active=true`, Sign in with Apple y ambos dominios.
- Verificación estricta de la firma del producto exportado: correcta.

App Store Connect recibe **1.0 (2)** y comienza su procesamiento. Después lo rechaza con el error
**90683**, por ausencia de `NSCameraUsageDescription`, aunque la validación previa había terminado
correctamente. La carga `f1a4b5c2-94f9-495d-b87c-1aa17d14c6c8` queda **Fallido**; este build no está
disponible para instalar. [Error de procesamiento](evidence/issue-54-commercial-build-2-processing-error.jpg).
No se realizan compras ni instalaciones desde Xcode.
Se restaura el destino anterior **iPhone 17 (27.2)**, esquema **SmartShoppingList / Fast**, sin app en ejecución.

### Corrección de metadatos y build 1.0 (3)

La auditoría de `SpeechCaptureService` encuentra solamente `requestAccess(for: .audio)`,
`AVCaptureDevice.default(for: .audio)` y el proveedor de audio de Speech. No existe solicitud `.video`,
captura de cámara ni de fotos. El error es compatible con la detección de APIs de captura compartidas;
no se atribuye a un acceso real a cámara ni se afirma conocer la heurística del analizador.

Se añade `NSCameraUsageDescription` mediante la herramienta oficial de Xcode y su traducción EN/ES
al catálogo `InfoPlist.xcstrings`, con texto fiel al comportamiento: se usa el micrófono para transcribir
la compra y no se toman fotos ni se graba vídeo. No se cambia el código ni se solicita un permiso nuevo.
Se incrementa el build a **3**. El nuevo Archive de las **19:38 CET** contiene la clave base y ambas
traducciones compiladas, mantiene **Smart List**, versión **1.0**, bundle comercial y mínimo iOS **27.0**.

```text
/Users/jesusf/Library/Developer/Xcode/Archives/2026-10-29/SmartShoppingList 29-10-2026, 19.38.xcarchive
```

Archive correcto, cero warnings/errores (`GetBuildLog/D0BCB60B-DDEB-42F2-9978-887D072E016D.txt`).
SHA-256 del ejecutable: `0272fc42fd5bf74dfecbf192ec2c30203e3f4e7c537423406f7134fe17766705`.

La revisión independiente del nuevo Archive y **Validate App** terminan sin hallazgos. Se selecciona
**TestFlight Internal Only** y Xcode confirma **1.0 (3) uploaded** a las **19:43 CET**.
[Confirmación](evidence/issue-54-commercial-build-3-upload-complete.png). App Store Connect muestra la
carga 3 como **Procesando**. El export de esa operación se conserva en
`/tmp/issue-54-commercial-1.0-3-testflight/`; no se vuelve a exportar un Archive diferente:

- IPA SHA-256: `84be22c77c556803af9781005ec717fcf7a348f5668b55ba98d54fedbd11c96f`.
- `ExportOptions.plist`: `method=app-store-connect`, `destination=upload`,
  `testFlightInternalTestingOnly=true`, símbolos incluidos, firma y versión automáticas.
- `DistributionSummary.plist` y la auditoría independiente del IPA confirman build **3**, firma
  **Apple Distribution**, `get-task-allow=false`, `beta-reports-active=true`, Sign in with Apple y
  ambos dominios. Verificación estricta de firma correcta. El código/UUID corresponde al Archive Release;
  la copia exportada tiene el mismo hash que el paquete de la subida.
- Se restaura **SmartShoppingList / Fast / iPhone 17 (27.2)**, sin lanzar ni instalar una app.

### Disponibilidad y primer ensayo comercial

Apple finaliza el procesamiento de **1.0 (3)**. Se completa el cuestionario técnico de cifrado con
**Ninguno de los algoritmos mencionados anteriormente**: el código usa únicamente servicios del sistema
Apple (CryptoKit/SHA-256 para namespaces, Keychain, HTTPS/URLSession, autenticación Apple y StoreKit), sin
implementación criptográfica propia ni biblioteca externa. Esta respuesta distingue esas APIs de los
algoritmos propios o adicionales que pregunta el formulario; no afirma ausencia de criptografía.
Se contrasta con la [tabla de documentación de Apple](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption/).
No se añade una declaración persistente de exención al proyecto en este paso.

App Store Connect pasa a **Lista para las pruebas** y la distribución automática del grupo **core**
incorpora el build. La lectura posterior del grupo confirma **1 tester / 2 compilaciones** y
**1.0 (3) · Internos · En pruebas**; el tester existente Jesús Franco conserva iPhone 16 / iOS 27.2,
todavía con diagnóstico **1.0 (1)** instalado según el portal. No se crea otro grupo ni invitación.
Se guardan instrucciones en «Qué se debe probar» y se conserva la
[captura de disponibilidad](evidence/issue-54-commercial-build-3-testflight-core.jpg).

[Build comercial en App Store Connect](https://appstoreconnect.apple.com/teams/69a6de96-c6fd-47e3-e053-5b8c7c11a4d1/apps/6814161606/testflight/ios/551f97ac-b166-420d-b2b1-9f0c5f737601).

El siguiente ensayo físico comienza actualizando desde TestFlight sin borrar la instalación:

1. Verificar que termina la preparación y aparece **Datos de prueba**.
2. Comprobar cuenta/listas/borrador anteriores de Sandbox y carga de Ajustes/Premium, inicialmente sin
   comprar ni restaurar. Anotar cualquier error antes del reintento.
3. Cerrar y reabrir; comprobar persistencia. Después comprobar dictado con permiso de micrófono y sin
   solicitud de cámara, App Intents/Atajos e invitaciones Sandbox.
4. Registrar por separado catálogo, compra/restauración y notificaciones de este build distribuido.

La disponibilidad del build no acredita aún ese ensayo, App Review, cuenta sin historial, funcionamiento
offline ni reemplazo por una descarga de App Store. No se modifica producción, se cambia una suscripción,
se realiza una compra, se hace commit/push ni se presenta a App Review.

## Corrección del aviso Sandbox que ocultaba Ajustes — 29 de octubre

Después de distribuir **1.0 (3)**, el propietario informa en iPhone 16: «Datos de prueba me tapa el botón
de ajustes». Se reproduce visualmente en la preview existente del arranque: el `safeAreaInset` exterior
al `TabView` ocupa la zona de las barras de navegación interiores; el engranaje y el título no se ven.
Las previews anteriores no habían detectado correctamente este bloqueo de navegación.

Se sustituye ese inset por un `VStack(spacing: 0)` con dos elementos: aviso Sandbox de altura natural y
`AppRootView` en el espacio restante. La etiqueta del botón define una superficie táctil rectangular de
al menos 44 pt, que crece con Dynamic Type. Se conservan la explicación, las traducciones y la acción.
No se añaden offsets ni alturas fijas ni se cambia el selector de entorno, sesión o persistencia.

La auditoría independiente SwiftUI/accesibilidad y de estilo no encuentra problemas en este diff
acotado a `AppBootstrapView.swift`; el script de estilo informa cero candidatos. No se añade un test
unitario que replique la estructura de la vista: la aceptación exige ver y pulsar Ajustes en las pestañas.

Previews Xcode 27.1 / render iPhone 18 Pro Max iOS 27.2: español **Large, XXX Large y AX5** e inglés
**Large**, con el engranaje y el título visibles y separados del aviso:

- [Reproducción anterior](evidence/issue-54-toolbar-before.png).
- [Corregido ES Large](evidence/issue-54-toolbar-after-es-large.png).
- [Corregido ES AX5](evidence/issue-54-toolbar-after-es-ax5.png).

Build Debug y lanzamiento mediante Xcode correctos, sin errores/warnings en el log completo
`RunProject-Log-20261029-195920.txt`. Se usa el fixture local existente `-shopping-ui-validation`,
español, iPhone 17 Simulator iOS 27.2, para verificar las pulsaciones sin compras ni cuentas remotas.
El build comercial siguiente se identifica como **1.0 (4)**.

La interacción detecta un segundo detalle: el fondo material extendía el frame accesible del aviso
hasta la barra de estado, aunque la etiqueta se dibujaba en su fila. Se limita con
`.background(.bar, ignoresSafeAreaEdges: [])`. El cambio conserva la altura natural y no añade
coordenadas a la implementación. La revisión independiente no encuentra problemas; el nuevo lanzamiento
Debug (`RunProject-Log-20261029-200540.txt`) vuelve a compilar sin errores ni warnings.

El ensayo interactivo final mediante RocketSim confirma que Ajustes abre y cierra desde **Añadir** y
**Comprar**, y que el toque semántico en **Datos de prueba** abre la explicación y **Aceptar** la cierra.
El frame accesible del aviso queda en `(0, 62, 402, 44)`; el engranaje nativo permanece en
`(20, 120, 36, 36)`, separado y sin solape. Esto no acredita un objetivo táctil de 44 pt para el control
nativo ni VoiceOver físico. Se conservan capturas finales de [Añadir](evidence/issue-54-toolbar-final-add.png),
[Ajustes](evidence/issue-54-toolbar-final-settings.png), [Comprar](evidence/issue-54-toolbar-final-shop.png)
y [explicación](evidence/issue-54-toolbar-final-notice.png). La preview ES AX5 se regenera e inspecciona
con la corrección final del material a las 20:07 CET; Ajustes sigue visible.

La app de Simulator se detiene y se elimina el esquema temporal de validación, tras restaurar el esquema
comercial **SmartShoppingList / Fast**. No se alteran los argumentos del esquema comercial ni se incluyen
fixtures en Release. El ensayo físico de la corrección queda pendiente de la distribución de **1.0 (4)**.

### Archive comercial 1.0 (4)

El propietario desbloquea el Mac y autoriza expresamente crear el Archive y subir **1.0 (4)** mediante
**TestFlight Internal Only**. Xcode 27.1 crea el Archive a las **20:37 CET**:

```text
/Users/jesusf/Library/Developer/Xcode/Archives/2026-10-29/SmartShoppingList 29-10-2026, 20.37.xcarchive
```

El log completo `GetBuildLog/B327DB05-784E-4EAC-817A-D53262ED3FA6.txt` no contiene errores ni warnings.
La auditoría independiente confirma **Smart List**, **1.0 (4)**, bundle comercial, mínimo iOS 27.0,
SDK 27.1, Release/Swift 6/optimización y 101 fuentes comerciales. No hay `DEBUG`, fixtures activos ni
fuentes del diagnóstico. Se mantienen los textos de privacidad base y EN/ES, Apple Sign In y ambos
dominios. La firma local es válida; ejecutable/dSYM comparten UUID `0ebd2e07-88cb-352d-af67-5b4cbfc971ed`.
El `AppBootstrapView.swift` auditado tiene SHA-256
`aabc3d13a7fb45982910aa3e37418ac7deab9beedae82fcdb8ea877e1c93d68c`.

El primer intento de Validate App informa de autenticación no disponible. Se comprueba la cuenta/equipo
existente en Xcode y se reintenta una vez; la operación continúa sin cambiar credenciales ni permisos.
Las comprobaciones locales de interacción y previews de la corrección se reutilizan del paso anterior:
no ha cambiado código Swift desde ellas. Fast e Integration conservan su evidencia anterior; no se
presentan como suites ejecutadas de nuevo para esta corrección de layout.

**Validate App** termina correctamente a las **20:39 CET**. Se confirma visualmente el canal
**TestFlight Internal Only**, y Xcode registra la subida de **1.0 (4)** a las **20:40 CET**.
[Confirmación de Xcode](evidence/issue-54-commercial-build-4-upload-complete.png). App Store Connect
muestra la carga **Procesando**. Los artefactos de esa misma operación se exportan a
`/tmp/issue-54-commercial-1.0-4-testflight/`. Se restaura **SmartShoppingList / Fast / iPhone 17 (27.2)**
sin lanzar la app ni instalarla en el teléfono.

La revisión independiente del IPA exportado termina sin hallazgos: **Apple Distribution**, firma estricta
válida, `get-task-allow=false`, `beta-reports-active=true`, Apple Sign In, ambos dominios y privacidad
base/EN/ES. UUID y código corresponden al Archive 4 auditado; `ExportOptions.plist` confirma
`testFlightInternalTestingOnly=true`. SHA-256 del IPA:
`c2ed70a64a531165a8218edf76b214d4d46272d212f75fe1e6ae1c932f18d767`.

### Disponibilidad de la corrección en TestFlight

Apple finaliza el procesamiento. Se responde el cuestionario de cifrado con **Ninguno de los algoritmos
mencionados anteriormente**, conforme al mismo uso exclusivo de servicios criptográficos Apple auditado
en el build 3; esta corrección de layout no lo modifica. La app pasa a **Lista para las pruebas** y la
distribución automática la incorpora a **core**. A las **20:50 CET**, el grupo confirma **1 tester /
3 compilaciones**, con **1.0 (4) · Internos · En pruebas**. El tester Jesús Franco figura con
**iPhone 16 / iOS 27.2** y build 3 instalado. No se modifica la pertenencia del grupo ni se crea invitación.

Se guardan instrucciones de «Qué se debe probar» para actualizar sin borrar la app, abrir/cerrar Ajustes
desde Añadir y Comprar, comprobar texto grande y la explicación de Datos de prueba, y conservar el
contexto Sandbox. No se realizan compras ni restauraciones durante esta entrega.

- [Build 1.0 (4) en App Store Connect](https://appstoreconnect.apple.com/teams/69a6de96-c6fd-47e3-e053-5b8c7c11a4d1/apps/6814161606/testflight/ios/d2dddb83-083d-4784-8506-6e43278649c4).
- [Disponibilidad en core](evidence/issue-54-commercial-build-4-testflight-core.jpg).

La instalación y aceptación física del arreglo quedan pendientes del propietario. La disponibilidad
de TestFlight no acredita App Review ni producción. Los cambios de código/documentación permanecen
locales y sin commit en la rama de #54; no se hace commit, push, merge ni presentación a revisión.

### Ensayo físico posterior: Gratis tras restauración única

En la secuencia de prueba de **1.0 (4)**, el propietario informa que puede entrar en Premium y ve
**plan gratuito**, opciones mensual/anual y ninguna fecha de renovación/caducidad. A indicación del
ensayo pulsa **Restaurar compras una vez**; permanece Gratis sin aviso ni error. Sospecha que la compra
se hizo con el usuario del iPhone 11, pero no se da esa titularidad por confirmada. No ha informado de
una nueva compra en este recorrido ni ha confirmado aún Ajustes desde ambas pestañas/texto grande.

La revisión de fuente confirma que restaurar llama `AppStore.sync()` y vuelve a cargar la autoridad
del servidor y las transacciones. La ausencia de transacciones compatibles puede terminar sin aviso:
los tokens/productos no coincidentes se omiten y el store filtra otro entorno. No se concluye a partir
de la UI si hay ausencia de compras, caducidad o cuenta incompatible. Ajustes muestra nombre opcional
y sesión Apple, pero no identifica de forma inequívoca al titular ni al tester Sandbox de StoreKit.

La evidencia histórica de #39 registra cuentas distintas en ambos teléfonos y una restauración activa
en iPhone 16 a las 14:05 del 29/10; no acredita qué cuenta está usando ahora TestFlight ni vigencia actual.
La [documentación de Apple](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight/)
distingue el Sandbox automático de TestFlight del uso explícito de un Sandbox Apple Account, que requiere
salir de Contenido y compras para que ese tester se use. En este paso sólo se pide inspeccionar las
sesiones actuales, sin cambiarlas, repetir restauración, comprar ni borrar historial. La siguiente decisión
depende de distinguir sesión de Smart List, Contenido y compras y tester Sandbox activo.

### 30 de octubre — corrección del acceso tras cerrar Contenido y compras

El propietario confirma testers Sandbox y usuarios distintos en iPhone 11/16, y sesión real abierta
en Contenido y compras del iPhone 16. Tras indicarle cerrarla, se le pidió erróneamente abrir Smart List
«desde TestFlight»: TestFlight solicita autenticación real y rechaza el tester Sandbox con un aviso
sobre creación de cuenta iTunes. Ese acceso fallido no es una restauración de Smart List ni evidencia
del estado de la suscripción.

Se corrige el procedimiento conforme a Apple: con la beta ya instalada, conservar Contenido y compras
cerrado, comprobar el tester del iPhone 16 en Desarrollador y abrir **Smart List directamente desde su
icono de Inicio/Biblioteca**, sin pasar por TestFlight. El tester Sandbox se usa en Desarrollador, no en
el acceso normal de TestFlight/App Store. No hace falta salir y entrar de Sandbox si sigue conectado.
Después se propone una única restauración en ese contexto corregido; el resultado físico sigue pendiente.
No se crean cuentas iTunes, se borra historial ni se realiza otra compra en este paso.

### 30 de octubre — restauración sin derecho vigente, contrastada con Apple y Sandbox

El propietario abre la app instalada directamente desde su icono. Restaurar solicita la contraseña del
tester Sandbox y vuelve a Gratis sin aviso; después de refrescar repite una vez con el mismo resultado.
Confirma que conserva **Test1 → Aldi → Alpro**. No se le pide continuar repitiendo restauraciones ni
cambiar de cuenta. Esos datos corroboran continuidad del contexto; no prueban por sí solos su UUID.

La consulta autenticada de sólo lectura a App Store Server API, realizada a las **11:26:38 CET**, devuelve
para la cadena conocida del iPhone 16 `2000001258851316`:

- Estado Apple **2 / expired**, producto mensual y última transacción `2000001259202627`.
- Último periodo: **29/10/2026 19:28:41–19:58:41 CET**.
- Autorrenovación **desactivada**, sin gracia, reintento de cobro ni revocación.

Se contrasta a las **11:31:16 CET** mediante SELECT acotado a esa cadena en Railway, entorno
**sandbox → Postgres-7lx1**, sin modificar datos:

- Misma transacción, estado **expired**, `expires_at` **29/10 19:58:41 CET**, sin gracia y autorrenovación false.
- Comparación del `appAccountToken` de Apple con el titular persistido: **true**. El UUID no se publica.
- `account_premium_access.premium_until` **29/10 19:58:41 CET**; acceso vigente en el momento de consulta: **false**.
- Última verificación persistida: **30/10 11:26:04 CET**.

Apple y servidor coinciden: la restauración de esa suscripción caducada no concede Premium. No se
atribuye la causa del fin de la renovación ni se certifica todavía una compra/restauración activa en
el build 4. La consulta vincula Apple con el titular persistido; no extrae el identificador de la sesión
actual del teléfono. No hay evidencia que justifique alterar la concesión o reabrir #39.

La revisión iOS confirma que el Sandbox resuelto en Release mantiene origen, namespace y Keychain
de Debug. `AppStore.sync()` seguido de una carga sin derechos compatibles puede finalizar sin aviso;
la UI oculta las fechas cuando no hay Premium. Se registra como pendiente de feedback: comunicar el
resultado de restaurar sin deducir «caducada» únicamente de una secuencia vacía de StoreKit.

**Siguiente ensayo:** una compra mensual Sandbox iniciada por el propietario desde la app ya instalada,
con las mismas cuentas, comprobando el carácter de prueba de la hoja Apple. Registrar Premium/fecha
o el error exacto y contrastar la nueva transacción con el servidor. Quedan abiertos Ajustes en ambas
pestañas/texto grande, restauración con derecho activo, reinicio y demás aceptación física de #54.
En este diagnóstico no se cambia Swift, configuración, credenciales, suscripciones ni datos remotos.

### 30 de octubre — compra mensual desde TestFlight confirmada en el backend

El propietario informa que compra la mensual en Sandbox desde el iPhone 16 y ahora ve **Premium** con
renovación a las **13:03**. La comprobación posterior es de sólo lectura; la compra la inicia el propietario.

La consulta a Apple de las **12:34:56 CET** confirma, en la misma cadena `2000001258851316`, la nueva
transacción **`2000001259554781`**, producto `com.plusprojects.SmartShoppingList.premium.monthly`,
estado **1 / subscribed**, periodo **30/10/2026 12:33:33–13:03:33 CET**, autorrenovación activa, sin
gracia ni revocación. El token coincide con el titular conocido; no se publica el UUID de la cuenta.

Railway **sandbox → Postgres-7lx1**, comprobado mediante consultas SELECT acotadas:

- **12:34:49 CET:** `app_store_subscriptions` contiene esa misma transacción/producto en estado
  **subscribed**, con caducidad **13:03:33 CET**, autorrenovación true y sin gracia; verificación
  persistida **12:33:39 CET**. `account_premium_access.premium_until` coincide y el acceso actual es true.
- **12:35:18 CET:** `app_store_transactions` devuelve una fila para la nueva transacción en **Sandbox**,
  vinculada a la misma cadena y al mismo titular que Apple y la suscripción. Registro verificado a las
  **12:33:35 CET**. No hay cambio de propietario en este recorrido.

La historia de notificaciones V2 de Apple, consultada una vez a las **12:35:54 CET** para el intervalo
**12:30–12:35:54 CET**, todavía no devuelve un evento de esa transacción/cadena. No se dispone de un UUID
de notificación para correlacionar su recibo SQL; esa ausencia en este checkpoint no demuestra fallo
ni acredita entrega. No se emite TEST ni se fuerza reenvío. La recepción V2 de esta compra queda pendiente.

La fecha de la app coincide con Apple y con el acceso concedido por el backend. Esta evidencia valida
la compra mensual observada en el build distribuido y la persistencia de su derecho Sandbox. No acredita
todavía renovación posterior, restauración con derecho activo, reinicio, App Review ni producción.

### 30 de octubre — recibo V2 persistido, correlación con Apple pendiente

El propietario solicita comprobar de nuevo la notificación V2. La consulta de sólo lectura a
`app_store_notifications` en **Sandbox**, acotada desde **12:30 CET**, devuelve a las **12:38:30 CET**
una fila recibida a las **12:33:35 CET**:

- UUID `73cbe432-e494-4f83-89c4-df5a07916ea1`.
- SHA-256 del payload firmado: `20cfbd6d80f66e71337c6b7f707dc21adfd1069c53d968ea9a5e86b2539ef474`.

Esto acredita un recibo V2 persistido en el backend. La cercanía temporal a la compra no basta para
atribuirle una transacción o un tipo/subtipo: la tabla sólo conserva entorno, UUID, hash y hora.

La historia Apple consultada a las **12:38:52 CET**, y la comprobación del formato de respuesta a las
**12:40:36 CET**, devuelven **HTTP 200**, `notificationHistory=[]` y `hasMore=false` para un intervalo
que incluye la compra. Se revisan endpoint Sandbox, milisegundos UTC, cuerpo JSON, ausencia de filtros
restrictivos, nombre del campo y paginación. No se omite un evento por un filtro local. El UUID/hash
persistido aún no puede correlacionarse con Apple; tampoco se acredita su resultado HTTP de entrega.
No se interpreta el historial vacío como fallo de recepción ni se emite TEST/reenvío.

Apple a las **12:38:52 CET** y SQL a las **12:39:05 CET** siguen mostrando la nueva mensual activa hasta
**13:03:33 CET**, autorrenovación habilitada y Premium vigente. El siguiente ensayo físico es cerrar
completamente la app, abrirla desde su icono, comprobar datos/Premium y restaurar una vez mientras
el derecho siga activo. Ese ensayo y la correlación exacta de la V2 quedan pendientes del resultado.

### 30 de octubre — reinicio y restauración con Premium activo confirmados

El propietario confirma en el iPhone 16, dentro del ensayo de **1.0 (4)**:

- Cierra completamente Smart List y vuelve a abrirla: conserva **Test1 → Aldi → Alpro** y **Premium**
  con la misma fecha que antes del reinicio.
- Pulsa **Restaurar compras una vez** y mantiene **Premium**.

Se acepta este recorrido físico de reinicio y restauración con derecho activo a partir de su
observación. No es una reinstalación ni una prueba de recuperación desde otra cuenta/dispositivo,
ni acredita por sí sola renovación automática o entrega/correlación V2. No se repite compra/restauración.

**Siguiente ensayo:** comprobar Ajustes desde Añadir y Comprar, la explicación de Datos de prueba y
el acceso a ambos controles con texto grande, para cerrar la aceptación física del arreglo de layout
que motivó el build 4. La siguiente renovación, correlación V2 y demás pruebas de distribución siguen
pendientes. En este paso sólo se actualiza la evidencia; no se modifica código ni servicios remotos.

### 30 de octubre — aceptación física de Ajustes y Datos de prueba

El propietario confirma en el iPhone 16 que **Ajustes** y **Datos de prueba** responden y no se tapan
en **Añadir** ni en **Comprar**, también con el **texto al máximo**. Queda aceptado el arreglo físico
de la regresión de layout del build 3, distribuido en **1.0 (4)**. Esta observación no acredita por sí
sola VoiceOver ni el resto de la accesibilidad de la app.

No hace falta repetir compra, restauración ni el ensayo de estos controles. Los siguientes recorridos
del build comercial son dictado, confirmación y envío de un producto de prueba, App Intents e invitaciones Sandbox;
se mantienen separados la renovación automática y la correlación exacta de notificaciones V2.

### 30 de octubre — correlación exacta de la V2 de compra completada

Una nueva consulta de lectura a la historia Apple a las **12:56:04 CET** devuelve **HTTP 200**, una
notificación y `hasMore=false`. El evento ahora disponible es **SUBSCRIBED / RESUBSCRIBE**, firmado a
las **12:33:34.219 CET**, para la cadena `2000001258851316` y la compra `2000001259554781`.

Coinciden exactamente el UUID `73cbe432-e494-4f83-89c4-df5a07916ea1` y el SHA-256
`20cfbd6d80f66e71337c6b7f707dc21adfd1069c53d968ea9a5e86b2539ef474` con el recibo SQL de las **12:33:35 CET**.
Apple registra un intento a las **12:33:34.403 CET**, con `sendAttemptResult=SUCCESS`; no se deduce un
código HTTP numérico del webhook a partir de ese campo. Queda confirmada la correlación y entrega de
la V2 de esta compra Sandbox. Los checkpoints anteriores de historial vacío se conservan como historia;
no representaban por sí solos un fallo de entrega. No se emite TEST, reenvío ni una nueva compra.

Esto no acredita todavía una notificación de renovación: sigue pendiente observar el siguiente periodo.

### 30 de octubre — dictado y envío a la lista aceptados

El propietario confirma en el iPhone 16, dentro del ensayo de **1.0 (4)**, que el dictado reconoce
correctamente el producto de prueba y **Aldi**. Lo añade a **Test1**, aparece en la lista y **Alpro**
permanece intacto. Queda aceptado ese recorrido de dictado, interpretación, confirmación y envío en
la app comercial distribuida. Su respuesta no especifica si aparecieron solicitudes de permisos.

El siguiente ensayo corresponde a **Atajos/App Intents**, para comprobar la resolución del entorno
y el acceso a la sesión Sandbox al ejecutar desde el sistema con la app cerrada y el teléfono
desbloqueado. Las invitaciones y la siguiente renovación automática se mantienen como pruebas separadas.
En este registro no se modifica código, configuración ni datos remotos.

### 30 de octubre — Siri abre la app y añade directamente a la lista

El ensayo se orienta a la acción publicada para lista compartida mediante Siri, sin necesidad de crear
un atajo manual. El propietario informa de una transcripción aproximada al hablar rápido, con varios
«unos», y acepta el producto propuesto. Después confirma expresamente que **Smart List se abrió** y
el producto aparece en **Comprar → Test1 → Aldi**, **sin quedarse en el borrador**.

Queda aceptada la activación mediante Siri y el envío directo al contexto Sandbox conocido del build
**1.0 (4)**. No se usa el texto exacto del ejemplo como criterio de aceptación ni se afirma precisión
perfecta del reconocimiento de voz. No se extiende esta evidencia a Siri en inglés, teléfono bloqueado,
acción de borrador o recuperación de resultados inciertos. No se repite la operación ya confirmada.

### 30 de octubre — primera renovación automática y su V2 confirmadas

Apple consultado a las **13:24:33 CET** confirma una nueva mensual en la misma cadena `2000001258851316`:
transacción **`2000001259567216`**, estado **subscribed**, periodo **13:03:33–13:33:33 CET**, autorrenovación
activa, titular coincidente y sin gracia ni revocación. SQL Sandbox a las **13:24:32 CET** coincide en
transacción, periodo, estado y `premium_until`, con Premium vigente; verificación persistida **13:13:30 CET**.

La historia Apple incluye **DID_RENEW**, firmado a las **13:02:36.830 CET**, con intento
**13:02:36.976 CET / SUCCESS**. El SELECT exacto de las **13:25:12 CET** en
**sandbox → Postgres-7lx1 → app_store_notifications** confirma:

- UUID `5b89a7cc-6873-44cf-a533-6ab0c79a6db2`.
- SHA-256 `a2087f92e56bd21bbaed159ab22dc3a3c1bdc136ae586d3dbe9bb2131e3bcf22`, igual al payload de Apple.
- Recibido a las **13:02:39 CET**.

Se conservan las horas tal como las proporcionan Apple y SQL: la firma/entrega precede al inicio del
nuevo periodo. Quedan contrastados renovación y recibo V2; no se ha solicitado otra compra, TEST,
reenvío ni cambio de suscripción. La fecha mostrada por la app después de esta renovación queda por
observar, separada de esta comprobación del servidor.

El propietario dispone del iPhone 11 con una versión anterior. La siguiente prueba de invitaciones
debe mantener ambas cuentas y usar el iPhone 16 con TestFlight como receptor; el contexto Sandbox y
la capacidad del grupo emisor se comprobarán antes de tratar el enlace como evidencia de distribución.

### 30 de octubre — corrección del contexto del iPhone 11 y aviso recurrente

El propietario precisa que el **iPhone 11 probablemente tiene la app de producción**, no una de las
instalaciones de TestFlight. Se retira la suposición de que la versión anterior disponible sirve como
emisor Sandbox. No se crean/comparten invitaciones ni se cambian cuentas o instalaciones. La prueba
entre cuentas requiere primero un segundo cliente Sandbox identificado; el backend real permanece intacto.

En el iPhone 16 informa que al volver del segundo plano aparece siempre un aviso de resultado de envío
sin confirmar. La [captura original](evidence/issue-49-foreground-submission-warning-testflight-1.0-4.png)
de las **12:51** lo muestra sobre Premium. Se registra en la issue existente **#49** y en su
[informe](ui-controls-and-refresh-review.md#seguimiento-vigente--30-de-octubre-aviso-de-envío-al-volver-a-primer-plano).
El mensaje genérico también se utiliza para errores de consultas GET y respuestas inválidas; no acredita
por sí solo una mutación pendiente ni un error de compra. La revisión encuentra refrescos completos
repetidos al volver a primer plano, pero aún no identifica la petición/causa física exacta del fallo.

Se prioriza reproducir y corregir este comportamiento antes del siguiente build comercial, conservando
errores relevantes, autoridad de sesión/grupo y recuperación idempotente. La investigación de #49 y su
aceptación física no se dan por terminadas. Este paso sólo actualiza evidencia y seguimiento; no cambia
código, despliegues, datos, cuentas ni la configuración de distribución.

### 30 de octubre — preparación del iPhone 11 para TestFlight y alcance de #49

El propietario plantea incorporar el iPhone 11 a TestFlight y usar después su tester Sandbox de compras.
La autorización de TestFlight corresponde al tester, no a un alta por cada dispositivo. Si se reutiliza
el acceso del tester del iPhone 16 no hace falta duplicarlo; una cuenta distinta requiere comprobar su
autorización interna para **1.0 (4)**. Se pregunta qué cuenta real usará el iPhone 11; aún no se modifica
ningún tester, cuenta, permiso o instalación. La página anterior de App Store Connect mostraba core/4,
pero al recargar la sesión ha caducado: esa vista previa no se presenta como inventario actualizado.

Para listas/invitaciones basta instalar la beta y confirmar **Datos de prueba**; no es necesario cerrar
Contenido y compras. Para probar compras con el tester Sandbox específico, la secuencia será instalar
primero con la cuenta real autorizada, cerrar después Contenido y compras, comprobar el tester en
Desarrollador y abrir Smart List desde su icono. No se utiliza la cuenta Sandbox para acceder a TestFlight,
ni se cambia iCloud o la sesión de Smart List como parte de ese acceso. La sustitución de la app no se
describe como migración de datos de producción al entorno de pruebas.

Fuentes Apple: [TestFlight](https://developer.apple.com/testflight/),
[testers internos](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/),
[pruebas con Sandbox](https://developer.apple.com/documentation/storekit/testing-in-app-purchases-with-sandbox).

Respecto al aviso, el propietario acepta resolverlo junto a los refrescos si no hay un arreglo pequeño.
La auditoría no identifica una causa física determinista; cambiar sólo el texto o silenciar el aviso
no resuelve de forma completa el problema. Se mantiene como unidad conjunta en #49 antes del siguiente
build comercial, sin cambio Swift, rebuild ni nueva distribución en este paso.

### 31 de octubre–7 de noviembre — iPhone 11 instalado y aceptación bloqueada por cupo

El propietario confirma que ha aceptado la invitación de TestFlight, instalado **1.0 (4)** en el
**iPhone 11** y observado **Datos de prueba**. Se propone enviar desde el iPhone 16 una invitación
a **Test1** y comprobar después **Aldi → Alpro** en el receptor. La instalación y la identificación
visual del entorno quedan realizadas; no requieren repetición para continuar este ensayo.

El **7 de noviembre** informa de que no puede aceptar por el límite de grupos del plan gratuito.
Confirma también Gratis en el iPhone 16. El contrato vigente admite una pertenencia total en Gratis
y cinco en Premium; el plan del administrador no amplía el cupo personal del invitado. Elegir otro
grupo gratuito sólo cambia el acceso entre pertenencias existentes y no libera una plaza.

Al orientar la prueba de Premium en el iPhone 11, el propietario señala que Ajustes sólo muestra
la invitación pendiente y acceso con Apple. Se corrige el orden: iniciar primero la sesión dentro
de Smart List, manteniendo separadas la identidad de la app y la del tester de compras Sandbox.
Después comunica **«Ya soy premium en el iPhone 11 pero sigo con el cupo de grupos lleno»** y pide
conservar este resultado para no repetir la prueba. Esta declaración acredita el resultado que
observa en la app; todavía no hay una nueva correlación de transacción, estado Apple y backend.

El propietario confirma a continuación **cinco grupos en el selector: A·1, A·2, B (el gratuito), C y D**.
Con ese inventario, el bloqueo de una sexta pertenencia corresponde al máximo Premium de cinco.
Queda registrada la observación física de **Premium comunicado + cinco grupos + aceptación bloqueada**;
no se atribuye este resultado a un fallo de refresco ni se usa para acreditar una nueva comprobación
del backend. La UI utiliza la capacidad de cuenta tanto para presentar Premium como para habilitar
la aceptación; la compra ya intenta actualizar sesión y grupos antes de terminar.

**Continuidad de la prueba:** instalación, Datos de prueba, recorrido de acceso, resultado Premium
comunicado y bloqueo con cinco grupos ya constan como realizados. No se repiten compra, restauración
ni ensayo de cupo completo para continuar. La aceptación de Test1 permanece **pendiente** hasta liberar
una plaza mediante la salida de un grupo de prueba elegido expresamente por el propietario. Se propone
conservar B y usar Miembros y administración en el grupo del que quiera salir. Si es el último miembro,
Cerrar grupo y salir impide reabrirlo; no se presume que ningún grupo concreto sea prescindible. Si
administra un grupo con otros miembros, debe completar antes el traspaso. No se ha ejecutado ninguna
salida, cierre ni aceptación desde las herramientas.

La próxima comprobación es **cinco → cuatro pertenencias tras salir → cinco al aceptar Test1**,
conservando los otros grupos. Si la invitación procede de una sesión anterior, comprobar su caducidad
(24 horas desde su creación) y generar otra sólo cuando sea necesario. Quedan por observar la
incorporación efectiva a Test1 y la sincronización entre las dos cuentas.

### 7 de noviembre — A·2 cerrado y vista previa de Test1 recuperada

El propietario confirma **salida y cierre de A·2** en el iPhone 11 y selección posterior de **B** como
grupo activo. Continúa desde cuatro pertenencias según el inventario anterior y esa salida; no se
repite el cierre. En Invitación pendiente aparece **«Accede y actualiza para consultar el grupo antes
de aceptar»**, sin botón Aceptar, con Descartar habilitado.

La revisión de fuente identifica un recorrido determinista compatible con el síntoma:
`selectGroup` llama a `clearGroupPresentation`, que pone `invitationPreview=nil` y conserva
`pendingInvitation`. Después carga el grupo activo sin volver a consultar la invitación. La vista
oculta Aceptar y usa ese texto genérico cuando no hay vista previa, incluso con sesión abierta.
Este mensaje no acredita por sí solo cierre de sesión, falta de Premium o invitación caducada.

Se pide **Actualizar una sola vez en Ajustes**. El propietario confirma que reaparecen **Test1 y
Aceptar invitación**. Queda realizada la recuperación de la vista previa en el build **1.0 (4)**;
el defecto al cambiar el grupo activo se recoge en el [seguimiento de refrescos](ui-controls-and-refresh-review.md#7-de-noviembre--invitación-pendiente-sin-vista-previa-al-cambiar-grupo).
No se ha cambiado Swift ni distribuido un arreglo en este paso.

**Punto de continuación:** pulsar Aceptar invitación una vez y comprobar Test1 → Aldi → Alpro en
el iPhone 11, conservando A·1, B, C y D. Aceptación y sincronización siguen pendientes hasta la
confirmación física. No repetir instalación, compra, comprobación de cupo completo, cierre de A·2
ni el refresco de recuperación ya confirmado; tampoco descartar o regenerar este enlace vigente.

### 7 de noviembre — invitación aceptada y lista compartida visible en el iPhone 11

El propietario confirma **«aceptado, veo Aldi y Alpro y dos productos más»** tras pulsar Aceptar
invitación. Quedan realizadas en **TestFlight 1.0 (4), iPhone 11, Datos de prueba** la incorporación
a **Test1** y la lectura inicial de **Aldi → Alpro**, junto con otros dos productos cuyos nombres no
se especifican. No se repiten estas acciones para avanzar. La respuesta no incluye una comprobación
expresa del selector completo A·1/B/C/D/Test1; no se afirma esa inspección por inferencia.

El ensayo distingue el bloqueo correcto con cinco pertenencias de la pérdida de vista previa al
cambiar el grupo activo. La salida y cierre de A·2, el refresco manual que recupera Test1 y la
aceptación posterior ya constan como hechos comunicados por el propietario. El defecto de refresco
sigue pendiente de corrección; el refresco manual no equivale a una versión corregida.

**Guion de sincronización, cuyo resultado se registra a continuación:** añadir desde el iPhone 11 un único producto identificable
de prueba a Test1/Aldi, comprobar su aparición una sola vez en el iPhone 16 tras actualizar, confirmar
la compra de sólo ese producto desde el 16 y comprobar tras actualizar el 11 que deja de estar pendiente.
Conservar Alpro y los otros productos. Este recorrido comprobará escritura del miembro invitado y
lectura de cambios en ambos sentidos; marcar una casilla local sin confirmar la compra no lo acredita.

### 7 de noviembre — sincronización entre iPhone 11 y 16 confirmada

El propietario confirma la ejecución del guion con el producto **Prueba sync 7 noviembre**:

- El producto añadido desde el iPhone 11 aparece **una sola vez** en el iPhone 16.
- Tras **Confirmar compra** en el 16, deja de estar pendiente también en el 11.
- **Alpro y los otros dos productos siguen presentes**.

Quedan aceptadas físicamente la escritura del miembro invitado, su lectura por la otra cuenta y la
lectura en el 11 de la compra confirmada desde el 16, usando las actualizaciones manuales del guion.
Esto no acredita actualización en tiempo real sin refresco, una simulación de respuesta perdida ni
toda la matriz de idempotencia; acredita una única aparición en el recorrido ejecutado.

Instalación, compra de prueba comunicada, cupo Premium lleno, salida/cierre de A·2, recuperación de
vista previa, aceptación de Test1 y sincronización ya tienen resultado registrado. No reiniciar ese
guion para avanzar; una futura corrección requiere sólo la regresión que afecte a su alcance. El fallo
de vista previa al cambiar grupo continúa pendiente en el seguimiento de #49.

**Guion de arranque sin red y recuperación, iniciado a continuación:** cerrar la app en el iPhone 11,
activar modo avión con Wi-Fi apagado y abrirla desde su icono. Registrar si resuelve Datos de prueba
con evidencia disponible, muestra recuperación o queda esperando. No exigir listas compartidas
disponibles offline ni interpretar un error de red como sesión perdida. Restaurar la conexión y usar
Reintentar en la recuperación, o Actualizar si ya abrió la app; comprobar Datos de prueba y
Test1/Aldi/Alpro con los otros dos productos. No introducir compras ni escrituras offline en este ensayo.

### 7 de noviembre — arranque sin red llega a Añadir y Comprar con mensajes de grupo ausente

Durante el ensayo en el iPhone 11, el propietario comunica:

- **Comprar:** «Configura tu grupo en Ajustes para compartir una lista de la compra» y Abrir Ajustes.
- **Añadir:** Añadir a mano, «Abre ajustes para unirte a un grupo o crear uno» y «Tus productos se
  guardan en este dispositivo hasta que tengas un grupo».

Confirma expresamente que **todavía estaba sin conexión**, antes de recuperar Internet y actualizar.
La app ha llegado a las pantallas funcionales; no comunica una pantalla de recuperación del arranque.
En esta respuesta no confirma expresamente la presencia del indicador Datos de prueba. No se da por
perdida la cuenta, la sesión ni las pertenencias por esos mensajes, ni por superada la recuperación.

La fuente muestra una distinción pendiente: Comprar usa `hasLoaded && !isBusy && groups.isEmpty`
y Añadir usa `group == nil && groups.isEmpty` para sugerir crear/unirse a un grupo, sin exigir que
esa ausencia se haya verificado con el servidor. En un arranque sin red, la colección aún no cargada
puede estar vacía. El problema de presentación se registra con #49; no acredita eliminación remota.

**Punto de continuación:** restaurar Internet en el iPhone 11, pulsar Actualizar una vez en Ajustes
y comprobar Datos de prueba y Test1 → Aldi → Alpro con los otros dos productos. Registrar cualquier
aviso y si conserva la cuenta. No crear grupos, cerrar sesión, comprar de nuevo ni repetir el arranque
offline ya observado. Falta el resultado físico de esta recuperación.

### 7 de noviembre — recuperación automática tras el arranque sin red confirmada

El propietario confirma que, al recuperar Internet en el iPhone 11, **la app se actualiza sola sin
pulsar Actualizar**. Reaparecen **Datos de prueba y Test1** y, al seleccionar **Aldi**, se muestran
**Alpro y los otros dos productos, sin ningún aviso**. La recuperación no requiere otra cuenta,
compra ni creación de grupos. Queda aceptado este recorrido físico de arranque sin red y recuperación
del contexto/lista en **TestFlight 1.0 (4)** con el estado local disponible en ese dispositivo.

El resultado no identifica el disparador exacto del refresco automático; no se presenta como prueba
de un observador de conectividad ni de recuperación sin transición de ciclo de vida. No se ha medido
una ausencia de evidencia local de AppTransaction, ni se ha observado aquí la pantalla de Reintentar.
El mensaje que sugiere crear/unirse a un grupo mientras la consulta está pendiente sigue siendo una
incidencia de presentación registrada con #49. La recuperación correcta no corrige ese texto.

No repetir instalación, compras, invitaciones, sincronización ni este arranque offline para avanzar.
**Guion de VoiceOver, cuyo resultado se registra a continuación:** botón Datos de prueba, lectura y
cierre de su aviso con Aceptar, retorno del foco y acceso a Ajustes/Cerrar en Añadir y Comprar.
Las pruebas de toque y texto máximo ya realizadas no acreditan esa interacción con lector de pantalla.
Una futura corrección de los hallazgos requiere una regresión acotada a lo modificado.

### 7 de noviembre — VoiceOver confirmado y cierre de esta ronda manual

El propietario confirma en el ensayo del iPhone 11 con **TestFlight 1.0 (4)** que VoiceOver lee la
explicación completa, permite abrir y cerrar **Datos de prueba y Ajustes desde Añadir y Comprar**, y
que **el foco no se pierde ni queda atrapado**. Queda aceptado este recorrido, sin extender el resultado
a toda la accesibilidad de la app.

El propietario cuestiona la prioridad de probar un control ausente de producción. La fuente de
`AppBootstrapView` limita Datos de prueba al entorno Sandbox. Esta comprobación complementaria cubre
la navegación de la distribución de pruebas y su convivencia con Ajustes; no es un requisito de la
interfaz de producción ni acredita App Review o el cambio TestFlight/App Store.

**Siguiente paso recomendado:** terminar esta ronda manual del build 4 y priorizar los hallazgos
registrados con #49: vista previa de invitación perdida al cambiar grupo, mensajes de grupo ausente
cuando aún no se ha podido consultar el servidor y refrescos/avisos de primer plano. En este último
caso sigue pendiente identificar el error físico que dispara la alerta. Después corresponde probar
sólo las regresiones afectadas en un nuevo build. No se repiten los recorridos ya aceptados para
empezar esas correcciones. Esta anotación no implica código corregido, un nuevo envío ni preparación
para producción completada; los requisitos de publicación y backend conservan sus propios pendientes.
