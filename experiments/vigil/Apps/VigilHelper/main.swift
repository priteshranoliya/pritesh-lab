import Darwin
import Foundation
import VigilIPC

// Runs as root from /Library/LaunchDaemons. launchd restarts it if it exits.
guard geteuid() == 0 else {
    fputs("Vigil helper must run as root (installed by Vigil’s one-time setup).\n", stderr)
    exit(77)
}
umask(0o077)
signal(SIGPIPE, SIG_IGN)

let host = HelperHost(store: StateStore(folder: VigilIdentity.stateDirectory))
host.start()
SystemPowerObserver.start { host.systemWillSleep() }

let server = SocketServer(path: VigilIdentity.socketPath) { body in
    DispatchQueue.main.sync { MainActor.assumeIsolated { host.handle(body) } }
}
do { try server.start() } catch {
    fputs("Vigil helper could not open its socket: \(error.localizedDescription)\n", stderr)
    host.shutdown()
    exit(1)
}

var signalSources: [DispatchSourceSignal] = []
for value in [SIGTERM, SIGINT] {
    signal(value, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: value, queue: .main)
    source.setEventHandler {
        MainActor.assumeIsolated { host.shutdown() }
        exit(0)
    }
    source.resume()
    signalSources.append(source)
}

dispatchMain()
