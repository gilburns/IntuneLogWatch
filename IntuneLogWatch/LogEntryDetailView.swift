//
//  LogEntryDetailView.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import SwiftUI

struct LogEntryDetailView: View {
    let displayName: String
    let bundleIdentifier: String
    let policyType: PolicyType
    let entries: [LogEntry]
    @State private var currentIndex: Int
    @Environment(\.presentationMode) var presentationMode
    
    init(displayName: String, bundleIdentifier: String, policyType: PolicyType, entries: [LogEntry], currentIndex: Int) {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.policyType = policyType
        self.entries = entries
        self._currentIndex = State(initialValue: currentIndex)
    }
    
    private var entry: LogEntry {
        entries[currentIndex]
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                
                HStack {
                    AppIconView(
                        bundleId: bundleIdentifier,
                        policyType: policyType,
                        size: 48
                    )
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.title2)
                            .fontWeight(.semibold)
                        
                        Text("Log Entry Details")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Divider()
                
                HStack {
                    levelIcon
                    Text(entry.level.displayName)
                        .font(.caption)
                    
                    Spacer()
                    
                    Text(formatDateTime(entry.timestamp))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            
            Grid(alignment: .center, horizontalSpacing: 10, verticalSpacing: 4) {
                GridRow {
                    Text("Component:")
                        .fontWeight(.medium)
                        .gridColumnAlignment(.trailing)
                    
                    Text(entry.component)
                        .foregroundColor(.secondary)
                        .gridColumnAlignment(.leading)
                    
                    Spacer()
                        .gridColumnAlignment(.center)
                    
                    Text("Thread:")
                        .fontWeight(.medium)
                        .gridColumnAlignment(.trailing)
                    
                    Text(entry.threadId)
                        .foregroundColor(.secondary)
                        .gridColumnAlignment(.trailing)
                }
                .font(.caption)
                
                GridRow {
                    if let policyId = entry.policyId {
                        Text("Policy ID:")
                            .fontWeight(.medium)
                            .gridColumnAlignment(.trailing)
                        
                        Text(policyId)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .gridColumnAlignment(.leading)
                        
                        Spacer()
                            .gridColumnAlignment(.center)
                        
                        Text("")
                            .gridColumnAlignment(.trailing)
                        
                        Text("")
                            .gridColumnAlignment(.trailing)
                    } else {
                        Text("")
                            .gridColumnAlignment(.trailing)
                        Text("")
                            .gridColumnAlignment(.leading)
                        Spacer()
                            .gridColumnAlignment(.center)
                        Text("")
                            .gridColumnAlignment(.trailing)
                        Text("")
                            .gridColumnAlignment(.trailing)
                    }
                }
                .font(.caption)

                GridRow {
                    if let bundleId = entry.bundleId {
                        Text("Bundle ID:")
                            .fontWeight(.medium)
                            .gridColumnAlignment(.trailing)
                        
                        Text(bundleId)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .gridColumnAlignment(.leading)
                        
                        Spacer()
                            .gridColumnAlignment(.center)
                        
                        Text("")
                            .gridColumnAlignment(.trailing)
                        
                        Text("")
                            .gridColumnAlignment(.trailing)
                    } else {
                        Text("")
                            .gridColumnAlignment(.trailing)
                        Text("")
                            .gridColumnAlignment(.leading)
                        Spacer()
                            .gridColumnAlignment(.center)
                        Text("")
                            .gridColumnAlignment(.trailing)
                        Text("")
                            .gridColumnAlignment(.trailing)
                    }
                }
                .font(.caption)
                
            }
            
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Message")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(action: copyMessage) {
                        Label("Copy", systemImage: "document.on.clipboard")
                    }
                    .buttonStyle(PressedCopyButtonStyle())
                    .controlSize(.small)
                    .keyboardShortcut("c", modifiers: .command)
                    
                }
                
                ScrollView {
                    Text(entry.message)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 90, idealHeight: 90, maxHeight: 200)
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Raw Log Line")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(action: copyRawLine) {
                        Label("Copy", systemImage: "document.on.clipboard")
                    }
                    .buttonStyle(PressedCopyButtonStyle())
                    .controlSize(.small)
                    .keyboardShortcut("c", modifiers: .control)
                }
                
                ScrollView {
                    Text(entry.rawLine)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 90, idealHeight: 90, maxHeight: 200)
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
            
            HStack {
                Spacer()
                
                HStack(spacing: 8) {
                    Button(action: previousEntry) {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(currentIndex <= 0)
                    .keyboardShortcut("[", modifiers: .command)

                    Text("\(currentIndex + 1) of \(entries.count)")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: nextEntry) {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(currentIndex >= entries.count - 1)
                    .keyboardShortcut("]", modifiers: .command)
                }
                
                Spacer()
                
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.escape)
                
            }
        }
        .padding()
        .frame(minWidth: 650, idealWidth: 650, maxWidth: 800, minHeight: 550, idealHeight: 550, maxHeight: 700)
        .presentationBackground(Color.gray.opacity(0.07))
    }
    
    private var levelIcon: some View {
        Group {
            switch entry.level {
            case .info:
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.blue)
            case .warning:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            case .error:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            case .debug:
                Image(systemName: "ladybug.fill")
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private func copyMessage() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.message, forType: .string)
    }
    
    private func copyRawLine() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.rawLine, forType: .string)
    }
    
    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
    
    private func previousEntry() {
        if currentIndex > 0 {
            currentIndex -= 1
        }
    }
    
    private func nextEntry() {
        if currentIndex < entries.count - 1 {
            currentIndex += 1
        }
    }
}


struct PressedCopyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}
