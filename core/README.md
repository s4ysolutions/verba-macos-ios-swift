# core

A Swift Package Manager library shared by the Verba iOS and macOS applications. It encapsulates all business logic using a **Clean Architecture** layering: **Domain → Application → Adapters**.

- **Platforms:** iOS 15+, macOS 12+
- **Swift tools version:** 6.2

---

## Architecture

```
Sources/
├── Domain/          # Pure business rules – no frameworks, no side effects
│   ├── Entities/    # Value types & enums that model the problem space
│   ├── Errors/      # Typed error enums
│   └── Ports/       # Protocols (interfaces) the Application layer depends on
├── Application/     # Use-case orchestration
│   ├── TranslationService.swift   # Actor implementing both use cases
│   └── Ports/       # Use-case protocols consumed by the UI layer
└── Adapters/        # Concrete implementations of the Domain ports
```

Dependencies only flow inward: Adapters depend on Domain; Application depends on Domain; nothing in Domain depends on outer layers.

---

## Domain Layer

### Entities

| Type | Kind | Description |
|---|---|---|
| `User` | struct | Represents the current device user identified by a unique `id` string. |
| `TranslationRequest` | struct | Validated value object capturing everything needed for a translation call (source text, languages, mode, provider, quality, IPA flag). Built via the `create(...)` factory, which returns a `Result` and enforces non-empty text and valid language code lengths (3–16 chars). |
| `TranslationResponse` | struct | The result of a successful translation: translated text, input/output token counts, server-side latency (`timeMs`), and the updated list of available providers. |
| `TranslationProvider` | struct | Describes an AI backend reachable by the service (e.g. `openai`). Carries a stable `id`, a human-readable `displayName`, and the set of `TranslationQuality` tiers it supports. |
| `TranslationMode` | enum | `TranslateSentence` / `ExplainWords` / `Auto` – maps to the server's `translate`, `explain`, `auto` strings. |
| `TranslationQuality` | enum | `Fast` / `Optimal` / `Thinking` (maps to `fast` / `optimal` / `deep`). Provides a localised `displayName`. |
| `Purchasable` | struct | A product available for purchase (id, title, price, currency, optional subscription period). |
| `Purchased` | struct | A completed StoreKit transaction (product id, purchase date, optional expiration, `isActive` flag). |

### Errors

| Type | Description |
|---|---|
| `ValidationError` | Input-level problems: empty string, invalid provider/quality/mode values, language codes that are too short or too long. |
| `TranslationError` | Wraps either a `ValidationError` or an `ApiError`; exposed to the UI layer. |
| `ApiError` | Network/API-level failures: `invalidKey`, `rateLimitExceeded`, `requestTooBig`, `encodingFailed`, `decodingFailed`, `http(statusCode, body)`, `networking(error)`, `unexpected(message)`. Implements `LocalizedError` and strips HTML tags from server error bodies. |
| `StoreError` | StoreKit-level failures (currently `unexpected(message)`). |

### Ports (Domain Interfaces)

| Protocol | Methods |
|---|---|
| `TranslationRepository` | `translate(from:byUser:)`, `providers()` |
| `UserRepository` | `me()` |
| `StoreRepository` | `fetchProducts()`, `fetchPurchases()`, `purchase(_:)`, `purchaseUpdates: AsyncStream<[Purchased]>` |

---

## Application Layer

### `TranslationService` (Swift `actor`)

The single application-layer service. It is concurrency-safe (`actor`) and implements two use-case protocols:

#### `TranslateUseCase`
```swift
func translate(from translationRequest: TranslationRequest) async -> Result<TranslationResponse, TranslationError>
```
1. Resolves the current user via `UserRepository.me()` (fatal error if unavailable).
2. Forwards the request to `TranslationRepository.translate(from:byUser:)`.
3. Maps `ApiError` → `TranslationError.api`.

#### `GetProvidersUseCase`
```swift
func providers() async -> Result<[TranslationProvider], TranslationError>
```
1. Returns cached providers if already fetched (in-memory cache, lives for the actor's lifetime).
2. Coalesces concurrent in-flight requests into a single upstream call (task deduplication via `fetchTask`).
3. Delegates to `TranslationRepository.providers()`.

### Use-Case Protocols (`Application/Ports/`)

The UI layer depends on these thin protocols, not on `TranslationService` directly:

| Protocol | Method |
|---|---|
| `TranslateUseCase` | `translate(from:)` |
| `GetProvidersUseCase` | `providers()` |

---

## Adapters Layer

Concrete implementations wired up by the host application at startup.

### `TranslationRestRepository`
Implements `TranslationRepository` by calling the Verba REST back-end (`https://verba.s4y.solutions`).

- **Authentication:** WSSE `UsernameToken` – a Base64-encoded SHA-256 digest of `(nonce + created + secret)`. The shared secret is read from `Info.plist` key `VERBA_SECRET`. For translation requests the username is the device/user id; for provider lookups it is `"verba"`.
- **`providers()`** – `GET /providers` → decodes `[ProviderDTO]` → `[TranslationProvider]`.
- **`translate(from:byUser:)`** – `POST /translation` with a JSON body; decodes `TranslationResponseDTO` → `TranslationResponse`.
- **HTTP error mapping:** `401`/`403` → `.invalidKey`, `413` → `.requestTooBig`, `429` → `.rateLimitExceeded`, other 4xx/5xx → `.http(code, cleanedBody)`.
- **`HttpClient` protocol** – thin abstraction over `URLSession.data(for:)` that makes the repository fully testable with a mock.

### `UserDeviceRepository`
Implements `UserRepository`.

- **iOS:** returns `UIDevice.current.identifierForVendor?.uuidString`.
- **macOS:** reads `IOPlatformUUID` from the IOKit `IOPlatformExpertDevice` service.
- Returns `.failure(.unexpected(...))` if no identifier is available.

### `StoreKitStoreRepository`
Implements `StoreRepository` using **StoreKit 2**.

- Initialised with a list of product ids to manage.
- **`fetchProducts()`** – calls `StoreKit.Product.products(for:)` and maps to `[Purchasable]`.
- **`fetchPurchases()`** – iterates `Transaction.currentEntitlements` and maps verified transactions to `[Purchased]`.
- **`purchase(_:)`** – calls `skProduct.purchase()`, handles `.success(verified)`, `.userCancelled`, and `.pending` outcomes.
- **`purchaseUpdates`** – an `AsyncStream<[Purchased]>` that emits a fresh snapshot of all active purchases whenever `Transaction.updates` yields a new verified transaction (background listener task).

### `HttpClient`
```swift
public protocol HttpClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}
```
`URLSession` conforms to this protocol out of the box. Tests substitute a `MockHttpClient`.

---

## Tests

Located in `Tests/coreTests/`.

### `TranslationRestRepositoryTests`
Uses `MockHttpClient` to inject pre-canned `(Data, URLResponse)` pairs and exercises `TranslationRestRepository.executeRequest(_:parser:)` in isolation:

| Scenario | Expected outcome |
|---|---|
| HTTP 200 with valid data | Parser called, `Result.success` returned |
| HTTP 401 / 403 | `.failure(.invalidKey)` |
| HTTP 429 | `.failure(.rateLimitExceeded)` |
| HTTP 500, plain-text body | `.failure(.http(500, body))` |
| HTTP 500, HTML body | `.failure(.http(500, ...))` with `<body>` content extracted |
| Non-HTTP `URLResponse` | `.failure(.unexpected(...))` |
| `URLSession` throws | `.failure(.networking(...))` |

---

## Usage

Add the package as a local dependency in the host application's `Package.swift` or Xcode project, then inject adapters into the service:

```swift
import core

let httpClient = URLSession.shared
let translationRepo = TranslationRestRepository(httpClient: httpClient)
let userRepo = UserDeviceRepository()

let service = TranslationService(
    translationRepository: translationRepo,
    userRepository: userRepo
)

// Translate
let request = TranslationRequest.create(
    sourceText: "Hello",
    sourceLang: "eng",
    targetLang: "spa",
    provider: someProvider,
    ipa: false
)

if case .success(let req) = request {
    let result = await service.translate(from: req)
}

// In-app purchases
let storeRepo = StoreKitStoreRepository(productIds: ["com.example.pro"])
let products = await storeRepo.fetchProducts()
```

