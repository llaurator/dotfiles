# Control manual de WireGuard (macOS y Linux).

_vpn_interface() {
  local iface

  case "$OSTYPE" in
    darwin*)
      [[ -r /var/run/wireguard/wg0.name ]] || {
        iface="$(sudo cat /var/run/wireguard/wg0.name 2>/dev/null)" || return 1
      }
      [[ -n "$iface" ]] || iface="$(cat /var/run/wireguard/wg0.name 2>/dev/null)"
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

vpn() {
  local config="$HOME/.config/wireguard/wg0.conf"
  local action="${1:-status}"
  local iface

  if ! command -v wg >/dev/null 2>&1 ||
     ! command -v wg-quick >/dev/null 2>&1; then
    print -u2 "WireGuard no está instalado."
    return 1
  fi

  case "$OSTYPE" in
    darwin*|linux*) ;;
    *)
      print -u2 "Sistema operativo no compatible."
      return 1
      ;;
  esac

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
        print "VPN conectada ($iface)"
        sudo wg show "$iface"
      else
        print "VPN desconectada"
      fi
      ;;

    ip)
      curl -4fsS --max-time 8 https://api.ipify.org
      print
      ;;

    *)
      print "Uso: vpn {on|off|status|ip}"
      return 1
      ;;
  esac
}
