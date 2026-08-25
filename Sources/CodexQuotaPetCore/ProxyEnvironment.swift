import Foundation

public enum ProxyEnvironment {
    private static let proxyKeys = [
        "HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY",
        "http_proxy", "https_proxy", "all_proxy",
        "NO_PROXY", "no_proxy"
    ]

    public static func make(
        base: [String: String] = ProcessInfo.processInfo.environment,
        settings: AppSettings
    ) throws -> [String: String] {
        let settings = settings.normalized
        try settings.validateProxy()

        var environment = base
        for key in proxyKeys {
            environment.removeValue(forKey: key)
        }

        environment["NO_PROXY"] = "localhost,127.0.0.1,::1"
        environment["no_proxy"] = "localhost,127.0.0.1,::1"

        switch settings.proxyMode {
        case .disabled:
            break
        case .http:
            for key in ["HTTP_PROXY", "HTTPS_PROXY", "ALL_PROXY", "http_proxy", "https_proxy", "all_proxy"] {
                environment[key] = settings.proxyURL
            }
        case .socks5:
            let normalizedURL = normalizeSocksURL(settings.proxyURL)
            environment["ALL_PROXY"] = normalizedURL
            environment["all_proxy"] = normalizedURL
        }

        return environment
    }

    private static func normalizeSocksURL(_ value: String) -> String {
        guard value.lowercased().hasPrefix("socks5://") else { return value }
        return "socks5h://" + value.dropFirst("socks5://".count)
    }
}
