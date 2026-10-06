import Foundation

public enum CodexExecutableError: LocalizedError, Equatable {
    case customPathNotExecutable(String)
    case notFound

    public var errorDescription: String? {
        switch self {
        case let .customPathNotExecutable(path):
            "指定的 Codex 不可执行：\(path)"
        case .notFound:
            "未找到 Codex。请安装 ChatGPT/Codex，或在设置中选择 ChatGPT/Codex 应用或 Codex CLI 可执行文件。"
        }
    }
}

public enum CodexExecutableResolver {
    private static let bundleExecutablePaths = [
        "Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex",
        "Contents/Resources/codex-cli/bin/codex",
        "Contents/Resources/codex",
        "Contents/MacOS/codex"
    ]

    public static let standardPaths = ["ChatGPT.app", "Codex.app"].flatMap { name in
        bundleExecutablePaths.map { "/Applications/\(name)/\($0)" }
    } + [
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex"
    ]

    public static func resolve(
        customPath: String,
        fileManager: FileManager = .default,
        searchPaths: [String]? = nil
    ) throws -> URL {
        let customPath = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customPath.isEmpty {
            let expandedPath = (customPath as NSString).expandingTildeInPath
            if let executable = executable(at: expandedPath, fileManager: fileManager) {
                return executable
            }

            // Recover a saved bundled CLI path after an application update moves
            // the binary. Restrict this to recognized locations in the same app.
            for relativePath in bundleExecutablePaths where expandedPath.hasSuffix("/" + relativePath) {
                let bundlePath = String(expandedPath.dropLast(relativePath.count + 1))
                if bundlePath.lowercased().hasSuffix(".app"),
                   let executable = executable(at: bundlePath, fileManager: fileManager) {
                    return executable
                }
            }
            throw CodexExecutableError.customPathNotExecutable(customPath)
        }

        for path in searchPaths ?? defaultSearchPaths(fileManager: fileManager) {
            if let executable = executable(at: path, fileManager: fileManager) {
                return executable
            }
        }
        throw CodexExecutableError.notFound
    }

    private static func defaultSearchPaths(fileManager: FileManager) -> [String] {
        let home = fileManager.homeDirectoryForCurrentUser
        let userApplications = ["ChatGPT.app", "Codex.app"].map {
            home.appendingPathComponent("Applications/\($0)").path
        }
        let pathExecutables = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .filter { $0.hasPrefix("/") }
            .map { URL(fileURLWithPath: String($0)).appendingPathComponent("codex").path }
        return standardPaths + userApplications + pathExecutables
    }

    private static func executable(at path: String, fileManager: FileManager) -> URL? {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        if !isDirectory.boolValue {
            return fileManager.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
        }

        let directory = URL(fileURLWithPath: path, isDirectory: true)
        // Accept an app bundle or a selected CLI/resources directory. Never use
        // the GUI application's CFBundleExecutable as the app-server binary.
        let relativePaths = bundleExecutablePaths + [
            "codex", "bin/codex", "CodexCLI.app/Contents/MacOS/codex",
            "codex-cli/CodexCLI.app/Contents/MacOS/codex", "codex-cli/bin/codex"
        ]
        for relativePath in relativePaths {
            let candidate = directory.appendingPathComponent(relativePath)
            var candidateIsDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: candidate.path, isDirectory: &candidateIsDirectory),
               !candidateIsDirectory.boolValue,
               fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }
}
