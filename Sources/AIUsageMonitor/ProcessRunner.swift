import Foundation

struct ProcessResult: Sendable {
    let exitCode: Int32
    let standardOutput: String
    let standardError: String
}

enum ProcessRunner {
    static func run(
        executableURL: URL,
        arguments: [String],
        standardInput: String? = nil,
        timeout: TimeInterval = 15
    ) async throws -> ProcessResult {
        try await Task.detached(priority: .utility) {
            try runSynchronously(
                executableURL: executableURL,
                arguments: arguments,
                standardInput: standardInput,
                timeout: timeout
            )
        }.value
    }

    private static func runSynchronously(
        executableURL: URL,
        arguments: [String],
        standardInput: String?,
        timeout: TimeInterval
    ) throws -> ProcessResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let inputPipe = Pipe()
        let outputBuffer = ProcessDataBuffer()
        let errorBuffer = ProcessDataBuffer()

        process.executableURL = executableURL
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        if standardInput != nil {
            process.standardInput = inputPipe
        }

        outputPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                outputBuffer.append(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty {
                errorBuffer.append(data)
            }
        }

        do {
            try process.run()
        } catch {
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw ProviderError.processFailed(error.localizedDescription)
        }

        if let standardInput {
            if let data = standardInput.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            try? inputPipe.fileHandleForWriting.close()
        }

        let deadline = Date().addingTimeInterval(max(1, timeout))
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }

        if process.isRunning {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.2)
            if process.isRunning {
                process.interrupt()
            }
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw ProviderError.timedOut(executableURL.lastPathComponent)
        }

        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
        outputBuffer.append(outputPipe.fileHandleForReading.readDataToEndOfFile())
        errorBuffer.append(errorPipe.fileHandleForReading.readDataToEndOfFile())

        return ProcessResult(
            exitCode: process.terminationStatus,
            standardOutput: outputBuffer.string,
            standardError: errorBuffer.string
        )
    }
}

private final class ProcessDataBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) {
        guard !chunk.isEmpty else { return }
        lock.lock()
        data.append(chunk)
        lock.unlock()
    }

    var string: String {
        lock.lock()
        defer { lock.unlock() }
        return String(data: data, encoding: .utf8) ?? ""
    }
}
