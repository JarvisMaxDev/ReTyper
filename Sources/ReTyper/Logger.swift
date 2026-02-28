import Foundation
import os

/// Logger that outputs to both OSLog and a file for debugging.
/// Writes to /tmp/retyper.log
final class Logger {
    static let shared = Logger()
    
    private let osLog = os.Logger(subsystem: "com.retyper.app", category: "general")
    private let logURL = URL(fileURLWithPath: "/tmp/retyper.log")
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    
    private init() {
        // Add session separator instead of clearing the log
        let separator = "\n\n========== ReTyper session started at \(DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .medium)) ==========\n"
        if let data = separator.data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: logURL.path) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? separator.write(to: logURL, atomically: true, encoding: .utf8)
            }
        }
        log("📋 Logger initialized")
    }
    
    func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        
        // Log to OSLog (visible in Console.app)
        osLog.info("\(message, privacy: .public)")
        
        // Print to stdout
        print(line, terminator: "")
        fflush(stdout)
        
        // Append to file
        if let data = line.data(using: .utf8) {
            if let handle = FileHandle(forWritingAtPath: logURL.path) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try? line.write(to: logURL, atomically: true, encoding: .utf8)
            }
        }
    }
}
