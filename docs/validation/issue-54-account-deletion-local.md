# #54 — Eliminación de cuenta: validación local

**9 de noviembre de 2026 · Rama `codex/issue-54-privacy-account-deletion` · Base `4596c2f`.**

La implementación local reúne la decisión aprobada sobre texto antiguo, el proceso persistente del servidor, la interfaz iOS y la recuperación de Premium. Este informe acredita ejecución local; no activación en servicios alojados. El [diseño](../architecture/account-deletion.md) y los [borradores legales](../legal/README.md) conservan las condiciones de activación y publicación.

## Comportamiento implementado

- **Contenido antiguo:** reconstrucción de autoría únicamente con un historial completo y consistente. La vista previa avisa del texto incierto; la purga retira texto propio e incierto, incluso si este último pudiera ser de otros miembros, conforme a la decisión aprobada. Conserva contenido ajeno probado. Incluye grupos abandonados/cerrados y copias de contenido en recibos.
- **Solicitud persistente:** reautenticación con desafío específico, vista previa versionada, comprobante privado guardado antes del envío y aceptación irreversible. La cuenta se bloquea al aceptar; un worker recupera el trabajo tras interrupciones. Consultar o cancelar una preparación no crea una segunda eliminación.
- **Concurrencia y Apple:** coordinación entre escrituras, login, revalidación de credenciales y purga. Los intercambios externos pendientes se registran antes de llamar a Apple. Un acceso iniciado antes de eliminar no recrea la cuenta; un alta explícita posterior sí puede crear otra. La revocación confirmada y la alternativa manual tienen resultados distintos.
- **Grupos:** los grupos con otros miembros pueden quedar pendientes de administración; una sola persona puede asumirla atómicamente. Se respetan los permisos personales. Si sale el último miembro de un grupo pendiente, la confirmación advierte de la eliminación de grupo e historial.
- **Dispositivo:** entrada separada en Ajustes, impacto y advertencia de suscripción, seguimiento tras cerrar/reabrir, limpieza confirmada y aislamiento entre Sandbox y producción. Un error de red al comprobar una sesión inválida conserva la credencial para verificarla después y bloquea los envíos. No se borran borradores ajenos ni se reasignan operaciones antiguas a una cuenta nueva.
- **Premium:** Restaurar compras inicia una recuperación solo tras comprobación local de StoreKit. El servidor vincula App Attest a cuenta nueva, reto, transacción exacta y entorno, reserva la cadena y verifica su estado con Apple. No traslada cadenas de otra cuenta activa ni recupera datos borrados. Una reasociación externa incierta puede quedar en cuarentena anónima para conciliación.
- **Compatibilidad:** contrato **0.6**, con `X-SmartList-Contract: 0.6` obligatorio salvo notificaciones Apple V2. Los clientes anteriores reciben `426 client_update_required`; requiere una entrega coordinada.

## Comprobaciones ejecutadas

| Comprobación | Resultado y alcance |
|---|---|
| Servidor, `swift build --build-tests --force-resolved-versions` | Correcto con Apple Swift 6.4.2. Único aviso externo conocido: [EXC-001, manifiesto de JWTKit](../dependency-exceptions.md). Sin nuevos warnings propios. |
| Servidor, `swift test --skip-build` | **204 pruebas en 13 suites, 0 fallos**, en 69,771 segundos. PostgreSQL exclusivo `db-test`, puerto 5433, sin conexión a bases alojadas. |
| Xcode MCP, Build for Testing | Correcto, esquema SmartShoppingList, simulador iPhone 18 Pro. |
| Xcode MCP, Fast | **514 ejecuciones, 294 métodos, 0 fallos y 0 avisos de runtime**, verificado en xcresult final. |
| Xcode MCP, Integration | **22 ejecuciones, 14 métodos, 0 fallos y 0 avisos de runtime**, verificado en xcresult. Incluye persistencia real de comprobantes en Keychain; los cambios posteriores no modifican ese mecanismo. |
| Contrato y ejemplos | **40 operaciones, 134 ejemplos positivos, 50 negativos**. Validación estructural JSON Schema 2020-12; no sustituye las pruebas HTTP. |
| Diseño | **65 pares × 4 modos y 23 assets × 4 variantes**, concordantes con las tablas canónicas. |
| Localización y previews | 63 claves nuevas con español; se conservan contenido y formato originales del catálogo. Inspección visual de eliminación completada en EN Large/XXXL/AX5, preparación en ES AX5 y administración pendiente en EN Large/ES AX5. |
| Revisiones independientes | Backend: ciclo persistente, seguridad, concurrencia, pruebas y estilo. iOS: arquitectura, estado, accesibilidad declarativa, pruebas y estilo. Hallazgos corregidos y releídos; sin hallazgos pendientes. |
| Formato | `git diff --check` correcto. |

Evidencia local, susceptible de limpieza de temporales:

- Servidor: `/tmp/smartlist-deletion-verified-build.log` y `/tmp/smartlist-deletion-verified-tests.log`.

- Fast: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/Test-SmartShoppingList-2026.11.09_19-11-17-+0100.xcresult`.
- Integration: `/var/folders/wt/r327qtw12_s5tbbcnx9dzqv80000gn/T/ActionArtifacts/default/RunAllTests/Test-SmartShoppingList-2026.11.09_18-57-44-+0100.xcresult`.

Los tests recorren HTTP/PostgreSQL, migraciones y reversiones, reconstrucción/purga histórica, administración concurrente, pérdida de respuesta, cancelación, reanudación tras lease vencido, intercambios Apple tardíos y comprobantes locales. Las pruebas criptográficas usan certificados y recibos CMS de un emisor de pruebas independiente, con defectos de identidad, clave, nonce, categoría/build, firma, fecha y raíz. Las pruebas de negocio utilizan dobles de Apple: no acreditan interoperabilidad real ni cambios en una cuenta Apple.

Durante la validación se corrigieron un acceso incorrecto a índices de `ArraySlice` al decodificar CBOR, las carreras de autenticación con eliminación, errores de contrato mal clasificados en iOS y la pérdida prematura de la credencial al no poder comprobar una eliminación remota. La última corrección de prueba limita la caducidad simulada a concesiones con un lease existente; no altera producción.

## Pendiente antes de activar

1. **Ensayo en Sandbox y TestFlight:** configurar App Attest/App Store y firma del nuevo build; comprobar con Apple real compra → eliminación → nueva cuenta → Restaurar compras → renovación V2. Validar otro comprador, otro dispositivo, cadena todavía vinculada, caducidad y respuesta incierta. La atestación usa producción en TestFlight aunque las compras sean Sandbox.
2. **Dispositivos físicos:** recorrer eliminación, cancelación, red perdida, segundo plano y limpieza del otro iPhone; VoiceOver y texto máximo. Las previews y pruebas de lógica no sustituyen esa interacción.
3. **Infraestructura:** ensayo de migración con datos representativos, copia y restauración; reaplicar supresiones antes de abrir una restauración. Comprobar retenciones, seguimiento de trabajos demorados y conciliación de recuperaciones en cuarentena. Coordinar servidor/cliente 0.6 sin escritores antiguos.
4. **Publicación:** completar identidad legal, correo operativo, revisión de proveedores/retenciones y textos ES/EN; publicar las URLs e integrar enlaces. Los borradores siguen sin publicar.

Al cerrar esta validación local todavía no se habían hecho commit ni push. La entrega posterior se registra en la PR y en #54. La autorización del 9/11 incluye commit, push, PR y CI, además de preparar el ensayo Sandbox/TestFlight; no incluye integrar en main ni activar producción.

Para la entrega se reutilizan las suites anteriores: los únicos cambios Swift posteriores son saltos de línea de seis bloques iOS, sin cambios de comportamiento. La auditoría final de estilo cubre 23 archivos Swift iOS y 47 del servidor, sin hallazgos. El smoke test de la imagen se adapta a 0.6 y habilita App Attest con configuración desechable para comprobar sus recursos; `bash -n` pasa y su ejecución Linux corresponde a la CI de la PR. No se han desplegado servicios, subido builds ni ejecutado eliminaciones reales.
