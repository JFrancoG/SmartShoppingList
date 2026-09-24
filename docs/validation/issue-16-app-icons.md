# Iconos Brain y Check — #16

## Alcance aprobado

El 24 de septiembre de 2026 el usuario autoriza incorporar todos sus cambios actuales de diseño y ajustes recomendados por Xcode, implementar la selección de icono si la plataforma lo permite y hacer commit/push en `main`. Se conservan los 26 originales de `design/app-icon/` (13 PNG y 13 prompts) y ambos archivos Icon Composer, cada uno con sus cuatro capas. No se regenera ni recolorea el arte.

Brain es el icono principal de instalación. Check se solicita al entrar en primer plano solo si `SystemLanguageModel.default.availability` informa `.deviceNotEligible`. Desactivar Apple Intelligence o esperar a la descarga no equivale a hardware incompatible. En una plataforma sin iconos alternativos se conserva el principal. El cambio muestra el aviso nativo de iOS; no es silencioso.

Se incorporan también los ajustes del usuario: migración de metadatos a Xcode 27.2, analizador de textos no localizados, generación de símbolos del catálogo y eliminación de código no utilizado. No se cambian dependencias, backend, entitlements ni el idioma del esquema.

## Validación técnica

- Revisión independiente de reglas, aislamiento `MainActor`, idempotencia y concurrencia de escenas: sin hallazgos funcionales. Se aplica `initial: true` y se normaliza el estilo antes de la ejecución final. Auditoría de los tres Swift modificados: sin candidatos pendientes.
- Plan Fast, Xcode 27.2 beta, iPhone 17 simulado con iOS 27.2: **79 declaraciones / 137 ejecuciones parametrizadas aprobadas, 0 fallos**, según consola y `.xcresult` cerrado. El inventario MCP muestra otras seis pruebas sin ejecución, ajenas al filtro Fast; no se presentan como aprobadas.
- `AppIconControllerTests`: cinco declaraciones / siete ejecuciones verifican Check en hardware no compatible; retorno a Brain en los tres estados compatibles; ausencia de cambios redundantes o en entornos deshabilitados; escenas concurrentes mientras la API está suspendida; fallo sin bucle de reintentos. Dobles deterministas, sin sleeps, micrófono ni modelo reales.
- El intento inicial de ejecución selectiva fue rechazado por MCP, que marcaba todos los tests como deshabilitados. No se acredita una fase roja ejecutada. Tras una cancelación comunicada por Xcode y autorización del usuario para reintentar, el plan completo se ejecutó correctamente, conservando el filtro original.
- Debug y Release compilados mediante Xcode MCP. Inspección de `Info.plist` compilado en ambos: `CFBundleIcons` y `CFBundleIcons~ipad` declaran `SmartShoppingListIconBrain` como principal y `SmartShoppingListIconCheck` como alternativo. El compilador de assets recibe ambos `.icon`. No se escriben a mano estas claves generadas.
- Logs completos revisados: sin warnings propios; únicamente `Metadata extraction skipped, no AppIntents.framework dependency found`, cubierto por EXC-002. El destino y la configuración temporal Release se restauran a iPhone 11 / Debug.

Evidencia local de esta ejecución (no incorporada como binarios al repositorio):

- `.xcresult`: `Test-SmartShoppingList-2026.09.24_23-26-48-+0200.xcresult` en `ActionArtifacts/default/RunAllTests`.
- Build Debug: `BuildProject-Log-20260924-232807.txt`.
- Build Release: `BuildProject-Log-20260924-232941.txt`.

## Ensayo real y límites

Compilación e instalación Debug mediante Xcode MCP en iPhone 11 físico con iOS 27.2 correctas. El usuario confirma el aviso y la bolsa con Check en la pantalla de inicio tras abrir esta compilación. Las unitarias prueban la política, no la presentación de SpringBoard. La restauración al principal en hardware compatible está cubierta con dobles; no se atribuye todavía a un ensayo físico.

La incorporación del icono no completa la integración de tokens/componentes del sistema de diseño ni la matriz global de accesibilidad.

## Fuentes

- [Apple: configurar iconos alternativos](https://developer.apple.com/documentation/xcode/configuring-your-app-to-use-alternate-app-icons). Admite Icon Composer, genera metadatos y documenta el aviso nativo.
- [Apple: setAlternateIconName](https://developer.apple.com/documentation/uikit/uiapplication/setalternateiconname(_:completionhandler:)).
