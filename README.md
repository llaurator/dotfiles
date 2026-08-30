# dotfiles

Dotfiles centralizados para macOS Apple Silicon (también compatible con Homebrew Intel),
Arch, Fedora/Fedora Asahi y Debian/Ubuntu. GNU Stow crea los enlaces y un instalador Bash
detecta la plataforma, instala dependencias y activa uno de tres perfiles.

## Instalación rápida

La opción más sencilla descarga el bootstrap auditable desde GitHub y abre el menú
interactivo del instalador:

```bash
curl -fsSL https://raw.githubusercontent.com/llaurator/dotfiles/main/bootstrap.sh | bash
```

Instalación no interactiva para un servidor:

```bash
curl -fsSL https://raw.githubusercontent.com/llaurator/dotfiles/main/bootstrap.sh \
  | bash -s -- --profile server --yes
```

Instalación reproducible desde una release concreta:

```bash
curl -fsSL https://raw.githubusercontent.com/llaurator/dotfiles/main/bootstrap.sh \
  | bash -s -- --ref v1.1.0 --profile server --yes
```

El repositorio permanece en `${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles`, o en la ruta
absoluta indicada mediante `DOTFILES_DIR`. Es necesario conservarlo porque los enlaces de
GNU Stow apuntan a sus archivos. El bootstrap clona por HTTPS, actualiza `main` solo mediante
fast-forward y conserva cualquier cambio local sin aplicar `reset` ni `clean`.

## Instalación manual y perfiles

```bash
git clone https://github.com/llaurator/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

El modo interactivo ofrece `personal`, `work` y `server`. Para automatización:

```bash
./install.sh --profile personal --yes
./install.sh --profile work --yes
./install.sh --profile server --yes
```

`--yes` requiere `--profile` y omite las preguntas propias del instalador; `sudo`, el
gestor de paquetes, `chsh` o macOS aún pueden pedir autorización. El perfil se guarda en
`~/.config/dotfiles/profile` y `.zshrc` lo carga en cada sesión. `personal` y `work`
incluyen la capa opcional `development.zsh`; `server` evita SSH cliente del repositorio,
VS Code y configuración de escritorio.

El sistema se detecta con `uname` y el gestor disponible. Git, Stow y Zsh son esenciales.
fzf, fd, zoxide, eza, bat, ripgrep, btop, grc, git-delta y direnv se obtienen del gestor
nativo cuando están disponibles. Debian/Ubuntu y Fedora avisan y continúan si falta un
paquete opcional. Debian crea los nombres compatibles `fd`/`bat` para `fdfind`/`batcat`.
Arch usa `pacman -S --needed`, sin AUR ni actualización completa forzada. macOS conserva
el Zsh del sistema y requiere Homebrew.

Oh My Zsh, Powerlevel10k, zsh-autosuggestions, zsh-history-substring-search y
zsh-syntax-highlighting se clonan directamente desde upstream. Powerlevel10k se carga
desde `~/.oh-my-zsh/custom/themes/powerlevel10k`, su instant prompt permanece al principio
de `.zshrc` y `.p10k.zsh` se carga al final. Las herramientas opcionales nunca son un
requisito para abrir Zsh.

## Estructura Stow

- `zsh`: `.zshrc`, configuración completa de Powerlevel10k y módulos por plataforma/perfil.
- `git`: configuración común, sin identidad.
- `btop`: configuración mínima.
- `ssh`: cliente y `config.d`, solo para `personal`/`work`.
- `vscode`: única fuente versionada de settings y extensiones, solo para desktop.

El despliegue usa `--restow --no-folding`: no convierte `~/.ssh` o `~/.config` completos
en enlaces. Antes de invocar Stow, un preflight lista los archivos reales que entrarían en
conflicto y cancela por defecto. Nunca usa `stow --adopt` ni sobrescribe esos archivos.

## Baseline y restauración

La primera instalación nueva crea una baseline por ciclo en
`${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/cycles/`. Su manifest versionado registra
solo las rutas que el instalador puede gestionar, conserva archivos, directorios y symlinks
previos, y mantiene huellas para detectar modificaciones posteriores. Una segunda instalación
reutiliza la baseline activa; después de restaurarla, una instalación nueva crea otro ciclo.

Los conflictos de Stow siguen cancelando de forma predeterminada. En modo interactivo se puede
elegir «Hacer copia de seguridad y continuar»; en automatización requiere intención explícita:

```bash
./install.sh --profile personal --yes --backup-conflicts
```

Para inspeccionar o restaurar:

```bash
./install.sh --status
./install.sh --uninstall --dry-run
./install.sh --uninstall
./install.sh --uninstall --keep-packages
./install.sh --uninstall --yes
```

La restauración solo retira enlaces o archivos que todavía pueda demostrar como propios. Si una
ruta fue sustituida o modificada después, aborta antes de sobrescribirla. Las instalaciones
anteriores al sistema de baseline se reconocen como tales: solo pueden retirar enlaces Stow
verificables y no prometen reconstruir un estado previo desconocido.

Por defecto, una baseline de formato 2 restaura el shell solo si aún coincide con el que puso
el ciclo y retira exclusivamente paquetes explícitos que ese ciclo introdujo. No usa
`autoremove`; si el preflight detecta retiradas laterales no registradas, aborta. También puede
retirar clones upstream intactos y directorios creados que hayan quedado vacíos.
`--keep-packages` conserva paquetes y clones upstream, realizando solo
el rollback de configuración, shell y directorios. Las baselines de formato 1 mantienen el
rollback conservador antiguo y no inventan estado previo ausente.

Nunca se eliminan el repositorio ni extensiones de VS Code. Tampoco se revierten
`.bash_history`, `.zsh_history` o su backup de migración, y nunca se toca la
configuración local `~/.ssh/config.d/*.conf`. Para VS Code, la baseline es la fuente de verdad
del rollback; `settings.json.pre-dotfiles` se registra como ruta gestionada dentro del mismo
ciclo cuando el instalador lo crea. Por seguridad, tampoco se revierte automáticamente
una modificación posterior del usuario. Los modes de directorios se restauran únicamente si
siguen coincidiendo con el valor aplicado por el instalador.

Dry-run contra un HOME temporal:

```bash
tmp_home="$(mktemp -d)"
stow -n -v --no-folding --dir="$PWD" --target="$tmp_home" zsh git btop ssh vscode
```

Para retirar un paquete:

```bash
stow -D --no-folding --dir="$PWD" --target="$HOME" zsh
```

En una máquina con `~/.zshrc`, `~/.p10k.zsh`, `~/.gitconfig` o `~/.ssh/config`
preexistentes, compáralos y respáldalos o migra su contenido manualmente. **No uses
`stow --adopt` a ciegas**: puede introducir datos locales y secretos en el repositorio.

## Git

`git/.gitconfig` contiene únicamente opciones comunes y carga
`~/.config/git/local.gitconfig`. Tras desplegar Stow, el instalador conserva la identidad
efectiva si ya existen `user.name` y `user.email`. Si falta alguno, el modo interactivo
ofrece configurarla con respuesta predeterminada «no». Solo añade las claves ausentes al
fichero local mediante `git config --file`, conserva el resto y aplica modo `0600`.

En modo `--yes` nunca pregunta por la identidad: avisa si está incompleta y continúa sin
inventar valores. `local.gitconfig` está ignorado y no se versiona.

## SSH y secretos

`ssh/.ssh/config` es genérico e incluye `~/.ssh/config.d/*`. Solo los `*.example` vacíos
se versionan; los `*.conf` reales son locales. El instalador crea `~/.ssh` y `config.d`
con modo `0700`, sin generar hosts ni claves ni reemplazar configuraciones locales. Si no
hay ningún `*.conf` local tras el despliegue, muestra un mensaje informativo para recordar
que se pueden copiar y adaptar los ejemplos; esa situación no se considera un error.

Claves privadas y públicas, `known_hosts`, `authorized_keys`, sockets, tokens y `.env`
están ignorados. Revisa siempre `git status` antes de confirmar cambios.

## VS Code

La lista versionada contiene exclusivamente Prettier, Ruff, Python Environments, Spanish
Language Pack y Dracula Official. Python Environments descubre y permite seleccionar los
entornos virtuales de los proyectos Python, incluidos los directorios `.venv`. Las extensiones
ya instaladas se detectan sin distinguir mayúsculas y minúsculas, y solo se invoca la
instalación para las ausentes. `settings.json` activa formato al guardar, Prettier para JS, TS,
JSON, CSS y HTML, Ruff para Python, limpieza de espacios, newline final, regla a 100, minimapa
desactivado y `Dracula Theme`. El idioma puede seleccionarse con “Configure Display
Language”; no se mantiene un fichero de locale dependiente de versión.

En macOS se instala el cask `visual-studio-code`; en Arch, el paquete oficial `code`.
Fedora y Debian/Ubuntu no reciben repositorios Microsoft: si `code` falta, se avisa y se
continúa. La fuente de settings es única. El instalador enlaza a
`~/.config/dotfiles/vscode/settings.json` mediante Stow y aplica su contenido a
`~/Library/Application Support/Code/User/settings.json` en macOS o a
`${XDG_CONFIG_HOME:-~/.config}/Code/User/settings.json` en Linux. Nunca reemplaza un
archivo local a ciegas: valida con `jq` y fusiona las claves locales con las gestionadas,
dando prioridad a estas últimas cuando coinciden. Conserva las claves locales adicionales,
crea una única copia original `settings.json.pre-dotfiles` y reemplaza el destino mediante un
temporal validado. Si el JSON local no es válido, lo deja intacto, avisa y continúa con el
resto de la instalación. `jq` se instala como dependencia del sistema.

## Desarrollo y macOS

`development.zsh` detecta pyenv, Android SDK, Flutter, Java, Miniconda y thefuck antes de
cargarlos. `macos.zsh`, cargado antes de `common.zsh`, busca Homebrew en
`/opt/homebrew/bin/brew`, `/usr/local/bin/brew` y finalmente en `PATH`, y ejecuta
`brew shellenv` una sola vez.

## Probar cambios

Antes de desplegar, ejecuta:

```bash
bash -n bootstrap.sh install.sh scripts/*.sh tests/*.sh
zsh -n zsh/.zshrc zsh/.config/zsh/*.zsh
git diff --check
./install.sh --help
```

Si están disponibles, añade `shellcheck bootstrap.sh install.sh scripts/*.sh tests/*.sh` y
`jq empty` sobre
`vscode/.config/dotfiles/vscode/settings.json`, además del dry-run temporal anterior.
`./install.sh --help` solo muestra ayuda; no instala nada.

## Migrar el historial de Bash

La migración es una operación explícita y separada de la instalación normal:

```bash
./install.sh --migrate-bash-history
./install.sh --migrate-bash-history --dry-run
```

Importa comandos únicos de `~/.bash_history` en `~/.zsh_history`, conserva el historial Zsh
y crea una única copia inicial `~/.zsh_history.pre-bash-migration`. El fichero Bash nunca se
modifica. Los timestamps de Bash se descartan y las entradas nuevas se escriben en el formato
extendido que usa `SHARE_HISTORY`. Antes de importar se omiten patrones evidentes de posibles
secretos y solo se muestran estadísticas, nunca los comandos. Este filtro es conservador y no
garantiza detectar todos los secretos; revisa el historial de origen antes de migrarlo.

## Releases

Cada push a `main` ejecuta semantic-release en GitHub Actions. Los commits `feat` generan
una versión minor; `fix`, `perf`, `security` y `revert`, una patch; y cualquier breaking
change, una major. `docs`, `refactor`, `chore`, `build`, `ci` y `test` aparecen en las notas
cuando existe una release, pero no crean una versión por sí solos.

El workflow crea el tag `vX.Y.Z`, actualiza `CHANGELOG.md`, confirma ese cambio con
`[skip ci]` y publica la GitHub Release usando únicamente el `GITHUB_TOKEN` del repositorio.
No publica paquetes npm y no se ejecuta para pull requests.
