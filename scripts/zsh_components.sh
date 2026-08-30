#!/usr/bin/env bash

zsh_component_marker() { case "$1" in omz) printf 'oh-my-zsh.sh';; p10k) printf 'powerlevel10k.zsh-theme';; autosuggestions) printf 'zsh-autosuggestions.zsh';; syntax) printf 'zsh-syntax-highlighting.zsh';; history) printf 'zsh-history-substring-search.zsh';; *) return 1;; esac; }
zsh_component_managed_dir() { case "$1" in omz) printf '%s/.oh-my-zsh' "$HOME";; p10k) printf '%s/.oh-my-zsh/custom/themes/powerlevel10k' "$HOME";; autosuggestions) printf '%s/.oh-my-zsh/custom/plugins/zsh-autosuggestions' "$HOME";; syntax) printf '%s/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting' "$HOME";; history) printf '%s/.oh-my-zsh/custom/plugins/zsh-history-substring-search' "$HOME";; esac; }
zsh_component_relative_path() { case "$1" in omz) printf '.oh-my-zsh';; p10k) printf '.oh-my-zsh/custom/themes/powerlevel10k';; autosuggestions) printf '.oh-my-zsh/custom/plugins/zsh-autosuggestions';; syntax) printf '.oh-my-zsh/custom/plugins/zsh-syntax-highlighting';; history) printf '.oh-my-zsh/custom/plugins/zsh-history-substring-search';; *) return 1;; esac; }
zsh_component_for_relative_path() { case "$1" in .oh-my-zsh) printf omz;; .oh-my-zsh/custom/themes/powerlevel10k) printf p10k;; .oh-my-zsh/custom/plugins/zsh-autosuggestions) printf autosuggestions;; .oh-my-zsh/custom/plugins/zsh-syntax-highlighting) printf syntax;; .oh-my-zsh/custom/plugins/zsh-history-substring-search) printf history;; *) return 1;; esac; }
zsh_component_repository() { case "$1" in omz) printf 'https://github.com/ohmyzsh/ohmyzsh.git';; p10k) printf 'https://github.com/romkatv/powerlevel10k.git';; autosuggestions) printf 'https://github.com/zsh-users/zsh-autosuggestions.git';; syntax) printf 'https://github.com/zsh-users/zsh-syntax-highlighting.git';; history) printf 'https://github.com/zsh-users/zsh-history-substring-search.git';; *) return 1;; esac; }
zsh_component_valid_dir() { [[ -n "$2" && -d "$2" && -r "$2/$(zsh_component_marker "$1")" ]]; }
# shellcheck disable=SC2016 # Los patrones buscan sintaxis literal no evaluada.
zsh_safe_path() {
  local value="$1"
  case "$value" in
    \"*\") value="${value:1:${#value}-2}" ;;
    \'*\') value="${value:1:${#value}-2}" ;;
  esac
  case "$value" in
    '$HOME') value="$HOME" ;;
    '$HOME/'*) value="$HOME/${value#'$HOME/'}" ;;
    '${HOME}') value="$HOME" ;;
    '${HOME}/'*) value="$HOME/${value#'${HOME}/'}" ;;
  esac
  [[ "$value" != *'$('* && "$value" != *'`'* && "$value" != *'$'* && "$value" != *';'* && "$value" != *'|'* && "$value" != *'&'* && "$value" != *'<'* && "$value" != *'>'* && "$value" == /* ]] || return 1
  printf '%s' "$value"
}
# shellcheck disable=SC2016 # Los patrones buscan sintaxis literal no evaluada.
zshrc_component_dir() {
  local component="$1" file="$HOME/.zshrc" marker line token path
  [[ -f "$file" && ! -L "$file" && -r "$file" ]] || return 1
  marker="$(zsh_component_marker "$component")"
  while IFS= read -r line; do
    [[ "$line" != *'$('* && "$line" != *'`'* && "$line" != *';'* && "$line" != *'|'* && "$line" != *'&'* ]] || continue
    if [[ "$component" == omz && "$line" =~ ^[[:space:]]*ZSH=(.+)$ ]]; then token="${BASH_REMATCH[1]}"; else
      [[ "$line" =~ ^[[:space:]]*(source|\.)[[:space:]]+(.+)$ ]] || continue; token="${BASH_REMATCH[2]}"
    fi
    path="$(zsh_safe_path "$token")" || continue
    [[ "$component" == omz || "$path" == *"/$marker" ]] || continue
    [[ "$component" == omz ]] || path="${path%/*}"
    zsh_component_valid_dir "$component" "$path" && { printf '%s' "$path"; return 0; }
  done < "$file"
  return 1
}
zsh_component_system_dir() {
  local root="${DOTFILES_ZSH_SYSTEM_ROOT:-}"
  [[ "$DOTFILES_DISTRO" == arch ]] || return 1
  case "$1" in omz) printf '%s/usr/share/oh-my-zsh' "$root";; p10k) printf '%s/usr/share/zsh-theme-powerlevel10k' "$root";; autosuggestions) printf '%s/usr/share/zsh/plugins/zsh-autosuggestions' "$root";; syntax) printf '%s/usr/share/zsh/plugins/zsh-syntax-highlighting' "$root";; history) printf '%s/usr/share/zsh/plugins/zsh-history-substring-search' "$root";; esac
}
zsh_component_is_managed() {
  local component="$1" relative _ recorded_relative existed origin commit baseline_key
  relative="$(zsh_component_relative_path "$component")" || return 1
  validate_home_and_state
  baseline_key="$STATE_ROOT/active"
  if [[ "${ZSH_OWNERSHIP_BASELINE:-}" != "$baseline_key" ]]; then
    validate_active_cycle || return 1
    ZSH_OWNERSHIP_BASELINE="$baseline_key"
  fi
  [[ "$BASELINE_STATUS" == active && "$BASELINE_FORMAT" == 2 ]] || return 1
  while IFS=$'\t' read -r _ recorded_relative existed origin commit; do
    [[ "$recorded_relative" == "$relative" && "$existed" == no ]] || continue
    upstream_is_pristine "$HOME/$relative" "$origin" "$commit"
    return
  done < <(sed -n '2,$p' "$ACTIVE_CYCLE_DIR/upstream.tsv")
  return 1
}
resolve_zsh_component() {
  local component="$1" path
  path="$(zsh_component_managed_dir "$component")"
  if zsh_component_valid_dir "$component" "$path"; then
    if zsh_component_is_managed "$component"; then printf 'managed\t%s\n' "$path"; else printf 'external\t%s\n' "$path"; fi
    return
  fi
  if path="$(zshrc_component_dir "$component")"; then printf 'external\t%s\n' "$path"; return; fi
  if path="$(zsh_component_system_dir "$component" 2>/dev/null)" && zsh_component_valid_dir "$component" "$path"; then printf 'external\t%s\n' "$path"; else printf 'missing\t-\n'; fi
}
resolve_zsh_components() { local component; for component in omz p10k autosuggestions syntax history; do printf '%s\t' "$component"; resolve_zsh_component "$component"; done; }
zsh_component_created() { array_contains "$1" "${ZSH_COMPONENTS_CREATED[@]:-}"; }
zsh_component_install_missing() {
  local component="$1" repository destination state path
  IFS=$'\t' read -r state path < <(resolve_zsh_component "$component")
  case "$state" in
    managed|external) info "Zsh: se reutiliza $component ($state): $path"; return 0 ;;
    missing) ;;
    *) die "Estado de componente Zsh no válido: $component" ;;
  esac
  repository="$(zsh_component_repository "$component")"
  destination="$(zsh_component_managed_dir "$component")"
  if [[ -e "$destination" || -L "$destination" ]]; then
    warn "Zsh: $component apareció durante la instalación; se conserva: $destination"
    return 0
  fi
  mkdir -p "${destination%/*}"
  if git clone --depth=1 "$repository" "$destination"; then
    zsh_component_valid_dir "$component" "$destination" || die "El clon de $component no contiene su marker esperado."
    ZSH_COMPONENTS_CREATED+=("$component")
  else
    die "No se pudo clonar $component."
  fi
}
install_resolved_zsh_components() {
  local component
  ZSH_COMPONENTS_CREATED=()
  info 'Instalando únicamente los componentes Zsh pendientes...'
  for component in omz p10k autosuggestions syntax history; do zsh_component_install_missing "$component"; done
}
zsh_component_config_relative_path() { printf '.config/dotfiles/zsh-components.zsh'; }
write_resolved_zsh_component_config() {
  local relative target temporary component state path proof omz_path p10k_path autosuggestions_path syntax_path history_path
  [[ "$BASELINE_MODE" == active && "$BASELINE_FORMAT" == 2 ]] || {
    warn 'Zsh: no hay baseline v2 activa; se conserva la configuración de rutas existente.'
    return 0
  }
  relative="$(zsh_component_config_relative_path)"; target="$HOME/$relative"
  if [[ -e "$target" || -L "$target" ]]; then
    proof="$(awk -F '\t' -v wanted="$relative" 'NR > 1 && $1 == wanted { print $3; exit }' "$OWNERSHIP_FILE")"
    if [[ -n "$proof" ]] && ! preflight_owned_path "$relative" zsh_components "$proof" '-'; then
      warn "Zsh: $target fue modificado o es externo; se conserva y no se regenera."
      return 0
    fi
  fi
  for component in omz p10k autosuggestions syntax history; do
    IFS=$'\t' read -r state path < <(resolve_zsh_component "$component")
    [[ "$state" != missing ]] || die "Zsh: $component sigue pendiente después de instalar."
    case "$component" in
      omz) omz_path="$path" ;; p10k) p10k_path="$path/$(zsh_component_marker "$component")" ;;
      autosuggestions) autosuggestions_path="$path/$(zsh_component_marker "$component")" ;;
      syntax) syntax_path="$path/$(zsh_component_marker "$component")" ;;
      history) history_path="$path/$(zsh_component_marker "$component")" ;;
    esac
  done
  mkdir -p "${target%/*}"
  temporary="$(mktemp "${target%/*}/.zsh-components.zsh.XXXXXX")" || die 'No se pudo preparar la configuración local de Zsh.'
  {
    printf '%s\n' '# Generado por dotfiles; rutas resueltas durante la instalación.'
    printf 'export ZSH=%q\n' "$omz_path"
    printf 'DOTFILES_P10K_THEME=%q\n' "$p10k_path"
    printf 'DOTFILES_ZSH_AUTOSUGGESTIONS=%q\n' "$autosuggestions_path"
    printf 'DOTFILES_ZSH_HISTORY_SUBSTRING=%q\n' "$history_path"
    printf 'DOTFILES_ZSH_SYNTAX_HIGHLIGHTING=%q\n' "$syntax_path"
  } > "$temporary"
  chmod 600 "$temporary"
  mv -f "$temporary" "$target"
  mark_path_if_changed "$relative" zsh_components '-'
}
