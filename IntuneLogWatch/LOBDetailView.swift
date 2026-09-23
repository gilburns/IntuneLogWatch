//
//  LOBDetailView.swift
//  IntuneLogWatch
//
//  Detail view for a selected LOB app deployment event.
//

import SwiftUI

struct LOBDetailView: View {
    let event: LOBAppEvent
    @State private var showRawLogs = false
    @State private var selectedLogSource: LOBLogSource = .all

    enum LOBLogSource: String, CaseIterable {
        case all = "All"
        case unifiedLog = "Unified Log"
        case installLog = "Install Log"
    }

    var body: some View {
        VStack(spacing: 0) {
            eventHeader
            lifecycleSection
            Divider()
            logControls
            logEntryList
        }
    }

    // MARK: - Header

    private var eventHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "shippingbox.fill")
                    .foregroundColor(.indigo)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)

                    if let pkgId = event.packageId {
                        Text(pkgId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                ChannelBadge(channel: .managedLOB)
                overallStatusBadge
            }

            HStack(spacing: 16) {
                if let version = event.packageVersion {
                    metricView(value: version, label: "Version", icon: "tag", color: .purple)
                }

                if let duration = event.duration {
                    metricView(value: formatDuration(duration), label: "Duration", icon: "clock", color: .secondary)
                }

                metricView(
                    value: "\(event.unifiedLogEntries.count)",
                    label: "Log Entries",
                    icon: "doc.text",
                    color: .blue
                )

                if !event.installLogEntries.isEmpty {
                    metricView(
                        value: "\(event.installLogEntries.count)",
                        label: "Install Logs",
                        icon: "wrench.and.screwdriver",
                        color: .green
                    )
                }

                if event.receiptInfo != nil {
                    metricView(value: "Yes", label: "Receipt", icon: "checkmark.seal", color: .green)
                }

                Spacer()
            }

            HStack {
                Text("First seen: \(formatDateTime(event.timestamp))")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if let endTime = event.endTime {
                    Text("Last activity: \(formatDateTime(endTime))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private var overallStatusBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: statusIcon)
                .foregroundColor(statusColor)
            Text(event.status.displayName)
                .fontWeight(.medium)
        }
        .font(.title3)
    }

    // MARK: - Lifecycle Timeline

    private var lifecycleSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Deployment Lifecycle")
                .font(.headline)
                .padding(.horizontal)
                .padding(.top, 8)

            DeploymentLifecycleView(stages: event.lifecycleStages)
                .padding(.horizontal)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Receipt Info

    @ViewBuilder
    private var receiptSection: some View {
        if let receipt = event.receiptInfo {
            VStack(alignment: .leading, spacing: 4) {
                Text("Package Receipt")
                    .font(.headline)
                    .padding(.horizontal)

                VStack(alignment: .leading, spacing: 2) {
                    receiptRow("Name", receipt.displayName)
                    receiptRow("Version", receipt.displayVersion)
                    receiptRow("Installed", formatDateTime(receipt.installDate))
                    receiptRow("Process", receipt.processName)
                    if !receipt.packageIdentifiers.isEmpty {
                        receiptRow("Package IDs", receipt.packageIdentifiers.joined(separator: ", "))
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }

    private func receiptRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .trailing)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
            Spacer()
        }
    }

    // MARK: - Log Controls

    private var logControls: some View {
        HStack {
            Picker("Source:", selection: $selectedLogSource) {
                ForEach(LOBLogSource.allCases, id: \.self) { source in
                    Text(source.rawValue).tag(source)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .fixedSize()

            Spacer()

            receiptSection

            Text("\(filteredLogCount) entries")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - Log Entry List

    private var filteredLogCount: Int {
        switch selectedLogSource {
        case .all: return event.unifiedLogEntries.count + event.installLogEntries.count
        case .unifiedLog: return event.unifiedLogEntries.count
        case .installLog: return event.installLogEntries.count
        }
    }

    private var logEntryList: some View {
        List {
            switch selectedLogSource {
            case .all:
                combinedLogEntries
            case .unifiedLog:
                unifiedLogEntries
            case .installLog:
                installLogEntries
            }
        }
    }

    @ViewBuilder
    private var combinedLogEntries: some View {
        let combined = buildCombinedEntries()
        ForEach(combined, id: \.id) { entry in
            CombinedLogRow(entry: entry)
        }
    }

    @ViewBuilder
    private var unifiedLogEntries: some View {
        ForEach(event.unifiedLogEntries) { entry in
            UnifiedLogRow(entry: entry)
        }
    }

    @ViewBuilder
    private var installLogEntries: some View {
        ForEach(event.installLogEntries) { entry in
            InstallLogRow(entry: entry)
        }
    }

    // MARK: - Combined entries

    private func buildCombinedEntries() -> [CombinedLogEntry] {
        var entries: [CombinedLogEntry] = []

        for entry in event.unifiedLogEntries {
            entries.append(CombinedLogEntry(
                id: entry.id,
                timestamp: entry.timestamp,
                source: .unifiedLog,
                process: entry.process,
                message: entry.message,
                level: entry.level.rawValue
            ))
        }

        for entry in event.installLogEntries {
            entries.append(CombinedLogEntry(
                id: entry.id,
                timestamp: entry.timestamp,
                source: .installLog,
                process: entry.process,
                message: entry.message,
                level: entry.result ?? ""
            ))
        }

        return entries.sorted { $0.timestamp < $1.timestamp }
    }

    // MARK: - Helpers

    private func metricView(value: String, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(value)
                    .fontWeight(.semibold)
            }
            Text(label)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    private var statusIcon: String {
        switch event.status {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .installing: return "arrow.clockwise"
        case .downloading: return "icloud.and.arrow.down"
        case .pending: return "clock"
        case .unknown: return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch event.status {
        case .completed: return .green
        case .failed: return .red
        case .installing, .downloading: return .blue
        case .pending: return .orange
        case .unknown: return .secondary
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%dm %ds", minutes, seconds)
        }
    }
}

// MARK: - Combined Log Entry Model

struct CombinedLogEntry: Identifiable {
    let id: UUID
    let timestamp: Date
    let source: LogSourceType
    let process: String
    let message: String
    let level: String
}

// MARK: - Row Views

struct CombinedLogRow: View {
    let entry: CombinedLogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            sourceIndicator
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(formatTime(entry.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(entry.process)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }
                Text(entry.message)
                    .font(.caption)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }

    private var sourceIndicator: some View {
        Circle()
            .fill(entry.source == .unifiedLog ? Color.blue : Color.green)
            .frame(width: 8, height: 8)
            .padding(.top, 4)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct UnifiedLogRow: View {
    let entry: UnifiedLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(formatTime(entry.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(entry.process)
                    .font(.caption)
                    .fontWeight(.medium)
                levelBadge
                Spacer()
            }
            Text(entry.message)
                .font(.caption)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private var levelBadge: some View {
        Text(entry.level.rawValue)
            .font(.caption2)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(levelColor.opacity(0.15))
            .foregroundColor(levelColor)
            .cornerRadius(3)
    }

    private var levelColor: Color {
        switch entry.level {
        case .error, .fault: return .red
        case .debug: return .purple
        case .info: return .blue
        case .default: return .secondary
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct InstallLogRow: View {
    let entry: InstallLogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(formatTime(entry.timestamp))
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(entry.process)
                    .font(.caption)
                    .fontWeight(.medium)
                if let result = entry.result {
                    Text(result)
                        .font(.caption2)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(result == "success" ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                        .foregroundColor(result == "success" ? .green : .red)
                        .cornerRadius(3)
                }
                Spacer()
            }
            Text(entry.message)
                .font(.caption)
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .padding(.vertical, 2)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
