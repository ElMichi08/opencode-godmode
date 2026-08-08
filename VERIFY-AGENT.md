# VERIFY-AGENT.md — smoke test de opencode-godmode

Pegá esto en OpenCode después de reiniciarlo, dentro del proyecto donde
corriste `./install.sh`. Reemplazá `<PROFILE_NAME>` y `<BDD_DIR>` por los
valores reales de tu `stack.conf` (los mostró el resumen final de
install.sh).

Para CADA paso respondé en una línea: `PASO N: OK` o `PASO N: FALLA — <por
qué>`. No repitas estas instrucciones, no expliques de más.

---

**Paso 1 — perfil y orquestador.** Confirmá (sin ejecutar nada) que ves el
agente `gentle-orchestrator` y que el perfil `<PROFILE_NAME>` existe entre
los perfiles disponibles.

**Paso 2 — rtk.** Corré `git status` con la tool bash. Confirmá que el
output que ves está comprimido (no un diff completo pegado). Después corré
`rtk gain --history` y confirmá que aparece una entrada reciente para ese
comando.

**Paso 3 — Engram.** Guardá una memoria de prueba (`mem_save`) con
contenido "smoke test opencode-godmode VERIFY-AGENT". Buscala con
`mem_search`. Borrala. Confirmá que los tres pasos funcionaron.

**Paso 4 — subagente de exploración.** Lanzá el subagente de exploración
con una pregunta trivial sobre este repo (ej: "¿qué archivos hay en la
raíz?"). Confirmá que el reporte sigue el formato comprimido del bloque de
AGENTS.md: fragmentos, sin saludos, una línea por hallazgo con
`path:línea`, cierre `ABIERTO:`.

**Paso 5 — estilo del orquestador.** Respondé vos, como orquestador, una
pregunta explicativa simple sobre el repo (ej: "¿qué hace este proyecto?").
Confirmá que tu respuesta usa el estilo explicativo normal de gentle-ai —
NO el formato comprimido del Paso 4 (esas reglas son solo para subagentes
de exploración/implementación, no para vos).

**Paso 6 — BDD** (solo si tu proyecto tiene `WITH_BDD=true`). Creá
`<BDD_DIR>/smoke.feature` con exactamente:

```gherkin
Feature: smoke
  Scenario: trivial
    Given nothing
```

Pedí una tarea trivial relacionada (ej: "implementá un noop para este
escenario"). Confirmá que el plan cita el escenario por `smoke.feature /
Escenario: trivial`. Borrá el archivo al terminar.

---

Al final reportá `RESUMEN: X/Y pasos OK` (Y=5 si WITH_BDD=false, Y=6 si
WITH_BDD=true) y listá cualquier FALLA con una línea de causa probable.
