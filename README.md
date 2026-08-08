# opencode-godmode

Bootstrap reproducible del stack de optimización de tokens para
[OpenCode](https://opencode.ai): workflow Spec-Driven Development con
subagentes y memoria persistente (vía **gentle-ai** + **Engram**), compresión
de output de bash (**rtk**), asignación de modelos por fase, y una capa de
trazabilidad BDD (Gherkin → diseño → test → review) propia de este proyecto.
Todo corre en bash puro — el agente no gasta contexto instalando su propio
stack.

## Instalación

```bash
git clone <este-repo>
cd tu-proyecto            # el proyecto que querés configurar
/ruta/a/opencode-godmode/install.sh
```

Sin `stack.conf`, `install.sh` te lo genera preguntando (modelos, perfil,
BDD). Con `--dry-run` mostrás todo el plan sin tocar nada; con `--yes`
corrés no-interactivo (requiere `stack.conf` ya presente).

## Arquitectura

```
install.sh              # instala/configura todo — idempotente
verify.sh                # checklist PASS/WARN/FAIL sin agente
upgrade.sh                # protocolo de actualización segura
uninstall.sh               # revierte lo que install.sh agregó
stack.conf(.example)        # tu configuración: modelos, flags
templates/
  AGENTS.md.block             # bloque que se inserta en el AGENTS.md del proyecto
  rtk-config.toml              # config de rtk: exclusiones + tee en fallos
VERIFY-AGENT.md               # smoke test para pegar en OpenCode (<1500 tokens)
DECISIONS.md                   # decisiones tomadas durante la construcción
```

**gentle-ai, Engram y rtk son globales a la máquina** (se instalan una vez);
el perfil SDD, el bloque de `AGENTS.md` y `BDD_DIR` son por-proyecto. Correr
`install.sh` en un segundo proyecto de la misma máquina no reinstala nada
global, solo configura lo que es de ese proyecto.

## Por qué gentle-ai y rtk

Este proyecto no reimplementa un orquestador SDD ni un compresor de output:
se apoya en herramientas que ya lo hacen bien.

- **[gentle-ai](https://github.com/Gentleman-Programming/gentle-ai)** (de
  [Gentleman-Programming](https://github.com/Gentleman-Programming)) provee
  los agentes SDD, el orquestador, los perfiles por fase y gestiona
  **Engram** (memoria persistente). opencode-godmode nunca edita los
  archivos que gentle-ai genera — todo pasa por su CLI.
- **[rtk](https://github.com/rtk-ai/rtk)** comprime el output de bash antes
  de que llegue al contexto del agente.

Actualizaciones de prompts/agentes llegan vía `gentle-ai upgrade`, no vía
templates propios de este repo — es una decisión deliberada (ver
`DECISIONS.md`).

## Capa BDD (el aporte propio de este proyecto)

Los `.feature` bajo `BDD_DIR` (default `features/`) son artefactos
**humanos** — los agentes los consumen pero nunca los crean ni editan. Con
`WITH_BDD=true`, el bloque de `AGENTS.md` agrega reglas para que el flujo
SDD los use como fuente de verdad:

- Al iniciar una tarea, el agente carga solo los escenarios pertinentes y
  los cita por `archivo.feature / Escenario: nombre`.
- La spec de diseño incluye una tabla de trazabilidad
  escenario → decisión → criterio de aceptación.
- Cada test que cubre un escenario lleva `# Cubre: archivo/escenario`; el
  review rechaza si hay escenarios en alcance sin test que pase.

No hay integración con frameworks BDD ejecutables (Cucumber, Behave): el
mapeo test↔escenario es por convención de comentarios.

## Protocolo de upgrade

`./upgrade.sh` te muestra la versión instalada y actual de gentle-ai, te
pausa para que leas las release notes, corre `gentle-ai upgrade` (que hace
su propio backup automático antes de tocar nada), actualiza rtk, re-aplica
el bloque de `AGENTS.md` por si cambió de formato, y corre `verify.sh` al
final. Si algo se comporta raro después, `gentle-ai restore` te deja elegir
un backup para volver atrás.

## Fuera de alcance

- Windows nativo, macOS, y distros Linux sin `apt` — v1 es exclusivamente
  Debian/Ubuntu-based (WSL o nativo).
- Templates propios de agentes SDD — se depende de gentle-ai y sus updates.
- Frameworks BDD ejecutables (Cucumber, Behave, SpecFlow).
- Generación automática de `.feature` desde la conversación.
- Instalación standalone de Engram (la gestiona gentle-ai).
- Medición de baseline de tokens (metodología de validación empírica, no
  parte del bootstrap — `verify.sh` confirma que el stack quedó bien
  instalado, no si vale la pena).
- `OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS` — quien lo quiera lo agrega a
  mano a su shell rc.

## Troubleshooting

**"OpenCode no está en PATH"** — no se instala vía `apt`. Corré
`curl -fsSL https://opencode.ai/install | bash` y abrí una terminal nueva
(el instalador agrega el PATH a tu `.bashrc`, que solo se lee en shells
interactivos).

**`rtk gain` falla / "wrong package"** — existe otro proyecto llamado `rtk`
("Rust Type Kit") en crates.io. Si en algún momento corriste
`cargo install rtk` a secas, tenés el paquete equivocado. Reinstalá con el
script oficial (el que usa `install.sh`) o `cargo install --git
https://github.com/rtk-ai/rtk`.

**El instalador de gentle-ai abre un TUI en vez de correr solo** — las
versiones recientes de gentle-ai soportan `gentle-ai install --agent
opencode ...` de forma 100% no-interactiva, que es lo que usa `install.sh`
por defecto. Si tu versión de gentle-ai no trae esos flags todavía,
`install.sh` cae automáticamente a un gate interactivo: te pausa, abre el
TUI, y **verifica programáticamente** que quedó bien configurado antes de
seguir — si el TUI se cierra a la mitad o elegís mal, te ofrece reintentar
en vez de continuar con una instalación rota.

**gentle-ai/rtk "ya estaban instalados" pero `install.sh` los reinstala
igual** — gentle-ai y rtk dejan sus binarios en `~/.local/bin` sin tocar tu
`.bashrc`. `install.sh` ya agrega ese directorio al PATH por su cuenta al
arrancar, así que esto no debería pasar; si pasa, revisá que
`~/.local/bin` no esté siendo limpiado por otra herramienta.

**Un modelo configurado no responde en `verify.sh`** — es un `WARN`, no un
`FAIL`. Revisá que el proveedor esté autenticado (`opencode models
--refresh` refresca la lista contra el proveedor real).

## Créditos

opencode-godmode es una capa fina sobre el trabajo de
[Gentleman-Programming](https://github.com/Gentleman-Programming)
(gentle-ai, Engram) y el equipo de [rtk](https://github.com/rtk-ai/rtk). El
valor agregado propio de este repo es el bootstrap reproducible y la capa
BDD — todo lo demás son sus proyectos.
