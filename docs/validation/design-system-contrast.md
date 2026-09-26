# Validación de contraste del sistema de diseño

Informe generado desde las tablas de [tokens y pares](../design-system.md). No editar a mano.

Resultado: **PASA** · 244/244 comprobaciones con umbral; 12 mediciones decorativas sin umbral.

Huella SHA-256 de las tablas: `37dd6bd4b1ebe4be724e8352a9f0ec80b72f5a45162f78ca76e90d8fb5b83e55`.

## Método y alcance

Colores opacos sRGB de 8 bits. Canal c = byte/255; linealización: c/12,92 si c ≤ 0,04045, en otro caso ((c + 0,055)/1,055)^2,4. L = 0,2126 R + 0,7152 G + 0,0722 B. Ratio = (L mayor + 0,05)/(L menor + 0,05). Se compara sin redondear; la tabla muestra dos decimales.

`text`: objetivo propio 4,5:1 Light/Dark y 7:1 HC, incluso si el texto es grande. `ui`: 3:1 en los cuatro modos. `decorative`: no se usa para identificar un control o estado. La fórmula y criterios proceden de [WCAG 2.2](https://www.w3.org/TR/WCAG22/#dfn-relative-luminance); el umbral HC es una decisión del proyecto.

El verificador también comprueba los 21 colorsets del catálogo: nombres derivados de los tokens en PascalCase, con prefijo `App` solo en `AppPrimary` y `AppSeparator` para evitar colisiones, cuatro variantes únicas con idiom universal, sRGB opaco y bytes RGB idénticos a la tabla. Rechaza `AccentColor` y colorsets inesperados.

Sólo se acreditan estos pares nominales y su correspondencia con los archivos de assets. No se ha ejecutado la app ni medido materiales, antialiasing, resolución de assets en ejecución, controles nativos, Dynamic Type, foco o VoiceOver. No equivale a conformidad AA/AAA del producto.

## Mínimos entre los pares exigidos

| Modo | Texto mínimo | Par de texto limitante | UI mínimo |
|---|---|---|---|
| Light | 5.43:1 | text-tertiary / surface-muted | 3.73:1 |
| Dark | 6.23:1 | text-tertiary / surface-muted | 4.58:1 |
| HC Light | 8.22:1 | text-tertiary / surface-muted | 7.78:1 |
| HC Dark | 10.66:1 | danger / primary-soft | 10.65:1 |

## Todos los pares

Cada celda sin marca de fallo supera su umbral; en filas decorativas el resultado es N/A.

| Foreground | Background | Clase | Light | Dark | HC Light | HC Dark |
|---|---|---|---|---|---|---|
| text-primary | canvas | text | 14.65:1 | 16.50:1 | 21.00:1 | 21.00:1 |
| text-primary | surface | text | 15.40:1 | 14.42:1 | 21.00:1 | 18.98:1 |
| text-primary | surface-muted | text | 13.53:1 | 11.77:1 | 18.90:1 | 16.33:1 |
| text-secondary | canvas | text | 7.48:1 | 11.39:1 | 13.29:1 | 17.42:1 |
| text-secondary | surface | text | 7.87:1 | 9.96:1 | 13.29:1 | 15.75:1 |
| text-secondary | surface-muted | text | 6.91:1 | 8.12:1 | 11.96:1 | 13.55:1 |
| text-tertiary | canvas | text | 5.89:1 | 8.74:1 | 9.13:1 | 14.77:1 |
| text-tertiary | surface | text | 6.19:1 | 7.64:1 | 9.13:1 | 13.35:1 |
| text-tertiary | surface-muted | text | 5.43:1 | 6.23:1 | 8.22:1 | 11.48:1 |
| primary | canvas | text | 6.30:1 | 10.81:1 | 10.03:1 | 15.88:1 |
| primary | surface | text | 6.63:1 | 9.45:1 | 10.03:1 | 14.35:1 |
| primary | surface-muted | text | 5.82:1 | 7.71:1 | 9.03:1 | 12.34:1 |
| success | canvas | text | 6.90:1 | 11.02:1 | 10.20:1 | 16.65:1 |
| success | surface | text | 7.26:1 | 9.63:1 | 10.20:1 | 15.04:1 |
| success | surface-muted | text | 6.38:1 | 7.86:1 | 9.18:1 | 12.94:1 |
| warning | canvas | text | 6.91:1 | 12.52:1 | 10.97:1 | 16.60:1 |
| warning | surface | text | 7.27:1 | 10.94:1 | 10.97:1 | 15.00:1 |
| warning | surface-muted | text | 6.38:1 | 8.93:1 | 9.88:1 | 12.90:1 |
| danger | canvas | text | 6.22:1 | 10.47:1 | 10.14:1 | 14.57:1 |
| danger | surface | text | 6.54:1 | 9.15:1 | 10.14:1 | 13.17:1 |
| danger | surface-muted | text | 5.74:1 | 7.46:1 | 9.13:1 | 11.33:1 |
| info | canvas | text | 6.43:1 | 11.28:1 | 10.44:1 | 16.11:1 |
| info | surface | text | 6.76:1 | 9.86:1 | 10.44:1 | 14.56:1 |
| info | surface-muted | text | 5.94:1 | 8.04:1 | 9.40:1 | 12.53:1 |
| text-primary | primary-soft | text | 13.02:1 | 10.94:1 | 18.36:1 | 15.36:1 |
| text-primary | success-soft | text | 13.23:1 | 11.12:1 | 18.55:1 | 14.86:1 |
| text-primary | warning-soft | text | 13.54:1 | 10.82:1 | 18.77:1 | 14.96:1 |
| text-primary | danger-soft | text | 12.96:1 | 12.40:1 | 18.16:1 | 16.35:1 |
| text-primary | info-soft | text | 13.12:1 | 11.35:1 | 18.64:1 | 15.63:1 |
| primary | primary-soft | text | 5.60:1 | 7.17:1 | 8.77:1 | 11.61:1 |
| text-secondary | primary-soft | text | 6.65:1 | 7.56:1 | 11.62:1 | 12.74:1 |
| danger | primary-soft | text | 5.53:1 | 6.94:1 | 8.87:1 | 10.66:1 |
| success | success-soft | text | 6.24:1 | 7.43:1 | 9.01:1 | 11.78:1 |
| warning | warning-soft | text | 6.39:1 | 8.21:1 | 9.80:1 | 11.83:1 |
| danger | danger-soft | text | 5.50:1 | 7.87:1 | 8.77:1 | 11.34:1 |
| info | info-soft | text | 5.76:1 | 7.76:1 | 9.27:1 | 12.00:1 |
| on-primary | primary | text | 6.63:1 | 10.31:1 | 10.03:1 | 15.88:1 |
| on-yellow | brand-yellow | text | 8.19:1 | 11.16:1 | 10.67:1 | 16.60:1 |
| border | canvas | ui | 4.21:1 | 6.98:1 | 8.99:1 | 15.05:1 |
| border | surface | ui | 4.43:1 | 6.10:1 | 8.99:1 | 13.60:1 |
| border | surface-muted | ui | 3.89:1 | 4.98:1 | 8.10:1 | 11.70:1 |
| border | primary-soft | ui | 3.75:1 | 4.63:1 | 7.86:1 | 11.01:1 |
| border | success-soft | ui | 3.81:1 | 4.71:1 | 7.94:1 | 10.65:1 |
| border | warning-soft | ui | 3.90:1 | 4.58:1 | 8.04:1 | 10.73:1 |
| border | danger-soft | ui | 3.73:1 | 5.25:1 | 7.78:1 | 11.72:1 |
| border | info-soft | ui | 3.78:1 | 4.80:1 | 7.98:1 | 11.21:1 |
| primary | canvas | ui | 6.30:1 | 10.81:1 | 10.03:1 | 15.88:1 |
| primary | surface | ui | 6.63:1 | 9.45:1 | 10.03:1 | 14.35:1 |
| primary | surface-muted | ui | 5.82:1 | 7.71:1 | 9.03:1 | 12.34:1 |
| success | canvas | ui | 6.90:1 | 11.02:1 | 10.20:1 | 16.65:1 |
| success | surface | ui | 7.26:1 | 9.63:1 | 10.20:1 | 15.04:1 |
| success | surface-muted | ui | 6.38:1 | 7.86:1 | 9.18:1 | 12.94:1 |
| warning | canvas | ui | 6.91:1 | 12.52:1 | 10.97:1 | 16.60:1 |
| warning | surface | ui | 7.27:1 | 10.94:1 | 10.97:1 | 15.00:1 |
| warning | surface-muted | ui | 6.38:1 | 8.93:1 | 9.88:1 | 12.90:1 |
| danger | canvas | ui | 6.22:1 | 10.47:1 | 10.14:1 | 14.57:1 |
| danger | surface | ui | 6.54:1 | 9.15:1 | 10.14:1 | 13.17:1 |
| danger | surface-muted | ui | 5.74:1 | 7.46:1 | 9.13:1 | 11.33:1 |
| info | canvas | ui | 6.43:1 | 11.28:1 | 10.44:1 | 16.11:1 |
| info | surface | ui | 6.76:1 | 9.86:1 | 10.44:1 | 14.56:1 |
| info | surface-muted | ui | 5.94:1 | 8.04:1 | 9.40:1 | 12.53:1 |
| separator | canvas | decorative | 1.33:1 N/A | 2.04:1 N/A | 8.99:1 N/A | 15.05:1 N/A |
| separator | surface | decorative | 1.40:1 N/A | 1.78:1 N/A | 8.99:1 N/A | 13.60:1 N/A |
| separator | surface-muted | decorative | 1.23:1 N/A | 1.46:1 N/A | 8.10:1 N/A | 11.70:1 N/A |

## Reproducción

Desde la raíz del repositorio, Python 3 sin paquetes externos:

```bash
python3 scripts/validate_design_system.py
```

Tras editar tokens o pares:

```bash
python3 scripts/validate_design_system.py --write
```

La ejecución normal falla si algún par no pasa, los assets no coinciden con el contrato o el informe o la lámina SVG no coinciden con las tablas. La opción `--write` regenera solo el informe y la lámina SVG; nunca escribe assets y también devuelve error si hay pares fallidos o assets inválidos. Las comprobaciones de interfaz se conservan en el [protocolo de accesibilidad](../accessibility.md).
