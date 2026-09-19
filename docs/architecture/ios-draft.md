# Borrador iOS: decisiones del bloque 3

Perfil `greenfield-xcode27`, aplicado a la plantilla existente con iOS 27, Swift 6 y concurrencia estricta. El alcance procede de [#3](https://github.com/JFrancoG/SmartShoppingList/issues/3), la [spec](../mvp-spec.md) y el [contrato](../contracts/mvp-api.md).

- `Features/AddItems` contiene valores de borrador, reglas, presentación y adaptadores. El borrador admite campos incompletos; preparar una entrada exige las invariantes del contrato. No se introduce un catálogo ni una deduplicación de productos.
- Un ViewModel `@Observable @MainActor` coordina las intenciones de la pantalla. Las Views muestran estado y bindings. Los servicios reciben capacidades pequeñas por inicializador; las sustituciones permiten comprobar fallos y respuestas tardías sin usar modelos ni micrófono reales en unitarias.
- Foundation Models crea propuestas con una sesión nueva por interpretación. Una revisión de estado identifica la solicitud; modificar el borrador o cancelar invalida resultados tardíos. Las propuestas se añaden sin sobrescribir entradas corregidas y siempre requieren revisión humana.
- Un actor posee la captura Speech y su ciclo de vida. Usa `SpeechAnalyzer`, `SpeechTranscriber` y `CaptureInputSequenceProvider` del SDK 27, con permiso de micrófono, disponibilidad de español y assets. No se introduce reconocimiento remoto ni una dependencia de Apple Intelligence para la entrada manual.
- El borrador local es un agregado pequeño y acotado. Un actor conserva un snapshot Codable mediante escritura atómica en Application Support; no se necesita un grafo SwiftData para este único documento. La persistencia se serializa y conserva el último estado ante errores. Este archivo no es una cola offline ni una escritura compartida.
- La revisión local valida productos, cantidades y tienda sin comunicar que se han guardado en el grupo. El envío autenticado y la resolución de tiendas por ID se implementan con #4; el contrato del backend sigue siendo la autoridad de normalización de claves.

Las comprobaciones deterministas usan Swift Testing. Las pruebas reales de interpretación, transcripción, físico, VoiceOver y texto grande se registran por separado con entorno y límites. El target UI heredado de la plantilla no se presenta como cobertura de esos recorridos.

La interfaz tiene español como idioma de desarrollo y usa String Catalog para sus textos. Los permisos se piden únicamente al iniciar el dictado; el estado `.inactive` provocado por un diálogo de permiso no cancela la operación. Entrar en segundo plano sí detiene la captura.

La normalización usa la transformación NFC de Foundation (`String.applyingTransform` con `Any-NFC`) y comprueba equivalencia canónica antes de colapsar espacios. En el SDK 27 se reprodujo pérdida de escalares con `precomposedStringWithCanonicalMapping` al repetir U+0344 más de 32 veces; las regresiones exigen conservar la secuencia completa o rechazarla por su longitud, sin truncarla. Las formas y los límites permanecen alineados con el contrato.

El esquema compartido ofrece los planes `Fast` (dominio y coordinación con dobles) e `Integration` (persistencia en disco temporal). Se seleccionan mediante tags de Swift Testing. El probe de modelos reales vive fuera del target automático para que la ausencia de hardware o assets no se confunda con cobertura determinista; su resultado real se registra por separado.
