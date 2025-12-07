//
//  SyncEventDetailView.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import Foundation
import SwiftUI

// MARK: - Sync Event Details

struct SyncEventDetailView: View {
    let syncEvent: SyncEvent
    @Binding var selectedPolicy: PolicyExecution?
    @State private var searchText = ""
    @State private var selectedPolicyType: String = "all"
    @State private var logDetailPolicy: PolicyExecution?
    @State private var showingClipDialog = false

    @FocusState private var policyListFocused: Bool
    @FocusState private var searchFieldFocused: Bool
    @Environment(\.colorScheme) private var colorScheme
    
    var filteredPolicies: [PolicyExecution] {
        var policies = syncEvent.policies
        
        // Filter by policy type
        switch selectedPolicyType {
        case "app":
            policies = policies.filter { $0.type == .app }
        case "script":
            policies = policies.filter { $0.type == .script }
        case "health":
            policies = policies.filter { $0.type == .health }
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
                    .overlay(alignment: .trailing) {
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 6)
                        }
                    }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .fixedSize(horizontal: false, vertical: true)
                        
            HStack {
                let policyCount = policies.count
                let filteredPolicyCount = filteredPolicies.count
                Spacer()
                Text("Viewing \(filteredPolicyCount) of \(policyCount) Policies")
            }
            .padding(.horizontal)
            .padding(.vertical, 2)
            .fixedSize(horizontal: false, vertical: true)
            .font(.caption)
            .foregroundColor(.secondary)

            if #available(macOS 14.0, *) {
                List(filteredPolicies, selection: $selectedPolicy) { policy in
                    PolicyRow(
                        policy: policy,
                        syncEvent: syncEvent,
                        isSelected: selectedPolicy?.id == policy.id,
                        onDoubleClick: {
                            if !policy.entries.isEmpty {
                                logDetailPolicy = policy
                            }
                        }
                    )
                    .listRowBackground(Color.gray.opacity(0.07))
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
                    .presentationBackground(Color.gray.opacity(0.07))
            }
        }

    }
    
    
    private var eventHeaderIcon: String {
        switch syncEvent.eventType {
        case .fullSync:
            return "gearshape.arrow.triangle.2.circlepath"
        case .recurringPolicy:
            return "clock.arrow.circlepath"
        case .healthPolicy:
            return "stethoscope.circle"
        }
    }

    private var eventHeaderIconColor: Color {
        switch syncEvent.eventType {
        case .fullSync:
            return .blue
        case .recurringPolicy:
            return .blue
        case .healthPolicy:
            return .blue
        }
    }

    private var syncEventHeader: some View {

        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: eventHeaderIcon)
                    .foregroundColor(eventHeaderIconColor)
                Text(syncEvent.eventType.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                statusIcon
                Spacer()
                Text(formatDateTime(syncEvent.startTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .tooltip(formatDateTimeFull(syncEvent.startTime))
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

                if let frequency = syncEvent.executionFrequencyFormatted {
                    syncMetric(
                        value: frequency,
                        label: "Frequency",
                        icon: "arrow.clockwise",
                        color: .purple
                    )
                }

                Spacer()

            }
            
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
        .id(colorScheme)
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

    private func formatDateTimeFull(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .full
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
    let syncEvent: SyncEvent
    let isSelected: Bool
    let onDoubleClick: (() -> Void)?
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var packageReceiptInfo: PackageReceiptInfo?
    @State private var showingClipDialog = false
    @State private var isHovered: Bool = false

    init(policy: PolicyExecution, syncEvent: SyncEvent, isSelected: Bool = false, onDoubleClick: (() -> Void)? = nil) {
        self.policy = policy
        self.syncEvent = syncEvent
        self.isSelected = isSelected
        self.onDoubleClick = onDoubleClick
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                AppIconView(
                    bundleId: policy.bundleId,
                    policyType: policy.type,
                    size: 36
                )
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(policy.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    if let bundleId = policy.bundleId {
                        Text(bundleId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if let policyId = policy.policyId as NSString? {
                        Text("\(policyId)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                }

                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    HStack (alignment: .center) {
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
                        
                        statusBadge

                    }
                    Text("")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                }
            }
            .padding(.bottom, 12)

            HStack {
                policyTypeTiles
                    .padding(.bottom, 7)

                Spacer()

                if isHovered {
                    actionButtons
                        .transition(.opacity)
                }
            }
        }
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(isHovered && !isSelected ? 0.2 : 0))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .sheet(item: $packageReceiptInfo) { info in
            PackageReceiptView(packageInfo: info)
                .frame(minWidth: 700, minHeight: 600)
        }
        .sheet(isPresented: $showingClipDialog) {
            ClipEventDialog(policy: policy) { customName, notes in
                let clippedEvent = ClippedPolicyEvent(customName: customName, notes: notes, policyExecution: policy)
                ClipLibraryManager.shared.saveEvent(clippedEvent)
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { d in
            0
        }

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
            case .health:
                Image(systemName: "stethoscope")
                    .foregroundColor(.purple)
            case .unknown:
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.secondary)
            }
        }
    }
        
    private var actionButtons: some View {
        HStack(spacing: 6) {

            // Reveal in Finder button for apps
            if policy.type == .app, let bundleId = policy.bundleId {
                if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                    // App bundle found - show Finder button
                    Button(action: {
                        NSWorkspace.shared.selectFile(appURL.path, inFileViewerRootedAtPath: "")
                    }) {
                        Image(systemName: "arrow.forward.folder")
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(4)
                            .padding(.bottom, 1)
                            .padding(.leading, 1)
                            .background(
                                Circle()
                                    .fill(Color.indigo)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 1.5)
                                    )
                            )
                    }
                    .buttonStyle(PressedButtonStyle())
                    .help("Reveal \(policy.displayName) in Finder")
                } else {
                    // Show disabled button
                    Button(action: {

                    }) {
                        Image(systemName: "arrow.forward.folder")
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(4)
                            .padding(.bottom, 1)
                            .padding(.leading, 1)
                            .background(
                                Circle()
                                    .fill(Color(NSColor.lightGray).opacity(0.5))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                                    )
                            )
                    }
                    .buttonStyle(PressedButtonStyle())
                    .help("\(policy.displayName) not found in Finder")
                }
                
                // PKG Inspector
                if PackageInspectorHelper.hasPackageReceipt(bundleId: bundleId) {
                    // Package receipt found - show package info button
                    Button(action: {
                        if let info = PackageInspectorHelper.getPackageInfo(bundleId: bundleId) {
                            packageReceiptInfo = info
                        }
                    }) {
                        Image(systemName: "shippingbox")
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(4)
                            .padding(.bottom, 1)
                            .padding(.leading, 1)
                            .background(
                                Circle()
                                    .fill(Color.yellow.opacity(0.8))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 1.5)
                                    )
                            )
                    }
                    .buttonStyle(PressedButtonStyle())
                    .help("View \(policy.displayName) package receipt")
                } else {
                    // Show disabled button
                    Button(action: {

                    }) {
                        Image(systemName: "shippingbox")
                            .foregroundColor(.white)
                            .font(.caption)
                            .padding(4)
                            .padding(.bottom, 1)
                            .padding(.leading, 1)
                            .background(
                                Circle()
                                    .fill(Color(NSColor.lightGray).opacity(0.5))
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                                    )
                            )
                    }
                    .buttonStyle(PressedButtonStyle())
                    .help("\(policy.displayName) package receipt not found")
                }
            } else {
                // Show disabled button
                Button(action: {

                }) {
                    Image(systemName: "arrow.forward.folder")
                        .foregroundColor(.white)
                        .font(.caption)
                        .padding(4)
                        .padding(.bottom, 1)
                        .padding(.leading, 1)
                        .background(
                            Circle()
                                .fill(Color(NSColor.lightGray).opacity(0.5))
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                                )
                        )
                }
                .buttonStyle(PressedButtonStyle())
                .help("Script objects not available in the Finder")

                // Show disabled button
                Button(action: {

                }) {
                    Image(systemName: "shippingbox")
                        .foregroundColor(.white)
                        .font(.caption)
                        .padding(4)
                        .padding(.bottom, 1)
                        .padding(.leading, 1)
                        .background(
                            Circle()
                                .fill(Color(NSColor.lightGray).opacity(0.5))
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.5), lineWidth: 1.5)
                                )
                        )
                }
                .buttonStyle(PressedButtonStyle())
                .help("Script objects do not have a package receipt")
                
            }

            if !policy.entries.isEmpty {
                Button(action: {
                    PolicyExportHelper.exportPolicyToPDF(policy: policy)
                }) {
                    Image(systemName: "doc.richtext")
                        .foregroundColor(.white)
                        .font(.caption)
                        .padding(4)
                        .background(
                            Circle()
                                .fill(Color.purple)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 1.5)
                                )
                        )
                }
                .buttonStyle(PressedButtonStyle())
                .help("Export \(policy.displayName) logs to PDF")

                Button(action: {
                    PolicyExportHelper.exportPolicyLogs(policy: policy, syncEvent: nil)
                }) {
                    Image(systemName: "arrow.up.doc")
                        .foregroundColor(.white)
                        .font(.caption)
                        .padding(4)
                        .padding(.bottom, 3)
                        .background(
                            Circle()
                                .fill(Color.green)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 1.5)
                                )
                        )
                }
                .buttonStyle(PressedButtonStyle())
                .help("Export \(policy.displayName) log entries to file")

                Button(action: {
                    onDoubleClick?()
                }) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .foregroundColor(.white)
                        .font(.caption)
                        .padding(4)
                        .padding(.bottom, 1)
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
                .help("View \(policy.displayName) log entries")
                
                Button(action: {
                    showingClipDialog = true
                }) {
                    Image(systemName: "scissors")
                        .foregroundColor(.white)
                        .font(.caption)
                        .padding(4)
                        .background(
                            Circle()
                                .fill(Color.orange)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white, lineWidth: 1.5)
                                )
                        )
                }
                .buttonStyle(PressedButtonStyle())
                .help("Save \(policy.displayName) to Clip Library")

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
