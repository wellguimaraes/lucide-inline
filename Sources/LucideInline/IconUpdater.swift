import CryptoKit
import Foundation

/// Keeps the icon set current by pulling the latest lucide-static package from npm.
final class IconUpdater {
    enum Outcome {
        case upToDate(version: String)
        case updated(from: String, to: String, count: Int)
    }

    enum UpdateError: LocalizedError {
        case badResponse
        case integrityMismatch
        case extractFailed
        case emptyPackage

        var errorDescription: String? {
            switch self {
            case .badResponse: "The npm registry returned an unexpected response."
            case .integrityMismatch: "The downloaded package failed its integrity check."
            case .extractFailed: "The downloaded package could not be unpacked."
            case .emptyPackage: "The downloaded package contained no icons."
            }
        }
    }

    private struct PackageInfo: Decodable {
        struct Dist: Decodable {
            let tarball: URL
            let integrity: String
        }

        let version: String
        let dist: Dist
    }

    private static let registryURL = URL(string: "https://registry.npmjs.org/lucide-static/latest")!
    private static let lastCheckKey = "lastIconUpdateCheck"
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private let store: IconStore
    private var timer: Timer?
    private(set) var isChecking = false

    init(store: IconStore) {
        self.store = store
    }

    /// Checks now if the last successful check is over a day old, then re-evaluates hourly
    /// (a plain 24h timer would drift or be skipped across sleep).
    func startDailyChecks() {
        checkIfDue()
        timer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            self?.checkIfDue()
        }
    }

    private func checkIfDue() {
        let lastCheck = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(lastCheck) >= Self.checkInterval else { return }
        check { result in
            if case .failure(let error) = result {
                NSLog("LucideInline: icon update check failed: \(error.localizedDescription)")
            }
        }
    }

    func check(completion: @escaping (Result<Outcome, Error>) -> Void) {
        guard !isChecking else { return }
        isChecking = true
        let current = store.version

        Task.detached {
            let result: Result<Outcome, Error>
            do {
                result = .success(try await Self.update(from: current))
            } catch {
                result = .failure(error)
            }

            await MainActor.run {
                self.isChecking = false
                if case .success(let outcome) = result {
                    UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                    if case .updated = outcome { self.store.reload() }
                }
                completion(result)
            }
        }
    }

    // MARK: Download

    private static func update(from current: String) async throws -> Outcome {
        let (infoData, response) = try await URLSession.shared.data(from: registryURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.badResponse }
        let info = try JSONDecoder().decode(PackageInfo.self, from: infoData)

        guard current.isOlderVersion(than: info.version) else { return .upToDate(version: current) }

        let (tarballData, tarballResponse) = try await URLSession.shared.data(from: info.dist.tarball)
        guard (tarballResponse as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError.badResponse }
        guard matchesIntegrity(tarballData, info.dist.integrity) else { throw UpdateError.integrityMismatch }

        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("lucide-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }

        let tarball = workDir.appendingPathComponent("package.tgz")
        try tarballData.write(to: tarball)
        try extract(tarball, into: workDir)

        let set = try buildIconSet(packageDir: workDir.appendingPathComponent("package"), version: info.version)
        let destination = IconStore.downloadedURL
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(set).write(to: destination, options: .atomic)

        return .updated(from: current, to: set.version, count: set.icons.count)
    }

    /// npm publishes "sha512-<base64 digest>" for every tarball.
    private static func matchesIntegrity(_ data: Data, _ integrity: String) -> Bool {
        guard integrity.hasPrefix("sha512-") else { return false }
        let expected = String(integrity.dropFirst("sha512-".count))
        return Data(SHA512.hash(data: data)).base64EncodedString() == expected
    }

    private static func extract(_ tarball: URL, into directory: URL) throws {
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-xzf", tarball.path, "-C", directory.path]
        try tar.run()
        tar.waitUntilExit()
        guard tar.terminationStatus == 0 else { throw UpdateError.extractFailed }
    }

    /// Same transformation as scripts/fetch-icons.mjs.
    private static func buildIconSet(packageDir: URL, version: String) throws -> IconSet {
        let tagsData = try Data(contentsOf: packageDir.appendingPathComponent("tags.json"))
        let tags = try JSONDecoder().decode([String: [String]].self, from: tagsData)

        let iconsDir = packageDir.appendingPathComponent("icons")
        let files = try FileManager.default.contentsOfDirectory(atPath: iconsDir.path)
            .filter { $0.hasSuffix(".svg") }
            .sorted()

        let icons = try files.map { file -> LucideIcon in
            let name = String(file.dropLast(".svg".count))
            let svg = try String(contentsOf: iconsDir.appendingPathComponent(file), encoding: .utf8)
                .replacingOccurrences(of: "<!--[\\s\\S]*?-->", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return LucideIcon(name: name, tags: tags[name] ?? [], svg: svg)
        }
        guard !icons.isEmpty else { throw UpdateError.emptyPackage }
        return IconSet(version: version, icons: icons)
    }
}

extension String {
    /// Numeric dotted-version comparison ("1.9.0" < "1.10.0"); non-numeric parts count as 0.
    func isOlderVersion(than other: String) -> Bool {
        let lhs = split(separator: ".").map { Int($0) ?? 0 }
        let rhs = other.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a < b }
        }
        return false
    }
}
