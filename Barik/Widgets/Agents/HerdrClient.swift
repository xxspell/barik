import Darwin
import Foundation

enum HerdrClientError: Error, Equatable {
    case socketMissing
    case connectFailed(Int32)
    case closedWithoutResponse
    case timeout
}

/// Unix-socket client for herdr's JSON API.
/// herdr serves one request per connection (except `events.subscribe`).
final class HerdrClient: @unchecked Sendable {
    private let socketPath: String
    private let timeout: TimeInterval
    private let queue = DispatchQueue(label: "barik.agents.herdr-client", qos: .utility, attributes: .concurrent)

    init(socketPath: String, timeout: TimeInterval = 3) {
        self.socketPath = socketPath
        self.timeout = timeout
    }

    // MARK: Public API

    func send(_ request: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            queue.async { [self] in
                do { cont.resume(returning: try sendBlocking(request)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func subscribe(_ request: Data) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            let handle = FDHandle()
            continuation.onTermination = { _ in handle.terminate() }
            queue.async { [self] in
                // The reader thread is the only closer of the fd, so the number
                // it reads/writes can never have been recycled by another connection.
                defer { handle.closeFromReader() }
                do {
                    let fd = try openConnection(timeout: nil)
                    guard handle.set(fd) else { // terminated before connect finished
                        continuation.finish()
                        return
                    }
                    try writeAll(fd, request)
                    var pending = Data()
                    var buf = [UInt8](repeating: 0, count: 4096)
                    while true {
                        let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
                        if n < 0 {
                            if errno == EINTR { continue }
                            let e = errno
                            if handle.isTerminated { break }
                            throw HerdrClientError.connectFailed(e)
                        }
                        if n == 0 { break }
                        pending.append(contentsOf: buf[0..<n])
                        while let nl = pending.firstIndex(of: 0x0A) {
                            let line = Data(pending[pending.startIndex..<nl])
                            pending.removeSubrange(pending.startIndex...nl)
                            if !line.isEmpty { continuation.yield(line) }
                        }
                    }
                    if !pending.isEmpty { continuation.yield(pending) }
                    continuation.finish()
                } catch {
                    if handle.isTerminated { continuation.finish() }
                    else { continuation.finish(throwing: error) }
                }
            }
        }
    }

    // MARK: Internals

    private func sendBlocking(_ request: Data) throws -> Data {
        let fd = try openConnection(timeout: timeout)
        defer { close(fd) }
        try writeAll(fd, request)
        var response = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        while true {
            let n = buf.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { throw HerdrClientError.timeout }
                throw HerdrClientError.connectFailed(errno)
            }
            if n == 0 { break }
            response.append(contentsOf: buf[0..<n])
            if let nl = response.firstIndex(of: 0x0A) {
                return Data(response[response.startIndex..<nl])
            }
        }
        if response.isEmpty { throw HerdrClientError.closedWithoutResponse }
        return response
    }

    private func openConnection(timeout: TimeInterval?) throws -> Int32 {
        guard FileManager.default.fileExists(atPath: socketPath) else { throw HerdrClientError.socketMissing }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(socketPath.utf8CString)
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            throw HerdrClientError.connectFailed(ENAMETOOLONG)
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw HerdrClientError.connectFailed(errno) }

        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        if let timeout {
            var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        }

        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            pathBytes.withUnsafeBytes { raw.copyMemory(from: $0) }
        }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            let e = errno
            close(fd)
            if e == ENOENT || e == ECONNREFUSED { throw HerdrClientError.socketMissing }
            throw HerdrClientError.connectFailed(e)
        }
        return fd
    }

    private func writeAll(_ fd: Int32, _ data: Data) throws {
        var offset = 0
        try data.withUnsafeBytes { raw in
            while offset < raw.count {
                let n = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if n < 0 {
                    if errno == EINTR { continue }
                    if errno == EAGAIN || errno == EWOULDBLOCK { throw HerdrClientError.timeout }
                    throw HerdrClientError.connectFailed(errno)
                }
                offset += n
            }
        }
    }
}

/// Owns a subscription fd. Only the reader thread closes it; termination just
/// shuts the socket down (under the lock, while live) to unblock a pending read.
private final class FDHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32 = -1
    private var terminated = false

    var isTerminated: Bool { lock.lock(); defer { lock.unlock() }; return terminated }

    /// Returns false (and closes the fd, called from the reader) if termination already happened.
    func set(_ newFD: Int32) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if terminated { close(newFD); return false }
        fd = newFD
        return true
    }

    func terminate() {
        lock.lock(); defer { lock.unlock() }
        terminated = true
        if fd >= 0 { shutdown(fd, SHUT_RDWR) }
    }

    func closeFromReader() {
        lock.lock(); defer { lock.unlock() }
        if fd >= 0 { close(fd); fd = -1 }
    }
}
