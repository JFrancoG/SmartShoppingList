# Preparación de TestFlight 1.0 (5)

Fecha: 7 de noviembre de 2026. Issues [#54](https://github.com/JFrancoG/SmartShoppingList/issues/54)
y [#49](https://github.com/JFrancoG/SmartShoppingList/issues/49).
Rama: `codex/issue-54-production-readiness`, base de consolidación `3dd5237`.

## Alcance y revisión

El propietario autoriza revisar/consolidar, hacer commit y push y preparar el siguiente build para
TestFlight Internal Only. Se conserva el bundle comercial, versión 1.0 y separación de datos; el
build pasa de 4 a 5 mediante Xcode. El último Archive local y build distribuido acreditado es 1.0 (4).
La consulta actual de App Store Connect requiere recuperar la sesión antes de confirmar disponibilidad.

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

## Siguiente gate

Preparar y revisar el Archive comercial 1.0 (5) para TestFlight Internal Only. Esta preparación no
acredita una subida, procesamiento de Apple ni aceptación física. #49 y #54 permanecen abiertas.
Tras instalar el build nuevo, comprobar sólo los tres recorridos de
[regresión de #49](ui-controls-and-refresh-review.md#próxima-aceptación-física-sólo-en-el-nuevo-build).
No repetir compra, salida del grupo A·2, incorporación a Test1 ni sincronización ya aceptadas.
