# Fuentes del sistema de diseño y revisión de actualidad

Consulta: **23 de septiembre de 2026**. Alcance: diseño y accesibilidad de SmartShoppingList para iOS 27. Las capturas de Saotome y el icono candidato son referencias aportadas por el usuario, no instrucciones normativas ni evidencia de cumplimiento.

## Qué cambia respecto a una referencia de iOS 26

| Fuente primaria | Versión/estado observado | Decisión para el proyecto |
|---|---|---|
| [WCAG 2.2](https://www.w3.org/TR/WCAG22/) | W3C Recommendation, 12 diciembre 2024 | Base estable de criterios A/AA; mejora propia de contraste de texto a 7:1 en HC |
| [WCAG 3.0](https://www.w3.org/TR/wcag-3.0/) | Working Draft, 10 septiembre 2026 | Es más reciente, pero no sustituye WCAG 2.2 como compromiso de conformidad |
| [WCAG2ICT](https://www.w3.org/TR/wcag2ict-22/) | Group Note, 11 diciembre 2025 | Guía informativa para trasladar criterios a software nativo; no certificación independiente |
| [WCAG2Mobile](https://www.w3.org/TR/wcag2mobile-22/) | Group Draft Note, 6 mayo 2025 | Consulta complementaria específica de móviles; sigue siendo trabajo en curso |
| [WCAG-EM 2.0](https://www.w3.org/TR/wcag-em-2/) | Group Note, 23 julio 2026 | Novedad útil: metodología para definir alcance, muestra, evaluación y evidencias de productos digitales; no añade umbrales |
| [WWDC26: guía de diseño](https://developer.apple.com/wwdc26/guides/design/) | Recursos públicos de 2026 | Referencia anual actual frente a las sesiones de 2025; incluye herramientas e identidad, no obliga a ampliar el MVP |
| [Platforms State of the Union, WWDC26](https://developer.apple.com/videos/play/wwdc2026/102/) | Sección de diseño de las versiones 27 | Revisar material, personalización y adaptación de tamaño con el runtime/SDK actual |
| [Principles of great design, WWDC26](https://developer.apple.com/videos/play/wwdc2026/250/) | Sesión y nueva página de principios | Mantener claridad, control del usuario y flexibilidad; revisión antes de cualquier escritura compartida |

La sesión State of the Union describe mayor difusión del contenido tras el vidrio, ajustes de bordes/reflejos y un control de personalización de transparencia/tintado. Indica que parte de la mejora llega automáticamente a apps que ya usan Liquid Glass al ejecutarse en las versiones 27. También presenta redimensionamiento de apps iOS en iPad y iPhone Mirroring al reconstruir con el SDK nuevo. Por ello, el ensayo incluye fondos durante scroll, preferencias del sistema y tamaños variables; compilar con el SDK nuevo no demuestra accesibilidad.

No se ha encontrado en estas fuentes un cambio de los umbrales WCAG 2.2 por la llegada de iOS 27. Las HIG son documentación viva: una fecha antigua en su historial no invalida una regla que Apple sigue publicando. No se inventa una «WCAG para iOS 27» ni se sustituye el cálculo por APCA para declarar AA.

## Apple: diseño nativo y comprobación

Se consultaron las HIG mediante Cupertino y se contrastaron Color y Accessibility con el JSON público actual de Apple Developer. Cupertino facilita la lectura, pero su corpus local no prueba por sí mismo que una página recoja las novedades de 2026.

- [HIG Color](https://developer.apple.com/design/human-interface-guidelines/color): uso semántico consistente, colores del sistema y cuatro variantes para colores propios. Aplicación: acento de marca limitado y pares explícitos; no pintar toda la UI del verde del icono.
- [HIG Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility): preferencias, alternativas de interacción y evaluación. La tabla actual distingue tamaño de control predeterminado 44×44 pt y mínimo 28×28 pt para iOS/iPadOS; **el proyecto elige ≥44×44 pt**. No se atribuye a Apple un mínimo universal actual de 44 pt.
- [HIG VoiceOver](https://developer.apple.com/design/human-interface-guidelines/voiceover): nombres, descripciones y navegación. Los errores y el retorno al editor necesitan ensayo real.
- [HIG Typography](https://developer.apple.com/design/human-interface-guidelines/typography): estilos y Dynamic Type. Las medidas de la escala propia no sustituyen fuentes semánticas.
- [SwiftUI ColorSchemeContrast](https://developer.apple.com/documentation/swiftui/colorschemecontrast) y [Show Button Shapes](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityshowbuttonshapes): preferencias que deben respetar los componentes propios, además de las variantes del catálogo.
- [Accessibility Nutrition Labels](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/overview-of-accessibility-nutrition-labels): una declaración de soporte depende de comprobar los recorridos; no se publica basándose en una paleta.

Las HIG permiten colores personalizados y recomiendan preferir los del sistema. La solución combina identidad en contenido propio con presentación nativa de navegación, autenticación y controles. Es una decisión de diseño del proyecto, no un requisito de Apple de utilizar estos HEX.

## W3C: lectura precisa de los umbrales

- [1.4.3, contraste mínimo](https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html): 4,5:1 para texto normal y 3:1 para texto grande; no redondear antes de decidir. WCAG define texto grande como al menos 18 pt o 14 pt en negrita, aproximadamente 24/18,67 CSS px. No trasladar mecánicamente CSS px a puntos iOS. La política de 4,5 para todo texto evita depender de esa clasificación.
- [1.4.6, contraste mejorado](https://www.w3.org/WAI/WCAG22/Understanding/contrast-enhanced.html): 7:1 para texto normal y 4,5:1 para grande. Adoptar 7:1 en HC es una mejora acotada; no acredita todos los criterios AAA.
- [1.4.11, contraste no textual](https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html): 3:1 para información visual esencial de controles/estados y gráficos frente a colores adyacentes. No exige que cada superficie decorativa contraste 3:1 con el lienzo; tampoco define un nivel AAA para componentes.
- [1.4.1, uso del color](https://www.w3.org/WAI/WCAG22/Understanding/use-of-color.html): acompañar el color con identificación independiente. En el MVP, check provisional, compra confirmada y cancelación son estados diferentes.
- [2.5.8, objetivo mínimo](https://www.w3.org/WAI/WCAG22/Understanding/target-size-minimum.html): AA establece 24×24 CSS px o las condiciones/excepciones admitidas. [2.5.5](https://www.w3.org/WAI/WCAG22/Understanding/target-size-enhanced.html) utiliza 44×44 CSS px en AAA. Los 44×44 pt de esta app son una política táctil nativa, no una conversión física exacta de unidades web.

## Límite de la conclusión

Hay fuentes pertinentes posteriores a 2025 y están incorporadas. Lo acreditado en esta entrega documental es la investigación, la definición de tokens y el cálculo de pares. Quedan por verificar asignación en assets, composición renderizada, componentes nativos, tecnologías de asistencia y flujos completos. La matriz de [accesibilidad](../accessibility.md) define esa aceptación; las fuentes deben revisarse si cambian el SDK, la versión de iOS o el alcance antes de publicar afirmaciones de conformidad.
