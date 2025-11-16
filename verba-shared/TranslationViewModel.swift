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
    @Published var fromLanguage: String = ""
    @Published var toLanguage: String = Locale.current.localizedString(forLanguageCode: Locale.current.languageCode ?? "") ?? ""
    @Published var mode: TranslationMode = .Auto
    @Published var quality: TranslationQuality? = nil // .Optimal
    @Published var qualities: [TranslationQuality] = []
    @Published var provider: TranslationProvider? = nil
    @Published var providers: [TranslationProvider] = []
    @Published var isLoading = true
    @Published var loadingError: String? = nil

    private var currentTranslationTask: Task<Void, Never>?

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
        if let savedFrom = userDefaults.string(forKey: Self.fromLanguageKey) {
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

        /* will be set when providers loaded
         if let rawQuality = userDefaults.string(forKey: Self.qualityKey),
            let savedQuality = TranslationQuality(rawValue: rawQuality) {
             quality = savedQuality
         }
          */

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
                if let v = value {
                    userDefaults.set(v.rawValue, forKey: Self.qualityKey)
                }
            }
            .store(in: &cancellables)

        $provider
            .dropFirst()
            .sink { value in
                if let value = value {
                    userDefaults.set(value.id, forKey: Self.providerKey)
                }
                self.syncQualities(value)
            }.store(in: &cancellables)

        Task {
            await updateProviders()
            isLoading = false
        }
    }

    func translate(text: String, force: Bool) {
        logger.debug("translation requested")
        if toLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            logger.debug("No need to translate, no target language")
            return
        }
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

        cancelTranslation()

        translatingText = text
        currentTranslationTask = Task {
            await performTranslation()
        }
    }

    func cancelTranslation() {
        currentTranslationTask?.cancel()
        currentTranslationTask = nil
        isTranslating = false
    }

    private func performTranslation() async {
        errorMessage = nil
        guard !isLoading else {
            logger.debug("App is loading, no translating possible")
            return
        }

        guard let translateProvider = provider else {
            errorMessage = NSLocalizedString("error.ui.no-provider", comment: "")
            logger.debug("No provider set")
            // TODO: error
            return
        }

        guard let translateQuality = quality else {
            errorMessage = NSLocalizedString("error.ui.no-quality", comment: "")
            logger.debug("No quality set")
            return
        }

        isTranslating = true
        logger.debug("View model clear error")

        let ipa = UserDefaults.standard.bool(forKey: requestIpaKey)

        let requestParsed = TranslationRequest.create(
            sourceText: translatingText,
            sourceLang: fromLanguage,
            targetLang: toLanguage,
            mode: mode,
            provider: translateProvider,
            quality: translateQuality,
            ipa: ipa,
        )

        switch requestParsed {
        case let .success(request):
            logger.debug("Translating: \(request.sourceText)")

            guard !Task.isCancelled else {
                logger.debug("Translation cancelled before network call")
                isTranslating = false
                return
            }

            let result = await translateUseCase.translate(from: request)

            guard !Task.isCancelled else {
                logger.debug("Translation cancelled after network call")
                isTranslating = false
                return
            }

            switch result {
            case let .success(response):
                translatedText = response.translated
                lastTranslatedText = response.translated
                lastUsedMode = mode
                lastUsedQuality = quality
                lastUsedProvider = provider
                setProviders(response.providers)
                if UserDefaults.standard.object(forKey: "menu.check.autoPaste") as? Bool ?? true {
                    copyToClipboard(response.translated)
                    logger.debug("Pasted translation to clipboard")
                }
            case let .failure(error):
                logger.debug("View model set error: \(error.localizedDescription)")
                errorMessage = error.localizedDescription
            }

        case let .failure(error):
            logger.debug("View model set error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
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
            setProviders(providers)
        case let .failure(error):
            // TODO: word
            logger.debug("View model set error: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }

    private func setProviders(_ providers: [TranslationProvider]) {
        self.providers = providers
        logger.debug("setProviders: \(self.providers)")

        // Early return if no providers
        guard !providers.isEmpty else {
            provider = nil
            return
        }

        // Set provider (from saved preference or first available)
        let nextProvider = restoreSavedProvider(from: providers) ?? providers.first
        logger.debug("setProviders, selected: \(String(describing: nextProvider?.id))")
        // subscription tiggerers sync of qualities
        provider = nextProvider
    }

    private func restoreSavedProvider(from providers: [TranslationProvider]) -> TranslationProvider? {
        guard let savedProviderId = UserDefaults.standard.string(forKey: Self.providerKey) else {
            return nil
        }
        return providers.first(where: { $0.id == savedProviderId }) ?? providers.first
    }

    private func syncQualities(_ provider: TranslationProvider?) {
        guard let provider else {
            qualities = []
            quality = nil
            return
        }
        qualities = provider.qualities
        logger.debug("syncQualities with provider \(provider): \(self.qualities)")
        guard !qualities.isEmpty else {
            quality = nil
            return
        }
        quality = restoreSavedQuality(from: qualities)
    }

    private func restoreSavedQuality(from qualities: [TranslationQuality]) -> TranslationQuality? {
        guard let rawQuality = UserDefaults.standard.string(forKey: Self.qualityKey),
              let savedQuality = TranslationQuality(rawValue: rawQuality) else {
            return nil
        }
        return qualities.first(where: { $0.id == savedQuality.id }) ?? qualities.first
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba-masos", category: "TranslationViewModel")
}
