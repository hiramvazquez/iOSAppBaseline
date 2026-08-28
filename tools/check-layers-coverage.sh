#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
# check-layers-coverage.sh — control negativo de `layers.conf`
# ════════════════════════════════════════════════════════════════════
# `check-layers.sh` responde «¿alguien importa lo que no debe?».
# Este responde la pregunta que nadie hacía: **¿alguna regla dejó de mirar?**
#
# EL FALLO REAL QUE LO MOTIVA (2026-08-28, OQ-4 del PRD 0001)
# ------------------------------------------------------------
# La regla «la UI no habla HTTP» estaba escrita como glob `*/UI/*`. Al mover
# `Sources/UI/Movies/` → `Sources/Features/Movies/`, el glob dejó de casar con
# ningún archivo. La regla no falló: **dejó de existir**, en silencio, y
# `check-layers.sh` siguió imprimiendo `errors=0`. Se cazó a mano, plantando un
# `import CoreNetworking` bajo la ruta nueva y viendo que NADIE se quejaba.
#
# Una prueba de fuego manual no sobrevive a la siguiente sesión. Esto sí.
#
# CONTRATO DE EXIT CODES (AGENTS.md §14.3)
#   0 = toda regla cubre al menos un archivo
#   1 = hay reglas huérfanas → tu movimiento apagó un gate
#   3 = no pude mirar (falta el conf o no hay fuentes)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="${LAYERS_CONF:-$ROOT/tools/layers.conf}"
SRC_DIRS="${LAYERS_SRC_DIRS:-Sources Tests}"

[ -f "$CONF" ] || { echo "⚠️  check-layers-coverage: no existe $CONF"; exit 3; }

EXISTING=""
for d in $SRC_DIRS; do [ -d "$ROOT/$d" ] && EXISTING="$EXISTING $ROOT/$d"; done
[ -n "$EXISTING" ] || { echo "⚠️  check-layers-coverage: no hay fuentes que mirar"; exit 3; }

FILES="$(find $EXISTING -type f \
          \( -name '*.swift' -o -name '*.kt' -o -name '*.ts' -o -name '*.tsx' \
             -o -name '*.js' -o -name '*.jsx' -o -name '*.py' \) 2>/dev/null)"
[ -n "$FILES" ] || { echo "⚠️  check-layers-coverage: no hay archivos de código"; exit 3; }

HUERFANAS=0
TOTAL=0
PROPIAS=0
UNIVERSALES_MUDAS=0

# Solo se exige cobertura a las reglas PROPIAS del proyecto — las que hay debajo
# del marcador de abajo en `layers.conf`.
#
# El bloque universal de arriba es plantilla compartida del template: trae globs
# de otros stacks (`*/ui/*` para web, `*/domain/*` para js) y de carpetas que
# este repo puede no tener. Que no casen aquí no es un gate apagado, es una
# plantilla más ancha que este proyecto — y además esos globs los fijan tests
# del harness (ADOPTION §4.5), así que borrarlos rompería otra cosa.
#
# Lo que sí se rompe al mover una carpeta es la regla que ESTE repo escribió
# para ESTA estructura. Esas son las que tienen que casar con algo.
MARCADOR='Reglas propias'
EN_PROPIAS=0

while IFS= read -r rule; do
  case "$rule" in
    *"$MARCADOR"*) EN_PROPIAS=1; continue ;;
    ''|'#'*) continue ;;
  esac
  glob="$(printf '%s' "$rule" | awk -F' *:: *' '{print $1}')"
  msg="$(printf '%s'  "$rule" | awk -F' *:: *' '{print $3}')"
  [ -z "$glob" ] && continue
  TOTAL=$((TOTAL+1))

  if [ "$EN_PROPIAS" -eq 0 ]; then
    # Regla del bloque universal. NO bloquea, pero se CUENTA y se muestra: una
    # regla muda invisible es el problema que este script existe para evitar, y
    # eso vale también para las que decide no bloquear.
    encontrado_u=0
    while IFS= read -r file; do
      rel="./${file#"$ROOT"/}"
      # shellcheck disable=SC2254
      case "$rel" in $glob) encontrado_u=1; break ;; esac
    done <<< "$FILES"
    [ "$encontrado_u" -eq 0 ] && UNIVERSALES_MUDAS=$((UNIVERSALES_MUDAS+1))
    continue
  fi
  PROPIAS=$((PROPIAS+1))

  encontrado=0
  while IFS= read -r file; do
    rel="./${file#"$ROOT"/}"
    # shellcheck disable=SC2254
    case "$rel" in $glob) encontrado=1; break ;; esac
  done <<< "$FILES"

  if [ "$encontrado" -eq 0 ]; then
    echo "❌ regla HUÉRFANA: '$glob' no casa con ningún archivo — $msg"
    HUERFANAS=$((HUERFANAS+1))
  fi
done < "$CONF"

# EL PROPIO MODO DE FALLO DE ESTE SCRIPT (4ª pasada del design-review, 2026-08-28).
# La exención del bloque universal se hace buscando un comentario por su TEXTO.
# Si alguien lo reescribe, `EN_PROPIAS` nunca llega a 1, no se examina ninguna
# regla, y el script salía con 0 huérfanas y exit 0: verde sin haber mirado nada.
# Un gate que no corrió no puede parecer un gate que pasó (AGENTS.md §14.3), y
# eso incluye al gate que existe justo para cazar esa clase de silencio.
if [ "$PROPIAS" -eq 0 ]; then
  echo "⚠️  check-layers-coverage: no encontré el marcador '$MARCADOR' en $CONF,"
  echo "   así que no examiné NINGUNA regla. Esto no es 'todo correcto': es 'no pude mirar'."
  echo "   Si renombraste el bloque de reglas propias, actualiza MARCADOR en este script."
  exit 3
fi

echo "LAYERS_COVERAGE_SUMMARY reglas=$TOTAL propias=$PROPIAS huerfanas=$HUERFANAS universales_mudas=$UNIVERSALES_MUDAS"

# Las universales mudas se REPORTAN pero no bloquean: el conf compartido trae
# globs de otros stacks que nunca casarán aquí, y bloquear por ellos sería un
# falso positivo permanente (§14.2). Visible no es lo mismo que bloqueante —
# pero invisible sí era el problema.
if [ "$UNIVERSALES_MUDAS" -gt 0 ]; then
  echo "   ℹ️  $UNIVERSALES_MUDAS regla(s) del bloque universal no casan con nada."
  echo "      Normal si son de otro stack (web/kotlin). Revisable si son globs Swift."
fi

if [ "$HUERFANAS" -gt 0 ]; then
  cat <<'EOM'

   Una regla que no casa con ningún archivo no protege nada, y `check-layers.sh`
   seguirá diciendo errors=0 mientras tanto — un gate que no mira parece un gate
   que pasa (AGENTS.md §14.3).

   Si acabas de mover o renombrar una carpeta de Sources/, la regla viaja con la
   estructura: actualiza el glob en tools/layers.conf en ESTE commit.
   Si la regla ya no aplica, bórrala — pero bórrala a mano, no la dejes muda.
EOM
  exit 1
fi
exit 0
