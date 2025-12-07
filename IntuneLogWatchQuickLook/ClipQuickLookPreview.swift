//
//  ClipQuickLookPreview.swift
//  IntuneLogWatchQuickLook
//
//  Created by Gil Burns on 11/30/25.
//

import SwiftUI

// MARK: - Quick Look Preview View

struct ClipQuickLookPreview: View {
    let event: ClippedPolicyEvent
    @State private var showingRawLogs = false

    // Store policy as a let property
    private let policy: PolicyExecution

    init(event: ClippedPolicyEvent) {
        self.event = event
        self.policy = event.policyExecution.toPolicyExecution()
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with clip info
            clipInfoHeader

            Divider()

            // Policy Details
            policyHeader

            // Toggle between Timeline and Raw Logs
            HStack {
                Button(action: { showingRawLogs.toggle() }) {
                    Label(showingRawLogs ? "Timeline View" : "Raw Logs",
                          systemImage: showingRawLogs ? "timeline.selection" : "doc.plaintext")
                }
                .buttonStyle(BorderedButtonStyle())

                Spacer()

                Text("\(policy.entries.count) log entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()

            if showingRawLogs {
                rawLogView
            } else {
                timelineView
            }
        }
    }

    // MARK: - Clip Info Header

    private var clipInfoHeader: some View {
        HStack(alignment: .top, spacing: 1) {
            VStack {
                Text("Quick Look Preview")
                    .rotationEffect(.degrees(-90))
                    .padding(.leading, -36)
                    .padding(.trailing, -36)
                    .offset(x: 0, y: 0)
                    .font(.caption2)
                    .foregroundColor(.secondary)

            }
            .frame(height: 105)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Custom Title
                        if !event.customName.isEmpty {
                            Text(event.customName)
                                .font(event.customName.count > 27 ? .title3 : .title2)
                                .fontWeight(.semibold)
                        } else {
                            Text(policy.displayName)
                                .font(policy.displayName.count > 27 ? .title3 : .title2)
                                .fontWeight(.semibold)
                        }

                        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 4) {
                            GridRow {
                                Image(systemName: "scissors")
                                    .font(.caption)
                                    .foregroundColor(.blue)

                                Text("Clipped: \(formatDateTime(event.clippedDate))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                EmptyView()
                            }

                            if !event.notes.isEmpty {
                                GridRow {
                                    Image(systemName: "doc")
                                        .font(.caption)
                                        .foregroundColor(.blue)

                                    Text("Notes:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }

                        if !event.notes.isEmpty {
                            HStack {
                                Spacer()
                                    .frame(width: 40)

                                Text(event.notes)
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .padding(.top, -4)
                            }
                        }
                    }

                    Spacer()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
        }
    }

    // MARK: - Policy Header

    private var policyHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                AppIconView(
                    bundleId: policy.bundleId,
                    policyType: policy.type,
                    size: 42
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(policy.displayName)
                        .font(policy.displayName.count > 27 ? .title3 : .title2)
                        .fontWeight(.semibold)

                    if let bundleId = policy.bundleId, bundleId != policy.displayName {
                        Text(bundleId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                statusBadge
            }
            .padding(.top, -10)

            HStack(spacing: 16) {
                if let startTime = policy.startTime {
                    detailMetric(label: "Event Date", value: formatDate(startTime), icon: "calendar", color: .purple)
                }

                if let startTime = policy.startTime {
                    detailMetric(label: "Started", value: formatTime(startTime), icon: "clock", color: .blue)
                }

                if let endTime = policy.endTime {
                    detailMetric(label: "Completed", value: formatTime(endTime), icon: "checkmark.circle", color: .green)
                }

                if let duration = policy.duration {
                    detailMetric(label: "Duration", value: formatDuration(duration), icon: "timer", color: .orange)
                }

                Spacer()
            }
            .padding(.bottom, -5)

            HStack(spacing: 16) {
                policyIdDisplay
            }
            .padding(.bottom, -4)

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    HStack(spacing: 4) {
                        Image(systemName: "info.bubble")
                            .foregroundColor(.secondary)
                            .font(.caption)

                        Text("Policy Type")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    policyTypeTiles

                }
                Spacer()
                policyIssueStatus
            }
            .padding(.bottom, -4)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    // MARK: - Supporting Views

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
        case .completed: return .green
        case .failed: return .red
        case .warning: return .orange
        case .running: return .blue
        case .pending: return .secondary
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

    private var policyIdDisplay: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "number")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Policy ID")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, -2)

                Text(policy.policyId)
                    .font(.caption)
                    .fontWeight(.medium)
                    .textSelection(.enabled)
                    .lineLimit(1)
            }
        }
    }

    private var policyIssueStatus: some View {
        VStack(alignment: .leading) {
            if policy.hasErrors || policy.hasWarnings || policy.hasAppInstallationErrors {
                HStack(alignment: .bottom, spacing: 12) {
                    Text("")
                        .font(.caption)
                        .foregroundColor(.red)
                }

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

                    HStack {
                        Text("  ")
                        if errorCodes.isEmpty {
                            Label("Error", systemImage: "app.badge.checkmark")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Label("Error:", systemImage: "app.badge.checkmark")
                                .font(.caption)
                                .foregroundColor(.red)

                            ForEach(errorCodes, id: \.self) { code in
                                Text(code)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }
            } else {
                Text("  ")
                    .font(.caption)
                    .foregroundColor(.red)

                HStack(alignment: .bottom, spacing: 12) {
                    Label("No Issues Detected", systemImage: "app.badge.checkmark")
                        .font(.caption)
                        .foregroundColor(.green.opacity(0.8))
                }
            }
        }
    }

    private var policyTypeTiles: some View {
        HStack(spacing: 4) {
            // Main policy type
            Text(policy.type.displayName)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.cyan.opacity(0.3))
                .foregroundColor(.cyan)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white, lineWidth: 0.5)
                )

            // App type indicator
            if let appType = policy.appType {
                Text(appType)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(appType == "PKG" ? Color.green.opacity(0.2) : Color.purple.opacity(0.2))
                    .foregroundColor(appType == "PKG" ? .green : .purple)
                    .cornerRadius(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white, lineWidth: 0.5)
                    )
            }

            // App intent indicator
            if let appIntent = policy.appIntent {
                Text(intentDisplayName(appIntent))
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(intentColor(appIntent).opacity(0.2))
                    .foregroundColor(intentColor(appIntent))
                    .cornerRadius(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white, lineWidth: 0.5)
                    )
            }

            // Script type indicator
            if let scriptType = policy.scriptType {
                Text(scriptType == "Custom Attribute" ? "ATTR" : "SCRIPT")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(scriptType == "Custom Attribute" ? Color.orange.opacity(0.2) : Color.teal.opacity(0.2))
                    .foregroundColor(scriptType == "Custom Attribute" ? .orange : .teal)
                    .cornerRadius(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white, lineWidth: 0.5)
                    )
            }

            // Execution context indicator
            if policy.type == .script, let executionContext = policy.executionContext {
                Text(executionContext.uppercased())
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(contextColor(executionContext).opacity(0.2))
                    .foregroundColor(contextColor(executionContext))
                    .cornerRadius(3)
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(Color.white, lineWidth: 0.5)
                    )
            }
        }
    }

    private var timelineView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(policy.entries) { entry in
                    TimelineEntryView(entry: entry)
                }
            }
            .padding()
        }
    }

    private var rawLogView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(policy.entries) { entry in
                    RawLogEntryView(entry: entry)
                }
            }
            .padding()
        }
    }

    // MARK: - Helper Functions

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
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

    private func intentDisplayName(_ intent: String) -> String {
        switch intent {
        case "RequiredInstall": return "REQUIRED"
        case "Available": return "AVAILABLE"
        case "Uninstall": return "UNINSTALL"
        default: return intent.uppercased()
        }
    }

    private func intentColor(_ intent: String) -> Color {
        switch intent {
        case "RequiredInstall": return .red
        case "Available": return .cyan
        case "Uninstall": return .brown
        default: return .gray
        }
    }

    private func contextColor(_ context: String) -> Color {
        switch context.lowercased() {
        case "root": return .red
        case "user": return .cyan
        default: return .gray
        }
    }
}
