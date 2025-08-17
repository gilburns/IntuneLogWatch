//
//  LogParser.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/10/25.
//

import Foundation

class LogParser: ObservableObject {
    @Published var isLoading = false
    @Published var analysis: LogAnalysis?
    @Published var error: String?
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss:SSS"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter
    }()
    
    func parseLogFile(at url: URL) {
        isLoading = true
        error = nil
        
        Task {
            do {
                // Start accessing security-scoped resource
                guard url.startAccessingSecurityScopedResource() else {
                    await MainActor.run {
                        self.error = "Unable to access the selected file. Please try again."
                        self.isLoading = false
                    }
                    return
                }
                
                defer {
                    url.stopAccessingSecurityScopedResource()
                }
                
                let content = try String(contentsOf: url, encoding: .utf8)
                let sourceTitle = url.lastPathComponent
                
                // Validate that this appears to be an Intune log file
                let validationResult = validateIntuneLogFile(content: content, filename: sourceTitle)
                if !validationResult.isValid {
                    await MainActor.run {
                        self.error = validationResult.errorMessage
                        self.isLoading = false
                    }
                    return
                }
                
                let analysis = await parseLogContent(content, sourceTitle: sourceTitle)
                
                await MainActor.run {
                    self.analysis = analysis
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = "Failed to read log file: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    func loadLocalIntuneLogs() {
        isLoading = true
        error = nil
        
        Task {
            do {
                let intuneAgentPath = "/Library/Intune/Microsoft Intune Agent.app"
                let intuneLogPath = "/Library/Logs/Microsoft/Intune"
                let fileManager = FileManager.default
                
                // Check Intune installation status
                let intuneStatus = checkIntuneInstallation()
                
                // If no agent and no logs, device has no Intune association
                if !intuneStatus.hasAgent && !intuneStatus.hasLogs {
                    await MainActor.run {
                        self.error = """
                        This device does not appear to be enrolled in Microsoft Intune.
                        
                        • Intune Agent not found at: /Library/Intune/Microsoft Intune Agent.app
                        • No log files found at: /Library/Logs/Microsoft/Intune
                        
                        You can still open individual log files using "Open Log File..." if you have logs from another device.
                        """
                        self.isLoading = false
                    }
                    return
                }
                
                // If agent missing but logs exist, show warning but continue
                if !intuneStatus.hasAgent && intuneStatus.hasLogs {
                    // We'll show a warning in the analysis but continue processing
                }
                
                // Check if Intune logs directory exists
                guard fileManager.fileExists(atPath: intuneLogPath) else {
                    await MainActor.run {
                        self.error = "Intune logs directory not found at \(intuneLogPath)"
                        self.isLoading = false
                    }
                    return
                }
                
                // Get all log files
                let logFiles = try getIntuneLogFiles(at: intuneLogPath)
                
                guard !logFiles.isEmpty else {
                    await MainActor.run {
                        if intuneStatus.hasAgent {
                            self.error = "Intune Agent is installed but no log files found. The device may not have synced yet."
                        } else {
                            self.error = "No Intune log files found at \(intuneLogPath)"
                        }
                        self.isLoading = false
                    }
                    return
                }
                
                // Read and combine all log files
                let combinedContent = try await readAndCombineLogFiles(logFiles)
                let sourceTitle = "Local Intune Logs (\(logFiles.count) files)"
                var analysis = await parseLogContent(combinedContent, sourceTitle: sourceTitle)
                
                // Add warning if agent is missing
                if !intuneStatus.hasAgent {
                    analysis = LogAnalysis(
                        syncEvents: analysis.syncEvents,
                        totalEntries: analysis.totalEntries,
                        parseErrors: analysis.parseErrors + ["WARNING: Intune Agent not found at \(intuneAgentPath). Device may have been unenrolled from Intune."],
                        sourceTitle: analysis.sourceTitle,
                        environment: analysis.environment,
                        region: analysis.region,
                        asu: analysis.asu,
                        accountID: analysis.accountID,
                        aadTenantID: analysis.aadTenantID,
                        deviceID: analysis.deviceID,
                        macOSVers: analysis.macOSVers,
                        agentVers: analysis.agentVers,
                        platform: analysis.platform,
                        networkSummary: analysis.networkSummary
                    )
                }
                
                await MainActor.run {
                    self.analysis = analysis
                    self.isLoading = false
                }
                
            } catch {
                await MainActor.run {
                    self.error = "Failed to load local Intune logs: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }
    
    private func checkIntuneInstallation() -> (hasAgent: Bool, hasLogs: Bool) {
        let fileManager = FileManager.default
        let intuneAgentPath = "/Library/Intune/Microsoft Intune Agent.app"
        let intuneLogPath = "/Library/Logs/Microsoft/Intune"
        
        let hasAgent = fileManager.fileExists(atPath: intuneAgentPath)
        
        var hasLogs = false
        if fileManager.fileExists(atPath: intuneLogPath) {
            do {
                let logFiles = try getIntuneLogFiles(at: intuneLogPath)
                hasLogs = !logFiles.isEmpty
            } catch {
                hasLogs = false
            }
        }
        
        return (hasAgent: hasAgent, hasLogs: hasLogs)
    }
    
    private func getIntuneLogFiles(at path: String) throws -> [URL] {
        let fileManager = FileManager.default
        let directoryURL = URL(fileURLWithPath: path)
        
        let contents = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: []
        )
        
        // Filter for IntuneMDMDaemon log files and sort by modification date (newest first)
        let logFiles = contents
            .filter { url in
                let filename = url.lastPathComponent
                return filename.hasPrefix("IntuneMDMDaemon") && filename.hasSuffix(".log")
            }
            .sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date.distantPast
                return date1 > date2 // Newest first
            }
        
        return logFiles
    }
    
    private func readAndCombineLogFiles(_ urls: [URL]) async throws -> String {
        var combinedContent = ""
        var logEntries: [(content: String, date: Date)] = []
        
        // Read all files and extract their content with timestamps
        for url in urls {
            let content = try String(contentsOf: url, encoding: .utf8)
            
            // Get the first timestamp from the file to help with sorting
            let lines = content.components(separatedBy: .newlines)
            var firstTimestamp = Date.distantPast
            
            for line in lines {
                if let timestamp = extractTimestamp(from: line) {
                    firstTimestamp = timestamp
                    break
                }
            }
            
            logEntries.append((content: content, date: firstTimestamp))
        }
        
        // Sort by first timestamp (oldest first for chronological order)
        logEntries.sort { $0.date < $1.date }
        
        // Combine all content
        combinedContent = logEntries.map { $0.content }.joined(separator: "\n")
        
        return combinedContent
    }
    
    private func extractTimestamp(from line: String) -> Date? {
        let timestampPattern = "^(\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}:\\d{3})"
        
        if let regex = try? NSRegularExpression(pattern: timestampPattern),
           let match = regex.firstMatch(in: line, options: [], range: NSRange(location: 0, length: line.count)) {
            let range = Range(match.range(at: 1), in: line)!
            let timestampString = String(line[range])
            return dateFormatter.date(from: timestampString)
        }
        
        return nil
    }
    
    private func parseLogContent(_ content: String, sourceTitle: String = "Unknown") async -> LogAnalysis {
        let lines = content.components(separatedBy: .newlines)
        var entries: [LogEntry] = []
        var parseErrors: [String] = []
        
        var currentEntry: (components: [String], additionalLines: [String])? = nil
        
        for (index, line) in lines.enumerated() {
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            
            // Check if this line starts a new log entry (has timestamp format)
            if isNewLogEntry(line) {
                // Process the previous entry if it exists
                if let current = currentEntry {
                    if let entry = buildLogEntry(from: current.components, additionalLines: current.additionalLines, rawLines: [current.components.joined(separator: " | ")] + current.additionalLines) {
                        if entry.component != "AppPolicyResultsReporter" {
                            entries.append(entry)
                        }
                    } else {
                        parseErrors.append("Line \(index): Failed to parse multi-line log entry")
                    }
                }
                
                // Start new entry
                let components = line.components(separatedBy: " | ")
                if components.count >= 5 {
                    currentEntry = (components: components, additionalLines: [])
                } else {
                    parseErrors.append("Line \(index + 1): Invalid log entry format")
                    currentEntry = nil
                }
            } else {
                // This is a continuation line
                if currentEntry != nil {
                    currentEntry!.additionalLines.append(line)
                } else {
                    parseErrors.append("Line \(index + 1): Orphaned continuation line")
                }
            }
        }
        
        // Process the final entry
        if let current = currentEntry {
            if let entry = buildLogEntry(from: current.components, additionalLines: current.additionalLines, rawLines: [current.components.joined(separator: " | ")] + current.additionalLines) {
                entries.append(entry)
            } else {
                parseErrors.append("Final entry: Failed to parse multi-line log entry")
            }
        }
        
        let syncEvents = await extractSyncEvents(from: entries)
        
        // Extract enrollment information
        let enrollmentInfo = extractEnrollmentInfo(from: content)
        
        // Extract network connectivity summary
        let networkSummary = extractNetworkSummary(from: content)
        
        return LogAnalysis(
            syncEvents: syncEvents,
            totalEntries: entries.count,
            parseErrors: parseErrors,
            sourceTitle: sourceTitle,
            environment: enrollmentInfo.environment,
            region: enrollmentInfo.region,
            asu: enrollmentInfo.asu,
            accountID: enrollmentInfo.accountID,
            aadTenantID: enrollmentInfo.aadTenantID,
            deviceID: enrollmentInfo.deviceID,
            macOSVers: enrollmentInfo.macOSVers,
            agentVers: enrollmentInfo.agentVers,
            platform: enrollmentInfo.platform,
            networkSummary: networkSummary
        )
    }
    
    private func isNewLogEntry(_ line: String) -> Bool {
        // Check if line starts with timestamp pattern: YYYY-MM-DD HH:MM:SS:mmm
        let timestampPattern = "^\\d{4}-\\d{2}-\\d{2} \\d{2}:\\d{2}:\\d{2}:\\d{3}"
        
        if let regex = try? NSRegularExpression(pattern: timestampPattern) {
            let range = NSRange(location: 0, length: line.count)
            return regex.firstMatch(in: line, options: [], range: range) != nil
        }
        
        return false
    }
    
    private func buildLogEntry(from components: [String], additionalLines: [String], rawLines: [String]) -> LogEntry? {
        guard components.count >= 5 else { return nil }
        
        let timestampString = components[0]
        let process = components[1]
        let levelString = components[2]
        let threadId = components[3]
        let component = components[4]
        let baseMessage = components.dropFirst(5).joined(separator: " | ")
        
        // Combine base message with additional lines
        let fullMessage = ([baseMessage] + additionalLines).joined(separator: "\n")
        let rawLine = rawLines.joined(separator: "\n")
        
        guard let timestamp = dateFormatter.date(from: timestampString),
              let level = LogLevel(rawValue: levelString) else {
            return nil
        }
        
        return LogEntry(
            timestamp: timestamp,
            process: process,
            level: level,
            threadId: threadId,
            component: component,
            message: fullMessage,
            rawLine: rawLine
        )
    }
    
    private func extractSyncEvents(from entries: [LogEntry]) async -> [SyncEvent] {
        var syncEvents: [SyncEvent] = []
        var currentSyncEntries: [LogEntry] = []
        var syncStartTime: Date?
        
        for entry in entries {
            if entry.component == "FullSyncWorkflow" && entry.message.contains("Starting sidecar gateway service checkin") {
                if !currentSyncEntries.isEmpty, let startTime = syncStartTime {
                    let syncEvent = await buildSyncEvent(
                        startTime: startTime,
                        endTime: nil,
                        entries: currentSyncEntries
                    )
                    syncEvents.append(syncEvent)
                }
                
                currentSyncEntries = [entry]
                syncStartTime = entry.timestamp
                
            } else if entry.component == "FullSyncWorkflow" && entry.message.contains("Finished sidecar gateway service checkin") {
                currentSyncEntries.append(entry)
                
                if let startTime = syncStartTime {
                    let syncEvent = await buildSyncEvent(
                        startTime: startTime,
                        endTime: entry.timestamp,
                        entries: currentSyncEntries
                    )
                    syncEvents.append(syncEvent)
                }
                
                currentSyncEntries = []
                syncStartTime = nil
                
            } else if syncStartTime != nil {
                currentSyncEntries.append(entry)
            }
        }
        
        if !currentSyncEntries.isEmpty, let startTime = syncStartTime {
            let syncEvent = await buildSyncEvent(
                startTime: startTime,
                endTime: nil, // nil indicates sync is still in progress
                entries: currentSyncEntries
            )
            syncEvents.append(syncEvent)
        }
        
        return syncEvents
    }
    
    private func buildSyncEvent(startTime: Date, endTime: Date?, entries: [LogEntry]) async -> SyncEvent {
        let policies = await extractPolicies(from: entries)
        
        return SyncEvent(
            startTime: startTime,
            endTime: endTime,
            policies: policies,
            allEntries: entries
        )
    }
    
    private func extractPolicies(from entries: [LogEntry]) async -> [PolicyExecution] {
        var policyMap: [String: [LogEntry]] = [:]
        
        for entry in entries {
            guard let policyId = entry.policyId else { continue }
            policyMap[policyId, default: []].append(entry)
        }
        
        var policies: [PolicyExecution] = []
        
        for (policyId, policyEntries) in policyMap {
            let sortedEntries = policyEntries.sorted { $0.timestamp < $1.timestamp }
            
            let type = PolicyType.fromComponent(sortedEntries.first?.component)
            let bundleId = sortedEntries.compactMap { $0.bundleId }.first
            let appName = sortedEntries.compactMap { $0.appName }.first
            let appType = sortedEntries.compactMap { $0.appType }.first
            let appIntent = sortedEntries.compactMap { $0.appIntent }.first
            let scriptType = sortedEntries.compactMap { $0.scriptType }.first
            let executionContext = sortedEntries.compactMap { $0.executionContext }.first
            
            let startTime = sortedEntries.first?.timestamp
            let endTime = getEndTime(for: sortedEntries, type: type)
            
            let status = determineStatus(for: sortedEntries, type: type)
            
            let policy = PolicyExecution(
                policyId: policyId,
                type: type,
                bundleId: bundleId,
                appName: appName,
                appType: appType,
                appIntent: appIntent,
                scriptType: scriptType,
                executionContext: executionContext,
                status: status,
                startTime: startTime,
                endTime: endTime,
                entries: sortedEntries
            )

            policies.append(policy)
        }
        
        return policies.sorted { $0.startTime ?? Date.distantPast < $1.startTime ?? Date.distantPast }
    }
    
    private func getEndTime(for entries: [LogEntry], type: PolicyType) -> Date? {
        switch type {
        case .app:
            return entries.last { $0.message.contains("Handling app policy finished") }?.timestamp
        case .script:
            return entries.last { $0.message.contains("policy ran") }?.timestamp
        case .unknown:
            return entries.last?.timestamp
        }
    }
    
    private func extractEnrollmentInfo(from content: String) -> (environment: String?, region: String?, asu: String?, accountID: String?, aadTenantID: String?, deviceID: String?, macOSVers: String?, agentVers: String?, platform: String?) {
        let lines = content.components(separatedBy: .newlines)
        
        var environment: String?
        var region: String?
        var asu: String?
        var accountID: String?
        var aadTenantID: String?
        var deviceID: String?
        var macOSVers: String?
        var agentVers: String?
        var platform: String?

        for line in lines {
            // Look for VerifyEnrollmentStatus lines with enrollment information

            if line.contains("VerifyEnrollmentStatus") && line.contains("Successfully verified enrollment status") {
                                                
                // Extract Environment
                if let envRange = line.range(of: "Environment: ([^,]+)", options: .regularExpression) {
                    let envMatch = String(line[envRange])
                    environment = envMatch.replacingOccurrences(of: "Environment: ", with: "")
                }
                
                // Extract Region
                if let regionRange = line.range(of: "Region: ([^,]+)", options: .regularExpression) {
                    let regionMatch = String(line[regionRange])
                    region = regionMatch.replacingOccurrences(of: "Region: ", with: "")
                }
                
                // Extract ASU
                if let asuRange = line.range(of: "ASU: ([^,]+)", options: .regularExpression) {
                    let asuMatch = String(line[asuRange])
                    asu = asuMatch.replacingOccurrences(of: "ASU: ", with: "")
                }

                // Extract AccountID
                if let accountRange = line.range(of: "AccountID: ([a-fA-F0-9-]+)", options: .regularExpression) {
                    let accountMatch = String(line[accountRange])
                    accountID = accountMatch.replacingOccurrences(of: "AccountID: ", with: "")
                }

                // Extract AADTenantID (Entra Tenant ID)
                if let tenantRange = line.range(of: "AADTenantID: ([a-fA-F0-9-]+)", options: .regularExpression) {
                    let tenantMatch = String(line[tenantRange])
                    aadTenantID = tenantMatch.replacingOccurrences(of: "AADTenantID: ", with: "")
                }
            }
            
            if line.contains("VerifyEnrollmentStatus") && line.contains("Successfully verified device status") {
                                
                // Extract Device ID
                if let deviceRange = line.range(of: "DeviceId: ([^,]+)", options: .regularExpression) {
                    let deviceMatch = String(line[deviceRange])
                    deviceID = deviceMatch.replacingOccurrences(of: "DeviceId: ", with: "")
                }
                
                // macOS Version
                if let macOSRange = line.range(of: "OSVersionActual: ([^,]+)", options: .regularExpression) {
                    let macOSMatch = String(line[macOSRange])
                    macOSVers = macOSMatch.replacingOccurrences(of: "OSVersionActual: ", with: "")
                }

                // Agent Version
                if let agentRange = line.range(of: "VersionInstalled: ([^,]+)", options: .regularExpression) {
                    let agentMatch = String(line[agentRange])
                    agentVers = agentMatch.replacingOccurrences(of: "VersionInstalled: ", with: "")
                }
            }
            
            if line.contains("VerifyEnrollmentStatus") && line.contains("Successfully verified MDM server info") {
                
                // MDM Server Platform
                if let platformRange = line.range(of: "Platform=([^,]+)", options: .regularExpression) {
                    let platformMatch = String(line[platformRange])
                    platform = platformMatch.replacingOccurrences(of: "Platform=", with: "")
                }
            }
            
            // Return match when we have all values
            if (environment != nil || region != nil || asu != nil || accountID != nil || aadTenantID != nil) && (deviceID != nil || macOSVers != nil || agentVers != nil) {
                return (environment, region, asu, accountID, aadTenantID, deviceID, macOSVers, agentVers, platform)
            }

        }
        
        return (nil, nil, nil, nil, nil, nil, nil, nil, nil)
    }
    
    private func extractNetworkSummary(from content: String) -> NetworkSummary? {
        let lines = content.components(separatedBy: .newlines)
        var interfaceStats: [String: Int] = [:]
        var noConnectionCount = 0
        var totalChecks = 0
        
        for line in lines {
            if line.contains("ObserveNetworkInterface") {
                totalChecks += 1
                
                if line.contains("No internet connection") {
                    noConnectionCount += 1
                } else if line.contains("Internet connection available. Context:") {
                    // Extract the interface(s) from the Context array
                    if let contextRange = line.range(of: "Context: \\[\"([^\\]]+)\"\\]", options: .regularExpression) {
                        let contextMatch = String(line[contextRange])
                        // Extract content between ["..."]
                        if let interfaceRange = contextMatch.range(of: "\\[\"(.+)\"\\]", options: .regularExpression) {
                            let interfaceString = String(contextMatch[interfaceRange])
                            let cleanInterface = interfaceString
                                .replacingOccurrences(of: "[\"", with: "")
                                .replacingOccurrences(of: "\"]", with: "")
                            
                            // Handle multiple interfaces separated by commas
                            let interfaces = cleanInterface.components(separatedBy: "\", \"")
                            for interface in interfaces {
                                let cleanedInterface = interface.trimmingCharacters(in: .whitespacesAndNewlines)
                                interfaceStats[cleanedInterface, default: 0] += 1
                            }
                        }
                    }
                }
            }
        }
        
        guard totalChecks > 0 else { return nil }
        
        return NetworkSummary(
            totalNetworkChecks: totalChecks,
            interfaceStats: interfaceStats,
            noConnectionCount: noConnectionCount
        )
    }
    
    private func determineStatus(for entries: [LogEntry], type: PolicyType) -> PolicyStatus {
        if entries.contains(where: { $0.level == .error }) {
            return .failed
        }
        
        if entries.contains(where: { $0.message.contains("Not running script policy because this policy has already been run.") }) || entries.contains(where: { $0.message.contains("Finished management script.") })
        {
            return .completed
        }
            
        if entries.contains(where: { $0.level == .warning }) {
            if getEndTime(for: entries, type: type) != nil {
                return .warning
            } else {
                return .running
            }
        }
        
        if getEndTime(for: entries, type: type) != nil {
            if entries.contains(where: { $0.message.contains("Status: Success") }) ||
               entries.contains(where: { $0.message.contains("Handling app policy finished") })
            {
                return .completed
            } else {
                return .warning
            }
        }
        
        return .running
    }
    
    private func validateIntuneLogFile(content: String, filename: String) -> (isValid: Bool, errorMessage: String) {
        let lines = content.components(separatedBy: .newlines).prefix(50) // Check first 50 lines
        
        var hasTimestampFormat = false
        var hasProcessColumn = false
        var hasIntuneDaemon = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines and header lines (support logs)
            guard !trimmedLine.isEmpty && !trimmedLine.hasPrefix("===") else {
                continue
            }
            
            // Check timestamp format: YYYY-MM-DD HH:MM:SS (flexible - allow with or without milliseconds)
            if line.range(of: #"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}"#, options: .regularExpression) != nil {
                hasTimestampFormat = true
            }
            
            // Check for pipe-delimited format with process column
            let components = line.components(separatedBy: " | ")
            if components.count >= 5 {
                hasProcessColumn = true
                
                // Check if process column contains IntuneMDMDaemon or IntuneMDM-Daemon
                if components[1].contains("IntuneMDMDaemon") || components[1].contains("IntuneMDM-Daemon") {
                    hasIntuneDaemon = true
                }
            }
            
            // If we found all the basic requirements, we can stop early
            if hasTimestampFormat && hasProcessColumn && hasIntuneDaemon {
                break
            }
        }
        
        // Determine if this looks like an Intune log file
        let hasCorrectFormat = hasTimestampFormat && hasProcessColumn
        let hasIntuneContent = hasIntuneDaemon
        
        if !hasCorrectFormat {
            return (false, """
                This file does not appear to be a valid log file format.
                
                Expected format: timestamp | process | level | thread | component | message
                
                Log files should have:
                • Timestamp format: YYYY-MM-DD HH:MM:SS
                • Pipe-delimited columns (at least 5 columns)
                
                Please select a valid log file.
                """)
        }
        
        if !hasIntuneContent {
            return (false, """
                This file appears to be in the correct log format but does not contain Intune-specific content.
                
                Expected: "IntuneMDMDaemon" or "IntuneMDM-Daemon" in the process column
                
                Please select a valid Intune log file from /Library/Logs/Microsoft/Intune/
                (typically named "IntuneMDMDaemon*.log" or support log collections)
                """)
        }
        
        return (true, "")
    }
}

extension PolicyType {
    static func fromComponent(_ component: String?) -> PolicyType {
        switch component {
        case "AppPolicyHandler":
            return .app
        case "ScriptPolicyRunner", "AdHocScriptProcessor":
            return .script
        default:
            return .unknown
        }
    }
}
