import Darwin
import Foundation

public enum ProxyPreflightError: LocalizedError, Equatable {
    case invalidEndpoint
    case unreachable(host: String, port: Int)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            "代理地址无效。"
        case let .unreachable(host, port):
            "代理不可用：\(host):\(port)。已停止请求，不会自动直连。"
        }
    }
}

public enum ProxyEndpointPreflight {
    public static func check(settings: AppSettings, timeoutMilliseconds: Int32 = 1_500) throws {
        guard settings.proxyMode != .disabled else { return }
        try settings.validateProxy()
        guard let components = URLComponents(string: settings.proxyURL),
              let host = components.host,
              let port = components.port else {
            throw ProxyPreflightError.invalidEndpoint
        }

        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &result) == 0, let first = result else {
            throw ProxyPreflightError.unreachable(host: host, port: port)
        }
        defer { freeaddrinfo(first) }

        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let address = cursor?.pointee {
            let descriptor = socket(address.ai_family, address.ai_socktype, address.ai_protocol)
            if descriptor >= 0 {
                let existingFlags = fcntl(descriptor, F_GETFL, 0)
                _ = fcntl(descriptor, F_SETFL, existingFlags | O_NONBLOCK)
                let connectResult = Darwin.connect(descriptor, address.ai_addr, address.ai_addrlen)
                if connectResult == 0 {
                    Darwin.close(descriptor)
                    return
                }

                if errno == EINPROGRESS {
                    var pollDescriptor = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                    if poll(&pollDescriptor, 1, timeoutMilliseconds) > 0 {
                        var socketError: Int32 = 0
                        var socketErrorLength = socklen_t(MemoryLayout<Int32>.size)
                        if getsockopt(
                            descriptor,
                            SOL_SOCKET,
                            SO_ERROR,
                            &socketError,
                            &socketErrorLength
                        ) == 0, socketError == 0 {
                            Darwin.close(descriptor)
                            return
                        }
                    }
                }
                Darwin.close(descriptor)
            }
            cursor = address.ai_next
        }

        throw ProxyPreflightError.unreachable(host: host, port: port)
    }
}
