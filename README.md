# fledge-plugin-attest

🔏 Run [`attest`](https://github.com/CorvidLabs/attest) — a signed provenance ledger for code changes — as a first-class `fledge attest` command.

A plugin for [fledge](https://github.com/CorvidLabs/fledge).

It records *who or what reviewed a change and at what confidence*, keyed to git commit SHAs and stored portably in git notes (`refs/notes/attest`), so the trust record travels with the repository across every git host. Signing is optional — an unsigned attestation is still a valid record — so the plugin works with zero setup. A policy in `.attest.json` lets CI and agent loops gate on the recorded trust.

This plugin links [`AttestKit`](https://github.com/CorvidLabs/attest) directly, so it is **self-contained**: there is no separate `attest` binary to install. It drives the same engine types the upstream CLI uses, so behaviour and storage are identical.

> **macOS-only.** `attest`/`AttestKit` target macOS 13+, so this plugin does too — no Linux/Windows support.
>
> **Private access.** Both this plugin and `attest` are private CorvidLabs repos. Building requires git/GitHub credentials with read access to `github.com/CorvidLabs/attest` (Swift Package Manager resolves it transitively, pinned to the `0.1.0` release).

## Install

```bash
fledge plugins install CorvidLabs/fledge-plugin-attest
```

## Usage

```bash
# Record an attestation on HEAD (unsigned, zero setup)
fledge attest sign --reviewer agent:claude --confidence 0.9 --verdict proceed

# Record that a human approved a change, and sign it
fledge attest sign --reviewer human:leif --human-approved --sign

# Pipe an augur verdict straight in (auto-fills verdict + confidence)
augur check --json | fledge attest sign --reviewer agent:claude --from-augur -

# Gate a range against .attest.json — exits non-zero on any violation (CI / agents)
fledge attest verify --range main..HEAD

# List the recorded ledger (add --json for machine output)
fledge attest log

# Emit a single stable JSON audit document for a range
fledge attest export --range main..HEAD --policy .attest.json
```

### Subcommands

| Command | Purpose |
|---------|---------|
| `sign`   | Record an attestation for a commit, written to git notes. |
| `verify` | Exit non-zero if any commit in a range violates policy (CI / agent gating). |
| `log`    | List recorded attestations, human-readable or JSON. |
| `export` | Emit the complete provenance trail across a range as one stable JSON audit document. |

Signing uses the key from `attest keygen` (`~/.config/attest/key`). Generate one with the upstream `attest` CLI if you want signed attestations; unsigned attestations need no key.

Git notes are not pushed by default — share the ledger with `git push origin "refs/notes/*"`.

## License

MIT
