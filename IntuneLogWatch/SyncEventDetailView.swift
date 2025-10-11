//
//  SyncEventDetailView.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import Foundation
import SwiftUI

struct SyncEventDetailView: View {
    let syncEvent: SyncEvent
    @Binding var selectedPolicy: PolicyExecution?
    @State private var searchText = ""
    @State private var selectedPolicyType: String = "all"
    @State private var logDetailPolicy: PolicyExecution?
    @FocusState private var policyListFocused: Bool
    @FocusState private var searchFieldFocused: Bool
    
    var filteredPolicies: [PolicyExecution] {
        var policies = syncEvent.policies
        
        // Filter by policy type
        switch selectedPolicyType {
        case "app":
            policies = policies.filter { $0.type == .app }
        case "script":
            policies = policies.filter { $0.type == .script }
        default:
            break // "all" - no filtering
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            policies = policies.filter { policy in
                policy.displayName.localizedCaseInsensitiveContains(searchText) ||
                policy.policyId.localizedCaseInsensitiveContains(searchText) ||
                (policy.bundleId?.localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }
        
        return policies
    }
    
    var body: some View {
        VStack(spacing: 0) {
            syncEventHeader
            
            let policies = syncEvent.policies
            let appPoliciesCount = (policies.filter { $0.type == .app }).count
            let scriptPoliciesCount = (policies.filter { $0.type == .script }).count
            
            HStack {
                Picker("Policy Type:", selection: $selectedPolicyType) {
                    Text("All Policies").tag("all")
                    Text("App Policies (\(appPoliciesCount))").tag("app")
                    Text("Script Policies (\(scriptPoliciesCount))").tag("script")
                }
                .pickerStyle(SegmentedPickerStyle())
                .fixedSize()
                
                Spacer()
                
                TextField("Search policies...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(width: 200)
                    .focused($searchFieldFocused)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .fixedSize(horizontal: false, vertical: true)
            
            if #available(macOS 14.0, *) {
                List(filteredPolicies, selection: $selectedPolicy) { policy in
                    PolicyRow(policy: policy) {
                        if !policy.entries.isEmpty {
                            logDetailPolicy = policy
                        }
                    }
                    .tag(policy)
                }
                .focused($policyListFocused)
                .onKeyPress(.return) {
                    if let selectedPolicy = selectedPolicy, !selectedPolicy.entries.isEmpty {
                        logDetailPolicy = selectedPolicy
                        return .handled
                    }
                    return .ignored
                }
                .onReceive(NotificationCenter.default.publisher(for: .focusPolicyList)) { _ in
                    policyListFocused = true
                    // Auto-select first policy when focus is received
                    if !filteredPolicies.isEmpty {
                        selectedPolicy = filteredPolicies.first
                    }
                }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
            searchFieldFocused = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchFieldDirect)) { _ in
            searchFieldFocused = true
        }
            } else {
                // Fallback on earlier versions
            }
        }
        .sheet(item: $logDetailPolicy) { policy in
            if !policy.entries.isEmpty {
                LogEntryDetailView(displayName: policy.displayName, bundleIdentifier: policy.bundleId ?? "", policyType: policy.type, entries: policy.entries, currentIndex: 0)
                    .frame(minWidth: 700, minHeight: 550)
            }
        }
    }
    
    private var syncEventHeader: some View {
        
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .foregroundColor(.blue)
                Text("Sync Event (FullSyncWorkflow)")
                    .font(.title2)
                    .fontWeight(.semibold)
                statusIcon
                Spacer()
                Text(formatDateTime(syncEvent.startTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack(spacing: 16) {
                syncMetric(
                    value: "\(syncEvent.totalPolicies)",
                    label: "Total Policies",
                    icon: "doc.text",
                    color: .blue
                )
                
                syncMetric(
                    value: "\(syncEvent.completedPolicies)",
                    label: "Completed",
                    icon: "checkmark.circle.fill",
                    color: .green
                )
                
                if syncEvent.failedPolicies > 0 {
                    syncMetric(
                        value: "\(syncEvent.failedPolicies)",
                        label: "Failed",
                        icon: "xmark.circle.fill",
                        color: .red
                    )
                }
                
                if syncEvent.warningPolicies > 0 {
                    syncMetric(
                        value: "\(syncEvent.warningPolicies)",
                        label: "Warnings",
                        icon: "exclamationmark.triangle.fill",
                        color: .orange
                    )
                }
                
                if let duration = syncEvent.duration {
                    syncMetric(
                        value: formatDuration(duration),
                        label: "Duration",
                        icon: "clock",
                        color: .secondary
                    )
                }
                
                Spacer()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func syncMetric(value: String, label: String, icon: String, color: Color) -> some View {
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
    
    private var statusIcon: some View {
        Group {
            switch syncEvent.overallStatus {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.title2)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.title2)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.title2)
            case .running:
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.blue)
                    .font(.title2)
            case .pending:
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
                    .font(.title2)
            }
        }
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%.1fs", duration)
        }
    }
}

struct PolicyRow: View {
    let policy: PolicyExecution
    let onDoubleClick: (() -> Void)?
    @Environment(\.controlActiveState) private var controlActiveState

    init(policy: PolicyExecution, onDoubleClick: (() -> Void)? = nil) {
        self.policy = policy
        self.onDoubleClick = onDoubleClick
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                AppIconView(
                    bundleId: policy.bundleId,
                    policyType: policy.type,
                    size: 20
                )
                Text(policy.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                
                HStack(spacing: 4) {
                    // Main policy type
                    Text(policy.type.displayName)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(selectionAwareColor(.blue, fallback: .cyan).opacity(0.3))
                        .foregroundColor(selectionAwareColor(.blue, fallback: .cyan))
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.white, lineWidth: 0.5)
                        )
                    
                    // App type indicator (PKG/DMG)
                    if let appType = policy.appType {
                        Text(appType)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(appType == "PKG" ? Color.green.opacity(enhancedBackgroundOpacity(0.1)) : Color.purple.opacity(enhancedBackgroundOpacity(0.1)))
                            .foregroundColor(appType == "PKG" ? .green : .purple)
                            .cornerRadius(3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.white, lineWidth: 0.5)
                            )
                    }
                    
                    // App intent indicator (RequiredInstall/Available/Uninstall)
                    if let appIntent = policy.appIntent {
                        Text(intentDisplayName(appIntent))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(intentColor(appIntent).opacity(enhancedBackgroundOpacity(0.1)))
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
                            .background(scriptType == "Custom Attribute" ? Color.orange.opacity(enhancedBackgroundOpacity(0.1)) : Color.teal.opacity(enhancedBackgroundOpacity(0.1)))
                            .foregroundColor(scriptType == "Custom Attribute" ? .orange : .teal)
                            .cornerRadius(3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.white, lineWidth: 0.5)
                            )
                    }
                    
                    // Execution context indicator (for scripts only)
                    if policy.type == .script, let executionContext = policy.executionContext {
                        Text(executionContext.uppercased())
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(contextColor(executionContext).opacity(enhancedBackgroundOpacity(0.1)))
                            .foregroundColor(contextColor(executionContext))
                            .cornerRadius(3)
                            .overlay(
                                RoundedRectangle(cornerRadius: 3)
                                    .stroke(Color.white, lineWidth: 0.5)
                            )
                    }
                }
            }
            
            if let bundleId = policy.bundleId {
                Text(bundleId)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            HStack {
                statusBadge
                
                if let startTime = policy.startTime {
                    Text(formatTime(startTime))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let duration = policy.duration {
                    Text("• \(formatDuration(duration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if policy.hasErrors {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }
                
                if policy.hasWarnings {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption)
                }

                if !policy.entries.isEmpty {
                    Button(action: {
                        onDoubleClick?()
                    }) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(4)
                            .background(
                                Circle()
                                    .fill(Color.blue)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 1.5)
                                    )
                            )
                    }
                    .buttonStyle(PressedButtonStyle())
                    .help("View log entries")
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    private var policyIcon: some View {
        Group {
            switch policy.type {
            case .app:
                Image(systemName: "app.badge")
                    .foregroundColor(.blue)
            case .script:
                Image(systemName: "terminal")
                    .foregroundColor(.mint)
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var statusBadge: some View {
        Text(policy.status.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(enhancedBackgroundOpacity(0.2)))
            .foregroundColor(statusColor)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white, lineWidth: 0.5)
            )
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
            return selectionAwareColor(.blue, fallback: .teal)
        case .pending:
            return .secondary
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1.0 {
            return String(format: "%.0fms", duration * 1000)
        } else if duration < 60.0 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%dm %ds", minutes, seconds)
        }
    }
    
    private func intentDisplayName(_ intent: String) -> String {
        switch intent {
        case "RequiredInstall":
            return "REQUIRED"
        case "Available":
            return "AVAILABLE"
        case "Uninstall":
            return "UNINSTALL"
        default:
            return intent.uppercased()
        }
    }
    
    private func intentColor(_ intent: String) -> Color {
        switch intent {
        case "RequiredInstall":
            return .red // Required = must install
        case "Available":
            return selectionAwareColor(.blue, fallback: .cyan) // Available = optional
        case "Uninstall":
            return .brown // Uninstall = removal
        default:
            return .gray
        }
    }
    
    private func contextColor(_ context: String) -> Color {
        switch context.lowercased() {
        case "root":
            return .red // Root = administrative/system level
        case "user":
            return selectionAwareColor(.blue, fallback: .cyan) // User = user context
        default:
            return .gray
        }
    }
    
    // Helper method to provide selection-aware colors
    private func selectionAwareColor(_ originalColor: Color, fallback: Color) -> Color {
        // Use fallback color for better contrast when item might be selected
        return fallback
    }
    
    // Helper method to provide enhanced background opacity for better visibility
    private func enhancedBackgroundOpacity(_ baseOpacity: Double) -> Double {
        // Increase opacity slightly for better visibility on selection
        return min(baseOpacity + 0.1, 0.4)
    }
}

struct PressedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.85 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
