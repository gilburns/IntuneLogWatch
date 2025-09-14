//
//  ErrorCodesReferenceViewSimple.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 9/13/25.
//

import SwiftUI

struct ErrorCodesReferenceViewSimple: View {
    @State private var searchText = ""

    private var filteredErrorCodes: [IntuneErrorCode] {
        let allCodes = IntuneErrorCodeLookup.shared.getAllErrorCodes()

        if searchText.isEmpty {
            return allCodes.sorted { $0.hexCode < $1.hexCode }
        } else {
            return allCodes.filter { errorCode in
                errorCode.hexCode.localizedCaseInsensitiveContains(searchText) ||
                errorCode.code.localizedCaseInsensitiveContains(searchText) ||
                errorCode.title.localizedCaseInsensitiveContains(searchText) ||
                errorCode.description.localizedCaseInsensitiveContains(searchText) ||
                errorCode.recommendation.localizedCaseInsensitiveContains(searchText)
            }.sorted { $0.hexCode < $1.hexCode }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerSection

            Divider()

            // Content
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(filteredErrorCodes, id: \.hexCode) { errorCode in
                        ErrorCodeRowView(errorCode: errorCode)
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        .navigationTitle("Error Codes Reference")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Microsoft Intune Error Codes Reference")
                .font(.title)
                .fontWeight(.bold)

            Text("\(filteredErrorCodes.count) known error codes")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Search error codes, titles, or descriptions...", text: $searchText)
                .textFieldStyle(.roundedBorder)
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
    }
}

struct ErrorCodeRowView: View {
    let errorCode: IntuneErrorCode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header row with codes and title
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(errorCode.hexCode)
                        .font(.system(.subheadline, design: .monospaced))
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                        .textSelection(.enabled)

                    Text(errorCode.code)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                .frame(width: 120, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(errorCode.title)
                        .font(.headline)
                        .fontWeight(.medium)

                    Text("Error Code Details")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            // Description
            Text(errorCode.description)
                .font(.body)
                .foregroundColor(.primary)

            // Recommendation
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "lightbulb.fill")
                    .foregroundColor(.blue)
                    .font(.caption)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Recommendation")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)

                    Text(errorCode.recommendation)
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding()
        .background(Color(NSColor.textBackgroundColor))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .cornerRadius(8)
    }
}

// Simple window controller for the error codes reference
class ErrorCodesReferenceWindowControllerSimple: NSWindowController {
    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Intune Error Codes Reference"
        window.contentView = NSHostingView(rootView: ErrorCodesReferenceViewSimple())
        window.center()
        window.setFrameAutosaveName("ErrorCodesReference")

        self.init(window: window)
    }
}

#Preview {
    ErrorCodesReferenceViewSimple()
        .frame(width: 900, height: 600)
}