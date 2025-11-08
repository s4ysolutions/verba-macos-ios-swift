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
    @FocusState private var focused: Bool

    init(translateUseCase: TranslateUseCase, getProvidersUseCase: GetProvidersUseCase) {
        _viewModel = StateObject(wrappedValue: TranslationViewModel(
            translateUseCase: translateUseCase,
            getProviderUseCase: getProvidersUseCase
        ))
    }

    var body: some View {
        let vm = viewModel

        VStack(spacing: 0) {
            GeometryReader { geo in
                if viewModel.isLoading {
                    panelBackground(
                        VStack {
                            Spacer()
                            ProgressView("Loading...")
                                .frame(maxWidth: .infinity, alignment: .center)
                            Spacer()
                        }
                    )
                    .frame(height: geo.size.height)
                } else {
                    // Top panel
                    VStack(spacing: 0) {
                        panelBackground(
                            VStack(spacing: 0) {
                                editableText($viewModel.translatingText)
                                    .focused($focused)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding([.leading, .bottom])
                                HStack(spacing: 0) {
                                    Spacer()
                                    TextField(NSLocalizedString("lable.from", value: "From:", comment: "A language to translate from"),
                                              text: $viewModel.fromLanguage)
                                        .frame(maxWidth: 150)
                                    Button(NSLocalizedString(
                                        "label.translate",
                                        value: "Translate",
                                        comment: "Send the content of the text field to the translation service"))
                                    {
                                        handleTranslate()
                                    }
                                    .padding([.trailing, .leading])
                                    .buttonStyle(.borderedProminent)
                                    .disabled(viewModel.isTranslating)
                                }.padding([.bottom])
                            }
                        )
                        .frame(height: geo.size.height * (2.0 / 9.0)) // 2 -

                        Divider()

                        // Middle panel
                        if vm.isTranslating {
                            panelBackground(
                                ProgressView("Translating...")
                            )
                            .frame(height: geo.size.height * (7.0 / 9.0))
                        } else {
                            panelBackground(
                                VStack(spacing: 0) {
                                    editableText($viewModel.translatedText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding([.leading, .top, .bottom])
                                    HStack(spacing: 0) {
                                        HStack(spacing: 0) {
                                            Picker("", selection: $viewModel.mode) {
                                                Text(modeLabel(.Auto)).tag(TranslationMode.Auto)
                                                Text(modeLabel(.TranslateSentence)).tag(TranslationMode.TranslateSentence)
                                                Text(modeLabel(.ExplainWords)).tag(TranslationMode.ExplainWords)
                                            }
                                            .pickerStyle(.menu)
                                            .pickerStyle(.menu)
                                            .padding(.trailing)
                                            #if os(macOS)
                                                .frame(maxWidth: 180)
                                            #endif

                                            // Quality selector
                                            Picker("", selection: $viewModel.quality) {
                                                Text(qualityLabel(.Fast)).tag(TranslationQuality.Fast)
                                                Text(qualityLabel(.Optimal)).tag(TranslationQuality.Optimal)
                                                Text(qualityLabel(.Thinking)).tag(TranslationQuality.Thinking)
                                            }
                                            .pickerStyle(.menu)
                                            .padding(.trailing)
                                            #if os(macOS)
                                                .frame(maxWidth: 180)
                                            #endif

                                            Picker("", selection: $viewModel.provider) {
                                                ForEach(viewModel.providers) { provider in
                                                    Text(provider.displayName).tag(Optional(provider))
                                                }
                                            }
                                            .pickerStyle(.menu)
                                            #if os(macOS)
                                                .frame(maxWidth: 180)
                                            #endif
                                        }
                                        .fixedSize(horizontal: true, vertical: false)

                                        Spacer()

                                        HStack(spacing: 0) {
                                            TextField(NSLocalizedString("label.to", value: "To:", comment: "A language to translate to"),
                                                      text: $viewModel.toLanguage)
                                                .frame(maxWidth: 150)
                                                .padding([.trailing])
                                            Button(NSLocalizedString(
                                                "label.copy",
                                                value: "Copy",
                                                comment: "Copy the translated text to the clipboard"), systemImage: "doc.on.doc") {
                                                    handleCopy()
                                                }
                                        }
                                        .fixedSize(horizontal: true, vertical: false)
                                    }.padding([.bottom, .trailing, .leading])
                                }
                            )
                            .frame(height: geo.size.height * (7.0 / 9.0))
                        }
                    }
                }
            }
        }
        .onAppear {
            logger.debug("View: onAppear")
            updateClipboardText()
            focused = true
        }
        // Update when the app becomes active (regains focusInsert)
        .onReceive(appBecameActivePublisher) { _ in
            logger.debug("View: onRecieve")
            updateClipboardText()
            focused = true
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
        let monitorClipboard = UserDefaults.standard.object(forKey: "menu.check.autoCopy") as? Bool ?? true
        if monitorClipboard == false {
            logger.debug("Monitoring clipboard is disabled")
            return
        }

        #if os(macOS)
            let str = NSPasteboard.general.string(forType: .string) ?? ""
        #else
            let str = UIPasteboard.general.string ?? ""
        #endif
        logger.error("Launching translation task (force: false)")
        Task {
            logger.error("Translation task (force: false) started")
            await viewModel.translate(text: str, force: false)
        }
        logger.error("Launching translation task (force: false) ended")
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

    // Provide user-facing labels for modes
    private func modeLabel(_ mode: TranslationMode) -> String {
        switch mode {
        case .Auto:
            return NSLocalizedString("mode.auto", value: "Auto", comment: "Automatic mode")
        case .TranslateSentence:
            return NSLocalizedString("mode.translate", value: "Translate sentence", comment: "Translate sentence mode")
        case .ExplainWords:
            return NSLocalizedString("mode.explain", value: "Explain words", comment: "Explain words mode")
        }
    }

    // Provide user-facing labels for qualities
    private func qualityLabel(_ quality: TranslationQuality) -> String {
        switch quality {
        case .Fast:
            return NSLocalizedString("qulity.fast", value: "Fast", comment: "Lowest but fastest translate")
        case .Optimal:
            return NSLocalizedString("qulity.optimal", value: "Optimal", comment: "Optimal quality but acceptable fast translate")
        case .Thinking:
            return NSLocalizedString("qulity.thinking", value: "Thinking", comment: "Best quality but slowest translate")
        }
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
        logger.debug("Launching translation (force: true)")
        Task {
            await viewModel.translate(text: viewModel.translatingText, force: true)
        }
    }

    private func handleCopy() {
        viewModel.copyToClipboard(viewModel.translatedText)
    }
}

#Preview {
    // ContentView(translateUseCase: TranslationService(translationRepository: TranslationRestRepository()))
}
