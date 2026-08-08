# PLAN.md — Brief de construcción: "opencode-godmode" (bootstrap reproducible del stack gentle-ai + rtk + BDD para OpenCode, sin consumir contexto de agente)

> **Instrucción para Claude Code:** Este documento es la especificación completa de la
> herramienta a construir. Léelo entero antes de escribir código. Construye siguiendo
> las fases de la sección 8, en orden, probando cada fase antes de avanzar. Trabaja
> dentro de un Linux Debian/Ubuntu-based (WSL o nativo). Ante cualquier ambigüedad no cubierta aquí, elige la
> opción más simple y documenta la decisión en DECISIONS.md. No agregues features no
> especificadas.

---

## 1. Contexto y problema

El usuario configura OpenCode con un stack de optimización de tokens: workflow
Spec-Driven Development con subagentes y memoria persistente (provistos por
**gentle-ai**, que instala y gestiona **Engram**), compresión de output bash
(**rtk**), asignación de modelos por fase SDD, y reglas de compresión de reportes
por rol de subagente. Hoy ese setup se hace a mano o vía un runbook markdown que
ejecuta el propio agente de OpenCode, consumiendo 30-80% de la ventana de contexto
en la instalación.

Además, el usuario escribe requisitos en Gherkin (archivos .feature) FUERA del
agente, como artefactos de análisis previos. El flujo SDD debe consumirlos como
fuente de verdad del comportamiento esperado, con trazabilidad:
escenario → decisión de diseño → test → gate de review. Gentle-ai no provee esta
capa BDD; es el aporte propio de opencode-godmode.

**Objetivo:** un bootstrap en bash que instala y configura todo el stack de forma
reproducible SIN consumir contexto de agente, agrega la capa BDD, y verifica el
resultado. El agente solo participa al final en una verificación de humo de menos
de 1.500 tokens.

## 2. Principios de diseño (no negociables)

1. **Cero contexto de agente durante la instalación.** Todo corre en bash puro.
   Pasos interactivos en terminal (TUI de gentle-ai) son aceptables: consumen
   tiempo humano, no tokens.
2. **gentle-ai es dependencia de primera clase, no se reimplementa.** Provee el
   SDD (agentes, orquestador, perfiles por fase) y gestiona Engram. Decisión
   deliberada del usuario: recibir las actualizaciones de prompts de la comunidad
   vía `gentle-ai upgrade` en vez de mantener templates propios.
3. **Nunca modificar archivos gestionados por gentle-ai.** Todo lo propio de
   opencode-godmode(reglas BDD, reglas de compresión por rol, notas de rtk) vive
   EXCLUSIVAMENTE en el AGENTS.md del proyecto, entre delimitadores propios, donde
   `gentle-ai sync` no lo toca. Regla dura: si un cambio requiere editar un archivo
   generado por gentle-ai, el cambio está mal diseñado.
4. **Idempotente:** correr el instalador dos veces no rompe nada ni duplica bloques.
5. **Reversible:** `uninstall.sh` deja el sistema como estaba. Backup automático de
   toda config que opencode-godmode toque directamente, con timestamp — pero solo
   si el contenido a modificar cambió respecto al último backup existente, para no
   acumular copias idénticas en reinstalaciones idempotentes. La estrategia de
   reversión de `uninstall.sh` no es uniforme, y es intencional (ver 4.6): para
   AGENTS.md el default es remover el bloque por sus propios delimitadores
   (restaurar-desde-backup queda como alternativa explícita, solo interactiva);
   para rtk-config.toml, que no tiene delimitadores, sí es restaurar por
   defecto el backup más reciente, con opción de listar y elegir uno anterior.
   (gentle-ai hace sus propios backups de lo suyo; no duplicarlos.)
6. **Legible:** el instalador completo debe poder leerse en 10 minutos. Bash +
   coreutils + curl + jq como máximo para toda la lógica del instalador.
   Excepción única y acotada: `python3` (stdlib, sin dependencias externas) solo
   para el merge no-destructivo de `rtk-config.toml` — jq no entiende TOML. El
   resto del instalador sigue siendo bash puro.
7. **Target v1: Linux Debian/Ubuntu-based exclusivamente (WSL o nativo).**
   Ambos caminos usan `apt`, así que no hace falta distinguirlos; detectar que
   `apt` exista y abortar con mensaje claro si no. macOS y otras distros de Linux
   quedan fuera de v1.
8. **Los requisitos son artefacto humano.** Los agentes consumen los .feature pero
   jamás los crean ni los editan.
9. **El stack es global a la máquina, no al proyecto.** gentle-ai, Engram y rtk se
   instalan una sola vez por máquina; `install.sh` detecta si ya están instalados
   y configurados (misma verificación que usarían los gates) y salta esos pasos
   en una segunda corrida sobre otro proyecto. Solo el perfil SDD, el bloque de
   AGENTS.md y BDD_DIR son por-proyecto.

## 3. Arquitectura de la solución

```
opencode-godmode/
├── install.sh              # Punto de entrada único (orquesta todo el bootstrap)
├── uninstall.sh            # Reversión de lo que opencode-godmode agregó
├── verify.sh               # Verificación post-install SIN agente
├── upgrade.sh              # Protocolo de actualización segura del stack
├── stack.conf.example      # Configuración: modelos, flags
├── templates/
│   ├── AGENTS.md.block             # Bloque delimitado: BDD + compresión por rol + rtk
│   └── rtk-config.toml             # Config rtk: exclusiones + tee en fallos
├── VERIFY-AGENT.md         # Prompt de humo para el agente (< 1.500 tokens)
├── DECISIONS.md            # Registro de decisiones tomadas durante la construcción
└── README.md               # Uso, arquitectura, protocolo de upgrade, capa BDD
```

Nota: NO hay templates de agentes SDD ni de opencode.json — los agentes y el
orquestador los genera y actualiza gentle-ai. Los perfiles de modelo por fase se
crean vía la CLI de gentle-ai (`gentle-ai sync --profile / --profile-phase`), no
editando config a mano.

## 4. Especificación funcional

### 4.1 stack.conf (configuración del usuario)

`install.sh` busca `./stack.conf`; si no existe, lo genera interactivamente
preguntando (con defaults sensatos) y lo guarda:

```bash
# Modelos por fase SDD (formato proveedor/modelo, sintaxis OpenCode/gentle-ai)
PROFILE_NAME="godmode-mi-proyecto"  # nombre del perfil SDD que gentle-ai creará;
                         # como el stack es global a la máquina (principio 9) pero
                         # el perfil es por-proyecto, el generador interactivo
                         # sugiere "godmode-<nombre del directorio actual>" como
                         # default para no chocar con el perfil de otro proyecto
MODEL_EXPLORE=""         # barato/gratis — ej: openrouter/qwen/qwen3-30b-a3b:free
MODEL_DESIGN=""          # capaz — ej: anthropic/claude-sonnet-4-6
MODEL_IMPLEMENT=""       # opcional — vacío = hereda MODEL_EXPLORE (igual que el
                         # runbook manual SETUP-STACK.md); setear solo si se
                         # quiere un modelo distinto al de exploración
MODEL_REVIEW=""          # capaz — default: igual a MODEL_DESIGN

WITH_RTK=true            # compresión de output bash
WITH_BDD=true            # activa las reglas BDD en AGENTS.md.block
BDD_DIR="features"       # directorio de .feature relativo a la raíz del proyecto
```

Validación: si MODEL_EXPLORE, MODEL_DESIGN o MODEL_REVIEW quedan vacíos, abortar
con instrucciones de cómo listar los modelos disponibles. MODEL_IMPLEMENT puede
quedar vacío (hereda MODEL_EXPLORE) sin que eso sea un error. Con WITH_BDD=false,
el bloque de AGENTS.md se renderiza sin la sección BDD (bloques condicionales en
el renderizado).

### 4.2 install.sh — flujo

Los pasos 3, 4, 5 y 7 son globales a la máquina (principio 9): cada uno empieza
verificando si ya está satisfecho (misma condición que usaría su gate/verify.sh)
y se salta con un aviso si es así. Esto es lo que hace que una segunda corrida
de install.sh en OTRO proyecto de la misma máquina no reinstale binarios ni
reabra el TUI de gentle-ai. Los pasos 6, 8 y 9 son por-proyecto y siempre corren.

1. **Preflight:** verificar que `apt` existe (Debian/Ubuntu-based, WSL o nativo
   — principio 7); si no, abortar. Verificar `opencode` en PATH: si falta,
   abortar con el link de instalación (no se resuelve vía apt). Verificar curl,
   jq, git, python3 (este último solo se usa en el paso 7, para el merge de
   rtk-config.toml): si falta alguno, Gate 2 pregunta si instalarlos vía
   `sudo apt install`. Registrar versión de OpenCode.
2. **Backup:** antes de modificar AGENTS.md del proyecto o
   `~/.config/rtk/config.toml`, comparar el contenido actual contra el backup con
   timestamp más reciente que exista; si difieren (o no hay backup previo), crear
   uno nuevo. Si son idénticos, no duplicar. La config de OpenCode que gestiona
   gentle-ai NO se respalda aquí: gentle-ai tiene su propio sistema de backups y
   duplicarlo genera confusión sobre cuál restaurar.
3. **gentle-ai — binario (saltar si `gentle-ai --version` ya responde):**
   instalar vía su script oficial
   (`https://raw.githubusercontent.com/Gentleman-Programming/gentle-ai/main/scripts/install.sh`).
   Verificar con `gentle-ai --version` (equivalentes confirmados: `gentle-ai
   version`, `gentle-ai -v`). Decisión ya tomada (registrada en
   DECISIONS.md): se usa curl directo y NO brew, a diferencia de
   SETUP-STACK.md que prioriza brew — v1 es Linux Debian/Ubuntu-based, donde
   linuxbrew no es garantía, y mantener una sola vía de instalación
   simplifica el script (principio 6). Nota: el instalador oficial de
   gentle-ai deja el binario en `~/.local/bin` sin tocar `.bashrc` (a
   diferencia del instalador de OpenCode, que sí lo hace) — `install.sh`
   exporta ese PATH él mismo al arrancar para que la detección de "ya
   instalado" (principio 9) funcione incluso en una terminal nueva. rtk hace
   lo mismo, misma solución.
4. **gentle-ai — configuración de agentes (HUMAN GATE 1, saltar si la
   verificación programática de 4.2.1 ya pasa):** camino primario confirmado
   y 100% no-interactivo: `gentle-ai install --agent opencode --preset
   full-gentleman --sdd-mode multi --scope=global` (validado en vivo contra
   gentle-ai 2.3.0: 64/64 checks, `opencode.json` real con el orquestador
   presente). El gate bloqueante con TUI de la sección 4.2.1 pasa a ser el
   **fallback** para una versión de gentle-ai vieja que no traiga esos flags
   (detectable con `gentle-ai install --help | grep -q -- '--agent'`) — no es
   el camino primario. Esto NO viola el principio 1: es interacción de
   terminal, cero tokens de agente.
5. **Verificación gentle-ai + Engram (siempre corre; rápida y no destructiva):**
   `gentle-ai doctor` debe reportar sano; `engram version` responde (gentle-ai lo
   instala); ciclo save/search/delete de una memoria de prueba con la CLI real
   de engram: `engram save <título> <mensaje> --project <nombre>` (el output
   trae el id, `Memory saved: #<id> "<título>" (...)`), `engram search
   <query> --project <nombre>`, `engram delete <id> --hard`. Esta CLI es
   distinta de las tools MCP `mem_save`/`mem_search` que usa el agente (esas
   sí están bien nombradas en §5 — son la interfaz MCP, no la CLI standalone).
6. **Perfiles de modelo por fase:** crear vía CLI usando stack.conf, replicando la
   lógica del runbook manual (SETUP-STACK.md Fase 2.2): exploración e
   implementación heredan el modelo barato del perfil base; solo diseño y review
   reciben override explícito. `sdd-apply` (la fase de implementación — ver nota
   de nombres abajo) NO se sincroniza como fase aparte salvo que el usuario haya
   puesto un MODEL_IMPLEMENT distinto de MODEL_EXPLORE:
   ```bash
   gentle-ai sync --profile ${PROFILE_NAME}:${MODEL_EXPLORE}
   gentle-ai sync --profile-phase ${PROFILE_NAME}:sdd-design:${MODEL_DESIGN}
   gentle-ai sync --profile-phase ${PROFILE_NAME}:sdd-verify:${MODEL_REVIEW}
   # Solo si MODEL_IMPLEMENT está seteado y difiere de MODEL_EXPLORE:
   gentle-ai sync --profile-phase ${PROFILE_NAME}:sdd-apply:${MODEL_IMPLEMENT}
   ```
   **Nombres de fase confirmados (10 en total, todas prefijo `sdd-`):** init,
   explore, propose, spec, design, tasks, **apply** (esta es "implementar" —
   `sdd-implement` NO existe), **verify** (esta es "review" — `sdd-review` NO
   existe; gentle-ai lo rechaza con `unknown phase "sdd-review"`), archive,
   onboard. `sdd-apply` es una fase de primera clase como cualquier otra, no
   tiene herencia implícita especial más allá de lo que tendría cualquier fase
   sin asignar (cae al modelo base del perfil).
7. **rtk** (si WITH_RTK; saltar instalación del binario y `rtk init -g
   --opencode --auto-patch` si `rtk --version` y `rtk init --show` ya lo
   confirman instalado — el merge de `rtk-config.toml` sí corre siempre, es
   idempotente): instalar vía script oficial
   (`https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh`;
   misma razón que el paso 3 para omitir brew), verificar con `rtk gain` (detecta
   la colisión de nombre con el paquete equivocado de crates.io "Rust Type Kit"),
   ejecutar `rtk init -g --opencode --auto-patch` (no-interactivo confirmado), y
   aplicar `templates/rtk-config.toml` a `~/.config/rtk/config.toml` con un merge
   no-destructivo en python3: `tomllib` (stdlib) solo para LEER y para VALIDAR el
   resultado antes de escribir — nunca para reserializar el archivo completo
   (perdería comentarios/formato). La escritura es una inserción de línea
   idempotente y quirúrgica: si falta una sección entera del template, se agrega
   completa al final; si la sección existe pero le falta una key, se inserta esa
   línea justo debajo del header de la sección. Ninguna línea que el usuario ya
   tenía se toca nunca — así se garantiza no pisar sus exclusiones previas sin
   necesitar un serializador TOML (que tampoco existe en stdlib).
8. **AGENTS.md:** renderizar `templates/AGENTS.md.block` (según WITH_BDD y
   BDD_DIR) e insertarlo en el AGENTS.md del proyecto actual (crear si no existe),
   entre delimitadores `<!-- stack-optimizacion:begin -->` /
   `<!-- stack-optimizacion:end -->` — misma convención que ya usa el runbook
   manual SETUP-STACK.md / AGENTS-STACK-BLOCK.md, para que un proyecto migrado
   desde el runbook sea reconocido sin duplicar bloques. Si los delimitadores ya
   existen, reemplazar el contenido entre ellos (idempotencia); si no existen,
   agregar el bloque al final del archivo.
9. **Resumen final:** qué se instaló, qué se saltó, dónde quedaron los backups, y
   los pasos manuales restantes: reiniciar OpenCode; dentro de OpenCode, en el
   proyecto, ejecutar `/sdd-init` (no se automatiza: corre dentro del agente, no
   en bash — principio 1) y luego `gentle-ai skill-registry refresh` desde una
   terminal; verificar con Tab que el perfil ${PROFILE_NAME} aparece; y correr
   VERIFY-AGENT.md. `verify.sh` puede confirmar más tarde si `/sdd-init` +
   skill-registry quedaron aplicados (ver 4.3).

Flags: `--dry-run` (muestra todo lo que haría sin ejecutar; los pasos interactivos
se listan como "[HUMAN GATE]" con las instrucciones que mostrarían), `--yes`
(no interactivo donde sea posible, requiere stack.conf presente; ver 4.2.1 para su
comportamiento ante gates bloqueantes), `--uninstall` (atajo a uninstall.sh).

### 4.2.1 Patrón obligatorio de human gates

Un paso manual mal implementado es un script que confía en que el humano hizo lo
correcto. Todo human gate de opencode-godmode implementa las CUATRO partes:
**PAUSA → HANDOFF → VERIFICACIÓN → REINTENTO**. Implementar solo las dos primeras
es un bug.

Regla rectora: **al humano se le pregunta qué hacer, nunca si el sistema quedó
bien.** Que el sistema quedó bien lo comprueba el script de forma programática.
Prohibido usar confirmaciones tipo "¿salió todo bien? [s/n]" como criterio de
avance.

**Gate 1 — TUI de gentle-ai (bloqueante, dentro del script).** Único gate de este
tipo. **Confirmado: en la versión actual de gentle-ai (2.3.0) NO hace falta** —
`gentle-ai install --agent opencode --preset full-gentleman --sdd-mode multi
--scope=global` cubre exactamente lo que este gate haría, de forma 100%
no-interactiva. Este gate queda como **fallback** para una gentle-ai vieja sin
esos flags (detectable con `gentle-ai install --help | grep -q -- '--agent'`
antes de decidir cuál camino tomar).

Aprovechar que el TUI es un proceso de terminal bloqueante: bash espera solo, sin
polling ni señales. Estructura de referencia (nombres de comandos y checks ya
confirmados contra gentle-ai real):

```bash
verificar_gate1() {
    gentle-ai doctor >/dev/null 2>&1 || return 1
    jq -e '.installed_agents | index("opencode")' ~/.gentle-ai/state.json >/dev/null 2>&1 || return 1
    jq -e '.agent."gentle-orchestrator"' ~/.config/opencode/opencode.json >/dev/null 2>&1 || return 1
}

# VERIFICACIÓN PRIMERO: si otra corrida anterior (este u otro proyecto en la
# misma máquina) ya dejó gentle-ai configurado, no reabrir el TUI.
if verificar_gate1; then
    echo "✔ gentle-ai ya estaba configurado — se salta el TUI."
else
    echo "════════════════════════════════════════════════════"
    echo " PASO MANUAL: se abrirá el instalador de gentle-ai."
    echo ""
    echo " Dentro del TUI, selecciona:"
    echo "   1. Agente: OpenCode"
    echo "   2. Plugins comunitarios (si los ofrece): aceptar"
    echo "      sub-agent-statusline y sdd-engram-plugin"
    echo "   3. Completa el flujo hasta salir del instalador."
    echo "════════════════════════════════════════════════════"
    read -rp "Presiona Enter para abrir el TUI..."

    while true; do
        gentle-ai                    # ← bloqueante: el script espera aquí

        # VERIFICACIÓN: nunca confiar en que el paso humano salió bien
        if verificar_gate1; then
            echo "✔ gentle-ai configurado correctamente."
            break
        fi

        echo "✘ La verificación falló: la config de OpenCode no quedó completa."
        read -rp "[r]eintentar TUI / [a]bortar instalación: " opt
        [[ "$opt" == "a" ]] && { echo "Revierte con ./uninstall.sh"; exit 1; }
    done
fi
```

Requisitos del gate 1:
- La verificación es programática: `gentle-ai doctor` + validación con jq de que
  el orquestador quedó en la config real de OpenCode. Nunca preguntarle al humano.
- La verificación corre ANTES de abrir el TUI, no solo después: en una máquina
  donde el stack ya está configurado (otro proyecto, o una reinstalación), el
  gate se salta sin interacción — necesario para que principio 4 (idempotente) y
  principio 9 (stack global) se cumplan de verdad.
- El bucle de reintento cubre los fallos reales: TUI cerrado a la mitad, agente
  equivocado seleccionado, proceso interrumpido.
- Abortar debe indicar cómo revertir lo ya hecho.
- `set -euo pipefail` no debe matar el script si el TUI retorna código != 0 por
  salida del usuario: manejar ese caso dentro del bucle.

**Gate 2 — confirmaciones puntuales.** `sudo apt install jq/curl` si faltan,
sobreescritura de configuraciones existentes. Patrón simple sí/no. En `--yes` se
auto-aceptan.

**Gate 3 — pasos post-script.** Reiniciar OpenCode; ejecutar `/sdd-init` en el
proyecto (dentro de OpenCode) y luego `gentle-ai skill-registry refresh` (en
terminal); verificar con Tab que el perfil aparece; correr VERIFY-AGENT.md. NO
son gates dentro del script: ocurren después de que install.sh termina, porque
`/sdd-init` requiere una sesión de OpenCode que principio 1 prohíbe abrir desde
el instalador. Se imprimen en el resumen final como checklist numerado, y
`verify.sh` queda disponible para comprobarlos al volver.

**Comportamiento de `--yes`:** auto-acepta los gates tipo 2. Gate 1 "es
necesario" solo cuando su verificación (4.2.1) falla EN ESE MOMENTO y no hay
camino no-interactivo — no es una propiedad estática de gentle-ai. En una
máquina ya configurada (otro proyecto, o reinstalación), la verificación pasa
sin abrir el TUI y `--yes` sigue de largo con normalidad. Si la verificación sí
falla y no hay camino no-interactivo, `--yes` debe fallar TEMPRANO —en el
preflight, antes de instalar nada— con mensaje explícito: "gentle-ai requiere
configuración interactiva; --yes no está disponible para este paso. Ejecuta sin
--yes." Prohibido quedarse colgado esperando un TUI en un entorno sin humano.

### 4.3 verify.sh — verificación SIN agente

Checklist automatizado que imprime PASS/FAIL por ítem y sale con código != 0 si
algo falla:

- `opencode --version` responde
- `gentle-ai doctor` reporta sano
- `engram version` y ciclo save/search/delete de prueba
- La config de OpenCode contiene el orquestador de gentle-ai y el perfil
  ${PROFILE_NAME} con los modelos de stack.conf. Rutas confirmadas:
  `~/.config/opencode/opencode.json` (orquestador en `.agent."gentle-orchestrator"`,
  modelo por fase en `.agent."sdd-{phase}-${PROFILE_NAME}".model` — ej.
  `.agent."sdd-design-${PROFILE_NAME}".model`) y `~/.gentle-ai/state.json`
  (`.installed_agents` para confirmar que gentle-ai sabe que gestiona OpenCode).
- Los modelos configurados responden: para cada modelo del perfil, confirmar
  que aparece en el listado de `opencode models` (sin `--refresh` — ese flag
  intenta refrescar contra el proveedor real y puede colgarse minutos si no
  hay proveedores configurados; la lista sin refrescar ya sirve para el
  chequeo). WARN (no FAIL) si un modelo no aparece, listando modelo y
  proveedor para que el usuario revise su API key.
- `rtk --version`, `rtk gain` y `rtk init --show` confirman binario y plugin
  (si WITH_RTK)
- La config de rtk contiene las entradas de templates/rtk-config.toml
- AGENTS.md del proyecto contiene los delimitadores de stack-optimizacion
- El proyecto quedó registrado en SDD — WARN (no FAIL) si falta, con
  instrucción de correr `/sdd-init` + `gentle-ai skill-registry refresh`, ya
  que no bloquean el resto del stack. Check confirmado: existencia de
  `.atl/skill-registry.md` + `.atl/.skill-registry.cache.json` (escritos por
  `gentle-ai skill-registry refresh`, con contrato de archivo estable) y que
  el cache JSON parsea con una key `fingerprint` no nula. `openspec/config.yaml`
  (el artefacto que en teoría escribe `/sdd-init`) es solo informativo — su
  formato es "prompt-driven", no un contrato de archivo garantizado por
  gentle-ai, así que su ausencia NUNCA es FAIL ni WARN.
- Si WITH_BDD=true: existe ${BDD_DIR}/ o se imprime WARN (no FAIL) con
  instrucción de crearlo — la ausencia de .features no rompe nada, el flujo BDD
  queda latente
- Los backups de la fase 2 existen (si aplicaba)

### 4.4 upgrade.sh — actualización segura del stack

La contracara de depender de gentle-ai: sus upgrades traen mejoras de prompts pero
pueden cambiar comportamiento. Protocolo:

1. Mostrar la versión actual (`gentle-ai version`) y correr `gentle-ai update`
   (comando de solo-chequeo, confirmado — no muta nada) para ver la última
   disponible; imprimir el link a las release notes
   (`https://github.com/Gentleman-Programming/gentle-ai/releases`) y PAUSAR:
   "Lee los cambios antes de continuar [Enter]".
2. `gentle-ai upgrade` (comando de aplicar-cambios confirmado, distinto de
   `update`; hace su propio backup automático antes de tocar nada — visible en
   su output como "Creating pre-upgrade backup"). Si falla (ej. su propio
   chequeo de versión no pudo completarse), abortar con el error tal cual —
   gentle-ai no aplica nada si no pudo chequear versiones.
3. Actualizar rtk por su mecanismo oficial (si WITH_RTK) — no tiene subcomando
   de self-update; el mecanismo oficial es re-correr el mismo script de
   instalación, que descarga y sobreescribe con la última release.
4. Re-aplicar el bloque de AGENTS.md (idempotente — por si el formato del bloque
   cambió en una versión nueva de opencode-godmode).
5. Correr `verify.sh` completo y mostrar el resultado.
6. Recordar en pantalla: reiniciar OpenCode y, ante comportamiento raro post-
   upgrade, `gentle-ai restore` (comando confirmado) para restaurar desde los
   backups automáticos de gentle-ai.

### 4.5 VERIFY-AGENT.md — humo con agente (< 1.500 tokens)

Prompt corto que el usuario pega en OpenCode tras reiniciar. Pide al agente:
1. Confirmar que ve el orquestador de gentle-ai y el perfil ${PROFILE_NAME}.
2. Ejecutar `git status` vía bash y confirmar output comprimido (verificable con
   `rtk gain --history`).
3. Guardar y buscar una memoria de prueba en Engram, luego borrarla.
4. Lanzar el subagente de exploración sobre una pregunta trivial del repo y
   confirmar que el reporte respeta el formato comprimido del bloque de AGENTS.md.
5. Responder una pregunta explicativa como orquestador y confirmar estilo normal
   (la persona docente de gentle-ai intacta).
6. Si WITH_BDD=true: crear `${BDD_DIR}/smoke.feature` mínimo (3 líneas), pedir una
   tarea trivial relacionada, confirmar que el plan la referencia por
   `archivo/escenario`, y borrar el archivo al final.

Requisito duro: menos de 1.500 tokens medidos, incluyendo instrucciones de reporte.
Recortar redacción de otras pruebas si hace falta.

### 4.6 uninstall.sh

- **Remover bloque de AGENTS.md por delimitadores es el default** (sin tocar
  el resto) — NO restaurar el backup más reciente por defecto para este
  archivo. Razón confirmada probando el flujo completo: `backup_if_changed`
  solo respalda un archivo que YA existe; la primera vez que install.sh crea
  AGENTS.md desde cero no hay nada que respaldar, así que el primer backup
  que llega a existir (recién en la segunda modificación) ya tiene nuestro
  propio bloque adentro — "restaurar el más reciente" no deshace nada en ese
  caso. Restaurar-desde-backup-completo queda como alternativa explícita y
  SOLO interactiva (nunca automática ni siquiera con `--yes`, para no
  reintroducir el mismo problema en corridas no-interactivas).
- `rtk init -g --uninstall` + ofrecer borrar el binario y ~/.config/rtk. Para
  este archivo sí corresponde restaurar-desde-backup por defecto (no hay
  delimitadores en TOML para poder hacer un strip quirúrgico como en
  AGENTS.md).
- Para gentle-ai: NO desinstalarlo silenciosamente — preguntar, incluso con
  `--yes`. Si el usuario acepta: `gentle-ai uninstall --agent opencode --yes`
  (comando confirmado — `--all` es mutuamente excluyente con `--agent` y
  gentle-ai lo rechaza con error si se combinan; esto remueve todo lo
  gestionado para ESE agente sin tocar otros agentes que gentle-ai pueda
  tener configurados en la misma máquina, y sin tocar el binario de
  gentle-ai). Recordar que sus backups automáticos permiten restaurar con
  `gentle-ai restore`.
- NO borrar `~/.engram` por defecto — las memorias son datos del
  usuario; pedir confirmación explícita, incluso con `--yes`.
- NUNCA tocar ${BDD_DIR}/ — los .feature son artefactos del usuario.

## 5. Especificación del bloque AGENTS.md (el artefacto propio más importante)

Como los prompts de los agentes pertenecen a gentle-ai, TODO el valor agregado de
opencode-godmode en comportamiento vive en este bloque. Presupuesto: máximo ~65
líneas sin BDD, ~75 con BDD (se relee cada sesión; su costo en tokens es
permanente — referencia: AGENTS-STACK-BLOCK.md, la versión sin BDD, mide 64
líneas). Contenido:

**Encabezado:** "Reglas de opencode-godmode — complementan la configuración de
gentle-ai. Ante conflicto con una instrucción explícita del usuario en la
conversación, gana el usuario."

**Compresión por rol (siempre):**
- Subagentes de exploración: reportes en fragmentos, sin saludos ni preámbulos,
  una línea por hallazgo con path:línea, sección final `ABIERTO:` con lo no
  encontrado. Incluir un mini-ejemplo de reporte bien formado (3-4 líneas).
- Subagentes de implementación: prosa mínima, reporte final de un archivo por
  línea + resultado de tests. NUNCA comprimir ni truncar código, mensajes de
  error literales, o paths — la compresión aplica a la prosa, no a la sustancia.
- Orquestador y fases de diseño/review: estilo explicativo normal de gentle-ai;
  estas reglas de compresión NO les aplican.

**rtk (si WITH_RTK):**
- El hook solo intercepta el tool Bash; para output largo preferir comandos bash
  o `rtk read/grep/find` explícitos.
- Ante fallo de comando, leer el log tee completo que rtk indica en vez de
  re-ejecutar.

**Protocolo de memoria (Engram, siempre):**
- Al cerrar trabajo significativo (bugfix no trivial, decisión de arquitectura,
  causa raíz encontrada): guardar con mem_save (qué / por qué / dónde /
  aprendido).
- Al arrancar tarea sobre un área ya trabajada: mem_search ANTES de explorar el
  código. Re-explorar lo ya conocido es el desperdicio de tokens más caro.
- No guardar trivialidades (typos, renombres, cambios de formato).

**Requisitos BDD (solo si WITH_BDD=true; máximo 10 líneas):**
- Los .feature bajo ${BDD_DIR}/ son la fuente de verdad del comportamiento. Ante
  conflicto entre chat y .feature, señalarlo antes de proceder.
- Al iniciar una tarea, cargar SOLO los escenarios pertinentes; citarlos por
  `archivo.feature / Escenario: nombre` (y tag, ej. @HU-07); nunca pegar .feature
  completos en reportes ni specs.
- La spec de diseño incluye tabla de trazabilidad escenario → decisión → criterio
  de aceptación; escenarios ambiguos se reportan al usuario, no se reescriben.
- Cada test que cubre un escenario lleva comentario `# Cubre: archivo/escenario`;
  el review rechaza si hay escenarios en alcance sin test que pase, listándolos.
- Los agentes no crean ni editan archivos .feature.

**Higiene de contexto:**
- Respetar los triggers de delegación de gentle-ai: 4+ archivos para entender un
  flujo → delegar exploración; 2+ archivos no triviales → un solo writer y
  review fresco antes de cerrar.
- Ante sesión larga con señales de degradación (contradicciones, olvidos),
  proponer guardar estado en Engram (mem_session_end) y continuar en sesión
  fresca.
- No pegar archivos completos en el contexto cuando un extracto alcanza.

## 6. Restricciones y manejo de errores

- Nunca `sudo` sin preguntar; si apt necesita instalar jq/curl, pedirlo explícito.
- Todo `set -euo pipefail`; ante error, imprimir en qué paso falló y cómo revertir.
- El merge del TOML de rtk debe preservar lo que el usuario tenga configurado.
- No hardcodear rutas de Windows; todo es Linux Debian/Ubuntu-based (WSL o nativo).
- Regla del principio 3 aplicada al código: install.sh, upgrade.sh y uninstall.sh
  tienen PROHIBIDO escribir en los archivos que gentle-ai genera o sincroniza.
  Toda interacción con la config SDD es a través de la CLI de gentle-ai.

## 7. Fuera de alcance explícito (registrar en README)

- Windows nativo, macOS, y distros Linux sin `apt` (v1 es Debian/Ubuntu-based,
  WSL o nativo — principio 7).
- Templates propios de agentes SDD: decisión deliberada de usar gentle-ai y sus
  actualizaciones; no reimplementar.
- Ejecución de Gherkin con frameworks BDD (Cucumber, Behave, SpecFlow). El mapeo
  test↔escenario es por convención de comentarios; adoptar BDD ejecutable solo si
  el mapeo manual demuestra degradarse con el uso.
- Generación automática de .feature desde conversación.
- Instalación standalone de Engram (lo gestiona gentle-ai).
- Medición de baseline con opencode-tokenscope (Fase 0 de SETUP-STACK.md) y el
  criterio de éxito a 2 semanas que compara baseline vs. post-stack: es
  metodología de validación empírica, no parte del bootstrap del stack: quien
  quiera medirlo sigue esa fase manualmente. verify.sh valida que el stack quedó
  bien instalado, no si vale la pena.
- `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true` (Fase 2.3 de SETUP-STACK.md,
  ya marcada como opcional/experimental ahí): fuera de v1; quien lo quiera lo
  agrega a mano a su shell rc.

## 8. Fases de construcción (para Claude Code)

1. **Investigación — COMPLETADA.** Los hallazgos completos, con fuentes citadas
   y cross-checks contra los binarios reales, están en `DECISIONS.md` (incluye
   dos addenda con bugs encontrados solo por ejecutar de verdad, no por leer
   documentación). Resumen de las preguntas originales, todas resueltas:
   (a) `gentle-ai install --agent opencode --preset ... --scope=global` es
   100% no-interactivo — confirmado, es el camino primario de 4.2 paso 4;
   (b) las 10 fases SDD son init/explore/propose/spec/design/tasks/**apply**
   (esto es "implementar" — `sdd-implement` no existe)/**verify** (esto es
   "review" — `sdd-review` no existe, confirmado con el error real de
   gentle-ai)/archive/onboard — `sdd-apply` es de primera clase, sin herencia
   especial más allá de la de cualquier fase sin asignar; (c) ubicación y
   formato de archivos en 4.3; (d) `gentle-ai version`/`--version`/`-v`,
   desinstalación en 4.6; (e) `.atl/skill-registry.md` +
   `.atl/.skill-registry.cache.json` en 4.3; (f) `opencode models` en 4.3;
   (g) estrategia de merge TOML en 4.2 paso 7. Además: `rtk init -g --opencode
   --auto-patch` confirmado no-interactivo.
2. **templates/:** redactar AGENTS.md.block (sección 5, con bloques condicionales
   BDD y medición del largo) y rtk-config.toml. Es el entregable de mayor valor:
   máximo cuidado en la redacción.
3. **install.sh + stack.conf:** implementar 4.2 con --dry-run primero; probar
   dry-run antes de la ejecución real. Manejar la pausa interactiva de gentle-ai
   con mensajes claros.
4. **Tests:** (a) inserción del bloque en un AGENTS.md preexistente con contenido
   del usuario → nada se pierde, delimitadores correctos; (b) instalar dos veces →
   sin duplicación (idempotencia); (c) WITH_BDD=false → el bloque renderizado no
   contiene la sección BDD; (d) merge del TOML de rtk preserva entradas previas;
   (e) gate 1 con verificación fallando (stub que retorna error) → el bucle de
   reintento se activa y no avanza; (f) `--yes` con gate 1 necesario → falla en
   preflight sin instalar nada; (g) gate 1 con verificación pasando desde el
   inicio (stub que simula stack ya configurado) → el TUI NUNCA se invoca; (h)
   segundo backup con contenido idéntico al último → no crea archivo nuevo.
5. **verify.sh + upgrade.sh + uninstall.sh:** implementar 4.3, 4.4 y 4.6. Probar
   el ciclo completo: install → verify (PASS) → uninstall → sistema limpio →
   install de nuevo.
6. **VERIFY-AGENT.md + README.md:** redactar el prompt de humo (medir < 1.500
   tokens con la prueba BDD incluida) y el README con: instalación en 3 líneas,
   arquitectura, por qué gentle-ai es dependencia (créditos al autor), protocolo
   de upgrade, cómo funciona la capa BDD, y troubleshooting de los fallos más
   probables (opencode no en PATH, rtk equivocado de crates.io, TUI de gentle-ai
   interrumpido a la mitad).

## 9. Criterios de aceptación

- [ ] `./install.sh --dry-run` muestra el plan completo sin tocar nada
- [ ] `./install.sh` completa (incluida la pausa interactiva) en menos de 10
      minutos en una máquina Debian/Ubuntu-based limpia (WSL o nativa) con
      OpenCode
- [ ] `./verify.sh` da PASS en todos los ítems tras instalación
- [ ] Instalar dos veces seguidas no duplica bloques ni rompe la config
- [ ] Instalar en un SEGUNDO proyecto de la misma máquina (stack global ya
      configurado) NO reabre el TUI de gentle-ai ni reinstala binarios; solo
      corre los pasos por-proyecto (perfil, AGENTS.md) — verifica principio 9
- [ ] Instalar dos veces seguidas no crea backups duplicados cuando el contenido
      a respaldar no cambió
- [ ] `verify.sh` reporta WARN (no FAIL) si un modelo configurado no responde
      (simular con un modelo/proveedor inválido)
- [ ] Ningún script escribe en archivos generados por gentle-ai (auditar con grep
      sobre los scripts: cero rutas de la config SDD fuera de llamadas a la CLI
      de gentle-ai)
- [ ] El gate 1 implementa las cuatro partes (pausa, handoff, verificación
      programática, bucle de reintento); ningún gate usa "¿salió bien? [s/n]"
      como criterio de avance
- [ ] Simular TUI abortado a la mitad → el gate lo detecta y ofrece reintentar,
      no continúa con la instalación
- [ ] `--yes` con gate 1 necesario falla en el preflight con mensaje explícito,
      sin instalar nada y sin colgarse
- [ ] Un AGENTS.md preexistente del usuario sobrevive intacto fuera de los
      delimitadores
- [ ] Con WITH_BDD=false el bloque no contiene sección BDD
- [ ] `./upgrade.sh` pausa para release notes y termina corriendo verify.sh
- [ ] `./uninstall.sh` + `./verify.sh` demuestra reversión de lo propio, y las
      memorias de Engram y ${BDD_DIR}/ sobreviven por defecto
- [ ] VERIFY-AGENT.md mide menos de 1.500 tokens (con la prueba BDD incluida)
- [ ] Cero invocaciones a un agente LLM en install.sh, verify.sh, upgrade.sh y
      uninstall.sh
- [ ] Un desarrollador puede leer install.sh completo y entenderlo en 10 minutos
- [ ] El README acredita a gentle-ai/Engram (Gentleman-Programming) y a rtk como
      los proyectos sobre los que opencode-godmode se apoya