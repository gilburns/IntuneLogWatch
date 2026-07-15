//
//  LOBModels.swift
//  IntuneLogWatch
//
//  LOB (Line of Business) app deployment models for managed PKG apps
//  deployed via Apple's native MDM channel (mdmclient).
//

import Foundation
import SwiftUI

// DeploymentChannel is defined in Models.swift (shared with CLI target)

// MARK: - Log Source Types

enum LogSourceType: String {
    case mdmDaemon          // Existing: IntuneMDMDaemon*.log
    case unifiedLog         // NEW: macOS unified log (mdmclient)
    case installLog         // NEW: /var/log/install.log
    case installHistory     // NEW: InstallHistory.plist
}

// MARK: - Sidebar Event (unified wrapper for agent sync + LOB events)

enum SidebarEvent: Identifiable, Hashable {
    case agentSync(SyncEvent)
    case lobInstall(LOBAppEvent)

    var id: UUID {
        switch self {
        case .agentSync(let syncEvent): return syncEvent.id
        case .lobInstall(let lobEvent): return lobEvent.id
        }
    }

    var timestamp: Date {
        switch self {
        case .agentSync(let syncEvent): return syncEvent.startTime
        case .lobInstall(let lobEvent): return lobEvent.timestamp
        }
    }
}

// MARK: - Channel Badge

struct ChannelBadge: View {
    let channel: DeploymentChannel

    var body: some View {
        Text(channel.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor.opacity(0.15))
            .foregroundColor(badgeColor)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white, lineWidth: 0.5)
            )
    }

    private var badgeColor: Color {
        switch channel {
        case .managedLOB: return .indigo
        case .agent: return .teal
        case .unknown: return .secondary
        }
    }
}

// MARK: - LOB Deployment Status

enum LOBDeploymentStatus: String, CaseIterable {
    case pending = "Pending"
    case downloading = "Downloading"
    case installing = "Installing"
    case completed = "Completed"
    case failed = "Failed"
    case unknown = "Unknown"

    var displayName: String { rawValue }
}

// MARK: - Unified Log Entry (from mdmclient)

struct UnifiedLogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let process: String       // mdmclient, storedownloadd, installer, etc.
    let subsystem: String     // com.apple.ManagedClient
    let category: String
    let level: UnifiedLogLevel
    let message: String

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: UnifiedLogEntry, rhs: UnifiedLogEntry) -> Bool {
        lhs.id == rhs.id
    }
}

enum UnifiedLogLevel: String, CaseIterable {
    case `default` = "Default"
    case info = "Info"
    case debug = "Debug"
    case error = "Error"
    case fault = "Fault"

    init(fromLogShow value: String) {
        switch value.lowercased() {
        case "default": self = .default
        case "info": self = .info
        case "debug": self = .debug
        case "error": self = .error
        case "fault": self = .fault
        default: self = .default
        }
    }
}

// MARK: - Install Log Entry (from /var/log/install.log)

struct InstallLogEntry: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let process: String       // installer, mdmclient, etc.
    let message: String
    let packagePath: String?
    let result: String?       // success/failure indicator

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: InstallLogEntry, rhs: InstallLogEntry) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Package Receipt Info (from InstallHistory.plist)

struct LOBPackageReceipt: Identifiable, Hashable {
    let id = UUID()
    let packageIdentifiers: [String]
    let displayName: String
    let displayVersion: String
    let installDate: Date
    let processName: String   // "mdmclient" for MDM-pushed installs

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: LOBPackageReceipt, rhs: LOBPackageReceipt) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - LOB App Deployment Event

struct LOBAppEvent: Identifiable, Hashable {
    let id = UUID()
    let timestamp: Date
    let appName: String?
    let packageId: String?
    let mdmCommandUUID: String?
    var status: LOBDeploymentStatus
    var unifiedLogEntries: [UnifiedLogEntry]
    var installLogEntries: [InstallLogEntry]
    var receiptInfo: LOBPackageReceipt?

    var displayName: String {
        if let name = appName, !name.isEmpty {
            return name
        } else if let receipt = receiptInfo {
            return receipt.displayName
        } else if let pkgId = packageId {
            return pkgId
        } else if let uuid = mdmCommandUUID {
            return "MDM Command \(uuid.prefix(8))..."
        } else {
            return "Unknown LOB App"
        }
    }

    var endTime: Date? {
        let allTimestamps = unifiedLogEntries.map(\.timestamp) + installLogEntries.map(\.timestamp)
        if let receipt = receiptInfo {
            return ([receipt.installDate] + allTimestamps).max()
        }
        return allTimestamps.max()
    }

    var duration: TimeInterval? {
        guard let end = endTime else { return nil }
        return end.timeIntervalSince(timestamp)
    }

    var packageVersion: String? {
        receiptInfo?.displayVersion
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: LOBAppEvent, rhs: LOBAppEvent) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - LOB Analysis Result

struct LOBAnalysis {
    let events: [LOBAppEvent]
    let totalUnifiedLogEntries: Int
    let totalInstallLogEntries: Int
    let totalReceipts: Int
    let parseErrors: [String]
    let queryDuration: String?    // e.g. "last 24h"

    var totalEvents: Int { events.count }
    var completedEvents: Int { events.filter { $0.status == .completed }.count }
    var failedEvents: Int { events.filter { $0.status == .failed }.count }

    var successRate: Double {
        guard totalEvents > 0 else { return 0 }
        return Double(completedEvents) / Double(totalEvents) * 100
    }
}

// MARK: - Lifecycle Stage (for timeline visualization)

enum LOBLifecycleStage: String, CaseIterable {
    case mdmCommand = "MDM Command"
    case download = "Download"
    case installation = "Installation"
    case verification = "Verification"

    var icon: String {
        switch self {
        case .mdmCommand: return "arrow.down.doc"
        case .download: return "icloud.and.arrow.down"
        case .installation: return "shippingbox"
        case .verification: return "checkmark.seal"
        }
    }
}

struct LOBLifecycleStageInfo: Identifiable {
    let id = UUID()
    let stage: LOBLifecycleStage
    let status: LOBDeploymentStatus
    let timestamp: Date?
    let entries: [UnifiedLogEntry]
    let errorMessage: String?
}
