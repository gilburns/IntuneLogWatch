//
//  ErrorCodeDetailView.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 9/13/25.
//

import SwiftUI

struct ErrorCodeDetailView: View {
    let errorCode: IntuneErrorCode

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.red)
                    .font(.title2)

                VStack(alignment: .leading, spacing: 2) {
                    Text(errorCode.title)
                        .font(.headline)
                        .fontWeight(.semibold)

                    HStack(spacing: 8) {
                        Text("Code:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(errorCode.code) (\(errorCode.hexCode))")
                            .font(.caption)
                            .fontWeight(.medium)
                            .textSelection(.enabled)
                    }
                }

                Spacer()
            }

            Divider()

            Text(errorCode.description)
                .font(.body)
                .multilineTextAlignment(.leading)
                .textSelection(.enabled)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "lightbulb.fill")
                        .foregroundColor(.blue)
                        .font(.caption)
                    Text("Recommendation")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                }

                Text(errorCode.recommendation)
                    .font(.body)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
            }

            HStack {
                Spacer()
                Text("Microsoft Intune Error Code")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: 450, minHeight: 220)
    }
}

struct ErrorCodeButton: View {
    let errorCode: String
    let hexCode: String?
    @State private var showingPopover = false

    var body: some View {
        Button(action: {
            showingPopover = true
        }) {
            HStack(spacing: 4) {
                if let hexCode = hexCode {
                    Text("\(errorCode) (\(hexCode))")
                } else {
                    Text(errorCode)
                }
                Image(systemName: "info.circle")
                    .font(.caption2)
            }
            .font(.caption)
            .foregroundColor(.red)
        }
        .buttonStyle(BorderlessButtonStyle())
        .popover(isPresented: $showingPopover) {
            if let errorDetails = IntuneErrorCodeLookup.shared.getErrorDetails(for: errorCode) {
                ErrorCodeDetailView(errorCode: errorDetails)
            } else {
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "questionmark.circle")
                            .foregroundColor(.secondary)
                        Text("Unknown Error Code")
                            .font(.headline)
                    }
                    Text("No additional information available for this error code.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                    if let hexCode = hexCode {
                        Text("\(errorCode) (\(hexCode))")
                            .font(.caption)
                            .fontWeight(.medium)
                            .textSelection(.enabled)
                    } else {
                        Text(errorCode)
                            .font(.caption)
                            .fontWeight(.medium)
                            .textSelection(.enabled)
                    }
                }
                .padding()
                .frame(maxWidth: 350, minHeight: 120)
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ErrorCodeButton(errorCode: "-2016330846", hexCode: "0x87D13BA2")
        ErrorCodeButton(errorCode: "-2016214707", hexCode: "0x87D3014D")
        ErrorCodeButton(errorCode: "12345", hexCode: nil)
    }
    .padding()
}