# Base visual — issue #20

Fecha: 25 de septiembre de 2026. [Seguimiento](https://github.com/JFrancoG/SmartShoppingList/issues/20).

La implementación y validación se realizaron en `codex/issue-20-design-system-foundation`, sobre `5a03389` de #19. La [issue #20](https://github.com/JFrancoG/SmartShoppingList/issues/20) conserva los enlaces y el estado definitivo de la entrega. El 25 de septiembre el responsable autoriza commit, push, PR, merge y cierre de esta unidad; la validación técnica se distingue del resultado de Git.

## Resultado

Los 21 tokens de [la paleta](../design-system.md) tienen cuatro variantes sRGB opacas en Asset Catalog y acceso directo a los símbolos tipados generados por Xcode, como `.canvas`, `.surface` y `.onPrimary`, sin enum intermedio. Los assets usan PascalCase sin prefijo, salvo `AppPrimary` y `AppSeparator` por colisiones nativas; sus accesos son `.appPrimary` y `.appSeparator`. `AppPrimary` es el único recurso del tinte global, configurado en Debug y Release; se elimina `AccentColor`. Los estilos nativos mantienen usos contextuales como `.foregroundStyle(.primary)`.

## Comprobaciones

La compilación y el verificador comprueban los nombres definitivos: 19 assets sin prefijo y las dos excepciones. El sondeo de valores y las capturas proceden de la versión inicial; no se han repetido tras cambiar únicamente los nombres.

| Comprobación | Resultado y alcance |
|---|---|
| `python3 scripts/validate_design_system.py` | 21 assets × 4 variantes idénticas a la tabla; 62 pares × 4 modos, 236/236 umbrales cumplidos y 12 mediciones decorativas sin umbral. Informe y SVG actualizados |
| Xcode MCP `BuildProject` | Con los 19 assets renombrados y acceso directo, Debug correcto en iPhone 18 Pro / iOS 27.0, Xcode 27.0; log completo revisado, sin errores ni avisos propios |
| Símbolos generados | `GeneratedAssetSymbols.swift` contiene 19 accesos sin prefijo y `.appPrimary`/`.appSeparator`, sin directivas `#warning` |
| Tinte compilado | `actool --accent-color AppPrimary` y `NSAccentColorName = AppPrimary` en el bundle Debug. Debug y Release también comprobados en Build Settings; no se ha compilado Release en este bloque |
| Resolución de recursos en ejecución | Sobre la versión inicial con enum, posteriormente eliminado: sondeo Xcode `RunCodeSnippet`: 84/84 resultados coinciden exactamente con los RGB de la tabla y alpha 1, sin conversiones fallidas |
| Muestra SwiftUI aislada | `DesignSystemPreview`, sin servicios ni datos del usuario: renders Light, Dark, HC Light y HC Dark inspeccionados en iPhone 18 Pro / iOS 27.2, destino elegido por el servicio de previews. Capturas anteriores a la eliminación del enum y al ajuste de nombres; los valores y el layout se conservan |
| Texto ampliado | Renders adicionales XXX Large y AX 5; etiquetas multilínea y contenido desplazable. No es una validación de interacción ni VoiceOver |
| Revisión independiente | Sin hallazgos en tokens, API Swift, aislamiento del diagnóstico y coherencia documental; auditoría de estilo sin candidatos |
| `git diff --check` | Correcto |

El único aviso del log es `Metadata extraction skipped, no AppIntents.framework dependency found`, cubierto exclusivamente por [EXC-002](../dependency-exceptions.md#exc-002--extracción-de-metadatos-app-intents-sin-adopción). No se oculta ni se declara ausencia global de warnings.

Log local de la compilación final: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/BuildProject/BuildProject-Log-20260925-111223.txt`. Capturas locales: directorio hermano `RenderPreview/`, nombres `Semantic colors - 2026-09-25 at 08.36.48.png`, `08.36.48 2.png`, `08.36.49.png` y `08.36.49 2.png`; texto ampliado `08.37.29.png` y `08.37.29 2.png` con el mismo prefijo. Son artefactos temporales de esta sesión.

## Simplificación del acceso

El 25 de septiembre el usuario señala que Xcode ya genera los accesos tipados. Se elimina `AppColor` y la vista de diagnóstico usa los símbolos generados directamente. La compilación indicada arriba incorpora también los nombres definitivos. No se atribuyen el sondeo ni las capturas anteriores a una nueva ejecución.

Se comprueba por separado con `actool` y `swiftc` de Xcode 27.0, fuera del proyecto, el caso de un asset llamado `primary`. El generador emite un warning de colisión con `Color.primary` y omite ese miembro personalizado; `.foregroundStyle(.primary)` sigue resolviendo al estilo jerárquico nativo. `separator` también provoca un warning por colisión con `UIColor.separator`. El experimento falla con warnings como errores. A petición del usuario, solo estos dos assets conservan `App`; los otros 19 usan PascalCase sin prefijo. Evidencia local temporal: `/tmp/ssl-primary-probe-42s5iom1/GeneratedAssetSymbols.swift` y `Probe.ast`.

Para revisar los colores, abrir `App/Debug/DesignSystemPreview.swift` y combinar los overrides `Color Scheme` (Light/Dark Appearance) y `Contrast` (Standard/Increased Contrast).

## Pendiente del bloque posterior

Aplicar los pares y componentes a las pantallas y verificar los controles que heredan el nuevo tinte global. El sondeo acredita la resolución de recursos; ni sus resultados ni los ratios acreditan la accesibilidad completa del recorrido. No se ha repetido la suite funcional de compra ni el ensayo físico ya registrado. La integración visual requiere su propia validación de estados, tamaños y VoiceOver.
