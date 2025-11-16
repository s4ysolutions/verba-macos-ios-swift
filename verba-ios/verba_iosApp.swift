import core
import SwiftUI

@main
struct verba_iosApp: App {
    @State private var showAbout = false

    // Create a shared service that conforms to both TranslateUseCase and GetProvidersUseCase
    private let translationService = TranslationService(translationRepository: TranslationRestRepository())
    @AppStorage(autoCopyKey) private var autoCopy: Bool = true
    @AppStorage(autoPasteKey) private var autoPaste: Bool = true
    @AppStorage(requestIpaKey) private var requestIpa: Bool = true

    var body: some Scene {
        WindowGroup {
            NavigationView {
                ContentView(
                    translateUseCase: translationService,
                    getProvidersUseCase: translationService
                )
                .navigationTitle(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "Verba")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            // Auto-copy toggle
                            Button(action: {
                                let newValue = !(UserDefaults.standard.bool(forKey: autoCopyKey))
                                UserDefaults.standard.set(newValue, forKey: autoCopyKey)
                            }) {
                                Label(
                                    NSLocalizedString(
                                        "menu.check.autoCopy",
                                        value: "Monitor Clipboard",
                                        comment: "Toggle monitoring clipboard"
                                    ),
                                    systemImage: autoCopy ? "checkmark.square" : "square"
                                )
                            }

                            // Auto-paste toggle
                            Button(action: {
                                let newValue = !(UserDefaults.standard.bool(forKey: autoPasteKey))
                                UserDefaults.standard.set(newValue, forKey: autoPasteKey)
                            }) {
                                Label(
                                    NSLocalizedString(
                                        "menu.check.autoPaste",
                                        value: "Auto-Paste Translation",
                                        comment: "Toggle auto pasting translation to clipboard"
                                    ),
                                    systemImage: autoPaste ? "checkmark.square" : "square"
                                )
                            }

                            // Request IPA toggle
                            Button(action: {
                                let newValue = !(UserDefaults.standard.bool(forKey: requestIpaKey))
                                UserDefaults.standard.set(newValue, forKey: requestIpaKey)
                            }) {
                                Label(
                                    NSLocalizedString(
                                        "menu.requestIPA",
                                        value: "Show Transcription",
                                        comment: "Request IPA transcription with the translation"
                                    ),
                                    systemImage: requestIpa ? "checkmark.square" : "square"
                                )
                            }

                            Divider()

                            Button(NSLocalizedString("menu.about", value: "About & Privacy", comment: "")) {
                                showAbout = true
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .rotationEffect(.degrees(90))
                        }
                        .menuStyle(BorderlessButtonMenuStyle())
                        .menuIndicator(.hidden)
                    }
                }
                .sheet(isPresented: $showAbout) {
                    AboutView()
                }
            }
            .navigationViewStyle(StackNavigationViewStyle())
            .task {
                _ = await translationService.providers()
            }
        }
    }
}
