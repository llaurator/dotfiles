#!/usr/bin/env bash
install_system_packages() {
  local package
  local available_packages=()
  get_system_packages
  run_privileged apt-get update
  run_tracked_package_transaction system-required run_privileged apt-get install -y "${SYSTEM_REQUIRED_PACKAGES[@]}"
  for package in "${SYSTEM_OPTIONAL_PACKAGES[@]}"; do
    if apt-cache show --no-all-versions "$package" >/dev/null 2>&1; then
      available_packages+=("$package")
    else
      warn "Paquete no disponible mediante apt: $package"
    fi
  done
  if (( ${#available_packages[@]} )); then
    run_tracked_package_transaction system-optional run_privileged apt-get install -y "${available_packages[@]}"
  fi
  mkdir -p "$HOME/.local/bin"
  if ! command_exists fd && command_exists fdfind; then
    ln -sfn "$(command -v fdfind)" "$HOME/.local/bin/fd"
  fi
  if ! command_exists bat && command_exists batcat; then
    ln -sfn "$(command -v batcat)" "$HOME/.local/bin/bat"
  fi
  command_exists eza || warn 'eza no está disponible en esta versión de apt; se conservará ls.'
  if [[ "$PROFILE" != server ]] && ! command_exists code; then
    warn 'VS Code no está en los repositorios Debian/Ubuntu estándar; se configurará cuando el comando code exista.'
  fi
}
# shellcheck disable=SC2034 # Consumida por scripts/state.sh después de source.
get_system_packages() { SYSTEM_REQUIRED_PACKAGES=(git stow zsh jq); SYSTEM_OPTIONAL_PACKAGES=(fzf fd-find zoxide bat ripgrep btop grc direnv eza); SYSTEM_PACKAGES=("${SYSTEM_REQUIRED_PACKAGES[@]}" "${SYSTEM_OPTIONAL_PACKAGES[@]}"); }
