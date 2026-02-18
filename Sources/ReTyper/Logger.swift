import Foundation

/// Simple file logger for debugging.
/// Writes to /tmp/layoutswitcher.log
final class Logger {
    static let shared = Logger()
    
    private let logURL = URL(fileURLWithPath: "/tmp/layoutswitcher.log")
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()
    
    private init() {
        // Clear log file on start
        try? "".write(to: logURL, atomically: true, encoding: .utf8)
        log("📋 Logger initialized")
    }
    
    func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        
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
