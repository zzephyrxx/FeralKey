// SPDX-License-Identifier: GPL-3.0-or-later
import Foundation

@main enum CodexClientTests {
    static func main() throws {
        let executable = URL(fileURLWithPath: "tests/fake-codex.py").standardizedFileURL.path
        setenv("FERALKEY_TEST_MODE", "ok", 1)
        let snapshot = try CodexClient.fetch(executable: executable, timeout: 3)
        precondition(snapshot.remaining(bucket: "codex", minutes: 300, at: Date()) == 75)
        precondition(snapshot.remaining(bucket: "codex", minutes: 10080, at: Date()) == 40)
        for mode in ["exit", "timeout", "error", "malformed", "broken-pipe"] {
            setenv("FERALKEY_TEST_MODE", mode, 1)
            let start = Date()
            do { _ = try CodexClient.fetch(executable: executable, timeout: 0.4); fatalError("accepted \(mode)") }
            catch { precondition(!error.localizedDescription.contains("SECRET"), "no raw RPC secrets in errors") }
            precondition(Date().timeIntervalSince(start) < 3, "bounded timeout and child cleanup")
        }
        setenv("FERALKEY_TEST_MODE", "timeout", 1)
        let cancellation = CodexReadCancellation()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { cancellation.cancel() }
        let start = Date()
        do { _ = try CodexClient.fetch(executable: executable, timeout: 10, cancellation: cancellation); fatalError("cancel ignored") } catch { }
        precondition(Date().timeIntervalSince(start) < 3, "cancel closes child promptly")
        unsetenv("FERALKEY_TEST_MODE")
        precondition(!CodexClient.isExecutableFile("./tests/fake-codex.py"))
        precondition(!CodexClient.isExecutableFile(FileManager.default.currentDirectoryPath))
        precondition(CodexClient.locate(override: "./tests/fake-codex.py") == nil)
        let originalPath = ProcessInfo.processInfo.environment["PATH"]
        setenv("PATH", ".:relative/bin", 1)
        let located = CodexClient.locate()
        precondition(located == nil || located!.hasPrefix("/"), "ignore relative automatic PATH entries")
        if let originalPath { setenv("PATH", originalPath, 1) } else { unsetenv("PATH") }
        print("PASS: Codex stdio handshake, fragmented messages, live decoding, error privacy, EOF, malformed JSON, timeout, cancellation and process cleanup (local fixtures only).")
    }
}
