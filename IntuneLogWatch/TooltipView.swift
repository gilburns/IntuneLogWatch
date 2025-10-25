//
//  TooltipView.swift
//  IntuneLogWatch
//
//  Created by Gil Burns on 10/22/25.
//

import SwiftUI

extension View {
    func tooltip(_ tip: String) -> some View {
        self.background(
            GeometryReader { geometry in
                Tooltip(tip) {
                    self
                }
                .frame(width: geometry.size.width, height:
geometry.size.height)
            }
        )
    }
}

private struct Tooltip<Content: View>: NSViewRepresentable {
    let text: String?
    let content: Content

    init(_ text: String?, @ViewBuilder content: () -> Content) {
        self.text = text
        self.content = content()
    }

    func makeNSView(context: Context) -> NSHostingView<Content> {
        let view = NSHostingView(rootView: content)
        view.toolTip = text
        return view
    }

    func updateNSView(_ nsView: NSHostingView<Content>, context: Context) {
        nsView.toolTip = text
        nsView.rootView = content
    }
}
