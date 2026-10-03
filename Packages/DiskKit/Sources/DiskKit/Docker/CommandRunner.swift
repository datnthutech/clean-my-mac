import Foundation

public struct CommandResult: Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
    public let timedOut: Bool

    public init(exitCode: Int32, stdout: String, stderr: String, timedOut: Bool = false) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
        self.timedOut = timedOut
    }

    public var succeeded: Bool { exitCode == 0 && !timedOut }
}

/// Runs external programs. Abstracted so Docker logic can be tested without Docker.
public protocol CommandRunner: Sendable {
    func run(_ executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval) throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        // Drain both pipes concurrently so a chatty process never blocks on a full pipe buffer.
        let group = DispatchGroup()
        let outData = DataBox()
        let errData = DataBox()
        group.enter()
        DispatchQueue.global().async {
            outData.value = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData.value = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            // Close our ends so the reader threads finish, then report the launch failure.
            try? outPipe.fileHandleForWriting.close()
            try? errPipe.fileHandleForWriting.close()
            group.wait()
            throw error
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            _ = exited.wait(timeout: .now() + 2)
        }
        group.wait()
        process.waitUntilExit()

        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: String(decoding: outData.value, as: UTF8.self),
            stderr: String(decoding: errData.value, as: UTF8.self),
            timedOut: timedOut
        )
    }
}

/// Written by one reader thread, read after `DispatchGroup.wait()` — the group provides the synchronization.
private final class DataBox: @unchecked Sendable {
    var value = Data()
}
