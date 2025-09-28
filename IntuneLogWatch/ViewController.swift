//
//  ViewController.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import Foundation
import SwiftUI

struct ContentView: View {
    @StateObject private var parser = LogParser()
    @State private var selectedSyncEvent: SyncEvent?
    @State private var selectedPolicy: PolicyExecution?
    @State private var showingFilePicker = false
    @Binding var showingCertificateInspector: Bool
    @State private var sortNewestFirst = false
    @FocusState private var syncEventListFocused: Bool
    @FocusState private var syncEventDetailFocused: Bool
    
    init(showingCertificateInspector: Binding<Bool>) {
        self._showingCertificateInspector = showingCertificateInspector
    }
    
    var body: some View {
        NavigationSplitView {
            sidebar.frame(minWidth: 300)
        } content: {
            syncEventDetail
        } detail: {
            policyDetail
        }
        .navigationTitle(parser.analysis?.sourceTitle ?? "Intune Log Watch")
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: [.log, .plainText],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    parser.parseLogFile(at: url)
                }
            case .failure(let error):
                parser.error = error.localizedDescription
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                
                Button("Open Log File...") {
                    selectedSyncEvent = nil
                    selectedPolicy = nil
                    parser.analysis = nil
                    parser.error = nil
                    showingFilePicker = true
                }
                .disabled(parser.isLoading)
                
                Button("Reload Local Logs") {
                    selectedSyncEvent = nil
                    selectedPolicy = nil
                    parser.loadLocalIntuneLogs()
                }
                .disabled(parser.isLoading)
                
                Button("Inspect MDM Certificate") {
                    showingCertificateInspector = true
                }
            }
        }
        .onAppear {
            // Automatically load local Intune logs when the app launches
            if parser.analysis == nil && parser.error == nil {
                parser.loadLocalIntuneLogs()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openLogFile)) { _ in
            // Trigger the same action as the toolbar button
            selectedSyncEvent = nil
            selectedPolicy = nil
            parser.analysis = nil
            parser.error = nil
            showingFilePicker = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .reloadLocalLogs)) { _ in
            // Trigger the same action as the reload button
            selectedSyncEvent = nil
            selectedPolicy = nil
            parser.loadLocalIntuneLogs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusSearchField)) { _ in
            // Handle search focus at the top level
            if selectedSyncEvent != nil {
                // If we have a sync event, ensure detail view is focused first
                syncEventDetailFocused = true
                // Then post the search field focus notification
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(name: .focusSearchFieldDirect, object: nil)
                }
            }
        }
        .onChange(of: parser.isLoading) { oldValue, newValue in
            // Auto-select first sync event when parsing completes
            if !newValue, let analysis = parser.analysis, selectedSyncEvent == nil {
                let sortedEvents = sortedSyncEvents(analysis.syncEvents)
                selectedSyncEvent = sortedEvents.first
                syncEventListFocused = true
            }
        }
        .sheet(isPresented: $showingCertificateInspector) {
            CertificateInspectionView()
        }
    }
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if parser.isLoading {
                ProgressView("Parsing log file...")
//                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let analysis = parser.analysis {
                
                appInfoHeader()
                enrollmentHeader(analysis)
                networkHeader(analysis)
                analysisHeader(analysis)
                
                sortControls
                
                if #available(macOS 14.0, *) {
                    List(sortedSyncEvents(analysis.syncEvents), selection: $selectedSyncEvent) { syncEvent in
                        SyncEventRow(syncEvent: syncEvent)
                            .tag(syncEvent)
                    }
                    .focused($syncEventListFocused)
                    .onKeyPress(.rightArrow) {
                        if selectedSyncEvent != nil {
                            syncEventDetailFocused = true
                            return .handled
                        }
                        return .ignored
                    }
                    .onAppear {
                        // Auto-select the first sync event when the list appears
                        if selectedSyncEvent == nil {
                            let sortedEvents = sortedSyncEvents(analysis.syncEvents)
                            selectedSyncEvent = sortedEvents.first
                            syncEventListFocused = true
                        }
                    }
                } else {
                    // Fallback on earlier versions
                }

            } else if let error = parser.error {
                VStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text("Error")
                        .font(.headline)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("No Log File Selected")
                        .font(.headline)
                    Text("Click 'Open Log File' to select an Intune log file to analyze")
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    
    @State var enrollmentExpanded: Bool = false
    @State var networkExpanded: Bool = false
    @State var analysisExpanded: Bool = true
    
    private func appInfoHeader() -> some View {
        VStack(alignment: .leading, spacing: 2) {
                        
            VStack {
                AppVersionInformationView(
                    versionString: AppVersionProvider.appVersion(),
                    appIcon: AppIconProvider.appIcon()
                )
            }
            Divider()
            HStack {
                Spacer()
            }
        }
//        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func enrollmentHeader(_ analysis: LogAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 2) {
                        
            if hasEnrollmentInfo(analysis) {
                
                DisclosureGroup("Enrollment Status", isExpanded: $enrollmentExpanded) {
                    
                    VStack(alignment: .leading, spacing: 2) {
                        if let aadTenantID = analysis.aadTenantID {
                            HStack {
                                Text("Entra Tenant ID:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text(" \(aadTenantID)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .textSelection(.enabled)
                                Spacer()
                            }
                            Spacer()
                        }
                        
                        if let deviceID = analysis.deviceID {
                            HStack {
                                Text("Intune Device ID:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            HStack {
                                Text(" \(deviceID)")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .textSelection(.enabled)
                                Spacer()
                            }
                            Spacer()
                        }
                        
                        Grid(alignment: .leading, horizontalSpacing: 40, verticalSpacing: 4) {
                            if let environment = analysis.environment {
                                GridRow {
                                    Text("Environment:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(" \(environment)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                            }
                            
                            if let region = analysis.region {
                                GridRow {
                                    Text("Region:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(" \(region)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                            }
                            
                            if let asu = analysis.asu {
                                GridRow {
                                    Text("ASU:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(" \(asu)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                            }
                            
                            if let macOSVers = analysis.macOSVers {
                                GridRow {
                                    Text("macOS Version:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(" \(macOSVers)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                            }

                            if let agentVers = analysis.agentVers {
                                GridRow {
                                    Text("Agent Version:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(" \(agentVers)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                            }

                            if let platform = analysis.platform {
                                GridRow {
                                    Text("Platform:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(" \(platform)")
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .textSelection(.enabled)
                                    Spacer()
                                }
                            }
                        }
                    }
                    .padding(.bottom, 8)
                    .padding(.leading, 30)

                    Divider()
                    
                }
                .font(.headline)
                .padding(.leading, 10)
                .padding(.trailing, 20)

            }
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func networkHeader(_ analysis: LogAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 2) {
                        
            // Network Summary Section
            if let networkSummary = analysis.networkSummary, networkSummary.hasData {
                
                DisclosureGroup("Network Connectivity", isExpanded: $networkExpanded) {
                    
                    Spacer()

                    VStack(alignment: .leading, spacing: 2) {
                        
                        Grid(alignment: .trailing, horizontalSpacing: 5, verticalSpacing: 4) {
                            
                            GridRow {
                                Text("Connection")
                                Text("Checks")
                                Text("Percent")
                            }
                            .font(.subheadline)
                            
                            Divider()
                                .background(Color.blue)
                                .opacity(0.7)
                                .frame(height: 1)

                            GridRow {
                                Text("Total:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%d", networkSummary.totalNetworkChecks))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text("100%")
                                    .font(.caption)
                                    .fontWeight(.medium)
                            }
                            
                            if networkSummary.noConnectionCount > 0 {
                                GridRow {
                                    Text("Disconnected:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%d", networkSummary.noConnectionCount))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.red)
                                    Text(String(format: "%.1f%%", networkSummary.noConnectionPercentage))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.red)
                                }
                            }

                            // Interface percentages
                            ForEach(networkSummary.interfaceStats.sorted(by: { $0.value > $1.value }), id: \.key) { interface, count in
                                GridRow {
                                    Text("\(interface):")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%d", count))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(interfaceColor(interface))
                                    let percentage = networkSummary.interfacePercentages[interface] ?? 0
                                    Text(String(format: "%.1f%%", percentage))
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(interfaceColor(interface))
                                }
                            }

                        }
                        .padding(.leading)
                        .padding(.trailing)
                        
                    }
                    .padding(.bottom, 8)
                    .padding(.leading, 10)
                    Divider()
                    
                }
                .font(.headline)
                .padding(.leading, 10)
                .padding(.trailing, 20)


            }
            
        }
        .background(Color(NSColor.controlBackgroundColor))
    }

    private func analysisHeader(_ analysis: LogAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 2) {
                        
            DisclosureGroup("Analysis Summary", isExpanded: $analysisExpanded) {
                Spacer()

                HStack {
                    Label("\(analysis.totalSyncEvents)", systemImage: "clock")
                        .font(.caption)
                        .foregroundColor(.blue)
                    Label("\(analysis.completedSyncs)", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Label("\(analysis.failedSyncs)", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    Spacer()
                }
                .padding(.leading, 20)
                .padding(.trailing, 10)

                // Show Intune installation warnings
                ForEach(analysis.parseErrors.filter { $0.hasPrefix("WARNING:") }, id: \.self) { warning in
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.caption)
                        Text(warning.replacingOccurrences(of: "WARNING: ", with: ""))
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(.top, 2)
                }
                .padding(.leading, 30)
                .padding(.trailing, 10)

            }
            .font(.headline)
            .padding(.leading, 10)

            Divider()
        }
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var syncEventDetail: some View {
        Group {
            if let syncEvent = selectedSyncEvent {
                if #available(macOS 14.0, *) {
                    SyncEventDetailView(syncEvent: syncEvent, selectedPolicy: $selectedPolicy)
                        .focused($syncEventDetailFocused)
                        .onKeyPress(.leftArrow) {
                            syncEventListFocused = true
                            return .handled
                        }
                        .onChange(of: syncEventDetailFocused) { oldValue, newValue in
                            if newValue {
                                NotificationCenter.default.post(name: .focusPolicyList, object: nil)
                            }
                        }
                } else {
                    // Fallback on earlier versions
                }
            } else {
                VStack {
                    Image(systemName: "sidebar.left")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Select a Sync Event")
                        .font(.headline)
                    Text("Choose a sync event from the sidebar to view its details")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private var policyDetail: some View {
        Group {
            if let policy = selectedPolicy {
                PolicyDetailView(policy: policy)
            } else {
                VStack {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Select a Policy")
                        .font(.headline)
                    Text("Choose a policy from the sync event to view its details")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
    
    private var sortControls: some View {
        HStack {
            Text("Sort:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(action: { sortNewestFirst = false }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.caption)
                    Text("Oldest First")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(sortNewestFirst ? .secondary : .blue)
            .fontWeight(sortNewestFirst ? .regular : .medium)
            
            Button(action: { sortNewestFirst = true }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                        .font(.caption)
                    Text("Newest First")
                        .font(.caption)
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(sortNewestFirst ? .blue : .secondary)
            .fontWeight(sortNewestFirst ? .medium : .regular)
            
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private func sortedSyncEvents(_ syncEvents: [SyncEvent]) -> [SyncEvent] {
        if sortNewestFirst {
            return syncEvents.sorted { $0.startTime > $1.startTime }
        } else {
            return syncEvents.sorted { $0.startTime < $1.startTime }
        }
    }
    
    private func hasEnrollmentInfo(_ analysis: LogAnalysis) -> Bool {
        return analysis.environment != nil || 
               analysis.region != nil || 
               analysis.accountID != nil || 
               analysis.aadTenantID != nil
    }
    
    private func interfaceColor(_ interface: String) -> Color {
        switch interface.lowercased() {
        case let str where str.contains("wifi") || str.contains("wi-fi"):
            return .blue
        case let str where str.contains("ethernet") || str.contains("en0"):
            return .green
        case let str where str.contains("cellular") || str.contains("pdp"):
            return .orange
        case let str where str.contains("bluetooth"):
            return .purple
        default:
            return .secondary
        }
    }
}

struct SyncEventRow: View {
    let syncEvent: SyncEvent
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                statusIcon
                Text(syncEvent.isComplete ? "Sync Event" : "Sync Event (In Progress)")
                    .font(.headline)
                Spacer()
                Text(formatTime(syncEvent.startTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text("\(syncEvent.totalPolicies) policies")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if let duration = syncEvent.duration {
                    Text("• \(formatDuration(duration))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if syncEvent.failedPolicies > 0 {
                    Label("\(syncEvent.failedPolicies)", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                if syncEvent.warningPolicies > 0 {
                    Label("\(syncEvent.warningPolicies)", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }
    
    private var statusIcon: some View {
        Group {
            switch syncEvent.overallStatus {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            case .running:
                Image(systemName: "arrow.clockwise")
                    .foregroundColor(.blue)
            case .pending:
                Image(systemName: "clock")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

