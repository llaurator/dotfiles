# Control manual de WireGuard (macOS y Linux).
#
# Uso:
#   vpn on
#   vpn off
#   vpn status
#   vpn ip

# Obtiene la interfaz WireGuard activa.
_vpn_interface() {
  local iface=""

  case "$OSTYPE" in
    darwin*)
      iface="$(sudo cat /var/run/wireguard/wg0.name 2>/dev/null)" || return 1
      ;;
    linux*)
      iface="wg0"
      ;;
    *)
      return 1
      ;;
  esac

  [[ -n "$iface" ]] || return 1
  sudo wg show "$iface" >/dev/null 2>&1 || return 1

  print -r -- "$iface"
}

# Convierte bytes a un formato legible.
_vpn_bytes() {
  local bytes="${1:-0}"

  if (( bytes >= 1073741824 )); then
    printf "%.2f GiB" "$(( bytes / 1073741824.0 ))"
  elif (( bytes >= 1048576 )); then
    printf "%.2f MiB" "$(( bytes / 1048576.0 ))"
  elif (( bytes >= 1024 )); then
    printf "%.2f KiB" "$(( bytes / 1024.0 ))"
  else
    printf "%s B" "$bytes"
  fi
}

# Devuelve el tiempo transcurrido desde el último handshake.
_vpn_handshake() {
  local timestamp="${1:-0}"
  local now elapsed

  if (( timestamp <= 0 )); then
    print "Sin handshake"
    return
  fi

  now="$(date +%s)"
  elapsed=$(( now - timestamp ))

  if (( elapsed < 0 )); then
    print "Desconocido"
  elif (( elapsed < 60 )); then
    print "${elapsed} segundos"
  elif (( elapsed < 3600 )); then
    print "$(( elapsed / 60 )) minutos"
  elif (( elapsed < 86400 )); then
    print "$(( elapsed / 3600 )) horas"
  else
    print "$(( elapsed / 86400 )) días"
  fi
}

# Consulta la IPv4 pública.
_vpn_public_ipv4() {
  curl -4fsS \
    --connect-timeout 4 \
    --max-time 8 \
    https://api.ipify.org 2>/dev/null
}

# Consulta la IPv6 pública utilizando HTTPS sobre IPv6 real.
#
# --resolve evita depender de la selección de direcciones
# IPv4 mapeadas (::ffff:) que hemos observado en macOS.
#
# La dirección IPv6 corresponde a un servidor de Google.
# El nombre del dominio se conserva para validar TLS.
_vpn_public_ipv6() {
  curl -6fsS \
    --connect-timeout 4 \
    --max-time 8 \
    --resolve 'www.google.com:443:[2a00:1450:4010:c0a::64]' \
    'https://www.google.com/' \
    -o /dev/null 2>/dev/null || return 1

  # Obtenemos la dirección IPv6 local utilizada para el túnel.
  # En macOS/Linux se extrae de la configuración de WireGuard.
  #
  # La dirección se considera válida porque acabamos de
  # verificar conectividad HTTPS sobre IPv6 real.

  local config="$HOME/.config/wireguard/wg0.conf"
  local addresses addr

  [[ -r "$config" ]] || return 1

  addresses="$(
    sed -n \
      's/^[[:space:]]*Address[[:space:]]*=[[:space:]]*//p' \
      "$config"
  )"

  for addr in ${(s:,:)addresses}; do
    addr="${addr//[[:space:]]/}"
    addr="${addr%%/*}"

    # Excluir IPv4, link-local y ULA.
    [[ "$addr" == *:* ]] || continue
    [[ "$addr" == fe80:* ]] && continue
    [[ "$addr" == fd*:* ]] && continue
    [[ "$addr" == fc*:* ]] && continue

    print -r -- "$addr"
    return 0
  done

  return 1
}

# Muestra las IP públicas.
_vpn_show_ips() {
  local ipv4 ipv6

  ipv4="$(_vpn_public_ipv4)"
  ipv6="$(_vpn_public_ipv6)"

  print "IPv4 pública: ${ipv4:-no disponible}"
  print "IPv6 pública: ${ipv6:-no disponible}"
}

# Muestra el estado resumido de WireGuard.
_vpn_status() {
  local iface="$1"
  local endpoint handshake transfer
  local peer rx tx timestamp

  print "VPN: conectada"
  print "Interfaz: $iface"

  # Obtener el primer peer configurado.
  peer="$(sudo wg show "$iface" peers 2>/dev/null | head -n 1)"

  if [[ -n "$peer" ]]; then
    endpoint="$(
      sudo wg show "$iface" endpoints 2>/dev/null |
      awk -v peer="$peer" '$1 == peer {print $2; exit}'
    )"

    timestamp="$(
      sudo wg show "$iface" latest-handshakes 2>/dev/null |
      awk -v peer="$peer" '$1 == peer {print $2; exit}'
    )"

    transfer="$(
      sudo wg show "$iface" transfer 2>/dev/null |
      awk -v peer="$peer" '$1 == peer {print $2, $3; exit}'
    )"

    read -r rx tx <<< "$transfer"

    print "Servidor: ${endpoint:--}"
    print "Último handshake: $(_vpn_handshake "${timestamp:-0}")"
    print "Recibido: $(_vpn_bytes "${rx:-0}")"
    print "Enviado: $(_vpn_bytes "${tx:-0}")"
  else
    print "Servidor: sin peer"
  fi

  print

  _vpn_show_ips
}

# Comando principal.
vpn() {
  local config="$HOME/.config/wireguard/wg0.conf"
  local action="${1:-status}"
  local iface

  case "$OSTYPE" in
    darwin*|linux*) ;;
    *)
      print -u2 "Sistema operativo no compatible."
      return 1
      ;;
  esac

  # vpn ip no necesita que WireGuard esté instalado.
  if [[ "$action" == "ip" ]]; then
    if ! command -v curl >/dev/null 2>&1; then
      print -u2 "curl no está instalado."
      return 1
    fi

    _vpn_show_ips
    return
  fi

  if ! command -v wg >/dev/null 2>&1 ||
     ! command -v wg-quick >/dev/null 2>&1; then
    print -u2 "WireGuard no está instalado."
    return 1
  fi

  case "$action" in
    on)
      if iface="$(_vpn_interface)"; then
        print "La VPN ya está conectada ($iface)."
        return 0
      fi

      if [[ ! -f "$config" ]]; then
        print -u2 "No existe la configuración: $config"
        return 1
      fi

      sudo wg-quick up "$config"
      ;;

    off)
      if ! iface="$(_vpn_interface)"; then
        print "La VPN ya está desconectada."
        return 0
      fi

      sudo wg-quick down "$config"
      ;;

    status)
      if iface="$(_vpn_interface)"; then
        _vpn_status "$iface"
      else
        print "VPN: desconectada"
      fi
      ;;

    *)
      print "Uso: vpn {on|off|status|ip}"
      return 1
      ;;
  esac
}
