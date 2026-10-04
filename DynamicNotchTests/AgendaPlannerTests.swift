//
//  AgendaPlannerTests.swift
//  DynamicNotchTests
//

@testable import DynamicNotch
import EventKit
import XCTest

final class AgendaPlannerTests: XCTestCase {
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Paris")!
        return c
    }()

    /// Vendredi 26 septembre 2026, 10:00 (Paris).
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: 26, hour: 10))!
    }

    private func entry(_ id: String, day: Int, hour: Int, minutes: Int = 60, allDay: Bool = false) -> AgendaEntry {
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
        return AgendaEntry(
            id: id,
            title: id,
            start: start,
            end: start.addingTimeInterval(TimeInterval(minutes * 60)),
            isAllDay: allDay,
            color: nil
        )
    }

    func test_split_sortsTodayAndTomorrow_allDayFirst() {
        let entries = [
            entry("demain", day: 27, hour: 9),
            entry("midi", day: 26, hour: 12),
            entry("matin", day: 26, hour: 8),
            entry("journée", day: 26, hour: 0, minutes: 24 * 60, allDay: true),
            entry("hier", day: 25, hour: 18)
        ]
        let split = AgendaPlanner.split(entries, now: now, calendar: calendar)
        XCTAssertEqual(split.today.map(\.id), ["journée", "matin", "midi"])
        XCTAssertEqual(split.tomorrow.map(\.id), ["demain"])
    }

    func test_upcoming_skipsEndedAndAllDay_andLimits() {
        let today = [
            entry("journée", day: 26, hour: 0, minutes: 24 * 60, allDay: true),
            entry("fini", day: 26, hour: 8),
            entry("en cours", day: 26, hour: 9, minutes: 90),
            entry("midi", day: 26, hour: 12),
            entry("soir", day: 26, hour: 18)
        ]
        XCTAssertEqual(AgendaPlanner.upcoming(today, now: now, limit: 2).map(\.id), ["en cours", "midi"])
    }

    func test_accessMapping() {
        XCTAssertEqual(CalendarStore.access(for: .fullAccess), .granted)
        XCTAssertEqual(CalendarStore.access(for: .notDetermined), .notDetermined)
        XCTAssertEqual(CalendarStore.access(for: .denied), .denied)
        XCTAssertEqual(CalendarStore.access(for: .restricted), .denied)
        XCTAssertEqual(CalendarStore.access(for: .writeOnly), .denied)
    }

    func test_makeID_distinguishesOccurrences_andIsStable() {
        let first = Date(timeIntervalSince1970: 1000)
        let second = Date(timeIntervalSince1970: 87400)
        let a = AgendaEntry.makeID(eventIdentifier: "evt", title: "Réunion", start: first)
        let b = AgendaEntry.makeID(eventIdentifier: "evt", title: "Réunion", start: second)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a, AgendaEntry.makeID(eventIdentifier: "evt", title: "Réunion", start: first))
        XCTAssertEqual(a, "evt-1000.0")
    }

    func test_makeID_fallsBackToTitle_thenPlaceholder() {
        let start = Date(timeIntervalSince1970: 42)
        XCTAssertEqual(AgendaEntry.makeID(eventIdentifier: nil, title: "Sport", start: start), "Sport-42.0")
        XCTAssertEqual(AgendaEntry.makeID(eventIdentifier: nil, title: nil, start: start), "event-42.0")
    }
}
