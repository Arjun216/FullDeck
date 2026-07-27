import Foundation
import Testing

@testable import Domain

private let day0 = Date(timeIntervalSince1970: 86_400 * 20_000)  // 2024-10-04T00:00:00Z

@Test("FR-4 two instants inside the same UTC day count as the same day")
func sameDayWithinTheDay() {
    let laterSameDay = day0.addingTimeInterval(23 * 3600)

    #expect(DayCalendar.isSameDay(day0, laterSameDay))
}

@Test("FR-4 an instant one day later is a different day")
func differentDayAcrossMidnight() {
    let nextDay = day0.addingTimeInterval(86_400)

    #expect(!DayCalendar.isSameDay(day0, nextDay))
}

@Test("FR-3 startOfDay truncates an instant to its UTC midnight")
func startOfDayTruncates() {
    let midAfternoon = day0.addingTimeInterval(13 * 3600 + 47 * 60)

    #expect(DayCalendar.startOfDay(midAfternoon) == day0)
}

@Test("FR-8 adding days moves forward by whole UTC days")
func addingDaysMovesForward() {
    #expect(DayCalendar.adding(days: 6, to: day0) == day0.addingTimeInterval(6 * 86_400))
}
