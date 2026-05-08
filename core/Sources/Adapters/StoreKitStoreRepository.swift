import Foundation
import StoreKit

// TODO: is not used at the moment

public final class StoreKitStoreRepository: StoreRepository {
    private let productIds: [String]

    private let purchaseUpdatesStream: AsyncStream<[Purchased]>
    private let purchaseUpdatesContinuation: AsyncStream<[Purchased]>.Continuation

    public init(productIds: [String]) {
        self.productIds = productIds

        var continuation: AsyncStream<[Purchased]>.Continuation!
        purchaseUpdatesStream = AsyncStream { c in continuation = c }
        purchaseUpdatesContinuation = continuation

        startTransactionListener()
    }

    // MARK: - Port API

    public func fetchProducts() async -> Result<[Purchasable], StoreError> {
        do {
            let skProducts = try await StoreKit.Product.products(for: productIds)
            let domainProducts = skProducts.map { sk in
                Purchasable(
                    id: sk.id,
                    title: sk.displayName,
                    price: sk.displayPriceDecimal,
                    currencyCode: sk.priceFormatStyle.currencyCode,
                    subscriptionPeriod: nil // iOS <18.4, ignore
                )
            }
            return .success(domainProducts)
        } catch {
            return .failure(.unexpected(error.localizedDescription))
        }
    }

    public func fetchPurchases() async -> Result<[Purchased], StoreError> {
        do {
            var purchases: [Purchased] = []

            for await result in Transaction.currentEntitlements {
                if case let .verified(t) = result {
                    purchases.append(Self.mapTransaction(t))
                }
            }

            return .success(purchases)
        } catch {
            return .failure(.unexpected(error.localizedDescription))
        }
    }

    public func purchase(_ product: Purchasable) async -> Result<Purchased, StoreError> {
        do {
            guard let skProduct = try await loadSKProduct(id: product.id) else {
                return .failure(.unexpected("Product not found"))
            }

            let result = try await skProduct.purchase()

            switch result {
            case let .success(verification):
                switch verification {
                case let .verified(transaction):
                    let purchase = Self.mapTransaction(transaction)
                    await transaction.finish()
                    return .success(purchase)
                case let .unverified(_, error):
                    return .failure(.unexpected("Unverified transaction: \(error.localizedDescription)"))
                }

            case .userCancelled:
                return .failure(.unexpected("User cancelled"))

            case .pending:
                return .failure(.unexpected("Purchase pending"))

            @unknown default:
                return .failure(.unexpected("Unknown purchase result"))
            }

        } catch {
            return .failure(.unexpected(error.localizedDescription))
        }
    }

    public var purchaseUpdates: AsyncStream<[Purchased]> {
        purchaseUpdatesStream
    }

    // MARK: - Internal

    private func startTransactionListener() {
        Task.detached { [weak self] in
            guard let self else { return }

            for await update in Transaction.updates {
                if case let .verified(transaction) = update {
                    let purchase = Self.mapTransaction(transaction)
                    self.sendUpdate(purchase)
                    await transaction.finish()
                }
            }
        }
    }

    private func sendUpdate(_ p: Purchased) {
        Task {
            let current = await fetchPurchases().getOr([])
            purchaseUpdatesContinuation.yield(current)
        }
    }

    private func loadSKProduct(id: String) async throws -> StoreKit.Product? {
        let products = try await StoreKit.Product.products(for: [id])
        return products.first
    }

    private static func mapTransaction(_ t: Transaction) -> Purchased {
        Purchased(
            id: String(t.id),
            productID: t.productID,
            purchaseDate: t.purchaseDate,
            expirationDate: t.expirationDate,
            isActive: t.revocationDate == nil && t.expirationDate.map { $0 > Date() } != false
        )
    }
}

// Helper extensions
extension StoreKit.Product {
    var displayPriceDecimal: Decimal { price }
}

extension Result {
    func getOr(_ fallback: Success) -> Success {
        switch self {
        case let .success(value): return value
        case .failure: return fallback
        }
    }
}
