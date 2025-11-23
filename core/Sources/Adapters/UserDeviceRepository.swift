#if os(iOS)
    import UIKit
#elseif os(macOS)
    import Foundation
    import IOKit
#endif
import OSLog

public struct UserDeviceRepository: UserRepository {
    public init() {
    }
    public func me() async -> Result<User, ApiError> {
        // Resolve a single optional device identifier across platforms
        #if os(iOS)
            let deviceID: String? = await UIDevice.current.identifierForVendor?.uuidString
        #elseif os(macOS)
            let deviceID: String? = getMacDeviceIdentifier()
        #else
            let deviceID: String? = nil
        #endif

        logger.debug("DeviceID: \(String(describing: deviceID))")

        if let deviceID {
            return .success(User(id: deviceID))
        }
        return .failure(.unexpected(String(NSLocalizedString("error.device-id-not-available", comment: "Error, no device ID available"))))
    }

    #if os(macOS)
        private func getMacDeviceIdentifier() -> String? {
            let platformExpert = IOServiceGetMatchingService(
                kIOMainPortDefault,
                IOServiceMatching("IOPlatformExpertDevice")
            )

            guard platformExpert != 0 else { return nil }

            defer { IOObjectRelease(platformExpert) }

            let uuid = IORegistryEntryCreateCFProperty(
                platformExpert,
                kIOPlatformUUIDKey as CFString,
                kCFAllocatorDefault,
                0
            )?.takeRetainedValue() as? String

            return uuid
        }
    #endif
}

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "verba-masos", category: "UserDeviceRepository")
