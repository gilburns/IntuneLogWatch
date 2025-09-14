//
//  Models.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import Foundation

enum LogLevel: String, CaseIterable {
    case info = "I"
    case warning = "W"
    case error = "E"
    case debug = "D"
    
    var displayName: String {
        switch self {
        case .info: return "Info"
        case .warning: return "Warning"
        case .error: return "Error"
        case .debug: return "Debug"
        }
    }
}

enum PolicyType: String, CaseIterable {
    case app = "AppPolicyHandler"
    case script = "ScriptPolicyRunner"
    case unknown = "Unknown"
    
    var displayName: String {
        switch self {
        case .app: return "App Policy"
        case .script: return "Script Policy"
        case .unknown: return "Other"
        }
    }
}

enum PolicyStatus: String, CaseIterable {
    case pending = "pending"
    case running = "running"
    case completed = "completed"
    case failed = "failed"
    case warning = "warning"
    
    var displayName: String {
        switch self {
        case .pending: return "Pending"
        case .running: return "Running"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .warning: return "Warning"
        }
    }
}

struct LogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let process: String
    let level: LogLevel
    let threadId: String
    let component: String
    let message: String
    let rawLine: String
    
    var policyId: String? {
        extractPolicyId(from: message)
    }
    
    var bundleId: String? {
        extractBundleId(from: message)
    }
    
    var appName: String? {
        extractAppName(from: message)
    }
    
    var appType: String? {
        extractAppType(from: message)
    }
    
    var scriptType: String? {
        extractScriptType(from: message)
    }
    
    var appIntent: String? {
        extractAppIntent(from: message)
    }
    
    var executionContext: String? {
        extractExecutionContext(from: message)
    }

    var hasAppInstallationError: Bool {
        extractAppInstallationError(from: message)
    }

    var appErrorCode: String? {
        extractAppErrorCode(from: message)
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: LogEntry, rhs: LogEntry) -> Bool {
        lhs.id == rhs.id
    }
    
    private func extractPolicyId(from message: String) -> String? {
        let patterns = [
            "PolicyID: ([a-f0-9-]{36})",
            "PolicyID:([a-f0-9-]{36})",
            "Policy measurement. ID: ([a-f0-9-]{36})"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: message, options: [], range: NSRange(location: 0, length: message.count)) {
                let range = Range(match.range(at: 1), in: message)!
                return String(message[range])
            }
        }
        return nil
    }
    
    private func extractBundleId(from message: String) -> String? {
        let patterns = [
            "BundleID: ([^,\\s]+)",
            "Primary BundleID: ([^,\\s]+)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: message, options: [], range: NSRange(location: 0, length: message.count)) {
                let range = Range(match.range(at: 1), in: message)!
                return String(message[range])
            }
        }
        return nil
    }
    
    private func extractAppName(from message: String) -> String? {
        let patterns = [
            "AppName: ([^,]+)",
            "AppName:([^,]+)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: message, options: [], range: NSRange(location: 0, length: message.count)) {
                let range = Range(match.range(at: 1), in: message)!
                return String(message[range]).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    
    private func extractAppType(from message: String) -> String? {
        let patterns = [
            "AppType: (PKG|DMG)",
            "AppType:(PKG|DMG)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: message, options: [], range: NSRange(location: 0, length: message.count)) {
                let range = Range(match.range(at: 1), in: message)!
                return String(message[range])
            }
        }
        return nil
    }
    
    private func extractScriptType(from message: String) -> String? {
        if message.contains("custom attribute policy") {
            return "Custom Attribute"
        } else if message.contains("recurring script policy") {
            return "Script Policy"
        } else if message.contains("Not running script policy") {
            return "Script Policy"
        }
        return nil
    }
    
    private func extractAppIntent(from message: String) -> String? {
        let patterns = [
            "App Policy Intent: (RequiredInstall|Available|Uninstall)",
            "App Policy Intent:(RequiredInstall|Available|Uninstall)"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: message, options: [], range: NSRange(location: 0, length: message.count)) {
                let range = Range(match.range(at: 1), in: message)!
                return String(message[range])
            }
        }
        return nil
    }
    
    private func extractExecutionContext(from message: String) -> String? {
        let patterns = [
            "ExecutionContext: (root|user)",
            "ExecutionContext:(root|user)"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: message, options: [], range: NSRange(location: 0, length: message.count)) {
                let range = Range(match.range(at: 1), in: message)!
                return String(message[range])
            }
        }
        return nil
    }

    private func extractAppInstallationError(from message: String) -> Bool {
        // Check if this is an AppResultStateChangeManager entry with ErrorCode
        guard component == "AppResultStateChangeManager" else { return false }

        // Extract the current PolicyResult section (not CachedPolicyResult)
        guard let currentPolicyResult = extractCurrentPolicyResult(from: message) else { return false }

        // Look for ErrorCode in the current PolicyResult's ComplianceStateMessage or EnforcementStateMessage
        let errorCodePatterns = [
            "\"ErrorCode\"\\s*=\\s*\"[^\"]+\"",
            "ErrorCode\\s*=\\s*\"[^\"]+\"",
            "\"ErrorCode\":\\s*\"[^\"]+\"",
            "ErrorCode:\\s*\"[^\"]+\""
        ]

        for pattern in errorCodePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               regex.firstMatch(in: currentPolicyResult, options: [], range: NSRange(location: 0, length: currentPolicyResult.count)) != nil {
                return true
            }
        }

        return false
    }

    private func extractAppErrorCode(from message: String) -> String? {
        // Check if this is an AppResultStateChangeManager entry
        guard component == "AppResultStateChangeManager" else { return nil }

        // Extract the current PolicyResult section (not CachedPolicyResult)
        guard let currentPolicyResult = extractCurrentPolicyResult(from: message) else { return nil }

        // Look for ErrorCode value in the current PolicyResult's ComplianceStateMessage or EnforcementStateMessage
        let errorCodePatterns = [
            "\"?ErrorCode\"?\\s*[=:]\\s*\"([^\"]+)\"",
            "\"?ErrorCode\"?\\s*[=:]\\s*([^,\\s;}]+)"
        ]

        for pattern in errorCodePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = regex.firstMatch(in: currentPolicyResult, options: [], range: NSRange(location: 0, length: currentPolicyResult.count)) {
                let range = Range(match.range(at: 1), in: currentPolicyResult)!
                let errorCode = String(currentPolicyResult[range]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Filter out empty values or placeholder values
                if !errorCode.isEmpty && errorCode != "0" {
                    return errorCode
                }
            }
        }

        return nil
    }

    private func extractCurrentPolicyResult(from message: String) -> String? {
        // Look for PolicyResult pattern and extract everything up to CachedPolicyResult or end of message
        let policyResultPattern = "PolicyResult:\\s*(\\[.*?)(?:,\\s*CachedPolicyResult:|$)"

        if let regex = try? NSRegularExpression(pattern: policyResultPattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: message, options: [], range: NSRange(location: 0, length: message.count)) {
            let range = Range(match.range(at: 1), in: message)!
            return String(message[range])
        }

        // Fallback: look for PolicyResult without expecting CachedPolicyResult
        let fallbackPattern = "PolicyResult:\\s*(\\[.*)"
        if let regex = try? NSRegularExpression(pattern: fallbackPattern, options: [.dotMatchesLineSeparators]),
           let match = regex.firstMatch(in: message, options: [], range: NSRange(location: 0, length: message.count)) {
            let range = Range(match.range(at: 1), in: message)!
            return String(message[range])
        }

        return nil
    }
}

struct PolicyExecution: Identifiable, Hashable {
    let id = UUID()
    let policyId: String
    let type: PolicyType
    let bundleId: String?
    let appName: String?
    let appType: String? // PKG or DMG
    let appIntent: String? // RequiredInstall, Available, Uninstall
    let scriptType: String? // Custom Attribute or Script Policy
    let executionContext: String? // root or user
    let status: PolicyStatus
    let startTime: Date?
    let endTime: Date?
    let entries: [LogEntry]
    
    var duration: TimeInterval? {
        guard let start = startTime, let end = endTime else { return nil }
        return end.timeIntervalSince(start)
    }
    
    var hasErrors: Bool {
        entries.contains { $0.level == .error }
    }
    
    var hasWarnings: Bool {
        entries.contains { $0.level == .warning }
    }

    var hasAppInstallationErrors: Bool {
        entries.contains { $0.hasAppInstallationError }
    }

    var appErrorCodes: [String] {
        entries.compactMap { $0.appErrorCode }
    }
    
    var displayName: String {
        if let appName = appName {
            return appName
        } else if let bundleId = bundleId {
            return bundleId
        } else {
            return "Policy \(policyId.prefix(8))..."
        }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: PolicyExecution, rhs: PolicyExecution) -> Bool {
        lhs.id == rhs.id
    }
}

struct SyncEvent: Identifiable, Hashable {
    let id = UUID()
    let startTime: Date
    let endTime: Date?
    let policies: [PolicyExecution]
    let allEntries: [LogEntry]
    
    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(startTime)
    }
    
    var totalPolicies: Int {
        policies.count
    }
    
    var completedPolicies: Int {
        policies.filter { $0.status == .completed }.count
    }
    
    var failedPolicies: Int {
        policies.filter { $0.status == .failed }.count
    }
    
    var warningPolicies: Int {
        policies.filter { $0.hasWarnings }.count
    }
    
    var isComplete: Bool {
        endTime != nil
    }
    
    var overallStatus: PolicyStatus {
        if failedPolicies > 0 {
            return .failed
        } else if warningPolicies > 0 {
            return .warning
        } else if isComplete {
            return .completed
        } else {
            return .running
        }
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: SyncEvent, rhs: SyncEvent) -> Bool {
        lhs.id == rhs.id
    }
}

struct NetworkSummary {
    let totalNetworkChecks: Int
    let interfaceStats: [String: Int] // Interface name -> count
    let noConnectionCount: Int
    
    var hasData: Bool {
        totalNetworkChecks > 0
    }
    
    var interfacePercentages: [String: Double] {
        guard totalNetworkChecks > 0 else { return [:] }
        return interfaceStats.mapValues { Double($0) / Double(totalNetworkChecks) * 100 }
    }
    
    var noConnectionPercentage: Double {
        guard totalNetworkChecks > 0 else { return 0 }
        return Double(noConnectionCount) / Double(totalNetworkChecks) * 100
    }
}

struct LogAnalysis {
    let syncEvents: [SyncEvent]
    let totalEntries: Int
    let parseErrors: [String]
    let sourceTitle: String // Title for tab display
    
    // Enrollment information extracted from VerifyEnrollmentStatus logs
    let environment: String?
    let region: String?
    let asu: String? 
    let accountID: String?
    let aadTenantID: String? // Entra Tenant ID
    let deviceID: String? // Intune Device ID
    let macOSVers:String?
    let agentVers: String? // Intune Agent Version
    let platform: String?
    
    // Network connectivity summary from ObserveNetworkInterface logs
    let networkSummary: NetworkSummary?

    var totalSyncEvents: Int {
        syncEvents.count
    }
    
    var completedSyncs: Int {
        syncEvents.filter { $0.isComplete }.count
    }
    
    var failedSyncs: Int {
        syncEvents.filter { $0.overallStatus == .failed }.count
    }
}
