import EventKit
import SwiftUI

struct TimeWidget: View {
    @EnvironmentObject var configProvider: ConfigProvider
    var config: ConfigData { configProvider.config }
    var calendarConfig: ConfigData? { config["calendar"]?.dictionaryValue }

    var format: String { config["format"]?.stringValue ?? "E d, J:mm" }
    var timeZone: String? { config["time-zone"]?.stringValue }

    var calendarFormat: String {
        calendarConfig?["format"]?.stringValue ?? "J:mm"
    }
    var calendarShowEvents: Bool {
        calendarConfig?["show-events"]?.boolValue ?? true
    }

    var stacked: Bool { config["stacked"]?.boolValue ?? false }
    var stackedTimeFormat: String { config["stacked-time-format"]?.stringValue ?? "J:mm" }
    var stackedDateFormat: String { config["stacked-date-format"]?.stringValue ?? "E d MMM" }

    @State private var currentTime = Date()
    let calendarManager: CalendarManager

    @State private var rect = CGRect()

    private let timer = Timer.publish(every: 1, on: .main, in: .common)
        .autoconnect()

    var body: some View {
        widgetContent
        .foregroundStyle(.foregroundOutside)
        .shadow(color: .foregroundShadowOutside, radius: 3)
        .onReceive(timer) { date in
            currentTime = date
        }
        .captureScreenRect(into: $rect)
        .experimentalConfiguration(cornerRadius: 15)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.001))
        .monospacedDigit()
        .contentShape(Rectangle())
        .onTapGesture {
            MenuBarPopup.show(rect: rect, id: "calendar") {
                CalendarPopup(
                    calendarManager: calendarManager,
                    configProvider: configProvider)
            }
        }
    }

    @ViewBuilder
    private var widgetContent: some View {
        if stacked {
            VStack(alignment: .trailing, spacing: 1) {
                Text(formattedTime(pattern: stackedTimeFormat, from: currentTime))
                    .font(.system(size: 14, weight: .semibold))
                Text(formattedTime(pattern: stackedDateFormat, from: currentTime))
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.7)
            }
        } else {
            VStack(alignment: .trailing, spacing: 0) {
                Text(formattedTime(pattern: format, from: currentTime))
                    .fontWeight(.semibold)
                if let event = calendarManager.nextEvent, calendarShowEvents {
                    Text(eventText(for: event))
                        .opacity(0.8)
                        .font(.subheadline)
                }
            }
            .font(.headline)
        }
    }

    // Format the current time.
    private func formattedTime(pattern: String, from time: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate(pattern)

        if let timeZone = timeZone,
            let tz = TimeZone(identifier: timeZone)
        {
            formatter.timeZone = tz
        } else {
            formatter.timeZone = TimeZone.current
        }

        return formatter.string(from: time)
    }

    // Create text for the calendar event.
    private func eventText(for event: EKEvent) -> String {
        var text = event.title ?? ""
        if !event.isAllDay {
            text += " ("
            text += formattedTime(
                pattern: calendarFormat, from: event.startDate)
            text += ")"
        }
        return text
    }
}

struct TimeWidget_Previews: PreviewProvider {
    static var previews: some View {
        let provider = ConfigProvider(config: ConfigData())
        let manager = CalendarManager(configProvider: provider)

        ZStack {
            TimeWidget(calendarManager: manager)
                .environmentObject(provider)
        }.frame(width: 500, height: 100)
    }
}
