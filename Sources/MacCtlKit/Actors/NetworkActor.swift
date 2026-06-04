import Network
import Foundation

public actor NetworkActor {
    private let monitor: NWPathMonitor
    private var currentPath: NWPath?
    private let monitorQueue = DispatchQueue(label: "macctl.network-monitor", qos: .utility)

    public init() {
        monitor = NWPathMonitor()
        let m = monitor
        Task { await self.startMonitor(m) }
    }

    private func startMonitor(_ m: NWPathMonitor) {
        m.pathUpdateHandler = { [weak self] path in
            Task { await self?.setPath(path) }
        }
        m.start(queue: monitorQueue)
    }

    private func setPath(_ path: NWPath) { currentPath = path }

    deinit { monitor.cancel() }

    // MARK: - Status

    public struct NetworkStatus: Sendable {
        public let isConnected: Bool
        public let isExpensive: Bool
        public let isConstrained: Bool
        public let interfaces: [String]
        public let hasWifi: Bool
        public let hasCellular: Bool
        public let hasWired: Bool
        public let hasVPN: Bool
    }

    public func status() -> NetworkStatus {
        let path = currentPath ?? monitor.currentPath
        let ifaces = path.availableInterfaces
        return NetworkStatus(
            isConnected:   path.status == .satisfied,
            isExpensive:   path.isExpensive,
            isConstrained: path.isConstrained,
            interfaces:    ifaces.map(\.name),
            hasWifi:       ifaces.contains { $0.type == .wifi },
            hasCellular:   ifaces.contains { $0.type == .cellular },
            hasWired:      ifaces.contains { $0.type == .wiredEthernet },
            hasVPN:        ifaces.contains { $0.type == .other }
        )
    }

    // MARK: - DNS resolution (getaddrinfo — public POSIX API)

    public func resolve(hostname: String) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var hints = addrinfo()
                hints.ai_family = AF_UNSPEC
                hints.ai_socktype = SOCK_STREAM
                var result: UnsafeMutablePointer<addrinfo>?
                guard getaddrinfo(hostname, nil, &hints, &result) == 0, let result else {
                    continuation.resume(throwing: NetworkError.resolutionFailed(hostname))
                    return
                }
                defer { freeaddrinfo(result) }
                var addresses: [String] = []
                var ptr: UnsafeMutablePointer<addrinfo>? = result
                while let current = ptr {
                    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                    if getnameinfo(current.pointee.ai_addr, current.pointee.ai_addrlen,
                                  &host, socklen_t(NI_MAXHOST), nil, 0, NI_NUMERICHOST) == 0 {
                        let addr = String(cString: host)
                        if !addresses.contains(addr) { addresses.append(addr) }
                    }
                    ptr = current.pointee.ai_next
                }
                if addresses.isEmpty {
                    continuation.resume(throwing: NetworkError.resolutionFailed(hostname))
                } else {
                    continuation.resume(returning: addresses)
                }
            }
        }
    }
}

public enum NetworkError: Error, Sendable {
    case resolutionFailed(String)
}
