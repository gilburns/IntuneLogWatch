//
//  IntuneLogWatchApp.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 8/11/25.
//

import SwiftUI
import UniformTypeIdentifiers
import Sparkle

@main
struct IntuneLogWatchApp: App {
    private let updaterController: SPUStandardUpdaterController
    
    init() {
        // Set up Sparkle updater
        updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(DefaultWindowStyle())
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    updaterController.checkForUpdates(nil)
                }
            }
            
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
