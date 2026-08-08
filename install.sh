#!/usr/bin/env bash
#
# opencode-godmode — bootstrap reproducible de gentle-ai + rtk + capa BDD para
# OpenCode, sin consumir contexto de agente. Ver PLAN.md y DECISIONS.md.
#
# Uso: ./install.sh [--dry-run] [--yes] [--uninstall]
#   Se corre desde la raíz del proyecto que querés configurar (busca/genera
#   ./stack.conf ahí, y escribe el bloque en ./AGENTS.md ahí). gentle-ai, Engram
#   y rtk son globales a la máquina (principio 9): una segunda corrida en OTRO
#   proyecto no los reinstala.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"
STACK_CONF="$PROJECT_DIR/stack.conf"
PROJECT_AGENTS_MD="$PROJECT_DIR/AGENTS.md"
BACKUP_ROOT="$HOME/.local/state/opencode-godmode/backups"

DRY_RUN=false
YES=false

# gentle-ai y rtk instalan sus binarios en ~/.local/bin sin agregarlo al PATH
# del shell (a diferencia del instalador de OpenCode). Lo agregamos acá,
# siempre, para que la detección de "ya instalado" (idempotencia, principio 9)
# funcione incluso en una terminal nueva que nunca reconfiguró su PATH.
export PATH="$HOME/.local/bin:$PATH"

# --uninstall es un atajo: delega en uninstall.sh con el resto de los flags,
# antes de que install.sh procese nada más.
for arg in "$@"; do
  if [[ "$arg" == "--uninstall" ]]; then
    rest=()
    for a in "$@"; do [[ "$a" == "--uninstall" ]] || rest+=("$a"); done
    exec "$SCRIPT_DIR/uninstall.sh" "${rest[@]}"
  fi
done

# ---------------------------------------------------------------------------
# Helpers: logging, confirmación, comandos
# ---------------------------------------------------------------------------

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

have_cmd() { command -v "$1" >/dev/null 2>&1; }

confirm() {
  local prompt="$1"
  if $DRY_RUN; then
    log_info "[HUMAN GATE] $prompt"
    return 0
  fi
  $YES && return 0
  local reply
  read -rp "$prompt [y/N] " reply || true
  [[ "$reply" =~ ^[Yy]$ ]]
}

usage() {
  cat <<'EOF'
Uso: ./install.sh [--dry-run] [--yes] [--uninstall]

  --dry-run     Muestra todo lo que haría, sin ejecutar nada. Los pasos
                interactivos se listan como [HUMAN GATE].
  --yes         No interactivo donde sea posible. Requiere ./stack.conf
                presente. Si un paso necesita interacción real (TUI de
                gentle-ai en una versión vieja sin flags no-interactivos),
                falla temprano en vez de colgarse.
  --uninstall   Atajo a ./uninstall.sh (pasa el resto de los flags).
EOF
}

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    --yes) YES=true ;;
    -h|--help) usage; exit 0 ;;
    *) log_error "Flag desconocida: $arg"; usage; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Backups: solo si el contenido a modificar cambió respecto al último backup.
# ---------------------------------------------------------------------------

backup_if_changed() {
  local target="$1"
  [[ -f "$target" ]] || return 0

  mkdir -p "$BACKUP_ROOT"
  local key
  key="$(printf '%s' "$target" | sed 's#[/ ]#_#g')"
  local latest
  latest="$(find "$BACKUP_ROOT" -maxdepth 1 -name "${key}.*.bak" -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -n1 | cut -d' ' -f2- || true)"

  if [[ -n "$latest" ]] && cmp -s "$target" "$latest"; then
    log_info "Backup sin cambios respecto al último — no se duplica ($target)."
    return 0
  fi

  local ts dest
  ts="$(date +%Y%m%d%H%M%S)"
  dest="$BACKUP_ROOT/${key}.${ts}.bak"
  if $DRY_RUN; then
    log_info "[DRY-RUN] backup: $target -> $dest"
  else
    cp -p "$target" "$dest"
    log_info "Backup creado: $dest"
  fi
}

# ---------------------------------------------------------------------------
# stack.conf: cargar o generar interactivamente
# ---------------------------------------------------------------------------

generate_stack_conf_interactive() {
  log_step "stack.conf"
  log_info "No se encontró $STACK_CONF — generándolo de forma interactiva."
  local default_profile
  default_profile="godmode-$(basename "$PROJECT_DIR")"

  read -rp "PROFILE_NAME [$default_profile]: " PROFILE_NAME
  PROFILE_NAME="${PROFILE_NAME:-$default_profile}"
  read -rp "MODEL_EXPLORE (ej: openrouter/qwen/qwen3-30b-a3b:free): " MODEL_EXPLORE
  read -rp "MODEL_DESIGN (ej: anthropic/claude-sonnet-4-6): " MODEL_DESIGN
  read -rp "MODEL_REVIEW [= MODEL_DESIGN]: " MODEL_REVIEW
  MODEL_REVIEW="${MODEL_REVIEW:-$MODEL_DESIGN}"
  read -rp "MODEL_IMPLEMENT (opcional, vacío = hereda MODEL_EXPLORE): " MODEL_IMPLEMENT
  read -rp "WITH_RTK [true]: " WITH_RTK
  WITH_RTK="${WITH_RTK:-true}"
  read -rp "WITH_BDD [true]: " WITH_BDD
  WITH_BDD="${WITH_BDD:-true}"
  read -rp "BDD_DIR [features]: " BDD_DIR
  BDD_DIR="${BDD_DIR:-features}"

  cat > "$STACK_CONF" <<EOF
PROFILE_NAME="${PROFILE_NAME}"
MODEL_EXPLORE="${MODEL_EXPLORE}"
MODEL_DESIGN="${MODEL_DESIGN}"
MODEL_IMPLEMENT="${MODEL_IMPLEMENT}"
MODEL_REVIEW="${MODEL_REVIEW}"

WITH_RTK=${WITH_RTK}
WITH_BDD=${WITH_BDD}
BDD_DIR="${BDD_DIR}"
EOF
  log_ok "stack.conf generado en $STACK_CONF"
}

load_stack_conf() {
  if [[ ! -f "$STACK_CONF" ]]; then
    if $YES; then
      log_error "$STACK_CONF no existe. --yes requiere stack.conf presente."
      log_error "Ejecutá sin --yes para generarlo interactivamente, o copiá stack.conf.example."
      exit 1
    fi
    generate_stack_conf_interactive
  fi

  # shellcheck disable=SC1090
  source "$STACK_CONF"

  if [[ -z "${MODEL_EXPLORE:-}" || -z "${MODEL_DESIGN:-}" || -z "${MODEL_REVIEW:-}" ]]; then
    log_error "MODEL_EXPLORE, MODEL_DESIGN y MODEL_REVIEW son obligatorios en stack.conf."
    log_error "Para ver modelos disponibles: opencode models --refresh && opencode models"
    exit 1
  fi

  PROFILE_NAME="${PROFILE_NAME:-godmode-$(basename "$PROJECT_DIR")}"
  WITH_RTK="${WITH_RTK:-true}"
  WITH_BDD="${WITH_BDD:-true}"
  BDD_DIR="${BDD_DIR:-features}"
}

# ---------------------------------------------------------------------------
# Paso 1: preflight
# ---------------------------------------------------------------------------

ensure_apt_pkg() {
  local pkg="$1"
  have_cmd "$pkg" && return 0
  if confirm "Falta '$pkg'. ¿Instalarlo con sudo apt install $pkg?"; then
    if $DRY_RUN; then
      log_info "[DRY-RUN] sudo apt-get install -y $pkg"
      return 0
    fi
    sudo apt-get update -qq
    sudo apt-get install -y "$pkg"
  else
    log_error "'$pkg' es requerido. Instalalo manualmente y reintentá."
    exit 1
  fi
}

ensure_node() {
  if have_cmd node && have_cmd npm; then
    local major
    major="$(node --version | sed 's/^v//' | cut -d. -f1)"
    if [[ "$major" -ge 18 ]]; then
      log_ok "Node $(node --version) / npm $(npm --version) — requerido por gentle-ai."
      return
    fi
  fi
  # gentle-ai requiere Node 18+/npm en toda plataforma (DECISIONS.md (a));
  # no lo instala por sí mismo, solo avisa. Lo resolvemos acá como Gate 2.
  if confirm "gentle-ai requiere Node.js 18+ y npm. ¿Instalar Node LTS vía NodeSource + apt?"; then
    if $DRY_RUN; then
      log_info "[DRY-RUN] curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -"
      log_info "[DRY-RUN] sudo apt-get install -y nodejs"
      return
    fi
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs
  else
    log_error "Node.js 18+ es requerido por gentle-ai. Instalalo manualmente y reintentá."
    exit 1
  fi
}

preflight() {
  log_step "Preflight"

  have_cmd apt-get || {
    log_error "Este instalador es exclusivo para Linux Debian/Ubuntu-based (WSL o nativo)."
    log_error "No se encontró 'apt'. Ver PLAN.md principio 7."
    exit 1
  }

  if ! have_cmd opencode; then
    log_error "OpenCode no está en PATH. Instalalo con:"
    log_error "  curl -fsSL https://opencode.ai/install | bash"
    log_error "(no se resuelve vía apt — ver https://github.com/anomalyco/opencode)"
    exit 1
  fi
  log_ok "OpenCode: $(opencode --version)"

  ensure_apt_pkg curl
  ensure_apt_pkg jq
  ensure_apt_pkg git
  ensure_apt_pkg python3
  ensure_node
}

# ---------------------------------------------------------------------------
# Paso 3-4: gentle-ai — binario y configuración de agentes
# ---------------------------------------------------------------------------

step_gentle_ai_binary() {
  log_step "gentle-ai — binario"
  if have_cmd gentle-ai; then
    log_ok "gentle-ai ya instalado ($(gentle-ai --version 2>/dev/null || true)) — se salta."
    return
  fi
  if $DRY_RUN; then
    log_info "[DRY-RUN] curl -fsSL https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh | bash"
    return
  fi
  curl -fsSL https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh | bash
  have_cmd gentle-ai || {
    log_error "gentle-ai no quedó en PATH tras instalar. Agregá ~/.local/bin a tu PATH y reintentá."
    exit 1
  }
  log_ok "gentle-ai instalado: $(gentle-ai --version)"
}

verify_gate1() {
  gentle-ai doctor >/dev/null 2>&1 || return 1
  [[ -f "$HOME/.gentle-ai/state.json" ]] || return 1
  jq -e '.installed_agents | index("opencode")' "$HOME/.gentle-ai/state.json" >/dev/null 2>&1 || return 1
  [[ -f "$HOME/.config/opencode/opencode.json" ]] || return 1
  jq -e '.agent."gentle-orchestrator"' "$HOME/.config/opencode/opencode.json" >/dev/null 2>&1 || return 1
  return 0
}

gentle_ai_supports_noninteractive() {
  gentle-ai install --help 2>&1 | grep -q -- '--agent'
}

# Camino de respaldo si una versión vieja de gentle-ai no trae los flags
# no-interactivos confirmados en DECISIONS.md (a). Implementa el patrón
# obligatorio de PLAN.md 4.2.1: PAUSA -> HANDOFF -> VERIFICACIÓN -> REINTENTO.
gate1_tui_loop() {
  echo "════════════════════════════════════════════════════"
  echo " PASO MANUAL: se abrirá el instalador de gentle-ai."
  echo ""
  echo " Dentro del TUI, seleccioná:"
  echo "   1. Agente: OpenCode"
  echo "   2. Plugins comunitarios (si los ofrece): aceptar"
  echo "   3. Completá el flujo hasta salir del instalador."
  echo "════════════════════════════════════════════════════"
  read -rp "Presioná Enter para abrir el TUI..." _ || true

  while true; do
    gentle-ai || true   # bloqueante; set -e no debe matar el script si sale != 0
    if verify_gate1; then
      log_ok "gentle-ai configurado correctamente."
      return 0
    fi
    log_warn "La verificación falló: la config de OpenCode no quedó completa."
    local opt
    read -rp "[r]eintentar TUI / [a]bortar instalación: " opt || true
    if [[ "$opt" == "a" ]]; then
      log_error "Abortado. Revertí lo ya hecho con ./uninstall.sh"
      exit 1
    fi
  done
}

step_gentle_ai_agents() {
  log_step "gentle-ai — configuración de agentes"

  if verify_gate1; then
    log_ok "gentle-ai ya tiene OpenCode configurado — se salta."
    return
  fi

  if $DRY_RUN; then
    log_info "[DRY-RUN] gentle-ai install --agent opencode --preset full-gentleman --sdd-mode multi --scope=global"
    return
  fi

  if ! gentle_ai_supports_noninteractive; then
    if $YES; then
      log_error "gentle-ai requiere configuración interactiva (TUI) en esta versión; --yes no está disponible para este paso."
      log_error "Ejecutá sin --yes."
      exit 1
    fi
    gate1_tui_loop
    return
  fi

  local attempt
  for attempt in 1 2; do
    if gentle-ai install --agent opencode --preset full-gentleman --sdd-mode multi --scope=global; then
      if verify_gate1; then
        log_ok "gentle-ai configurado correctamente."
        return
      fi
    fi
    log_warn "La verificación post-instalación falló (intento $attempt/2)."
    if [[ "$attempt" -eq 1 ]]; then
      if $YES; then
        log_error "gentle-ai install falló con --yes activo. Ejecutá sin --yes para diagnosticar"
        log_error "(causas comunes: proveedor de modelos sin autenticar, red)."
        exit 1
      fi
      confirm "¿Reintentar 'gentle-ai install'?" || {
        log_error "Abortado. Revertí con ./uninstall.sh"
        exit 1
      }
    fi
  done
  log_error "gentle-ai no quedó configurado tras 2 intentos. Revisá 'gentle-ai doctor' manualmente."
  log_error "Revertí lo ya hecho con ./uninstall.sh"
  exit 1
}

# ---------------------------------------------------------------------------
# Paso 5: verificación gentle-ai + Engram (siempre corre)
# ---------------------------------------------------------------------------

step_verify_gentle_engram() {
  log_step "Verificación gentle-ai + Engram"
  if $DRY_RUN; then
    log_info "[DRY-RUN] gentle-ai doctor; engram version; ciclo save/search/delete de prueba"
    return
  fi

  gentle-ai doctor || { log_error "gentle-ai doctor reportó problemas."; exit 1; }
  have_cmd engram || { log_error "engram no está en PATH (gentle-ai debería haberlo instalado)."; exit 1; }
  engram version >/dev/null || { log_error "'engram version' falló."; exit 1; }

  local title="opencode-godmode-smoke-$$" save_out id
  if ! save_out="$(engram save "$title" "smoke test opencode-godmode" --project opencode-godmode-smoke 2>&1)"; then
    log_error "engram save de prueba falló: $save_out"
    exit 1
  fi
  id="$(printf '%s' "$save_out" | grep -oE '#[0-9]+' | head -1 | tr -d '#')"
  if [[ -z "$id" ]]; then
    log_error "No se pudo parsear el ID de la memoria de prueba (output: $save_out)."
    exit 1
  fi
  if ! engram search "$title" --project opencode-godmode-smoke >/dev/null 2>&1; then
    log_error "engram search de prueba falló."
    exit 1
  fi
  engram delete "$id" --hard >/dev/null 2>&1 || log_warn "No se pudo borrar la memoria de prueba (#$id) — borrala manualmente."

  log_ok "gentle-ai + Engram verificados."
}

# ---------------------------------------------------------------------------
# Paso 6: perfiles de modelo por fase
# ---------------------------------------------------------------------------

step_profiles() {
  log_step "Perfiles de modelo por fase (${PROFILE_NAME})"

  if $DRY_RUN; then
    log_info "[DRY-RUN] gentle-ai sync --profile ${PROFILE_NAME}:${MODEL_EXPLORE}"
    log_info "[DRY-RUN] gentle-ai sync --profile-phase ${PROFILE_NAME}:sdd-design:${MODEL_DESIGN}"
    log_info "[DRY-RUN] gentle-ai sync --profile-phase ${PROFILE_NAME}:sdd-verify:${MODEL_REVIEW}"
    if [[ -n "${MODEL_IMPLEMENT:-}" && "${MODEL_IMPLEMENT}" != "${MODEL_EXPLORE}" ]]; then
      log_info "[DRY-RUN] gentle-ai sync --profile-phase ${PROFILE_NAME}:sdd-apply:${MODEL_IMPLEMENT}"
    fi
    return
  fi

  gentle-ai sync --profile "${PROFILE_NAME}:${MODEL_EXPLORE}"
  gentle-ai sync --profile-phase "${PROFILE_NAME}:sdd-design:${MODEL_DESIGN}"
  # La fase de review/gate se llama sdd-verify, no sdd-review (confirmado en
  # vivo: gentle-ai rechaza "sdd-review" listando las 10 fases válidas — ver
  # DECISIONS.md (b) y su addendum). sdd-apply es la fase de implementación
  # (sdd-implement tampoco existe). Solo se sincroniza sdd-apply si el usuario
  # pidió un modelo distinto al de exploración — si no, hereda como cualquier
  # fase sin asignar.
  gentle-ai sync --profile-phase "${PROFILE_NAME}:sdd-verify:${MODEL_REVIEW}"
  if [[ -n "${MODEL_IMPLEMENT:-}" && "${MODEL_IMPLEMENT}" != "${MODEL_EXPLORE}" ]]; then
    gentle-ai sync --profile-phase "${PROFILE_NAME}:sdd-apply:${MODEL_IMPLEMENT}"
  fi

  log_ok "Perfil ${PROFILE_NAME} sincronizado."
}

# ---------------------------------------------------------------------------
# Paso 7: rtk
# ---------------------------------------------------------------------------

merge_rtk_config() {
  local target="$HOME/.config/rtk/config.toml"
  local template="$TEMPLATES_DIR/rtk-config.toml"

  mkdir -p "$(dirname "$target")"
  backup_if_changed "$target"

  if $DRY_RUN; then
    log_info "[DRY-RUN] merge no-destructivo: $template -> $target"
    return
  fi

  python3 - "$template" "$target" <<'PYEOF'
import sys, tomllib, re, pathlib

template_path, target_path = sys.argv[1], sys.argv[2]
template_text = pathlib.Path(template_path).read_text(encoding="utf-8")
template = tomllib.loads(template_text)

target = pathlib.Path(target_path)
existing_text = target.read_text(encoding="utf-8") if target.exists() else ""
existing = tomllib.loads(existing_text) if existing_text.strip() else {}


def split_sections(text):
    order, blocks = [], {}
    current, buf = None, []
    for line in text.splitlines(keepends=True):
        m = re.match(r"^\[([^\]]+)\]\s*$", line)
        if m:
            if current is not None:
                blocks[current] = "".join(buf)
            current = m.group(1)
            order.append(current)
            buf = [line]
        else:
            if current is None:
                continue
            buf.append(line)
    if current is not None:
        blocks[current] = "".join(buf)
    return order, blocks


def fmt_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, str):
        return '"' + v.replace("\\", "\\\\").replace('"', '\\"') + '"'
    if isinstance(v, list):
        return "[" + ", ".join(fmt_value(i) for i in v) + "]"
    raise TypeError(f"unsupported type for rtk config: {type(v)}")


order, blocks = split_sections(template_text)
lines = existing_text.splitlines(keepends=True) if existing_text else []
changed = False
pending_append = []  # secciones enteras nuevas, en orden de template

for section in order:
    if section not in existing:
        # Sección entera ausente en el archivo del usuario: se agrega tal
        # cual viene del template (ya trae su propio separador en blanco),
        # sin tocar nada de lo existente.
        pending_append.append(blocks[section])
        changed = True
        continue

    # Sección presente: solo se agregan las keys de nivel superior que
    # falten. Nunca se toca una línea que el usuario ya tenía.
    template_section = template[section]
    existing_section = existing[section]
    missing_keys = [k for k in template_section if k not in existing_section]
    if not missing_keys:
        continue

    header_idx = next(
        i for i, l in enumerate(lines)
        if re.match(rf"^\[{re.escape(section)}\]\s*$", l)
    )
    new_lines = [f"{k} = {fmt_value(template_section[k])}\n" for k in missing_keys]
    lines[header_idx + 1:header_idx + 1] = new_lines
    changed = True

if pending_append:
    if lines and not lines[-1].endswith("\n"):
        lines.append("\n")
    if lines:
        lines.append("\n")
    lines.extend(pending_append)

if not changed:
    print(f"rtk config sin cambios: {target_path}")
else:
    new_text = "".join(lines) if lines else template_text
    tomllib.loads(new_text)  # valida antes de escribir
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(new_text, encoding="utf-8")
    print(f"rtk config actualizado: {target_path}")
PYEOF

  log_ok "rtk config aplicado en $target"
}

step_rtk() {
  log_step "rtk"
  if [[ "${WITH_RTK}" != "true" ]]; then
    log_info "WITH_RTK=false — se salta instalación y config de rtk."
    return
  fi

  local need_install=true
  if have_cmd rtk && rtk init --show >/dev/null 2>&1; then
    need_install=false
  fi

  if $need_install; then
    if $DRY_RUN; then
      log_info "[DRY-RUN] curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh"
      log_info "[DRY-RUN] rtk init -g --opencode --auto-patch"
    else
      curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
      have_cmd rtk || {
        log_error "rtk no quedó en PATH tras instalar (revisá ~/.local/bin)."
        exit 1
      }
      # rtk gain detecta la colisión de nombre con el paquete equivocado de
      # crates.io ("Rust Type Kit") — ver DECISIONS.md (i).
      rtk gain >/dev/null || {
        log_error "rtk gain falló — puede que se haya instalado el paquete equivocado."
        log_error "Reinstalá con el script oficial (no 'cargo install rtk' de crates.io)."
        exit 1
      }
      rtk init -g --opencode --auto-patch
      log_ok "rtk instalado: $(rtk --version)"
    fi
  else
    log_ok "rtk ya instalado y configurado — se salta instalación (el merge de config sí corre)."
  fi

  merge_rtk_config
}

# ---------------------------------------------------------------------------
# Paso 8: AGENTS.md
# ---------------------------------------------------------------------------

render_agents_block() {
  RENDERED_BDD="$WITH_BDD" RENDERED_RTK="$WITH_RTK" awk '
    BEGIN { bdd = ENVIRON["RENDERED_BDD"]; rtk = ENVIRON["RENDERED_RTK"] }
    /<!-- IF WITH_RTK -->/  { skip = (rtk != "true"); next }
    /<!-- END WITH_RTK -->/ { skip = 0; next }
    /<!-- IF WITH_BDD -->/  { skip = (bdd != "true"); next }
    /<!-- END WITH_BDD -->/ { skip = 0; next }
    !skip { print }
  ' "$TEMPLATES_DIR/AGENTS.md.block" | sed "s#__BDD_DIR__#${BDD_DIR}#g"
}

step_agents_md() {
  log_step "AGENTS.md"
  local begin="<!-- stack-optimizacion:begin -->"
  local end="<!-- stack-optimizacion:end -->"
  local rendered
  rendered="$(render_agents_block)"

  if $DRY_RUN; then
    log_info "[DRY-RUN] insertaría/actualizaría el bloque entre delimitadores en $PROJECT_AGENTS_MD"
    return
  fi

  backup_if_changed "$PROJECT_AGENTS_MD"

  if [[ -f "$PROJECT_AGENTS_MD" ]] && grep -qF "$begin" "$PROJECT_AGENTS_MD"; then
    local tmp
    tmp="$(mktemp)"
    RENDERED_BLOCK="$rendered" awk -v begin="$begin" -v end="$end" '
      BEGIN { inside = 0; block = ENVIRON["RENDERED_BLOCK"] }
      index($0, begin) { print block; inside = 1; next }
      index($0, end)   { inside = 0; next }
      !inside { print }
    ' "$PROJECT_AGENTS_MD" > "$tmp"
    mv "$tmp" "$PROJECT_AGENTS_MD"
    log_ok "Bloque de AGENTS.md actualizado (ya existía)."
  else
    printf '\n%s\n' "$rendered" >> "$PROJECT_AGENTS_MD"
    log_ok "Bloque de AGENTS.md agregado."
  fi
}

# ---------------------------------------------------------------------------
# Paso 9: resumen final
# ---------------------------------------------------------------------------

print_summary() {
  log_step "Resumen"
  cat <<EOF
  Perfil SDD:        ${PROFILE_NAME}
  Proyecto:          ${PROJECT_DIR}
  AGENTS.md:         ${PROJECT_AGENTS_MD}
  WITH_RTK:          ${WITH_RTK}
  WITH_BDD:          ${WITH_BDD} (BDD_DIR=${BDD_DIR})
  Backups:           ${BACKUP_ROOT}

  Pasos manuales restantes:
    1. Reiniciá OpenCode.
    2. Dentro de OpenCode, en este proyecto, corré /sdd-init.
    3. Desde una terminal: gentle-ai skill-registry refresh
    4. Verificá con Tab que el perfil "${PROFILE_NAME}" aparece.
    5. Corré el smoke test de VERIFY-AGENT.md dentro de OpenCode.

  ./verify.sh confirma más tarde si los pasos 2-3 quedaron aplicados.
EOF
}

# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

main() {
  load_stack_conf
  preflight
  step_gentle_ai_binary
  step_gentle_ai_agents
  step_verify_gentle_engram
  step_profiles
  step_rtk
  step_agents_md
  print_summary
}

# El guard permite `source install.sh` (tests) sin disparar la instalación.
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main
fi
