import Foundation

public enum CodexExecutableError: LocalizedError, Equatable {
    case customPathNotExecutable(String)
    case notFound

    public var errorDescription: String? {
        switch self {
        case let .customPathNotExecutable(path):
            "指定的 Codex 不可执行：\(path)"
        case .notFound:
            "未找到 Codex。请安装 ChatGPT/Codex，或在设置中选择 Codex 可执行文件。"
        }
    }
}

public enum CodexExecutableResolver {
    public static let standardPaths = [
        "/Applications/ChatGPT.app/Contents/Resources/codex",
        "/opt/homebrew/bin/codex",
        "/usr/local/bin/codex"
    ]

    public static func resolve(
        customPath: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let customPath = customPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !customPath.isEmpty {
            guard fileManager.isExecutableFile(atPath: customPath) else {
                throw CodexExecutableError.customPathNotExecutable(customPath)
            }
            return URL(fileURLWithPath: customPath)
        }

        for path in standardPaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        throw CodexExecutableError.notFound
    }
}
