import SwiftUI

struct WorkingDaysRow: View {
    let selectedWeekdays: Set<Int>
    let onChange: (Int, Bool) -> Void

    private let weekdays = [
        (weekday: 2, label: "Mon"),
        (weekday: 3, label: "Tue"),
        (weekday: 4, label: "Wed"),
        (weekday: 5, label: "Thu"),
        (weekday: 6, label: "Fri"),
        (weekday: 7, label: "Sat"),
        (weekday: 1, label: "Sun")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Working days")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(ChromeColor.primaryText)

            HStack(spacing: 4) {
                ForEach(weekdays, id: \.weekday) { day in
                    let isSelected = selectedWeekdays.contains(day.weekday)

                    Button {
                        onChange(day.weekday, !isSelected)
                    } label: {
                        Text(day.label)
                            .font(.system(size: 12, weight: .regular))
                            .frame(maxWidth: .infinity, minHeight: 24)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? ChromeColor.accentText : ChromeColor.primaryText)
                    .background(isSelected ? ChromeColor.reportBottom : ChromeColor.controlGroup)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct PreferenceSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Section {
            content
        } header: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(ChromeColor.primaryText)
        }
    }
}

struct PreferenceRow<Accessory: View>: View {
    let title: String
    let accessory: Accessory

    init(_ title: String, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.accessory = accessory()
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(ChromeColor.primaryText)

            Spacer(minLength: 12)

            accessory
        }
    }
}

struct PreferenceToggleRow: View {
    let title: String
    let isOn: Binding<Bool>

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self.isOn = isOn
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(ChromeColor.primaryText)

            Spacer(minLength: 12)

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity)
    }
}

struct TimeRow: View {
    let title: String
    let selection: Binding<Int>

    init(_ title: String, selection: Binding<Int>) {
        self.title = title
        self.selection = selection
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(ChromeColor.primaryText)

            Spacer(minLength: 12)

            PreferenceMenuPicker(
                selection: selection,
                options: Self.timeOptions
            )
        }
        .frame(maxWidth: .infinity)
    }

    private static var timeOptions: [(value: Int, label: String)] {
        Array(stride(from: 0, to: 1440, by: 15)).map { minutes in
            (value: minutes, label: timeLabel(minutes: minutes))
        }
    }

    private static func timeLabel(minutes: Int) -> String {
        let hour = minutes / 60
        let minute = minutes % 60
        let displayHour = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "AM" : "PM"
        return "\(displayHour):\(String(format: "%02d", minute)) \(suffix)"
    }
}

struct DurationRow: View {
    let title: String
    let selection: Binding<Int>

    init(_ title: String, selection: Binding<Int>) {
        self.title = title
        self.selection = selection
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(ChromeColor.primaryText)

            Spacer(minLength: 12)

            PreferenceMenuPicker(
                selection: selection,
                options: Self.durationOptions
            )
        }
        .frame(maxWidth: .infinity)
    }

    private static var durationOptions: [(value: Int, label: String)] {
        Array(stride(from: 0, through: 240, by: 15)).map { minutes in
            (value: minutes, label: durationLabel(minutes: minutes))
        }
    }

    private static func durationLabel(minutes: Int) -> String {
        if minutes == 0 {
            return "None"
        }

        let hours = minutes / 60
        let minutes = minutes % 60

        if hours == 0 {
            return "\(minutes) min"
        }

        if minutes == 0 {
            return hours == 1 ? "1 hour" : "\(hours) hours"
        }

        return "\(hours)h \(minutes)m"
    }
}

struct PreferenceMenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(value: Value, label: String)]
    @State private var isHovered = false

    private var selectedLabel: String {
        options.first { $0.value == selection }?.label ?? ""
    }

    var body: some View {
        Menu {
            ForEach(options, id: \.value) { option in
                Button {
                    selection = option.value
                } label: {
                    if option.value == selection {
                        Label(option.label, systemImage: "checkmark")
                    } else {
                        Text(option.label)
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Text(selectedLabel)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(ChromeColor.primaryText)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(ChromeColor.secondaryText)
                    .frame(width: 18, height: 18)
                    .background(ChromeColor.selectChevronBackground)
                    .clipShape(Circle())
            }
            .padding(.leading, 6)
            .padding(.trailing, 2)
            .frame(height: 24)
            .background(isHovered ? ChromeColor.selectHover : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

extension View {
    func lastPreferenceRow() -> some View {
        listRowSeparator(.hidden, edges: .bottom)
    }
}

struct SettingsControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .regular))
            .foregroundStyle(ChromeColor.primaryText)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(configuration.isPressed ? ChromeColor.settingsButtonPressedBackground : ChromeColor.settingsButtonBackground)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

extension ButtonStyle where Self == SettingsControlButtonStyle {
    static var settingsControl: SettingsControlButtonStyle {
        SettingsControlButtonStyle()
    }
}
