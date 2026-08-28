# dotfiles

Dotfiles centralizados para macOS Apple Silicon (también compatible con Homebrew Intel),
Arch, Fedora/Fedora Asahi y Debian/Ubuntu. GNU Stow crea los enlaces y un instalador Bash
detecta la plataforma, instala dependencias y activa uno de tres perfiles.

## Instalación y perfiles

```bash
git clone <URL-DEL-REPOSITORIO> ~/dotfiles
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
conflicto y aborta. No mueve, borra, adopta ni sobrescribe esos archivos.

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
bash -n install.sh scripts/*.sh
zsh -n zsh/.zshrc zsh/.config/zsh/*.zsh
git diff --check
./install.sh --help
```

Si están disponibles, añade `shellcheck install.sh scripts/*.sh` y `jq empty` sobre
`vscode/.config/dotfiles/vscode/settings.json`, además del dry-run temporal anterior.
`./install.sh --help` solo muestra ayuda; no instala nada.
