import Combine
import core
import OSLog
import SwiftUI

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var translatingText: String = ""
    @Published var translatedText: String = ""
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var fromLanguage: String = "english"
    @Published var toLanguage: String = "russian"
    var firstTime: Bool = true

    private var lastTranslatedText: String = "" // non-edited translated text

    private let translator: any TranslateUseCase
    private let userDefaults: UserDefaults
    private static let fromLanguageKey = "translation.fromLanguage"
    private static let toLanguageKey = "translation.toLanguage"

    init(translator: TranslateUseCase, userDefaults: UserDefaults = .standard) {
        self.translator = translator
        self.userDefaults = userDefaults

        // Load persisted languages if available
        if let savedFrom = userDefaults.string(forKey: Self.fromLanguageKey), !savedFrom.isEmpty {
            self.fromLanguage = savedFrom
        }
        if let savedTo = userDefaults.string(forKey: Self.toLanguageKey), !savedTo.isEmpty {
            self.toLanguage = savedTo
        }
    }

    func translate(text: String, force: Bool) async {
        logger.debug("translate: \(text)")
        if text == translatedText || text == lastTranslatedText {
            logger.debug("No need to translate, its result of translation")
            return
        }
        if !force && text.isEmpty {
            logger.debug("No need to translate, empty text")
            return
        }
        if !force && text == translatingText {
            logger.debug("No need to translate, same as translating")
            return
        }
        translatingText = text

        // Persist current language selections
        userDefaults.set(fromLanguage, forKey: Self.fromLanguageKey)
        userDefaults.set(toLanguage, forKey: Self.toLanguageKey)

        isLoading = true
        errorMessage = nil

        let requestParsed = TranslationRequest.create(
            sourceText: text,
            sourceLang: fromLanguage,
            targetLang: toLanguage,
            mode: "auto",
            provider: "google",
            quality: "optimal"
        )

        switch requestParsed {
        case let .success(request):
            logger.debug("Translating: \(request.sourceText)")
            let result = await translator.translate(from: request)

            switch result {
            case let .success(text):
                translatedText = text
                lastTranslatedText = text
                // Copy to clipboard on success
                copyToClipboard(text)
            case let .failure(error):
                errorMessage = "Failed: \(error.localizedDescription)"
            }

        case let .failure(error):
            logger.debug("Tranlating failed: \(error.localizedDescription)")
            errorMessage = "Invalid: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func copyToClipboard(_ text: String) {
        if text.isEmpty {
            return
        }
        #if canImport(UIKit)
            // iOS / iPadOS
            UIPasteboard.general.string = text
        #elseif canImport(AppKit)
            // macOS
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
        #endif
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba-masos", category: "TranslationViewModel")
}
