---
id: CHG-0002-refresh-locked-attest-1-0-dependency
state: implementing
type: migration
base_commit: afff3043714fb5e66bf2ca1fc3780a97c0262d19
---

# Refresh locked Attest 1.0 dependency

## Intent

Refresh locked Attest 1.0 dependency

## Affected Canonical Specs

- None

## Acceptance Criteria

- The locked dependency resolves to the declared stable 1.0 release and the native verify lane passes

## No-spec Rationale

Refresh the lockfile to the already-declared stable 1.0 component without changing plugin behavior.
