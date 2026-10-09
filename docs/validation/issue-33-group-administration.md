# Administración transferible — validación de #33

Fecha: 9 de octubre de 2026. [Issue #33](https://github.com/JFrancoG/SmartShoppingList/issues/33).

Primera unidad posterior al MVP, elaborada sobre `22511fc` en `codex/issue-33-group-access`. El plan aprobado se publicó en ese commit antes de comenzar. La issue conserva los commits, la PR y el estado de integración de esta entrega; este informe registra la evidencia técnica y no acredita un despliegue. El [contrato 0.2.0](../contracts/group-administration.md) define el comportamiento y la [arquitectura](../architecture/shared-shopping.md#administración-transferible-y-salida-33) explica sus fronteras.

## Alcance comprobado

- Administrador actual separado del creador histórico, migración de grupos existentes y restricción diferida de pertenencia del administrador.
- Propuesta de siete días, aceptación, rechazo, retirada y caducidad; autorización y un único traspaso pendiente.
- Salida del miembro, obligación de traspasar antes de salir como administrador con colaboradores y confirmación expresa de cierre del último miembro.
- Conservación de productos pendientes, comprados y cancelados; revocación de invitaciones sin consumir al cerrar y pérdida de acceso al grupo cerrado.
- Recibos y recuperación sin repetir una salida ni sustituir una pertenencia posterior. Las capacidades vigentes se consultan antes de consolidar el resultado en iOS.
- Capacidades preparadas para grupos por cuenta, tiendas por grupo y pendientes por tienda. Se mantiene un grupo por cuenta; no se activan cuotas de tiendas/productos ni pagos.

## Resultados

| Comprobación | Resultado | Entorno y límite |
|---|---|---|
| Contrato y ejemplos | 23 operaciones, 64 ejemplos positivos y 27 peticiones negativas: PASS | JSON Schema 2020-12 y formatos; no sustituye validación runtime ni meta-validación completa de OpenAPI. |
| Sistema de diseño | 64 pares × 4 apariencias y 21 assets × 4 variantes: PASS | Validador del repositorio, tablas y SVG canónicos; no certifica contraste renderizado de todas las pantallas. |
| Servidor y tests | Build completo desde limpieza, correcciones compiladas y 95 funciones en 8 suites: PASS, 16,350 s | Swift 6.4 nativo macOS, PostgreSQL 18.6 temporal y aislado. Sin nuevos warnings propios; el primer build conserva el warning de manifiesto JWTKit aceptado en EXC-001. |
| iOS, build para tests | PASS; último build 9,224 s, registro sin warnings | Xcode MCP 27.2, esquema SmartShoppingList, iPhone 17 con iOS Simulator 27.2. Build incremental; no se afirma una limpieza completa de DerivedData. |
| iOS, plan Fast | 175 funciones / 303 ejecuciones parametrizadas y simples: PASS | `xcresulttool get test-results summary`, 0 fallos, 0 omitidas, 0 runtime warnings. |
| iOS, plan Integration | 9 funciones / 15 ejecuciones parametrizadas y simples: PASS | Incluye persistencia real en Keychain del simulador y reapertura de las nuevas operaciones; 0 fallos, 0 omitidas, 0 runtime warnings. |
| Previews iPhone 17 | Gestión ES/EN en Large, XXXL y AX5; receptor ES/EN en AX5; componente de traspaso ES AX5/EN Large: renderizados e inspeccionados | Datos sintéticos del trait compartido. Se revisa el contenido visible; los elementos bajo el pliegue requieren desplazamiento y no se acredita interacción física ni VoiceOver. |
| Revisiones independientes | Sin hallazgos estáticos pendientes | Arquitectura iOS, concurrencia, recuperación, SwiftUI, localización y estilo. Revisión de 16 archivos Swift iOS y 16 de servidor en el diff. |

Los contadores de `RunAllTests` de MCP pueden incluir estados conservados de otro plan: en Integration presentaba 125 aprobados. Las cifras anteriores proceden del `xcresult` de cada ejecución, no de sumar esos estados. La plantilla `example()` sin etiqueta queda fuera de ambos planes; no se declara ejecutada.

Las suites iOS se ejecutaron sobre el comportamiento final. Después solo cambiaron presentación del título, ubicación del botón de actualizar y preparación de previews, con nueva compilación y renders; no se repitieron las suites por esos ajustes visuales.

En la preparación de la entrega se repitió la auditoría de los 32 archivos Swift y se ajustó únicamente el formato de ocho archivos del servidor. La comparación anterior/posterior no contiene cambios de tokens ni de literales. Se recompilaron servidor y tests sin nuevos warnings; se reutiliza la ejecución nativa reciente y CI ejecuta la suite completa en Linux.

## Casos relevantes

El servidor prueba el backfill con datos previos, los IDs y todas las columnas de productos antes/después, las restricciones de administrador al commit (`23503` y nombre de constraint), el cambio de permisos de invitación y la conservación de la autoría. El antiguo creador puede ceder, salir y crear otro grupo. Los recibos propios de salida se reproducen tras volver al mismo grupo o entrar en otro, sin alterar esa nueva pertenencia.

Las pruebas concurrentes observan ambas peticiones bloqueadas en PostgreSQL antes de liberarlas: aceptar frente a salir, cerrar frente a aceptar invitación y dos reintentos de la misma aceptación. Las carreras existentes de compras, edición e incorporación de lotes se adaptaron al bloqueo del grupo sin retirar sus aserciones. La consulta de cuenta y grupo usa una única sentencia para evitar resultados mezclados durante el cierre desde otro dispositivo.

En iOS se comprueban intención persistida antes de enviar, pérdida de respuesta, reintento con la misma clave, refresco fallido tras un éxito, rechazo terminal frente a resultado incierto, pertenencia posterior preservada y caché anterior sin permisos implícitos. Un test protege la selección de compra: proponer un traspaso dentro del mismo grupo conserva tienda, checks y posibilidad de finalizar. Las pruebas HTTP rechazan recibos de otro grupo o campos de estado omitidos; las de Keychain reabren propuesta, resolución y salida.

La revisión corrigió la pérdida de checks durante un traspaso, añadió actualización explícita además del gesto y trasladó la normalización del nombre fuera de `body`. El espaciado del miembro escala con la tipografía. Los renders motivaron título compacto y actualización en la barra. Las previews desactivan únicamente su refresco al aparecer porque el trait ya prepara un snapshot completo; la pantalla de producción mantiene el refresco automático por defecto.

## Reproducción y artefactos locales

El servidor se compiló con `swift package clean` seguido de `swift build --build-tests --force-resolved-versions --jobs 4`. Tras corregir diagnósticos y fixtures, se repitieron build y suite completa. PostgreSQL estuvo en el contenedor exclusivo `smartshoppinglist-issue33-db`, imagen fijada por el digest del repositorio, puerto loopback 55433 y base `smartshoppinglist_issue33_testing`, con almacenamiento temporal. Ninguna prueba usó la configuración de desarrollo o producción.

```sh
TEST_DATABASE_HOST=127.0.0.1 \
TEST_DATABASE_PORT=55433 \
TEST_DATABASE_USERNAME=vapor_test \
TEST_DATABASE_PASSWORD=vapor_test_password \
TEST_DATABASE_NAME=smartshoppinglist_issue33_testing \
swift test --skip-build
```

Ejecutar desde `server/`, solo con una base temporal preparada y sin otra suite usando esa base. Credenciales exclusivamente de prueba.

Al terminar se detuvo y eliminó el contenedor temporal. Xcode quedó con el plan Fast y el destino original iPhone 11 restaurados; se cerró únicamente el workspace abierto por esta tarea.

Artefactos de esta sesión, temporales y propios de esta máquina:

- Servidor: `/tmp/smartshoppinglist-issue33-server-build.log`, `/tmp/smartshoppinglist-issue33-server-final-build.log` y `/tmp/smartshoppinglist-issue33-server-final-tests.log`.
- Fast: `Test-SmartShoppingList-2026.10.09_19-24-57-+0200.xcresult`.
- Integration: `Test-SmartShoppingList-2026.10.09_19-26-13-+0200.xcresult`.
- Los `.xcresult` están bajo `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/`; los renders finales, bajo el directorio hermano `RenderPreview/`, entre 19:33:38 y 19:33:53 CEST.

## Límites de esta evidencia

La validación local no incluye build Release, migración de producción, SIWA real con dos cuentas, comprobación física de VoiceOver/foco o compra StoreKit. La ejecución de CI Linux se verifica como parte de la entrega y se registra por separado. El servidor debe actualizarse antes del cliente que usa las nuevas rutas. La prueba manual compartida y la activación se mantienen separadas de la validación local.

Las pertenencias múltiples y su selector, las admisiones comerciales de tiendas/productos, el detalle de pérdida de capacidad y la facturación son las unidades posteriores del [plan aprobado](../architecture/group-access-and-limits.md); este informe no las declara implementadas.
