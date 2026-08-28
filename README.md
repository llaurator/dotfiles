# dotfiles

Repositorio de dotfiles multiplataforma para mantener un entorno de terminal consistente en macOS, Arch Linux, Fedora/Fedora Asahi y Debian/Ubuntu (incluidos CTs y VMs).

La configuración se despliega con **GNU Stow** y las dependencias se instalan mediante `install.sh`.

## Uso rápido

```bash
git clone git@github.com:TU_USUARIO/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh
```

El instalador detecta el sistema operativo, pregunta el perfil, instala las dependencias, instala Oh My Zsh/Powerlevel10k/plugins desde upstream, guarda el perfil local y despliega los paquetes Stow.

También puede ejecutarse sin interacción:

```bash
./install.sh --profile personal --yes
./install.sh --profile work --yes
./install.sh --profile server --yes
```

## Perfiles

- `personal`: equipo personal con SSH cliente.
- `work`: equipo de trabajo con SSH cliente y `work.zsh`.
- `server`: perfil ligero para servidores, CTs y VMs.

El perfil elegido se guarda automáticamente en `~/.config/dotfiles/profile`. Ese archivo es local a cada máquina.

## Seguridad SSH

El repo debe contener configuración SSH, nunca claves privadas, `known_hosts`, `authorized_keys`, tokens o certificados secretos.

## Stow

```bash
cd ~/dotfiles
stow -n -v -t "$HOME" zsh     # simulación
stow -t "$HOME" zsh git btop  # desplegar
stow -D -t "$HOME" zsh        # retirar enlaces
```
