# dotfiles

Dotfiles personales para macOS y determinadas distribuciones Linux, instalados con Bash y [GNU Stow](https://www.gnu.org/software/stow/).

[English](README.md) | Español

> [!WARNING]
> Estos son dotfiles personales. El instalador puede instalar paquetes, cambiar el shell de inicio de sesión, crear enlaces simbólicos y modificar la configuración de usuario. Revisa los scripts antes de ejecutarlos y úsalos bajo tu propia responsabilidad.

<p align="center">
  <img src="docs/screenshot.png" alt="Dotfiles ejecutándose en Fedora Asahi con Zsh, Powerlevel10k, Dracula y MesloLGS Nerd Font">
</p>

## Inicio rápido

```bash
curl -fsSL https://raw.githubusercontent.com/llaurator/dotfiles/main/bootstrap.sh | bash
```

Para una instalación desatendida en un servidor:

```bash
curl -fsSL https://raw.githubusercontent.com/llaurator/dotfiles/main/bootstrap.sh \
  | bash -s -- --profile server --yes
```

### Inspeccionar antes (recomendado)

Descarga e inspecciona el script bootstrap antes de ejecutarlo:

```bash
curl -fsSLO https://raw.githubusercontent.com/llaurator/dotfiles/main/bootstrap.sh
less bootstrap.sh
bash bootstrap.sh
```

El bootstrap clona por HTTPS y después ejecuta el `install.sh` del repositorio. Conserva el checkout en:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles
```

o en la ruta absoluta indicada en `DOTFILES_DIR`. Conserva este repositorio: los enlaces simbólicos de Stow apuntan a archivos dentro de él.

Para instalar una etiqueta, rama o commit concretos en vez de `main`:

```bash
curl -fsSL https://raw.githubusercontent.com/llaurator/dotfiles/main/bootstrap.sh \
  | bash -s -- --ref vX.Y.Z --profile server --yes
```

### Instalación manual por HTTPS

```bash
git clone https://github.com/llaurator/dotfiles.git \
  "${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles"
cd "${XDG_DATA_HOME:-$HOME/.local/share}/dotfiles"
./install.sh
```

## Perfiles

El instalador ofrece tres perfiles:

- `personal` — configuración orientada a escritorio, incluida la configuración de SSH y VS Code.
- `work` — configuración orientada a escritorio, incluida la configuración de SSH y VS Code.
- `server` — evita la configuración de cliente SSH del repositorio, VS Code y la configuración de escritorio.

Ejemplos no interactivos:

```bash
./install.sh --profile personal --yes
./install.sh --profile work --yes
./install.sh --profile server --yes
```

`--yes` requiere `--profile` y acepta las confirmaciones del instalador. No activa la instalación de VS Code.

## Comandos del instalador

```text
-p, --profile PROFILE   personal | work | server
-y, --yes               Do not ask for confirmation
    --migrate-bash-history
                        Import ~/.bash_history into ~/.zsh_history
    --uninstall         Remove managed dotfiles and restore the available baseline
    --keep-packages     With --uninstall, keep packages, upstream clones, and fonts
    --status            Show status without changing files
    --backup-conflicts  Explicitly back up Stow conflicts before installation
    --install-vscode    Explicitly install VS Code for personal/work where supported
    --configure-konsole Explicitly configure Konsole for personal/work
    --dry-run           Simulate history migration or uninstall
-h, --help              Show help
```

Comandos útiles:

```bash
./install.sh --status
./install.sh --uninstall --dry-run
./install.sh --uninstall
./install.sh --uninstall --keep-packages
./install.sh --migrate-bash-history
./install.sh --migrate-bash-history --dry-run
./install.sh --profile personal --yes --backup-conflicts
./install.sh --profile work --yes --install-vscode
./install.sh --profile work --yes --configure-konsole
```

`--dry-run` solo es válido con `--migrate-bash-history` o `--uninstall`. `--backup-conflicts`, `--install-vscode` y `--configure-konsole` son opciones exclusivas de instalación.

## Qué cambia la instalación

El instalador detecta macOS o Linux y usa el gestor de paquetes compatible disponible. Instala herramientas necesarias como Git, Stow, Zsh y `jq`, además de herramientas de línea de comandos opcionales cuando están disponibles. Despliega los paquetes Stow seleccionados, escribe el perfil activo, instala componentes de Zsh desde sus repositorios upstream e intenta establecer Zsh como shell de inicio de sesión.

Antes de ejecutar Stow, los conflictos se muestran y la instalación se detiene de forma predeterminada. Nunca usa `stow --adopt` ni sobrescribe un conflicto salvo que se solicite explícitamente con `--backup-conflicts`.

## Desinstalación y rollback

Cada nuevo ciclo de instalación crea una baseline en:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/cycles/
```

La baseline de formato v2 registra las rutas de configuración gestionadas y su estado anterior, las huellas de los cambios realizados por el instalador, el shell de inicio de sesión previo, snapshots de paquetes antes y después de las transacciones de paquetes, clones upstream, fuentes instaladas, y directorios y modos creados. Los snapshots de paquetes permiten atribuir cambios de paquetes —incluidas las dependencias registradas— sin deducirlos del grafo de paquetes al desinstalar.

`--uninstall` primero verifica que los archivos gestionados sigan coincidiendo con lo que instaló el ciclo. Restaura la configuración registrada y el shell anterior solo cuando es seguro, y elimina únicamente paquetes atribuibles, clones upstream intactos, fuentes atribuibles y directorios creados que estén vacíos. Si una ruta cambió después de la instalación, se detiene en lugar de sobrescribirla. No usa `autoremove`; la retirada de paquetes es explícita y tiene un preflight para efectos laterales no registrados. `--keep-packages` realiza el rollback de configuración, shell y directorios mientras conserva paquetes, clones upstream y fuentes.

Se conservan deliberadamente los historiales de Bash y Zsh (incluida la copia de la migración), el checkout de dotfiles, las extensiones de VS Code y la configuración SSH privada en `~/.ssh/config.d/*.conf`. Los cambios existentes o posteriores del usuario no se sobrescriben automáticamente durante el rollback.

Las baselines antiguas se gestionan de forma conservadora: una baseline v1 puede retirar enlaces Stow verificables, pero no puede reconstruir un estado previo desconocido.

## VS Code

VS Code es opcional. Si `code` ya existe, el instalador lo configura sin atribuirse la propiedad de su paquete. La instalación explícita está disponible con `--install-vscode` para `personal` y `work` en macOS, Arch y Fedora; Debian/Ubuntu no añade un repositorio de VS Code automáticamente.

El instalador fusiona la configuración gestionada en vez de reemplazar a ciegas JSON local válido, configura el locale español e instala solo las extensiones que faltan: Prettier, Ruff, Python Environments, Spanish Language Pack y Dracula Official. La configuración gestionada selecciona Dracula y activa los valores predeterminados de formato del repositorio. Si el JSON local de VS Code no es válido, se deja sin modificar.

## Konsole

El soporte para Konsole es opcional y solo se considera cuando su binario `konsole` está presente en `personal` o `work`. El instalador interactivo pregunta antes de cambiar nada; `--yes` no lo activa. Usa `--configure-konsole` para un opt-in explícito no interactivo. Instala un esquema de colores Dracula con hash verificado desde un commit oficial fijo de `dracula/konsole`, crea `Dotfiles.profile` con Dracula y la familia MesloLGS Nerd Font detectada y restaura de forma segura el perfil predeterminado anterior y los archivos durante el rollback.

## SSH y datos privados

La configuración SSH versionada es genérica e incluye `~/.ssh/config.d/*`. Los archivos reales `config.d/*.conf`, las claves, `known_hosts` y los secretos son solo locales y nunca deben versionarse ni subirse al repositorio. El instalador no genera claves SSH ni hosts, y no reemplaza la configuración SSH privada local.

La identidad de Git se guarda igualmente de forma local en `~/.config/git/local.gitconfig` cuando se configura mediante el instalador interactivo; no está versionada.

## Migración del historial de Bash a Zsh

La migración es explícita e independiente de la instalación normal:

```bash
./install.sh --migrate-bash-history
```

Importa comandos únicos de Bash al formato de historial extendido de Zsh, conserva el historial de Bash y crea una única copia inicial en `~/.zsh_history.pre-bash-migration`. Filtra entradas claramente similares a secretos y muestra recuentos en lugar de comandos, pero ese filtro no es una garantía: inspecciona el historial de origen antes de migrarlo.

## Sistemas compatibles

El instalador contiene rutas de plataforma para:

- macOS (Homebrew es obligatorio)
- Fedora
- Arch Linux
- Debian y derivados, incluido Ubuntu

La compatibilidad se limita a las combinaciones de plataforma y gestor de paquetes implementadas por los scripts. Otras distribuciones Linux se rechazan; no se afirma compatibilidad con sistemas no probados.

## Releases

Las releases se automatizan con `semantic-release` y [Conventional Commits](https://www.conventionalcommits.org/). Usa mensajes de commit convencionales para los cambios: `feat` produce una release minor; `fix`, `perf`, `security` y `revert` producen una release patch; y los cambios incompatibles producen una release major. Los tipos de commit de documentación y mantenimiento contribuyen a las notas cuando se crea una release, pero no crean una por sí solos.

## Contribuir

Las issues y los pull requests acotados son bienvenidos. Mantén los cambios portables entre las plataformas compatibles, no añadas datos personales ni secretos y ejecuta las comprobaciones de sintaxis o específicas correspondientes antes de abrir un pull request.
