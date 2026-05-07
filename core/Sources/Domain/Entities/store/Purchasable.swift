import Foundation

public struct Purchasable: Sendable, Identifiable, Hashable {
    public let id: String
    public let title: String
    public let price: Decimal
    public let currencyCode: String
    public let subscriptionPeriod: TimeInterval?  // only for subs
}
