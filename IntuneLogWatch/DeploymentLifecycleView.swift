//
//  DeploymentLifecycleView.swift
//  IntuneLogWatch
//
//  Visual lifecycle pipeline component showing LOB deployment stages.
//

import SwiftUI

struct DeploymentLifecycleView: View {
    let stages: [LOBLifecycleStageInfo]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                stageView(stage)

                if index < stages.count - 1 {
                    connector(
                        from: stage.status,
                        to: stages[index + 1].status
                    )
                }
            }
        }
        .padding(.vertical, 8)
    }

    private func stageView(_ stage: LOBLifecycleStageInfo) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(stageColor(stage.status).opacity(0.15))
                    .frame(width: 40, height: 40)

                Image(systemName: stageIcon(stage))
                    .foregroundColor(stageColor(stage.status))
                    .font(.system(size: 16))
            }

            Text(stage.stage.rawValue)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)

            if let timestamp = stage.timestamp {
                Text(formatTime(timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(minWidth: 70)
    }

    private func connector(from: LOBDeploymentStatus, to: LOBDeploymentStatus) -> some View {
        Rectangle()
            .fill(connectorColor(from: from, to: to))
            .frame(height: 2)
            .frame(maxWidth: 30)
            .padding(.bottom, 24) // Align with circle center
    }

    private func stageIcon(_ stage: LOBLifecycleStageInfo) -> String {
        switch stage.status {
        case .completed:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .installing, .downloading:
            return "arrow.clockwise"
        case .pending:
            return stage.stage.icon
        case .unknown:
            return "circle.dotted"
        }
    }

    private func stageColor(_ status: LOBDeploymentStatus) -> Color {
        switch status {
        case .completed: return .green
        case .failed: return .red
        case .installing, .downloading: return .blue
        case .pending: return .orange
        case .unknown: return .secondary
        }
    }

    private func connectorColor(from: LOBDeploymentStatus, to: LOBDeploymentStatus) -> Color {
        if from == .completed {
            return .green
        }
        if from == .failed {
            return .red
        }
        return .secondary.opacity(0.3)
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

// MARK: - Helper to build lifecycle stages from a LOBAppEvent

extension LOBAppEvent {
    var lifecycleStages: [LOBLifecycleStageInfo] {
        var stages: [LOBLifecycleStageInfo] = []

        // MDM Command stage
        let mdmEntries = unifiedLogEntries.filter {
            $0.message.lowercased().contains("installapplication") ||
            $0.message.lowercased().contains("mdm command") ||
            $0.message.lowercased().contains("received command")
        }
        let mdmStatus: LOBDeploymentStatus = mdmEntries.isEmpty ? .unknown : .completed
        stages.append(LOBLifecycleStageInfo(
            stage: .mdmCommand,
            status: mdmStatus,
            timestamp: mdmEntries.first?.timestamp ?? (status != .unknown ? timestamp : nil),
            entries: mdmEntries,
            errorMessage: nil
        ))

        // Download stage
        let downloadEntries = unifiedLogEntries.filter {
            $0.message.lowercased().contains("download") ||
            $0.process.lowercased() == "storedownloadd"
        }
        let downloadStatus: LOBDeploymentStatus
        if downloadEntries.contains(where: { $0.level == .error || $0.level == .fault }) {
            downloadStatus = .failed
        } else if !downloadEntries.isEmpty {
            downloadStatus = .completed
        } else if mdmStatus == .completed {
            downloadStatus = status == .unknown ? .unknown : .completed // Assume download happened
        } else {
            downloadStatus = .unknown
        }
        stages.append(LOBLifecycleStageInfo(
            stage: .download,
            status: downloadStatus,
            timestamp: downloadEntries.first?.timestamp,
            entries: downloadEntries,
            errorMessage: downloadEntries.first(where: { $0.level == .error })?.message
        ))

        // Installation stage
        let installEntries = unifiedLogEntries.filter {
            $0.message.lowercased().contains("install") &&
            !$0.message.lowercased().contains("installapplication")
        }
        let allInstallEntries = installEntries + unifiedLogEntries.filter { $0.process.lowercased() == "installer" }
        let installStatus: LOBDeploymentStatus
        if allInstallEntries.contains(where: { $0.level == .error || $0.level == .fault }) {
            installStatus = .failed
        } else if !allInstallEntries.isEmpty || !installLogEntries.isEmpty {
            installStatus = .completed
        } else if downloadStatus == .completed && status == .completed {
            installStatus = .completed
        } else {
            installStatus = status == .failed ? .failed : .unknown
        }
        stages.append(LOBLifecycleStageInfo(
            stage: .installation,
            status: installStatus,
            timestamp: allInstallEntries.first?.timestamp ?? installLogEntries.first?.timestamp,
            entries: allInstallEntries,
            errorMessage: allInstallEntries.first(where: { $0.level == .error })?.message
        ))

        // Verification stage
        let verificationStatus: LOBDeploymentStatus
        if receiptInfo != nil {
            verificationStatus = .completed
        } else if status == .completed {
            verificationStatus = .completed
        } else if status == .failed {
            verificationStatus = .failed
        } else {
            verificationStatus = .unknown
        }
        stages.append(LOBLifecycleStageInfo(
            stage: .verification,
            status: verificationStatus,
            timestamp: receiptInfo?.installDate,
            entries: [],
            errorMessage: nil
        ))

        return stages
    }
}
