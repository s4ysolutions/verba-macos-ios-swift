import Foundation

public struct Purchased: Sendable, Identifiable, Hashable {
    public let id: String
    public let productID: String
    public let purchaseDate: Date
    public let expirationDate: Date?
    public let isActive: Bool
}
