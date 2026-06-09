@preconcurrency import Foundation
import ArgumentParser
import AttestKit

// MARK: - Root command

/// `fledge attest` — a thin fledge front end over `AttestKit`, the signed
/// provenance ledger engine that backs the `attest` CLI.
///
/// This plugin links `AttestKit` directly, so it is self-contained: it needs no
/// separately installed `attest` binary. It exposes the most useful subset of
/// attest's surface — `sign`, `verify`, `log`, and `export` — driving the same
/// engine types (`Attest`, `NotesStore`, `Verifier`, `Exporter`, `Policy`) that
/// the upstream CLI uses, so behaviour and storage stay identical.
@main
struct FledgeAttestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fledge-attest",
        abstract: "🔏 Record and verify signed provenance attestations on git commits, via fledge.",
        discussion: """
        attest records signed attestations keyed to git commit SHAs and stores them \
        portably in git notes (refs/notes/attest), so the trust record travels with the \
        repository across every git host. Signing is optional — an unsigned attestation \
        is still a valid record — so the plugin works with zero setup. A policy in \
        `.attest.json` lets CI and agent loops gate on the recorded trust.
        """,
        version: "0.1.0",
        subcommands: [Sign.self, Verify.self, Log.self, Export.self],
        defaultSubcommand: Log.self
    )
}

// MARK: - Shared options

/// Options shared by every subcommand: the repository path and a validated store.
struct RepoOptions: ParsableArguments {
    @Option(name: [.long, .customShort("C")], help: "Path to the repository.")
    var path: String = "."

    /// Builds a `NotesStore` for `path`, validating that it is a git work tree.
    func makeStore() throws -> NotesStore {
        let store = NotesStore(path: path)
        try store.validate()
        return store
    }
}

// MARK: - sign

/// Records an attestation for a commit, written to git notes.
struct Sign: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Record an attestation for a commit, written to git notes."
    )

    @OptionGroup var repo: RepoOptions

    @Option(name: .long, help: "The commit to attest (SHA or revision, e.g. HEAD).")
    var commit: String = "HEAD"

    @Option(name: .long, help: "Who or what reviewed, e.g. 'agent:claude' or 'human:leif'.")
    var reviewer: String

    @Option(name: .long, help: "Reviewer confidence, 0...1.")
    var confidence: Double?

    @Option(name: .long, help: "Recorded verdict: proceed, review, or block.")
    var verdict: String?

    @Flag(name: .long, help: "Record that the change's tests passed.")
    var testsPassed = false

    @Flag(name: .long, help: "Record that a human approved the change.")
    var humanApproved = false

    @Option(name: .long, help: "An optional free-text note.")
    var note: String?

    @Option(name: .long, help: "Read augur JSON (verdict + riskScore) from a file or '-' for stdin.")
    var fromAugur: String?

    @Flag(name: .long, help: "Sign the attestation with the key from `attest keygen`.")
    var sign = false

    @Flag(name: .long, help: "Emit the stored attestation as JSON.")
    var json = false

    func run() async throws {
        let store = try repo.makeStore()
        let sha = try store.resolve(revision: commit)

        var resolvedVerdict: Verdict? = verdict.flatMap(Verdict.init(rawValue:))
        if let verdict, resolvedVerdict == nil {
            throw ValidationError("verdict must be one of: proceed, review, block (got '\(verdict)')")
        }
        var resolvedConfidence = confidence

        // Merge augur JSON when requested; explicit flags take precedence.
        if let source = fromAugur {
            let augur = try Self.readAugur(source)
            if resolvedVerdict == nil { resolvedVerdict = augur.verdict }
            if resolvedConfidence == nil { resolvedConfidence = augur.confidence }
        }

        // A bare `--human-approved` is itself the confidence signal: default it to full.
        if resolvedConfidence == nil, humanApproved {
            resolvedConfidence = 1.0
        }

        guard let finalConfidence = resolvedConfidence else {
            throw ValidationError(
                "provide --confidence, --human-approved, or --from-augur to supply a confidence value"
            )
        }

        let attestation = Attestation(
            commit: sha,
            reviewer: reviewer,
            confidence: finalConfidence,
            verdict: resolvedVerdict,
            testsPassed: testsPassed,
            humanApproved: humanApproved,
            timestamp: Int(Date().timeIntervalSince1970),
            note: note
        )

        var signer: Ed25519Signer?
        if sign {
            signer = try KeyStore().load()
        }

        let attest = Attest(store: store)
        let stored = try attest.record(attestation, signer: signer)

        if json {
            print(try stored.jsonString())
        } else {
            let signedNote = stored.isSigned ? " (signed)" : ""
            print("attest · recorded \(reviewer) on \(String(sha.prefix(10)))\(signedNote)")
        }
    }

    /// Reads augur JSON from a file path or stdin (`-`).
    private static func readAugur(_ source: String) throws -> AugurVerdict {
        let raw: String
        if source == "-" {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            raw = String(decoding: data, as: UTF8.self)
        } else {
            raw = try String(contentsOfFile: source, encoding: .utf8)
        }
        return try AugurVerdict.parse(raw)
    }
}

// MARK: - verify

/// Exits non-zero if any commit in a range violates policy (for CI / agent gating).
struct Verify: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Exit non-zero if any commit in a range violates policy (for CI / agent gating)."
    )

    @OptionGroup var repo: RepoOptions

    @Option(name: .long, help: "A git range to check, e.g. 'main..HEAD'.")
    var range: String?

    @Option(name: .long, help: "Check a single commit (SHA or revision). Defaults to HEAD.")
    var commit: String?

    @Option(name: .long, help: "Path to the policy file.")
    var policy: String = ".attest.json"

    @Flag(name: .long, help: "Emit machine-readable JSON.")
    var json = false

    func run() async throws {
        let store = try repo.makeStore()

        let commits: [String]
        if let range {
            commits = try store.commits(inRange: range)
        } else if let commit {
            commits = [try store.resolve(revision: commit)]
        } else {
            commits = [try store.resolve(revision: "HEAD")]
        }

        let loadedPolicy: Policy
        if FileManager.default.fileExists(atPath: policy) {
            loadedPolicy = try Policy.load(fromFile: policy)
        } else {
            loadedPolicy = .default
        }

        let attest = Attest(store: store)
        let result = try attest.verify(commits: commits, policy: loadedPolicy)

        if json {
            print(try result.jsonString())
        } else {
            print(Reporter.renderVerification(result))
        }

        if !result.passed {
            throw ExitCode(1)
        }
    }
}

// MARK: - log

/// Lists recorded attestations, human-readable or JSON.
struct Log: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "List recorded attestations, human-readable or JSON."
    )

    @OptionGroup var repo: RepoOptions

    @Option(name: .long, help: "Limit to a git range, e.g. 'main..HEAD'.")
    var range: String?

    @Option(name: .long, help: "Limit to a single commit (SHA or revision).")
    var commit: String?

    @Flag(name: .long, help: "Emit machine-readable JSON.")
    var json = false

    func run() async throws {
        let store = try repo.makeStore()

        let commits: [String]
        if let commit {
            commits = [try store.resolve(revision: commit)]
        } else if let range {
            commits = try store.commits(inRange: range).reversed()
        } else {
            commits = try store.attestedCommits()
        }

        let groups: [(commit: String, attestations: [Attestation])] = try commits.compactMap { sha in
            let attestations = try store.attestations(for: sha)
            return attestations.isEmpty ? nil : (commit: sha, attestations: attestations)
        }

        if json {
            print(try Self.renderJSON(groups))
        } else {
            print(Reporter.renderLog(groups))
        }
    }

    /// Encodes the grouped attestations as stable JSON.
    private static func renderJSON(_ groups: [(commit: String, attestations: [Attestation])]) throws -> String {
        let entries = groups.map { LogEntry(commit: $0.commit, attestations: $0.attestations) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(entries), as: UTF8.self)
    }

    private struct LogEntry: Encodable {
        let commit: String
        let attestations: [Attestation]
    }
}

// MARK: - export

/// Emits the complete provenance trail across a range as one stable JSON audit document.
struct Export: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Emit the complete provenance trail across a range as one stable JSON audit document."
    )

    @OptionGroup var repo: RepoOptions

    @Option(name: .long, help: "A git range to export, e.g. 'main..HEAD'.")
    var range: String?

    @Option(name: .long, help: "Export a single commit (SHA or revision).")
    var commit: String?

    @Option(name: .long, help: "Optional policy file; when set, each commit's pass/fail is included.")
    var policy: String?

    @Flag(name: .long, inversion: .prefixedNo, help: "Pretty-print the JSON (default: on).")
    var pretty = true

    func run() async throws {
        let store = try repo.makeStore()

        let commits: [String]
        if let commit {
            commits = [try store.resolve(revision: commit)]
        } else if let range {
            commits = try store.commits(inRange: range)
        } else {
            commits = try store.attestedCommits()
        }

        var loadedPolicy: Policy?
        if let policy {
            loadedPolicy = try Policy.load(fromFile: policy)
        }

        let report = try Exporter(store: store).report(commits: commits, policy: loadedPolicy)
        print(try report.jsonString(pretty: pretty))
    }
}
