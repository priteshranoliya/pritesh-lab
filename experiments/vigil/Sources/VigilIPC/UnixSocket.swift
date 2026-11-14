import Darwin
import Foundation

/// One request per connection: the client writes a JSON line, the server
/// answers with one JSON line and closes. Messages are small and bounded.
public enum UnixSocket {
    public static let maximumMessageBytes = 64 * 1024

    public enum Failure: LocalizedError, Equatable {
        case unavailable, timedOut, tooLarge, closed, system(Int32)
        public var errorDescription: String? {
            switch self {
            case .unavailable: "The Vigil helper isn’t running."
            case .timedOut: "The Vigil helper didn’t respond in time."
            case .tooLarge: "The helper message was too large."
            case .closed: "The helper closed the connection."
            case .system(let code): "Helper connection failed (\(String(cString: strerror(code))))."
            }
        }
    }

    /// Sends one request and waits for the reply. Blocking; call off the main thread.
    public static func send(_ request: Data, to path: String, timeout: TimeInterval = 5) throws -> Data {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Failure.system(errno) }
        defer { close(fd) }
        try setTimeout(fd, timeout)
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var address = try makeAddress(path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            throw errno == ENOENT || errno == ECONNREFUSED ? Failure.unavailable : Failure.system(errno)
        }
        try writeMessage(request, to: fd)
        return try readMessage(from: fd)
    }

    public static func makeAddress(_ path: String) throws -> sockaddr_un {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        guard bytes.count < capacity else { throw Failure.system(ENAMETOOLONG) }
        withUnsafeMutableBytes(of: &address.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        return address
    }

    public static func setTimeout(_ fd: Int32, _ seconds: TimeInterval) throws {
        var value = timeval(tv_sec: Int(seconds), tv_usec: Int32((seconds - floor(seconds)) * 1_000_000))
        let size = socklen_t(MemoryLayout<timeval>.size)
        guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &value, size) == 0,
              setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &value, size) == 0 else { throw Failure.system(errno) }
    }

    /// Reads up to the first newline (or EOF). Rejects oversized messages.
    public static func readMessage(from fd: Int32) throws -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &buffer, buffer.count)
            if count < 0 {
                if errno == EINTR { continue }
                throw errno == EAGAIN || errno == EWOULDBLOCK ? Failure.timedOut : Failure.system(errno)
            }
            if count == 0 { break }
            if let newline = buffer[0..<count].firstIndex(of: 0x0A) {
                data.append(contentsOf: buffer[0..<newline])
                break
            }
            data.append(contentsOf: buffer[0..<count])
            guard data.count <= maximumMessageBytes else { throw Failure.tooLarge }
        }
        guard !data.isEmpty else { throw Failure.closed }
        guard data.count <= maximumMessageBytes else { throw Failure.tooLarge }
        return data
    }

    public static func writeMessage(_ data: Data, to fd: Int32) throws {
        guard data.count < maximumMessageBytes else { throw Failure.tooLarge }
        var message = data
        message.append(0x0A)
        try message.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let written = write(fd, raw.baseAddress! + offset, raw.count - offset)
                if written < 0 {
                    if errno == EINTR { continue }
                    throw errno == EAGAIN || errno == EWOULDBLOCK ? Failure.timedOut : Failure.system(errno)
                }
                offset += written
            }
        }
    }
}

/// Typed client used by the app and the CLI.
public enum HelperClient {
    public static func send(_ request: HelperRequest, path: String = VigilIdentity.socketPath,
                            timeout: TimeInterval = 5) throws -> HelperResponse {
        let body = try HelperCoding.encoder().encode(request)
        let reply = try UnixSocket.send(body, to: path, timeout: timeout)
        return try HelperCoding.decoder().decode(HelperResponse.self, from: reply)
    }
}
