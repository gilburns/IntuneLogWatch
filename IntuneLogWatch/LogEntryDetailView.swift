//
//  LogEntryDetailView.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import SwiftUI

struct LogEntryDetailView: View {
    let entry: LogEntry
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Log Entry Details")
                        .font(.title2)
                        .fontWeight(.semibold)
                    
                    HStack {
                        levelIcon
                        Text(entry.level.displayName)
                            .font(.caption)
                        
                        Spacer()
                        
                        Text(formatDateTime(entry.timestamp))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
                
                Button("Close") {
                    presentationMode.wrappedValue.dismiss()
                }
                .keyboardShortcut(.escape)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Component:")
                        .fontWeight(.medium)
                    Text(entry.component)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("Thread:")
                        .fontWeight(.medium)
                    Text(entry.threadId)
                        .foregroundColor(.secondary)
                }
                .font(.caption)
                
                if let policyId = entry.policyId {
                    HStack {
                        Text("Policy ID:")
                            .fontWeight(.medium)
                        Text(policyId)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    .font(.caption)
                }

                if let bundleId = entry.bundleId {
                    HStack {
                        Text("Bundle ID:")
                            .fontWeight(.medium)
                        Text(bundleId)
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                    .font(.caption)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Message")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button(action: copyMessage) {
                        Label("Copy", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.small)
                }
                
                ScrollView {
                    Text(entry.message)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 200)
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
                        Label("Copy", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(BorderedButtonStyle())
                    .controlSize(.small)
                }
                
                ScrollView {
                    Text(entry.rawLine)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
                .padding()
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                )
            }
        }
        .padding()
        .frame(minWidth: 650, idealWidth: 650, maxWidth: 800, minHeight: 550, idealHeight: 550, maxHeight: 700)
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
}
