#!/usr/bin/env bash

migrate_bash_history() (
  local dry_run="${1:-0}"
  local bash_history="$HOME/.bash_history"
  local zsh_history="$HOME/.zsh_history"
  local backup="$HOME/.zsh_history.pre-bash-migration"
  local temp_dir='' candidates zsh_commands new_entries import_file stats present_count_file
  local found_count omitted_count present_count new_count timestamp

  if [[ ! -s "$bash_history" ]]; then
    info 'No hay historial Bash para migrar; no se modifica ningún archivo.'
    exit 0
  fi

  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-history.XXXXXX")" || {
    warn 'No se pudo crear un directorio temporal para migrar el historial.'
    exit 1
  }
  candidates="$temp_dir/candidates"
  zsh_commands="$temp_dir/zsh-commands"
  new_entries="$temp_dir/new-entries"
  import_file="$temp_dir/import"
  stats="$temp_dir/stats"
  present_count_file="$temp_dir/present-count"

  # Invocada indirectamente por trap EXIT.
  # shellcheck disable=SC2329
  cleanup_history_migration() {
    rm -f "$candidates" "$zsh_commands" "$new_entries" "$import_file" "$stats" "$present_count_file"
    rmdir "$temp_dir" 2>/dev/null || true
  }
  trap cleanup_history_migration EXIT
  trap 'exit 1' HUP INT TERM

  LC_ALL=C awk -v candidates="$candidates" -v stats="$stats" '
    function is_sensitive(text, lower) {
      lower = tolower(text)
      if (lower ~ /(password|passwd|token|api[-_]?key|apikey|secret)[[:space:]]*=/) return 1
      if (lower ~ /authorization[[:space:]]*:/) return 1
      if (lower ~ /bearer[[:space:]]+[^[:space:]]+/) return 1
      if (lower ~ /export[[:space:]]+[a-z_][a-z0-9_]*(token|secret|password)[a-z0-9_]*[[:space:]]*=/) return 1
      if (lower ~ /(^|[[:space:]])--?(password|passwd|token|api[-_]?key|apikey|secret)(=|[[:space:]])/) return 1
      if (lower ~ /-----begin[[:space:]]+([^[:space:]]+[[:space:]]+)*private[[:space:]]+key-----/) return 1
      if (lower ~ /[a-z]+:\/\/[^[:space:]\/:]+:[^[:space:]@\/]+@/) return 1
      return 0
    }
    /^[[:space:]]*$/ { next }
    /^#[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]*$/ { next }
    {
      found++
      if (is_sensitive($0)) {
        omitted++
        next
      }
      print $0 > candidates
    }
    END {
      print found + 0, omitted + 0 > stats
    }
  ' "$bash_history"

  : > "$zsh_commands"
  if [[ -e "$zsh_history" || -L "$zsh_history" ]]; then
    LC_ALL=C awk '
      {
        command = $0
        sub(/^: [0-9][0-9]*:[0-9][0-9]*;/, "", command)
        if (command !~ /^[[:space:]]*$/) print command
      }
    ' "$zsh_history" > "$zsh_commands"
  fi

  : > "$new_entries"
  if [[ -f "$candidates" ]]; then
    LC_ALL=C awk -v zsh_commands="$zsh_commands" -v present_count_file="$present_count_file" '
      BEGIN {
        while ((getline command < zsh_commands) > 0) existing[command] = 1
        close(zsh_commands)
      }
      !considered[$0]++ {
        if (existing[$0]) present++
        else print $0
      }
      END { print present + 0 > present_count_file }
    ' "$candidates" > "$new_entries"
  else
    printf '0\n' > "$present_count_file"
  fi

  read -r found_count omitted_count < "$stats"
  read -r present_count < "$present_count_file"
  new_count="$(awk 'END { print NR + 0 }' "$new_entries")"

  printf 'Historial Bash encontrado: %s entradas\n' "$found_count"
  printf 'Ya presentes en Zsh: %s\n' "$present_count"
  printf 'Nuevas para importar: %s\n' "$new_count"
  printf 'Omitidas por posible secreto: %s\n' "$omitted_count"

  if [[ "$dry_run" -eq 1 ]]; then
    info 'Dry-run: no se ha modificado ningún historial.'
    exit 0
  fi
  if [[ "$new_count" -eq 0 ]]; then
    success 'El historial Zsh ya contiene todas las entradas seguras de Bash.'
    exit 0
  fi

  timestamp="$(date +%s)"
  LC_ALL=C awk -v timestamp="$timestamp" '{ print ": " timestamp ":0;" $0 }' "$new_entries" > "$import_file"

  if [[ -e "$zsh_history" || -L "$zsh_history" ]]; then
    if [[ ! -e "$backup" && ! -L "$backup" ]]; then
      cp -p "$zsh_history" "$backup" || {
        warn 'No se pudo crear ~/.zsh_history.pre-bash-migration; no se modifica el historial.'
        exit 1
      }
    fi
    command cat "$import_file" >> "$zsh_history" || {
      warn 'No se pudieron añadir las entradas migradas a ~/.zsh_history.'
      exit 1
    }
  else
    umask 077
    cp "$import_file" "$zsh_history" || {
      warn 'No se pudo crear ~/.zsh_history.'
      exit 1
    }
    chmod 600 "$zsh_history"
  fi

  success "Historial Bash migrado: $new_count entradas nuevas."
)
