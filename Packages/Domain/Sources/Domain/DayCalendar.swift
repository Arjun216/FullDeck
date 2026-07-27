import Foundation

/// The one calendar Domain does day arithmetic on: a fixed Gregorian/UTC
/// calendar, never `Calendar.current`. Results must not depend on the device's
/// locale or time zone, and `date(byAdding: .day, ...)` stays correct across DST.
///
/// Internal on purpose — an implementation detail shared by `Scheduler` and
/// `SessionBuilder` so the two can never drift onto different calendars.
enum DayCalendar {
    static let gregorianUTC: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    static func startOfDay(_ date: Date) -> Date {
        gregorianUTC.startOfDay(for: date)
    }

    static func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        gregorianUTC.isDate(lhs, inSameDayAs: rhs)
    }

    /// Falls back to `date` if the calendar cannot produce the result — day
    /// arithmetic on a Gregorian calendar never actually fails, and the
    /// alternative is a force-unwrap Domain does not allow.
    static func adding(days: Int, to date: Date) -> Date {
        gregorianUTC.date(byAdding: .day, value: days, to: date) ?? date
    }
}
