# PLAN-WINDOWS.md — planificando la compatibilidad con Windows

> Este documento NO es un spec de construcción como `PLAN.md`. Es un
> documento de planificación previa: plantea el problema, opciones con
> tradeoffs, y preguntas abiertas a investigar antes de que valga la pena
> escribir un plan de construcción ejecutable. No hay una decisión tomada
> todavía — eso lo define quien lea esto.

## 1. Contexto

`PLAN.md` (principio 7) deja a Windows nativo, macOS y distros Linux sin
`apt` explícitamente fuera de v1: el target es exclusivamente Debian/Ubuntu-
based, WSL o nativo. Eso significa que, hoy, un usuario de Windows tiene que:

1. Instalar manualmente una distro WSL Ubuntu/Debian.
2. Entrar a esa distro.
3. Clonar/copiar opencode-godmode ahí adentro.
4. Correr `install.sh` desde dentro de WSL.

No hay ningún punto de entrada desde PowerShell/cmd — el usuario tiene que
saber que WSL existe y saber usarlo. Este documento explora si vale la pena
bajar esa fricción, y cómo.

Nota importante: esto **ya funciona hoy** exactamente como está — el
`install.sh` actual se construyó y probó de punta a punta en un WSL Ubuntu
26.04 real (ver `DECISIONS.md`), incluyendo el ciclo completo
install→verify→uninstall→reinstall. El problema a resolver acá no es "¿corre
en Windows?" (ya corre, adentro de WSL), es "¿qué tan fácil es llegar ahí?".

## 2. Opciones a evaluar

### Opción A — Solo documentación

Agregar al README instrucciones claras: instalar WSL con una distro
Debian/Ubuntu-based, entrar, clonar el repo ahí, correr `install.sh` sin
modificaciones.

- **Esfuerzo:** ~cero. No hay cambios de código.
- **Riesgo:** ninguno — es exactamente lo que ya se probó.
- **Contra:** el usuario sigue teniendo que saber/aprender WSL por su cuenta.

### Opción B — Wrapper PowerShell fino sobre WSL

Un `install.ps1` (o `.cmd`) en la raíz que:

1. Detecta si existe una distro WSL Debian/Ubuntu-based utilizable; si no,
   la crea (`wsl --install -d Ubuntu`).
2. Traduce la ruta del repo a su equivalente WSL (`wslpath`).
3. Delega TODO el trabajo real al `install.sh` existente, corriendo adentro
   de esa distro: `wsl -d <distro> -- bash -c "cd $(wslpath ...) &&
   ./install.sh $args"`.

`install.sh` no cambia — sigue siendo la única fuente de verdad del
comportamiento real. El wrapper es puramente un punto de entrada.

- **Esfuerzo:** bajo/medio. Reutiliza el 100% de lo ya construido y probado.
- **Complejidad conocida a manejar** (ya la pisamos construyendo este mismo
  proyecto, así que están documentadas, no son hipotéticas):
  - Mapeo de rutas Windows↔WSL (`wslpath -u`/`wslpath -w`).
  - Detectar la distro Debian/Ubuntu-based default vs. crear una nueva —
    en esta máquina, por ejemplo, la distro WSL default resultó ser
    `docker-desktop`, no una distro Ubuntu utilizable; el wrapper necesita
    lógica explícita para no asumir "la default sirve".
  - Bit de ejecutable: un checkout de este repo en Windows con
    `core.fileMode=false` (el default común en Windows) pierde el `+x` de
    los `.sh` — ya lo pisamos en este build (`git update-index --chmod=+x`
    lo arregla en el repo; el wrapper debería además correr un `chmod +x`
    defensivo antes de invocar, por si el usuario clona con otra
    configuración de git).
  - Passthrough de flags (`--dry-run`, `--yes`) y de exit code, para que el
    wrapper se sienta como una llamada directa, no una capa aparte.
- **Contra:** un archivo más para mantener, aunque delgado.

### Opción C — Nativo, sin WSL

Reescribir la lógica central para PowerShell puro: `apt` → `winget`/`choco`,
rutas `~/.config/...` → sus equivalentes de Windows (`%APPDATA%`,
`%LOCALAPPDATA%`), sin depender de WSL en absoluto.

- **Esfuerzo:** alto. En la práctica es un proyecto hermano nuevo (mismo
  propósito, implementación completamente distinta), no una extensión de
  `install.sh`.
- **Riesgo:** cada dependencia (gentle-ai, rtk, Engram) tendría que tener
  build nativo de Windows Y su instalador tendría que soportar el flujo
  no-interactivo igual de bien que en Linux — nada de esto está confirmado
  todavía (ver preguntas abiertas).
- **Contra:** duplica mantenimiento — dos implementaciones del mismo
  comportamiento (Linux/WSL y Windows nativo) que pueden divergir con el
  tiempo.

## 3. Preguntas abiertas (bloquean escribir un plan ejecutable)

Antes de poder convertir cualquiera de estas opciones (sobre todo B o C) en
un plan de construcción con fases concretas, hace falta resolver:

- ¿gentle-ai y rtk publican binarios nativos de Windows, o solo Linux/macOS?
  (OpenCode sí tiene instalador Windows nativo — confirmado en este build,
  `opencode.ai/install` sirve un script que detecta la plataforma; gentle-ai
  y rtk no se investigaron para Windows en este build, solo para Linux.)
- Los scripts de instalación oficiales de gentle-ai/rtk son bash — ¿corren
  bajo Git Bash en Windows sin WSL, o dependen de utilidades que solo existen
  en un entorno Linux real?
- ¿Engram tiene build nativo de Windows?
- ¿Qué tan confiable es `wsl --install -d Ubuntu` sin intervención manual en
  Windows 10 vs. Windows 11 — funciona siempre en un solo comando, o hay
  casos (virtualización deshabilitada en BIOS, versión de Windows vieja,
  etc.) que necesitan guiar al usuario a mano?
- Pregunta de producto, no técnica: ¿cuántos usuarios reales de este stack
  están en Windows vs. macOS/Linux nativo? Determina si vale la pena el
  esfuerzo de B, y mucho más el de C.

## 4. Recomendación tentativa

**Opción B** tiene la mejor relación esfuerzo/beneficio: un wrapper delgado
que reutiliza `install.sh` tal cual — cero riesgo de que la lógica diverja
entre plataformas, porque solo hay una implementación real. WSL Ubuntu ya
demostró funcionar perfecto para este propósito en este mismo build (todo
el ciclo install→verify→uninstall→reinstall se probó ahí).

**Opción C** probablemente no se justifica mientras WSL siga siendo gratis y
venga integrado en Windows 10/11 — el esfuerzo de mantener dos
implementaciones paralelas es alto para un beneficio que la opción B ya
cubre razonablemente bien.

**Opción A** (solo documentación) es el paso mínimo si no hay apetito para
ni siquiera el esfuerzo bajo de B — y es compatible con hacer B más
adelante, no son mutuamente excluyentes.

## 5. Próximos pasos sugeridos

Si se decide seguir con esto:

1. Fase de investigación acotada (mismo espíritu que la sección 8.1 original
   de `PLAN.md`) para responder las preguntas abiertas de la sección 3 —
   especialmente si gentle-ai/rtk/Engram tienen binarios de Windows, porque
   eso es lo que realmente decide entre B y C.
2. Recién con esas respuestas, escribir un plan de construcción ejecutable
   (formato `PLAN.md`: principios, arquitectura, fases, criterios de
   aceptación) para la opción elegida.
3. No implementar nada de esto todavía — este documento es solo el punto de
   partida para esa decisión.
