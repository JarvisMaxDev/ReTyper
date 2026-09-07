import Foundation
import os
import Darwin

/// Local diagnostics. Callers must pass metadata, never user text or clipboard contents.
/// An arbitrary String cannot be reliably classified or redacted here.
final class Logger {
    static let shared = Logger()

    static let maximumFileBytes = 1_048_576
    static let maximumMessageBytes = 4_096
    static let maximumPendingMessages = 256

    // Internal so tests can stall the writer and exercise admission deterministically.
    let queue = DispatchQueue(label: "com.retyper.app.logger", qos: .utility,
                              autoreleaseFrequency: .workItem)
    private let slots = DispatchSemaphore(value: maximumPendingMessages)
    private let fileURLOverride: URL?

    // These properties are only accessed on the writer queue.
    private lazy var osLog = os.Logger(subsystem: "com.retyper.app", category: "general")
    private lazy var fileURL: URL? = fileURLOverride ?? FileManager.default
        .urls(for: .cachesDirectory, in: .userDomainMask).first?
        .appendingPathComponent("com.retyper.app", isDirectory: true)
        .appendingPathComponent("retyper.log")
    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    init(fileURL: URL? = nil) {
        fileURLOverride = fileURL
    }

    func log(_ message: String) {
        // Drop newest on overload, without waiting for disk or retaining a large String.
        guard slots.wait(timeout: .now()) == .success else { return }
        let bytes = Array(message.utf8.prefix(Self.maximumMessageBytes + 1))
        queue.async {
            defer { self.slots.signal() }
            self.write(bytes)
        }
    }

    /// Waits for already submitted writes; intended for tests, not the event-tap hot path.
    func flush() {
        queue.sync {}
    }

    private func write(_ bytes: [UInt8]) {
        var bytes = bytes
        let truncated = bytes.count > Self.maximumMessageBytes
        if truncated {
            bytes.removeLast()
            // A byte limit can split the last scalar; discard only its incomplete bytes.
            while String(bytes: bytes, encoding: .utf8) == nil {
                bytes.removeLast()
            }
        }

        let message = String(decoding: bytes, as: UTF8.self)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\u{0085}", with: "\\u{0085}")
            .replacingOccurrences(of: "\u{2028}", with: "\\u{2028}")
            .replacingOccurrences(of: "\u{2029}", with: "\\u{2029}")
        let timestamp = dateFormatter.string(from: Date())
        let data = Data("[\(timestamp)] \(message)\(truncated ? " [truncated]" : "")\n".utf8)

        // Never publish the supplied String, even if it appears to contain only metadata.
        osLog.info("Diagnostic event (record bytes: \(data.count, privacy: .public))")

        guard let fileURL = fileURL, fileURL.isFileURL else { return }
        let directoryURL = fileURL.deletingLastPathComponent()
        let parent = open(directoryURL.deletingLastPathComponent().path,
                          O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW_ANY)
        guard parent >= 0 else { return }
        defer { close(parent) }

        var info = stat()
        guard fstat(parent, &info) == 0,
              info.st_uid == geteuid(), info.st_mode & 0o022 == 0 else { return }
        guard mkdirat(parent, directoryURL.lastPathComponent, 0o700) == 0 || errno == EEXIST else {
            return
        }
        let directory = openat(parent, directoryURL.lastPathComponent,
                               O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard directory >= 0 else { return }
        defer { close(directory) }
        guard fstat(directory, &info) == 0, info.st_uid == geteuid(),
              fchmod(directory, 0o700) == 0 else { return }

        // Descriptor-relative opens pin the checked directory. Nonblocking also rejects FIFOs.
        let file = openat(directory, fileURL.lastPathComponent,
                          O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK, 0o600)
        guard file >= 0 else { return }
        defer { close(file) }
        guard flock(file, LOCK_EX | LOCK_NB) == 0,
              fstat(file, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == geteuid(), info.st_nlink == 1,
              fchmod(file, 0o600) == 0 else { return }

        var originalSize = info.st_size
        if originalSize > Self.maximumFileBytes - data.count {
            guard ftruncate(file, 0) == 0 else { return }
            originalSize = 0
        }

        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var written = 0
            while written < buffer.count {
                let count = Darwin.write(file, base.advanced(by: written), buffer.count - written)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else {
                    // Best effort: do not leave a partial line after a failed append.
                    _ = ftruncate(file, originalSize)
                    return
                }
                written += count
            }
        }
    }
}
