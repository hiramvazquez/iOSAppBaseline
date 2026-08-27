# Guía de seguridad del repo — para el revisor del plugin `security-guidance`

> Este archivo lo lee el **revisor de seguridad de contexto fresco** del plugin
> `security-guidance` (fin de turno + por commit) como contexto adicional a su
> checklist interna. Es la versión ACCIONABLE de `AGENTS.md §6` y de
> `.agents/skills/security/SKILL.md`.
>
> ⚠️ Es **guía para un revisor, no un guardrail**. Lo que debe bloquear de forma
> determinista va en `.claude/security-patterns.yaml` (per-edit), en
> `scripts/agent-hooks/canon-enforce.sh` (Stop) o en `.gitleaks.toml` (Anillo 1).
> Una regla aquí que diga "ignora X" **no** suprime hallazgos: el archivo es aditivo.

## Modelo de amenaza de este proyecto

<!-- FILL: 3-5 líneas. ¿Qué datos manejas? ¿Quién es el atacante realista?
     ¿Qué es lo peor que puede pasar? Sin esto el revisor prioriza a ciegas.
     Ejemplo: "App móvil con datos de salud (PHI). Atacante realista: alguien con
     acceso físico al dispositivo, y un usuario legítimo intentando leer datos de
     otro. Lo peor: fuga de PHI entre cuentas." -->

## Reglas duras de este repo

1. **Cero secretos en código, logs, telemetría o mensajes de error** que lleguen al
   cliente. API keys, tokens, claves privadas y connection strings van a variables
   de entorno o al secret manager.
2. **PII/PHI solo en almacenamiento seguro de la plataforma** (Keychain / Keystore /
   cifrado). Nunca `UserDefaults`, `SharedPreferences` ni `localStorage` en claro.
3. **Autorización por recurso, no solo por ruta.** Un endpoint autenticado que no
   comprueba que el recurso pertenece al solicitante es un IDOR. Toda query
   multi-tenant filtra por el identificador de tenant/usuario.
4. **Authn/authz, cripto y validación sensible fallan cerradas:** ante error o
   duda, deniega; nunca sustituyas una decisión fallida por permisos/defaults
   permisivos. Un fallo de observabilidad se hace visible (sin el dato) y solo
   preserva la operación principal si hacerlo sigue siendo seguro. Fail-silent nunca.
5. **Toda entrada externa se valida en el servidor**, aunque ya se valide en el
   cliente. La validación de cliente es UX, no seguridad.
6. **Comparación de tokens/secretos en tiempo constante** (`timingSafeEqual` y
   equivalentes), nunca `==`.
7. **Sin dependencias no auditadas** para manejar secretos o criptografía. Revisa
   el lockfile en el mismo PR que añade la dependencia.

## Reglas específicas de este proyecto

<!-- FILL: aquí van las que solo aplican a TU dominio. Son las que más valor
     aportan porque el revisor no puede inferirlas. Ejemplos del formato:

- No loguear `customer_id` ni `account_number` en nivel INFO o superior.
- Toda ruta bajo `/admin` llama a `require_role("admin")` ANTES de cualquier
  lectura de base de datos.
- Toda tabla nueva en la DB necesita política RLS en la misma migración.
- El identificador de dispositivo nunca sale del dispositivo sin hashear.
-->

## Qué NO es un hallazgo aquí

Para mantener la señal alta (un revisor ruidoso se ignora, igual que un linter ruidoso):

- Código en `tools/`, `ci/`, `scripts/` y `tools/tests/` — es tooling interno del
  harness, no superficie de ataque de producto.
- Valores de ejemplo en `*.example`, `*.sample` y en fixtures de test claramente
  marcadas.
- Los `<!-- FILL: ... -->` del template: son placeholders, no configuración real.
