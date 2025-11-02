//
//  ContentView.swift
//  verba-masos
//
//  Created by Dolin Sergey on 2. 11. 2025..
//

import SwiftUI

struct ContentView: View {
    @State private var clipboardText: String = ""
    @State private var middleText: String = """
    Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed non risus. Suspendisse lectus tortor, dignissim sit amet, adipiscing nec, ultricies sed, dolor. \
    Cras elementum ultrices diam. Maecenas ligula massa, varius a, semper congue, euismod non, mi. Proin porttitor, orci nec nonummy molestie, enim est eleifend mi, \
    non fermentum diam nisl sit amet erat. Duis semper. Duis arcu massa, scelerisque vitae, consequat in, pretium a, enim. Pellentesque congue.
    """

    var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let topHeight = totalHeight * (1.0 / 6.0)
            let middleHeight = totalHeight * (1.0 / 2.0)
            let bottomHeight = totalHeight * (1.0 / 3.0)

            VStack(spacing: 0) {
                // Top panel
                panelBackground(
                    ScrollView {
                        selectableText(clipboardText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                )
                .frame(height: topHeight)

                Divider()

                // Middle panel
                panelBackground(
                    ScrollView {
                        selectableText(middleText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                )
                .frame(height: middleHeight)

                Divider()

                // Bottom panel
                panelBackground(
                    HStack {
                        Spacer()
                        Button("Cancel") {
                            handleCancel()
                        }
                        .keyboardShortcut(.cancelAction)

                        Button("OK") {
                            handleOK()
                        }
                        .keyboardShortcut(.defaultAction)
                    }
                    .padding()
                )
                .frame(height: bottomHeight)
            }
            .onAppear {
                updateClipboardText()
            }
            // Update when the app becomes active (regains focus)
            .onReceive(appBecameActivePublisher) { _ in
                updateClipboardText()
            }
        }
        .padding(.vertical, 0)
        .padding(.horizontal, 0)
    }

    // MARK: - Platform helpers

    private var appBecameActivePublisher: NotificationCenter.Publisher {
        #if os(macOS)
        return NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
        #else
        return NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
        #endif
    }

    private func updateClipboardText() {
        #if os(macOS)
        if let str = NSPasteboard.general.string(forType: .string) {
            clipboardText = str
        } else {
            clipboardText = ""
        }
        #else
        clipboardText = UIPasteboard.general.string ?? ""
        #endif
    }

    // MARK: - UI helpers

    @ViewBuilder
    private func selectableText(_ text: String) -> some View {
        #if os(macOS)
        Text(text)
            .textSelection(.enabled)
            .font(.system(.body, design: .default))
        #else
        // On iOS 15+, Text supports textSelection too
        Text(text)
            .textSelection(.enabled)
            .font(.body)
        #endif
    }

    @ViewBuilder
    private func panelBackground<Content: View>(_ content: Content) -> some View {
        #if os(macOS)
        content
            .background(Color(NSColor.textBackgroundColor))
        #else
        content
            .background(Color(UIColor.systemBackground))
        #endif
    }

    // MARK: - Actions

    private func handleOK() {
        // Wire this up to your intended behavior (e.g., accept, close window, etc.)
        print("OK tapped")
        #if os(macOS)
        // Example: close key window
        NSApp.keyWindow?.performClose(nil)
        #endif
    }

    private func handleCancel() {
        // Wire this up to your intended behavior (e.g., cancel, close window, etc.)
        print("Cancel tapped")
        #if os(macOS)
        NSApp.keyWindow?.performClose(nil)
        #endif
    }
}

#Preview {
    ContentView()
}
