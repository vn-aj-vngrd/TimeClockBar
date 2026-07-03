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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChromeColor.secondaryText)

            HStack(spacing: 4) {
                ForEach(weekdays, id: \.weekday) { day in
                    let isSelected = selectedWeekdays.contains(day.weekday)

                    Button {
                        onChange(day.weekday, !isSelected)
                    } label: {
                        Text(day.label)
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity, minHeight: 26)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSelected ? ChromeColor.primaryText : ChromeColor.secondaryText)
                    .background(isSelected ? ChromeColor.reportBottom : ChromeColor.controlGroup)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(ChromeColor.sectionRing, lineWidth: 1)
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ChromeColor.secondaryText)

            VStack(alignment: .leading, spacing: 9) {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(ChromeColor.sectionBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(ChromeColor.sectionRing, lineWidth: 1)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChromeColor.secondaryText)

            Spacer(minLength: 12)

            accessory
        }
        .frame(minHeight: 32)
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChromeColor.primaryText)

            Spacer(minLength: 12)

            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChromeColor.secondaryText)

            Spacer(minLength: 12)

            Picker(title, selection: selection) {
                ForEach(Array(stride(from: 0, to: 1440, by: 15)), id: \.self) { minutes in
                    Text(Self.timeLabel(minutes: minutes)).tag(minutes)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 110)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ChromeColor.secondaryText)

            Spacer(minLength: 12)

            Picker(title, selection: selection) {
                ForEach(Array(stride(from: 0, through: 240, by: 15)), id: \.self) { minutes in
                    Text(Self.durationLabel(minutes: minutes)).tag(minutes)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(width: 110)
        }
        .frame(maxWidth: .infinity, minHeight: 32)
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
