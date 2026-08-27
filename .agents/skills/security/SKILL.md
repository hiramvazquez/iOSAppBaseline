---
name: security
description: Usar al manejar secretos, credenciales, datos sensibles (PII/PHI), almacenamiento, logging, autorización o dependencias. Reglas de seguridad básicas que aplican a CUALQUIER plataforma + checklist del sub-agente security-reviewer.
when_to_use: Al tocar autenticación, autorización, secretos, criptografía, almacenamiento de datos personales, logging de datos de usuario, migraciones de base de datos o dependencias nuevas.
paths:
  - "**/auth/**"
  - "**/Auth/**"
  - "**/security/**"
  - "**/crypto/**"
  - "**/migrations/**"
  - "**/*Keychain*"
  - "**/*Credential*"
  - "**/*Token*"
---

<!-- Esta skill es el conocimiento. El ENFORCEMENT vive en tres sitios distintos,
     de más barato a más caro:
       .claude/security-patterns.yaml  → match determinista por edición (0 tokens)
       .claude/claude-security-guidance.md → contexto del revisor de modelo
       .gitleaks.toml + canon-enforce  → gates que bloquean
     Si añades una regla aquí y no la reflejas en al menos uno de esos, es prosa. -->

# Seguridad — <PROJECT>

> Skill mayormente rellenada (las reglas base son universales). Lo específico de plataforma va en
> §Por plataforma. La detección mecánica la hace `gitleaks` (Anillo 1+3); la semántica, el
> sub-agente `security-reviewer`. Esta skill es lo que el scanner NO ve.

## Las 6 reglas base (no negociables)

1. **Cero secretos en código.** API keys, tokens, claves privadas, connection strings, certificados →
   variables de entorno / secret manager. Nunca hardcoded, nunca commiteado, nunca en el bundle del cliente.
2. **Cero secretos en logs / telemetría / mensajes de error** que salgan del proceso o lleguen al cliente.
3. **Datos sensibles (PII/PHI) → almacenamiento seguro** de la plataforma (cifrado / Keychain / Keystore),
   nunca en almacenamiento en claro (UserDefaults / SharedPreferences / localStorage planos).
4. **Autorización por recurso.** Toda lectura/escritura de datos de usuario valida identidad y permiso
   (RLS / policies / checks server-side). Nunca confíes solo en el cliente.
5. **Cifrado in-transit y at-rest.** TLS para todo; cifrado at-rest verificado en la DB/almacenamiento.
6. **Dependencias auditadas.** Sin paquetes no confiables para cripto/secretos; revisa el lockfile en cada PR.

## Manejo de errores en paths sensibles

- **Fail-closed** en authz/cripto: ante duda, denegar. **Loguea la señal, nunca el dato** ("auth falló para user X", no el token).
- No tragues silenciosamente errores de seguridad (fail-silent oculta brechas).

## Checklist del `security-reviewer` (qué revisa por PR)

- [ ] ¿Hay literales que parezcan secretos? (incluso "de prueba" con formato real)
- [ ] ¿Algún secreto/token/PII llega a un log, analytics, o crash report?
- [ ] ¿Datos sensibles van a almacenamiento inseguro?
- [ ] ¿Endpoints/queries nuevos tienen authz por fila/recurso?
- [ ] ¿Input externo se valida/sanitiza? (inyección, XSS, deserialización)
- [ ] ¿Se añadió una dependencia que toca cripto/secretos sin auditar?
- [ ] ¿`.gitignore` cubre los archivos de secretos nuevos?
- [ ] **Trifecta letal (agentes y MCP):** ¿este cambio le da a un agente las TRES a la vez?

### La trifecta letal — el riesgo no está en las tools, está en su combinación

Vocabulario de riesgo del equipo de MCP, y la razón por la que auditar tools de una en una no
sirve: ninguna de estas tres capacidades es peligrosa por separado, y juntas son exfiltración.

1. **Acceso a datos privados** (tu repo, tu DB, el Keychain, variables de entorno).
2. **Exposición a contenido no confiable** (una página web, un issue de GitHub, un PDF, la
   respuesta de una API, el output de otra herramienta) — cualquier texto que un tercero
   controla y que el agente va a leer.
3. **Capacidad de comunicar hacia fuera** (una petición HTTP, `git push`, enviar un mensaje,
   escribir en un recurso compartido).

Con las tres, una instrucción escondida en (2) puede hacer que el agente lea (1) y lo mande por
(3), sin que ninguna tool haya hecho nada que su descripción no permitiera. Es prompt injection
convertida en canal de salida.

**Cómo se revisa en la práctica:** al añadir un MCP, una tool o un permiso, pregunta cuál de los
tres vértices añade y si el agente ya tenía los otros dos. **Romper un vértice basta** y casi
siempre el más barato es el tercero: red restringida por allowlist, `git push` en `ask`,
sin credenciales de escritura en el entorno del agente. Cuando no puedas romper ninguno, que la
acción sea la que pida aprobación humana — y que quede auditada.

> En este harness: el Anillo 0 ya pone `git push` y los publish en `ask`, y deniega la lectura
> de `.env`/secretos. Eso rompe (1) y (3) parcialmente **por defecto**. Lo que introduce riesgo
> nuevo es casi siempre un MCP añadido sin pensar en el vértice (2).

## §Por plataforma

<!-- FILL: completa lo de TU stack. Opiniones por defecto: -->
- **iOS:** secretos/sesión → Keychain. Archivos sensibles → `NSFileProtection`. App Lock biométrico opcional.
- **Android:** `EncryptedSharedPreferences` / Keystore; `EncryptedFile`. Sin claves en `strings.xml` ni en el APK.
- **Web:** sesión en cookies `httpOnly`+`Secure`, no `localStorage`. Secretos solo server-side, nunca en `NEXT_PUBLIC_*`/bundle. CSP + sanitización.
- **Backend/DB:** RLS/policies activas; service-role keys solo server-side; rota credenciales expuestas de inmediato.

## Si encuentras un secreto ya commiteado

1. **Rótalo YA** (asume comprometido). 2. Quítalo del código + añade a `.gitignore`.
3. Considera limpiar historial (`git filter-repo`) si era válido. 4. Registra en el ledger (`tools/findings/`).
