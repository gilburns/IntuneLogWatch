//
//  InstallLogParser.swift
//  IntuneLogWatch
//
//  Parses /var/log/install.log for MDM-pushed package installation records.
//

import Foundation

class InstallLogParser {

    // MARK: - Public API

    /// Parse install.log and return entries related to MDM installs
    func parseInstallLog(since date: Date? = nil) async throws -> [InstallLogEntry] {
        let path = "/var/log/install.log"

        guard FileManager.default.fileExists(atPath: path) else {
            throw InstallLogError.fileNotFound(path)
        }

        let content = try String(contentsOfFile: path, encoding: .utf8)
        return parseContent(content, since: date)
    }

    /// Parse install.log content (useful for testing)
    func parseContent(_ content: String, since date: Date? = nil) -> [InstallLogEntry] {
        let lines = content.components(separatedBy: .newlines)
        var entries: [InstallLogEntry] = []
        var currentInstallBlock: [String] = []
        var inInstallBlock = false
        var currentPackagePath: String?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Detect install block boundaries
            if trimmed.contains("---Begin Install---") || trimmed.contains("### BEGIN") {
                inInstallBlock = true
                currentInstallBlock = [line]
                currentPackagePath = nil
                continue
            }

            if trimmed.contains("---End Install---") || trimmed.contains("### END") {
                if inInstallBlock {
                    currentInstallBlock.append(line)
                    // Process the collected block
                    let blockEntries = parseInstallBlock(currentInstallBlock, packagePath: currentPackagePath, since: date)
                    entries.append(contentsOf: blockEntries)
                }
                inInstallBlock = false
                currentInstallBlock = []
                currentPackagePath = nil
                continue
            }

            if inInstallBlock {
                currentInstallBlock.append(line)
                // Try to extract package path
                if currentPackagePath == nil, let path = extractPackagePath(from: line) {
                    currentPackagePath = path
                }
                continue
            }

            // Lines outside install blocks — parse individually if they match MDM patterns
            if let entry = parseLine(line, since: date) {
                if isMDMRelated(entry) {
                    entries.append(entry)
                }
            }
        }

        // Handle unterminated install block
        if inInstallBlock && !currentInstallBlock.isEmpty {
            let blockEntries = parseInstallBlock(currentInstallBlock, packagePath: currentPackagePath, since: date)
            entries.append(contentsOf: blockEntries)
        }

        return entries
    }

    // MARK: - Private Parsing

    /// Line format: YYYY-MM-DD HH:MM:SS-TZ process[pid]: message
    private func parseLine(_ line: String, since date: Date? = nil) -> InstallLogEntry? {
        // Pattern: 2024-03-15 10:30:45+00 installer[12345]: message
        let pattern = #"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}[+-]\d{2})\s+(\w+)\[?\d*\]?:\s+(.+)$"#

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: line.count)) else {
            return nil
        }

        guard let timestampRange = Range(match.range(at: 1), in: line),
              let processRange = Range(match.range(at: 2), in: line),
              let messageRange = Range(match.range(at: 3), in: line) else {
            return nil
        }

        let timestampStr = String(line[timestampRange])
        let process = String(line[processRange])
        let message = String(line[messageRange])

        guard let timestamp = Self.parseTimestamp(timestampStr) else {
            return nil
        }

        // Filter by date if specified
        if let since = date, timestamp < since {
            return nil
        }

        let packagePath = extractPackagePath(from: message)
        let result = extractResult(from: message)

        return InstallLogEntry(
            timestamp: timestamp,
            process: process,
            message: message,
            packagePath: packagePath,
            result: result
        )
    }

    private func parseInstallBlock(_ lines: [String], packagePath: String?, since date: Date?) -> [InstallLogEntry] {
        var entries: [InstallLogEntry] = []

        for line in lines {
            if let entry = parseLine(line, since: date) {
                // Include all entries in install blocks (they're all relevant)
                entries.append(entry)
            }
        }

        return entries
    }

    // MARK: - Helpers

    private func isMDMRelated(_ entry: InstallLogEntry) -> Bool {
        let mdmKeywords = ["mdmclient", "MDM", "ManagedClient", "InstallApplication"]
        return mdmKeywords.contains { entry.message.localizedCaseInsensitiveContains($0) }
            || entry.process.lowercased() == "mdmclient"
    }

    private func extractPackagePath(from message: String) -> String? {
        // Look for path patterns like /path/to/something.pkg
        let pathPattern = #"(/[^\s]+\.pkg)"#
        if let regex = try? NSRegularExpression(pattern: pathPattern),
           let match = regex.firstMatch(in: message, range: NSRange(location: 0, length: message.count)),
           let range = Range(match.range(at: 1), in: message) {
            return String(message[range])
        }
        return nil
    }

    private func extractResult(from message: String) -> String? {
        if message.localizedCaseInsensitiveContains("successfully installed") ||
           message.localizedCaseInsensitiveContains("install successful") ||
           message.localizedCaseInsensitiveContains("Installation successful") {
            return "success"
        }
        if message.localizedCaseInsensitiveContains("install failed") ||
           message.localizedCaseInsensitiveContains("error") ||
           message.localizedCaseInsensitiveContains("Installation failed") {
            return "failure"
        }
        return nil
    }

    static func parseTimestamp(_ str: String) -> Date? {
        // Try multiple formats
        let formatters: [DateFormatter] = [
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ssZ"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }(),
            {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd HH:mm:ss"
                f.locale = Locale(identifier: "en_US_POSIX")
                return f
            }()
        ]

        for formatter in formatters {
            if let date = formatter.date(from: str) {
                return date
            }
        }
        return nil
    }
}

// MARK: - Errors

enum InstallLogError: LocalizedError {
    case fileNotFound(String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Install log not found at \(path). This is normal if no packages have been installed recently."
        }
    }
}
