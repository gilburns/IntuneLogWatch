//
//  ViewController.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var parser = LogParser()
    @State private var selectedSyncEvent: SyncEvent?
    @State private var selectedPolicy: PolicyExecution?
    @State private var showingFilePicker = false
    
    var body: some View {
        NavigationSplitView {
            sidebar
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
    }
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if parser.isLoading {
                ProgressView("Parsing log file...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let analysis = parser.analysis {
                analysisHeader(analysis)
                
                List(analysis.syncEvents, selection: $selectedSyncEvent) { syncEvent in
                    SyncEventRow(syncEvent: syncEvent)
                        .tag(syncEvent)
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
    
    private func analysisHeader(_ analysis: LogAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 4) {
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
            HStack {
                Text("Analysis Summary")
                    .font(.headline)
                Spacer()
            }
            
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
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
    
    private var syncEventDetail: some View {
        Group {
            if let syncEvent = selectedSyncEvent {
                SyncEventDetailView(syncEvent: syncEvent, selectedPolicy: $selectedPolicy)
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

