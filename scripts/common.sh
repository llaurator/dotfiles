#!/usr/bin/env bash
install_git_repo(){ local repo="$1" dest="$2"; if [[ -d "$dest/.git" ]]; then info "Ya existe: $dest"; return; fi; if [[ -e "$dest" ]]; then warn "Existe $dest pero no parece un repositorio Git; no se modifica."; return; fi; git clone --depth=1 "$repo" "$dest"; }
install_common_components(){
  info 'Instalando componentes Zsh desde upstream...'
  install_git_repo https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
  install_git_repo https://github.com/romkatv/powerlevel10k.git "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"
  install_git_repo https://github.com/zsh-users/zsh-autosuggestions.git "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
  install_git_repo https://github.com/zsh-users/zsh-syntax-highlighting.git "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
  install_git_repo https://github.com/zsh-users/zsh-history-substring-search.git "$HOME/.oh-my-zsh/custom/plugins/zsh-history-substring-search"
}
write_profile(){ mkdir -p "$HOME/.config/dotfiles"; printf '%s\n' "$1" > "$HOME/.config/dotfiles/profile"; success 'Perfil guardado en ~/.config/dotfiles/profile'; }
deploy_stow_packages(){
  local profile="$1"; local packages=(zsh git btop)
  case "$profile" in personal|work) packages+=(ssh) ;; esac
  info 'Desplegando dotfiles con GNU Stow...'
  ( cd "$DOTFILES_ROOT"; for package in "${packages[@]}"; do [[ -d "$package" ]] || { warn "Paquete Stow inexistente: $package"; continue; }; stow --restow --target="$HOME" "$package"; success "Stow: $package"; done )
}
ensure_zsh_shell(){ local zsh_path; zsh_path="$(command -v zsh || true)"; [[ -n "$zsh_path" ]] || { warn 'No se ha encontrado zsh.'; return; }; if [[ "${SHELL:-}" == "$zsh_path" ]]; then success 'Zsh ya es el shell por defecto.'; return; fi; info 'Configurando Zsh como shell por defecto...'; if chsh -s "$zsh_path"; then success "Shell por defecto cambiado a $zsh_path"; else warn "Ejecuta manualmente: chsh -s $zsh_path"; fi; }
