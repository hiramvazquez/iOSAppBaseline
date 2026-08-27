---
paths:
  - "**/Data/**"
  - "**/*Repository*.swift"
  - "**/*Keychain*.swift"
  - "**/*Auth*.swift"
---

# Regla path-scoped: datos / seguridad

> Se carga al tocar la capa de datos, repos, Keychain o auth. Espejo de `AGENTS.md` §6.

Antes de editar: `.agents/skills/security/SKILL.md`.

- **Secretos** → Keychain / env / secret manager; nunca hardcoded, nunca en logs/telemetría/errores al cliente.
- **Datos sensibles (PII/PHI)** → almacenamiento seguro (Keychain / `NSFileProtection`), nunca en claro (UserDefaults).
- **Authz por recurso** en toda lectura/escritura de datos de usuario; no confíes solo en el cliente.
- Fail-closed en authz/cripto; loguea la señal, nunca el dato.
