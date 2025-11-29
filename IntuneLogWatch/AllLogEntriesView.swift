//
//  AllLogEntriesView.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 11/4/25.
//

import Foundation
import SwiftUI

struct AllLogEntriesView: View {
    let entries: [LogEntry]
    let sourceTitle: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedLogEntry: LogEntry?
    @State private var showingRawLogs = false
    @State private var detailLogEntry: LogEntry?
    @State private var searchText = ""
    @State private var debouncedSearchText = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var startDate: Date?
    @State private var endDate: Date?
    @State private var selectedLogLevel: LogLevel?
    @State private var showingFilters = false

    // Computed property for filtered entries
    private var filteredEntries: [LogEntry] {
        var result = entries

        // Text search filter (using debounced search text)
        if !debouncedSearchText.isEmpty {
            result = result.filter { entry in
                entry.message.localizedCaseInsensitiveContains(debouncedSearchText) ||
                entry.component.localizedCaseInsensitiveContains(debouncedSearchText) ||
                String(entry.threadId).contains(debouncedSearchText)
            }
        }

        // Date range filter
        if let start = startDate {
            result = result.filter { $0.timestamp >= start }
        }
        if let end = endDate {
            result = result.filter { $0.timestamp <= end }
        }

        // Log level filter
        if let level = selectedLogLevel {
            result = result.filter { $0.level == level }
        }

        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            headerView

            // Search and Filter Controls
            VStack(spacing: 8) {
                HStack {
                    TextField("Search in message, component, or thread...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                    Button(action: { showingFilters.toggle() }) {
                        Label("Filters", systemImage: showingFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .buttonStyle(BorderedButtonStyle())

                    if searchText.isEmpty && startDate == nil && endDate == nil && selectedLogLevel == nil {
                        // No filters active
                    } else {
                        Button(action: {
                            searchText = ""
                            debouncedSearchText = ""
                            searchTask?.cancel()
                            startDate = nil
                            endDate = nil
                            selectedLogLevel = nil
                        }) {
                            Label("Clear", systemImage: "xmark.circle")
                        }
                        .buttonStyle(BorderedButtonStyle())
                    }
                }

                if showingFilters {
                    VStack(spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Date Range:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            DatePicker("From", selection: Binding(
                                get: { startDate ?? entries.first?.timestamp ?? Date() },
                                set: { startDate = $0 }
                            ), displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()

                            Button(action: { startDate = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .opacity(startDate == nil ? 0 : 1)

                            Text("- To -")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button(action: { startDate = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .opacity(0)

                            DatePicker("To", selection: Binding(
                                get: { endDate ?? entries.last?.timestamp ?? Date() },
                                set: { endDate = $0 }
                            ), displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()

                            Button(action: { endDate = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .opacity(endDate == nil ? 0 : 1)

                            Spacer()
                        }

                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Quick Range:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Button("Last 5m") {
                                setTimeRange(minutes: 5)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Last 10m") {
                                setTimeRange(minutes: 10)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Last 1h") {
                                setTimeRange(hours: 1)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Last 6h") {
                                setTimeRange(hours: 6)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Last 12h") {
                                setTimeRange(hours: 12)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Last 24h") {
                                setTimeRange(hours: 24)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Last 2d") {
                                setTimeRange(days: 2)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Spacer()
                        }

                        HStack(alignment: .firstTextBaseline) {
                            Text("Log Level:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach([LogLevel.error, LogLevel.warning, LogLevel.info, LogLevel.debug], id: \.self) { level in
                                Button(action: {
                                    if selectedLogLevel == level {
                                        selectedLogLevel = nil
                                    } else {
                                        selectedLogLevel = level
                                    }
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: levelIcon(for: level))
                                            .foregroundColor(levelColor(for: level))
                                        Text(levelName(for: level))
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(selectedLogLevel == level ? Color.accentColor.opacity(0.2) : Color.gray.opacity(0.1))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            Spacer()
                        }
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 8)

            HStack {
                Button(action: { showingRawLogs.toggle() }) {
                    Label(showingRawLogs ? "Timeline View" : "Raw Logs",
                          systemImage: showingRawLogs ? "timeline.selection" : "doc.plaintext")
                }
                .buttonStyle(BorderedButtonStyle())

                Spacer()

                if filteredEntries.count != entries.count {
                    Text("\(filteredEntries.count) of \(entries.count) entries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("\(entries.count) log entries")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 8)
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .background(Color(NSColor.controlBackgroundColor))

            HStack {
                Spacer()
                Text("(Double click on a log entry to view or copy details)")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.bottom, 8)
            .background(Color(NSColor.controlBackgroundColor))

            if showingRawLogs {
                rawLogView
            } else {
                timelineView
            }
        }
        .sheet(item: $detailLogEntry) { entry in
            if let index = filteredEntries.firstIndex(where: { $0.id == entry.id }) {
                LogEntryDetailView(displayName: "All Log Entries", bundleIdentifier: "", policyType: .unknown, entries: filteredEntries, currentIndex: index)
                    .frame(minWidth: 700, minHeight: 550)
            }

        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Close") {
                    dismiss()
                }
                .frame(height: 0)
                .padding(.all, 0)
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            // Cancel any existing search task
            searchTask?.cancel()

            // Create a new task with debounce delay
            searchTask = Task {
                // Wait 0.5 seconds before updating the debounced search text
                try? await Task.sleep(nanoseconds: 500_000_000)

                // Check if task was cancelled
                if !Task.isCancelled {
                    debouncedSearchText = newValue
                }
            }
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.blue)
                    .font(.title)

                VStack(alignment: .leading, spacing: 2) {
                    Text("All Log Entries")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(sourceTitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            HStack(spacing: 16) {
                detailMetric(
                    label: "First Entry",
                    value: filteredEntries.first.map { formatDateTime($0.timestamp) } ?? "N/A",
                    icon: "clock",
                    color: .blue
                )

                detailMetric(
                    label: "Last Entry",
                    value: filteredEntries.last.map { formatDateTime($0.timestamp) } ?? "N/A",
                    icon: "clock.fill",
                    color: .green
                )

                if let firstEntry = filteredEntries.first, let lastEntry = filteredEntries.last {
                    let duration = lastEntry.timestamp.timeIntervalSince(firstEntry.timestamp)
                    detailMetric(
                        label: "Time Span",
                        value: formatDuration(duration),
                        icon: "timer",
                        color: .orange
                    )
                } else {
                    detailMetric(
                        label: "Time Span",
                        value: "N/A",
                        icon: "timer",
                        color: .orange
                    )
                }

                Spacer()
            }

            HStack(spacing: 12) {
                let errorCount = filteredEntries.filter { $0.level == .error }.count
                let warningCount = filteredEntries.filter { $0.level == .warning }.count
                let infoCount = filteredEntries.filter { $0.level == .info }.count

                Label("\(errorCount) Errors", systemImage: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(errorCount > 0 ? .red : .secondary)

                Label("\(warningCount) Warnings", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(warningCount > 0 ? .orange : .secondary)

                Label("\(infoCount) Info", systemImage: "info.circle.fill")
                    .font(.caption)
                    .foregroundColor(infoCount > 0 ? .blue : .secondary)

                Spacer()
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
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

    private var timelineView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredEntries) { entry in
                        AllEntriesTimelineView(entry: entry)
                            .background(selectedLogEntry?.id == entry.id ? Color.accentColor.opacity(0.2) : Color.clear)
                            .border(.indigo, width: 0.5)
                            .simultaneousGesture(
                                TapGesture(count: 2)
                                    .onEnded {
                                        detailLogEntry = entry
                                    }
                            )
                            .simultaneousGesture(
                                TapGesture(count: 1)
                                    .onEnded {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                            if detailLogEntry == nil {
                                                selectedLogEntry = entry
                                            }
                                        }
                                    }
                            )
                    }
                    .id("timelineTop")
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))

            }
            .onAppear {
                proxy.scrollTo("timelineTop", anchor: .top)
            }
        }
    }

    private var rawLogView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(filteredEntries) { entry in
                        AllEntriesRawLogView(entry: entry)
                            .background(selectedLogEntry?.id == entry.id ? Color.accentColor.opacity(0.2) : Color.clear)
                            .border(.indigo, width: 0.5)
                            .simultaneousGesture(
                                TapGesture(count: 2)
                                    .onEnded {
                                        detailLogEntry = entry
                                    }
                            )
                            .simultaneousGesture(
                                TapGesture(count: 1)
                                    .onEnded {
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                            if detailLogEntry == nil {
                                                selectedLogEntry = entry
                                            }
                                        }
                                    }
                            )
                    }
                    .id("rawLogTop")
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
            }
            .onAppear {
                proxy.scrollTo("rawLogTop", anchor: .top)
            }
        }
    }

    // Helper function to set time range presets
    private func setTimeRange(minutes: Int = 0, hours: Int = 0, days: Int = 0) {
        guard let lastEntry = entries.last else { return }

        var timeInterval: TimeInterval = 0
        timeInterval += TimeInterval(minutes * 60)
        timeInterval += TimeInterval(hours * 3600)
        timeInterval += TimeInterval(days * 86400)

        endDate = lastEntry.timestamp
        startDate = lastEntry.timestamp.addingTimeInterval(-timeInterval)
    }

    // Helper functions for log level filtering UI
    private func levelIcon(for level: LogLevel) -> String {
        switch level {
        case .error: return "xmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        case .debug: return "ant.circle.fill"
        }
    }

    private func levelColor(for level: LogLevel) -> Color {
        switch level {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .debug: return .secondary
        }
    }

    private func levelName(for level: LogLevel) -> String {
        switch level {
        case .error: return "Error"
        case .warning: return "Warning"
        case .info: return "Info"
        case .debug: return "Debug"
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
    
    struct CustomSheetBackground: ViewModifier {

        func body(content: Content) -> some View {
            let lightGray = Color(white: 0.90)
            content
                .background(lightGray.ignoresSafeArea(.all))
        }
    }

}

// MARK: - Custom Entry Views with Full Date/Time

struct AllEntriesTimelineView: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 4) {
                levelIcon
                Rectangle()
                    .fill(levelColor.opacity(0.3))
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(formatDateTimeWithDate(entry.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(entry.component)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(3)

                    if entry.hasAppInstallationError {
                        if let errorCode = entry.appErrorCode {
                            let hexCode: String? = {
                                if let intCode = Int32(errorCode) {
                                    return String(format: "0x%08X", intCode)
                                }
                                return nil
                            }()

                            HStack(spacing: 4) {
                                Image(systemName: "app.badge.checkmark")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                Text("Error:")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                ErrorCodeButton(errorCode: errorCode, hexCode: hexCode)
                            }
                        } else {
                            Label("App Error", systemImage: "app.badge.checkmark")
                                .font(.caption2)
                                .foregroundColor(.red)
                        }
                    }

                    Spacer()

                    Text("Thread \(entry.threadId)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Text(entry.message)
                    .font(.caption)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(6)
    }

    private var levelIcon: some View {
        Group {
            switch entry.level {
            case .info:
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.caption2)
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption2)
            case .debug:
                Circle()
                    .fill(Color.secondary)
                    .frame(width: 6, height: 6)
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

    private func formatDateTimeWithDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct AllEntriesRawLogView: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            levelIcon

            VStack(alignment: .leading, spacing: 0) {
                Text(entry.rawLine)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(levelColor)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }

    private var levelIcon: some View {
        Group {
            switch entry.level {
            case .info:
                Text("I")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.blue)
                    .frame(width: 12)
            case .warning:
                Text("W")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.orange)
                    .frame(width: 12)
            case .error:
                Text("E")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.red)
                    .frame(width: 12)
            case .debug:
                Text("D")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 12)
            }
        }
    }

    private var levelColor: Color {
        switch entry.level {
        case .info:
            return .primary
        case .warning:
            return .orange
        case .error:
            return .red
        case .debug:
            return .secondary
        }
    }
}
