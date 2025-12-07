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
    @Binding var sidebarVisibility: NavigationSplitViewVisibility
    @Binding var enrollmentExpanded: Bool
    @Binding var networkExpanded: Bool
    @Binding var analysisExpanded: Bool
    @State private var showingAllLogEntries = false
    @State private var sortNewestFirst = false
    @State private var eventFilter: EventFilter = .syncOnly
    @FocusState private var syncEventListFocused: Bool
    @FocusState private var syncEventDetailFocused: Bool
    @State private var infoViewVisible = true
    @State private var windowHeight: CGFloat = 0
    @State private var bottomThreshold: CGFloat = 50
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openWindow) private var openWindow

    enum EventFilter: String, CaseIterable {
        case syncOnly = "sync"
        case recurringOnly = "recurring"
        case healthOnly = "health"

        var displayName: String {
            switch self {
            case .syncOnly: return "Sync Events"
            case .recurringOnly: return "Recurring Events"
            case .healthOnly: return "Health Events"
            }
        }

        func displayNameWithCount(syncCount: Int, recurringCount: Int, healthCount: Int) -> String {
            switch self {
            case .syncOnly:
                return "Sync\nEvents\n(\(syncCount))"
            case .recurringOnly:
                return "Recurring\nEvents\n(\(recurringCount))"
            case .healthOnly:
                return "Health\nEvents\n(\(healthCount))"
            }
        }

        func toolTipForFilter() -> String {
            switch self {
            case .syncOnly:
                return "Sync Events"
            case .recurringOnly:
                return "Recurring Events"
            case .healthOnly:
                return "Health Events"
            }
        }

        var keyboardShortcut: KeyEquivalent {
            switch self {
            case .syncOnly: return "1"
            case .recurringOnly: return "2"
            case .healthOnly: return "3"
            }
        }
    }

    init(
        showingCertificateInspector: Binding<Bool>,
        sidebarVisibility: Binding<NavigationSplitViewVisibility>,
        enrollmentExpanded: Binding<Bool>,
        networkExpanded: Binding<Bool>,
        analysisExpanded: Binding<Bool>
    ) {
        self._showingCertificateInspector = showingCertificateInspector
        self._sidebarVisibility = sidebarVisibility
        self._enrollmentExpanded = enrollmentExpanded
        self._networkExpanded = networkExpanded
        self._analysisExpanded = analysisExpanded

        // Load saved filter preference
        if let savedFilter = UserDefaults.standard.string(forKey: "EventFilterPreference"),
           let filter = EventFilter(rawValue: savedFilter) {
            _eventFilter = State(initialValue: filter)
        }
    }
    
    
    var body: some View {
        
        GeometryReader { geometry in
            
            NavigationSplitView(columnVisibility: $sidebarVisibility) {
                sidebar.frame(minWidth: 300)
            } content: {
                syncEventDetail
            } detail: {
                policyDetail
                    .frame(minWidth: 400)
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
            .onAppear {
                // Automatically load local Intune logs when the app launches
                if parser.analysis == nil && parser.error == nil {
                    parser.loadLocalIntuneLogs()
                }
                
                // Capture the window height on appearance
                windowHeight = geometry.size.height
                
                // Add local event monitor for mouse movement
                NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { event in
                    self.handleMouseMoved(event, windowHeight: geometry.size.height)
                    return event
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
            .onReceive(NotificationCenter.default.publisher(for: .showAllLogEntries)) { _ in
                // Show all log entries window
                if parser.analysis != nil {
                    showingAllLogEntries = true
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openClipLibrary)) { _ in
                // Open clip library window (Window scene ensures only one instance)
                openWindow(id: "clip-library")
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
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        withAnimation(.spring(duration: 1.0, bounce: 0.5, blendDuration: 1.0)) {
                            infoViewVisible = false
                        }
                    }
                }
            }
            .sheet(isPresented: $showingCertificateInspector) {
                CertificateInspectionView()
                    .frame(minWidth: 600, minHeight: 500)
            }
            .sheet(isPresented: $showingAllLogEntries) {
                if let analysis = parser.analysis {
                    AllLogEntriesView(entries: analysis.allEntries, sourceTitle: analysis.sourceTitle)
                        .frame(minWidth: 900, minHeight: 600)
                }
            }

        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Open Log File…", systemImage: "arrow.up.right") {
                    selectedSyncEvent = nil
                    selectedPolicy = nil
                    parser.analysis = nil
                    parser.error = nil
                    showingFilePicker = true
                }
                .disabled(parser.isLoading)
                .help("Open Log File…")
                .fixedSize()
                .clipped()
                .frame(width: sidebarVisibility != .doubleColumn ? 0 : nil)
                .opacity(sidebarVisibility != .doubleColumn ? 0 : 1)
                .scaleEffect(sidebarVisibility != .doubleColumn ? 0.5 : 1)
                .allowsHitTesting(sidebarVisibility == .doubleColumn)
                .animation(.easeInOut(duration: 0.25), value: sidebarVisibility)

                Button("Reload Local Logs…", systemImage: "arrow.clockwise") {
                    selectedSyncEvent = nil
                    selectedPolicy = nil
                    parser.loadLocalIntuneLogs()
                }
                .disabled(parser.isLoading)
                .help("Reload Local Logs…")
                .fixedSize()
                .clipped()
                .frame(width: sidebarVisibility != .doubleColumn ? 0 : nil)
                .opacity(sidebarVisibility != .doubleColumn ? 0 : 1)
                .scaleEffect(sidebarVisibility != .doubleColumn ? 0.5 : 1)
                .allowsHitTesting(sidebarVisibility == .doubleColumn)
                .animation(.easeInOut(duration: 0.25), value: sidebarVisibility)

                Button("View All Log Entries", systemImage: "text.page.badge.magnifyingglass") {
                    showingAllLogEntries = true
                }
                .disabled(parser.analysis == nil)
                .help("View All Log Entries")
                .fixedSize()
                .clipped()
                .frame(width: sidebarVisibility != .doubleColumn ? 0 : nil)
                .opacity(sidebarVisibility != .doubleColumn ? 0 : 1)
                .scaleEffect(sidebarVisibility != .doubleColumn ? 0.5 : 1)
                .allowsHitTesting(sidebarVisibility == .doubleColumn)
                .animation(.easeInOut(duration: 0.25), value: sidebarVisibility)

                Button("Inspect MDM Certificate", systemImage: "text.viewfinder") {
                    showingCertificateInspector = true
                }
                .help("Inspect MDM Certificate")
                .fixedSize()
                .clipped()
                .frame(width: sidebarVisibility != .doubleColumn ? 0 : nil)
                .opacity(sidebarVisibility != .doubleColumn ? 0 : 1)
                .scaleEffect(sidebarVisibility != .doubleColumn ? 0.5 : 1)
                .allowsHitTesting(sidebarVisibility == .doubleColumn)
                .animation(.easeInOut(duration: 0.25), value: sidebarVisibility)

                Image(systemName: "watch.analog")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 18))
                    .tooltip("IntuneLogWatch: This view shows you all the events loaded from the selected log file. You can view events and policies by clicking on them.")
                
            }
        }
        
        if infoViewVisible {
            bottomBarExpanded
                .animation(.easeInOut(duration: 0.25), value: infoViewVisible)

        } else {
            bottomBarExpander
                .animation(.easeInOut(duration: 0.25), value: infoViewVisible)
        }
    }
    
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            if parser.isLoading {
                ProgressView("Parsing log file...")
//                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let analysis = parser.analysis {
                
                Group {
                    appInfoHeader()
                    enrollmentHeader(analysis)
                    networkHeader(analysis)
                    analysisHeader(analysis)

                    filterControls(analysis: analysis)
                    sortControls

                }
                .background(Color(NSColor.controlBackgroundColor))

                
                if #available(macOS 14.0, *) {
                    List(sortedSyncEvents(analysis.syncEvents), selection: $selectedSyncEvent) { syncEvent in
                        SyncEventRow(
                            syncEvent: syncEvent,
                            isSelected: selectedSyncEvent?.id == syncEvent.id
                        )
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Spacer()
                Button("Open Log File…", systemImage: "arrow.up.right") {
                    selectedSyncEvent = nil
                    selectedPolicy = nil
                    parser.analysis = nil
                    parser.error = nil
                    showingFilePicker = true
                }
                .disabled(parser.isLoading)
                .help("Open Log File…")
                .fixedSize()
                .clipped()
                .frame(width: sidebarVisibility != .doubleColumn ? nil : 0)
                .opacity(sidebarVisibility != .doubleColumn ? 1 : 0)
                .scaleEffect(sidebarVisibility != .doubleColumn ? 1 : 0.5)
                .allowsHitTesting(sidebarVisibility != .doubleColumn)
                .animation(.easeInOut(duration: 0.25), value: sidebarVisibility)

                Button("Reload Local Logs…", systemImage: "arrow.clockwise") {
                    selectedSyncEvent = nil
                    selectedPolicy = nil
                    parser.loadLocalIntuneLogs()
                }
                .disabled(parser.isLoading)
                .help("Reload Local Logs…")
                .fixedSize()
                .clipped()
                .frame(width: sidebarVisibility != .doubleColumn ? nil : 0)
                .opacity(sidebarVisibility != .doubleColumn ? 1 : 0)
                .scaleEffect(sidebarVisibility != .doubleColumn ? 1 : 0.5)
                .allowsHitTesting(sidebarVisibility != .doubleColumn)
                .animation(.easeInOut(duration: 0.25), value: sidebarVisibility)

                Button("View All Log Entries", systemImage: "text.page.badge.magnifyingglass") {
                    showingAllLogEntries = true
                }
                .disabled(parser.analysis == nil)
                .help("View All Log Entries")
                .fixedSize()
                .clipped()
                .frame(width: sidebarVisibility != .doubleColumn ? nil : 0)
                .opacity(sidebarVisibility != .doubleColumn ? 1 : 0)
                .scaleEffect(sidebarVisibility != .doubleColumn ? 1 : 0.5)
                .allowsHitTesting(sidebarVisibility != .doubleColumn)
                .animation(.easeInOut(duration: 0.25), value: sidebarVisibility)

                Button("Inspect MDM Certificate", systemImage: "text.viewfinder") {
                    showingCertificateInspector = true
                }
                .help("Inspect MDM Certificate")
                .fixedSize()
                .clipped()
                .frame(width: sidebarVisibility != .doubleColumn ? nil : 0)
                .opacity(sidebarVisibility != .doubleColumn ? 1 : 0)
                .scaleEffect(sidebarVisibility != .doubleColumn ? 1 : 0.5)
                .allowsHitTesting(sidebarVisibility != .doubleColumn)
                .animation(.easeInOut(duration: 0.25), value: sidebarVisibility)
            }
        }
        .id(colorScheme)
    }

    private var bottomBarExpanded: some View {
        VStack() {
            HStack (alignment: .bottom) {
                Label("Show Bottom Bar", systemImage: "line.3.horizontal")
                    .foregroundColor(.blue)
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
                    .alignmentGuide(.bottom) { $0[HorizontalAlignment.center] }
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .help("Show Bottom Bar")

            HStack(alignment: .firstTextBaseline, spacing: 3) {

                if let icon = AppIconProvider.appIcon() {
                    Image(nsImage: icon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .offset(x: 0, y: 6)
                        .onTapGesture {
                            NSApplication.shared.orderFrontStandardAboutPanel(self)
                            
                            withAnimation(.spring(duration: 1.0, bounce: 0.5, blendDuration: 1.0)) {
                                infoViewVisible = false
                            }
                        }
                }

                Text("IntuneLogWatch")
                    .font(.system(size: 16, weight: .bold))
                    .padding(.trailing, 4)

                let version = AppVersionProvider.fullVersionString()

                Text("v\(version)")

                Spacer()

                HStack(spacing: 8) {
                    Button(action: {
                        let logsPath = "/Library/Logs/Microsoft/Intune"
                        NSWorkspace.shared.open (URL(fileURLWithPath: logsPath))
                        
                        withAnimation(.spring(duration: 1.0, bounce: 0.5, blendDuration: 1.0)) {
                            infoViewVisible = false
                        }
                    }) {
                        Label("Intune Logs", systemImage: "arrow.up.folder")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .padding(2)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .border(.black)
                    .cornerRadius(8)
                    .tooltip("/Library/Logs/Microsoft/Intune")

                    Button(action: {
                        // Post notification to open clip library
                        NotificationCenter.default.post(name: .openClipLibrary, object: nil)

                        withAnimation(.spring(duration: 1.0, bounce: 0.5, blendDuration: 1.0)) {
                            infoViewVisible = false
                        }
                    }) {
                        Label("Clip Library", systemImage: "scissors")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .padding(2)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .border(.black)
                    .cornerRadius(8)
                    .tooltip("IntuneLogWatch Clip Library")

                    Button(action: {
                        NotificationCenter.default.post(name: .showErrorCodesReference, object: nil)
                        
                        withAnimation(.spring(duration: 1.0, bounce: 0.5, blendDuration: 1.0)) {
                            infoViewVisible = false
                        }
                    }) {
                        Label("Error Codes", systemImage: "exclamationmark.triangle")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .padding(2)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .border(.black)
                    .cornerRadius(8)
                    .tooltip("Intune Error Codes Reference")

                    Button(action: {
                        let urlString = "https://github.com/gilburns/IntuneLogWatch/wiki"
                        NSWorkspace.shared.open (URL(string: urlString)!)
                        
                        withAnimation(.spring(duration: 1.0, bounce: 0.5, blendDuration: 1.0)) {
                            infoViewVisible = false
                        }
                    }) {
                        Label("Wiki", systemImage: "document")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .padding(2)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .border(.black)
                    .cornerRadius(8)
                    .tooltip("https://github.com/gilburns/IntuneLogWatch/wiki")

                    Button(action: {
                        let urlString = "https://github.com/gilburns/IntuneLogWatch/releases/tag/\(version)/"
                        NSWorkspace.shared.open (URL(string: urlString)!)
                        
                        withAnimation(.spring(duration: 1.0, bounce: 0.5, blendDuration: 1.0)) {
                            infoViewVisible = false
                        }
                    }) {
                        Label("Release Notes", systemImage: "music.note")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .padding(2)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .border(.black)
                    .cornerRadius(8)
                    .tooltip("https://github.com/gilburns/IntuneLogWatch/releases/tag/\(version)/")

                    Button(action: {
                        let urlString = "https://developer.microsoft.com/en-us/graph/graph-explorer"
                        NSWorkspace.shared.open (URL(string: urlString)!)
                        
                        withAnimation(.spring(duration: 1.0, bounce: 0.5, blendDuration: 1.0)) {
                            infoViewVisible = false
                        }
                    }) {
                        Label("Graph Explorer", systemImage: "curlybraces.square")
                            .frame(minWidth: 110)
                    }
                    .buttonStyle(.link)
                    .controlSize(.small)
                    .padding(2)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .border(.black)
                    .cornerRadius(8)
                    .tooltip("https://developer.microsoft.com/en-us/graph/graph-explorer")
                    
                }

            }
            .padding(.top, 0)
            .padding(.bottom, 12)
            .padding(.leading, 20)
            .padding(.trailing, 20)
            .cornerRadius(10)

        }
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(Divider(), alignment: .top)
    }
    
    private var bottomBarExpander: some View {
        HStack (alignment: .top) {
            Label("Show Bottom Bar", systemImage: "line.3.horizontal.decrease")
                .foregroundColor(.blue)
                .imageScale(.medium)
                .padding(.bottom, 6)
                .offset(x: 0, y: 3)
                .labelStyle(.iconOnly)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(duration: 1.0, bounce: 0.5, blendDuration: 1.0)) {
                infoViewVisible = true
            }
        }
        .help("Show IntuneLogWatcher action bar")
        .padding(.leading, 30)
        .padding(.trailing, 30)
    }

    private func handleMouseMoved(_ event: NSEvent, windowHeight: CGFloat) {
        // In macOS window coordinates, (0,0) is bottom-left.
        let mouseYLocation = event.locationInWindow.y
        
        // Check if the mouse is within the bottom threshold
        if mouseYLocation >= bottomThreshold {
            if infoViewVisible {
                withAnimation(.spring(duration: 1.0, bounce: 0.5, blendDuration: 1.0)) {
                    infoViewVisible = false
                }
            }
        } else {
//            if !infoViewVisible {
//                infoViewVisible = true
//            }
        }
    }

    private func appInfoHeader() -> some View {
        VStack(alignment: .leading, spacing: 2) {
                        
            VStack {
                AppVersionInformationView(
                    versionString: AppVersionProvider.appVersion(),
                    appIcon: AppIconProvider.appIcon()
                )
            }
            .padding(.bottom, 8)
            .padding(.leading, 10)

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
                    .padding(.bottom, 6)
                    
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

                            GridRow {
                                Divider()
                                    .background(Color.blue)
                                    .opacity(0.3)
                                    .frame(height: 1)
                                    .padding(.leading, 25)
                                    .gridCellColumns(3)
                            }
                            GridRow {
                                Text("Total:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(String(format: "%d", networkSummary.totalNetworkChecks))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                Text("")
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
                    .padding(.bottom, 6)

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

                VStack {
                    HStack {
                        Label("Parsed log entries: \(analysis.totalEntries)", systemImage: "doc.text.magnifyingglass")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Spacer()
                    }
                    .padding(.leading, 20)
                    .padding(.trailing, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 0)
                    
                    Divider()
                    .padding(.leading, 18)
                    .padding(.trailing, 40)
                    .padding(.bottom, 6)

                    
                    HStack {
                        VStack(alignment: .center, spacing: 2) {
                            Label("\(analysis.totalSyncEvents)", systemImage: "clock")
                                .font(.caption)
                                .foregroundColor(.blue)
                            Text("events")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        Spacer()

                        VStack(alignment: .center, spacing: 2) {
                            Label("\(analysis.completedSyncs)", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                            Text("completed")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        Spacer()

                        VStack(alignment: .center, spacing: 2) {
                            Label("\(analysis.failedSyncs)", systemImage: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.red)
                            Text("failed events")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                        Spacer()
                    }
                    .padding(.leading, 20)
                    .padding(.trailing, 10)
                    .padding(.bottom, 6)

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
                    .padding(.bottom, 6)

                }
             }
            .font(.headline)
            .padding(.leading, 10)

            Divider()
            .padding(.bottom, 6)
            
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
    
    private func filterControls(analysis: LogAnalysis) -> some View {
        let syncCount = analysis.syncEvents.filter { $0.eventType == .fullSync }.count
        let recurringCount = analysis.syncEvents.filter { $0.eventType == .recurringPolicy }.count
        let healthCount = analysis.syncEvents.filter { $0.eventType == .healthPolicy }.count

        return VStack(spacing: 0) {

            HStack {
                Text("Event Type:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 2)
            
            HStack(spacing: 4) {
                ForEach(EventFilter.allCases, id: \.self) { filter in
                    Button(action: {
                        eventFilter = filter
                    }) {
                        
                        Text(filter.displayNameWithCount(syncCount: syncCount, recurringCount: recurringCount, healthCount: healthCount))
                            .multilineTextAlignment(.center)
                            .font(.caption)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 8)
                            .frame(maxWidth: .infinity)
                            .background(eventFilter == filter ? Color.accentColor : Color.gray.opacity(0.2))
                            .foregroundColor(eventFilter == filter ? .white : .primary)
                            .cornerRadius(4)
                            .tooltip(filter.toolTipForFilter())

                    }
                    .buttonStyle(.plain)
                    .buttonBorderShape(.roundedRectangle)
                    .keyboardShortcut(filter.keyboardShortcut)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 2)
            .onChange(of: eventFilter) { oldValue, newValue in
                // Save filter preference to UserDefaults
                UserDefaults.standard.set(newValue.rawValue, forKey: "EventFilterPreference")

                // Clear selection first
                selectedSyncEvent = nil
                selectedPolicy = nil

                // Delay the selection to allow the List to update its content first
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    let filteredEvents = sortedSyncEvents(analysis.syncEvents)
                    if !filteredEvents.isEmpty {
                        selectedSyncEvent = filteredEvents.first
                    }
                }
            }
            HStack(spacing: 4) {
                Button(action: {}) {
                    Text("⌘1")
                        .font(.caption)
                        .foregroundColor(eventFilter == .syncOnly ? .blue : .secondary)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)

                }
                .background(Color(NSColor.controlBackgroundColor))
                .buttonStyle(.borderless)

                Button(action: {}) {
                    Text("⌘2")
                        .font(.caption)
                        .foregroundColor(eventFilter == .recurringOnly ? .blue : .secondary)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)

                }
                .background(Color(NSColor.controlBackgroundColor))
                .buttonStyle(.borderless)

                Button(action: {}) {
                    Text("⌘3")
                        .font(.caption)
                        .foregroundColor(eventFilter == .healthOnly ? .blue : .secondary)
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity)

                }
                .background(Color(NSColor.controlBackgroundColor))
                .buttonStyle(.borderless)

            }
            .padding(.horizontal)
            .padding(.vertical, 2)

        }
        .background(Color(NSColor.controlBackgroundColor))
        .padding(.bottom, 6)
    }

    private var sortControls: some View {
        VStack {
            HStack {
                Text("Event Sort:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            .padding(.horizontal)
            .background(Color(NSColor.controlBackgroundColor))

            HStack {
                Spacer()
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
                .keyboardShortcut(.upArrow)
                
                Text("⌘↑")
                    .font(.caption)
                    .foregroundColor(sortNewestFirst ? .secondary : .blue)
                    .fontWeight(sortNewestFirst ? .regular : .medium)

                Spacer()

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
                .keyboardShortcut(.downArrow)
                
                Text("⌘↓")
                    .font(.caption)
                    .foregroundColor(sortNewestFirst ? .blue : .secondary)
                    .fontWeight(sortNewestFirst ? .medium : .regular)

                Spacer()
                
            }
            .padding(.horizontal)
            .padding(.bottom, 6)
            .background(Color(NSColor.controlBackgroundColor))

        }
        .background(Color(NSColor.controlBackgroundColor))
    }
        
    private func sortedSyncEvents(_ syncEvents: [SyncEvent]) -> [SyncEvent] {
        // First, apply the filter
        var filteredEvents = syncEvents
        switch eventFilter {
//        case .all:
//            // Show only Sync and Recurring events (exclude health events as they're too frequent)
//            filteredEvents = syncEvents.filter { $0.eventType == .fullSync || $0.eventType == .recurringPolicy }
        case .syncOnly:
            filteredEvents = syncEvents.filter { $0.eventType == .fullSync }
        case .recurringOnly:
            filteredEvents = syncEvents.filter { $0.eventType == .recurringPolicy }
        case .healthOnly:
            filteredEvents = syncEvents.filter { $0.eventType == .healthPolicy }
        }

        // Then, apply the sort
        if sortNewestFirst {
            return filteredEvents.sorted { $0.startTime > $1.startTime }
        } else {
            return filteredEvents.sorted { $0.startTime < $1.startTime }
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
    let isSelected: Bool
    @State private var isHovered: Bool = false

    init(syncEvent: SyncEvent, isSelected: Bool = false) {
        self.syncEvent = syncEvent
        self.isSelected = isSelected
    }

    private var eventLabel: String {
        switch syncEvent.eventType {
        case .fullSync:
            return syncEvent.isComplete ? "Sync Event" : "Sync Event (In Progress)"
        case .recurringPolicy:
            return syncEvent.isComplete ? "Recurring Event" : "Recurring Event (In Progress)"
        case .healthPolicy:
            let healthPolicyName: String = syncEvent.policies.first?.displayName ?? "Unknown"
            let healthPolicyDomain = healthPolicyName.split(separator: " - ").last ?? ""
            return syncEvent.isComplete ? "Health Event - \(healthPolicyDomain)" : "Health Event - \(healthPolicyDomain) (In Progress)"
        }
    }

    private var eventIcon: String {
        switch syncEvent.eventType {
        case .fullSync:
            return "gearshape.arrow.triangle.2.circlepath"
        case .recurringPolicy:
            return "clock.arrow.circlepath"
        case .healthPolicy:
            return "stethoscope"
        }
    }

    private var eventIconColor: Color {
        switch syncEvent.eventType {
        case .fullSync:
            return .blue
        case .recurringPolicy:
            return .blue
        case .healthPolicy:
            return .purple
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {

                Image(systemName: eventIcon)
                    .foregroundColor(eventIconColor)
                Text(eventLabel)
                    .font(.headline)
                Spacer()
                Text(formatTime(syncEvent.startTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .tooltip(formatTimeFull(syncEvent.startTime))
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
        .padding(.bottom, 4)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.accentColor.opacity(isHovered && !isSelected ? 0.2 : 0))
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }

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

    private func formatTimeFull(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .full
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
