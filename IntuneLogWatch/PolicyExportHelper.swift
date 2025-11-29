//
//  PolicyExportHelper.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import Foundation
import SwiftUI
import PDFKit
import AppKit
import UniformTypeIdentifiers

struct PolicyExportHelper {

    // MARK: - Export to Log File

    static func exportPolicyLogs(policy: PolicyExecution, syncEvent: SyncEvent?) {
        guard !policy.entries.isEmpty else { return }

        // Generate filename based on policy name and date
        let sanitizedPolicyName = sanitizeFilename(policy.displayName)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let dateString = policy.startTime.map { dateFormatter.string(from: $0) } ?? "unknown_date"
        let suggestedFilename = "\(sanitizedPolicyName)_\(dateString).log"

        // Create NSSavePanel
        let savePanel = NSSavePanel()
        savePanel.title = "Export Log Entries"
        savePanel.message = "Choose where to save the log file"
        savePanel.nameFieldStringValue = suggestedFilename
        // Use a concrete UTType for allowed content types
        savePanel.allowedContentTypes = [UTType.plainText]
        savePanel.canCreateDirectories = true

        // Show the save panel
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            // Generate log content from entries
            var logLines = policy.entries.map { $0.rawLine }

            // Add sync event boundary markers for FullSyncWorkflow events
            if let syncEvent = syncEvent, syncEvent.eventType == .fullSync {
                let logDateFormatter = DateFormatter()
                logDateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss:SSS"

                // Create start marker
                let startTimestamp = logDateFormatter.string(from: syncEvent.startTime)
                let startMarker = "\(startTimestamp) | IntuneMDM-Daemon | I | 00000000 | FullSyncWorkflow | Starting sidecar gateway service checkin"
                logLines.insert(startMarker, at: 0)

                // Create end marker (use endTime if available, otherwise use last entry time)
                let endTime = syncEvent.endTime ?? syncEvent.startTime
                let endTimestamp = logDateFormatter.string(from: endTime)
                let endMarker = "\(endTimestamp) | IntuneMDM-Daemon | I | 00000000 | FullSyncWorkflow | Finished sidecar gateway service checkin"
                logLines.append(endMarker)
            }

            let logContent = logLines.joined(separator: "\n")

            do {
                try logContent.write(to: url, atomically: true, encoding: .utf8)

                // Show success alert
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Export Successful"
                    alert.informativeText = "Exported \(policy.entries.count) log entries to \(url.lastPathComponent)"
                    alert.alertStyle = .informational
                    alert.addButton(withTitle: "OK")
                    alert.addButton(withTitle: "Reveal in Finder")
                    let response = alert.runModal()

                    // If user clicked "Reveal in Finder"
                    if response == .alertSecondButtonReturn {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                    }
                }
            } catch {
                // Show error alert
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "Export Failed"
                    alert.informativeText = "Failed to export log entries: \(error.localizedDescription)"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }

    // MARK: - Export to PDF

    @MainActor
    static func exportPolicyToPDF(policy: PolicyExecution) {
        guard !policy.entries.isEmpty else { return }

        // Generate filename
        let sanitizedPolicyName = sanitizeFilename(policy.displayName)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let dateString = policy.startTime.map { dateFormatter.string(from: $0) } ?? "unknown_date"
        let suggestedFilename = "\(sanitizedPolicyName)_\(dateString).pdf"

        // Create the PDF content view
        let pdfView = PDFContentView(policy: policy)

        // Use ImageRenderer to create PDF
        let renderer = ImageRenderer(content: pdfView)
        renderer.proposedSize = ProposedViewSize(width: 612, height: 792) // US Letter size in points

        // Create NSSavePanel
        let savePanel = NSSavePanel()
        savePanel.title = "Export Policy to PDF"
        savePanel.message = "Choose where to save the PDF file"
        savePanel.nameFieldStringValue = suggestedFilename
        savePanel.allowedContentTypes = [.pdf]
        savePanel.canCreateDirectories = true

        // Show the save panel
        savePanel.begin { response in
            guard response == .OK, let url = savePanel.url else { return }

            // Render to PDF
            renderer.render { size, context in
                var mediaBox = CGRect(origin: .zero, size: size)

                guard let pdfContext = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
                    return
                }

                pdfContext.beginPDFPage(nil)
                context(pdfContext)
                pdfContext.endPDFPage()
                pdfContext.closePDF()
            }

            // Show success alert
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "PDF Export Successful"
                alert.informativeText = "Policy exported to \(url.lastPathComponent)"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "OK")
                alert.addButton(withTitle: "Reveal in Finder")
                let response = alert.runModal()

                // If user clicked "Reveal in Finder"
                if response == .alertSecondButtonReturn {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                }
            }
        }
    }

    // MARK: - Helper Functions

    private static func sanitizeFilename(_ filename: String) -> String {
        // Remove or replace characters that are invalid in filenames
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        let components = filename.components(separatedBy: invalidCharacters)
        let sanitized = components.joined(separator: "_")

        // Limit length to avoid filesystem issues
        let maxLength = 200
        if sanitized.count > maxLength {
            return String(sanitized.prefix(maxLength))
        }
        return sanitized
    }
}

// MARK: - PDF Functions

// PDF Content View - similar to PolicyDetailView but for export
struct PDFContentView: View {
    let policy: PolicyExecution

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            policyHeader

            Divider()

            // Error Code Details Section (if applicable)
            if policy.hasAppInstallationErrors {
                let errorCodes = policy.appErrorCodes
                if !errorCodes.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Error Code Details")
                            .font(.headline)
                            .padding(.horizontal)

                        ForEach(errorCodes, id: \.self) { code in
                            if let errorDetails = IntuneErrorCodeLookup.shared.getErrorDetails(for: code) {
                                PDFErrorCodeDetailView(errorCode: errorDetails)
                                    .padding(.horizontal)
                            }
                        }
                    }

                    Divider()
                }
            }

            // Timeline entries
            Text("Log Timeline (\(policy.entries.count) entries)")
                .font(.headline)
                .padding(.horizontal)

            VStack(alignment: .leading, spacing: 1) {
                ForEach(policy.entries) { entry in
                    PDFTimelineEntryView(entry: entry)
                }
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 612) // US Letter width
    }

    private var policyHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                policyTypeIcon

                VStack(alignment: .leading, spacing: 2) {
                    Text(policy.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)

                    if let bundleId = policy.bundleId, bundleId != policy.displayName {
                        Text(bundleId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if let scriptType = policy.scriptType {
                        Text(scriptType == "Custom Attribute" ? "Custom Attribute" : "Script")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                statusBadge
            }

            HStack(spacing: 16) {
                if let startTime = policy.startTime {
                    detailMetric(
                        label: "Started",
                        value: formatDateTime(startTime),
                        icon: "clock",
                        color: .blue
                    )
                }

                if let endTime = policy.endTime {
                    detailMetric(
                        label: "Completed",
                        value: formatDateTime(endTime),
                        icon: "checkmark.circle",
                        color: .green
                    )
                }

                if let duration = policy.duration {
                    detailMetric(
                        label: "Duration",
                        value: formatDuration(duration),
                        icon: "timer",
                        color: .orange
                    )
                }
                Spacer()
            }

            // Policy ID (without copy button)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "number")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Policy ID")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Text(policy.policyId)
                    .font(.caption)
                    .fontWeight(.medium)
            }

            if policy.hasErrors || policy.hasWarnings || policy.hasAppInstallationErrors {
                HStack(spacing: 12) {
                    if policy.hasErrors {
                        Label("Contains Errors", systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.red)
                    }

                    if policy.hasWarnings {
                        Label("Contains Warnings", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    if policy.hasAppInstallationErrors {
                        let errorCodes = policy.appErrorCodes
                        if errorCodes.isEmpty {
                            Label("App Installation Error", systemImage: "app.badge.checkmark")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            HStack(spacing: 4) {
                                Label("App Installation Error:", systemImage: "app.badge.checkmark")
                                    .font(.caption)
                                    .foregroundColor(.red)

                                ForEach(errorCodes, id: \.self) { code in
                                    if let intCode = Int32(code) {
                                        Text("0x\(String(format: "%08X", intCode))")
                                            .font(.caption)
                                            .fontWeight(.medium)
                                            .foregroundColor(.red)
                                    }
                                }
                            }
                        }
                    }

                    Spacer()
                }
            } else {
                Label("No Issues Detected", systemImage: "app.badge.checkmark")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(8)
    }

    private var policyTypeIcon: some View {
        Group {
            switch policy.type {
            case .app:
                Image(systemName: "app.badge")
                    .foregroundColor(.blue)
                    .font(.system(size: 32))
            case .script:
                Image(systemName: "terminal")
                    .foregroundColor(.green)
                    .font(.system(size: 32))
            case .health:
                Image(systemName: "stethoscope")
                    .foregroundColor(.purple)
                    .font(.system(size: 32))
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.secondary)
                    .font(.system(size: 32))
            }
        }
    }

    private var statusBadge: some View {
        Text(policy.status.displayName.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(statusColor.opacity(0.2))
            .foregroundColor(statusColor)
            .cornerRadius(8)
    }

    private var statusColor: Color {
        switch policy.status {
        case .completed:
            return .green
        case .failed:
            return .red
        case .warning:
            return .orange
        case .running:
            return .blue
        case .pending:
            return .secondary
        }
    }

    private func detailMetric(label: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .font(.caption)
                Text(label)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1.0 {
            return String(format: "%.0f ms", duration * 1000)
        } else if duration < 60.0 {
            return String(format: "%.2f s", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%d min %d sec", minutes, seconds)
        }
    }
}

// Timeline entry for PDF
struct PDFTimelineEntryView: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            LazyVStack(spacing: 2) {
                levelIcon
                Rectangle()
                    .fill(levelColor.opacity(0.3))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 16)
            
            LazyVStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(formatTime(entry.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(entry.component)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(3)

                    if entry.hasAppInstallationError {
                        if let errorCode = entry.appErrorCode {
                            HStack(spacing: 2) {
                                Image(systemName: "app.badge.checkmark")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                Text("Error:")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                if let intCode = Int32(errorCode) {
                                    Text("0x\(String(format: "%08X", intCode))")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }

                    Spacer()

                    Text("Thread \(entry.threadId)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(entry.message)
                    .font(.caption2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 6)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
        .cornerRadius(4)
    }

    private var levelIcon: some View {
        Group {
            switch entry.level {
            case .info:
                Circle()
                    .fill(Color.blue)
                    .frame(width: 6, height: 6)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 8))
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 8))
            case .debug:
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 5, height: 5)
            }
        }
    }

    private var levelColor: Color {
        switch entry.level {
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        case .debug:
            return .secondary
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// PDF Error Code Detail View
struct PDFErrorCodeDetailView: View {
    let errorCode: IntuneErrorCode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(errorCode.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    HStack(spacing: 4) {
                        Text("Code:")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(errorCode.code) (\(errorCode.hexCode))")
                            .font(.caption2)
                            .fontWeight(.medium)
                    }
                }

                Spacer()
            }

            Text(errorCode.description)
                .font(.caption)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.blue)
                        .font(.caption2)
                    Text("Recommendation")
                        .font(.caption)
                        .fontWeight(.semibold)
                }

                Text(errorCode.recommendation)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
}
