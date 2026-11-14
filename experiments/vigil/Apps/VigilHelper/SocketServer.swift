import Darwin
import Foundation
import VigilIPC

/// Accepts one request per connection on a root-owned Unix socket. Any local
/// process may connect; the helper only accepts bounded session commands.
final class SocketServer: @unchecked Sendable {
    private let path: String
    private let handler: @Sendable (Data) -> Data
    private let acceptQueue = DispatchQueue(label: "app.vigil.helper.accept")
    private let workQueue = DispatchQueue(label: "app.vigil.helper.ipc", attributes: .concurrent)
    private var source: DispatchSourceRead?

    init(path: String, handler: @escaping @Sendable (Data) -> Data) {
        self.path = path
        self.handler = handler
    }

    func start() throws {
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw UnixSocket.Failure.system(errno) }
        var address = try UnixSocket.makeAddress(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        // The app and CLI run as the logged-in user, so they must be able to connect.
        guard bound == 0, chmod(path, 0o666) == 0, listen(fd, 16) == 0 else {
            let code = errno
            close(fd)
            throw UnixSocket.Failure.system(code)
        }
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: acceptQueue)
        source.setEventHandler { [weak self] in
            let client = accept(fd, nil, nil)
            guard client >= 0, let self else { return }
            self.workQueue.async { self.serve(client) }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    private func serve(_ client: Int32) {
        defer { close(client) }
        var noSigPipe: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        guard (try? UnixSocket.setTimeout(client, 2)) != nil,
              let request = try? UnixSocket.readMessage(from: client) else { return }
        try? UnixSocket.writeMessage(handler(request), to: client)
    }
}
