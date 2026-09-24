# Configurar el recorrido compartido

El bloque 4 implementa acceso Apple, grupo, invitaciones, incorporación del borrador y consulta por tienda. Requiere un entorno HTTPS real para conectar dispositivos. Sin configurar los orígenes, la app permite preparar el borrador y explica que el acceso al grupo está pendiente.

La [issue #4](https://github.com/JFrancoG/SmartShoppingList/issues/4) conserva el estado operativo. La [arquitectura](../architecture/shared-shopping.md) explica las decisiones; el [informe de validación](../validation/issue-4-shared-flow.md) distingue las pruebas locales de las reales pendientes.

## Apple y backend

En Apple Developer, comprobar que el App ID `com.plusprojects.SmartShoppingList` pertenece al equipo usado para firmar la app y tiene activado Sign in with Apple. Preparar una clave de Sign in with Apple asociada a ese App ID. La app nativa usa ese bundle ID como `client_id`; este recorrido no utiliza login web ni un Service ID distinto.

El entitlement Sign in with Apple está incorporado al proyecto; habilitarlo en el portal y actualizar la firma sigue requiriendo la cuenta del equipo. La clave `.p8` nunca se incorpora al target iOS ni a la imagen Docker.

Para ejecución local, copiar `server/.env.example` a `server/.env` y reemplazar los marcadores. En el alojamiento, configurar las variables desde su gestor de secretos. Activar los tres identificadores, una única fuente de clave y las dos variables de cifrado:

| Variable | Valor |
|---|---|
| `APPLE_CLIENT_ID` | `com.plusprojects.SmartShoppingList` |
| `APPLE_TEAM_ID` | Team ID real de diez caracteres |
| `APPLE_KEY_ID` | ID de diez caracteres de la clave Sign in with Apple |
| `APPLE_PRIVATE_KEY_PATH` | Archivo `.p8` legible por el proceso, fuera de Git; alternativa excluyente con `APPLE_PRIVATE_KEY_PEM` |
| `APPLE_PRIVATE_KEY_PEM` | Contenido PEM multilínea de la clave, como secreto del alojamiento; alternativa excluyente con `APPLE_PRIVATE_KEY_PATH` |
| `APPLE_REFRESH_ACTIVE_KEY_VERSION` | Versión activa, inicialmente `v1` |
| `APPLE_REFRESH_KEYS_JSON` | Objeto JSON que asocia versiones a claves aleatorias de 32 bytes codificadas en base64 |
| `INVITATION_ORIGIN` | Origen público HTTPS del servidor de enlaces; por ejemplo el dominio real de la API, sin `/v1` |

Generar la clave de cifrado con un generador criptográfico, guardarla en el gestor de secretos del alojamiento y conservarla junto con las copias de seguridad autorizadas. No regenerarla en cada arranque: sin ella no se pueden revalidar las concesiones existentes. Al rotar, añadir una versión, cambiar la activa y conservar las versiones anteriores hasta que todas sus concesiones se hayan recifrado o revocado. La revalidación correcta recifra con la clave activa.

Vapor carga `.env` desde su directorio de trabajo. Con todas las variables Apple ausentes, el bootstrap local arranca, pero el acceso real devuelve indisponibilidad. La configuración de firma y la de cifrado se validan como familias independientes: una familia parcial, dos fuentes de clave simultáneas o una clave inválida impiden arrancar; activar ambas familias completas para habilitar el acceso. El PEM directo se consume en memoria, sin materializar un archivo. No existe una autenticación alternativa de producción.

Para el contenedor local con identidad, fijar `APPLE_PRIVATE_KEY_PATH=/run/secrets/apple-sign-in.p8` y `APPLE_PRIVATE_KEY_HOST_PATH` a la ruta privada del host. La clave debe ser legible por el usuario del contenedor mediante permisos acotados o un montaje de secretos adecuado; no hacerla pública. Ejecutar desde `server/`:

```bash
docker compose -f docker-compose.yml -f docker-compose.identity.yml up -d --build --wait app
```

El override opcional carga `.env` y monta la clave solo para lectura. El Compose habitual sigue sirviendo para desarrollo y pruebas sin credenciales Apple. Las credenciales de PostgreSQL que contiene el Compose local no se trasladan al alojamiento.

## HTTPS y alojamiento

Antes de contratar Railway, acordar presupuesto y alertas. La preparación de código y archivos no activa servicios de pago. Para desplegar el contenedor, usar `server/` como raíz de construcción, su Dockerfile y `/hello` como healthcheck. El proceso escucha en `0.0.0.0:8080`; fijar **`PORT=8080`**, además del puerto de destino 8080 del dominio: Railway usa esa variable para sus [healthchecks](https://docs.railway.com/deployments/healthchecks).

Railway puede generar un dominio con [HTTPS automático](https://docs.railway.com/networking/public-networking); no es necesario comprar uno para el ensayo. Su URL concreta se usa después en `INVITATION_ORIGIN`, los dos ajustes iOS y Associated Domains. El Dockerfile prescinde del cache mount de Swift porque Railway exige un [ID literal específico del servicio](https://docs.railway.com/builds/dockerfiles#cache-mounts); se conserva el mismo comando de compilación y se pierde esa caché entre builds. Los digests fijados admiten arm64 y amd64. La validación local arm64 no acredita la ejecución amd64 del alojamiento.

Preparar PostgreSQL con volumen persistente en el mismo proyecto y entorno. Referenciar sus variables desde el servicio de la API, sustituyendo `Postgres` por el nombre real del servicio:

| Variable de la API | Referencia Railway |
|---|---|
| `DATABASE_HOST` | `${{Postgres.PGHOST}}`, comprobando que es el dominio privado |
| `DATABASE_PORT` | `${{Postgres.PGPORT}}` |
| `DATABASE_USERNAME` | `${{Postgres.PGUSER}}` |
| `DATABASE_PASSWORD` | `${{Postgres.PGPASSWORD}}` |
| `DATABASE_NAME` | `${{Postgres.PGDATABASE}}` |

El [template PostgreSQL](https://docs.railway.com/databases/postgresql) genera su propia CA. Copiar **solo el certificado público** `root.crt` del servicio real a `DATABASE_CA_CERTIFICATE_PEM`; nunca copiar `root.key` ni `server.key`. Al configurar esa variable, la API exige TLS y verifica cadena y nombre del host; un PEM vacío o inválido impide arrancar. Comprobar que el certificado del servidor incluye el dominio privado en sus SAN: el [template actual](https://github.com/railwayapp-templates/postgres-ssl/blob/main/init-ssl.sh) lo incorpora desde `RAILWAY_PRIVATE_DOMAIN`, pero una base existente puede conservar un certificado anterior. No desactivar la verificación para sortear un certificado incorrecto; corregirlo en la base. Actualizar la CA de la API si se renueva la CA del servicio.

Sin esa variable, el desarrollo local conserva TLS preferente con la confianza del sistema. La red privada por sí sola no hace confiable una CA propia. El arranque aplica migraciones automáticamente; conservar la base entre versiones y verificar su copia de seguridad antes de actualizar un entorno con datos reales.

Configurar **una sola réplica de la app** para este MVP. La coordinación de revalidación de una concesión Apple reside en el proceso; ampliar réplicas requiere coordinación persistente adicional. En Railway, usar `APPLE_PRIVATE_KEY_PEM` como [variable multilínea sellada](https://docs.railway.com/variables), con saltos de línea reales, y omitir `APPLE_PRIVATE_KEY_PATH`. Definir una ruta no crea un archivo de secretos en el alojamiento. Sellar también las claves de cifrado. No incluir secretos en el Dockerfile, argumentos de build, Git ni logs.

Publicar en el dominio de enlaces, sin redirecciones:

- `GET /.well-known/apple-app-site-association`, JSON con el Team ID real y el bundle ID.
- `GET /invite/<uuid>`, página informativa que no consulta ni acepta invitaciones.

No configurar logs de cuerpos o cabeceras de autenticación en el proxy. El servidor limita el logger HTTP a `info` como mínimo y omite el diagnóstico de consultas que podría contener valores privados.

## Configuración de iOS

En el target `SmartShoppingList`, añadir en **Build Settings → User-Defined** los valores para Debug y Release:

| Ajuste | Valor |
|---|---|
| `SHARED_API_BASE_URL` | Origen HTTPS real de la API, sin `/v1` ni otra ruta |
| `SHARED_INVITATION_ORIGIN` | Mismo origen que `INVITATION_ORIGIN` en el servidor |

`Info.plist` ya referencia estos ajustes. Los dominios `.example`, valores vacíos, marcadores sin expandir, HTTP, credenciales en URL y rutas de base se rechazan. Los nombres de dominio no son secretos; no guardar ninguna clave Apple o de cifrado en estos ajustes.

Cuando se conozca el dominio real, añadir **Signing & Capabilities → Associated Domains** con `applinks:<dominio-real>`, sin `https://` ni ruta, y actualizar el perfil de firma. No se ha introducido un dominio ficticio en el entitlement. El servidor AASA permite `/invite/*` y no excluye el fragmento `#token=…`.

Compilar e instalar de nuevo tras configurar los dominios. Comprobar la asociación efectiva desde Mail o Mensajes: abrir una URL en el navegador o pasarla directamente a un simulador no acredita la entrega de un Universal Link real.

## Ensayo con dos personas

1. Con dos Apple IDs distintos, acceder en dos clientes y verificar que la primera cuenta puede crear el grupo.
2. Desde **Comprar → Gestionar invitaciones**, crear y compartir un enlace. Abrirlo en el segundo cliente sin sesión: debe mostrar Comprar, conservarlo durante el acceso y pedir aceptación explícita.
3. Confirmar que los enlaces caducados, revocados, consumidos por otra cuenta o manipulados no permiten incorporarse. La previsualización y el GET web no consumen el enlace.
4. En el primer cliente, preparar un producto manual con su tienda, revisarlo, elegir la tienda del grupo o confirmar su nombre y pulsar **Confirmar incorporación al grupo**.
5. En ambos clientes, seleccionar la misma tienda y actualizar. Cortar la red durante otro envío y reintentar la operación conservada; debe aparecer una sola incorporación.
6. Reiniciar la app iOS y el proceso del servidor; comprobar sesión, pertenencia, pendientes e idempotencia. Las credenciales y el sobre pendiente se mantienen en Keychain del mismo dispositivo.
7. Registrar los resultados físicos manuales y, por separado, la entrada de voz/IA del entorno compatible según [#7](https://github.com/JFrancoG/SmartShoppingList/issues/7).

La consulta se actualiza expresamente; no hay tiempo real. Edición, cancelación, checks de compra, finalización e historial corresponden a la fase 2 y aún no forman parte de estas pantallas.
