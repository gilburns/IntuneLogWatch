//
//  PreviewViewController.swift
//  IntuneLogWatchQuickLook
//
//  Created by Gil Burns on 11/30/25.
//

import Cocoa
import Quartz
import SwiftUI

class PreviewViewController: NSViewController, QLPreviewingController {

    override var nibName: NSNib.Name? {
        return nil  // No XIB needed for SwiftUI
    }

    override func loadView() {
        // Create a basic view
        self.view = NSView()
    }

    func preparePreviewOfFile(at url: URL) async throws {
        // Load and decode the .ilwclip file
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let event = try decoder.decode(ClippedPolicyEvent.self, from: data)

        // Create SwiftUI preview view
        let previewView = ClipQuickLookPreview(event: event)
        let hostingController = NSHostingController(rootView: previewView)

        // Add the SwiftUI view to our view hierarchy
        addChild(hostingController)

        // Configure hosting view
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)

        // Add constraints to fill the entire view
        NSLayoutConstraint.activate([
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }
}
