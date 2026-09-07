import XCTest
import Darwin
@testable import ReTyper

final class LoggerTests: XCTestCase {
    private var root: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        // Foundation can normalize /private/var back to the /var symlink.
        let temporaryPath = try XCTUnwrap(realpath(FileManager.default.temporaryDirectory.path, nil))
        defer { free(temporaryPath) }
        root = URL(fileURLWithPath: String(cString: temporaryPath), isDirectory: true)
            .appendingPathComponent("ReTyper-LoggerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        fileURL = root.appendingPathComponent("logs", isDirectory: true)
            .appendingPathComponent("retyper.log")
    }

    override func tearDownWithError() throws {
        if let root = root {
            try FileManager.default.removeItem(at: root)
        }
    }

    private func messages() throws -> [String] {
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(text.hasSuffix("\n"))
        return text.split(separator: "\n", omittingEmptySubsequences: false).dropLast().map { line in
            let line = String(line)
            let prefix = line.range(of: #"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}\] "#,
                                    options: .regularExpression)
            XCTAssertNotNil(prefix)
            return prefix.map { String(line[$0.upperBound...]) } ?? line
        }
    }

    func testWritesInOrderAndPreservesRecordBoundaries() throws {
        let logger = Logger(fileURL: fileURL)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        logger.log("event=started")
        logger.log("state=ready\r\nreason=none\\n\u{0085}\u{2028}\u{2029}")
        logger.log("")
        logger.log("event=finished count=3")
        logger.flush()

        XCTAssertEqual(try messages(), [
            "event=started",
            "state=ready\\r\\nreason=none\\\\n\\u{0085}\\u{2028}\\u{2029}",
            "",
            "event=finished count=3"
        ])
    }

    func testLoginItemFailuresLogOnlyBackendAndNumericCode() throws {
        let marker = "SENSITIVE-FIXTURE-MARKER"
        let error = NSError(domain: marker, code: 42, userInfo: [
            NSLocalizedDescriptionKey: marker,
            NSFilePathErrorKey: "/fixture/\(marker)/agent.plist"
        ])
        let logger = Logger(fileURL: fileURL)
        for legacy in [false, true] {
            logger.log(SettingsManager.loginItemFailureMessage(error, legacy: legacy))
        }
        logger.flush()

        XCTAssertEqual(try messages(), [
            "Login item update failed (backend=SMAppService, code=42)",
            "Login item update failed (backend=LaunchAgent, code=42)"
        ])
        XCTAssertFalse(try String(contentsOf: fileURL, encoding: .utf8).contains(marker))
    }

    func testAppendsAcrossInstancesAndEnforcesPrivatePermissions() throws {
        let first = Logger(fileURL: fileURL)
        first.log("event=first")
        first.flush()
        try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                              ofItemAtPath: fileURL.deletingLastPathComponent().path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: fileURL.path)

        let second = Logger(fileURL: fileURL)
        second.log("event=second")
        second.flush()

        XCTAssertEqual(try messages(), ["event=first", "event=second"])
        let directory = try FileManager.default.attributesOfItem(atPath: fileURL.deletingLastPathComponent().path)
        let file = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        XCTAssertEqual((directory[.posixPermissions] as? NSNumber)?.intValue, 0o700)
        XCTAssertEqual((file[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testConcurrentRepeatedMessagesStayIntact() throws {
        let logger = Logger(fileURL: fileURL)
        DispatchQueue.concurrentPerform(iterations: Logger.maximumPendingMessages) { _ in
            logger.log("event=completed count=7")
        }
        logger.flush()

        XCTAssertEqual(try messages(), Array(repeating: "event=completed count=7",
                                            count: Logger.maximumPendingMessages))
    }

    func testBacklogIsBoundedAndHotPathDoesNotWaitForWriter() throws {
        let logger = Logger(fileURL: fileURL)
        let producer = DispatchGroup()
        logger.queue.suspend()
        DispatchQueue.global().async(group: producer) {
            for _ in 0..<Logger.maximumPendingMessages {
                logger.log("event=queued")
            }
            let repeated = String(repeating: "state=overflow ", count: 10_000)
            for _ in 0..<10_000 {
                logger.log(repeated)
            }
        }
        let result = producer.wait(timeout: .now() + 5)
        logger.queue.resume()
        XCTAssertEqual(result, .success, "Logging must not wait for the stalled writer")
        guard result == .success else {
            producer.wait()
            logger.flush()
            return
        }
        logger.flush()
        XCTAssertEqual(try messages(), Array(repeating: "event=queued", count: Logger.maximumPendingMessages))

        logger.log("event=recovered")
        logger.flush()
        XCTAssertEqual(try messages().last, "event=recovered")
    }

    func testOversizedMessageIsBoundedWithoutSplittingUnicode() throws {
        let logger = Logger(fileURL: fileURL)
        logger.log("state=" + String(repeating: "\u{1F680}", count: Logger.maximumMessageBytes))
        logger.flush()

        let expected = "state=" + String(repeating: "\u{1F680}", count: (Logger.maximumMessageBytes - 6) / 4)
        XCTAssertEqual(try messages(), [expected + " [truncated]"])
        XCTAssertLessThan(try Data(contentsOf: fileURL).count, Logger.maximumMessageBytes + 100)
    }

    func testRepeatedDataRotatesWithinFileLimitAndPreservesWholeLines() throws {
        let logger = Logger(fileURL: fileURL)
        let repeated = "state=" + String(repeating: "x", count: Logger.maximumMessageBytes - 6)
        for _ in 0..<12 {
            for _ in 0..<64 {
                logger.log(repeated)
            }
            logger.flush()
            let size = try Data(contentsOf: fileURL).count
            XCTAssertGreaterThan(size, 0)
            XCTAssertLessThanOrEqual(size, Logger.maximumFileBytes)
            XCTAssertTrue(try messages().allSatisfy { $0 == repeated })
        }
        let retained = try messages()
        XCTAssertFalse(retained.isEmpty)
        XCTAssertLessThan(retained.count, 12 * 64)

        logger.log("event=after-rotation")
        logger.flush()
        XCTAssertEqual(try messages().last, "event=after-rotation")
        XCTAssertLessThanOrEqual(try Data(contentsOf: fileURL).count, Logger.maximumFileBytes)
    }

    func testOversizedExistingTestFileIsTruncatedBeforeAppend() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: false)
        try Data(repeating: 120, count: Logger.maximumFileBytes + 1).write(to: fileURL)
        let logger = Logger(fileURL: fileURL)
        logger.log("event=after-truncation")
        logger.flush()

        XCTAssertEqual(try messages(), ["event=after-truncation"])
    }

    func testMissingParentErrorsAreSwallowedAndLaterWritesRecover() throws {
        let missing = root.appendingPathComponent("missing", isDirectory: true)
        fileURL = missing.appendingPathComponent("logs/retyper.log")
        let logger = Logger(fileURL: fileURL)
        for _ in 0..<Logger.maximumPendingMessages {
            logger.log("event=unavailable")
        }
        logger.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o700])
        logger.log("event=recovered")
        logger.flush()
        XCTAssertEqual(try messages(), ["event=recovered"])
    }

    func testRejectsFileSymlinksAndHardLinksWithoutModifyingTarget() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: false)
        let target = root.appendingPathComponent("target")
        let original = Data("synthetic test fixture\n".utf8)
        try original.write(to: target)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: target.path)
        let logger = Logger(fileURL: fileURL)

        try FileManager.default.createSymbolicLink(at: fileURL, withDestinationURL: target)
        logger.log("event=symlink-refused")
        logger.flush()
        XCTAssertEqual(try Data(contentsOf: target), original)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: fileURL.path), target.path)

        try FileManager.default.removeItem(at: fileURL)
        try FileManager.default.linkItem(at: target, to: fileURL)
        logger.log("event=hardlink-refused")
        logger.flush()
        XCTAssertEqual(try Data(contentsOf: target), original)
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o644)
    }

    func testRejectsDirectoryAndAncestorSymlinks() throws {
        let target = root.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false,
                                                attributes: [.posixPermissions: 0o755])
        let alias = fileURL.deletingLastPathComponent()
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: target)

        let direct = Logger(fileURL: fileURL)
        direct.log("event=directory-symlink-refused")
        direct.flush()
        let ancestor = Logger(fileURL: alias.appendingPathComponent("nested/retyper.log"))
        ancestor.log("event=ancestor-symlink-refused")
        ancestor.flush()

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: target.path), [])
        let attributes = try FileManager.default.attributesOfItem(atPath: target.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o755)
    }

    func testRejectsNonRegularFileWithoutBlocking() throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: false)
        XCTAssertEqual(mkfifo(fileURL.path, 0o600), 0)
        let logger = Logger(fileURL: fileURL)
        logger.log("event=fifo-refused")
        logger.flush()

        var info = stat()
        XCTAssertEqual(lstat(fileURL.path, &info), 0)
        XCTAssertEqual(info.st_mode & S_IFMT, S_IFIFO)
        try FileManager.default.removeItem(at: fileURL)
        logger.log("event=recovered")
        logger.flush()
        XCTAssertEqual(try messages(), ["event=recovered"])
    }
}
