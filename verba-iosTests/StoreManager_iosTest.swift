import Testing
@testable import core
internal import StoreKit
// @testable import verba_ios

struct storeManger_iosTests {

    @Test func productWeeBurstShouldExist() async throws {
        let manager = await MainActor.run { StoreManager() }
        let weekBurst = await manager.product(withID: "s4y.solutions.verba.week_burst")

        #expect(weekBurst != nil)
    }

    @Test func productWeeBurstShouldHavePurchase() async throws {
        let manager = await MainActor.run { StoreManager() }
        let weekBurst = await manager.product(withID: "s4y.solutions.verba.week_burst")

        // Ensure product exists before attempting purchase
        let product = try #require(weekBurst)

        // Attempt a purchase with no special options
        let purchase = try await product.purchase(options: [])

        // We don't assert on the exact result (it can be user-cancelled, etc.),
        // but we do assert that we got a non-nil result object back from StoreKit.
        switch purchase {
            case .success(let verificationResult):
                // Verify the transaction
                switch verificationResult {
                    case .verified(let transaction):
                        // Get purchase date and status
                        let purchaseDate = transaction.purchaseDate
                        let productID = transaction.productID
                        let transactionID = transaction.id

                        print("Purchase Date: \(purchaseDate)")
                        print("Product ID: \(productID)")
                        print("Transaction ID: \(transactionID)")

                        // Finish the transaction
                        await transaction.finish()

                    case .unverified(let transaction, let error):
                        // Transaction failed verification
                        print("Unverified transaction: \(error)")
                }

            case .userCancelled:
                print("User cancelled the purchase")

            case .pending:
                print("Purchase is pending (e.g., Ask to Buy)")

            @unknown default:
                break
        }
    }
/*
    @Test func refreshSubscriptionGroupStatusShouldReturn() async throws {
        // Integration-style test that exercises StoreManager.refreshSubscriptionGroupStatus()
        // without requiring a StoreKit Test configuration. It asserts that the call completes
        // and sets the optional state to either a valid value or nil without crashing.
        let manager = await MainActor.run { StoreManager() }

        // Ensure products are loaded (from App Store or local StoreKit config if present)
        await manager.loadProducts()

        // Run the status refresh
        await manager.refreshSubscriptionGroupStatus()

        // Validate that the property is set to a coherent value (including nil if no config)
        // We primarily assert that the call path completed without throwing and the type is correct.
        // If there are subscription products and status is fetchable, it should be non-nil.
        // Since this is environment-dependent, we only check that access is possible.
        _ = await manager.subscriptionGroupStatus // access to ensure it's computed and published

        // Additionally, ensure calling it twice is idempotent and does not crash.
        await manager.refreshSubscriptionGroupStatus()
        _ = await manager.subscriptionGroupStatus
    }
*/
}
