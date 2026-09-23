//
//  LOBCorrelationEngine.swift
//  IntuneLogWatch
//
//  Merges data from unified logs, install.log, and InstallHistory.plist
//  into unified LOBAppEvent objects.
//

import Foundation

class LOBCorrelationEngine: ObservableObject {
    @Published var isLoading = false
    @Published var analysis: LOBAnalysis?
    @Published var error: String?

    private let unifiedLogReader = UnifiedLogReader()
    private let installLogParser = InstallLogParser()
    private let installHistoryParser = InstallHistoryParser()

    // MARK: - Public API

    /// Load and correlate all LOB data sources
    func loadLOBData(duration: String = "7d") {
        isLoading = true
        error = nil

        Task {
            do {
                let result = try await performAnalysis(duration: duration)
                await MainActor.run {
                    self.analysis = result
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    // MARK: - Analysis

    private func performAnalysis(duration: String) async throws -> LOBAnalysis {
        var parseErrors: [String] = []

        // 1. Query unified logs
        var unifiedEntries: [UnifiedLogEntry] = []
        do {
            unifiedEntries = try await unifiedLogReader.queryLOBInstalls(since: duration)
        } catch {
            parseErrors.append("Unified log query failed: \(error.localizedDescription)")
        }

        // 2. Parse install.log
        var installEntries: [InstallLogEntry] = []
        do {
            // Parse entries from roughly the same time window
            let sinceDate = durationToDate(duration)
            installEntries = try await installLogParser.parseInstallLog(since: sinceDate)
        } catch {
            parseErrors.append("Install log parse failed: \(error.localizedDescription)")
        }

        // 3. Parse InstallHistory.plist
        var receipts: [LOBPackageReceipt] = []
        do {
            let sinceDate = durationToDate(duration)
            receipts = try installHistoryParser.parseMDMInstalls(since: sinceDate)
        } catch {
            parseErrors.append("InstallHistory parse failed: \(error.localizedDescription)")
        }

        // 4. Correlate into LOBAppEvents
        let events = correlate(
            unifiedEntries: unifiedEntries,
            installEntries: installEntries,
            receipts: receipts
        )

        return LOBAnalysis(
            events: events,
            totalUnifiedLogEntries: unifiedEntries.count,
            totalInstallLogEntries: installEntries.count,
            totalReceipts: receipts.count,
            parseErrors: parseErrors,
            queryDuration: duration
        )
    }

    // MARK: - Correlation Logic

    private func correlate(
        unifiedEntries: [UnifiedLogEntry],
        installEntries: [InstallLogEntry],
        receipts: [LOBPackageReceipt]
    ) -> [LOBAppEvent] {
        var events: [LOBAppEvent] = []

        // Step 1: Group unified log entries by MDM command UUID
        let groupedByCommand = groupByMDMCommand(unifiedEntries)

        // Step 2: Create events from grouped unified log entries
        for (commandUUID, entries) in groupedByCommand {
            let sortedEntries = entries.sorted { $0.timestamp < $1.timestamp }
            let appName = extractAppName(from: sortedEntries)
            let packageId = extractPackageId(from: sortedEntries)
            let status = determineStatus(from: sortedEntries)

            var event = LOBAppEvent(
                timestamp: sortedEntries.first?.timestamp ?? Date(),
                appName: appName,
                packageId: packageId,
                mdmCommandUUID: commandUUID == "unknown" ? nil : commandUUID,
                status: status,
                unifiedLogEntries: sortedEntries,
                installLogEntries: [],
                receiptInfo: nil
            )

            // Step 3: Match install.log entries by timestamp proximity
            let matchedInstallEntries = matchInstallLogEntries(
                installEntries,
                toEvent: event,
                windowSeconds: 30
            )
            event.installLogEntries = matchedInstallEntries

            // Step 4: Match receipt by package identifier or name
            if let receipt = matchReceipt(receipts, toEvent: event) {
                event.receiptInfo = receipt
                if event.status != .failed {
                    event.status = .completed
                }
            }

            events.append(event)
        }

        // Step 5: Create events from receipts that weren't matched to unified log entries
        let matchedReceiptIds = Set(events.compactMap { $0.receiptInfo?.id })
        for receipt in receipts where !matchedReceiptIds.contains(receipt.id) {
            let event = LOBAppEvent(
                timestamp: receipt.installDate,
                appName: receipt.displayName,
                packageId: receipt.packageIdentifiers.first,
                mdmCommandUUID: nil,
                status: .completed,
                unifiedLogEntries: [],
                installLogEntries: matchInstallLogEntries(installEntries, toReceipt: receipt),
                receiptInfo: receipt
            )
            events.append(event)
        }

        return events.sorted { $0.timestamp > $1.timestamp } // Newest first
    }

    // MARK: - Grouping & Extraction

    private func groupByMDMCommand(_ entries: [UnifiedLogEntry]) -> [String: [UnifiedLogEntry]] {
        var groups: [String: [UnifiedLogEntry]] = [:]

        // Only group entries that have a command UUID (actual InstallApplication events)
        for entry in entries {
            guard let uuid = extractCommandUUID(from: entry.message) else {
                continue // Skip entries without a command UUID
            }
            groups[uuid, default: []].append(entry)
        }

        return groups
    }

    private func extractCommandUUID(from message: String) -> String? {
        let uuidRegex = #"([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})"#

        // Match "InstallApplication (UUID:XXXX)" — actual Intune format
        let installAppPattern = #"InstallApplication\s*\(UUID:([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\)"#
        if let regex = try? NSRegularExpression(pattern: installAppPattern),
           let match = regex.firstMatch(in: message, range: NSRange(location: 0, length: message.count)),
           let range = Range(match.range(at: 1), in: message) {
            return String(message[range])
        }

        // Generic command UUID patterns
        let commandPattern = #"[Cc]ommand\s*(?:UUID|Id|ID)?\s*[:=]?\s*([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})"#
        if let regex = try? NSRegularExpression(pattern: commandPattern),
           let match = regex.firstMatch(in: message, range: NSRange(location: 0, length: message.count)),
           let range = Range(match.range(at: 1), in: message) {
            return String(message[range])
        }

        // Any UUID in an InstallApplication context
        if message.contains("InstallApplication") || message.contains("InstallEnterpriseApplication") {
            if let regex = try? NSRegularExpression(pattern: uuidRegex),
               let match = regex.firstMatch(in: message, range: NSRange(location: 0, length: message.count)),
               let range = Range(match.range(at: 1), in: message) {
                return String(message[range])
            }
        }

        return nil
    }

    private func extractAppName(from entries: [UnifiedLogEntry]) -> String? {
        for entry in entries {
            // Look for app name in various message patterns
            let patterns = [
                #"Installing\s+\"([^\"]+)\""#,
                #"package\s+name\s*[:=]\s*\"?([^\";\n]+)"#,
                #"DisplayName\s*[:=]\s*\"?([^\";\n]+)"#,
                #"applicationName\s*[:=]\s*\"?([^\";\n]+)"#
            ]

            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
                   let match = regex.firstMatch(in: entry.message, range: NSRange(location: 0, length: entry.message.count)),
                   let range = Range(match.range(at: 1), in: entry.message) {
                    return String(entry.message[range]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }

    private func extractPackageId(from entries: [UnifiedLogEntry]) -> String? {
        for entry in entries {
            let patterns = [
                #"packageIdentifier\s*[:=]\s*\"?([^\";\s\n]+)"#,
                #"bundleIdentifier\s*[:=]\s*\"?([^\";\s\n]+)"#,
                #"com\.[a-zA-Z0-9]+\.[a-zA-Z0-9.]+"#
            ]

            for pattern in patterns {
                if let regex = try? NSRegularExpression(pattern: pattern),
                   let match = regex.firstMatch(in: entry.message, range: NSRange(location: 0, length: entry.message.count)) {
                    let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range(at: 0)
                    if let range = Range(captureRange, in: entry.message) {
                        return String(entry.message[range])
                    }
                }
            }
        }
        return nil
    }

    private func determineStatus(from entries: [UnifiedLogEntry]) -> LOBDeploymentStatus {
        let messages = entries.map { $0.message.lowercased() }
        let levels = entries.map { $0.level }

        if levels.contains(.error) || levels.contains(.fault) {
            return .failed
        }

        if messages.contains(where: { $0.contains("successfully installed") || $0.contains("install successful") || $0.contains("installation complete") }) {
            return .completed
        }

        if messages.contains(where: { $0.contains("installing") || $0.contains("running installer") }) {
            return .installing
        }

        if messages.contains(where: { $0.contains("downloading") || $0.contains("download") }) {
            return .downloading
        }

        if messages.contains(where: { $0.contains("installapplication") || $0.contains("mdm command") }) {
            return .pending
        }

        return .unknown
    }

    // MARK: - Matching

    private func matchInstallLogEntries(
        _ installEntries: [InstallLogEntry],
        toEvent event: LOBAppEvent,
        windowSeconds: TimeInterval = 30
    ) -> [InstallLogEntry] {
        guard let eventStart = event.unifiedLogEntries.first?.timestamp,
              let eventEnd = event.unifiedLogEntries.last?.timestamp else {
            return []
        }

        let windowStart = eventStart.addingTimeInterval(-windowSeconds)
        let windowEnd = eventEnd.addingTimeInterval(windowSeconds)

        return installEntries.filter { entry in
            entry.timestamp >= windowStart && entry.timestamp <= windowEnd
        }
    }

    private func matchInstallLogEntries(
        _ installEntries: [InstallLogEntry],
        toReceipt receipt: LOBPackageReceipt
    ) -> [InstallLogEntry] {
        let windowSeconds: TimeInterval = 60
        let windowStart = receipt.installDate.addingTimeInterval(-windowSeconds)
        let windowEnd = receipt.installDate.addingTimeInterval(windowSeconds)

        return installEntries.filter { entry in
            entry.timestamp >= windowStart && entry.timestamp <= windowEnd
        }
    }

    private func matchReceipt(
        _ receipts: [LOBPackageReceipt],
        toEvent event: LOBAppEvent
    ) -> LOBPackageReceipt? {
        // Try matching by package identifier
        if let eventPkgId = event.packageId {
            if let match = receipts.first(where: { $0.packageIdentifiers.contains(eventPkgId) }) {
                return match
            }
        }

        // Try matching by app name
        if let eventName = event.appName {
            if let match = receipts.first(where: {
                $0.displayName.localizedCaseInsensitiveContains(eventName) ||
                eventName.localizedCaseInsensitiveContains($0.displayName)
            }) {
                return match
            }
        }

        // Try matching by timestamp proximity
        let eventTime = event.timestamp
        let closest = receipts.min(by: {
            abs($0.installDate.timeIntervalSince(eventTime)) < abs($1.installDate.timeIntervalSince(eventTime))
        })

        if let closest = closest, abs(closest.installDate.timeIntervalSince(eventTime)) < 300 { // 5 min window
            return closest
        }

        return nil
    }

    // MARK: - Utilities

    private func splitByTimeGap(_ entries: [UnifiedLogEntry], gapThresholdSeconds: TimeInterval) -> [[UnifiedLogEntry]] {
        let sorted = entries.sorted { $0.timestamp < $1.timestamp }
        var groups: [[UnifiedLogEntry]] = []
        var currentGroup: [UnifiedLogEntry] = []

        for entry in sorted {
            if let last = currentGroup.last,
               entry.timestamp.timeIntervalSince(last.timestamp) > gapThresholdSeconds {
                groups.append(currentGroup)
                currentGroup = [entry]
            } else {
                currentGroup.append(entry)
            }
        }

        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }

        return groups
    }

    private func durationToDate(_ duration: String) -> Date? {
        // Parse duration strings like "24h", "7d", "1h"
        let pattern = #"(\d+)([hHdDmM])"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: duration, range: NSRange(location: 0, length: duration.count)),
              let valueRange = Range(match.range(at: 1), in: duration),
              let unitRange = Range(match.range(at: 2), in: duration),
              let value = Double(String(duration[valueRange])) else {
            return nil
        }

        let unit = String(duration[unitRange]).lowercased()
        let seconds: TimeInterval
        switch unit {
        case "m": seconds = value * 60
        case "h": seconds = value * 3600
        case "d": seconds = value * 86400
        default: return nil
        }

        return Date().addingTimeInterval(-seconds)
    }
}
