//
//  PolicyDetailView.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import Foundation
import SwiftUI

struct PolicyDetailView: View {
    let policy: PolicyExecution
    @State private var selectedLogEntry: LogEntry?
    @State private var showingRawLogs = false
    @State private var detailLogEntry: LogEntry?
    @State private var policyIdCopied = false
    @State private var copiedText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
            policyHeader
            
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
        .sheet(item: $detailLogEntry) { entry in
            LogEntryDetailView(entry: entry)
                .frame(minWidth: 700, minHeight: 550)
        }
    }
    
    private var policyHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                AppIconView(
                    bundleId: policy.bundleId,
                    policyType: policy.type,
                    size: 42
                )
                .id("\(policy.policyId)-\(policy.bundleId ?? "nil")")
                VStack(alignment: .leading, spacing: 2) {
                    Text(policy.displayName)
                        .font(.title2)
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
                
                copyablePolicyId
                
                Spacer()
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
                        HStack(spacing: 8) {
                            if errorCodes.isEmpty {
                                Label("App Installation Failed", systemImage: "app.badge.checkmark")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            } else {
                                Label("App Installation Failed:", systemImage: "app.badge.checkmark")
                                    .font(.caption)
                                    .foregroundColor(.red)

                                ForEach(errorCodes, id: \.self) { code in
                                    let hexCode: String? = {
                                        if let intCode = Int32(code) {
                                            return String(format: "0x%08X", intCode)
                                        }
                                        return nil
                                    }()

                                    ErrorCodeButton(errorCode: code, hexCode: hexCode)
                                }
                            }
                        }
                    }

                    Spacer()
                }
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
    
    private var policyIcon: some View {
        Group {
            switch policy.type {
            case .app:
                Image(systemName: "app.badge")
                    .foregroundColor(.blue)
                    .font(.title)
            case .script:
                Image(systemName: "terminal")
                    .foregroundColor(.green)
                    .font(.title)
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.secondary)
                    .font(.title)
            }
        }
    }
    
    private var statusBadge: some View {
        Text(policy.status.displayName.uppercased())
            .font(.caption)
            .fontWeight(.semibold)
            .padding(.horizontal, 12)
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
    
    private var copyablePolicyId: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: "number")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text("Policy ID")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button(action: {
                    // Detect if option key is pressed
                    if NSEvent.modifierFlags.contains(.option) {
                        copyGraphApiUrl()
                    } else if NSEvent.modifierFlags.contains(.control) {
                        copyIntunePortalUrl()
                    } else {
                        copyPolicyId()
                    }
                }) {
                    Image(systemName: policyIdCopied ? "checkmark" : "doc.on.clipboard")
                        .font(.caption2)
                        .foregroundColor(policyIdCopied ? .green : .secondary)
                }
                .buttonStyle(BorderlessButtonStyle())
                .help(policyIdCopied ? "Copied \(copiedText)!" : "Copy Policy ID\r⌥-click for Graph API URL,\r ⌃-click for Intune Portal URL")
            }
            Text(policy.policyId)
                .font(.caption)
                .fontWeight(.medium)
                .textSelection(.enabled)
        }
    }
    
    private func copyPolicyId() {
        copyToClipboard(text: policy.policyId, displayText: "Policy ID")
    }
    
    private func copyGraphApiUrl() {
        let apiUrl = generateGraphApiUrl(for: policy)
        copyToClipboard(text: apiUrl, displayText: "Graph API URL")
    }

    private func copyIntunePortalUrl() {
        let apiUrl = generateIntunePortalUrl(for: policy)
        copyToClipboard(text: apiUrl, displayText: "Intune Portal URL")
    }

    private func copyToClipboard(text: String, displayText: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        
        copiedText = displayText
        
        withAnimation(.easeInOut(duration: 0.2)) {
            policyIdCopied = true
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation(.easeInOut(duration: 0.2)) {
                policyIdCopied = false
            }
        }
    }
    
    private func generateGraphApiUrl(for policy: PolicyExecution) -> String {
        let baseUrl = "https://graph.microsoft.com/beta"
        let guid = policy.policyId
        
        switch policy.type {
        case .app:
            return "\(baseUrl)/deviceAppManagement/mobileApps/\(guid)"
        case .script:
            // Check if it's a custom attribute or regular script based on scriptType
            if let scriptType = policy.scriptType, scriptType == "Custom Attribute" {
                return "\(baseUrl)/deviceManagement/deviceCustomAttributeShellScripts/\(guid)"
            } else {
                return "\(baseUrl)/deviceManagement/deviceShellScripts/\(guid)"
            }
        case .unknown:
            // Default to shell script endpoint for unknown types
            return "\(baseUrl)/deviceManagement/deviceShellScripts/\(guid)"
        }
    }

    private func generateIntunePortalUrl(for policy: PolicyExecution) -> String {
        let baseUrl = "https://intune.microsoft.com"
        let guid = policy.policyId
        
        switch policy.type {
        case .app:
            return "\(baseUrl)/#view/Microsoft_Intune_Apps/SettingsMenu/~/0/appId/\(guid)"
        case .script:
            // Check if it's a custom attribute or regular script based on scriptType
            if let scriptType = policy.scriptType, scriptType == "Custom Attribute" {
                return "\(baseUrl)/#view/Microsoft_Intune_DeviceSettings/DevicesMacOsMenu/~/customAttributes"
            } else {
                return "\(baseUrl)/#view/Microsoft_Intune_DeviceSettings/DevicesMacOsMenu/~/scripts"
            }
        case .unknown:
            // Default to shell script endpoint for unknown types
            return "\(baseUrl)/#view/Microsoft_Intune_DeviceSettings/DevicesMacOsMenu/~/scripts"
        }
    }

    private var timelineView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(policy.entries) { entry in
                    TimelineEntryView(entry: entry)
                        .background(selectedLogEntry?.id == entry.id ? Color.accentColor.opacity(0.1) : Color.clear)
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
            }
            .onAppear {
                proxy.scrollTo("timelineTop", anchor: .top)
            }
            .onChange(of: policy.policyId) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("timelineTop", anchor: .top)
                }
            }
        }
    }
    
    private var rawLogView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(policy.entries) { entry in
                    RawLogEntryView(entry: entry)
                        .background(selectedLogEntry?.id == entry.id ? Color.accentColor.opacity(0.1) : Color.clear)
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
            }
            .onAppear {
                proxy.scrollTo("rawLogTop", anchor: .top)
            }
            .onChange(of: policy.policyId) { _ in
                withAnimation(.easeInOut(duration: 0.3)) {
                    proxy.scrollTo("rawLogTop", anchor: .top)
                }
            }
        }
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
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

struct TimelineEntryView: View {
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
                    Text(formatTime(entry.timestamp))
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
        .padding(.vertical, 4)
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
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

struct RawLogEntryView: View {
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
        .padding(.vertical, 1)
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
