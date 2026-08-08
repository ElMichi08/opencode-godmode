#!/usr/bin/env bash
#
# opencode-godmode — protocolo de actualización segura del stack (PLAN.md 4.4).
#
# Uso: ./upgrade.sh
#   Se corre desde la raíz del proyecto instalado.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(pwd)"

export PATH="$HOME/.local/bin:$PATH"

if [[ -t 1 ]]; then
  C_INFO=$'\033[0;36m'; C_OK=$'\033[0;32m'; C_ERR=$'\033[0;31m'; C_STEP=$'\033[1;35m'; C_RESET=$'\033[0m'
else
  C_INFO=""; C_OK=""; C_ERR=""; C_STEP=""; C_RESET=""
fi
log_step()  { printf '\n%s==> %s%s\n' "$C_STEP" "$1" "$C_RESET"; }
log_info()  { printf '%s  %s%s\n' "$C_INFO" "$1" "$C_RESET"; }
log_ok()    { printf '%s  \xe2\x9c\x94 %s%s\n' "$C_OK" "$1" "$C_RESET"; }
log_error() { printf '%s  \xe2\x9c\x98 %s%s\n' "$C_ERR" "$1" "$C_RESET" >&2; }
have_cmd()  { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Paso 1: mostrar versión actual/última de gentle-ai, pausar para leer notas
# ---------------------------------------------------------------------------

log_step "gentle-ai — versión"
if ! have_cmd gentle-ai; then
  log_error "gentle-ai no está en PATH. Corré ./install.sh primero."
  exit 1
fi
log_info "Instalada: $(gentle-ai version 2>/dev/null)"
log_info "Chequeando última versión disponible (gentle-ai update)..."
gentle-ai update || log_info "(el chequeo de versión falló — puede ser rate-limit de GitHub; seguimos igual)"
log_info "Release notes: https://github.com/Gentleman-Programming/gentle-ai/releases"
read -rp "Leé los cambios antes de continuar [Enter para seguir]... " _ || true

# ---------------------------------------------------------------------------
# Paso 2: gentle-ai upgrade (backups automáticos propios de gentle-ai)
# ---------------------------------------------------------------------------

log_step "gentle-ai upgrade"
gentle-ai upgrade || {
  log_error "gentle-ai upgrade devolvió error. Revisá el output de arriba antes de seguir."
  exit 1
}
log_ok "gentle-ai actualizado."

# ---------------------------------------------------------------------------
# Paso 3: rtk (mecanismo oficial = re-correr el instalador; no tiene
# self-update dedicado — confirmado contra 'rtk --help' en DECISIONS.md)
# ---------------------------------------------------------------------------

STACK_CONF="$PROJECT_DIR/stack.conf"
WITH_RTK=true
if [[ -f "$STACK_CONF" ]]; then
  # shellcheck disable=SC1090
  source "$STACK_CONF"
fi
WITH_RTK="${WITH_RTK:-true}"

if [[ "$WITH_RTK" == "true" ]] && have_cmd rtk; then
  log_step "rtk"
  curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
  log_ok "rtk actualizado: $(rtk --version)"
fi

# ---------------------------------------------------------------------------
# Paso 4: re-aplicar el bloque de AGENTS.md (idempotente — por si el formato
# cambió en una versión nueva de opencode-godmode)
# ---------------------------------------------------------------------------

log_step "AGENTS.md"
(
  set -- # limpiar argumentos posicionales antes de source-ear install.sh:
         # sus loops de nivel superior (--uninstall passthrough, flags)
         # iteran "$@", y no queremos que hereden los de upgrade.sh.
  # shellcheck disable=SC1090
  source "$SCRIPT_DIR/install.sh"
  load_stack_conf
  step_agents_md
) || { log_error "No se pudo re-aplicar el bloque de AGENTS.md."; exit 1; }

# ---------------------------------------------------------------------------
# Paso 5: verify.sh completo
# ---------------------------------------------------------------------------

log_step "verify.sh"
"$SCRIPT_DIR/verify.sh"
verify_rc=$?

# ---------------------------------------------------------------------------
# Paso 6: recordatorios finales
# ---------------------------------------------------------------------------

log_step "Resumen"
cat <<EOF
  Reiniciá OpenCode para que tome los cambios.

  Si algo se comporta raro después del upgrade, gentle-ai guarda sus propios
  backups automáticos antes de cada cambio — restaurá con:
    gentle-ai restore
  (te va a mostrar los backups disponibles; correlo sin argumentos primero
  para ver las opciones).
EOF

exit "$verify_rc"
