import Foundation

enum AppInfo {
    static var shortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
    }

    static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static var versionDisplay: String {
        "\(shortVersion) (\(buildNumber))"
    }

    static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.miaoz.wick"
    }

    /// Semantic-ish compare: "1.2.0" > "1.1.9". Pre-release suffixes sort below plain versions.
    static func isVersion(_ candidate: String, newerThan current: String) -> Bool {
        let lhs = normalizeVersion(candidate)
        let rhs = normalizeVersion(current)
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b {
                return a > b
            }
        }
        return false
    }

    private static func normalizeVersion(_ raw: String) -> [Int] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutV = trimmed.hasPrefix("v") || trimmed.hasPrefix("V")
            ? String(trimmed.dropFirst())
            : trimmed
        let core = withoutV.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: true).first
            .map(String.init) ?? withoutV
        return core.split(separator: ".").compactMap { Int($0) }
    }
}
