#!/usr/bin/env bash

zsh_component_marker() { case "$1" in omz) printf 'oh-my-zsh.sh';; p10k) printf 'powerlevel10k.zsh-theme';; autosuggestions) printf 'zsh-autosuggestions.zsh';; syntax) printf 'zsh-syntax-highlighting.zsh';; history) printf 'zsh-history-substring-search.zsh';; *) return 1;; esac; }
zsh_component_managed_dir() { case "$1" in omz) printf '%s/.oh-my-zsh' "$HOME";; p10k) printf '%s/.oh-my-zsh/custom/themes/powerlevel10k' "$HOME";; autosuggestions) printf '%s/.oh-my-zsh/custom/plugins/zsh-autosuggestions' "$HOME";; syntax) printf '%s/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting' "$HOME";; history) printf '%s/.oh-my-zsh/custom/plugins/zsh-history-substring-search' "$HOME";; esac; }
zsh_component_relative_path() { case "$1" in omz) printf '.oh-my-zsh';; p10k) printf '.oh-my-zsh/custom/themes/powerlevel10k';; autosuggestions) printf '.oh-my-zsh/custom/plugins/zsh-autosuggestions';; syntax) printf '.oh-my-zsh/custom/plugins/zsh-syntax-highlighting';; history) printf '.oh-my-zsh/custom/plugins/zsh-history-substring-search';; *) return 1;; esac; }
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
  local component="$1" relative _ recorded_relative existed origin commit
  relative="$(zsh_component_relative_path "$component")" || return 1
  validate_home_and_state
  validate_active_cycle || return 1
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
