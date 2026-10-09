# Pertenencias múltiples y selección de grupo — validación de #35

Fecha: 9 de octubre de 2026. [Issue #35](https://github.com/JFrancoG/SmartShoppingList/issues/35).

Segunda unidad posterior al MVP, implementada en `codex/issue-35-multiple-groups` desde `main` limpio y sincronizado en `353953d`. La validación de este informe se realizó sobre los cambios locales antes de publicar. La issue conserva el plan operativo, commits, PR, CI y estado definitivo de integración; este informe registra evidencia local y no acredita un despliegue. El [contrato 0.3.0](../contracts/group-memberships.md) define pertenencias, admisión y compatibilidad; la [arquitectura](../architecture/shared-shopping.md) explica el aislamiento del cliente.

## Alcance comprobado

- Relación de pertenencias por cuenta y grupo, migración de datos existentes y administrador único perteneciente a cada grupo activo. El creador histórico no cambia.
- Autorización, creación, invitaciones, administración, traspasos, salida y recibos vinculados al grupo solicitado. Una persona puede pertenecer y administrar varios grupos cuando su capacidad de admisión lo permite.
- Listado paginado de grupos actuales y capacidades de cuenta verificadas. El campo singular anterior es una proyección de compatibilidad, nunca la fuente de autorización; salir de ese grupo lo vacía sin elegir otro.
- Selección activa local por cuenta y dispositivo, persistida en Keychain. La pérdida de la pertenencia elegida exige selección explícita, incluso si queda un solo grupo.
- Cargas y errores antiguos descartados tras un cambio, también en el recorrido A → B → A. Operaciones persistidas conservan cuenta, grupo, intención y clave de reintento; no pueden redirigirse al destino visible.
- Borrador personal conservado; propuesta preparada, selección de compra y estado efímero invalidados al cambiar. El envío compartido muestra su grupo de destino.
- Siri conserva el borrador local y solo permite el envío directo existente cuando hay exactamente una pertenencia recién verificada y una tienda inequívoca. Varias pertenencias o una verificación incompleta requieren revisión explícita.
- La política predeterminada admite un grupo por cuenta. Las capacidades ampliadas se inyectan únicamente en pruebas mediante la frontera de servidor. No se activan compras, premium ni cuotas de tiendas/productos.

## Resultados

| Comprobación | Resultado | Entorno y límite |
|---|---|---|
| Contrato y ejemplos | 24 operaciones, 75 ejemplos positivos y 32 peticiones negativas: PASS | JSON Schema 2020-12 y formatos; no sustituye meta-validación completa de OpenAPI ni pruebas runtime. |
| Sistema de diseño | 64 pares × 4 modos y 21 assets × 4 variantes: PASS | Tablas, SVG y bytes sRGB canónicos; no certifica todas las pantallas renderizadas. |
| Servidor | Build desde limpieza con correcciones posteriores; último build 2,930 s; 104 funciones en 8 suites: PASS, 25,232 s | Swift 6.4 nativo macOS y PostgreSQL 18.6 aislado. Sin nuevos warnings propios. El build inicial conserva el warning del manifiesto de JWTKit aceptado en EXC-001. |
| iOS, build para tests | PASS; último build 2,861 s; registro sin warnings | Xcode MCP 27.2, esquema SmartShoppingList, iPhone 17 con iOS Simulator 27.2. Build incremental; no se declara limpieza de DerivedData. |
| iOS, plan Fast | 193 funciones / 330 ejecuciones: PASS | Resultado de su `xcresult`: 0 fallos, 0 omitidas y 0 runtime warnings. |
| iOS, plan Integration | 10 funciones / 16 ejecuciones: PASS | Incluye persistencia real de la selección en Keychain del simulador y reapertura. 0 fallos, 0 omitidas y 0 runtime warnings. |
| Previews | Selector ES y EN en AX5; alta ES Large, EN XXXL y ES AX5: renderizados e inspeccionados | iPhone 17, iOS 27.2; selector ES inicial adicional en iPhone 18 Pro Max. Datos sintéticos. Se comprueba el contenido visible; no se acredita desplazamiento, interacción física ni VoiceOver. |
| Revisiones independientes | Sin hallazgos estáticos pendientes | Arquitectura, concurrencia, recuperación, SwiftUI, localización y estilo; 40 archivos Swift del cambio, 19 iOS y 21 servidor. |
| Consistencia documental | 172 enlaces locales y 322 referencias internas OpenAPI: PASS | Snapshot de contratos, arquitectura, README, spec y plan; el informe se añadió posteriormente y se verificó por separado. |

Las cifras iOS proceden de `xcresulttool get test-results summary` para cada ejecución. Los contadores de `RunAllTests` de MCP conservaban estados de otros planes: Integration mostraba 138 aprobados. No se suman esos estados. La plantilla `example()` sin etiqueta queda fuera de ambos planes y no se declara ejecutada.

Las suites completas se ejecutaron sobre el código funcional final. Los renders y la documentación posteriores no cambiaron ese comportamiento ni las aserciones.

## Casos relevantes y correcciones

La migración compara antes/después todas las filas de usuarios, grupos, tiendas, productos, invitaciones, traspasos y recibos. Conserva bytes de recibos anteriores y permisos de grupos cerrados. La reversión rechaza transaccionalmente tanto pertenencias múltiples como una proyección singular que perdiera o inventara acceso; no convierte una relación múltiple en una selección arbitraria.

Las pruebas de servidor verifican el aislamiento de roles y recursos, la estabilidad y vinculación de cursores, la capacidad por cuenta, la admisión concurrente, invitaciones ya aceptadas y salidas que preservan los demás grupos. Los bloqueos de cuenta usan `FOR NO KEY UPDATE` para serializar admisión sin bloquear comprobaciones de claves foráneas de otro miembro. La carrera de propuestas de traspaso recíprocas comprueba que ambos participantes alcanzan la barrera antes de liberarla.

Las pruebas iOS verifican selección y reapertura, ausencia de fallback tras perder acceso, respuestas y errores tardíos, generaciones sucesivas, guardado reentrante en Keychain frente a un error de autenticación, operaciones pendientes inalteradas, editores, borradores y creación/unión explícitas. Capacidades ausentes, incoherentes o un listado parcial no habilitan mutaciones ni un destino directo para Siri. Los tests HTTP conservan las comprobaciones de paginación y decodificación.

En la primera ejecución, tres pruebas existentes detectaron una regresión del refresco: si fallaba la verificación de cuenta antes de cargar el grupo, los productos conservados seguían marcados como cargados. Se corrigió el estado sin perder productos ni checks; las aserciones se mantuvieron y el plan Fast completo pasó después. En servidor se corrigió una barrera de test que esperaba un INSERT cuando las dos peticiones estaban bloqueadas antes en un UPDATE; se conservaron las aserciones de concurrencia y se repitió toda la suite.

La revisión estática corrigió pluralización ES/EN y el estado sin selección del picker. Los renders muestran la identificación de grupos con nombres iguales sin truncamiento horizontal en el contenido visible. En XXXL y AX5 parte del formulario queda bajo el pliegue; el snapshot no prueba que se haya recorrido todo el formulario ni confirma el botón inferior en esos tamaños. El botón de alta con destino explícito sí se ve en ES Large.

## Reproducción y artefactos locales

Desde `server/`, se ejecutó `swift package clean` y `swift build --build-tests --force-resolved-versions --jobs 4`. Tras corregir compilación y barrera, se repitieron build y suite completa. La base exclusiva `smartshoppinglist_issue35_testing` usó el contenedor temporal `smartshoppinglist-issue35-db`, PostgreSQL fijado por el digest del repositorio, loopback 55435 y almacenamiento temporal. No se utilizaron bases de desarrollo o producción.

```sh
TEST_DATABASE_HOST=127.0.0.1 \
TEST_DATABASE_PORT=55435 \
TEST_DATABASE_USERNAME=vapor_test \
TEST_DATABASE_PASSWORD=vapor_test_password \
TEST_DATABASE_NAME=smartshoppinglist_issue35_testing \
swift test --skip-build
```

Solo debe ejecutarse con una base temporal preparada y sin otra suite usando esa base. Las credenciales anteriores son exclusivamente de prueba. Al terminar se eliminó únicamente el contenedor propio. Xcode quedó con el plan Fast y el destino original iPhone 11 restaurados; se cerró únicamente el workspace abierto por esta tarea.

Artefactos temporales de esta máquina:

- Servidor: `/tmp/smartshoppinglist-issue35-server-build.log`, `/tmp/smartshoppinglist-issue35-server-final-build.log` y `/tmp/smartshoppinglist-issue35-server-final-tests.log`.
- Build iOS: `BuildProject-Log-20261009-205520.txt`, bajo `ActionArtifacts/default/BuildProject/`.
- Fast: `Test-SmartShoppingList-2026.10.09_20-55-27-+0200.xcresult`.
- Integration: `Test-SmartShoppingList-2026.10.09_20-56-01-+0200.xcresult`.
- Los `.xcresult` están bajo `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/`; los renders, en el directorio hermano `RenderPreview/`, entre 20:59:23 y 21:00:28 CEST.

## Límites de esta evidencia y entrega

No se ejecutó build Release, CI de esta rama, migración de producción, SIWA real con dos cuentas, Siri físico, VoiceOver/foco físico ni StoreKit. El servidor debe actualizarse antes del cliente y la migración requiere detener escritores del backend anterior; la proyección de compatibilidad no sincroniza nuevas altas realizadas por ese backend. No se desplegó ningún entorno.

La funcionalidad estructural de varios grupos y su selector queda implementada y validada localmente. La admisión real continúa limitada a un grupo por cuenta: el plan personal verificado que permita grupos adicionales, las cifras comerciales, la pérdida de capacidad y las cuotas de tiendas/productos son entregas posteriores del [plan aprobado](../architecture/group-access-and-limits.md). El propietario autoriza commit, push, PR, CI, merge, cierre de #35 y eliminación de la rama; el resultado de esa entrega se verifica y registra por separado en la issue y la PR.
