import Combine
import core
import OSLog
import SwiftUI

@MainActor
final class TranslationViewModel: ObservableObject {
    @Published var translatingText: String = ""
    @Published var translatedText: String = ""
    @Published var isTranslating: Bool = false
    @Published var errorMessage: String?
    @Published var fromLanguage: String = "english"
    @Published var toLanguage: String = "russian"
    @Published var mode: TranslationMode = .Auto
    @Published var quality: TranslationQuality = .Optimal
    @Published var provider: TranslationProvider? = nil
    @Published var providers: [TranslationProvider] = []
    @Published var isLoading = true
    @Published var loadingError: String? = nil

    private var lastTranslatedText: String = "" // non-edited translated text
    private var lastUsedMode: TranslationMode?
    private var lastUsedQuality: TranslationQuality?
    private var lastUsedProvider: TranslationProvider?
    private var lastUsedIPA: Bool?

    private let translateUseCase: any TranslateUseCase
    private let getProvidersUseCase: any GetProvidersUseCase
    // private let userDefaults: UserDefaults
    private static let fromLanguageKey = "translation.fromLanguage"
    private static let toLanguageKey = "translation.toLanguage"
    private static let modeKey = "translation.mode"
    private static let qualityKey = "translation.quality"
    private static let providerKey = "translation.provider"

    private var cancellables = Set<AnyCancellable>()

    init(translateUseCase: TranslateUseCase, getProviderUseCase: GetProvidersUseCase) {
        self.translateUseCase = translateUseCase
        getProvidersUseCase = getProviderUseCase
        let userDefaults = UserDefaults.standard

        // Load persisted languages if available
        if let savedFrom = userDefaults.string(forKey: Self.fromLanguageKey), !savedFrom.isEmpty {
            fromLanguage = savedFrom
        }
        if let savedTo = userDefaults.string(forKey: Self.toLanguageKey), !savedTo.isEmpty {
            toLanguage = savedTo
        }
        // Load persisted mode if available
        if let rawMode = userDefaults.string(forKey: Self.modeKey),
           let savedMode = TranslationMode(rawValue: rawMode) {
            mode = savedMode
        }

        if let rawQuality = userDefaults.string(forKey: Self.qualityKey),
           let savedQuality = TranslationQuality(rawValue: rawQuality) {
            quality = savedQuality
        }

        // Persist changes automatically
        $fromLanguage
            .dropFirst()
            .sink { value in
                userDefaults.set(value, forKey: Self.fromLanguageKey)
            }
            .store(in: &cancellables)

        $toLanguage
            .dropFirst()
            .sink { value in
                userDefaults.set(value, forKey: Self.toLanguageKey)
            }
            .store(in: &cancellables)

        $mode
            .dropFirst()
            .sink { value in
                userDefaults.set(value.rawValue, forKey: Self.modeKey)
            }
            .store(in: &cancellables)

        $quality
            .dropFirst()
            .sink { value in
                userDefaults.set(value.rawValue, forKey: Self.qualityKey)
            }
            .store(in: &cancellables)

        $provider
            .dropFirst()
            .sink { value in
                if let value = value {
                    userDefaults.set(value.id, forKey: Self.providerKey)
                }
            }.store(in: &cancellables)

        Task {
            await updateProviders()
            isLoading = false
        }
    }

    func translate(text: String, force: Bool) async {
        logger.debug("translation requested")
        if text == translatedText || text == lastTranslatedText {
            logger.debug("No need to translate, its result of translation")
            return
        }
        if !force && text.isEmpty {
            logger.debug("No need to translate, empty text")
            return
        }
        if !force && (
            text == translatingText
                && mode == lastUsedMode
                && quality == lastUsedQuality
                && provider == lastUsedProvider
        ) {
            logger.debug("No need to translate, same as translating")
            return
        }

        translatingText = text

        await updateProviders()

        guard let translateProvider = provider else {
            logger.debug("No provider set")
            // TODO: error
            return
        }

        isTranslating = true
        errorMessage = nil

        let ipa = UserDefaults.standard.bool(forKey: requestIpaKey)

        let requestParsed = TranslationRequest.create(
            sourceText: text,
            sourceLang: fromLanguage,
            targetLang: toLanguage,
            mode: mode,
            provider: translateProvider,
            quality: quality,
            ipa: ipa,
        )

        switch requestParsed {
        case let .success(request):
            logger.debug("Translating: \(request.sourceText)")
            let result = await translateUseCase.translate(from: request)

            switch result {
            case let .success(text):
                translatedText = text
                lastTranslatedText = text
                lastUsedMode = mode
                lastUsedQuality = quality
                lastUsedProvider = provider
                if UserDefaults.standard.object(forKey: "menu.check.autoPaste") as? Bool ?? true {
                    copyToClipboard(text)
                    logger.debug("Pasted translation to clipboard")
                }
            case let .failure(error):
                errorMessage = "Failed: \(error.localizedDescription)"
            }

        case let .failure(error):
            logger.debug("Tranlating failed: \(error.localizedDescription)")
            errorMessage = "Invalid: \(error.localizedDescription)"
        }

        isTranslating = false
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

    private func updateProviders() async {
        logger.debug("getting provides...")
        let result = await getProvidersUseCase.providers()
        logger.debug("got providers")
        switch result {
        case let .success(providers):
            logger.debug("got providers success \(providers.count)")
            self.providers = providers
                if let savedProviderId = UserDefaults.standard.string(forKey: Self.providerKey) {
                if let found = providers.first(where: { $0.id == savedProviderId }) {
                    provider = found
                }
            }
            if provider == nil {
                provider = providers.first!
            }
        case let .failure(error):
            // TODO: word
            logger.warning("got providers error: \(error)")
            errorMessage = "Failed to load providers: \(error)"
        }
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba-masos", category: "TranslationViewModel")
}
