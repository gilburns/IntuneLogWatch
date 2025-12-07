//
//  ClipLibrary.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import Foundation
import SwiftUI

// MARK: - Clipped Policy Event Model

struct ClippedPolicyEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let customName: String
    let notes: String
    let clippedDate: Date
    let policyExecution: PolicyExecutionSnapshot

    // Initialize new clip from policy execution
    init(id: UUID = UUID(), customName: String, notes: String, policyExecution: PolicyExecution) {
        self.id = id
        self.customName = customName
        self.notes = notes
        self.clippedDate = Date()
        self.policyExecution = PolicyExecutionSnapshot(from: policyExecution)
    }

    // Initialize for updating existing clip (preserves id and clippedDate)
    init(id: UUID, customName: String, notes: String, clippedDate: Date, policyExecution: PolicyExecutionSnapshot) {
        self.id = id
        self.customName = customName
        self.notes = notes
        self.clippedDate = clippedDate
        self.policyExecution = policyExecution
    }

    var displayName: String {
        customName.isEmpty ? policyExecution.displayName : customName
    }
}

// MARK: - Policy Execution Snapshot (Codable version)

struct PolicyExecutionSnapshot: Codable, Hashable {
    let policyId: String
    let displayName: String
    let bundleId: String?
    let appName: String?
    let type: PolicyTypeSnapshot
    let status: PolicyStatusSnapshot
    let startTime: Date?
    let endTime: Date?
    let duration: TimeInterval?
    let hasErrors: Bool
    let hasWarnings: Bool
    let hasAppInstallationErrors: Bool
    let appErrorCodes: [String]
    let entries: [LogEntrySnapshot]
    let appType: String?
    let appIntent: String?
    let scriptType: String?
    let executionContext: String?
    let healthDomain: String?

    init(from policy: PolicyExecution) {
        self.policyId = policy.policyId
        self.displayName = policy.displayName
        self.bundleId = policy.bundleId
        self.appName = policy.appName
        self.type = PolicyTypeSnapshot(from: policy.type)
        self.status = PolicyStatusSnapshot(from: policy.status)
        self.startTime = policy.startTime
        self.endTime = policy.endTime
        self.duration = policy.duration
        self.hasErrors = policy.hasErrors
        self.hasWarnings = policy.hasWarnings
        self.hasAppInstallationErrors = policy.hasAppInstallationErrors
        self.appErrorCodes = policy.appErrorCodes
        self.entries = policy.entries.map { LogEntrySnapshot(from: $0) }
        self.appType = policy.appType
        self.appIntent = policy.appIntent
        self.scriptType = policy.scriptType
        self.executionContext = policy.executionContext
        self.healthDomain = policy.healthDomain
    }

    // Convert back to PolicyExecution for viewing
    func toPolicyExecution() -> PolicyExecution {
        return PolicyExecution(
            policyId: policyId,
            type: type.toPolicyType(),
            bundleId: bundleId,
            appName: appName,
            appType: appType,
            appIntent: appIntent,
            scriptType: scriptType,
            executionContext: executionContext,
            healthDomain: healthDomain,
            status: status.toPolicyStatus(),
            startTime: startTime,
            endTime: endTime,
            entries: entries.map { $0.toLogEntry() }
        )
    }
}

enum PolicyTypeSnapshot: String, Codable {
    case app, script, health, unknown

    init(from type: PolicyType) {
        switch type {
        case .app: self = .app
        case .script: self = .script
        case .health: self = .health
        case .unknown: self = .unknown
        }
    }

    func toPolicyType() -> PolicyType {
        switch self {
        case .app: return .app
        case .script: return .script
        case .health: return .health
        case .unknown: return .unknown
        }
    }
}

enum PolicyStatusSnapshot: String, Codable {
    case completed, failed, warning, running, pending

    init(from status: PolicyStatus) {
        switch status {
        case .completed: self = .completed
        case .failed: self = .failed
        case .warning: self = .warning
        case .running: self = .running
        case .pending: self = .pending
        }
    }

    func toPolicyStatus() -> PolicyStatus {
        switch self {
        case .completed: return .completed
        case .failed: return .failed
        case .warning: return .warning
        case .running: return .running
        case .pending: return .pending
        }
    }
}

struct LogEntrySnapshot: Codable, Hashable {
    let timestamp: Date
    let level: LogLevelSnapshot
    let process: String
    let component: String
    let threadId: String
    let message: String
    let rawLine: String
    let hasAppInstallationError: Bool
    let appErrorCode: String?

    init(from entry: LogEntry) {
        self.timestamp = entry.timestamp
        self.level = LogLevelSnapshot(from: entry.level)
        self.process = entry.process
        self.component = entry.component
        self.threadId = entry.threadId
        self.message = entry.message
        self.rawLine = entry.rawLine
        self.hasAppInstallationError = entry.hasAppInstallationError
        self.appErrorCode = entry.appErrorCode
    }

    func toLogEntry() -> LogEntry {
        return LogEntry(
            timestamp: timestamp,
            process: process,
            level: level.toLogLevel(),
            threadId: threadId,
            component: component,
            message: message,
            rawLine: rawLine
        )
    }
}

enum LogLevelSnapshot: String, Codable {
    case info, warning, error, debug

    init(from level: LogLevel) {
        switch level {
        case .info: self = .info
        case .warning: self = .warning
        case .error: self = .error
        case .debug: self = .debug
        }
    }

    func toLogLevel() -> LogLevel {
        switch self {
        case .info: return .info
        case .warning: return .warning
        case .error: return .error
        case .debug: return .debug
        }
    }
}

// MARK: - Clip Library Manager

class ClipLibraryManager: ObservableObject {
    static let shared = ClipLibraryManager()

    @Published var clippedEvents: [ClippedPolicyEvent] = []

    private let fileManager = FileManager.default
    private var storageDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let clipDir = appSupport.appendingPathComponent("IntuneLogWatch/ClippedEvents", isDirectory: true)

        // Create directory if it doesn't exist
        if !fileManager.fileExists(atPath: clipDir.path) {
            try? fileManager.createDirectory(at: clipDir, withIntermediateDirectories: true)
        }

        return clipDir
    }

    private init() {
        loadAllEvents()
    }

    // MARK: - Save Event

    func saveEvent(_ event: ClippedPolicyEvent) {
        let filename = "\(event.id.uuidString).ilwclip"
        let fileURL = storageDirectory.appendingPathComponent(filename)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(event)
            try data.write(to: fileURL)

            // Add to in-memory array
            clippedEvents.append(event)
            clippedEvents.sort { $0.clippedDate > $1.clippedDate }
        } catch {
            print("Failed to save clipped event: \(error)")
        }
    }

    // MARK: - Load Events

    func loadAllEvents() {
        do {
            let files = try fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: nil)
            let jsonFiles = files.filter { $0.pathExtension == "ilwclip" }

            var events: [ClippedPolicyEvent] = []
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            for file in jsonFiles {
                do {
                    let data = try Data(contentsOf: file)
                    let event = try decoder.decode(ClippedPolicyEvent.self, from: data)
                    events.append(event)
                } catch {
                    print("Failed to load event from \(file.lastPathComponent): \(error)")
                }
            }

            clippedEvents = events.sorted { $0.clippedDate > $1.clippedDate }
        } catch {
            print("Failed to load clipped events: \(error)")
        }
    }

    // MARK: - Update Event

    func updateEvent(_ event: ClippedPolicyEvent) {
        let filename = "\(event.id.uuidString).ilwclip"
        let fileURL = storageDirectory.appendingPathComponent(filename)

        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(event)
            try data.write(to: fileURL)

            // Update in-memory array
            if let index = clippedEvents.firstIndex(where: { $0.id == event.id }) {
                clippedEvents[index] = event
            }
        } catch {
            print("Failed to update clipped event: \(error)")
        }
    }

    // MARK: - Delete Event

    func deleteEvent(_ event: ClippedPolicyEvent) {
        let filename = "\(event.id.uuidString).ilwclip"
        let fileURL = storageDirectory.appendingPathComponent(filename)

        do {
            try fileManager.removeItem(at: fileURL)
            clippedEvents.removeAll { $0.id == event.id }
        } catch {
            print("Failed to delete event: \(error)")
        }
    }

    // MARK: - Import Event

    enum ImportResult {
        case success
        case duplicateExists(ClippedPolicyEvent)
        case invalidFileType
        case failed(Error)
    }

    func importEvent(from url: URL, overwrite: Bool = false) -> ImportResult {
        guard url.pathExtension == "ilwclip" else {
            print("Invalid file type: \(url.pathExtension)")
            return .invalidFileType
        }

        do {
            // Load and decode the clip
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let event = try decoder.decode(ClippedPolicyEvent.self, from: data)

            // Check if clip already exists
            if let existingEvent = clippedEvents.first(where: { $0.id == event.id }) {
                if !overwrite {
                    print("Clip already exists: \(event.id)")
                    return .duplicateExists(existingEvent)
                } else {
                    // Remove existing clip before importing
                    print("Overwriting existing clip: \(event.id)")
                    deleteEvent(existingEvent)
                }
            }

            // Copy file to storage directory
            let filename = "\(event.id.uuidString).ilwclip"
            let destURL = storageDirectory.appendingPathComponent(filename)

            // Remove existing file if overwriting
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }

            try FileManager.default.copyItem(at: url, to: destURL)

            // Add to in-memory array
            clippedEvents.append(event)
            clippedEvents.sort { $0.clippedDate > $1.clippedDate }

            print("Successfully imported clip: \(event.displayName)")
            return .success
        } catch {
            print("Failed to import clip: \(error)")
            return .failed(error)
        }
    }

    // MARK: - Get Storage Info

    func getStorageInfo() -> (count: Int, totalSize: String, location: String) {
        let count = clippedEvents.count

        var totalSize: Int64 = 0
        do {
            let files = try fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: [.fileSizeKey])
            for file in files {
                if let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(size)
                }
            }
        } catch {}

        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let sizeString = formatter.string(fromByteCount: totalSize)

        return (count, sizeString, storageDirectory.path)
    }
}
