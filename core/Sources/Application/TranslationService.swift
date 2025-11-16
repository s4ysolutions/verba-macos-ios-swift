import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba-masos", category: "TranslationService")

public actor TranslationService<TR: TranslationRepository>:
    TranslateUseCase, GetProvidersUseCase {
    private let translationRespository: TR

    private var cachedProviders: [TranslationProvider]?
    private var fetchTask: Task<Result<[TranslationProvider], ApiError>, Never>?

    public init(translationRepository: TR) {
        translationRespository = translationRepository
    }

    public func translate(from translationRequest: TranslationRequest) async
        -> Result<TranslationResponse, TranslationError> {
        logger.debug("request: \(translationRequest.sourceText)")
        let response = await translationRespository.translate(from: translationRequest)
        return response
            .mapError { .api($0) }
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
            let result = await translationRespository.providers()
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
