//
//  LOBSidebarView.swift
//  IntuneLogWatch
//
//  LOB event row view for the unified sidebar.
//

import SwiftUI

// MARK: - LOB Event Row

struct LOBEventRow: View {
    let event: LOBAppEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "shippingbox.fill")
                    .foregroundColor(.indigo)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    if let pkgId = event.packageId {
                        Text(pkgId)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 2) {
                    statusBadge
                    Text(formatDateTime(event.timestamp))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 4) {
                ChannelBadge(channel: .managedLOB)

                if let version = event.packageVersion {
                    Text("v\(version)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Color.gray.opacity(0.15))
                        .foregroundColor(.secondary)
                        .cornerRadius(3)
                }

                if let duration = event.duration {
                    Text(formatDuration(duration))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    private var statusBadge: some View {
        Text(event.status.displayName)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(statusColor.opacity(0.2))
            .foregroundColor(statusColor)
            .cornerRadius(4)
    }

    private var statusColor: Color {
        switch event.status {
        case .completed: return .green
        case .failed: return .red
        case .installing: return .blue
        case .downloading: return .orange
        case .pending: return .yellow
        case .unknown: return .secondary
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return String(format: "%.1fs", duration)
        } else {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%dm %ds", minutes, seconds)
        }
    }
}
