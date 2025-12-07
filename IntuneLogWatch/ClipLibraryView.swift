//
//  ClipLibraryView.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import Foundation
import SwiftUI
import ObjectiveC

// MARK: - Window Wrapper (for opening from menu)

struct ClipLibraryWindowWrapper: View {
    var body: some View {
        ClipLibraryView()
    }
}

// MARK: - Clip Event Dialog

struct ClipEventDialog: View {
    let policy: PolicyExecution
    @Environment(\.dismiss) private var dismiss
    @State private var customName: String = ""
    @State private var notes: String = ""
    let onSave: (String, String) -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Text("Save Policy Event to Clip Library")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Policy: \(policy.displayName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Custom Name Field
            VStack(alignment: .leading, spacing: 4) {
                Text("Custom Name (optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextField("Leave empty to use policy name", text: $customName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
            }
            
            // Notes Field
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes (optional)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $notes)
                    .frame(height: 100)
                    .border(Color.gray.opacity(0.3), width: 1)
                    .cornerRadius(4)
            }
            
            Divider()
            
            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Save to Library") {
                    onSave(customName, notes)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 450)
    }
}

// MARK: - Clip Library Window

struct ClipLibraryView: View {
    @ObservedObject var libraryManager = ClipLibraryManager.shared
    @State private var searchText = ""
    @State private var selectedEvent: ClippedPolicyEvent?
    @State private var sortOption: SortOption = .dateClippedNewest
    @State private var showingDeleteConfirmation = false
    @State private var eventToDelete: ClippedPolicyEvent?
    
    enum SortOption: String, CaseIterable {
        case dateClippedNewest = "Clipped Date (Newest First)"
        case dateClippedOldest = "Clipped Date (Oldest First)"
        case dateEventNewest = "Event Date (Newest First)"
        case dateEventOldest = "Event Date (Oldest First)"
        case nameAZ = "Name (A-Z)"
        case nameZA = "Name (Z-A)"
    }
    
    var filteredAndSortedEvents: [ClippedPolicyEvent] {
        var events = libraryManager.clippedEvents
        
        // Filter by search text
        if !searchText.isEmpty {
            events = events.filter { event in
                event.displayName.localizedCaseInsensitiveContains(searchText) ||
                event.notes.localizedCaseInsensitiveContains(searchText) ||
                event.policyExecution.policyId.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Sort
        switch sortOption {
        case .dateClippedNewest:
            events.sort { $0.clippedDate > $1.clippedDate }
        case .dateClippedOldest:
            events.sort { $0.clippedDate < $1.clippedDate }
        case .dateEventNewest:
            events.sort { $0.policyExecution.startTime! > $1.policyExecution.startTime! }
        case .dateEventOldest:
            events.sort { $0.policyExecution.startTime! < $1.policyExecution.startTime! }
        case .nameAZ:
            events.sort { $0.displayName.localizedCompare($1.displayName) == .orderedAscending }
        case .nameZA:
            events.sort { $0.displayName.localizedCompare($1.displayName) == .orderedDescending }
        }
        
        return events
    }
    
    var body: some View {
        NavigationSplitView {
            // Sidebar - List of clipped events
            VStack(spacing: 0) {
                Divider()

                // Search
                VStack {
                    HStack {
                        Text("Search:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)

                        Spacer()
                    }

                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search clips...", text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(.title3))
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)

                }
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.top, 0)
                .padding(.bottom, 4)

                VStack {
                    HStack {
                        Text("Sort By:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)

                        Spacer()
                    }
                    // Sort
                    Picker("Sort by", selection: $sortOption) {
                        ForEach(SortOption.allCases, id: \.self) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .labelsHidden()
                }
                .padding(.leading, 16)
                .padding(.trailing, 16)
                .padding(.top, 2)
                .padding(.bottom, 8)
                
                Divider()
                    .padding(.top, 0)
                    .padding(.bottom, 4)

                // Event List
                ScrollViewReader { proxy in
                    List(filteredAndSortedEvents, selection: $selectedEvent) { event in
                        ClipEventRow(
                            event: event,
                            isSelected: selectedEvent?.id == event.id,
                            onRevealInFinder: { revealClipInFinder(event) },
                            onDelete: {
                                eventToDelete = event
                                showingDeleteConfirmation = true
                            }
                        )
                        .tag(event)
                        .id(event.id)
                    }
                    .onChange(of: searchText) { oldValue, newValue in
                        // Scroll to top when search text changes
                        if let firstEvent = filteredAndSortedEvents.first {
                            withAnimation {
                                proxy.scrollTo(firstEvent.id, anchor: .top)
                            }
                        }
                    }
                }

                Divider()
                
                // Storage Info
                HStack {
                    let info = libraryManager.getStorageInfo()
                    Text("\(info.count) clips • \(info.totalSize)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Button(action: {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: info.location)
                    }) {
                        Image(systemName: "folder")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal clip library folder in Finder")
                }
                .padding(8)
            }
            .frame(minWidth: 310.0)
        } detail: {
            // Detail View
            if let event = selectedEvent {
                ClippedEventDetailView(event: event, onDelete: {
                    eventToDelete = event
                    showingDeleteConfirmation = true
                })
                .id(event.id) // Force new view instance when switching clips to reset editing state
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Select a clipped event to view")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("IntuneLogWatch Clip Library")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Image(systemName: "scissors")
                    .foregroundColor(.accentColor)
                    .tooltip("This view shows you all the log events that have been clipped from your Intune policy logs. You can manage the clips here.")
            }
        }
        
        .alert("Delete Clipped Event?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let event = eventToDelete {
                    libraryManager.deleteEvent(event)
                    if selectedEvent?.id == event.id {
                        selectedEvent = nil
                    }
                }
            }
        } message: {
            if let event = eventToDelete {
                Text("Are you sure you want to delete \"\(event.displayName)\"? This action cannot be undone.")
            }
        }
    }
    
    private func revealClipInFinder(_ event: ClippedPolicyEvent) {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let clipDir = appSupport.appendingPathComponent("IntuneLogWatch/ClippedEvents", isDirectory: true)
        let filename = "\(event.id.uuidString).ilwclip"
        let fileURL = clipDir.appendingPathComponent(filename)
        
        // Reveal the specific file in Finder
        NSWorkspace.shared.selectFile(fileURL.path, inFileViewerRootedAtPath: clipDir.path)
    }
}

// MARK: - Clip Event Row

struct ClipEventRow: View {
    let event: ClippedPolicyEvent
    let isSelected: Bool
    let onRevealInFinder: () -> Void
    let onDelete: () -> Void
    @State private var isHovered: Bool = false

    private var policy: PolicyExecution {
        event.policyExecution.toPolicyExecution()
    }

    private var statusColor: Color {
        switch event.policyExecution.status {
        case .completed: return .green
        case .failed: return .red
        case .warning: return .orange
        case .running: return .blue
        case .pending: return .secondary
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            HStack{
                VStack{
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .offset(x: -5, y: -4 - (event.notes.isEmpty ? 0 : 12))

                }
                
                VStack {
                    AppIconView(
                        bundleId: policy.bundleId,
                        policyType: policy.type,
                        size: 42
                    )
                    .offset(x: 0, y: -4 - (event.notes.isEmpty ? 0 : 12))

                }
                .padding(.leading, -6)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(event.displayName)
                            .font(.headline)
                            .lineLimit(1)

                        Spacer()

                    }

                    Grid(alignment: .leading) {
                        GridRow {
                            Text("Event:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(formatDate(event.policyExecution.startTime!))
                                .font(.caption)
                                .foregroundColor(.secondary)

                            if event.policyExecution.hasErrors || event.policyExecution.hasWarnings {
                                HStack (alignment: .top, spacing: 8) {
                                    EmptyView()
                                    Image(systemName: event.policyExecution.hasErrors ? "exclamationmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundColor(event.policyExecution.hasErrors ? .red : .orange)
                                }
                            } else {
                                EmptyView()
                            }
                            
                        }
                        GridRow {
                            Text("Clipped:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text(formatDate(event.clippedDate))
                                .font(.caption)
                                .foregroundColor(.secondary)

                            EmptyView()
                            
                        }

                        if !event.notes.isEmpty {
                            Divider()
                                .gridCellUnsizedAxes(.horizontal)

                            GridRow {
                                Text("Notes:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Text(event.notes)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)

                                EmptyView()
                                
                            }
                        }


                    }
                }
                .padding(.vertical, 4)
            }
            // Hover action buttons
            if isHovered {
                HStack(spacing: 2) {
                    Button(action: onRevealInFinder) {
                        Image(systemName: "arrow.forward.folder")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.blue.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Reveal clip in Finder")

                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(.white)
                            .padding(4)
                            .background(Color.red.opacity(0.7))
                            .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Delete clip")
                }
                .padding(8)
                .offset(x: 12, y: -24 - (event.notes.isEmpty ? 0 : 24))
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
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
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Clipped Event Detail View

struct ClippedEventDetailView: View {
    let event: ClippedPolicyEvent
    let onDelete: () -> Void
    @State private var showingRawLogs = false
    @State private var detailLogEntry: LogEntry?
    @State private var editedName: String = ""
    @State private var editedNotes: String = ""
    @State private var isEditing = false
    @State private var policyIdCopied = false
    @State private var copiedText: String = ""
    @State private var packageReceiptInfo: PackageReceiptInfo?
    @State private var showingClipDialog = false
    @ObservedObject var libraryManager = ClipLibraryManager.shared
    
    // Store policy as a let property so LogEntry IDs remain stable
    private let policy: PolicyExecution
    
    init(event: ClippedPolicyEvent, onDelete: @escaping () -> Void) {
        self.event = event
        self.onDelete = onDelete
        self.policy = event.policyExecution.toPolicyExecution()
        _editedName = State(initialValue: event.customName)
        _editedNotes = State(initialValue: event.notes)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with clip info
            clipInfoHeader
            
            Divider()
            
            // Policy Details (reuse from PolicyDetailView structure)
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
        
    }
    
    // Clip Info Header
    private var clipInfoHeader: some View {
        HStack(alignment: .top, spacing: 1) {
            Text("Your Notes")
                .rotationEffect(.degrees(-90))
                .padding(.leading, -22)
                .padding(.trailing, -20)
                .offset(x: 0, y: 32)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        // Custom Title
                        if isEditing {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Editing Custom Title")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                TextField("Leave empty to use policy name", text: $editedName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }
                        } else {
                            if !editedName.isEmpty {
                                Text(editedName)
                                    .font(editedName.count > 27 ? .title3 : .title2)
                                    .fontWeight(.semibold)
                            } else {
                                Text(policy.displayName)
                                    .font(policy.displayName.count > 27 ? .title3 : .title2)
                                    .fontWeight(.semibold)
                            }
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
                            GridRow {
                                // Notes
                                if isEditing {
                                    Image(systemName: "doc")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                    
                                    Text("Notes:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                } else {
                                    if !editedNotes.isEmpty {
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
                        }
                        HStack {
                            if isEditing {

                                Spacer()
                                    .frame(width: 40)
                                
                                TextEditor(text: $editedNotes)
                                    .frame(height: 60)
                                    .border(Color.gray.opacity(0.3), width: 1)
                                    .cornerRadius(4)


                            } else {
                                if !editedNotes.isEmpty {
                                    Spacer()
                                        .frame(width: 40)

                                    Text(editedNotes)
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .padding(.top, -4)

                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if isEditing {
                            Spacer()
                                .frame(height: 202)
                            Button(action: {
                                editedName = event.customName
                                editedNotes = event.notes
                                isEditing = false
                            }) {
                                Label("Cancel", systemImage: "xmark")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(BorderedButtonStyle())
                            
                            Button(action: {
                                saveChanges()
                            }) {
                                Label("Save", systemImage: "square.and.arrow.down")
                                    .foregroundColor(.blue)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(BorderedButtonStyle())
                        } else {
                            Spacer()
                                .frame(height: 20)
                            
                            Button(action: {
                                isEditing = true
                            }) {
                                Label("Edit", systemImage: "pencil")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(BorderedButtonStyle())
                            
                            Button(action: onDelete) {
                                Label("Delete", systemImage: "trash")
                                    .foregroundColor(.red)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(BorderedButtonStyle())
                            
                        }
                    }
                    .frame(width: 100, height: 20)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5))

        }
    }
    
    private func saveChanges() {
        // Create updated event with new name and notes
        let updatedEvent = ClippedPolicyEvent(
            id: event.id,
            customName: editedName,
            notes: editedNotes,
            clippedDate: event.clippedDate,
            policyExecution: event.policyExecution
        )
        
        libraryManager.updateEvent(updatedEvent)
        isEditing = false
    }
    
    // Reuse PolicyDetailView's header structure
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
            .padding(.bottom, -10)
            
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
                    
                    HStack() {
                        Text("  ")
                        if errorCodes.isEmpty {
                            Label("Error", systemImage: "app.badge.checkmark")
                                .font(.caption)
                                .foregroundColor(.red)

                            Text("")
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Label("Error:", systemImage: "app.badge.checkmark")
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
                            if let firstEntry = policy.entries.first {
                                detailLogEntry = firstEntry
                            }
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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(policy.entries) { entry in
                    TimelineEntryView(entry: entry)
                        .onTapGesture(count: 2) {
                            detailLogEntry = entry
                        }
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
                        .onTapGesture(count: 2) {
                            detailLogEntry = entry
                        }
                }
            }
            .padding()
        }
    }
    
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
