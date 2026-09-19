# Preparación de Git

Un único repositorio en la raíz contiene `ios/`, `server/` y `docs/`. Los comandos siguientes se ejecutan desde esa raíz; las dos ventanas de Xcode pueden seguir abiertas.

La inicialización y publicación de este repositorio se completaron el 19 de septiembre de 2026 con el commit `c19d087`, disponible en [GitHub](https://github.com/JFrancoG/SmartShoppingList/commit/c19d0872de623a712f2d640c3b0e31b7be27c623). Los comandos de inicialización y primer envío se conservan como referencia; no son tareas pendientes ni deben repetirse en este checkout.

## Archivos compartidos

- `.gitignore`: excluye compilaciones, estado personal de Xcode, configuración local y material de firma. Conserva el proyecto iOS, los assets y `Package.resolved`.
- `.gitattributes`: normaliza texto a LF y mantiene los archivos binarios como binarios.
- `.gitconfig`: configuración opcional y local de este repositorio. No se carga automáticamente por estar versionada; se activa con `include.path`.
- `CHANGELOG.md`: registro de cambios del repositorio.

El `.gitignore` de la plantilla de Vapor sigue limitado a `server/`. No se debe copiar su regla `*.xcodeproj` a la raíz, porque ocultaría el proyecto iOS.

La configuración compartida deja los finales de línea en manos de `.gitattributes`, permite únicamente avances directos al hacer `pull`, elimina referencias remotas obsoletas al hacer `fetch` y utiliza `push.default = simple`. Si las ramas divergen, el `pull` se detiene para resolverlo explícitamente. No cambia nombre, correo, credenciales, firma ni configuración global.

## Inicialización e identidad

```bash
git init -b main
git config set --local include.path ../.gitconfig
git var GIT_AUTHOR_IDENT
```

Comprueba el nombre y correo que muestra el último comando. Solo si necesitas establecer otra identidad para este repositorio, sustituye los ejemplos siguientes por tus datos:

```bash
git config set --local user.name "Tu nombre"
git config set --local user.email "tu-correo-verificado-en-github"
```

La ruta `../.gitconfig` se resuelve desde `.git/config`, por lo que apunta al archivo compartido de la raíz. Para verificar su lectura:

```bash
git config get --show-origin pull.ff
```

## Revisión y primer commit

```bash
git add .gitignore .gitattributes .gitconfig CHANGELOG.md README.md docs ios server
git status --short
git diff --cached --stat
git diff --cached --check
git diff --cached
```

Revisa el contenido preparado; sal del visor con `q`. No deben aparecer `.build`, `DerivedData`, `xcuserdata`, `.env` ni credenciales reales. Los valores de ejemplo de la plantilla no son configuración de producción.

Cuando la revisión sea correcta:

```bash
git commit -m "🔧 chore: initialize iOS and Vapor workspace"
git status --short --branch
```

## Conexión posterior con GitHub

Crea un repositorio vacío en GitHub, sin generar README, `.gitignore` ni licencia desde el asistente. Elige su visibilidad antes de subir el código y copia su URL HTTPS o SSH. Sustituye `URL_DEL_REPOSITORIO` por esa URL:

```bash
git remote add origin URL_DEL_REPOSITORIO
git remote -v
git push -u origin main
```

Cada clon nuevo necesita activar `.gitconfig` mediante el mismo comando `git config set --local include.path ../.gitconfig` si quiere utilizar estas preferencias.

## Referencias

- [Configuración e inclusión de archivos en Git](https://git-scm.com/docs/git-config).
- [Atributos y finales de línea](https://git-scm.com/docs/gitattributes).
- [Subir código local a GitHub](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github).
