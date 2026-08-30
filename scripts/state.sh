#!/usr/bin/env bash

readonly BASELINE_FORMAT_VERSION='2'
BASELINE_FORMAT=''
STOW_PACKAGES=()
CONFLICT_RELS=()
CONFLICT_SOURCES=()
BASELINE_MODE='none'
ACTIVE_CYCLE=''
ACTIVE_CYCLE_DIR=''
STATE_ROOT=''
MANIFEST_FILE=''
OWNERSHIP_FILE=''
FEDORA_VSCODE_REPO_FILE='/etc/yum.repos.d/vscode.repo'

validate_home_and_state() {
  local state_base
  [[ -n "${HOME:-}" && "$HOME" == /* && "$HOME" != '/' ]] ||
    die 'HOME debe ser una ruta absoluta segura distinta de /.'
  [[ "$HOME" != *$'\n'* && "$HOME" != *$'\t'* ]] || die 'HOME contiene caracteres no permitidos.'
  [[ -d "$HOME" ]] || die "HOME no existe: $HOME"

  state_base="${XDG_STATE_HOME:-$HOME/.local/state}"
  [[ "$state_base" != '/' ]] || die 'XDG_STATE_HOME no puede ser /.'
  STATE_ROOT="$state_base/dotfiles"
  [[ -n "$STATE_ROOT" && "$STATE_ROOT" == /* && "$STATE_ROOT" != '/' ]] ||
    die 'XDG_STATE_HOME debe producir una ruta absoluta segura.'
  [[ "$STATE_ROOT" != *$'\n'* && "$STATE_ROOT" != *$'\t'* ]] ||
    die 'La ruta de estado contiene caracteres no permitidos.'
  if [[ -e "$STATE_ROOT" || -L "$STATE_ROOT" ]]; then
    [[ -d "$STATE_ROOT" && ! -L "$STATE_ROOT" ]] || die 'El directorio de estado es inseguro.'
  fi
  if [[ -e "$STATE_ROOT/cycles" || -L "$STATE_ROOT/cycles" ]]; then
    [[ -d "$STATE_ROOT/cycles" && ! -L "$STATE_ROOT/cycles" ]] || die 'El directorio de ciclos es inseguro.'
  fi
}

validate_relative_path() {
  local relative="$1" remaining component
  [[ -n "$relative" && "$relative" != /* && "$relative" != */ ]] || return 1
  [[ "$relative" != *$'\n'* && "$relative" != *$'\t'* ]] || return 1
  remaining="$relative"
  while :; do
    component="${remaining%%/*}"
    [[ -n "$component" && "$component" != '.' && "$component" != '..' ]] || return 1
    [[ "$remaining" == */* ]] || break
    remaining="${remaining#*/}"
  done
}

validate_target_containment() {
  local relative="$1" remaining component current home_physical current_physical
  validate_relative_path "$relative" || die "Ruta relativa no válida en baseline: $relative"
  home_physical="$(cd -P -- "$HOME" && pwd)"
  current="$HOME"
  remaining="$relative"
  while [[ "$remaining" == */* ]]; do
    component="${remaining%%/*}"
    remaining="${remaining#*/}"
    current="$current/$component"
    if [[ -e "$current" || -L "$current" ]]; then
      [[ -d "$current" ]] || die "Un componente padre no es un directorio: ~/${relative}"
      current_physical="$(cd -P -- "$current" && pwd)"
      case "$current_physical" in
        "$home_physical"|"$home_physical"/*) ;;
        *) die "La ruta escapa del HOME mediante un enlace: ~/${relative}" ;;
      esac
    fi
  done
}

path_type() {
  if [[ -L "$1" ]]; then printf 'symlink'
  elif [[ -f "$1" ]]; then printf 'file'
  elif [[ -d "$1" ]]; then printf 'directory'
  elif [[ ! -e "$1" ]]; then printf 'missing'
  else printf 'unsupported'
  fi
}

path_mode() {
  if stat -f '%Lp' "$1" >/dev/null 2>&1; then
    stat -f '%Lp' "$1"
  else
    stat -c '%a' "$1"
  fi
}

path_fingerprint() {
  local target="$1" type mode checksum size link_target
  type="$(path_type "$target")"
  case "$type" in
    missing) printf 'missing' ;;
    file)
      mode="$(path_mode "$target")"
      checksum="$(sha256_stream < "$target")"
      size="$(wc -c < "$target" | tr -d '[:space:]')"
      printf 'file:%s:%s:%s' "$checksum" "$size" "$mode"
      ;;
    symlink)
      link_target="$(readlink "$target")"
      checksum="$(printf '%s' "$link_target" | sha256_stream)"
      size="${#link_target}"
      printf 'symlink:%s:%s' "$checksum" "$size"
      ;;
    directory)
      mode="$(path_mode "$target")"
      checksum="$(tar -cf - -C "${target%/*}" "${target##*/}" | sha256_stream)"
      printf 'directory:%s:%s' "$checksum" "$mode"
      ;;
    *) printf 'unsupported' ;;
  esac
}

sha256_stream() {
  if command_exists sha256sum; then
    sha256sum | awk '{ print $1 }'
  elif command_exists shasum; then
    shasum -a 256 | awk '{ print $1 }'
  else
    die 'Se necesita sha256sum o shasum para verificar la baseline.'
  fi
}

stow_link_is_managed() {
  local target="$1" source="$2"
  [[ -L "$target" && -e "$source" && "$target" -ef "$source" ]]
}

stow_packages_for_all_profiles() {
  STOW_PACKAGES=(zsh git btop ssh vscode)
}

collect_stow_entries() {
  local package source relative
  STOW_ENTRY_PACKAGES=()
  STOW_ENTRY_RELS=()
  STOW_ENTRY_SOURCES=()
  for package in "${STOW_PACKAGES[@]}"; do
    [[ -d "$DOTFILES_ROOT/$package" ]] || die "Paquete Stow inexistente: $package"
    while IFS= read -r -d '' source; do
      relative="${source#"$DOTFILES_ROOT/$package/"}"
      validate_target_containment "$relative"
      STOW_ENTRY_PACKAGES+=("$package")
      STOW_ENTRY_RELS+=("$relative")
      STOW_ENTRY_SOURCES+=("$package/$relative")
    done < <(find "$DOTFILES_ROOT/$package" -type f -print0)
  done
}

managed_dotfiles_exist() {
  local package source relative target
  for package in zsh git btop ssh vscode; do
    while IFS= read -r -d '' source; do
      relative="${source#"$DOTFILES_ROOT/$package/"}"
      validate_target_containment "$relative"
      target="$HOME/$relative"
      stow_link_is_managed "$target" "$source" && return 0
    done < <(find "$DOTFILES_ROOT/$package" -type f -print0)
  done
  return 1
}

load_active_pointer() {
  local line_count
  ACTIVE_CYCLE=''
  ACTIVE_CYCLE_DIR=''
  MANIFEST_FILE=''
  OWNERSHIP_FILE=''
  [[ -e "$STATE_ROOT/active" ]] || return 0
  [[ -f "$STATE_ROOT/active" && ! -L "$STATE_ROOT/active" ]] || die 'El puntero de baseline no es un archivo regular.'
  line_count="$(wc -l < "$STATE_ROOT/active" | tr -d '[:space:]')"
  [[ "$line_count" == 1 ]] || die 'El puntero de baseline está corrupto.'
  IFS= read -r ACTIVE_CYCLE < "$STATE_ROOT/active" || die 'No se pudo leer el installation_id activo.'
  [[ "$ACTIVE_CYCLE" =~ ^[0-9]{8}T[0-9]{6}Z-[0-9]+$ ]] ||
    die 'El installation_id activo no es válido.'
  ACTIVE_CYCLE_DIR="$STATE_ROOT/cycles/$ACTIVE_CYCLE"
  MANIFEST_FILE="$ACTIVE_CYCLE_DIR/manifest.tsv"
  OWNERSHIP_FILE="$ACTIVE_CYCLE_DIR/ownership.tsv"
}

validate_metadata() {
  local metadata="$ACTIVE_CYCLE_DIR/metadata.tsv" key value extra count=0
  local format='' installation_id='' metadata_home='' profile='' repo='' commit='' created=''
  [[ -f "$metadata" && ! -L "$metadata" ]] || die 'Metadata de baseline ausente o insegura.'
  while IFS=$'\t' read -r key value extra; do
    [[ -n "$key" && -n "$value" && -z "$extra" ]] || die 'Metadata de baseline corrupta.'
    case "$key" in
      format_version) [[ -z "$format" ]] || die 'Metadata duplicada.'; format="$value" ;;
      installation_id) [[ -z "$installation_id" ]] || die 'Metadata duplicada.'; installation_id="$value" ;;
      home) [[ -z "$metadata_home" ]] || die 'Metadata duplicada.'; metadata_home="$value" ;;
      profile) [[ -z "$profile" ]] || die 'Metadata duplicada.'; profile="$value" ;;
      repo) [[ -z "$repo" ]] || die 'Metadata duplicada.'; repo="$value" ;;
      commit) [[ -z "$commit" ]] || die 'Metadata duplicada.'; commit="$value" ;;
      created_at) [[ -z "$created" ]] || die 'Metadata duplicada.'; created="$value" ;;
      *) die "Clave de metadata desconocida: $key" ;;
    esac
    count=$((count + 1))
  done < "$metadata"
  [[ "$count" -eq 7 ]] || die 'Campos de metadata no válidos.'
  case "$format" in 1|2) ;; *) die 'Versión de metadata no soportada.' ;; esac
  BASELINE_FORMAT="$format"
  [[ "$installation_id" == "$ACTIVE_CYCLE" && "$metadata_home" == "$HOME" ]] ||
    die 'La baseline no pertenece al HOME o ciclo actual.'
  validate_profile "$profile"
  [[ "$repo" == /* && -n "$commit" && -n "$created" ]] || die 'Metadata de baseline incompleta.'
  [[ -f "$ACTIVE_CYCLE_DIR/status" && ! -L "$ACTIVE_CYCLE_DIR/status" ]] || die 'Estado de baseline ausente.'
  BASELINE_STATUS="$(< "$ACTIVE_CYCLE_DIR/status")"
  case "$BASELINE_STATUS" in active|restored) ;; *) die 'Estado de baseline corrupto.' ;; esac
}

manifest_has_path() {
  local relative="$1"
  awk -F '\t' -v wanted="$relative" 'NR > 1 && $1 == wanted { found=1 } END { exit !found }' "$MANIFEST_FILE"
}

manifest_field() {
  local relative="$1" field="$2"
  awk -F '\t' -v wanted="$relative" -v column="$field" 'NR > 1 && $1 == wanted { print $column; exit }' "$MANIFEST_FILE"
}

validate_backup_type() {
  local backup="$1" expected="$2"
  case "$expected" in
    file) [[ -f "$backup" && ! -L "$backup" ]] ;;
    directory) [[ -d "$backup" && ! -L "$backup" ]] ;;
    symlink) [[ -L "$backup" ]] ;;
    *) return 1 ;;
  esac
}

validate_backup_containment() {
  local relative="$1" remaining component current="$ACTIVE_CYCLE_DIR/files"
  [[ -d "$current" && ! -L "$current" ]] || die 'El directorio files de la baseline es inseguro.'
  remaining="$relative"
  while [[ "$remaining" == */* ]]; do
    component="${remaining%%/*}"
    remaining="${remaining#*/}"
    current="$current/$component"
    if [[ -e "$current" || -L "$current" ]]; then
      [[ -d "$current" && ! -L "$current" ]] || die "Un padre del backup es inseguro: $relative"
    fi
  done
}

validate_manifest() {
  local header relative original_type backup mode kind source backup_fingerprint extra backup_path package
  [[ -f "$MANIFEST_FILE" && ! -L "$MANIFEST_FILE" ]] || die 'Manifest de baseline ausente o inseguro.'
  IFS= read -r header < "$MANIFEST_FILE" || die 'Manifest vacío.'
  [[ "$header" == $'relative_path\toriginal_type\tbackup\tmode\tkind\tsource\tbackup_fingerprint' ]] || die 'Cabecera de manifest no válida.'
  exec 3< "$MANIFEST_FILE"
  IFS= read -r header <&3
  while IFS=$'\t' read -r relative original_type backup mode kind source backup_fingerprint extra <&3; do
    [[ -n "$relative" && -n "$original_type" && -n "$backup" && -n "$mode" &&
       -n "$kind" && -n "$source" && -n "$backup_fingerprint" && -z "$extra" ]] || die 'Entrada de manifest corrupta.'
    validate_target_containment "$relative"
    case "$original_type" in missing|file|directory|symlink) ;; *) die 'Tipo original no válido en manifest.' ;; esac
    case "$kind" in stow|profile|git|vscode|vscode_backup|vscode_locale|konsole_colorscheme|konsole_profile|konsole_config) ;; *) die 'Tipo gestionado no válido en manifest.' ;; esac
    if [[ "$kind" == stow ]]; then
      validate_relative_path "$source" || die 'Source Stow no válido en manifest.'
      package="${source%%/*}"
      case "$package" in zsh|git|btop|ssh|vscode) ;; *) die 'Paquete Stow no válido en manifest.' ;; esac
      [[ "$source" == "$package/$relative" ]] ||
        die 'La ruta Stow del manifest no coincide con el repositorio.'
    else
      [[ "$source" == '-' ]] || die 'Source inesperado en manifest.'
      case "$kind" in
        profile) [[ "$relative" == '.config/dotfiles/profile' ]] || die 'Ruta de perfil no válida.' ;;
        git) [[ "$relative" == '.config/git/local.gitconfig' ]] || die 'Ruta de identidad Git no válida.' ;;
        vscode) [[ "$relative" == 'Code/User/settings.json' || "$relative" == */Code/User/settings.json ]] || die 'Ruta de VS Code no válida.' ;;
        vscode_backup) [[ "$relative" == 'Code/User/settings.json.pre-dotfiles' || "$relative" == */Code/User/settings.json.pre-dotfiles ]] || die 'Ruta de backup de VS Code no válida.' ;;
        vscode_locale) [[ "$relative" == 'Code/User/locale.json' || "$relative" == */Code/User/locale.json ]] || die 'Ruta de locale de VS Code no válida.' ;;
        konsole_colorscheme) [[ "$relative" == '.local/share/konsole/Dracula.colorscheme' ]] || die 'Ruta de esquema Konsole no válida.' ;;
        konsole_profile) [[ "$relative" == '.local/share/konsole/Dotfiles.profile' ]] || die 'Ruta de perfil Konsole no válida.' ;;
        konsole_config) [[ "$relative" == '.config/konsolerc' ]] || die 'Ruta de configuración Konsole no válida.' ;;
      esac
    fi
    if [[ "$original_type" == missing ]]; then
      [[ "$backup" == '-' && "$mode" == '-' && "$backup_fingerprint" == '-' ]] || die 'Entrada missing inconsistente.'
    else
      [[ "$backup" == "files/$relative" && "$mode" =~ ^[0-7]{3,4}$ ]] || die 'Referencia de backup no válida.'
      backup_path="$ACTIVE_CYCLE_DIR/$backup"
      validate_backup_containment "$relative"
      validate_backup_type "$backup_path" "$original_type" || die "Backup ausente o de tipo incorrecto: $relative"
      [[ "$(path_fingerprint "$backup_path")" == "$backup_fingerprint" ]] || die "La integridad del backup no coincide: $relative"
    fi
  done
  exec 3<&-
  if awk -F '\t' 'NR > 1 { if (seen[$1]++) exit 1 }' "$MANIFEST_FILE"; then :; else die 'Manifest con rutas duplicadas.'; fi
}

validate_ownership() {
  local header relative kind proof source extra manifest_kind manifest_source
  [[ -f "$OWNERSHIP_FILE" && ! -L "$OWNERSHIP_FILE" ]] || die 'Registro de propiedad ausente o inseguro.'
  IFS= read -r header < "$OWNERSHIP_FILE" || die 'Registro de propiedad vacío.'
  [[ "$header" == $'relative_path\tkind\tproof\tsource' ]] || die 'Cabecera de propiedad no válida.'
  exec 3< "$OWNERSHIP_FILE"
  IFS= read -r header <&3
  while IFS=$'\t' read -r relative kind proof source extra <&3; do
    [[ -n "$relative" && -n "$kind" && -n "$proof" && -n "$source" && -z "$extra" ]] ||
      die 'Entrada de propiedad corrupta.'
    validate_target_containment "$relative"
    manifest_has_path "$relative" || die 'Propiedad sin entrada correspondiente en manifest.'
    manifest_kind="$(manifest_field "$relative" 5)"
    manifest_source="$(manifest_field "$relative" 6)"
    [[ "$kind" == "$manifest_kind" && "$source" == "$manifest_source" ]] ||
      die 'La propiedad no coincide con su entrada de manifest.'
    case "$kind" in
      stow)
        [[ "$proof" == pending || "$proof" =~ ^symlink:[0-9a-f]{64}:[0-9]+$ ]] || die 'Prueba Stow no válida.'
        validate_relative_path "$source" || die 'Source Stow no válido.'
        ;;
      profile|git|vscode|vscode_backup|vscode_locale|konsole_colorscheme|konsole_profile|konsole_config)
        [[ "$source" == '-' && "$proof" =~ ^file:[0-9a-f]{64}:[0-9]+:[0-7]{3,4}$|^symlink:[0-9a-f]{64}:[0-9]+$|^directory:[0-9a-f]{64}:[0-7]{3,4}$ ]] ||
          die 'Prueba de propiedad no válida.'
        ;;
      *) die 'Tipo de propiedad no válido.' ;;
    esac
  done
  exec 3<&-
  if awk -F '\t' 'NR > 1 { if (seen[$1]++) exit 1 }' "$OWNERSHIP_FILE"; then :; else die 'Propiedad con rutas duplicadas.'; fi
}

validate_active_cycle() {
  load_active_pointer
  [[ -n "$ACTIVE_CYCLE" ]] || return 1
  [[ -d "$ACTIVE_CYCLE_DIR" && ! -L "$ACTIVE_CYCLE_DIR" ]] || die 'Directorio de baseline ausente o inseguro.'
  validate_metadata
  validate_manifest
  validate_ownership
  validate_restore_journal
  if [[ "$BASELINE_FORMAT" == 2 ]]; then validate_environment_manifest; fi
}

validate_restore_journal() {
  local file="$ACTIVE_CYCLE_DIR/restore-journal.tsv" header action resource state extra
  [[ -e "$file" || -L "$file" ]] || return 0
  [[ -f "$file" && ! -L "$file" ]] || die 'Journal de restauración inseguro.'
  IFS= read -r header < "$file" || die 'Journal de restauración vacío.'
  [[ "$header" == $'action\tresource\tstate' ]] || die 'Cabecera del journal de restauración no válida.'
  while IFS=$'\t' read -r action resource state extra; do
    [[ -n "$resource" && -z "$extra" && "$state" =~ ^(started|completed)$ ]] ||
      die 'Entrada del journal de restauración corrupta.'
    case "$action" in
      config_remove|config_restore|shell_restore|upstream_remove|packages_remove|repository_remove|font_remove|directories_restore) ;;
      *) die 'Acción desconocida en el journal de restauración.' ;;
    esac
  done < <(sed -n '2,$p' "$file")
  awk -F '\t' 'NR > 1 { key=$1 FS $2; if (seen[key]++) exit 1 }' "$file" ||
    die 'Journal de restauración con acciones duplicadas.'
}

legacy_restore_completed() {
  local event="$1" resource="$2" file="$ACTIVE_CYCLE_DIR/restore.log"
  [[ -f "$file" && ! -L "$file" ]] || return 1
  awk -F '\t' -v wanted_event="$event" -v wanted_resource="$resource" \
    'NF >= 3 && $2 == wanted_event && (wanted_resource == "*" || $3 == wanted_resource) { found=1 } END { exit !found }' "$file"
}

restore_checkpoint_state() {
  local action="$1" resource="$2" legacy_event="${3:-}" legacy_resource="${4:-$2}"
  local file="$ACTIVE_CYCLE_DIR/restore-journal.tsv" state
  if [[ -f "$file" && ! -L "$file" ]]; then
    state="$(awk -F '\t' -v wanted_action="$action" -v wanted_resource="$resource" \
      'NR > 1 && $1 == wanted_action && $2 == wanted_resource { print $3; exit }' "$file")"
    if [[ -n "$state" ]]; then printf '%s' "$state"; return 0; fi
  fi
  if [[ -n "$legacy_event" ]] && legacy_restore_completed "$legacy_event" "$legacy_resource"; then
    printf 'completed'
    return 0
  fi
  printf 'pending'
}

restore_checkpoint_set() {
  local action="$1" resource="$2" state="$3" file="$ACTIVE_CYCLE_DIR/restore-journal.tsv" tmp old_umask
  [[ -n "$resource" && "$resource" != *$'\n'* && "$resource" != *$'\t'* ]] ||
    die 'Recurso no válido para el journal de restauración.'
  [[ "$state" == started || "$state" == completed ]] || die 'Estado de checkpoint no válido.'
  old_umask="$(umask)"
  umask 077
  tmp="$ACTIVE_CYCLE_DIR/.restore-journal.$$"
  if [[ -e "$file" || -L "$file" ]]; then
    [[ -f "$file" && ! -L "$file" ]] || die 'Journal de restauración inseguro.'
    awk -F '\t' -v wanted_action="$action" -v wanted_resource="$resource" \
      'NR == 1 || $1 != wanted_action || $2 != wanted_resource' "$file" > "$tmp"
  else
    printf 'action\tresource\tstate\n' > "$tmp"
  fi
  printf '%s\t%s\t%s\n' "$action" "$resource" "$state" >> "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$file"
  umask "$old_umask"
}

restore_log_append() {
  if [[ -e "$ACTIVE_CYCLE_DIR/restore.log" || -L "$ACTIVE_CYCLE_DIR/restore.log" ]]; then
    [[ -f "$ACTIVE_CYCLE_DIR/restore.log" && ! -L "$ACTIVE_CYCLE_DIR/restore.log" ]] ||
      die 'Log de restauración inseguro.'
  fi
  printf '%s\t%s\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$1" "$2" >> "$ACTIVE_CYCLE_DIR/restore.log"
  chmod 600 "$ACTIVE_CYCLE_DIR/restore.log"
}

restore_has_progress() {
  local journal="$ACTIVE_CYCLE_DIR/restore-journal.tsv" log="$ACTIVE_CYCLE_DIR/restore.log"
  [[ -f "$journal" && ! -L "$journal" ]] && awk 'NR > 1 { found=1 } END { exit !found }' "$journal" && return 0
  [[ -f "$log" && ! -L "$log" ]] &&
    awk -F '\t' '$2 ~ /^(removed|restored|shell-restored|upstream-removed|packages-removed|vscode-repository-removed)$/ { found=1 } END { exit !found }' "$log"
}

create_cycle() {
  local profile="$1" timestamp suffix commit temporary_active old_umask
  timestamp="$(date -u '+%Y%m%dT%H%M%SZ')"
  suffix="$(printf '%s' "$$-$RANDOM-$timestamp" | cksum | awk '{ print $1 }')"
  ACTIVE_CYCLE="$timestamp-$suffix"
  ACTIVE_CYCLE_DIR="$STATE_ROOT/cycles/$ACTIVE_CYCLE"
  while [[ -e "$ACTIVE_CYCLE_DIR" || -L "$ACTIVE_CYCLE_DIR" ]]; do
    suffix="$(printf '%s' "$$-$RANDOM-$timestamp-$suffix" | cksum | awk '{ print $1 }')"
    ACTIVE_CYCLE="$timestamp-$suffix"
    ACTIVE_CYCLE_DIR="$STATE_ROOT/cycles/$ACTIVE_CYCLE"
  done
  MANIFEST_FILE="$ACTIVE_CYCLE_DIR/manifest.tsv"
  OWNERSHIP_FILE="$ACTIVE_CYCLE_DIR/ownership.tsv"
  commit="$(git -C "$DOTFILES_ROOT" rev-parse --verify HEAD 2>/dev/null || printf 'unknown')"
  old_umask="$(umask)"
  umask 077
  mkdir -p "$STATE_ROOT/cycles" "$ACTIVE_CYCLE_DIR/files"
  chmod 700 "$STATE_ROOT" "$STATE_ROOT/cycles" "$ACTIVE_CYCLE_DIR" "$ACTIVE_CYCLE_DIR/files"
  {
    printf 'format_version\t%s\n' "$BASELINE_FORMAT_VERSION"
    printf 'installation_id\t%s\n' "$ACTIVE_CYCLE"
    printf 'home\t%s\n' "$HOME"
    printf 'profile\t%s\n' "$profile"
    printf 'repo\t%s\n' "$DOTFILES_ROOT"
    printf 'commit\t%s\n' "$commit"
    printf 'created_at\t%s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  } > "$ACTIVE_CYCLE_DIR/metadata.tsv"
  printf 'relative_path\toriginal_type\tbackup\tmode\tkind\tsource\tbackup_fingerprint\n' > "$MANIFEST_FILE"
  printf 'relative_path\tkind\tproof\tsource\n' > "$OWNERSHIP_FILE"
  printf 'key\tbefore\tafter\n' > "$ACTIVE_CYCLE_DIR/environment.tsv"
  printf 'package\tmanager\tstate\n' > "$ACTIVE_CYCLE_DIR/packages.tsv"
  mkdir -p "$ACTIVE_CYCLE_DIR/package-snapshots"
  chmod 700 "$ACTIVE_CYCLE_DIR/package-snapshots"
  printf 'transaction_id\tmanager\tlabel\tbefore_snapshot\tafter_snapshot\tbefore_sha256\tafter_sha256\n' > "$ACTIVE_CYCLE_DIR/package-transactions.tsv"
  printf 'name\trelative_path\texisted_before\texpected_origin\tinstalled_commit\n' > "$ACTIVE_CYCLE_DIR/upstream.tsv"
  printf 'relative_path\texisted_before\ttype\tmode\tinstalled_mode\n' > "$ACTIVE_CYCLE_DIR/directories.tsv"
  printf 'relative_path\tbefore_fingerprint\tinstalled_fingerprint\n' > "$ACTIVE_CYCLE_DIR/fonts.tsv"
  printf 'active\n' > "$ACTIVE_CYCLE_DIR/status"
  temporary_active="$STATE_ROOT/.active.$$"
  printf '%s\n' "$ACTIVE_CYCLE" > "$temporary_active"
  mv -f "$temporary_active" "$STATE_ROOT/active"
  umask "$old_umask"
  BASELINE_STATUS='active'
  BASELINE_MODE='active'
  BASELINE_FORMAT="$BASELINE_FORMAT_VERSION"
  success "Baseline creada: $ACTIVE_CYCLE"
  record_environment_baseline
}

copy_path_to_backup() {
  local target="$1" backup="$2"
  mkdir -p "${backup%/*}"
  cp -pPR "$target" "$backup"
}

record_baseline_path() {
  local relative="$1" kind="$2" source="$3" move_original="${4:-0}"
  local target="$HOME/$relative" original_type backup='-' mode='-' backup_path backup_fingerprint='-'
  manifest_has_path "$relative" && return 0
  validate_target_containment "$relative"
  original_type="$(path_type "$target")"
  [[ "$original_type" != unsupported ]] || die "Tipo de archivo no soportado: ~/$relative"
  if [[ "$original_type" != missing ]]; then
    backup="files/$relative"
    backup_path="$ACTIVE_CYCLE_DIR/$backup"
    mode="$(path_mode "$target")"
    mkdir -p "${backup_path%/*}"
    if [[ "$move_original" -eq 1 ]]; then
      mv "$target" "$backup_path"
      backup_fingerprint="$(path_fingerprint "$backup_path")"
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$relative" "$original_type" "$backup" "$mode" "$kind" "$source" "$backup_fingerprint" >> "$MANIFEST_FILE"
      printf '%s\tstow\tpending\t%s\n' "$relative" "$source" >> "$OWNERSHIP_FILE"
      info "Conflicto respaldado: ~/$relative"
      return 0
    fi
    copy_path_to_backup "$target" "$backup_path"
    backup_fingerprint="$(path_fingerprint "$backup_path")"
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$relative" "$original_type" "$backup" "$mode" "$kind" "$source" "$backup_fingerprint" >> "$MANIFEST_FILE"
}

ownership_set() {
  local relative="$1" kind="$2" proof="$3" source="$4" temporary
  [[ "$BASELINE_MODE" == active ]] || return 0
  temporary="$ACTIVE_CYCLE_DIR/.ownership.$$"
  awk -F '\t' -v wanted="$relative" 'NR == 1 || $1 != wanted' "$OWNERSHIP_FILE" > "$temporary"
  printf '%s\t%s\t%s\t%s\n' "$relative" "$kind" "$proof" "$source" >> "$temporary"
  mv -f "$temporary" "$OWNERSHIP_FILE"
}

mark_path_if_changed() {
  local relative="$1" kind="$2" source="$3" target
  local original_type backup backup_path original_fingerprint current_fingerprint
  target="$HOME/$relative"
  [[ "$BASELINE_MODE" == active ]] || return 0
  manifest_has_path "$relative" || die "No existe baseline para la ruta gestionada: ~/$relative"
  [[ -e "$target" || -L "$target" ]] || return 0
  original_type="$(manifest_field "$relative" 2)"
  current_fingerprint="$(path_fingerprint "$target")"
  if [[ "$original_type" != missing ]]; then
    backup="$(manifest_field "$relative" 3)"
    backup_path="$ACTIVE_CYCLE_DIR/$backup"
    original_fingerprint="$(path_fingerprint "$backup_path")"
    [[ "$current_fingerprint" != "$original_fingerprint" ]] || return 0
  fi
  ownership_set "$relative" "$kind" "$current_fingerprint" "$source"
}

mark_stow_package_owned() {
  local package="$1" index target
  [[ "$BASELINE_MODE" == active ]] || return 0
  for (( index=0; index<${#STOW_ENTRY_RELS[@]}; index++ )); do
    if [[ "${STOW_ENTRY_PACKAGES[index]}" == "$package" ]]; then
      target="$HOME/${STOW_ENTRY_RELS[index]}"
      [[ -L "$target" ]] || die "Stow no creó el enlace esperado: ~/${STOW_ENTRY_RELS[index]}"
      ownership_set "${STOW_ENTRY_RELS[index]}" stow "$(path_fingerprint "$target")" \
        "${STOW_ENTRY_SOURCES[index]}"
    fi
  done
}

vscode_managed_relatives() {
  VSCODE_SETTINGS_REL=''
  VSCODE_BACKUP_REL=''
  VSCODE_LOCALE_REL=''
  case "$1:$DOTFILES_OS" in
    server:*) return 0 ;;
    *:macos) VSCODE_SETTINGS_REL='Library/Application Support/Code/User/settings.json' ;;
    *:linux)
      local settings_path="${XDG_CONFIG_HOME:-$HOME/.config}/Code/User/settings.json"
      case "$settings_path" in "$HOME"/*) VSCODE_SETTINGS_REL="${settings_path#"$HOME/"}" ;; *) die 'Los settings de VS Code quedan fuera de HOME y no pueden incluirse en rollback.' ;; esac
      ;;
  esac
  VSCODE_BACKUP_REL="$VSCODE_SETTINGS_REL.pre-dotfiles"
  VSCODE_LOCALE_REL="${VSCODE_SETTINGS_REL%/*}/locale.json"
  validate_target_containment "$VSCODE_SETTINGS_REL"
  validate_target_containment "$VSCODE_BACKUP_REL"
  validate_target_containment "$VSCODE_LOCALE_REL"
}

mark_vscode_paths_if_changed() {
  local profile="$1"
  [[ "$BASELINE_MODE" == active ]] || return 0
  vscode_managed_relatives "$profile"
  [[ -n "$VSCODE_SETTINGS_REL" ]] || return 0
  mark_path_if_changed "$VSCODE_SETTINGS_REL" vscode '-'
  mark_path_if_changed "$VSCODE_BACKUP_REL" vscode_backup '-'
  mark_path_if_changed "$VSCODE_LOCALE_REL" vscode_locale '-'
}

is_conflict_relative() {
  local wanted="$1" conflict
  for conflict in "${CONFLICT_RELS[@]}"; do [[ "$conflict" == "$wanted" ]] && return 0; done
  return 1
}

plan_reversible_install() {
  local profile="$1" index target source answer
  validate_home_and_state
  stow_packages_for_profile "$profile"
  collect_stow_entries
  CONFLICT_RELS=()
  CONFLICT_SOURCES=()
  for (( index=0; index<${#STOW_ENTRY_RELS[@]}; index++ )); do
    target="$HOME/${STOW_ENTRY_RELS[index]}"
    source="$DOTFILES_ROOT/${STOW_ENTRY_SOURCES[index]}"
    if [[ -e "$target" || -L "$target" ]] && ! stow_link_is_managed "$target" "$source"; then
      if [[ "${STOW_ENTRY_RELS[index]}" == '.ssh/config' && -d "$target" && ! -L "$target" ]]; then
        die 'Se rechaza respaldar un directorio situado en ~/.ssh/config.'
      fi
      CONFLICT_RELS+=("${STOW_ENTRY_RELS[index]}")
      CONFLICT_SOURCES+=("${STOW_ENTRY_SOURCES[index]}")
    fi
  done
  load_active_pointer
  if [[ -n "$ACTIVE_CYCLE" ]]; then
    validate_active_cycle
    [[ "$BASELINE_STATUS" == active ]] && BASELINE_MODE='active'
  elif managed_dotfiles_exist; then
    BASELINE_MODE='legacy'
    info 'Esta instalación es anterior al sistema de rollback; no existe una baseline pre-dotfiles completa.'
  fi
  (( ${#CONFLICT_RELS[@]} > 0 )) || return 0
  warn 'Se han encontrado configuraciones existentes:'
  printf '  - ~/%s\n' "${CONFLICT_RELS[@]}" >&2
  if [[ "$BASELINE_MODE" == legacy ]]; then
    die 'No se respaldan conflictos sobre una instalación antigua sin baseline completa.'
  fi
  if [[ "$BASELINE_MODE" == active ]]; then
    for relative in "${CONFLICT_RELS[@]}"; do
      if manifest_has_path "$relative"; then
        die "Una ruta gestionada fue modificada después de crear la baseline y no se moverá: ~/$relative"
      fi
    done
  fi
  if [[ "$BACKUP_CONFLICTS" -eq 1 ]]; then return 0; fi
  if [[ "$ASSUME_YES" -eq 1 ]]; then
    die 'El modo --yes no mueve conflictos. Revisa las rutas o usa explícitamente --backup-conflicts.'
  fi
  printf '\n¿Qué quieres hacer?\n  1) Cancelar [recomendado]\n  2) Hacer copia de seguridad y continuar\n\n' >&2
  if ! read -r -p '> ' answer || [[ "$answer" != 2 ]]; then die 'Instalación cancelada; no se ha movido ningún conflicto.'; fi
  BACKUP_CONFLICTS=1
}

begin_reversible_install() {
  local profile="$1" index relative source move_original
  validate_home_and_state
  if [[ "$BASELINE_MODE" == legacy ]]; then return 0; fi
  if validate_active_cycle; then
    if [[ "$BASELINE_STATUS" == restored ]]; then
      create_cycle "$profile"
    else
      BASELINE_MODE='active'
      info "Baseline existente reutilizada: $ACTIVE_CYCLE"
    fi
  else
    create_cycle "$profile"
  fi

  for (( index=0; index<${#STOW_ENTRY_RELS[@]}; index++ )); do
    relative="${STOW_ENTRY_RELS[index]}"
    source="${STOW_ENTRY_SOURCES[index]}"
    move_original=0
    if is_conflict_relative "$relative"; then
      [[ "$BACKUP_CONFLICTS" -eq 1 ]] || die 'Conflicto no autorizado antes de Stow.'
      move_original=1
    elif ! manifest_has_path "$relative" &&
         stow_link_is_managed "$HOME/$relative" "$DOTFILES_ROOT/$source"; then
      die "Existe un enlace gestionado sin baseline verificable: ~/$relative"
    fi
    record_baseline_path "$relative" stow "$source" "$move_original"
  done
  record_baseline_path '.config/dotfiles/profile' profile '-'
  record_baseline_path '.config/git/local.gitconfig' git '-'
  vscode_managed_relatives "$profile"
  if [[ -n "$VSCODE_SETTINGS_REL" ]]; then
    record_baseline_path "$VSCODE_SETTINGS_REL" vscode '-'
    record_baseline_path "$VSCODE_BACKUP_REL" vscode_backup '-'
    record_baseline_path "$VSCODE_LOCALE_REL" vscode_locale '-'
  fi
  if [[ "${REQUEST_CONFIGURE_KONSOLE:-0}" -eq 1 ]]; then
    record_baseline_path '.local/share/konsole/Dracula.colorscheme' konsole_colorscheme '-'
    record_baseline_path '.local/share/konsole/Dotfiles.profile' konsole_profile '-'
    record_baseline_path '.config/konsolerc' konsole_config '-'
  fi
  record_manifest_parent_directories
  validate_active_cycle
}

ownership_entries_exist() {
  [[ -f "$OWNERSHIP_FILE" ]] && awk 'NR > 1 { found=1 } END { exit !found }' "$OWNERSHIP_FILE"
}

preflight_owned_path() {
  local relative="$1" kind="$2" proof="$3" source="$4" target
  target="$HOME/$relative"
  if [[ ! -e "$target" && ! -L "$target" ]]; then return 0; fi
  case "$kind" in
    stow)
      if [[ "$proof" == pending ]]; then
        stow_link_is_managed "$target" "$DOTFILES_ROOT/$source"
      else
        [[ -L "$target" && "$(path_fingerprint "$target")" == "$proof" ]]
      fi
      ;;
    *) [[ "$(path_fingerprint "$target")" == "$proof" ]] ;;
  esac
}

configuration_restore_state() {
  local relative="$1" kind="$2" proof="$3" source="$4" target original_type backup backup_path
  local remove_state restore_state current_fingerprint='missing'
  target="$HOME/$relative"
  original_type="$(manifest_field "$relative" 2)"
  remove_state="$(restore_checkpoint_state config_remove "$relative" removed)"
  restore_state="$(restore_checkpoint_state config_restore "$relative" restored)"
  if [[ -e "$target" || -L "$target" ]]; then current_fingerprint="$(path_fingerprint "$target")"; fi

  if [[ "$original_type" != missing ]]; then
    backup="$(manifest_field "$relative" 3)"
    backup_path="$ACTIVE_CYCLE_DIR/$backup"
    if [[ "$restore_state" != pending ]]; then
      [[ "$current_fingerprint" == "$(path_fingerprint "$backup_path")" ]] && { printf 'completed'; return; }
      printf 'conflict'; return
    fi
    if [[ "$remove_state" != pending || "$current_fingerprint" == missing ]]; then
      [[ "$current_fingerprint" == missing ]] && { printf 'restore'; return; }
      printf 'conflict'; return
    fi
  elif [[ "$remove_state" != pending ]]; then
    [[ "$current_fingerprint" == missing ]] && { printf 'completed'; return; }
    printf 'conflict'; return
  elif [[ "$current_fingerprint" == missing ]]; then
    printf 'completed'; return
  fi

  if preflight_owned_path "$relative" "$kind" "$proof" "$source"; then
    if [[ "$original_type" == missing ]]; then printf 'remove'; else printf 'remove_restore'; fi
  else
    printf 'conflict'
  fi
}

print_restore_plan() {
  local relative kind proof source original_type state
  printf '\nPlan de restauración:\n'
  while IFS=$'\t' read -r relative kind proof source; do
    validate_target_containment "$relative"
    original_type="$(manifest_field "$relative" 2)"
    state="$(configuration_restore_state "$relative" "$kind" "$proof" "$source")"
    case "$state" in
      completed) printf '  Hecho:      ~/%s\n' "$relative" ;;
      remove) printf '  Pendiente retirar:  ~/%s\n' "$relative" ;;
      restore) printf '  Pendiente restaurar: ~/%s (%s)\n' "$relative" "$original_type" ;;
      remove_restore)
        printf '  Pendiente retirar:  ~/%s\n' "$relative"
        printf '  Pendiente restaurar: ~/%s (%s)\n' "$relative" "$original_type"
        ;;
      conflict) printf '  Conflicto:  ~/%s\n' "$relative" ;;
    esac
  done < <(sed -n '2,$p' "$OWNERSHIP_FILE")
}

preflight_restore() {
  local relative kind proof source state conflicts=()
  while IFS=$'\t' read -r relative kind proof source; do
    state="$(configuration_restore_state "$relative" "$kind" "$proof" "$source")"
    [[ "$state" != conflict ]] || conflicts+=("$relative")
  done < <(sed -n '2,$p' "$OWNERSHIP_FILE")
  if (( ${#conflicts[@]} > 0 )); then
    warn 'La restauración se cancela porque estas rutas ya no son inequívocamente gestionadas:'
    printf '  - ~/%s\n' "${conflicts[@]}" >&2
    die 'Se conservan intactas las modificaciones posteriores del usuario.'
  fi
}

owned_stow_packages() {
  local relative kind proof source package existing current
  RESTORE_STOW_PACKAGES=()
  while IFS=$'\t' read -r relative kind proof source; do
    [[ "$kind" == stow ]] || continue
    package="${source%%/*}"
    existing=0
    for current in "${RESTORE_STOW_PACKAGES[@]}"; do [[ "$current" == "$package" ]] && existing=1; done
    (( existing == 1 )) || RESTORE_STOW_PACKAGES+=("$package")
  done < <(sed -n '2,$p' "$OWNERSHIP_FILE")
}

remove_owned_configuration() {
  local relative kind proof source target state checkpoint
  while IFS=$'\t' read -r relative kind proof source; do
    target="$HOME/$relative"
    state="$(configuration_restore_state "$relative" "$kind" "$proof" "$source")"
    checkpoint="$(restore_checkpoint_state config_remove "$relative" removed)"
    case "$state" in
      completed|restore)
        if [[ "$checkpoint" == started && ! -e "$target" && ! -L "$target" ]]; then
          restore_checkpoint_set config_remove "$relative" completed
          restore_log_append removed "$relative"
        fi
        continue
        ;;
      conflict) die "La ruta cambió durante la restauración: ~/$relative" ;;
    esac
    [[ "$checkpoint" == started ]] || restore_checkpoint_set config_remove "$relative" started
    if [[ "$kind" == stow ]]; then
      if [[ -L "$target" && "$proof" != pending && "$(path_fingerprint "$target")" == "$proof" ]]; then
        rm -- "$target" || die "No se pudo retirar de forma segura: ~/$relative"
      elif [[ "$proof" == pending ]] && stow_link_is_managed "$target" "$DOTFILES_ROOT/$source"; then
        rm -- "$target" || die "No se pudo retirar de forma segura: ~/$relative"
      fi
    elif [[ -e "$target" || -L "$target" ]]; then
      [[ "$(path_fingerprint "$target")" == "$proof" ]] ||
        die "La ruta cambió durante la restauración: ~/$relative"
      if [[ -d "$target" && ! -L "$target" ]]; then rm -rf -- "$target"; else rm -- "$target"; fi ||
        die "No se pudo retirar de forma segura: ~/$relative"
    fi
    if [[ -e "$target" || -L "$target" ]]; then
      die "No se pudo retirar de forma segura: ~/$relative"
    fi
    restore_checkpoint_set config_remove "$relative" completed
    restore_log_append removed "$relative"
  done < <(sed -n '2,$p' "$OWNERSHIP_FILE")
}

restore_baseline_files() {
  local relative kind proof source original_type backup target backup_path temporary state checkpoint
  while IFS=$'\t' read -r relative kind proof source; do
    original_type="$(manifest_field "$relative" 2)"
    [[ "$original_type" != missing ]] || continue
    state="$(configuration_restore_state "$relative" "$kind" "$proof" "$source")"
    [[ "$state" != completed ]] || {
      if [[ "$(restore_checkpoint_state config_restore "$relative" restored)" == started ]]; then
        restore_checkpoint_set config_restore "$relative" completed
        restore_log_append restored "$relative"
      fi
      continue
    }
    [[ "$state" == restore ]] || die "La ruta cambió durante la restauración: ~/$relative"
    backup="$(manifest_field "$relative" 3)"
    target="$HOME/$relative"
    backup_path="$ACTIVE_CYCLE_DIR/$backup"
    [[ ! -e "$target" && ! -L "$target" ]] || die "La ruta reapareció durante la restauración: ~/$relative"
    mkdir -p "${target%/*}"
    checkpoint="$(restore_checkpoint_state config_restore "$relative" restored)"
    [[ "$checkpoint" == started ]] || restore_checkpoint_set config_restore "$relative" started
    temporary="${target}.restore.$$"
    [[ ! -e "$temporary" && ! -L "$temporary" ]] || die 'Existe una ruta temporal de restauración insegura.'
    if ! copy_path_to_backup "$backup_path" "$temporary"; then
      rm -rf -- "$temporary"
      die "No se pudo restaurar ~/$relative; la restauración ha quedado parcial."
    fi
    if ! mv -- "$temporary" "$target"; then
      rm -rf -- "$temporary"
      die "No se pudo publicar de forma atómica ~/$relative; la restauración ha quedado parcial."
    fi
    [[ "$(path_fingerprint "$target")" == "$(path_fingerprint "$backup_path")" ]] ||
      die "La restauración no coincide con el backup: ~/$relative"
    restore_checkpoint_set config_restore "$relative" completed
    restore_log_append restored "$relative"
  done < <(sed -n '2,$p' "$OWNERSHIP_FILE")
}

set_cycle_restored() {
  local temporary="$ACTIVE_CYCLE_DIR/.status.$$"
  printf 'restored\n' > "$temporary"
  mv -f "$temporary" "$ACTIVE_CYCLE_DIR/status"
  BASELINE_STATUS='restored'
}

confirm_restore() {
  local answer
  [[ "$ASSUME_YES" -eq 1 ]] && return 0
  if ! read -r -p '¿Restaurar la configuración anterior? [s/N] ' answer; then die 'Restauración cancelada.'; fi
  case "$answer" in s|S|si|SI|sí|SÍ) ;; *) die 'Restauración cancelada.' ;; esac
}

legacy_uninstall() {
  local dry_run="$1" package index target source found=0 answer
  stow_packages_for_all_profiles
  collect_stow_entries
  printf '\nInstalación antigua sin baseline completa. Solo se retirarán enlaces Stow verificables:\n'
  for (( index=0; index<${#STOW_ENTRY_RELS[@]}; index++ )); do
    target="$HOME/${STOW_ENTRY_RELS[index]}"
    source="$DOTFILES_ROOT/${STOW_ENTRY_SOURCES[index]}"
    if stow_link_is_managed "$target" "$source"; then printf '  Retirar: ~/%s\n' "${STOW_ENTRY_RELS[index]}"; found=1; fi
  done
  (( found == 1 )) || { info 'No hay una instalación gestionada que retirar.'; return 0; }
  [[ "$dry_run" -eq 1 ]] && { info 'Dry-run: no se ha modificado ningún archivo.'; return 0; }
  confirm_restore
  for package in "${STOW_PACKAGES[@]}"; do
    if ! stow -D --no-folding --dir="$DOTFILES_ROOT" --target="$HOME" "$package"; then
      die "Stow falló al retirar $package; la desinstalación antigua puede haber quedado parcial."
    fi
  done
  for (( index=0; index<${#STOW_ENTRY_RELS[@]}; index++ )); do
    target="$HOME/${STOW_ENTRY_RELS[index]}"
    source="$DOTFILES_ROOT/${STOW_ENTRY_SOURCES[index]}"
    if stow_link_is_managed "$target" "$source"; then rm -- "$target"; fi
  done
  success 'Enlaces Stow retirados. No existía una baseline capaz de restaurar configuraciones anteriores.'
  info "El repositorio se conserva en $DOTFILES_ROOT"
}

uninstall_dotfiles() {
  local dry_run="$1" keep_packages="${2:-0}"
  validate_home_and_state
  if ! validate_active_cycle; then
    legacy_uninstall "$dry_run"
    return
  fi
  if [[ "$BASELINE_STATUS" == restored ]]; then
    info 'Este ciclo ya fue restaurado; no hay una instalación gestionada que retirar.'
    return 0
  fi
  if ! ownership_entries_exist; then
    info 'La baseline no contiene ninguna configuración aplicada que restaurar.'
    if [[ "$dry_run" -eq 1 ]]; then
      info 'Dry-run: no se ha modificado ningún archivo.'
      return 0
    fi
    confirm_restore
    set_cycle_restored
    success 'El ciclo vacío se ha marcado como restaurado.'
    return 0
  fi
  preflight_restore
  print_restore_plan
  if [[ "$BASELINE_FORMAT" == 1 ]]; then
    warn 'Baseline v1: no dispone de tracking completo de shell, paquetes, upstream, fuentes o directorios.'
  else
    preflight_environment_restore "$keep_packages"
    print_environment_restore_plan "$keep_packages"
  fi
  if [[ "$dry_run" -eq 1 ]]; then info 'Dry-run: no se ha modificado ningún archivo.'; return 0; fi
  confirm_restore
  remove_owned_configuration
  restore_baseline_files
  if [[ "$BASELINE_FORMAT" == 2 ]]; then
    restore_login_shell
    if [[ "$keep_packages" -eq 0 ]]; then
      remove_owned_upstream
      remove_cycle_packages
      remove_fedora_vscode_repository
      remove_cycle_fonts
    fi
    restore_directory_modes_and_remove_empty
  fi
  set_cycle_restored
  if [[ "$keep_packages" -eq 1 || "$BASELINE_FORMAT" == 1 ]]; then success 'La configuración se ha restaurado. Los paquetes y herramientas instalados se han conservado.'; else success 'La configuración y el entorno atribuible a este ciclo se han restaurado.'; fi
  info 'Los historiales Bash/Zsh, extensiones de VS Code y configuración SSH local se han conservado.'
  info "El repositorio se conserva en $DOTFILES_ROOT"
}

package_stow_status() {
  local package="$1" source relative target found=0
  while IFS= read -r -d '' source; do
    found=1
    relative="${source#"$DOTFILES_ROOT/$package/"}"
    target="$HOME/$relative"
    stow_link_is_managed "$target" "$source" || return 1
  done < <(find "$DOTFILES_ROOT/$package" -type f -print0)
  (( found == 1 ))
}

show_dotfiles_status() {
  local profile='no configurado' baseline='no disponible' installed='no' restore='ninguno' package shell hosts='ninguno'
  validate_home_and_state
  if [[ -f "$HOME/.config/dotfiles/profile" && ! -L "$HOME/.config/dotfiles/profile" ]]; then
    IFS= read -r profile < "$HOME/.config/dotfiles/profile" || profile='no configurado'
    case "$profile" in personal|work|server) ;; *) profile='desconocido' ;; esac
  fi
  if validate_active_cycle; then
    baseline="$BASELINE_STATUS, formato $BASELINE_FORMAT ($ACTIVE_CYCLE)"
    if [[ "$BASELINE_STATUS" == active ]] && restore_has_progress; then restore='parcial / pendiente'; fi
  fi
  if managed_dotfiles_exist; then installed='yes'; fi
  printf '\nDotfiles status\n\n'
  shell="$(current_login_shell)"
  printf 'Repo:       %s\nProfile:    %s\nBaseline:   %s\nRestore:    %s\nInstalled:  %s\nShell:      %s\n\n' "$DOTFILES_ROOT" "$profile" "$baseline" "$restore" "$installed" "$shell"
  printf 'Stow:\n'
  for package in zsh git btop ssh vscode; do
    if package_stow_status "$package"; then success "$package"; else printf '  - %s\n' "$package"; fi
  done
  printf '\nLocal:\n'
  if [[ -n "$(git config --get user.name 2>/dev/null || true)" && -n "$(git config --get user.email 2>/dev/null || true)" ]]; then success 'Identidad Git configurada'; else printf '  - Identidad Git incompleta\n'; fi
  if [[ -d "$HOME/.ssh/config.d" ]] && compgen -G "$HOME/.ssh/config.d/*.conf" >/dev/null; then hosts='configurados'; fi
  printf '  SSH local hosts: %s\n' "$hosts"
  if [[ -f "$HOME/.local/share/konsole/Dracula.colorscheme" && -f "$HOME/.local/share/konsole/Dotfiles.profile" ]]; then
    printf '  Konsole: ✓ Dracula / Dotfiles.profile\n'
  fi
  printf '\nTools:\n'
  for package in zsh stow fzf zoxide eza bat rg btop grc direnv; do if command_exists "$package"; then printf '  ✓ %s\n' "$package"; else printf '  - %s\n' "$package"; fi; done
}

# Environment rollback (baseline format 2).  Format 1 deliberately never enters
# these functions: absence of evidence is not reconstructed from current state.
current_login_shell() {
  local entry
  if [[ -n "${DOTFILES_LOGIN_SHELL:-}" ]]; then printf '%s' "$DOTFILES_LOGIN_SHELL"; return; fi
  if command_exists getent; then
    entry="$(getent passwd "${USER:-$(id -un)}" 2>/dev/null || true)"
    [[ -n "$entry" ]] && { printf '%s' "${entry##*:}"; return; }
  fi
  if [[ "$(uname -s)" == Darwin ]] && command_exists dscl; then
    entry="$(dscl . -read "/Users/${USER:-$(id -un)}" UserShell 2>/dev/null || true)"
    if [[ -n "$entry" ]]; then awk '{print $2}' <<< "$entry"; return; fi
  fi
  printf '%s' "${SHELL:-}"
}

environment_set() {
  local key="$1" before="$2" after="$3" file="$ACTIVE_CYCLE_DIR/environment.tsv" tmp
  tmp="$ACTIVE_CYCLE_DIR/.environment.$$"
  awk -F '\t' -v wanted="$key" 'NR == 1 || $1 != wanted' "$file" > "$tmp"
  printf '%s\t%s\t%s\n' "$key" "${before:--}" "${after:--}" >> "$tmp"
  mv -f "$tmp" "$file"
}

environment_field() { awk -F '\t' -v key="$1" -v col="$2" 'NR>1 && $1==key {print $col; exit}' "$ACTIVE_CYCLE_DIR/environment.tsv"; }

record_fedora_vscode_repository_before() {
  local before=missing
  [[ "$BASELINE_MODE" == active && "$BASELINE_FORMAT" == 2 ]] || return 0
  [[ -z "$(environment_field fedora_vscode_repository 2)" ]] || return 0
  if [[ -e "$FEDORA_VSCODE_REPO_FILE" || -L "$FEDORA_VSCODE_REPO_FILE" ]]; then
    [[ -f "$FEDORA_VSCODE_REPO_FILE" && ! -L "$FEDORA_VSCODE_REPO_FILE" ]] ||
      die "El fichero de repositorio de VS Code es inseguro: $FEDORA_VSCODE_REPO_FILE"
    before="$(path_fingerprint "$FEDORA_VSCODE_REPO_FILE")"
  fi
  environment_set fedora_vscode_repository "$before" '-'
}

record_fedora_vscode_repository_after() {
  local before after=missing
  [[ "$BASELINE_MODE" == active && "$BASELINE_FORMAT" == 2 ]] || return 0
  before="$(environment_field fedora_vscode_repository 2)"
  [[ -n "$before" ]] || die 'Falta el estado previo del repositorio de VS Code.'
  if [[ -e "$FEDORA_VSCODE_REPO_FILE" || -L "$FEDORA_VSCODE_REPO_FILE" ]]; then
    [[ -f "$FEDORA_VSCODE_REPO_FILE" && ! -L "$FEDORA_VSCODE_REPO_FILE" ]] ||
      die "El fichero de repositorio de VS Code es inseguro: $FEDORA_VSCODE_REPO_FILE"
    after="$(path_fingerprint "$FEDORA_VSCODE_REPO_FILE")"
  fi
  environment_set fedora_vscode_repository "$before" "$after"
}

record_environment_baseline() {
  environment_set login_shell "$(current_login_shell)" '-'
  record_relevant_directories
}

record_shell_changed() {
  [[ "$BASELINE_MODE" == active && "$BASELINE_FORMAT" == 2 ]] || return 0
  environment_set login_shell "$(environment_field login_shell 2)" "$1"
}

record_relevant_directories() {
  local rel target existed type mode
  local -a dirs=(.config .config/zsh .config/dotfiles .config/dotfiles/vscode .config/btop .config/Code .config/Code/User .ssh .ssh/config.d .local .local/share .local/share/fonts)
  for rel in "${dirs[@]}"; do
    target="$HOME/$rel"; existed=no; type=missing; mode=-
    if [[ -e "$target" || -L "$target" ]]; then existed=yes; type="$(path_type "$target")"; [[ "$type" == directory ]] && mode="$(path_mode "$target")"; fi
    printf '%s\t%s\t%s\t%s\t-\n' "$rel" "$existed" "$type" "$mode" >> "$ACTIVE_CYCLE_DIR/directories.tsv"
  done
}

record_one_directory_baseline() {
  local rel="$1" target existed=no type=missing mode=-
  validate_relative_path "$rel" || return 0
  awk -F '\t' -v wanted="$rel" 'NR>1 && $1==wanted {found=1} END {exit !found}' "$ACTIVE_CYCLE_DIR/directories.tsv" && return 0
  target="$HOME/$rel"
  if [[ -e "$target" || -L "$target" ]]; then existed=yes; type="$(path_type "$target")"; [[ "$type" == directory ]] && mode="$(path_mode "$target")"; fi
  printf '%s\t%s\t%s\t%s\t-\n' "$rel" "$existed" "$type" "$mode" >> "$ACTIVE_CYCLE_DIR/directories.tsv"
}

record_manifest_parent_directories() {
  local rel parent
  [[ "$BASELINE_FORMAT" == 2 ]] || return 0
  while IFS=$'\t' read -r rel _; do
    parent="${rel%/*}"; [[ "$parent" != "$rel" ]] || continue
    while [[ -n "$parent" && "$parent" != . ]]; do record_one_directory_baseline "$parent"; [[ "$parent" == */* ]] || break; parent="${parent%/*}"; done
  done < <(sed -n '2,$p' "$MANIFEST_FILE")
}

record_directories_after() {
  local file="$ACTIVE_CYCLE_DIR/directories.tsv" tmp="$ACTIVE_CYCLE_DIR/.directories.$$" rel existed type mode installed target
  [[ "$BASELINE_MODE" == active && "$BASELINE_FORMAT" == 2 ]] || return 0
  IFS= read -r _ < "$file"; printf 'relative_path\texisted_before\ttype\tmode\tinstalled_mode\n' > "$tmp"
  while IFS=$'\t' read -r rel existed type mode installed; do
    target="$HOME/$rel"; installed=-
    [[ -d "$target" && ! -L "$target" ]] && installed="$(path_mode "$target")"
    printf '%s\t%s\t%s\t%s\t%s\n' "$rel" "$existed" "$type" "$mode" "$installed" >> "$tmp"
  done < <(sed -n '2,$p' "$file")
  mv -f "$tmp" "$file"
}

package_manager_name() { case "$DOTFILES_DISTRO" in arch) echo pacman;; fedora) echo dnf;; debian) echo apt;; macos) echo brew;; esac; }
list_installed_packages() {
  case "$DOTFILES_DISTRO" in
    arch) pacman -Qq ;;
    fedora) rpm -qa --qf '%{NAME}\n' ;;
    debian) dpkg-query -W -f='${binary:Package}\t${db:Status-Abbrev}\n' | awk -F '\t' '$2 ~ /^ii / {print $1}' ;;
    macos) { brew list --formula; brew list --cask; } ;;
    *) die 'No se puede obtener el inventario de paquetes de esta plataforma.' ;;
  esac | LC_ALL=C sort -u
}
package_is_installed() {
  case "$DOTFILES_DISTRO" in
    arch) pacman -Q -- "$1" >/dev/null 2>&1 ;;
    fedora) rpm -q -- "$1" >/dev/null 2>&1 ;;
    debian) dpkg-query -W -f='${db:Status-Abbrev}' -- "$1" 2>/dev/null | grep -q '^ii ' ;;
    macos) brew list --formula "$1" >/dev/null 2>&1 || brew list --cask "$1" >/dev/null 2>&1 ;;
  esac
}

ensure_package_transaction_storage() {
  local old_umask
  [[ "$BASELINE_MODE" == active && "$BASELINE_FORMAT" == 2 ]] || return 0
  old_umask="$(umask)"
  umask 077
  if [[ -e "$ACTIVE_CYCLE_DIR/package-transactions.tsv" || -L "$ACTIVE_CYCLE_DIR/package-transactions.tsv" ]]; then
    [[ -f "$ACTIVE_CYCLE_DIR/package-transactions.tsv" && ! -L "$ACTIVE_CYCLE_DIR/package-transactions.tsv" ]] || die 'Manifest de transacciones de paquetes inseguro.'
  else
    printf 'transaction_id\tmanager\tlabel\tbefore_snapshot\tafter_snapshot\tbefore_sha256\tafter_sha256\n' > "$ACTIVE_CYCLE_DIR/package-transactions.tsv"
  fi
  if [[ -e "$ACTIVE_CYCLE_DIR/package-snapshots" || -L "$ACTIVE_CYCLE_DIR/package-snapshots" ]]; then
    [[ -d "$ACTIVE_CYCLE_DIR/package-snapshots" && ! -L "$ACTIVE_CYCLE_DIR/package-snapshots" ]] || die 'Directorio de snapshots de paquetes inseguro.'
  else
    mkdir "$ACTIVE_CYCLE_DIR/package-snapshots"
  fi
  chmod 600 "$ACTIVE_CYCLE_DIR/package-transactions.tsv"
  chmod 700 "$ACTIVE_CYCLE_DIR/package-snapshots"
  umask "$old_umask"
}

package_tracking_set() {
  local package="$1" manager="$2" state="$3" file="$ACTIVE_CYCLE_DIR/packages.tsv" tmp
  tmp="$ACTIVE_CYCLE_DIR/.packages.$$"
  awk -F '\t' -v wanted="$package" 'NR == 1 || $1 != wanted' "$file" > "$tmp"
  printf '%s\t%s\t%s\n' "$package" "$manager" "$state" >> "$tmp"
  mv -f "$tmp" "$file"
}

capture_package_snapshot() {
  local target="$1" temporary
  temporary="$target.tmp.$$"
  [[ ! -e "$target" && ! -L "$target" && ! -e "$temporary" && ! -L "$temporary" ]] || die 'Ruta de snapshot de paquetes ya existente o insegura.'
  list_installed_packages > "$temporary" || { rm -f -- "$temporary"; die 'No se pudo capturar el inventario completo de paquetes.'; }
  LC_ALL=C sort -cu "$temporary" || { rm -f -- "$temporary"; die 'El inventario de paquetes no quedó en orden canónico.'; }
  chmod 600 "$temporary"
  mv -f "$temporary" "$target"
}

package_snapshot_difference() {
  local before="$1" after="$2" temporary status=0
  temporary="$(mktemp -d /tmp/dotfiles-package-compare.XXXXXX)" || return 1
  chmod 700 "$temporary" || status=1
  if [[ "$status" -eq 0 ]] && ! LC_ALL=C sort -u "$before" > "$temporary/before.txt"; then status=1; fi
  if [[ "$status" -eq 0 ]] && ! LC_ALL=C sort -u "$after" > "$temporary/after.txt"; then status=1; fi
  if [[ "$status" -eq 0 ]] && ! LC_ALL=C comm -13 "$temporary/before.txt" "$temporary/after.txt"; then status=1; fi
  rm -rf -- "$temporary" || status=1
  return "$status"
}

run_tracked_package_transaction() {
  local label="$1" manager transaction_id before_rel after_rel before_file after_file before_sha after_sha package difference status=0 count
  shift
  if [[ "$BASELINE_MODE" != active || "$BASELINE_FORMAT" != 2 ]]; then "$@"; return; fi
  [[ "$label" =~ ^[A-Za-z0-9@+._-]+$ ]] || die 'Etiqueta de transacción de paquetes no válida.'
  ensure_package_transaction_storage
  manager="$(package_manager_name)"
  count="$(awk 'END {print NR-1}' "$ACTIVE_CYCLE_DIR/package-transactions.tsv")"
  printf -v transaction_id '%04d' "$((count + 1))"
  before_rel="package-snapshots/$transaction_id-before.txt"
  after_rel="package-snapshots/$transaction_id-after.txt"
  before_file="$ACTIVE_CYCLE_DIR/$before_rel"
  after_file="$ACTIVE_CYCLE_DIR/$after_rel"
  capture_package_snapshot "$before_file"
  "$@" || status=$?
  capture_package_snapshot "$after_file"
  difference="$(mktemp /tmp/dotfiles-package-difference.XXXXXX)" || die 'No se pudo preparar la diferencia de paquetes.'
  if ! package_snapshot_difference "$before_file" "$after_file" > "$difference"; then
    rm -f -- "$difference"
    die 'No se pudo comparar de forma canónica la transacción de paquetes.'
  fi
  while IFS= read -r package; do
    [[ -n "$package" ]] || continue
    package_tracking_set "$package" "$manager" installed_by_cycle
  done < "$difference"
  rm -f -- "$difference"
  before_sha="$(sha256_stream < "$before_file")"
  after_sha="$(sha256_stream < "$after_file")"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$transaction_id" "$manager" "$label" "$before_rel" "$after_rel" "$before_sha" "$after_sha" >> "$ACTIVE_CYCLE_DIR/package-transactions.tsv"
  return "$status"
}

record_packages_before() {
  local package manager
  [[ "$BASELINE_MODE" == active && "$BASELINE_FORMAT" == 2 ]] || return 0
  get_system_packages; manager="$(package_manager_name)"
  for package in "${SYSTEM_PACKAGES[@]}"; do
    awk -F '\t' -v wanted="$package" 'NR>1 && $1==wanted {found=1} END {exit !found}' "$ACTIVE_CYCLE_DIR/packages.tsv" && continue
    if package_is_installed "$package"; then package_tracking_set "$package" "$manager" already_present; else package_tracking_set "$package" "$manager" pending; fi
  done
}
record_packages_after() {
  local file="$ACTIVE_CYCLE_DIR/packages.tsv" tmp="$ACTIVE_CYCLE_DIR/.packages.$$" package manager state
  [[ "$BASELINE_MODE" == active && "$BASELINE_FORMAT" == 2 ]] || return 0
  printf 'package\tmanager\tstate\n' > "$tmp"
  while IFS=$'\t' read -r package manager state; do
    [[ "$state" == pending ]] && { if package_is_installed "$package"; then state=installed_by_cycle; else state=not_installed; fi; }
    printf '%s\t%s\t%s\n' "$package" "$manager" "$state" >> "$tmp"
  done < <(sed -n '2,$p' "$file")
  mv -f "$tmp" "$file"
}

upstream_specs() {
  printf '%s\t%s\t%s\n' \
    'Oh My Zsh' '.oh-my-zsh' 'https://github.com/ohmyzsh/ohmyzsh.git' \
    'Powerlevel10k' '.oh-my-zsh/custom/themes/powerlevel10k' 'https://github.com/romkatv/powerlevel10k.git' \
    'zsh-autosuggestions' '.oh-my-zsh/custom/plugins/zsh-autosuggestions' 'https://github.com/zsh-users/zsh-autosuggestions.git' \
    'zsh-syntax-highlighting' '.oh-my-zsh/custom/plugins/zsh-syntax-highlighting' 'https://github.com/zsh-users/zsh-syntax-highlighting.git' \
    'zsh-history-substring-search' '.oh-my-zsh/custom/plugins/zsh-history-substring-search' 'https://github.com/zsh-users/zsh-history-substring-search.git'
}
record_upstream_before() {
  local name rel origin existed
  [[ "$BASELINE_MODE" == active && "$BASELINE_FORMAT" == 2 ]] || return 0
  awk 'NR>1 {found=1} END {exit !found}' "$ACTIVE_CYCLE_DIR/upstream.tsv" && return 0
  while IFS=$'\t' read -r name rel origin; do existed=no; [[ -e "$HOME/$rel" || -L "$HOME/$rel" ]] && existed=yes; printf '%s\t%s\t%s\t%s\t-\n' "$name" "$rel" "$existed" "$origin"; done < <(upstream_specs) >> "$ACTIVE_CYCLE_DIR/upstream.tsv"
}
record_upstream_after() {
  local file="$ACTIVE_CYCLE_DIR/upstream.tsv" tmp="$ACTIVE_CYCLE_DIR/.upstream.$$" name rel existed origin commit
  [[ "$BASELINE_MODE" == active && "$BASELINE_FORMAT" == 2 ]] || return 0
  printf 'name\trelative_path\texisted_before\texpected_origin\tinstalled_commit\n' > "$tmp"
  while IFS=$'\t' read -r name rel existed origin commit; do
    commit=-; [[ "$existed" == no && -d "$HOME/$rel/.git" ]] && commit="$(git -C "$HOME/$rel" rev-parse HEAD 2>/dev/null || printf '-')"
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$rel" "$existed" "$origin" "$commit" >> "$tmp"
  done < <(sed -n '2,$p' "$file"); mv -f "$tmp" "$file"
}

validate_package_transactions() {
  local manifest="$ACTIVE_CYCLE_DIR/package-transactions.tsv" snapshots="$ACTIVE_CYCLE_DIR/package-snapshots"
  local header transaction_id manager label before_rel after_rel before_sha after_sha extra snapshot expected_sha package difference difference_valid
  if [[ ! -e "$manifest" && ! -e "$snapshots" ]]; then return 0; fi
  [[ -f "$manifest" && ! -L "$manifest" ]] || die 'Manifest de transacciones de paquetes ausente o inseguro.'
  [[ -d "$snapshots" && ! -L "$snapshots" ]] || die 'Directorio de snapshots de paquetes ausente o inseguro.'
  IFS= read -r header < "$manifest"
  [[ "$header" == $'transaction_id\tmanager\tlabel\tbefore_snapshot\tafter_snapshot\tbefore_sha256\tafter_sha256' ]] || die 'Manifest de transacciones de paquetes corrupto.'
  while IFS=$'\t' read -r transaction_id manager label before_rel after_rel before_sha after_sha extra; do
    [[ "$transaction_id" =~ ^[0-9]{4}$ && "$manager" =~ ^(apt|dnf|pacman|brew)$ && "$label" =~ ^[A-Za-z0-9@+._-]+$ && -z "$extra" ]] || die 'Entrada de transacción de paquetes corrupta.'
    [[ "$before_rel" == "package-snapshots/$transaction_id-before.txt" && "$after_rel" == "package-snapshots/$transaction_id-after.txt" ]] || die 'Ruta de snapshot de paquetes no válida.'
    [[ "$before_sha" =~ ^[0-9a-f]{64}$ && "$after_sha" =~ ^[0-9a-f]{64}$ ]] || die 'Hash de snapshot de paquetes no válido.'
    for snapshot in "$ACTIVE_CYCLE_DIR/$before_rel" "$ACTIVE_CYCLE_DIR/$after_rel"; do
      if [[ "$snapshot" == "$ACTIVE_CYCLE_DIR/$before_rel" ]]; then expected_sha="$before_sha"; else expected_sha="$after_sha"; fi
      [[ -f "$snapshot" && ! -L "$snapshot" ]] || die 'Snapshot de paquetes ausente o inseguro.'
      [[ "$(sha256_stream < "$snapshot")" == "$expected_sha" ]] || die 'La integridad de un snapshot de paquetes no coincide.'
      while IFS= read -r package; do [[ "$package" =~ ^[A-Za-z0-9@+._:-]+$ ]] || die 'Nombre no válido en snapshot de paquetes.'; done < "$snapshot"
    done
    difference="$(mktemp /tmp/dotfiles-package-difference.XXXXXX)" || die 'No se pudo preparar la validación de paquetes.'
    if ! package_snapshot_difference "$ACTIVE_CYCLE_DIR/$before_rel" "$ACTIVE_CYCLE_DIR/$after_rel" > "$difference"; then
      rm -f -- "$difference"
      die 'No se pudieron normalizar y comparar los snapshots de paquetes.'
    fi
    difference_valid=1
    while IFS= read -r package; do
      if ! awk -F '\t' -v wanted="$package" -v wanted_manager="$manager" 'NR>1 && $1==wanted && $2==wanted_manager && $3=="installed_by_cycle" {found=1} END {exit !found}' "$ACTIVE_CYCLE_DIR/packages.tsv"; then
        difference_valid=0
        break
      fi
    done < "$difference"
    rm -f -- "$difference"
    [[ "$difference_valid" -eq 1 ]] || die 'Una diferencia de paquetes no quedó atribuida al ciclo.'
  done < <(sed -n '2,$p' "$manifest")
  awk -F '\t' 'NR>1 {if (seen[$1]++) exit 1}' "$manifest" || die 'Transacciones de paquetes duplicadas.'
}

validate_environment_manifest() {
  local f header name rel existed origin commit package manager state key before after extra type mode installed_mode
  for f in environment.tsv packages.tsv upstream.tsv directories.tsv fonts.tsv; do [[ -f "$ACTIVE_CYCLE_DIR/$f" && ! -L "$ACTIVE_CYCLE_DIR/$f" ]] || die "Manifest de entorno ausente: $f"; done
  IFS= read -r header < "$ACTIVE_CYCLE_DIR/environment.tsv"; [[ "$header" == $'key\tbefore\tafter' ]] || die 'Manifest de entorno corrupto.'
  IFS= read -r header < "$ACTIVE_CYCLE_DIR/packages.tsv"; [[ "$header" == $'package\tmanager\tstate' ]] || die 'Manifest de paquetes corrupto.'
  while IFS=$'\t' read -r key before after extra; do
    [[ -n "$key" && -n "$before" && -n "$after" && -z "$extra" ]] || die 'Entrada de entorno corrupta.'
    case "$key" in
      login_shell) ;;
      fedora_vscode_repository)
        [[ "$before" == missing || "$before" =~ ^file:[0-9a-f]{64}:[0-9]+:[0-7]{3,4}$ ]] || die 'Estado previo del repositorio de VS Code no válido.'
        [[ "$after" == - || "$after" == missing || "$after" =~ ^file:[0-9a-f]{64}:[0-9]+:[0-7]{3,4}$ ]] || die 'Estado instalado del repositorio de VS Code no válido.'
        ;;
      *) die 'Clave de entorno desconocida.' ;;
    esac
  done < <(sed -n '2,$p' "$ACTIVE_CYCLE_DIR/environment.tsv")
  while IFS=$'\t' read -r package manager state extra; do [[ "$package" =~ ^[A-Za-z0-9@+._:-]+$ && "$manager" =~ ^(apt|dnf|pacman|brew)$ && "$state" =~ ^(already_present|installed_by_cycle|not_installed|pending)$ && -z "$extra" ]] || die 'Entrada de paquete corrupta.'; done < <(sed -n '2,$p' "$ACTIVE_CYCLE_DIR/packages.tsv")
  while IFS=$'\t' read -r name rel existed origin commit extra; do validate_target_containment "$rel"; [[ "$existed" =~ ^(yes|no)$ && "$origin" == https://github.com/* && -z "$extra" ]] || die 'Entrada upstream corrupta.'; done < <(sed -n '2,$p' "$ACTIVE_CYCLE_DIR/upstream.tsv")
  while IFS=$'\t' read -r rel existed type mode installed_mode extra; do validate_target_containment "$rel"; [[ "$existed" =~ ^(yes|no)$ && "$type" =~ ^(missing|directory|file|symlink|unsupported)$ && -n "$mode" && -n "$installed_mode" && -z "$extra" ]] || die 'Entrada de directorio corrupta.'; done < <(sed -n '2,$p' "$ACTIVE_CYCLE_DIR/directories.tsv")
  while IFS=$'\t' read -r rel before after extra; do
    if [[ "$rel" == homebrew-cask:* ]]; then [[ "$rel" == homebrew-cask:font-meslo-lg-nerd-font ]]; else validate_target_containment "$rel"; [[ "$rel" == .local/share/fonts/MesloLGSNerdFont-*.ttf ]]; fi
    [[ -n "$before" && -n "$after" && -z "$extra" ]] || die 'Entrada de fuente corrupta.'
  done < <(sed -n '2,$p' "$ACTIVE_CYCLE_DIR/fonts.tsv")
  validate_package_transactions
}

git_origin_matches() {
  local actual
  actual="$(git -C "$1" remote get-url origin 2>/dev/null || true)"
  [[ "$actual" == "$2" || "$actual" == "${2%.git}" || "${actual%.git}" == "${2%.git}" ]]
}
upstream_is_pristine() {
  local path="$1" origin="$2" commit="$3"
  [[ -d "$path/.git" && "$commit" != - ]] || return 1
  git_origin_matches "$path" "$origin" || return 1
  [[ "$(git -C "$path" rev-parse HEAD 2>/dev/null || true)" == "$commit" ]] || return 1
  [[ -z "$(git -C "$path" status --porcelain --untracked-files=normal 2>/dev/null)" ]]
}

preflight_environment_restore() {
  local before after current name rel existed origin commit package manager state checkpoint
  before="$(environment_field login_shell 2)"; after="$(environment_field login_shell 3)"; current="$(current_login_shell)"
  checkpoint="$(restore_checkpoint_state shell_restore login_shell shell-restored "$before")"
  if [[ "$checkpoint" == completed && "$current" == "$after" && "$before" != "$after" ]]; then
    die 'El shell restaurado volvió al valor instalado; se conserva y se detiene el rollback.'
  elif [[ "$checkpoint" == started && "$current" != "$after" && "$current" != "$before" ]]; then
    die "El shell cambió durante la restauración ($current); se conserva y se detiene el rollback."
  elif [[ "$checkpoint" == pending && "$after" != - && "$current" != "$after" && "$current" != "$before" ]]; then
    warn "El shell cambió después de la instalación ($current); se conservará."
  fi
  if [[ "$1" -eq 0 ]]; then
    while IFS=$'\t' read -r name rel existed origin commit; do
      [[ "$existed" == no ]] || continue
      if [[ -e "$HOME/$rel" ]] && ! upstream_is_pristine "$HOME/$rel" "$origin" "$commit"; then warn "$name contiene cambios o datos posteriores; se conservará."; fi
    done < <(sed -n '2,$p' "$ACTIVE_CYCLE_DIR/upstream.tsv")
    while IFS=$'\t' read -r package manager state; do
      case "$state" in already_present|installed_by_cycle|not_installed) ;; *) die 'Estado de paquete no válido en baseline.';; esac
    done < <(sed -n '2,$p' "$ACTIVE_CYCLE_DIR/packages.tsv")
    preflight_package_removal
  fi
}

preflight_package_removal() {
  local package manager state output line candidate checkpoint; local -a packages=() extras=()
  checkpoint="$(restore_checkpoint_state packages_remove system packages-removed '*')"
  [[ "$checkpoint" != completed ]] || return 0
  while IFS=$'\t' read -r package manager state; do [[ "$state" == installed_by_cycle ]] && package_is_installed "$package" && packages+=("$package"); done < <(sed -n '2,$p' "$ACTIVE_CYCLE_DIR/packages.tsv")
  (( ${#packages[@]} )) || return 0
  manager="$(awk -F '\t' '$3=="installed_by_cycle" {print $2; exit}' "$ACTIVE_CYCLE_DIR/packages.tsv")"
  case "$manager" in
    apt)
      output="$(LC_ALL=C apt-get -s remove "${packages[@]}")" || die 'No se pudo simular la retirada de paquetes.'
      while read -r line; do [[ "$line" == Remv\ * ]] || continue; candidate="${line#Remv }"; candidate="${candidate%% *}"; array_contains "$candidate" "${packages[@]}" || extras+=("$candidate"); done <<< "$output"
      ;;
    dnf)
      output="$(LC_ALL=C dnf remove --assumeno --no-autoremove "${packages[@]}" 2>&1)" || true
      while read -r candidate; do candidate="${candidate%%.*}"; [[ -n "$candidate" ]] && array_contains "$candidate" "${packages[@]}" || [[ -z "$candidate" ]] || extras+=("$candidate"); done < <(awk '/^Removing:/{on=1;next}/^Transaction Summary/{on=0} on && $1 !~ /^Package$/ && NF>=3 {print $1}' <<< "$output")
      ;;
    pacman) : ;; # pacman -R refuses required targets and does not cascade.
    brew)
      for package in "${packages[@]}"; do output="$(brew uses --installed "$package" 2>/dev/null || true)"; [[ -z "$output" ]] || extras+=("dependientes-de-$package"); done
      ;;
  esac
  (( ${#extras[@]} == 0 )) || { warn "El gestor retiraría elementos no registrados: ${extras[*]}"; die 'Se aborta antes de modificar la máquina.'; }
}

array_contains() { local wanted="$1" item; shift; for item in "$@"; do [[ "$item" == "$wanted" ]] && return 0; done; return 1; }

fedora_vscode_repository_is_removable() {
  local before after
  before="$(environment_field fedora_vscode_repository 2)"
  after="$(environment_field fedora_vscode_repository 3)"
  [[ "$before" == missing && "$after" == file:* ]] || return 1
  [[ -f "$FEDORA_VSCODE_REPO_FILE" && ! -L "$FEDORA_VSCODE_REPO_FILE" ]] || return 1
  [[ "$(path_fingerprint "$FEDORA_VSCODE_REPO_FILE")" == "$after" ]]
}

print_environment_restore_plan() {
  local keep="$1" before after current package manager state name rel existed origin commit checkpoint target
  printf '\nShell:\n'; before="$(environment_field login_shell 2)"; after="$(environment_field login_shell 3)"; current="$(current_login_shell)"
  checkpoint="$(restore_checkpoint_state shell_restore login_shell shell-restored "$before")"
  if [[ "$checkpoint" == completed || "$current" == "$before" ]]; then
    printf '  hecho: %s\n' "$before"
  elif [[ "$after" != - && "$current" == "$after" ]]; then
    printf '  pendiente: %s → %s\n' "$after" "$before"
  elif [[ "$after" == - ]]; then
    printf '  conservar %s\n' "$current"
  else
    printf '  conservar %s (cambio posterior)\n' "$current"
  fi
  printf '\nPaquetes instalados por este ciclo:\n'
  checkpoint="$(restore_checkpoint_state packages_remove system packages-removed '*')"
  while IFS=$'\t' read -r package manager state; do
    [[ "$state" == installed_by_cycle ]] || continue
    if [[ "$keep" -eq 1 ]]; then printf '  conservar %s\n' "$package"
    elif [[ "$checkpoint" == completed ]]; then printf '  hecho: %s\n' "$package"
    elif package_is_installed "$package"; then printf '  retirar %s\n' "$package"
    else printf '  hecho: %s\n' "$package"
    fi
  done < <(sed -n '2,$p' "$ACTIVE_CYCLE_DIR/packages.tsv")
  printf '\nPaquetes que ya existían:\n'; while IFS=$'\t' read -r package manager state; do [[ "$state" == already_present ]] && printf '  conservar %s\n' "$package"; done < <(sed -n '2,$p' "$ACTIVE_CYCLE_DIR/packages.tsv")
  if [[ -n "$(environment_field fedora_vscode_repository 2)" ]]; then
    printf '\nRepositorio oficial de VS Code:\n'
    checkpoint="$(restore_checkpoint_state repository_remove "$FEDORA_VSCODE_REPO_FILE" vscode-repository-removed)"
    if [[ "$keep" -eq 1 ]]; then
      printf '  conservar %s\n' "$FEDORA_VSCODE_REPO_FILE"
    elif [[ "$checkpoint" == completed ]]; then
      printf '  hecho: %s\n' "$FEDORA_VSCODE_REPO_FILE"
    elif fedora_vscode_repository_is_removable; then
      printf '  retirar %s\n' "$FEDORA_VSCODE_REPO_FILE"
    else
      printf '  conservar %s (preexistente o modificado)\n' "$FEDORA_VSCODE_REPO_FILE"
    fi
  fi
  printf '\nUpstream:\n'; while IFS=$'\t' read -r name rel existed origin commit; do
    checkpoint="$(restore_checkpoint_state upstream_remove "$rel" upstream-removed "$name")"; target="$HOME/$rel"
    if [[ "$existed" == yes || "$keep" -eq 1 ]]; then printf '  conservar %s\n' "$name"
    elif [[ "$checkpoint" == completed || "$checkpoint" == started && ! -e "$target" ]]; then printf '  hecho: %s\n' "$name"
    elif upstream_is_pristine "$target" "$origin" "$commit"; then printf '  pendiente retirar %s\n' "$name"
    else printf '  conservar %s (cambios posteriores)\n' "$name"
    fi
  done < <(sed -n '2,$p' "$ACTIVE_CYCLE_DIR/upstream.tsv")
  printf '\nFuentes:\n'; if [[ "$keep" -eq 1 ]]; then printf '  conservar fuentes instaladas\n'; else printf '  retirar únicamente archivos/cask atribuibles e intactos\n'; fi
  printf '\nDirectorios:\n  retirar directorios vacíos creados por este ciclo; restaurar modes solo si no cambiaron después\n'
  printf '\nHistoriales:\n  conservar .bash_history, .zsh_history y .zsh_history.pre-bash-migration\nRepo:\n  conservar %s\n' "$DOTFILES_ROOT"
}

restore_login_shell() {
  local before after current checkpoint
  before="$(environment_field login_shell 2)"; after="$(environment_field login_shell 3)"; current="$(current_login_shell)"
  [[ "$after" != - && "$before" != - ]] || return 0
  checkpoint="$(restore_checkpoint_state shell_restore login_shell shell-restored "$before")"
  if [[ "$checkpoint" == completed ]]; then return 0; fi
  if [[ "$current" == "$before" ]]; then
    restore_checkpoint_set shell_restore login_shell completed
    restore_log_append shell-restored "$before"
    return 0
  fi
  [[ "$current" == "$after" ]] || return 0
  [[ "$checkpoint" == started ]] || restore_checkpoint_set shell_restore login_shell started
  privileged_chsh "$before" || die 'No se pudo restaurar el shell de login.'
  restore_checkpoint_set shell_restore login_shell completed
  restore_log_append shell-restored "$before"
}

remove_owned_upstream() {
  local -a names=() rels=() origins=() commits=(); local name rel existed origin commit i target checkpoint
  while IFS=$'\t' read -r name rel existed origin commit; do [[ "$existed" == no ]] || continue; names+=("$name"); rels+=("$rel"); origins+=("$origin"); commits+=("$commit"); done < <(sed -n '2,$p' "$ACTIVE_CYCLE_DIR/upstream.tsv")
  for ((i=${#rels[@]}-1; i>=0; i--)); do
    validate_target_containment "${rels[i]}"; target="$HOME/${rels[i]}"
    checkpoint="$(restore_checkpoint_state upstream_remove "${rels[i]}" upstream-removed "${names[i]}")"
    if [[ "$checkpoint" == completed ]]; then continue; fi
    if [[ "$checkpoint" == started && ! -e "$target" && ! -L "$target" ]]; then
      restore_checkpoint_set upstream_remove "${rels[i]}" completed
      restore_log_append upstream-removed "${names[i]}"
      continue
    fi
    if upstream_is_pristine "$target" "${origins[i]}" "${commits[i]}"; then
      restore_checkpoint_set upstream_remove "${rels[i]}" started
      rm -rf -- "$target" || die "No se pudo retirar ${names[i]}; el rollback queda pendiente."
      [[ ! -e "$target" && ! -L "$target" ]] || die "No se pudo retirar completamente ${names[i]}."
      restore_checkpoint_set upstream_remove "${rels[i]}" completed
      restore_log_append upstream-removed "${names[i]}"
    elif [[ "$checkpoint" == started ]]; then
      die "${names[i]} cambió durante la restauración; se conserva y se detiene el rollback."
    fi
  done
}

remove_cycle_packages() {
  local manager='' package state recorded_manager checkpoint shell_before shell_after shell_current; local -a packages=()
  checkpoint="$(restore_checkpoint_state packages_remove system packages-removed '*')"
  [[ "$checkpoint" != completed ]] || return 0
  while IFS=$'\t' read -r package recorded_manager state; do [[ "$state" == installed_by_cycle ]] || continue; package_is_installed "$package" || continue; manager="$recorded_manager"; packages+=("$package"); done < <(sed -n '2,$p' "$ACTIVE_CYCLE_DIR/packages.tsv")
  if (( ${#packages[@]} == 0 )); then
    if [[ "$checkpoint" == started ]]; then restore_checkpoint_set packages_remove system completed; fi
    return 0
  fi
  if array_contains zsh "${packages[@]}"; then
    shell_before="$(environment_field login_shell 2)"
    shell_after="$(environment_field login_shell 3)"
    shell_current="$(current_login_shell)"
    if [[ "$shell_before" != "$shell_after" && "$shell_current" == "$shell_after" ]]; then
      die 'No se retirará zsh mientras siga siendo el shell de login activo.'
    fi
  fi
  [[ "$checkpoint" == started ]] || restore_checkpoint_set packages_remove system started
  case "$manager" in
    dnf) run_privileged dnf remove -y --no-autoremove "${packages[@]}" ;;
    pacman) run_privileged pacman -R --noconfirm "${packages[@]}" ;;
    apt) run_privileged apt-get remove -y "${packages[@]}" ;;
    brew) brew uninstall "${packages[@]}" ;;
    *) die 'Gestor de paquetes desconocido en baseline.' ;;
  esac || die 'No se pudieron retirar todos los paquetes registrados; el ciclo queda activo.'
  for package in "${packages[@]}"; do
    package_is_installed "$package" && die "El paquete $package continúa instalado; el ciclo queda activo."
  done
  restore_checkpoint_set packages_remove system completed
  restore_log_append packages-removed "${packages[*]}"
}

remove_fedora_vscode_repository() {
  local checkpoint
  [[ -n "$(environment_field fedora_vscode_repository 2)" ]] || return 0
  checkpoint="$(restore_checkpoint_state repository_remove "$FEDORA_VSCODE_REPO_FILE" vscode-repository-removed)"
  [[ "$checkpoint" != completed ]] || return 0
  if [[ "$checkpoint" == started && ! -e "$FEDORA_VSCODE_REPO_FILE" && ! -L "$FEDORA_VSCODE_REPO_FILE" ]]; then
    restore_checkpoint_set repository_remove "$FEDORA_VSCODE_REPO_FILE" completed
    restore_log_append vscode-repository-removed "$FEDORA_VSCODE_REPO_FILE"
    return 0
  fi
  if fedora_vscode_repository_is_removable; then
    restore_checkpoint_set repository_remove "$FEDORA_VSCODE_REPO_FILE" started
    run_privileged rm -- "$FEDORA_VSCODE_REPO_FILE" || die 'No se pudo retirar el repositorio de VS Code creado por el ciclo.'
    [[ ! -e "$FEDORA_VSCODE_REPO_FILE" && ! -L "$FEDORA_VSCODE_REPO_FILE" ]] ||
      die 'El repositorio de VS Code continúa presente; el rollback queda pendiente.'
    restore_checkpoint_set repository_remove "$FEDORA_VSCODE_REPO_FILE" completed
    restore_log_append vscode-repository-removed "$FEDORA_VSCODE_REPO_FILE"
  elif [[ "$checkpoint" == started ]]; then
    die 'El repositorio de VS Code cambió durante la restauración; se conserva.'
  fi
}

remove_cycle_fonts() {
  local rel before installed target checkpoint removed_any=0
  while IFS=$'\t' read -r rel before installed; do
    checkpoint="$(restore_checkpoint_state font_remove "$rel")"
    [[ "$checkpoint" != completed ]] || continue
    if [[ "$rel" == homebrew-cask:* ]]; then
      if [[ "$before" == missing && "$installed" == installed_by_cycle ]]; then
        if [[ "$checkpoint" == started ]] && ! brew list --cask "${rel#*:}" >/dev/null 2>&1; then
          restore_checkpoint_set font_remove "$rel" completed
          continue
        fi
        restore_checkpoint_set font_remove "$rel" started
        brew uninstall --cask "${rel#*:}" || die 'No se pudo retirar la fuente Homebrew.'
        ! brew list --cask "${rel#*:}" >/dev/null 2>&1 || die 'La fuente Homebrew continúa instalada.'
        restore_checkpoint_set font_remove "$rel" completed
        removed_any=1
      fi
      continue
    fi
    validate_target_containment "$rel"; target="$HOME/$rel"
    if [[ "$before" == missing && "$checkpoint" == started && ! -e "$target" && ! -L "$target" ]]; then
      restore_checkpoint_set font_remove "$rel" completed
    elif [[ "$before" == missing && -f "$target" && "$(path_fingerprint "$target")" == "$installed" ]]; then
      restore_checkpoint_set font_remove "$rel" started
      rm -- "$target" || die "No se pudo retirar la fuente ~/$rel; el rollback queda pendiente."
      [[ ! -e "$target" && ! -L "$target" ]] || die "La fuente ~/$rel continúa presente."
      restore_checkpoint_set font_remove "$rel" completed
      removed_any=1
    elif [[ "$checkpoint" == started ]]; then
      die "La fuente ~/$rel cambió durante la restauración; se conserva."
    fi
  done < <(sed -n '2,$p' "$ACTIVE_CYCLE_DIR/fonts.tsv")
  if [[ "$removed_any" -eq 1 ]] && command_exists fc-cache; then fc-cache -f "$HOME/.local/share/fonts" >/dev/null 2>&1 || warn 'No se pudo actualizar la caché de fuentes.'; fi
}

restore_directory_modes_and_remove_empty() {
  local rel existed type old_mode installed_mode target checkpoint
  checkpoint="$(restore_checkpoint_state directories_restore system)"
  [[ "$checkpoint" != completed ]] || return 0
  [[ "$checkpoint" == started ]] || restore_checkpoint_set directories_restore system started
  while IFS=$'\t' read -r rel existed type old_mode installed_mode; do
    target="$HOME/$rel"
    if [[ "$existed" == yes && "$type" == directory && "$old_mode" != - && "$installed_mode" != - && -d "$target" && ! -L "$target" && "$(path_mode "$target")" == "$installed_mode" ]]; then chmod "$old_mode" "$target"; fi
  done < <(sed -n '2,$p' "$ACTIVE_CYCLE_DIR/directories.tsv")
  while IFS=$'\t' read -r rel existed type old_mode installed_mode; do
    target="$HOME/$rel"; [[ "$existed" == no && -d "$target" && ! -L "$target" ]] && rmdir -- "$target" 2>/dev/null || true
  done < <(tail -n +2 "$ACTIVE_CYCLE_DIR/directories.tsv" | awk -F '\t' '{print length($1) "\t" $0}' | sort -rn | cut -f2-)
  restore_checkpoint_set directories_restore system completed
}
