//
//  UnifiedLogReader.swift
//  IntuneLogWatch
//
//  Reads macOS unified logs via `log show` to capture mdmclient
//  LOB (managed PKG) app deployment events.
//

import Foundation

class UnifiedLogReader {

    // MARK: - Public API

    /// Query mdmclient logs for InstallApplication events
    func queryLOBInstalls(since duration: String = "24h") async throws -> [UnifiedLogEntry] {
        let jsonEntries = try await runLogShow(duration: duration)
        return parseJSONEntries(jsonEntries)
    }

    /// Query with a specific start date
    func queryLOBInstalls(since date: Date) async throws -> [UnifiedLogEntry] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        let dateString = formatter.string(from: date)

        let jsonEntries = try await runLogShowSinceDate(dateString)
        return parseJSONEntries(jsonEntries)
    }

    /// Check if we can access unified logs
    func checkAccess() async -> Bool {
        do {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
            process.arguments = ["show", "--predicate", "process == \"mdmclient\"", "--last", "1m", "--style", "json"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()

            try process.run()
            process.waitUntilExit()

            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    // MARK: - Private: Run log show command

    private func runLogShow(duration: String) async throws -> [[String: Any]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--predicate", Self.mdmPredicate,
            "--info", "--debug",
            "--style", "json",
            "--last", duration
        ]

        return try await executeLogProcess(process)
    }

    private func runLogShowSinceDate(_ dateString: String) async throws -> [[String: Any]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show",
            "--predicate", Self.mdmPredicate,
            "--info", "--debug",
            "--style", "json",
            "--start", dateString
        ]

        return try await executeLogProcess(process)
    }

    private func executeLogProcess(_ process: Process) async throws -> [[String: Any]] {
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()

        // Read output asynchronously
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorString = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw UnifiedLogError.commandFailed(errorString)
        }

        guard !outputData.isEmpty else {
            return []
        }

        // Parse JSON array
        guard let json = try? JSONSerialization.jsonObject(with: outputData) as? [[String: Any]] else {
            // Sometimes log show returns empty or invalid JSON
            return []
        }

        return json
    }

    // MARK: - JSON Parsing

    private func parseJSONEntries(_ entries: [[String: Any]]) -> [UnifiedLogEntry] {
        // The timestamp format from `log show --style json` is like:
        // "2026-03-18 10:29:05.055328-0500"
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")

        let altDateFormatter = DateFormatter()
        altDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
        altDateFormatter.locale = Locale(identifier: "en_US_POSIX")

        // Timezone offset format: "2026-03-18 10:29:05.055328-0500"
        let tzDateFormatter = DateFormatter()
        tzDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        tzDateFormatter.locale = Locale(identifier: "en_US_POSIX")

        return entries.compactMap { entry -> UnifiedLogEntry? in
            guard let timestampStr = entry["timestamp"] as? String,
                  let message = entry["eventMessage"] as? String else {
                return nil
            }

            // Try parsing with timezone offset first (most common from log show)
            let cleanTimestamp = timestampStr.trimmingCharacters(in: .whitespaces)
            let timestamp = dateFormatter.date(from: cleanTimestamp)
                ?? altDateFormatter.date(from: cleanTimestamp)
                ?? parseFlexibleTimestamp(cleanTimestamp)
                ?? Date()

            // processImagePath gives full path like "/usr/libexec/mdmclient"
            let processPath = entry["processImagePath"] as? String ?? ""
            let processName = processPath.isEmpty
                ? (entry["process"] as? String ?? "unknown")
                : (processPath as NSString).lastPathComponent
            let subsystem = entry["subsystem"] as? String ?? ""
            let category = entry["category"] as? String ?? ""
            let levelStr = entry["messageType"] as? String ?? "Default"

            return UnifiedLogEntry(
                timestamp: timestamp,
                process: processName,
                subsystem: subsystem,
                category: category,
                level: UnifiedLogLevel(fromLogShow: levelStr),
                message: message
            )
        }
    }

    /// Flexible timestamp parser for edge cases
    private func parseFlexibleTimestamp(_ str: String) -> Date? {
        // Handle "2026-03-18 10:29:05.055328-0500" format
        // The issue is the timezone offset without colon: -0500 vs -05:00
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withFullTime, .withFractionalSeconds, .withTimeZone]

        // Try inserting colon in timezone offset
        if str.count > 6 {
            let sign = str[str.index(str.endIndex, offsetBy: -5)]
            if sign == "+" || sign == "-" {
                var modified = str
                modified.insert(":", at: str.index(str.endIndex, offsetBy: -2))
                // Replace space with T for ISO8601
                modified = modified.replacingOccurrences(of: " ", with: "T", range: modified.range(of: " "))
                if let date = iso.date(from: modified) {
                    return date
                }
            }
        }

        return nil
    }

    // MARK: - Predicate

    /// Combined predicate for MDM app installation events.
    /// Tightly scoped to avoid picking up general mdmclient housekeeping.
    static let mdmPredicate = """
    (process == "mdmclient" AND subsystem == "com.apple.ManagedClient" AND \
    category == "InstallApplication") OR \
    (process == "mdmclient" AND eventMessage CONTAINS "InstallApplication") OR \
    process == "storedownloadd"
    """
}

// MARK: - Errors

enum UnifiedLogError: LocalizedError {
    case commandFailed(String)
    case accessDenied

    var errorDescription: String? {
        switch self {
        case .commandFailed(let detail):
            return "Failed to query unified logs: \(detail)"
        case .accessDenied:
            return "Unable to access macOS unified logs. The app may need Full Disk Access permission."
        }
    }
}
