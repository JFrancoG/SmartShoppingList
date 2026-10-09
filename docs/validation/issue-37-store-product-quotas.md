# Cupos y archivo/restauración de tiendas — validación de #37

Fecha: 10 de octubre de 2026. [Issue #37](https://github.com/JFrancoG/SmartShoppingList/issues/37).

Tercera unidad posterior al MVP, implementada en `codex/issue-37-store-product-quotas` desde `main` limpio y sincronizado en `10f9617`. La validación de este informe se realizó sobre los cambios locales antes de publicar. La issue conserva el plan operativo, commits, PR, CI y estado definitivo de integración; este informe no acredita despliegue. El [contrato 0.4.0](../contracts/store-quotas.md) define la API y la [decisión comercial](../architecture/group-access-and-limits.md) conserva las reglas aprobadas.

## Alcance comprobado

- Plan gratuito: 1 pertenencia por cuenta, 3 tiendas activas por grupo y 20 entradas pendientes por tienda. Plan premium preparado: 5/10/100, comprobado mediante política confiable inyectada en pruebas. Las tiendas/productos usan el plan del administrador actual; cada miembro usa su propio cupo de pertenencias. No hay compras ni derechos premium reales activados.
- Un invitado gratuito ya perteneciente a un grupo no puede aceptar otro. El rechazo conserva el enlace sin consumir; puede aceptarlo tras liberar su plaza mientras siga vigente. El premium del administrador no amplía el cupo personal del invitado.
- Admisión completa de lotes y movimientos antes de insertar, con normalización de nombres, conteo de pendientes y coordinación por grupo. Las cantidades literales y las filas compradas/canceladas no consumen plazas de producto.
- Archivo explícito del administrador sobre una tienda sin pendientes. Libera una plaza activa y conserva ID, normalización, historial y recibos. Restauración explícita de la misma tienda con capacidad disponible; no hay duplicados ni reactivación mediante altas/movimientos.
- Exceso tras migración, reducción de plan o traspaso: contenido conservado, crecimiento limitado por recurso y lectura, compra, cancelación, edición sin crecimiento y archivo disponibles.
- Gestión iOS en Ajustes → Tiendas y capacidad, uso/límites, activas/archivadas, confirmaciones y motivos de restricción localizados. Los selectores ordinarios y la resolución de tiendas para Siri utilizan activas.
- Rechazos definitivos conservan borradores y correcciones; otra confirmación explícita genera una intención nueva. Respuestas inciertas conservan su sobre y clave. Recuperar un recibo histórico no instala su tienda como estado actual.

## Resultados

| Comprobación | Resultado | Entorno y límite |
|---|---|---|
| Contrato y ejemplos | 27 operaciones, 100 ejemplos positivos y 39 peticiones negativas: PASS | JSON Schema 2020-12 y formatos; no es meta-validación completa de OpenAPI ni comprobación runtime. |
| Sistema de diseño | 64 pares × 4 modos y 21 assets × 4 variantes: PASS | Tablas, SVG y bytes sRGB canónicos; no certifica todas las pantallas. |
| Servidor | Build desde limpieza con corrección posterior; último build de entrega 5,910 s. 120 funciones en 8 suites: PASS, 29,292 s | Swift 6.4 nativo macOS, PostgreSQL 18.6 aislado. Sin nuevos warnings propios; el manifiesto JWTKit conserva el diagnóstico aceptado en EXC-001. |
| iOS, build para tests | PASS; último build 8,665 s, cero errores y warnings | Xcode MCP 27.2, esquema SmartShoppingList, iPhone 17 con iOS Simulator 27.2. Primer build tras retirar únicamente la caché Build de este proyecto; correcciones posteriores compiladas incrementalmente. No se declara limpieza global de DerivedData. |
| iOS, plan Fast | 210 funciones / 364 ejecuciones: PASS | Su `xcresult` informa 0 fallos, 0 omitidas y 0 runtime warnings. |
| iOS, plan Integration | 10 funciones / 18 ejecuciones: PASS | Persistencia real en Keychain del simulador y reapertura, incluidas ambas acciones de tienda. 0 fallos, 0 omitidas y 0 runtime warnings. |
| Previews | Gestión ES/EN en Large, XXXL y AX5; fila ES AX5 y archivada EN Large: renderizados e inspeccionados | iPhone 17, iOS 27.2; render inicial adicional ES Large en iPhone 18 Pro Max. Datos sintéticos. Solo se acredita el contenido visible de cada snapshot. |
| Revisiones independientes | Sin hallazgos estáticos pendientes | Arquitectura, concurrencia, contrato HTTP, recuperación, SwiftUI, localización, accesibilidad y estilo. 38 archivos Swift: 18 iOS y 20 servidor. |
| Consistencia documental | 192 enlaces locales y 361 referencias internas OpenAPI: PASS | 13 Markdown; incluidos 23 enlaces con ancla. 64 destinos de referencia OpenAPI distintos. |

Los conteos iOS proceden de `xcresulttool get test-results summary` para cada plan: 382 ejecuciones en total. Los contadores agregados de MCP mostraban estados de otros planes —148 aprobados en Integration— y no se usan como evidencia de esa ejecución. La plantilla `example()` sin etiqueta queda fuera de ambos planes.

Las suites finales se ejecutaron después de corregir la recuperación y la carrera del refresco. Los renders y la documentación posteriores no modifican comportamiento ni aserciones. La comprobación final de enlaces, referencias OpenAPI y `git diff --check` también se registra en la issue.

En la preparación de la entrega se repitió la auditoría de los 38 Swift y se corrigió exclusivamente el formato de ocho construcciones en seis archivos del servidor. La comparación independiente conserva 9.902 tokens y 417 literales, incluidos SQL y aserciones. Se recompilaron servidor y tests sin warnings; se reutiliza la suite nativa reciente porque ese ajuste no cambia comportamiento. Las 18 fuentes iOS permanecen idénticas al snapshot validado. CI ejecuta una suite completa nueva en Linux y su resultado se registra por separado en la issue y la PR.

## Casos relevantes y correcciones

Las pruebas de migración preservan las filas e identidades existentes y los bytes exactos de recibos, incluso con uso superior al gratuito. Todas las tiendas anteriores quedan activas. La reversión rechaza transaccionalmente cualquier tienda archivada antes de retirar la columna, evitando reactivarla de forma silenciosa.

Las pruebas contra PostgreSQL comprueban límites gratuitos y premium, preflight sin tiendas huérfanas, normalización, altas/movimientos atómicos, compra/cancelación, mismos IDs al restaurar, permisos y cursores separados por estado. Las carreras verifican la última plaza de tienda o producto, restauración frente a creación, archivo frente a altas/movimientos y traspaso frente a crecimiento. También verifican que un administrador anterior pueda recuperar su propio recibo confirmado siendo aún miembro y que bajar capacidad no cambie sus bytes.

Las pruebas iOS verifican rechazos que conservan borradores/editores, nuevas claves tras otra confirmación, pérdida de respuesta y reapertura, sobres conservados hasta refrescar permisos, capacidades antiguas desconocidas y fallback de Siri. Una respuesta tardía de gestión tras cambiar de grupo no sustituye las tiendas ni la capacidad del nuevo destino.

La revisión detectó dos problemas del refresco: una guarda impedía reintentar después de un fallo temporal de `/me`, y permitir ese reintento sin proteger toda la verificación admitía actualizaciones simultáneas. Se corrigieron ambos con estado ocupado durante `/me` y pruebas deterministas mediante respuestas suspendidas. La selección continúa permitida durante la consulta posterior de archivadas, cuya respuesta se descarta por generación si cambia el grupo. La corrección del editor conserva su revisión previa para los rechazos anteriores y solo trata los nuevos errores de cuota/archivo como correcciones reutilizables.

El primer build de servidor detectó que los tests nuevos no podían acceder a un helper declarado `fileprivate`. Se amplió exclusivamente a visibilidad interna del módulo de tests, sin debilitar aserciones; build y suite completa pasaron después. El único diagnóstico externo es la excepción temporal [EXC-001 de JWTKit](../dependency-exceptions.md).

Los renders muestran traducciones ES/EN, fecha localizada, explicación de capacidad compartida y botones que se ajustan a AX5 sin truncamiento horizontal en el contenido visible. En XXXL/AX5 parte del formulario está bajo el pliegue; los snapshots no acreditan haberlo desplazado entero. La preview aislada de archivadas permite inspeccionar fecha y restauración. El doble de previews admite transiciones locales e idempotentes, pero no se declara un recorrido interactivo de esas acciones ni VoiceOver físico.

## Reproducción y artefactos locales

Desde `server/`, se ejecutó `swift package clean` seguido de `swift build --build-tests --force-resolved-versions --jobs 4`, y se repitió el build después de la corrección. La base exclusiva `smartshoppinglist_issue37_testing` utilizó el contenedor temporal `smartshoppinglist-issue37-db`, PostgreSQL 18.6 con el digest del repositorio, loopback 55437 y almacenamiento temporal. Ninguna prueba utilizó desarrollo o producción.

```sh
TEST_DATABASE_HOST=127.0.0.1 \
TEST_DATABASE_PORT=55437 \
TEST_DATABASE_USERNAME=vapor_test \
TEST_DATABASE_PASSWORD=vapor_test_password \
TEST_DATABASE_NAME=smartshoppinglist_issue37_testing \
swift test --skip-build
```

Solo debe ejecutarse con una base temporal preparada y sin otra suite usando esa base. Las credenciales anteriores son exclusivamente de prueba. Se eliminó únicamente el contenedor propio tras finalizar la suite. Se restauraron Fast y el destino original iPhone 11, y se cerró únicamente el workspace abierto por esta tarea, conservando el workspace preexistente de FranAlonso. Se retiró la copia temporal de la caché Build anterior; la caché nueva y los artefactos de validación permanecen disponibles.

Artefactos temporales de esta máquina:

- Servidor: `/tmp/smartshoppinglist-issue37-server-build-final.log`, `/tmp/smartshoppinglist-issue37-server-tests.log` y `/tmp/smartshoppinglist-issue37-delivery-build.log`.
- Build iOS: `BuildProject-Log-20261010-003511.txt`, bajo `ActionArtifacts/default/BuildProject/`.
- Fast: `Test-SmartShoppingList-2026.10.10_00-35-21-+0200.xcresult`.
- Integration: `Test-SmartShoppingList-2026.10.10_00-35-36-+0200.xcresult`.
- Los `.xcresult` están bajo `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/`; los renders, en el directorio hermano `RenderPreview/`, entre 00:36:34 y 00:37:50 CEST.

## Límites y siguiente entrega

Durante esta validación local no se ejecutó Release, CI de esta rama, migración/despliegue de producción, SIWA real entre dos cuentas, Siri físico, VoiceOver/foco físico ni StoreKit. Los nuevos campos son aditivos, pero los clientes 0.3 desconocen los nuevos `409` y requieren actualización para resolverlos y gestionar tiendas. No se presenta ese cambio como compatibilidad funcional completa.

La unidad queda implementada y validada localmente. El propietario autoriza commit, push, PR, CI, merge, cierre de issue y eliminación de rama; el resultado de esa entrega se verifica y registra por separado en #37 y su PR. Compras verificadas, oferta premium, precios, periodo de gracia y elección del grupo gratuito al perder capacidad de pertenencias siguen perteneciendo a la unidad de pagos.
