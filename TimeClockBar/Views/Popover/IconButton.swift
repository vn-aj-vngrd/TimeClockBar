import SwiftUI

struct IconButton: View {
    let title: String
    let systemImage: String
    let shortcut: String?
    let showsBackground: Bool
    let action: () -> Void
    @State private var isHovered = false

    init(_ title: String, systemImage: String, shortcut: String? = nil, showsBackground: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.shortcut = shortcut
        self.showsBackground = showsBackground
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isHovered ? ChromeColor.primaryText : ChromeColor.secondaryText)
        .background(isHovered ? ChromeColor.controlHover : showsBackground ? ChromeColor.controlGroup : .clear)
        .clipShape(Circle())
        .help(shortcut.map { "\(title) \($0)" } ?? title)
        .onHover { isHovered = $0 }
    }
}
