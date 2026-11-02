// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation
import Darwin

final class CodexReadCancellation {
    private let lock = NSLock()
    private var stopped = false
    private var process: Process?
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func attach(_ child: Process?) {
        lock.lock(); defer { lock.unlock() }
        process = child
        if stopped, let child, child.isRunning { child.terminate() }
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        stopped = true
        if let process, process.isRunning { process.terminate() }
    }
}

// Only initialize + account/rateLimits/read. No thread, prompt, token-file access,
// account switching, reset consumption, or raw RPC/log persistence.
enum CodexClient {
    static func isExecutableFile(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        let url = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true && FileManager.default.isExecutableFile(atPath: url.path)
    }
    static func locate(override: String = "") -> String? {
        if !override.isEmpty { return isExecutableFile(override) ? URL(fileURLWithPath: override).standardizedFileURL.resolvingSymlinksInPath().path : nil }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").filter { $0.hasPrefix("/") }.map { String($0) + "/codex" }
        let candidates = paths + ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "/Applications/Codex.app/Contents/Resources/codex", "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"]
        return candidates.first { isExecutableFile($0) }.map { URL(fileURLWithPath: $0).standardizedFileURL.resolvingSymlinksInPath().path }
    }

    static func fetch(executable: String, timeout: TimeInterval = 25, cancellation: CodexReadCancellation = CodexReadCancellation()) throws -> QuotaSnapshot {
        guard !cancellation.cancelled else { throw RKError.message("读取已取消。") }
        guard isExecutableFile(executable) else { throw RKError.message("Codex 路径必须是绝对路径且指向普通可执行文件。") }
        let process = Process()
        let input = Pipe(), output = Pipe()
        // A child exiting between handshake messages must report EPIPE, not
        // deliver SIGPIPE and terminate the GUI process.
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        // Do not inherit the application's project as a Codex workspace.
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        try process.run()
        cancellation.attach(process)
        defer {
            cancellation.attach(nil)
            try? input.fileHandleForWriting.close()
            if process.isRunning { process.terminate() }
            let exitDeadline = ProcessInfo.processInfo.systemUptime + 1
            while process.isRunning && ProcessInfo.processInfo.systemUptime < exitDeadline { Thread.sleep(forTimeInterval: 0.01) }
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var buffer = Data()
        func send(_ value: [String: Any]) throws {
            var data = try JSONSerialization.data(withJSONObject: value)
            data.append(10)
            try input.fileHandleForWriting.write(contentsOf: data)
        }
        func receive(id: Int) throws -> Data {
            while ProcessInfo.processInfo.systemUptime < deadline {
                guard !cancellation.cancelled else { throw RKError.message("读取已取消。") }
                while let newline = buffer.firstIndex(of: 10) {
                    let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
                    guard let obj = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                    guard (obj["id"] as? Int) == id else { continue }
                    if let error = obj["error"] as? [String: Any] {
                        let code = error["code"] as? Int ?? 0
                        throw RKError.message("Codex 未能提供额度（\(code)）。请确认此 Codex 已使用 ChatGPT 登录，且网络可用；API Key 登录不提供这两项套餐额度。")
                    }
                    guard let result = obj["result"] as? [String: Any] else { throw RKError.message("Codex 返回格式无法识别，请更新 Codex 后重试。") }
                    return try JSONSerialization.data(withJSONObject: result)
                }
                var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
                let status = poll(&descriptor, 1, 200)
                if status < 0 { if errno == EINTR { continue }; throw RKError.message("读取 Codex 连接失败。") }
                if status == 0 { continue }
                var chunk = [UInt8](repeating: 0, count: 16384)
                let count = Darwin.read(descriptor.fd, &chunk, chunk.count)
                guard count > 0 else { throw RKError.message("Codex 提前退出。请检查 Codex 路径、版本和登录状态。") }
                buffer.append(contentsOf: chunk.prefix(count))
                guard buffer.count <= 2_000_000 else { throw RKError.message("Codex 响应过大，已停止读取。") }
            }
            throw RKError.message("读取额度超时，旧数据已停用。请检查网络或 Codex 登录状态后重试。")
        }
        try send(["id": 1, "method": "initialize", "params": ["clientInfo": ["name": "feralkey", "title": "FeralKey", "version": "0.10.0"]]])
        _ = try receive(id: 1)
        try send(["method": "initialized"])
        try send(["id": 2, "method": "account/rateLimits/read"])
        let response = try JSONDecoder().decode(QuotaResponse.self, from: receive(id: 2))
        guard !response.buckets.isEmpty else { throw RKError.message("此账号没有返回可显示的额度窗口。") }
        return QuotaSnapshot(buckets: response.buckets, fetchedAt: Date(), isDemo: false)
    }
}
