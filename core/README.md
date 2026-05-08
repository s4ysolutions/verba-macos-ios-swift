# core

Shared Swift package for Verba apps (`iOS 15+`, `macOS 12+`).

This package contains translation, auth, and store business logic behind protocol ports, with concrete adapters for REST, Keychain, device identity, and StoreKit.

## Purpose

Use `core` as the single source of truth for:
- Translation domain models and validation
- Translation API orchestration and provider caching
- RSA key-based auth and bearer token generation
- StoreKit product/purchase access

## Package Layout

```text
core/
├── Sources/
│   ├── Domain/
│   │   ├── Entities/
│   │   ├── Errors/
│   │   └── Ports/
│   ├── Application/
│   │   ├── AuthService.swift
│   │   ├── TranslationService.swift
│   │   └── Ports/
│   └── Adapters/
└── Tests/coreTests/
```

Dependency direction:
- `Domain` has no side-effecting dependencies.
- `Application` depends on `Domain` ports.
- `Adapters` implement `Domain` ports.

## Core Flows

### 1. Translation flow

1. UI builds `TranslationRequest` using `TranslationRequest.create(...)`.
2. UI calls `TranslateUseCase.translate(from:)` (usually `TranslationService`).
3. `TranslationService` resolves current user via `UserRepository.me()`.
4. `TranslationService` calls `TranslationRepository.translate(from:byUser:)`.
5. `TranslationRestRepository` sends HTTP request with `Authorization: Bearer <token>`.
6. Result maps to `TranslationResponse` or `TranslationError.api`.

### 2. Providers flow

1. UI calls `GetProvidersUseCase.providers()`.
2. `TranslationService` returns in-memory cached providers if available.
3. Concurrent requests are coalesced through a shared in-flight `Task`.
4. `TranslationRepository.providers()` is called once, then cached.

### 3. Auth flow

1. `AuthService` asks `AuthKeyRepository` for RSA keypair (load or create).
2. If no stored user id, `AuthService` posts SPKI public key to `/registerPublicKey`.
3. Returned `userId` is persisted via `AuthKeyRepository.saveUserId`.
4. For each request, `AuthService.makeToken(payload:)` creates:
   - `<userId>.<payload>.<keyHash>.<timestamp>.<nonce>.<signature>`
5. Signature is RSA PKCS#1 v1.5 SHA-256 over first five fields.

## Public Contracts

### Domain entities
- `TranslationRequest`: validated input object (`sourceText`, languages, mode, provider, quality, `ipa`).
- `TranslationResponse`: translated text, token counts, latency, updated providers.
- `TranslationProvider`: provider `id`, `displayName`, supported qualities.
- `TranslationMode`: `.TranslateSentence`, `.ExplainWords`, `.Auto`.
- `TranslationQuality`: `.Fast`, `.Optimal`, `.Thinking`.
- `User`: currently just `id`.
- `KeyPair`: `SecKey` private key + SPKI bytes + public key hash.
- Store entities: `Purchasable`, `Purchased`.

### Domain ports
- `TranslationRepository`
  - `translate(from:byUser:)`
  - `providers()`
- `UserRepository`
  - `me()`
- `StoreRepository`
  - `fetchProducts()`
  - `fetchPurchases()`
  - `purchase(_:)`
  - `purchaseUpdates`
- `BearerTokenProvider`
  - `makeToken(payload:)`
- `AuthKeyRepository`
  - `getOrCreateKeyPair()`
  - `saveUserId(_:)`
  - `loadUserId()`

### Application use-case ports
- `TranslateUseCase.translate(from:)`
- `GetProvidersUseCase.providers()`

## Implementations (Adapters)

- `TranslationRestRepository`
  - Uses `HttpClient` (`URLSession` conforms).
  - Endpoints currently point to `http://localhost:8080` (`/translation`, `/providers`).
  - Maps status codes:
    - `401/403 -> .invalidKey`
    - `413 -> .requestTooBig`
    - `429 -> .rateLimitExceeded`
    - others -> `.http(status, body)`

- `KeychainAuthKeyRepository`
  - Stores RSA-2048 private key in Keychain.
  - Builds SPKI from PKCS#1 public key bytes.
  - Persists user id in `UserDefaults`.

- `UserDeviceRepository`
  - iOS: `UIDevice.current.identifierForVendor`.
  - macOS: `IOPlatformUUID` via IOKit.

- `StoreKitStoreRepository`
  - Maps StoreKit products/transactions to domain entities.
  - Streams updates through `AsyncStream<[Purchased]>`.

- `HttpClient`
  - Protocol to make networking testable.

## Error model

- `TranslationError`
  - `.validation(ValidationError)`
  - `.api(ApiError)`

- `ApiError`
  - includes auth, rate-limit, request-size, encoding/decoding, HTTP, networking, unexpected.

- `AuthError`
  - keychain, key generation, registration, missing user id, signing.

- `StoreError`
  - currently `.unexpected` only.

## Wiring Example

```swift
import core

let keyRepo = KeychainAuthKeyRepository()
let authService = AuthService(keyRepository: keyRepo)

let translationRepo = TranslationRestRepository(
    tokenProvider: authService,
    httpClient: URLSession.shared
)

let translationService = TranslationService(
    translationRepository: translationRepo,
    userRepository: authService
)

let storeRepository = StoreKitStoreRepository(productIds: [
    "your.product.id"
])
```

## AI Agent Notes

- Prefer using `TranslateUseCase` and `GetProvidersUseCase` abstractions in shared/UI code.
- `TranslationService.translate` currently `fatalError`s when user resolution fails.
- `TranslationRestRepository` is hardcoded to localhost base URL right now.
- `AuthService` expects registration response JSON to include `userId`.
- `TranslationRequest.create` allows empty `sourceLang` (stored as `nil`) but enforces target language length constraints.
- Existing tests focus on `TranslationRestRepository.executeRequest` status/error mapping.

## Tests

Current test target: `Tests/coreTests/TranslationRestRepositoryTests.swift`.

Covers:
- status mapping (`401`, `403`, `429`, `500`)
- non-HTTP response handling
- networking error mapping
- parser success path
