#!/usr/bin/env bash
install_system_packages() {
  local package listing_package
  local available_packages=()
  get_system_packages
  run_privileged apt-get update
  run_tracked_package_transaction system-required run_privileged apt-get install -y "${SYSTEM_REQUIRED_PACKAGES[@]}"
  for package in "${SYSTEM_OPTIONAL_PACKAGES[@]}"; do
    if apt_package_available "$package"; then
      available_packages+=("$package")
    else
      warn "Paquete no disponible mediante apt: $package"
    fi
  done
  listing_package="$(debian_listing_package)"
  if [[ -n "$listing_package" ]] && ! command_exists "$listing_package"; then
    available_packages+=("$listing_package")
  fi
  if (( ${#available_packages[@]} )); then
    run_tracked_package_transaction system-optional run_privileged apt-get install -y "${available_packages[@]}"
  fi
  if ! command_exists eza && ! command_exists lsd; then
    warn 'No se dispone de eza ni lsd; se conservará ls.'
  fi
  if [[ "$PROFILE" != server ]] && ! command_exists code; then
    warn 'VS Code no está en los repositorios Debian/Ubuntu estándar; se configurará cuando el comando code exista.'
  fi
}
apt_package_available() { apt-cache show --no-all-versions "$1" >/dev/null 2>&1; }
debian_listing_package() {
  if command_exists eza || apt_package_available eza; then printf eza
  elif command_exists lsd || apt_package_available lsd; then printf lsd
  fi
}
# shellcheck disable=SC2034 # Consumida por scripts/state.sh después de source.
get_system_packages() { SYSTEM_REQUIRED_PACKAGES=(git stow zsh jq); SYSTEM_OPTIONAL_PACKAGES=(fzf fd-find zoxide bat ripgrep btop grc direnv); SYSTEM_PACKAGES=("${SYSTEM_REQUIRED_PACKAGES[@]}" "${SYSTEM_OPTIONAL_PACKAGES[@]}" eza lsd); }
