//
//  IntuneLogWatchApp.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import SwiftUI
import UniformTypeIdentifiers

@main
struct IntuneLogWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(DefaultWindowStyle())
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open Log File...") {
                    // Post notification to trigger file picker
                    NotificationCenter.default.post(name: .openLogFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)
                
                Button("Reload Local Logs") {
                    // Post notification to trigger local logs reload
                    NotificationCenter.default.post(name: .reloadLocalLogs, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

extension Notification.Name {
    static let openLogFile = Notification.Name("openLogFile")
    static let reloadLocalLogs = Notification.Name("reloadLocalLogs")
}

extension UTType {
    static var log: UTType {
        UTType(filenameExtension: "log") ?? UTType.plainText
    }
}
