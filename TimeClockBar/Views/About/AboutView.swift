import SwiftUI

struct AboutView: View {
    private let repositoryURL = URL(string: "https://github.com/vn-aj-vngrd/TimeClockBar")!
    private let creatorURL = URL(string: "https://github.com/vn-aj-vngrd/")!

    var body: some View {
        VStack(spacing: 10) {
            Image("BrandIcon")
                .resizable()
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)

            Text(appName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)

            Text("Version \(versionText)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                Text("Created by")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Link("Van AJ Vanguardia", destination: creatorURL)
                    .font(.system(size: 12, weight: .semibold))
            }

            HStack(spacing: 4) {
                Text("Open source")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Link("vn-aj-vngrd/TimeClockBar", destination: repositoryURL)
                    .font(.system(size: 11, weight: .semibold))
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 28)
        .padding(.vertical, 30)
        .frame(width: 284, height: 228)
        .background(.regularMaterial)
    }

    private var appName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Time Clock Bar"
    }

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(version) (\(build))"
    }
}

#Preview {
    AboutView()
}
