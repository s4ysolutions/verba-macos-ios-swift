public protocol StoreRepository: Sendable {

    func fetchProducts() async -> Result<[Purchasable], StoreError>

    func fetchPurchases() async -> Result<[Purchased], StoreError>

    func purchase(_ product: Purchasable) async -> Result<Purchased, StoreError>

    var purchaseUpdates: AsyncStream<[Purchased]> { get }
}
