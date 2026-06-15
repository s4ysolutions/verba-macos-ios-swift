import SwiftUI

struct AboutView: View {
    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ??
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ??
        "App"
    }

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (\(b))"
    }

    var body: some View {
        VStack(spacing: 20) {
            Image(uiImage: UIApplication.shared.applicationIconImage ?? UIImage())
                .resizable()
                .frame(width: 80, height: 80)
                .cornerRadius(16)

            Text(appName)
                .font(.title3)
            Text("Version \(version)")
                .foregroundStyle(.secondary)

            if let privacyURL = URL(string: "https://s4ysolutions.github.io/verba/privacy/") {
                Link("Privacy Policy", destination: privacyURL)
                    .padding(.top, 8)
            }

            Spacer(minLength: 20)
        }
        .padding()
    }
}
