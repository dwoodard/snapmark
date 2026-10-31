import Foundation

/// Asks GitHub which release is latest. Reads the redirect from /releases/latest, so there is no API call, no token,
/// and no personal data sent. Drafts and pre-releases are never "latest", so they never trigger a notice.
enum UpdateChecker {
    static let repo = "dwoodard/snapmark"
    static let installCommand = "curl -fsSL https://raw.githubusercontent.com/\(repo)/HEAD/scripts/install.sh | bash"
    static let latestURL = URL(string: "https://github.com/\(repo)/releases/latest")!

    /// A newer published version found this session, if any.
    static var available: String?

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    struct Outcome {
        let latest: String
        let isNewer: Bool
    }

    enum CheckError: LocalizedError {
        case noRelease
        var errorDescription: String? { "No published release was found." }
    }

    /// Fetches the latest published version and records it in `available` when it is newer than this app.
    static func check() async throws -> Outcome {
        var request = URLRequest(url: latestURL)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 15
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let tag = response.url?.lastPathComponent, let latest = stableVersion(fromTag: tag) else {
            throw CheckError.noRelease
        }
        let newer = isNewer(latest, than: currentVersion)
        available = newer ? latest : nil
        return Outcome(latest: latest, isNewer: newer)
    }

    /// "v0.1.3" -> "0.1.3". Anything that is not a plain stable version is rejected.
    static func stableVersion(fromTag tag: String) -> String? {
        let v = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return parts(v) != nil && !v.contains("-") ? v : nil
    }

    private static func parts(_ version: String) -> [Int]? {
        let base = version.split(separator: "-", maxSplits: 1).first.map(String.init) ?? version
        let nums = base.split(separator: ".").compactMap { Int($0) }
        return nums.count == 3 && base.split(separator: ".").count == 3 ? nums : nil
    }

    /// True when `latest` is a newer release than `current`. A release candidate is older than its own release.
    static func isNewer(_ latest: String, than current: String) -> Bool {
        guard let l = parts(latest), let c = parts(current) else { return false }
        if l != c { return l.lexicographicallyPrecedes(c) == false }
        return current.contains("-")
    }
}
