//
//  ContentView.swift
//  verba-masos
//
//  Created by Dolin Sergey on 2. 11. 2025..
//

import core
import OSLog
import SwiftUI

struct ContentView: View {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba-masos", category: "ContentView")

    @StateObject private var viewModel: TranslationViewModel

    init(translateUseCase: TranslateUseCase) {
        _viewModel = StateObject(wrappedValue: TranslationViewModel(translator: translateUseCase))
    }

    var body: some View {
        let vm = viewModel

        // GeometryReader { geo in
        // let totalHeight = geo.size.height
        // let topHeight = totalHeight * (1.0 / 6.0)
        // let middleHeight = totalHeight * (1.0 / 2.0)
        // let bottomHeight = totalHeight * (1.0 / 3.0)

        VStack(spacing: 0) {
            GeometryReader { geo in

                VStack(spacing: 0) {
                    // Top panel
                    panelBackground(
                        HStack(alignment: .top, spacing: 0) {
                            ScrollView {
                                editableText($viewModel.translatingText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding([.top, .bottom])
                            }
                            .padding()
                            VStack(alignment: .trailing, spacing: 0) {
                                TextField(NSLocalizedString("lable.from", value: "From:", comment: "A language to translate from"),
                                          text: $viewModel.fromLanguage)
                                    // .frame(maxWidth: 150)
                                    .padding()
                                HStack {
                                    Spacer()
                                    Button(NSLocalizedString(
                                        "label.translate",
                                        value: "Translate",
                                        comment: "Send the content of the text field to the translation service"))
                                    {
                                        handleTranslate()
                                    }
                                    .padding([.trailing, .leading])
                                    .buttonStyle(.borderedProminent)
                                    //.controlSize(.large)
                                   // keyboardShortcut(.return, modifiers: .command)
                                    //.keyboardShortcut(.defaultAction)
                                    .disabled(viewModel.isLoading)
                                }
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    )
                    .frame(height: geo.size.height * (2.0 / 9.0)) // 2 -
                    // .frame(maxHeight: .infinity)
                    // .frame(height: topHeight)

                    Divider()

                    // Middle panel
                    if vm.isLoading {
                        panelBackground(
                            ProgressView("Translating...")
                        )
                        .frame(height: geo.size.height * (7.0 / 9.0))
                        // .frame(minHeight: 0)
                        // .layoutPriority(2)
                        // --
                        // .frame(height: middleHeight)
                    } else {
                        panelBackground(
                            HStack(alignment: .top, spacing: 0) {
                                ScrollView {
                                    editableText($viewModel.translatedText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding()
                                }
                                .padding([.top, .bottom])
                                VStack(alignment: .trailing, spacing: 0) {
                                    TextField(NSLocalizedString("label.to", value: "To:", comment: "A language to translate to"),
                                              text: $viewModel.toLanguage)
                                        // .frame(maxWidth: 150)
                                        .padding()
                                    HStack {
                                        Spacer()
                                        Button(NSLocalizedString(
                                            "label.copy",
                                            value: "Copy",
                                            comment: "Copy the translated text to the clipboard")) {
                                                handleCopy()
                                            }.padding([.trailing, .leading])
                                    }
                                }
                                .fixedSize(horizontal: true, vertical: false)
                            }
                        )
                        .frame(height: geo.size.height * (7.0 / 9.0))
                        // .frame(minHeight: 0)
                        // .layoutPriority(2)
                        // --
                        // .frame(height: middleHeight)
                    }
                }
            }
/*
            Divider()

            // Bottom panel
            panelBackground(
                HStack {
                    Spacer()
                    Button("Cancel") {
                        handleCancel()
                    }
                    .keyboardShortcut(.cancelAction)
                    /*
                                        Button("OK") {
                                            handleOK()
                                        }
                                        .keyboardShortcut(.defaultAction)
                     */
                }
                .padding()
            )
            // .frame(height: bottomHeight)
 */
        }
        .onAppear {
            updateClipboardText()
        }
        // Update when the app becomes active (regains focusInsert)
        .onReceive(appBecameActivePublisher) { _ in
            updateClipboardText()
        }
        // }
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
        if (viewModel.firstTime) {
            viewModel.firstTime = false
            return
        }
        #if os(macOS)
            let str = NSPasteboard.general.string(forType: .string) ?? ""
        #else
            let str = UIPasteboard.general.string ?? ""
        #endif
        Task {
            logger.debug("translate task launched")
            await viewModel.translate(text: str, force: false)
        }
    }

    // MARK: - UI helpers

    @ViewBuilder
    private func selectableText(_ text: String) -> some View {
        #if os(macOS)
            Text(text)
                .textSelection(.enabled)
                .font(.system(.body, design: .default))
        #else
            Text(text)
                .textSelection(.enabled)
                .font(.body)
        #endif
    }

    @ViewBuilder
    private func editableText(_ text: Binding<String>) -> some View {
        #if os(macOS)
            TextEditor(text: text)
                .textSelection(.enabled)
                .font(.system(.body, design: .default))
        #else
            TextEditor(text: text)
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
        print("OK tapped")
        #if os(macOS)
            NSApp.keyWindow?.performClose(nil)
        #endif
    }

    private func handleCancel() {
        print("Cancel tapped")
        #if os(macOS)
            NSApp.keyWindow?.performClose(nil)
        #endif
    }

    private func handleTranslate() {
        Task {
            await viewModel.translate(text: viewModel.translatingText, force: true)
        }
    }

    private func handleCopy() {
        viewModel.copyToClipboard(viewModel.translatedText)
    }
}

#Preview {
    ContentView(translateUseCase: TranslationService(repository: TranslationRestRepository()))
}
