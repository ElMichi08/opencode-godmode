#!/usr/bin/env bash
#
# opencode-godmode — verificación post-install SIN agente (PLAN.md 4.3).
# Imprime PASS/WARN/FAIL por ítem. Sale con código != 0 si algo FAIL.
#
# Uso: ./verify.sh   (se corre desde la raíz del proyecto instalado)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(pwd)"
STACK_CONF="$PROJECT_DIR/stack.conf"
PROJECT_AGENTS_MD="$PROJECT_DIR/AGENTS.md"
BACKUP_ROOT="$HOME/.local/state/opencode-godmode/backups"

export PATH="$HOME/.local/bin:$PATH"

if [[ -t 1 ]]; then
  C_OK=$'\033[0;32m'; C_WARN=$'\033[0;33m'; C_FAIL=$'\033[0;31m'; C_RESET=$'\033[0m'
else
  C_OK=""; C_WARN=""; C_FAIL=""; C_RESET=""
fi

FAIL_COUNT=0
WARN_COUNT=0
PASS_COUNT=0

pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf '%s  [PASS]%s %s\n' "$C_OK" "$C_RESET" "$1"; }
warn() { WARN_COUNT=$((WARN_COUNT + 1)); printf '%s  [WARN]%s %s\n' "$C_WARN" "$C_RESET" "$1"; }
fail() { FAIL_COUNT=$((FAIL_COUNT + 1)); printf '%s  [FAIL]%s %s\n' "$C_FAIL" "$C_RESET" "$1"; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

if [[ ! -f "$STACK_CONF" ]]; then
  fail "$STACK_CONF no existe — corré ./install.sh primero."
  exit 1
fi
# shellcheck disable=SC1090
source "$STACK_CONF"
PROFILE_NAME="${PROFILE_NAME:-godmode-$(basename "$PROJECT_DIR")}"
WITH_RTK="${WITH_RTK:-true}"
WITH_BDD="${WITH_BDD:-true}"
BDD_DIR="${BDD_DIR:-features}"

echo "opencode-godmode — verify.sh (perfil: ${PROFILE_NAME})"
echo "══════════════════════════════════════════════════════"

# --- OpenCode ---
if have_cmd opencode; then
  pass "opencode --version: $(opencode --version)"
else
  fail "opencode no está en PATH"
fi

# --- gentle-ai ---
if have_cmd gentle-ai && gentle-ai doctor >/dev/null 2>&1; then
  pass "gentle-ai doctor reporta sano"
else
  fail "gentle-ai doctor reportó problemas (o gentle-ai no está en PATH)"
fi

# --- Engram ---
if have_cmd engram && engram version >/dev/null 2>&1; then
  title="opencode-godmode-verify-$$"
  save_out="$(engram save "$title" "verify.sh smoke test" --project opencode-godmode-verify 2>&1)"
  id="$(printf '%s' "$save_out" | grep -oE '#[0-9]+' | head -1 | tr -d '#')"
  if [[ -n "$id" ]] && engram search "$title" --project opencode-godmode-verify >/dev/null 2>&1; then
    pass "Engram: ciclo save/search de prueba OK"
    engram delete "$id" --hard >/dev/null 2>&1 || warn "No se pudo borrar la memoria de prueba de verify.sh (#$id)"
  else
    fail "Engram: ciclo save/search de prueba falló (save_out: $save_out)"
  fi
else
  fail "engram no está en PATH o 'engram version' falló"
fi

# --- Config de OpenCode: orquestador + perfil + modelos ---
OPENCODE_JSON="$HOME/.config/opencode/opencode.json"
if [[ -f "$OPENCODE_JSON" ]] && jq -e '.agent."gentle-orchestrator"' "$OPENCODE_JSON" >/dev/null 2>&1; then
  pass "opencode.json contiene el orquestador de gentle-ai"
else
  fail "opencode.json no contiene .agent.\"gentle-orchestrator\" ($OPENCODE_JSON)"
fi

check_phase_model() {
  local phase="$1" expected="$2"
  [[ -z "$expected" ]] && return 0
  local actual
  actual="$(jq -r --arg k "sdd-${phase}-${PROFILE_NAME}" '.agent[$k].model // empty' "$OPENCODE_JSON" 2>/dev/null)"
  if [[ "$actual" == "$expected" ]]; then
    pass "Perfil ${PROFILE_NAME}: sdd-${phase} -> ${expected}"
  else
    fail "Perfil ${PROFILE_NAME}: sdd-${phase} esperaba '${expected}', encontré '${actual:-<sin asignar>}'"
  fi
}

if [[ -f "$OPENCODE_JSON" ]]; then
  check_phase_model "design" "${MODEL_DESIGN:-}"
  check_phase_model "verify" "${MODEL_REVIEW:-}"
  if [[ -n "${MODEL_IMPLEMENT:-}" && "${MODEL_IMPLEMENT}" != "${MODEL_EXPLORE:-}" ]]; then
    check_phase_model "apply" "${MODEL_IMPLEMENT}"
  fi
  orch_model="$(jq -r --arg k "sdd-orchestrator-${PROFILE_NAME}" '.agent[$k].model // empty' "$OPENCODE_JSON" 2>/dev/null)"
  if [[ "$orch_model" == "${MODEL_EXPLORE:-}" ]]; then
    pass "Perfil ${PROFILE_NAME}: orquestador -> ${MODEL_EXPLORE}"
  else
    fail "Perfil ${PROFILE_NAME}: orquestador esperaba '${MODEL_EXPLORE:-}', encontré '${orch_model:-<sin asignar>}'"
  fi
fi

# --- Modelos responden (WARN, no FAIL) ---
if have_cmd opencode; then
  models_out="$(timeout 15 opencode models 2>&1 || true)"
  for m in "${MODEL_EXPLORE:-}" "${MODEL_DESIGN:-}" "${MODEL_REVIEW:-}"; do
    [[ -z "$m" ]] && continue
    if printf '%s' "$models_out" | grep -qF "$m"; then
      pass "Modelo '$m' aparece en 'opencode models'"
    else
      warn "Modelo '$m' no aparece en 'opencode models' — revisá que el proveedor esté autenticado"
    fi
  done
fi

# --- rtk ---
if [[ "${WITH_RTK}" == "true" ]]; then
  if have_cmd rtk && rtk --version >/dev/null 2>&1; then
    pass "rtk --version: $(rtk --version)"
  else
    fail "rtk no está en PATH o 'rtk --version' falló"
  fi
  if have_cmd rtk && rtk gain >/dev/null 2>&1; then
    pass "rtk gain OK (no es el paquete equivocado de crates.io)"
  else
    fail "rtk gain falló — puede ser el paquete equivocado ('Rust Type Kit' de crates.io)"
  fi
  if have_cmd rtk && rtk init --show >/dev/null 2>&1; then
    pass "rtk init --show confirma el hook instalado"
  else
    fail "rtk init --show falló — el hook no parece instalado"
  fi

  RTK_CONFIG="$HOME/.config/rtk/config.toml"
  if [[ -f "$RTK_CONFIG" ]]; then
    missing="$(python3 - "$SCRIPT_DIR/templates/rtk-config.toml" "$RTK_CONFIG" <<'PYEOF'
import sys, tomllib, pathlib
template = tomllib.loads(pathlib.Path(sys.argv[1]).read_text(encoding="utf-8"))
target = tomllib.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
missing = []
for section, keys in template.items():
    if section not in target:
        missing.append(section)
        continue
    for key in keys:
        if key not in target[section]:
            missing.append(f"{section}.{key}")
print("\n".join(missing))
PYEOF
)"
    if [[ -z "$missing" ]]; then
      pass "rtk config.toml contiene todas las entradas de templates/rtk-config.toml"
    else
      fail "rtk config.toml — faltan entradas: $(printf '%s' "$missing" | tr '\n' ' ')"
    fi
  else
    fail "No existe $RTK_CONFIG"
  fi
else
  echo "  (WITH_RTK=false — se salta la verificación de rtk)"
fi

# --- AGENTS.md ---
if [[ -f "$PROJECT_AGENTS_MD" ]] && grep -qF '<!-- stack-optimizacion:begin -->' "$PROJECT_AGENTS_MD" \
   && grep -qF '<!-- stack-optimizacion:end -->' "$PROJECT_AGENTS_MD"; then
  pass "AGENTS.md contiene los delimitadores de stack-optimizacion"
else
  fail "AGENTS.md no contiene los delimitadores esperados ($PROJECT_AGENTS_MD)"
fi

# --- Registro SDD (WARN, no FAIL) ---
SKILL_REGISTRY_MD="$PROJECT_DIR/.atl/skill-registry.md"
SKILL_REGISTRY_CACHE="$PROJECT_DIR/.atl/.skill-registry.cache.json"
if [[ -f "$SKILL_REGISTRY_MD" && -f "$SKILL_REGISTRY_CACHE" ]] && jq -e '.fingerprint' "$SKILL_REGISTRY_CACHE" >/dev/null 2>&1; then
  pass "Proyecto registrado en SDD (.atl/skill-registry.md + cache válido)"
else
  warn "Falta el registro SDD — corré '/sdd-init' en OpenCode y luego 'gentle-ai skill-registry refresh'"
fi
if [[ -f "$PROJECT_DIR/openspec/config.yaml" ]]; then
  pass "openspec/config.yaml presente (informativo, no requerido)"
fi

# --- BDD_DIR (WARN, no FAIL) ---
if [[ "${WITH_BDD}" == "true" ]]; then
  if [[ -d "$PROJECT_DIR/$BDD_DIR" ]]; then
    pass "BDD_DIR (${BDD_DIR}/) existe"
  else
    warn "BDD_DIR (${BDD_DIR}/) no existe todavía — el flujo BDD queda latente hasta que crees .feature ahí"
  fi
else
  echo "  (WITH_BDD=false — se salta la verificación de BDD_DIR)"
fi

# --- Backups ---
key_agents="$(printf '%s' "$PROJECT_AGENTS_MD" | sed 's#[/ ]#_#g')"
if find "$BACKUP_ROOT" -maxdepth 1 -name "${key_agents}.*.bak" 2>/dev/null | grep -q .; then
  pass "Existen backups de AGENTS.md en $BACKUP_ROOT"
else
  echo "  (sin backups de AGENTS.md todavía — normal en una primera instalación)"
fi

echo "══════════════════════════════════════════════════════"
echo "Resumen: ${PASS_COUNT} PASS, ${WARN_COUNT} WARN, ${FAIL_COUNT} FAIL"

[[ "$FAIL_COUNT" -eq 0 ]]
