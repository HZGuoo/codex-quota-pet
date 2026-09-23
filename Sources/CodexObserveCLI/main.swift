import Foundation
import CodexQuotaPetCore

@main
enum CodexObserveCommand {
    static func main() async {
        do {
            let options = try Options(arguments: Array(CommandLine.arguments.dropFirst()))
            if options.showHelp {
                print(Options.help)
                return
            }

            var settings = AppSettings()
            settings.customCodexPath = options.codexPath ?? ""
            let client = CodexObservabilityClient()
            try await client.start(settings: settings)
            do {
                let snapshot = try await client.capture()
                let data = try CodexObservationExporter.export(snapshot, format: options.format)
                guard let output = String(data: data, encoding: .utf8) else {
                    throw CLIError.encodingFailed
                }
                print(output, terminator: "")
                await client.stop()
            } catch {
                await client.stop()
                throw error
            }
        } catch {
            FileHandle.standardError.write(Data("codex-observe: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

private struct Options {
    var format: CodexObservationExportFormat = .json
    var codexPath: String?
    var showHelp = false

    init(arguments: [String]) throws {
        var index = 0
        while index < arguments.count {
            switch arguments[index] {
            case "-h", "--help":
                showHelp = true
            case "--format":
                index += 1
                guard index < arguments.count,
                      let value = CodexObservationExportFormat(rawValue: arguments[index]) else {
                    throw CLIError.invalidFormat
                }
                format = value
            case "--codex-path":
                index += 1
                guard index < arguments.count, !arguments[index].isEmpty else {
                    throw CLIError.missingCodexPath
                }
                codexPath = arguments[index]
            default:
                throw CLIError.unknownArgument(arguments[index])
            }
            index += 1
        }
    }

    static let help = """
    Usage: codex-observe [--format json|csv] [--codex-path PATH]

    Captures a privacy-preserving local Codex observability snapshot containing
    quota windows, aggregate token usage, and task-state counts.
    """
}

private enum CLIError: LocalizedError {
    case invalidFormat
    case missingCodexPath
    case unknownArgument(String)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidFormat: "--format must be json or csv"
        case .missingCodexPath: "--codex-path requires a path"
        case let .unknownArgument(argument): "unknown argument: \(argument)"
        case .encodingFailed: "could not encode output as UTF-8"
        }
    }
}
