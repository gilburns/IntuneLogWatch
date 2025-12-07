//
//  PolicyDetailView.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import Foundation
import SwiftUI

// MARK: - Policy Details

struct PolicyDetailView: View {
    let policy: PolicyExecution
    @State private var selectedLogEntry: LogEntry?
    @State private var showingRawLogs = false
    @State private var detailLogEntry: LogEntry?
    @State private var policyIdCopied = false
    @State private var copiedText: String = ""
    @State private var packageReceiptInfo: PackageReceiptInfo?
    @State private var showingClipDialog = false

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

            Text("(Double click on a log entry to view or copy details)")
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()

            if showingRawLogs {
                rawLogView
            } else {
                timelineView
            }
        }
        .sheet(item: $detailLogEntry) { entry in
            if let index = policy.entries.firstIndex(where: { $0.id == entry.id }) {
                LogEntryDetailView(displayName: policy.displayName, bundleIdentifier: policy.bundleId ?? "", policyType: policy.type, entries: policy.entries, currentIndex: index)
                    .frame(minWidth: 700, minHeight: 550)
            }
        }
        .sheet(item: $packageReceiptInfo) { info in
            PackageReceiptView(packageInfo: info)
                .frame(minWidth: 800, minHeight: 600)
        }
        .sheet(isPresented: $showingClipDialog) {
            ClipEventDialog(policy: policy) { customName, notes in
                let clippedEvent = ClippedPolicyEvent(customName: customName, notes: notes, policyExecution: policy)
                ClipLibraryManager.shared.saveEvent(clippedEvent)
            }
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

                    HStack(alignment: .center, spacing: 12) {
                        Text(policy.displayName)
                            .font(policy.displayName.count > 27 ? .title3 : .title2)
                            .fontWeight(.semibold)

                    }

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
                VStack(alignment: .leading, spacing: 2) {
                    statusBadge
                    Text("")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, -4)

            HStack(spacing: 16) {
                if let startTime = policy.startTime {
                    detailMetric(
                        label: "Event Date",
                        value: formatDate(startTime),
                        icon: "calendar",
                        color: .purple
                    )
                }

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
            .padding(.bottom, -8)

            HStack(spacing: 16) {
                copyablePolicyId
            }
            .padding(.bottom, -8)

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
            }
            .padding(.bottom, -4)

            HStack(spacing: 16) {
                
                actionButtons
                
                Spacer()

                policyIssueStatus
            }
            .padding(.bottom, -8)

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
            case .health:
                Image(systemName: "stethoscope")
                    .foregroundColor(.purple)
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
    
    private var copyablePolicyId: some View {
        HStack() {
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
                
                HStack() {
                    if policy.policyId == "00000000-0000-0000-0000-000000000000" {
                        Text(policy.policyId)
                            .font(.caption)
                            .fontWeight(.medium)
                            .textSelection(.enabled)
                            .lineLimit(1)
                    } else {
                        Button(action: {
                            let intuneUrl = generateIntunePortalUrl(for: policy)
                            NSWorkspace.shared.open(URL(string: intuneUrl)!)
                        }) {
                            Text(policy.policyId).underline()
                                .foregroundColor(Color.blue)
                                .font(.caption)
                                .fontWeight(.medium)
                        }.buttonStyle(PlainButtonStyle())
                        .onHover { inside in
                            if inside {
                                NSCursor.pointingHand.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .help("Click to open this policy in the Intune portal: \(generateIntunePortalUrl(for: policy))")
                        .contextMenu {
                            if policy.policyId != "00000000-0000-0000-0000-000000000000" {
                                Button(action: {
                                    copyPolicyId()
                                }) {
                                    Label("Copy Policy ID", systemImage: "doc.on.doc")
                                }
                                
                                Divider()
                                
                                Button(action: {
                                    copyGraphApiUrl()
                                }) {
                                    Label("Copy Graph API URL", systemImage: "link")
                                }
                                
                                Button(action: {
                                    copyIntunePortalUrl()
                                }) {
                                    Label("Copy Intune Portal URL", systemImage: "globe")
                                }
                                
                                Divider()

                                Button(action: {
                                    let intuneUrl = generateIntunePortalUrl(for: policy)
                                    NSWorkspace.shared.open(URL(string: intuneUrl)!)
                                }) {
                                    Label("Open Intune Portal URL", systemImage: "globe.fill")
                                }

                            }
                        }
                    }
                }
            }
            
            Spacer()
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                
                HStack(alignment: .center) {
                    Text(policy.policyId == "00000000-0000-0000-0000-000000000000" ?
                         "No Policy ID" : "Copy ID")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.bottom, -6)
                }
                
                HStack(alignment: .center) {
                    Button(action: {
                        copyPolicyId()
                    }) {
                        Image(systemName: policy.policyId == "00000000-0000-0000-0000-000000000000" ?
                              "rectangle.portrait.slash" : policyIdCopied ? "checkmark" : "doc.on.clipboard")
                        .font(.caption2)
                        .foregroundColor(policyIdCopied ? .green : .secondary)
                        .frame(width: 40, height: 24)
                    }
                    .buttonStyle(BorderlessButtonStyle())
                    .disabled(policy.policyId == "00000000-0000-0000-0000-000000000000")
                    .help(policyIdCopied ? "Copied \(copiedText)!" : policy.policyId == "00000000-0000-0000-0000-000000000000" ?
                          "No Valid ID to Copy" : "Click to copy Policy ID\nRight-click for more options")
                    .contextMenu {
                        if policy.policyId != "00000000-0000-0000-0000-000000000000" {
                            Button(action: {
                                copyPolicyId()
                            }) {
                                Label("Copy Policy ID", systemImage: "doc.on.doc")
                            }
                            
                            Divider()
                            
                            Button(action: {
                                copyGraphApiUrl()
                            }) {
                                Label("Copy Graph API URL", systemImage: "link")
                            }
                            
                            Button(action: {
                                copyIntunePortalUrl()
                            }) {
                                Label("Copy Intune Portal URL", systemImage: "globe")
                            }
                            
                            Divider()

                            Button(action: {
                                let intuneUrl = generateIntunePortalUrl(for: policy)
                                NSWorkspace.shared.open(URL(string: intuneUrl)!)
                            }) {
                                Label("Open Intune Portal URL", systemImage: "globe.fill")
                            }

                        }
                    }
                }
            }
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
        let intuneUrl = generateIntunePortalUrl(for: policy)
        copyToClipboard(text: intuneUrl, displayText: "Intune Portal URL")
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
        case .health:
            return "Not Supported"
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
                return "\(baseUrl)/?ref=AdminCenter#view/Microsoft_Intune_DeviceSettings/ConfigureCustomAttributesPolicyMenuBladeViewModel/~/overview/id/\(guid)/displayName/"
            } else {
                return "\(baseUrl)/?ref=AdminCenter#view/Microsoft_Intune_DeviceSettings/ConfigureWMPolicyMenuBlade/~/overview/policyId/\(guid)/policyType~/1"
            }
        case .health:
            return "Not Supported"
        case .unknown:
            // Default to shell script endpoint for unknown types
            return "\(baseUrl)/#view/Microsoft_Intune_DeviceSettings/DevicesMacOsMenu/~/scripts"
        }
    }
    
    private var policyIssueStatus: some View {
        VStack(alignment: .leading) {

            if policy.hasErrors || policy.hasWarnings || policy.hasAppInstallationErrors {
                HStack(alignment: .bottom, spacing: 12) {
                    
                    if policy.hasAppInstallationErrors {
                        let errorCodes = policy.appErrorCodes
                        HStack(spacing: 8) {
                            if errorCodes.isEmpty {
                                Label("Error", systemImage: "app.badge.checkmark")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            } else {
                                Label("Error:", systemImage: "app.badge.checkmark")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        
                    } else {
                        Text("")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
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
                    
                    HStack() {
                        Text("  ")
                        if errorCodes.isEmpty {
                            Text("")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            ForEach(errorCodes, id: \.self) { code in
                                let hexCode: String? = {
                                    if let intCode = Int32(code) {
                                        return String(format: "0x%08X", intCode)
                                    }
                                    return nil
                                }()
                                
                                ErrorCodeButton(errorCode: code, hexCode: hexCode)
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
    
    private var actionButtons: some View {
        HStack() {
            VStack(alignment: .leading) {

                HStack(spacing: 4) {
                    Image(systemName: "ellipsis.circle")
                        .foregroundColor(.secondary)
                        .font(.caption)
                    Text("Policy Actions")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.bottom, -4)

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
                                .padding(.bottom, 1)
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
                            if let firstEntry = policy.entries.first {
                                detailLogEntry = firstEntry
                            }
                        }) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .foregroundColor(.white)
                                .font(.caption)
                                .padding(4)
                                .padding(.bottom, -1)
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
                .tooltip("This is the main policy type. Possible types include App, Script, and Health Check.")
            
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
                    .tooltip("For app policies, this indicates whether the app is installed as a PKG or DMG.")

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
                    .tooltip("For app policies, this indicates whether the app is Required, Available, or Uninstall.")

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
                    .tooltip("For script policies, this indicates whether the script is a custom attribute or a regular script.")

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
                    .tooltip("For script policies, this indicates the execution context in which the script is executed. Possible values are: Root or User.")

            }
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
            .onChange(of: policy.policyId) { oldValue, newValue in
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
            .onChange(of: policy.policyId) { oldValue, newValue in
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
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
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

// MARK: - Timeline

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

// MARK: - Raw Logs

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
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
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
