import Foundation

public enum BackendConfig {
    // public static let restBaseURL = URL(string: "https://verba.s4y.solutions")!
    public static let restBaseURL = URL(string: "http://localhost:8080/rest/v1")!
    public static let registrationURL = URL(string: "\(restBaseURL)/registerPublicKey")!
}
