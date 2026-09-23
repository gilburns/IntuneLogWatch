# IntuneLogWatchLOB - Design Document

## Overview

IntuneLogWatchLOB is a fork of [IntuneLogWatch](https://github.com/gilburns/IntuneLogWatch) that adds visibility into macOS Intune LOB (Line of Business) app deployments. The upstream project only monitors the Intune sidecar agent (`IntuneMDMDaemon`) logs. This fork adds monitoring of the Apple native MDM channel (`mdmclient`) which handles managed PKG deployments.

## Problem Statement

Intune uses two completely separate channels for deploying apps to macOS:

| Aspect | LOB (Managed PKG) | Agent (DMG/Unmanaged PKG) |
|---|---|---|
| Mechanism | Apple native MDM `InstallApplication` | Intune sidecar agent |
| Process | `mdmclient` | `IntuneMDMDaemon` |
| Log Location | macOS unified log (`com.apple.ManagedClient`) | `/Library/Logs/Microsoft/Intune/IntuneMDMDaemon*.log` |
| Install Logs | `/var/log/install.log`, `/Library/Receipts/InstallHistory.plist` | Inline in IntuneMDMDaemon |
| Visible in Upstream? | **No** | Yes |

LOB apps deployed via the native MDM channel are completely invisible in the upstream IntuneLogWatch.

## Architecture

### Data Flow

```
macOS Unified Log ──> UnifiedLogReader ──┐
                                          │
/var/log/install.log ──> InstallLogParser ──> LOBCorrelationEngine ──> LOBAppEvent[]
                                          │
InstallHistory.plist ──> InstallHistoryParser ──┘
```

### New Files

| File | Purpose |
|------|---------|
| `LOBModels.swift` | Data models: `LOBAppEvent`, `UnifiedLogEntry`, `InstallLogEntry`, `LOBPackageReceipt`, `LOBAnalysis`, `SidebarEvent` enum, `ChannelBadge`, lifecycle stages |
| `UnifiedLogReader.swift` | Reads macOS unified logs via `log show --style json` with predicates for mdmclient/storedownloadd/installer |
| `InstallLogParser.swift` | Parses `/var/log/install.log` for MDM install records |
| `InstallHistoryParser.swift` | Parses `/Library/Receipts/InstallHistory.plist` filtering for `processName == "mdmclient"` |
| `LOBCorrelationEngine.swift` | Merges all three data sources into `LOBAppEvent` objects using command UUID + timestamp proximity + package name matching |
| `LOBSidebarView.swift` | Left pane listing LOB deployment events with status/search filtering |
| `LOBDetailView.swift` | Detail pane showing lifecycle timeline, receipt info, unified + install log entries |
| `DeploymentLifecycleView.swift` | Visual pipeline component: MDM Command -> Download -> Installation -> Verification |

### Modified Files

| File | Changes |
|------|---------|
| `Models.swift` | Added `DeploymentChannel` enum, `deploymentChannel` property to `PolicyExecution` |
| `LogParser.swift` | Removed `AppPolicyResultsReporter` filter (line ~281), added `deploymentChannel: .agent` to policy creation |
| `ViewController.swift` | Added `LOBCorrelationEngine` state, `SidebarEvent`-based unified selection, LOB Installs filter button (Cmd+4), LOB stats in Analysis Summary header, auto-loads LOB data |
| `ClipLibrary.swift` | Added `deploymentChannel` to `PolicyExecutionSnapshot` for clip persistence |
| `SyncEventDetailView.swift` | Added `ChannelBadge` (from `LOBModels.swift`) to `PolicyRow.policyTypeTiles` |
| `PolicyDetailView.swift` | Added `ChannelBadge` to policy header |
| `project.pbxproj` | Updated bundle identifiers, added new files to QuickLook target membership |

## Key Design Decisions

### 1. Using `log show` instead of OSLog API

We shell out to `/usr/bin/log show --style json` rather than using the OSLog Swift API because:
- `OSLog` API has restricted access in sandboxed apps
- `log show` provides JSON output that's easy to parse
- The command-line tool handles predicate filtering natively
- Fallback is straightforward (detect failure, show permission instructions)

### 2. Three-Source Correlation

LOB events are correlated from three independent data sources:
1. **Unified logs** (mdmclient) - Primary source for deployment lifecycle events
2. **install.log** - Detailed installation execution records
3. **InstallHistory.plist** - Definitive record of completed installations

Correlation strategy:
- Group unified log entries by MDM command UUID
- Match install.log entries by timestamp proximity (30s window)
- Match receipts by package identifier, app name, or timestamp proximity (5min window)
- Fall back to time-gap-based grouping when UUIDs aren't available

### 3. Non-Destructive Integration

The LOB functionality is additive:
- Existing Agent Apps view works identically to upstream
- LOB events are integrated into the main sidebar as a 4th filter button ("LOB Installs", Cmd+4) alongside Sync Events, Recurring Events, and Health Events
- A `SidebarEvent` enum wraps both `SyncEvent` and `LOBAppEvent` for unified selection across the sidebar
- All existing keyboard shortcuts, clip library, and export features remain functional
- `DeploymentChannel.agent` is set as default for all existing policies

### 4. Bundle Identifier Changes

- Main app: `com.avoges.IntuneLogWatchLOB`
- CLI tool: `com.avoges.IntuneLogWatchLOB-cli`
- QuickLook: `com.avoges.IntuneLogWatchLOB.IntuneLogWatchQuickLook`

## UI Layout

LOB events are integrated directly into the main sidebar rather than using a separate tab switcher. The sidebar filter bar includes a 4th button for LOB content:

```
+------------------------------------------+
| Analysis Summary (includes LOB stats)    |
|------------------------------------------|
| Filter Bar                               |
|  [Sync Events] [Recurring] [Health]      |
|  [LOB Installs]   (Cmd+1..4)            |
|------------------------------------------|
| Sidebar Event List                       |
|   SidebarEvent wraps SyncEvent or        |
|   LOBAppEvent for unified selection      |
|------------------------------------------|
| Content Pane                             |
|   SyncEvent selected: SyncEventDetailView|
|   LOBAppEvent selected: LOBDetailView    |
|------------------------------------------|
| Detail Pane                              |
|   SyncEvent: PolicyDetailView            |
|   LOBAppEvent: (integrated in LOBDetail) |
+------------------------------------------+
```

## Permissions & Requirements

- **macOS 14.6+** (same as upstream)
- **Full Disk Access** may be required for unified log access
- No app sandbox (same as upstream - entitlements file is empty)
- The app gracefully handles permission failures with user-facing instructions

## Limitations

- Unified log retention is limited (hours to days depending on macOS settings)
- `log show` output format may vary slightly across macOS versions (mitigated by `--style json`)
- MDM command UUID correlation may not work for all MDM command types
- InstallHistory.plist only records completed installations, not failures
