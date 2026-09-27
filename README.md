# SmartShoppingList

[Español](#es) · [English](#en) · [Documentación / Documentation](#docs)

<a id="es"></a>

## Español

Lista de compra compartida para iPhone y iPad, desarrollada para **ACoding Hackathon 2026 · 27 de septiembre**. Dicta o escribe los productos y la tienda para añadirlos a la lista de tu grupo. Durante la compra, marca los productos y confirma solo los seleccionados; los demás siguen pendientes.

### Qué puedes hacer

- **Compartir la compra:** iniciar sesión con Apple, crear un grupo e invitar a otra persona mediante un enlace. Cuenta, grupo e invitaciones se gestionan desde **Ajustes**.
- **Añadir por voz o texto:** Speech transcribe y Foundation Models identifica productos, cantidades y tiendas. Si los datos están completos, **Confirmar** en el aviso los añade directamente a la lista. El borrador se abre para corregir errores de identificación, completar datos o cuando eliges **Editar**.
- **Añadir a mano:** introducir producto, cantidad opcional y tienda sin Apple Intelligence. Con un grupo activo, **Añadir producto** guarda esa entrada directamente; sin grupo, **Guardar producto** la conserva en el borrador local. Los controles manuales se muestran sin modelo, sin grupo o al recuperar y editar una propuesta.
- **Consultar y comprar:** elegir una tienda o buscarla por voz, actualizar sus pendientes, editar o cancelar productos y confirmar una compra parcial. Los checks son locales hasta pulsar **Confirmar compra**.
- **Usar Siri y Atajos:** añadir al borrador o a una tienda existente de la lista mediante dos acciones independientes. La acción de lista pregunta por producto, cantidad y tienda; si la tienda es desconocida o ambigua, abre el borrador para revisarlo.
- **Trabajar en español o inglés:** interfaz, permisos, avisos y acciones de Siri localizados. Los nombres introducidos por las personas conservan su idioma.

El servidor conserva las entradas compradas y canceladas, sus datos originales y, cuando hay compra, quién la confirmó y cuándo. Este es el historial mínimo; no hay una pantalla de historial. Los reintentos de una misma operación conservan su identidad para evitar duplicados. Dos altas voluntarias del mismo producto son operaciones distintas.

### Requisitos y tecnología

| Componente | Requisitos |
|---|---|
| App | **Smart List** en el dispositivo; iPhone/iPad con iOS/iPadOS **27.0 o posterior**. Mac y Mac Catalyst no son destinos de la app. |
| Compilación iOS | **Xcode 27.1 o posterior**, con SDK 27.1 o posterior. La adaptación a iPhone Duo usa APIs protegidas por disponibilidad. |
| Voz e IA | Permiso de micrófono y soporte de transcripción para el dispositivo y el idioma. La interpretación requiere un dispositivo y un modelo compatibles, Apple Intelligence activada y soporte del idioma elegido. La consulta de tiendas por voz y Siri tradicional no requieren Foundation Models. |
| Servidor nativo | **Swift 6.4**, macOS **26.2 o posterior** y Docker Desktop para PostgreSQL local. También se proporciona un contenedor Linux. |
| Acceso compartido | Conexión de red, firma con Sign in with Apple y Associated Domains, backend HTTPS y PostgreSQL configurados. |

La app utiliza **Swift 6, SwiftUI, concurrencia estricta, Speech, Foundation Models y App Intents**, sin dependencias de terceros. Conserva el borrador en almacenamiento local y las credenciales en Keychain. El servidor usa **Vapor 4.122.2, Fluent/PostgreSQL y JWTKit**; `Package.resolved` fija las dependencias. Los tests de lógica de ambos componentes usan **Swift Testing** y los targets propios tratan warnings como errores, con [excepciones externas documentadas](docs/dependency-exceptions.md).

### Ejecutar la app

Desde la raíz del repositorio:

```bash
open ios/SmartShoppingList/SmartShoppingList.xcodeproj
```

1. Selecciona el esquema **SmartShoppingList** y un iPhone, iPad o simulador compatible.
2. En **Signing & Capabilities**, configura la firma para el App ID autorizado. El proyecto usa `com.plusprojects.SmartShoppingList`, Sign in with Apple y Associated Domains.
3. Comprueba `SHARED_API_BASE_URL` y `SHARED_INVITATION_ORIGIN` en **Build Settings**, tanto en Debug como en Release. El checkout apunta al [servicio HTTPS del proyecto](https://smartshoppinglist-production.up.railway.app/hello).
4. Ejecuta la app. Abre **Ajustes → Preparar acceso con Apple**, continúa con el botón nativo de Apple y crea un grupo o acepta una invitación. La entrada manual y el borrador local permiten explorar la app sin un grupo.

El acceso al servicio existente requiere firma y capacidades compatibles con su App ID registrado. Para desplegar una instancia propia, configura conjuntamente la identidad Apple del servidor, los identificadores de la app, ambos orígenes HTTPS, Associated Domains y el archivo AASA; cambiar solo el equipo de firma no configura la colaboración. La [guía del recorrido compartido](docs/setup/shared-shopping.md) detalla las variables y los secretos necesarios. Ninguna clave privada pertenece al cliente ni al repositorio.

### Ejecutar el servidor y sus pruebas

Con Docker Desktop iniciado, desde la raíz:

```bash
cd server
docker compose --profile testing up -d --wait db db-test
swift build --build-tests --force-resolved-versions
swift test --skip-build
swift run --skip-build SmartShoppingListServer serve --hostname 127.0.0.1 --port 8081
```

En otra terminal:

```bash
curl --fail http://127.0.0.1:8081/hello
```

`db` utiliza el puerto 5432 y conserva los datos de desarrollo en el volumen `db_data`. `db-test` utiliza el puerto 5433 y una base temporal aislada. Las credenciales de Compose son ejemplos locales. El servidor aplica sus migraciones al arrancar; `/hello` comprueba respuesta HTTP, no un inicio de sesión ni una consulta a PostgreSQL.

El arranque local y las pruebas automáticas no necesitan credenciales Apple. Para autenticar usuarios reales, completa la configuración de `server/.env.example` en un `.env` local o en el gestor de secretos del alojamiento. El [README del servidor](server/README.md) amplía los comandos, variables y ejecución Linux. Una app física necesita un backend HTTPS accesible; `127.0.0.1` del Mac no es una URL de servidor válida para el iPhone.

Para detener el entorno, desde `server/`, usa `docker compose --profile testing stop`. Conserva el volumen de desarrollo y descarta los datos temporales de pruebas. No uses `down -v` si necesitas conservar la base. Una recuperación del servicio alojado requiere tanto la copia de PostgreSQL como las claves de cifrado de concesiones Apple, según la [guía de configuración](docs/setup/shared-shopping.md).

### Demostración con dos personas

Prepara dos clientes instalados, dos Apple IDs diferentes, conexión al mismo backend y una de las cuentas sin grupo para aceptar la invitación. Para este ejemplo, usa la app y Siri en español. Para la parte de IA, utiliza un entorno con Foundation Models disponible; comprueba por separado la captura de voz.

1. En el primer cliente, abre **Ajustes**, prepara el acceso con Apple, inicia sesión y crea un grupo. Desde **Invitaciones → Crear invitación → Compartir invitación**, envía un enlace al segundo usuario.
2. Abre el enlace en el segundo cliente, inicia sesión si es necesario y pulsa **Aceptar invitación** en **Ajustes**.
3. En **Añadir**, dicta «Comprar jabón, cerveza y yogures en Mercadona» y pulsa **Terminar dictado**; si usas el campo de texto, escribe los productos y la tienda y pulsa **Interpretar texto**. Cuando la identificación es correcta, **Confirmar** en el aviso añade los productos directamente a la lista. Si faltan datos o hay errores, corrígelos en el borrador; **Editar** también permite abrirlo voluntariamente. Sin IA, introduce cada producto mediante **Añadir a mano → Añadir producto**.
4. En el segundo cliente, abre **Comprar**, selecciona Mercadona y pulsa **Actualizar**. Deben aparecer los productos compartidos; la sincronización se solicita expresamente.
5. Añade dos productos más para tener cinco pendientes. Marca tres y pulsa **Confirmar compra · 3**. Actualiza el otro cliente: deben quedar los dos no seleccionados.
6. Desliza una fila a la izquierda para editar un pendiente y guarda los cambios. En otra fila, **Quitar → Ya no lo necesitamos** cancela el producto sin registrarlo como comprado. Cierra y vuelve a abrir la app para comprobar los datos conservados.
7. Como extra, di «**Añade a mi lista de la compra en Smart List**». Responde producto, cantidad y una tienda existente. Tras confirmar el servidor, **Ver lista** abre esa tienda. La acción **Añadir producto al borrador** conserva la revisión local.

El recorrido manual no acredita voz o IA. Siri usa frases publicadas y preguntas explícitas; la comprensión conversacional de Siri AI queda fuera de esta versión.

### Pruebas y alcance de la validación

- **iOS:** selecciona **Fast** o **Integration** en el esquema y ejecuta **Product → Test**. Ambos planes usan Swift Testing; Fast cubre reglas y coordinación, e Integration persistencia local y Keychain. No necesitan micrófono, modelos ni una sesión Apple real.
- **Servidor:** los comandos anteriores compilan y ejecutan pruebas HTTP con PostgreSQL aislado, autorización, concurrencia, compras, cancelaciones e idempotencia. `swift build --build-tests` por sí solo no ejecuta pruebas. La [validación Release del 27 de septiembre](docs/validation/server-release-2026-09-27.md) acredita 82 pruebas en 8 suites y el arranque del ejecutable nativo.
- **CI:** [GitHub Actions](https://github.com/JFrancoG/SmartShoppingList/actions/workflows/ci.yml) comprueba el servidor en Linux arm64, el contrato y los colores. No compila iOS ni despliega Railway. La [guía de CI](docs/setup/ci.md) permite reproducir los validadores localmente.
- **Evidencia real:** los [informes de validación](docs/validation/) distinguen pruebas automatizadas, simulador y dispositivos. [La issue de Siri](https://github.com/JFrancoG/SmartShoppingList/issues/10) recoge la confirmación física final en español e inglés del 27 de septiembre.

La [compilación Release del 27 de septiembre](docs/validation/release-2026-09-27.md) se ha verificado de nuevo sobre el commit publicado `99efa02`, incluidos los últimos textos e icono de cierre, para iOS físico con Xcode 27.2 beta: 0 errores y 0 warnings, con firma de desarrollo. El usuario confirmó el arranque Release anterior en iPhone 11 y después la compilación para iPhone 11 y 14 tras esos ajustes, sin especificar la configuración de estas últimas. Quedan por consolidar un arranque reciente en iOS 27.0 y la cobertura completa de accesibilidad de la UI final. Las pruebas focalizadas de VoiceOver, texto grande, colores y posturas Duo no equivalen a una validación global. El dictado en simulador tiene limitaciones documentadas; usa un entorno comprobado para la demo. El mínimo configurado de iOS 27.0 no debe confundirse con el SDK 27.1 requerido para compilar.

El MVP contempla un grupo por cuenta y refresco explícito. No incluye sincronización en tiempo real, uso sin conexión completo, precios, recetas, sugerencias ni órdenes de compra/cancelación por voz. El [alcance aprobado](docs/mvp-spec.md) y [GitHub Issues](https://github.com/JFrancoG/SmartShoppingList/issues) mantienen las decisiones y el seguimiento de la entrega.

<a id="en"></a>

## English

A shared shopping list for iPhone and iPad, built for **ACoding Hackathon 2026 · September 27**. Say or type the products and store to add them to your group's list. While shopping, select products and confirm only those selected; the rest remain pending.

### What you can do

- **Share your shopping:** sign in with Apple, create a group and invite someone through a link. Account, group and invitations are managed in **Settings**.
- **Add through speech or text:** Speech transcribes and Foundation Models identifies products, quantities and stores. When the details are complete, **Confirm** in the alert adds them directly to the list. The draft opens to correct identification errors, complete missing details or when you choose **Edit**.
- **Add manually:** enter a product, optional quantity and store without Apple Intelligence. With an active group, **Add product** saves that entry directly; without a group, **Save product** keeps it in the local draft. Manual controls appear without a model, without a group, or when recovering and editing a proposal.
- **Browse and shop:** select a store or find it by voice, refresh pending products, edit or cancel them, and confirm a partial purchase. Checkmarks stay local until you tap **Confirm purchase**.
- **Use Siri and Shortcuts:** add to the draft or to an existing store in the shared list through two separate actions. The list action asks for product, quantity and store; an unknown or ambiguous store opens the draft for review.
- **Work in English or Spanish:** localized UI, permission prompts, notices and Siri actions. User-entered names keep their original language.

The server retains purchased and cancelled entries, their original data and, for purchases, who confirmed them and when. This is the minimal history; there is no history screen. Retries preserve an operation's identity to prevent duplicates. Two intentional additions of the same product are separate operations.

### Requirements and technology

| Component | Requirements |
|---|---|
| App | **Smart List** on the device; iPhone/iPad running iOS/iPadOS **27.0 or later**. Mac and Mac Catalyst are not app destinations. |
| iOS build | **Xcode 27.1 or later**, with SDK 27.1 or later. iPhone Duo adaptations use availability-guarded APIs. |
| Speech and AI | Microphone permission and transcription support for the device and language. Interpretation requires compatible hardware and models, enabled Apple Intelligence and support for the selected language. Store voice queries and traditional Siri do not require Foundation Models. |
| Native server | **Swift 6.4**, macOS **26.2 or later**, and Docker Desktop for local PostgreSQL. A Linux container is also provided. |
| Shared access | Network access, signing with Sign in with Apple and Associated Domains, and a configured HTTPS backend and PostgreSQL database. |

The app uses **Swift 6, SwiftUI, strict concurrency, Speech, Foundation Models and App Intents**, with no third-party dependencies. It keeps drafts in local storage and credentials in Keychain. The server uses **Vapor 4.122.2, Fluent/PostgreSQL and JWTKit**; `Package.resolved` pins dependencies. Logic tests in both components use **Swift Testing**, and first-party targets treat warnings as errors, with [documented external exceptions](docs/dependency-exceptions.md).

### Run the app

From the repository root:

```bash
open ios/SmartShoppingList/SmartShoppingList.xcodeproj
```

1. Select the **SmartShoppingList** scheme and a compatible iPhone, iPad or simulator.
2. In **Signing & Capabilities**, configure signing for the authorized App ID. The project uses `com.plusprojects.SmartShoppingList`, Sign in with Apple and Associated Domains.
3. Check `SHARED_API_BASE_URL` and `SHARED_INVITATION_ORIGIN` in **Build Settings** for both Debug and Release. The checkout points to the [project's hosted HTTPS service](https://smartshoppinglist-production.up.railway.app/hello).
4. Run the app. Open **Settings → Prepare Sign in with Apple**, continue with the native Apple button, then create a group or accept an invitation. Manual entry and the local draft let you explore the app without a group.

Access to the existing service requires signing and capabilities compatible with its registered App ID. For your own deployment, configure the server's Apple identity, app identifiers, both HTTPS origins, Associated Domains and AASA together; changing only the signing team does not configure collaboration. The [shared-flow setup guide](docs/setup/shared-shopping.md) details the required variables and secrets. Private keys never belong in the client or repository.

### Run the server and its tests

With Docker Desktop running, from the repository root:

```bash
cd server
docker compose --profile testing up -d --wait db db-test
swift build --build-tests --force-resolved-versions
swift test --skip-build
swift run --skip-build SmartShoppingListServer serve --hostname 127.0.0.1 --port 8081
```

In another terminal:

```bash
curl --fail http://127.0.0.1:8081/hello
```

`db` uses port 5432 and persists development data in the `db_data` volume. `db-test` uses port 5433 and an isolated temporary database. Compose credentials are local examples. The server applies migrations at startup; `/hello` checks the HTTP response, not sign-in or a PostgreSQL query.

Local startup and automated tests do not need Apple credentials. To authenticate real users, complete the settings from `server/.env.example` in a local `.env` or your hosting secret manager. The [server README](server/README.md) covers additional commands, variables and Linux execution. A physical app needs a reachable HTTPS backend; the Mac's `127.0.0.1` is not a valid server URL for the iPhone.

To stop the environment, run `docker compose --profile testing stop` from `server/`. This preserves the development volume and discards temporary test data. Do not use `down -v` if you need to retain the database. Restoring the hosted service requires both the PostgreSQL backup and the Apple grant encryption keys, as described in the [setup guide](docs/setup/shared-shopping.md).

### Two-person demonstration

Prepare two installed clients, two different Apple IDs, access to the same backend and one account without a group to accept the invitation. For this example, use English in the app and Siri. For the AI portion, use an environment with available Foundation Models; check speech capture separately.

1. On the first client, open **Settings**, prepare Sign in with Apple, sign in and create a group. Use **Invitations → Create invitation → Share invitation** to send a link to the second user.
2. Open the link on the second client, sign in if needed and tap **Accept invitation** in **Settings**.
3. In **Add**, dictate “Buy soap, beer and yogurts at Mercadona,” then tap **Finish dictation**; if using the text field, type the products and store and tap **Interpret text**. When identification succeeds, **Confirm** in the alert adds the products directly to the list. Correct missing or misidentified details in the draft; **Edit** also lets you open it voluntarily. Without AI, enter each product through **Add manually → Add product**.
4. On the second client, open **Shop**, select Mercadona and tap **Refresh**. The shared products should appear; synchronization is requested explicitly.
5. Add two more products to reach five pending entries. Select three and tap **Confirm purchase · 3**. Refresh the other client: the two unselected products should remain pending.
6. Swipe a row left to edit a pending product and save the changes. On another row, **Remove → No longer needed** cancels the product without recording a purchase. Close and reopen the app to check retained data.
7. As an extra, say “**Add to my shopping list in Smart List**.” Answer with a product, quantity and existing store. After the server confirms the addition, **Open list** opens that store. The **Add product to draft** action retains local review.

The manual path does not establish speech or AI behavior. Siri uses published phrases and explicit prompts; conversational Siri AI understanding is outside this version.

### Tests and validation scope

- **iOS:** select **Fast** or **Integration** in the scheme and run **Product → Test**. Both use Swift Testing; Fast covers rules and coordination, while Integration covers local persistence and Keychain. They do not require a microphone, models or a real Apple session.
- **Server:** the commands above build and run HTTP tests with isolated PostgreSQL, authorization, concurrency, purchases, cancellations and idempotency. `swift build --build-tests` alone does not execute tests. The [September 27 Release validation](docs/validation/server-release-2026-09-27.md) records 82 tests in 8 suites and a native executable startup check.
- **CI:** [GitHub Actions](https://github.com/JFrancoG/SmartShoppingList/actions/workflows/ci.yml) checks the Linux arm64 server, API contract and colors. It does not build iOS or deploy to Railway. The [CI guide](docs/setup/ci.md) explains how to reproduce the validators locally.
- **Runtime evidence:** [validation reports](docs/validation/) distinguish automated tests, simulators and physical devices. [The Siri issue](https://github.com/JFrancoG/SmartShoppingList/issues/10) records the final physical English and Spanish confirmation on September 27.

The [September 27 Release build](docs/validation/release-2026-09-27.md) was repeated on published commit `99efa02`, including the latest labels and close icon, for physical iOS devices with Xcode 27.2 beta: 0 errors and 0 warnings, with development signing. The user confirmed the earlier Release launch on iPhone 11 and subsequently reported builds for iPhone 11 and 14 after those adjustments, without specifying their configuration. A fresh launch on iOS 27.0 and complete accessibility coverage of the final UI still need consolidation. Focused VoiceOver, large-text, color and Duo-posture checks do not establish full compliance. Simulator dictation has documented limitations; use a verified environment for the demo. The configured iOS 27.0 runtime minimum is distinct from the SDK 27.1 build requirement.

The MVP supports one group per account and explicit refresh. It does not include real-time synchronization, full offline operation, prices, recipes, suggestions or voice commands to purchase/cancel products. The [approved scope](docs/mvp-spec.md) and [GitHub Issues](https://github.com/JFrancoG/SmartShoppingList/issues) retain decisions and delivery tracking.

## Estructura / Repository layout

```text
ios/SmartShoppingList/  App SwiftUI, proyecto Xcode y tests / SwiftUI app, Xcode project and tests
server/                API Vapor, PostgreSQL y tests / Vapor API, PostgreSQL and tests
docs/                  Especificación, configuración y evidencia / Specification, setup and evidence
scripts/               Validadores de contrato y diseño / Contract and design validators
design/                Originales gráficos / Original artwork
```

Dentro de la app / Inside the app: `App/` arranque y composición / startup and composition; `Features/` recorridos / features; `Services/` API y Keychain; `Shared/` componentes comunes / shared components; `Resources/` colores, iconos, textos y configuración / colors, icons, strings and configuration. Las carpetas están sincronizadas con Xcode / Folders are synchronized with Xcode.

<a id="docs"></a>

## Documentación / Documentation

La documentación técnica enlazada conserva su idioma original, principalmente español; este README ofrece el recorrido de inicio y demostración en ambos idiomas. / Linked technical documentation retains its original language, mainly Spanish; this README provides getting-started and demonstration instructions in both languages.

| Documento / Document | Contenido / Contents |
|---|---|
| [Especificación / MVP specification](docs/mvp-spec.md) | Reglas, aceptación y exclusiones / Rules, acceptance and exclusions |
| [Plan / Implementation plan](docs/implementation-plan.md) | Fases, decisiones y condiciones de entrega / Phases, decisions and delivery conditions |
| [Servidor / Server](server/README.md) · [Configuración / Shared setup](docs/setup/shared-shopping.md) | PostgreSQL, Apple, HTTPS, firma y enlaces / PostgreSQL, Apple, HTTPS, signing and links |
| [Contrato / API contract](docs/contracts/mvp-api.md) · [Aceptación / Acceptance](docs/contracts/acceptance.md) | Operaciones, errores y casos verificables / Operations, errors and verifiable cases |
| [Borrador / Draft architecture](docs/architecture/ios-draft.md) · [Colaboración / Shared architecture](docs/architecture/shared-shopping.md) | Persistencia, coordinación y reintentos / Persistence, coordination and retries |
| [Varios grupos y traspaso / Multiple groups and admin transfer](docs/architecture/multiple-groups.md) | Diseño futuro, fuera del MVP / Future design, outside the MVP |
| [Diseño / Design system](docs/design-system.md) · [Accesibilidad / Accessibility](docs/accessibility.md) · [Contraste / Contrast](docs/validation/design-system-contrast.md) | Cuatro apariencias, criterios y cobertura / Four appearances, criteria and coverage |
| [UI](docs/validation/issue-28-shopping-ui.md) · [Duo](docs/validation/issue-30-duo-controls.md) · [Siri](docs/validation/issue-10-app-intents.md) · [ES/EN](docs/validation/issue-13-localization.md) | Evidencia por entorno y limitaciones / Environment-specific evidence and limitations |
| Release 2026-09-27: [iOS](docs/validation/release-2026-09-27.md) · [Servidor / Server](docs/validation/server-release-2026-09-27.md) | Compilación, pruebas y arranque por entorno / Build, tests and startup per environment |
| [CI](docs/setup/ci.md) · [Excepciones / Dependency exceptions](docs/dependency-exceptions.md) | Validación automática y diagnósticos aceptados / Automated validation and accepted diagnostics |
| [GitHub Issues](https://github.com/JFrancoG/SmartShoppingList/issues) · [Hito / Milestone](https://github.com/JFrancoG/SmartShoppingList/milestone/1) · [Changelog](CHANGELOG.md) | Seguimiento operativo e historial / Operational tracking and change history |
