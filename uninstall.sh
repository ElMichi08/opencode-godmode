#!/usr/bin/env bash
#
# opencode-godmode — reversión de lo que install.sh agregó (PLAN.md 4.6).
#
# Uso: ./uninstall.sh [--yes]
#   Se corre desde la raíz del proyecto instalado.
#
# Qué SÍ hace:
#   - Remueve el bloque de AGENTS.md (entre delimitadores) o restaura desde
#     backup si hay uno disponible.
#   - Restaura ~/.config/rtk/config.toml desde backup (si existe uno; si no,
#     no hay forma segura de deshacer un merge aditivo, así que se avisa y se
#     deja como está).
#   - Ofrece correr `rtk init -g --uninstall` y borrar el binario/config de rtk.
#   - Ofrece desinstalar gentle-ai (nunca en silencio, ni siquiera con --yes).
#
# Qué NUNCA hace:
#   - Tocar ${BDD_DIR}/ (son artefactos del usuario).
#   - Borrar memorias de Engram (~/.engram) sin confirmación explícita.
#   - Desinstalar gentle-ai sin preguntar explícitamente.

set -uo pipefail

PROJECT_DIR="$(pwd)"
STACK_CONF="$PROJECT_DIR/stack.conf"
PROJECT_AGENTS_MD="$PROJECT_DIR/AGENTS.md"
BACKUP_ROOT="$HOME/.local/state/opencode-godmode/backups"

export PATH="$HOME/.local/bin:$PATH"

YES=false
for arg in "$@"; do
  case "$arg" in
    --yes) YES=true ;;
    -h|--help)
      cat <<'EOF'
Uso: ./uninstall.sh [--yes]
  --yes   Auto-acepta las confirmaciones de bajo riesgo (remover bloque de
          AGENTS.md, desinstalar rtk). gentle-ai y las memorias de Engram
          SIEMPRE se preguntan explícitamente, incluso con --yes.
EOF
      exit 0
      ;;
    *) echo "Flag desconocida: $arg" >&2; exit 1 ;;
  esac
done

if [[ -t 1 ]]; then
  C_INFO=$'\033[0;36m'; C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'
  C_ERR=$'\033[0;31m'; C_STEP=$'\033[1;35m'; C_RESET=$'\033[0m'
else
  C_INFO=""; C_OK=""; C_WARN=""; C_ERR=""; C_STEP=""; C_RESET=""
fi
log_step()  { printf '\n%s==> %s%s\n' "$C_STEP" "$1" "$C_RESET"; }
log_info()  { printf '%s  %s%s\n' "$C_INFO" "$1" "$C_RESET"; }
log_ok()    { printf '%s  \xe2\x9c\x94 %s%s\n' "$C_OK" "$1" "$C_RESET"; }
log_warn()  { printf '%s  \xe2\x9a\xa0 %s%s\n' "$C_WARN" "$1" "$C_RESET" >&2; }
log_error() { printf '%s  \xe2\x9c\x98 %s%s\n' "$C_ERR" "$1" "$C_RESET" >&2; }
have_cmd()  { command -v "$1" >/dev/null 2>&1; }

# confirm_low_risk respeta --yes. confirm_high_risk NUNCA lo respeta: gentle-ai
# y las memorias de Engram son datos/estado compartido, no exclusivos de este
# proyecto, y el plan pide preguntar siempre.
confirm_low_risk() {
  local prompt="$1"
  $YES && return 0
  local reply
  read -rp "$prompt [y/N] " reply || true
  [[ "$reply" =~ ^[Yy]$ ]]
}
confirm_high_risk() {
  local prompt="$1"
  local reply
  read -rp "$prompt [y/N] " reply || true
  [[ "$reply" =~ ^[Yy]$ ]]
}

if [[ -f "$STACK_CONF" ]]; then
  # shellcheck disable=SC1090
  source "$STACK_CONF"
fi
BDD_DIR="${BDD_DIR:-features}"

# ---------------------------------------------------------------------------
# Backups: listar / elegir / restaurar
# ---------------------------------------------------------------------------

backups_for() {
  local target="$1" key
  key="$(printf '%s' "$target" | sed 's#[/ ]#_#g')"
  find "$BACKUP_ROOT" -maxdepth 1 -name "${key}.*.bak" 2>/dev/null | sort -r
}

restore_or_strip_agents_md() {
  log_step "AGENTS.md"

  # Remover solo el bloque delimitado es el default y es siempre correcto
  # ("sin tocar el resto"). Restaurar un backup completo NO lo es: el primer
  # backup de este archivo recién se crea en la SEGUNDA modificación
  # (install.sh no respalda un archivo que todavía no existía), así que para
  # cuando existe algún backup, nuestro propio bloque ya estaba adentro —
  # "restaurar el más reciente" no necesariamente deshace nada. Por eso acá
  # es una alternativa explícita y solo interactiva (nunca con --yes), a
  # diferencia de rtk-config.toml más abajo, que no tiene delimitadores para
  # poder hacer un strip quirúrgico y por eso sí usa backup-restore como
  # único mecanismo posible.
  local backups want_restore=false
  backups="$(backups_for "$PROJECT_AGENTS_MD")"
  if [[ -n "$backups" ]] && ! $YES; then
    local reply
    read -rp "  Hay backup(s) de AGENTS.md. ¿Restaurar un backup completo en vez de solo remover el bloque? [y/N] " reply || true
    [[ "$reply" =~ ^[Yy]$ ]] && want_restore=true
  fi

  if $want_restore; then
    local chosen
    chosen="$(echo "$backups" | head -n1)"
    echo "  Backups disponibles para AGENTS.md (más reciente primero):"
    local i=1
    while IFS= read -r b; do
      echo "    [$i] $b"
      i=$((i + 1))
    done <<< "$backups"
    local sel
    read -rp "  Restaurar [1] (Enter = más reciente), o número: " sel || true
    if [[ -n "$sel" ]]; then
      chosen="$(echo "$backups" | sed -n "${sel}p")"
      [[ -z "$chosen" ]] && { log_error "Selección inválida."; exit 1; }
    fi
    cp -p "$chosen" "$PROJECT_AGENTS_MD"
    log_ok "AGENTS.md restaurado desde $chosen"
    return
  fi

  if [[ ! -f "$PROJECT_AGENTS_MD" ]]; then
    log_info "No hay AGENTS.md que revertir."
    return
  fi
  if ! grep -qF '<!-- stack-optimizacion:begin -->' "$PROJECT_AGENTS_MD"; then
    log_info "AGENTS.md no tiene bloque de opencode-godmode — nada que remover."
    return
  fi

  local tmp
  tmp="$(mktemp)"
  awk '
    /<!-- stack-optimizacion:begin -->/ { inside = 1; next }
    /<!-- stack-optimizacion:end -->/   { inside = 0; next }
    !inside { print }
  ' "$PROJECT_AGENTS_MD" > "$tmp"

  if [[ -z "$(tr -d '[:space:]' < "$tmp")" ]]; then
    rm -f "$PROJECT_AGENTS_MD" "$tmp"
    log_ok "AGENTS.md quedó vacío tras remover el bloque — se borró (lo habíamos creado nosotros)."
  else
    mv "$tmp" "$PROJECT_AGENTS_MD"
    log_ok "Bloque de opencode-godmode removido de AGENTS.md (sin backup previo que restaurar)."
  fi
}

restore_rtk_config() {
  log_step "rtk config.toml"
  local target="$HOME/.config/rtk/config.toml"
  local backups
  backups="$(backups_for "$target")"

  if [[ -z "$backups" ]]; then
    log_warn "No hay backup de $target — un merge aditivo no se puede deshacer con seguridad."
    log_warn "Se deja el archivo como está. Revisalo a mano si querés limpiarlo."
    return
  fi

  local chosen
  chosen="$(echo "$backups" | head -n1)"
  if ! $YES; then
    echo "  Backups disponibles para rtk config.toml (más reciente primero):"
    local i=1
    while IFS= read -r b; do
      echo "    [$i] $b"
      i=$((i + 1))
    done <<< "$backups"
    local sel
    read -rp "  Restaurar [1] (Enter = más reciente), o número: " sel || true
    if [[ -n "$sel" ]]; then
      chosen="$(echo "$backups" | sed -n "${sel}p")"
      [[ -z "$chosen" ]] && { log_error "Selección inválida."; exit 1; }
    fi
  fi
  cp -p "$chosen" "$target"
  log_ok "rtk config.toml restaurado desde $chosen"
}

# ---------------------------------------------------------------------------
# rtk
# ---------------------------------------------------------------------------

uninstall_rtk() {
  log_step "rtk"
  if ! have_cmd rtk; then
    log_info "rtk no está instalado — nada que hacer."
    return
  fi
  if confirm_low_risk "¿Desinstalar el hook de rtk (rtk init -g --uninstall)?"; then
    rtk init -g --uninstall || log_warn "rtk init -g --uninstall devolvió error — revisalo a mano."
    log_ok "Hook de rtk removido."
  fi
  if confirm_low_risk "¿Borrar el binario de rtk y ~/.config/rtk?"; then
    rm -f "$HOME/.local/bin/rtk"
    rm -rf "$HOME/.config/rtk"
    log_ok "Binario y config de rtk borrados."
  fi
}

# ---------------------------------------------------------------------------
# gentle-ai (nunca en silencio)
# ---------------------------------------------------------------------------

uninstall_gentle_ai() {
  log_step "gentle-ai"
  if ! have_cmd gentle-ai; then
    log_info "gentle-ai no está instalado — nada que hacer."
    return
  fi
  log_info "gentle-ai es global a la máquina — puede estar en uso por otros proyectos."
  log_info "gentle-ai guarda sus propios backups antes de cualquier cambio (ver 'gentle-ai --help')."
  if confirm_high_risk "¿Desinstalar los componentes de gentle-ai para OpenCode (gentle-ai uninstall --agent opencode)?"; then
    # --all es exclusivo: no se puede combinar con --agent (gentle-ai lo
    # rechaza). --agent opencode sin --component remueve todos los
    # componentes gestionados para ESE agente únicamente.
    gentle-ai uninstall --agent opencode --yes || log_warn "gentle-ai uninstall devolvió error — revisalo a mano."
    log_ok "Componentes de gentle-ai para OpenCode removidos (el binario y ~/.local/bin/gentle-ai NO se tocan)."
  else
    log_info "gentle-ai se deja instalado y configurado."
  fi
}

# ---------------------------------------------------------------------------
# Engram (memorias del usuario — nunca en silencio)
# ---------------------------------------------------------------------------

warn_engram_data() {
  log_step "Engram"
  if [[ -d "$HOME/.engram" ]]; then
    log_info "Las memorias de Engram (~/.engram) son datos del usuario y NO se tocan por defecto."
    if confirm_high_risk "¿Borrar TODAS las memorias de Engram (~/.engram)? Esto es irreversible."; then
      rm -rf "$HOME/.engram"
      log_ok "\$HOME/.engram borrado."
    else
      log_info "\$HOME/.engram se deja intacto."
    fi
  else
    log_info "No hay ~/.engram — nada que hacer."
  fi
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

main() {
  restore_or_strip_agents_md
  restore_rtk_config
  uninstall_rtk
  uninstall_gentle_ai
  warn_engram_data

  log_step "Resumen"
  echo "  ${BDD_DIR}/ (si existe) no fue tocado — son artefactos del usuario."
  echo "  Backups usados/disponibles en: $BACKUP_ROOT"
  echo "  Corré ./verify.sh para confirmar el estado final."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
