import AppKit
import CryptoKit
import Security

// MARK: - Errors

/// An update step failed; `text` is ready to show to the user.
struct UpdateError: Error, Sendable {
    let text: String
    init(_ text: String) { self.text = text }
}

// MARK: - GitHub release

/// The parts of a GitHub release (`/repos/<slug>/releases/latest`) the updaters need.
struct GitHubRelease {
    /// Tag without a leading `v`, for example `26.10.4`.
    let version: String
    /// Release text (Markdown) with surrounding whitespace removed.
    let notes: String
    private let assets: [[String: Any]]

    /// Parses the JSON object of a release. Throws when the tag is not a plain version number.
    init(json: [String: Any]) throws {
        let tag = String((json["tag_name"] as? String ?? "").drop(while: { $0 == "v" || $0 == "V" }))
        guard tag.range(of: #"^[0-9]+(\.[0-9]+){0,3}$"#, options: .regularExpression) != nil else {
            throw UpdateError(L("Ungültige Versionsnummer", "Invalid version number"))
        }
        version = tag
        notes = (json["body"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        assets = json["assets"] as? [[String: Any]] ?? []
    }

    /// Direct download link (`browser_download_url`) of an asset; only https on github.com.
    func downloadURL(_ name: String) -> URL? {
        guard let s = asset(name)?["browser_download_url"] as? String, let u = URL(string: s),
              u.scheme == "https", u.host == "github.com" else { return nil }
        return u
    }

    /// API link (`url`) of an asset for downloads with `Accept: application/octet-stream`, optionally
    /// with a token for private repositories; only https on api.github.com.
    func apiURL(_ name: String) -> URL? {
        guard let s = asset(name)?["url"] as? String, let u = URL(string: s),
              u.scheme == "https", u.host == "api.github.com" else { return nil }
        return u
    }

    private func asset(_ name: String) -> [String: Any]? {
        assets.first { $0["name"] as? String == name }
    }
}

// MARK: - Update core

/// The steps every updater shares: finding the latest release, downloading, verifying (checksum,
/// Ed25519, bundle ID, version, code signature) and swapping the app. Everything app specific
/// (repository, app name, bundle ID, public key, texts around it) comes in as a parameter.
enum UpdateCore {

    // MARK: Versions

    /// Compares version numbers part by part, so `26.10.10` is newer than `26.10.9` and `1.7` equals `1.7.0`.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    // MARK: GitHub

    /// GET `/repos/<repo>/releases/latest`, never from the cache. The caller inspects the status code
    /// (200, 401, 403/429, 404) because the apps word those cases differently.
    static func fetchLatestRelease(repo: String, userAgent: String, token: String? = nil) async throws -> (Data, HTTPURLResponse?) {
        var req = apiRequest(URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!, userAgent: userAgent, token: token)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await URLSession.shared.data(for: req)
        return (data, resp as? HTTPURLResponse)
    }

    /// Downloads a release asset (direct link or API link). A token is sent to api.github.com only;
    /// GitHub redirects asset downloads to a signed storage link where the token must not go.
    static func download(_ url: URL, userAgent: String, token: String? = nil) async throws -> Data {
        var req = apiRequest(url, userAgent: userAgent, token: token)
        req.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 120
        let (data, resp) = try await URLSession.shared.data(for: req, delegate: StripAuthOnRedirect())
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError(L("Download fehlgeschlagen", "Download failed")) }
        return data
    }

    private static func apiRequest(_ url: URL, userAgent: String, token: String?) -> URLRequest {
        var r = URLRequest(url: url, timeoutInterval: 20)
        if let token { r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        r.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return r
    }

    // MARK: Verification

    /// `sha256Text` is the content of a `.sha256` file (`<hex>  <name>`), as written by `shasum -a 256`.
    static func verifyChecksum(_ data: Data, sha256Text: String) throws {
        let expected = sha256Text.split(whereSeparator: \.isWhitespace).first.map(String.init)?.lowercased() ?? ""
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard expected.count == 64, expected == actual else { throw UpdateError(L("Prüfsumme stimmt nicht", "Checksum does not match")) }
    }

    /// `signatureText` is the Base64 signature from the `.sig` asset, `publicKey` the Base64 Ed25519
    /// public key compiled into the app (tools/release-key.swift).
    static func verifyEd25519(_ data: Data, signatureText: String, publicKey: String) throws {
        guard let key = Data(base64Encoded: publicKey).flatMap({ try? Curve25519.Signing.PublicKey(rawRepresentation: $0) }),
              let sig = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)),
              key.isValidSignature(sig, for: data) else {
            throw UpdateError(L("Signatur des Updates stimmt nicht, verworfen", "Update signature does not match, discarded"))
        }
    }

    /// nil when the app can be replaced where it is; otherwise an explanation for the user. With
    /// `requireWritable` the app folder must be writable by this user; without it only a read-only
    /// volume is a problem (the app then swaps with administrator rights).
    nonisolated static func targetProblem(_ app: URL, appName: String, requireWritable: Bool) -> String? {
        let move = L("Bitte \(appName) in den Ordner „Programme“ ziehen, von dort öffnen und das Update dann erneut starten.",
                     "Please move \(appName) to the Applications folder, open it from there and start the update again.")
        if app.path.contains("/AppTranslocation/") {
            return L("\(appName) läuft aus einem vorübergehenden Ort (macOS-Schutz für geladene Apps).",
                     "\(appName) is running from a temporary location (macOS app translocation).") + " " + move
        }
        if requireWritable {
            let fm = FileManager.default
            if !fm.isWritableFile(atPath: app.deletingLastPathComponent().path) || !fm.isWritableFile(atPath: app.path) {
                return L("Der Ordner mit \(appName) ist nicht beschreibbar.", "The folder containing \(appName) is not writable.") + " " + move
            }
        } else {
            var fs = statfs()
            if statfs(app.path, &fs) == 0, fs.f_flags & UInt32(MNT_RDONLY) != 0 {
                return L("\(appName) liegt auf einem schreibgeschützten Volume.", "\(appName) is on a read-only volume.") + " " + move
            }
        }
        return nil
    }

    /// Unpacks the zip into `work`, checks bundle ID, version and code signature of `<appName>.app`
    /// and only then removes the quarantine flag. Runs off the main thread. Returns the unpacked app.
    static func unpackAndVerify(zip zipData: Data, in work: URL, appName: String, bundleID: String, version: String) async throws -> URL {
        let zipURL = work.appendingPathComponent("\(appName).zip")
        let newApp = work.appendingPathComponent("\(appName).app")
        try await Task.detached(priority: .userInitiated) {
            try zipData.write(to: zipURL)
            guard run("/usr/bin/ditto", ["-x", "-k", zipURL.path, work.path]) else { throw UpdateError(L("Entpacken fehlgeschlagen", "Unzipping failed")) }
            let b = Bundle(url: newApp)
            guard b?.bundleIdentifier == bundleID else { throw UpdateError(L("Falsche App im Release", "Wrong app in the release")) }
            guard b?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version else {
                throw UpdateError(L("Versionsnummer passt nicht zum Release", "Version number does not match the release"))
            }
            try verifyCodeSignature(newApp)
            _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", newApp.path])
        }.value
        return newApp
    }

    /// Valid (ad hoc) code signature. Authenticity comes from the checksum or the Ed25519 signature.
    nonisolated static func verifyCodeSignature(_ app: URL) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateError(L("Signatur nicht lesbar", "Signature not readable"))
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, nil) == errSecSuccess else {
            throw UpdateError(L("Code-Signatur ungültig, Update verworfen", "Invalid code signature, update discarded"))
        }
    }

    // MARK: Swap

    /// Starts a small script that waits for this process to end, replaces `target` with `newApp`,
    /// opens the new app and removes `work`. If moving fails the old app comes back and, when a
    /// `logFile` is given, `failureMessage` is appended to it with a timestamp. The script text is
    /// static; paths and texts travel as arguments. `zsh -f` ignores the user's startup files.
    static func launchSwapScript(target: URL, newApp: URL, work: URL, logFile: URL? = nil, failureMessage: String? = nil) throws {
        let script = work.appendingPathComponent("swap.sh")
        let body = #"""
        #!/bin/zsh -f
        # $1 = PID of the old app, $2 = target (.app), $3 = new app, $4 = work folder, $5 = log file (optional), $6 = message for the log
        PID="$1"; TARGET="$2"; NEW="$3"; WORK="$4"; LOG="$5"; MSG="$6"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        OLD="$TARGET.alt"
        rm -rf "$OLD"
        if mv "$TARGET" "$OLD" && mv "$NEW" "$TARGET"; then
            rm -rf "$OLD"
        else
            [[ -d "$OLD" && ! -d "$TARGET" ]] && mv "$OLD" "$TARGET"
            [[ -n "$LOG" ]] && echo "$(date '+%Y-%m-%d %H:%M:%S')  $MSG" >> "$LOG"
        fi
        open "$TARGET"
        rm -rf "$WORK"
        """#
        try body.write(to: script, atomically: true, encoding: .utf8)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-f", script.path, String(ProcessInfo.processInfo.processIdentifier), target.path, newApp.path, work.path,
                       logFile?.path ?? "", failureMessage ?? ""]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
    }

    // MARK: Helpers

    /// Runs a tool and waits for it; true when it exits with 0.
    @discardableResult
    nonisolated static func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}

/// Drops the Authorization header when a download is redirected away from api.github.com.
private final class StripAuthOnRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        var r = request
        if r.url?.host != "api.github.com" { r.setValue(nil, forHTTPHeaderField: "Authorization") }
        return r
    }
}

// MARK: - Release notes

enum ReleaseNotes {
    /// GitHub Markdown roughly to plain text (for notifications and views without Markdown).
    static func cleanNotes(_ md: String) -> String {
        md.split(separator: "\n", omittingEmptySubsequences: false)
            .map { line -> String in
                var l = line.trimmingCharacters(in: .whitespaces)
                while l.hasPrefix("#") { l.removeFirst() }
                if l.hasPrefix("- ") || l.hasPrefix("* ") { l = "• " + l.dropFirst(2) }
                return l.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Release notes as attributed text: inline Markdown (bold, code) with line breaks kept and
    /// list dashes turned into bullets, because inline Markdown knows no lists.
    static func markdown(_ s: String) -> AttributedString {
        let s = s.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.hasPrefix("- ") || $0.hasPrefix("* ") ? "•  " + $0.dropFirst(2) : String($0) }.joined(separator: "\n")
        return (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
