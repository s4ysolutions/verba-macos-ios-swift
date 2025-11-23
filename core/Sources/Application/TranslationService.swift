import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba-masos", category: "TranslationService")

public actor TranslationService:
    TranslateUseCase, GetProvidersUseCase {
    private let translationRepository: TranslationRepository
    private let userRepository: UserRepository

    private var cachedProviders: [TranslationProvider]?
    private var fetchTask: Task<Result<[TranslationProvider], ApiError>, Never>?

    public init(translationRepository: TranslationRepository, userRepository: UserRepository) {
        self.translationRepository = translationRepository
        self.userRepository = userRepository
    }

    public func translate(from translationRequest: TranslationRequest) async
        -> Result<TranslationResponse, TranslationError> {
        let meResult = await userRepository.me()
        guard case let .success(me) = meResult else {
            fatalError("User not logged in")
        }
        logger.debug("request: \(translationRequest.sourceText)")
        let response = await translationRepository.translate(from: translationRequest, byUser: me)
        return response.mapError { .api($0) }
    }

    public func providers() async
        -> Result<[TranslationProvider], TranslationError> {
        if let providers = cachedProviders {
            logger.debug("Use cached providers")
            return .success(providers)
        }

        if let existingTask = fetchTask {
            logger.debug("Waiting for previous providers request to complete")
            return await existingTask.value.mapError { .api($0) }
        }

        let task = Task<Result<[TranslationProvider], ApiError>, Never> {
            let result = await translationRepository.providers()
            if case let .success(providers) = result {
                logger.debug("Fetched providers successfully and cached them")
                self.cachedProviders = providers
            }
            self.fetchTask = nil
            return result
        }

        fetchTask = task

        return await task.value.mapError { .api($0) }
    }
}
