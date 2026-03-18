import Foundation
import Darwin

final class PTYProcess: @unchecked Sendable {
    var onOutput: ((String) -> Void)?
    var onExit: ((Int32) -> Void)?

    private var process: Process?
    private var masterFD: Int32 = -1
    private var masterHandle: FileHandle?
    private var stopped = false

    func start(command: String, cwd: String) throws {
        var master: Int32 = 0
        var slave: Int32 = 0

        guard openpty(&master, &slave, nil, nil, nil) == 0 else {
            throw NSError(
                domain: "PTYProcess",
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "openpty failed (errno \(errno))"]
            )
        }

        masterFD = master
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", command]
        proc.currentDirectoryURL = URL(fileURLWithPath: cwd, isDirectory: true)
        proc.standardInput = slaveHandle
        proc.standardOutput = slaveHandle
        proc.standardError = slaveHandle
        proc.environment = ProcessInfo.processInfo.environment

        proc.terminationHandler = { [weak self] process in
            self?.cleanup()
            self?.onExit?(process.terminationStatus)
        }

        try proc.run()
        process = proc

        let masterHandle = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        self.masterHandle = masterHandle

        masterHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            self?.onOutput?(String(decoding: data, as: UTF8.self))
        }
    }

    func write(_ text: String) {
        guard masterFD >= 0, !text.isEmpty else { return }
        let data = Data(text.utf8)
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            _ = Darwin.write(masterFD, base, ptr.count)
        }
    }

    func interrupt() {
        write("\u{3}")
    }

    func stop() {
        guard !stopped else { return }
        stopped = true

        cleanup()

        if let process, process.isRunning {
            process.terminate()
        }

        if masterFD >= 0 {
            Darwin.close(masterFD)
            masterFD = -1
        }
    }

    deinit {
        stop()
    }

    private func cleanup() {
        masterHandle?.readabilityHandler = nil
        masterHandle = nil
    }
}
