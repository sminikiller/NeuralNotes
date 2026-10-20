import Foundation

public struct StudyReviewEvent: Codable, Identifiable, Equatable, Sendable {
    public var id = UUID()
    public var cardID: UUID
    public var rating: ReviewRating
    public var date: Date
    public var intervalDays: Int
    public init(cardID: UUID, rating: ReviewRating, date: Date, intervalDays: Int) {
        self.cardID = cardID; self.rating = rating; self.date = date; self.intervalDays = intervalDays
    }
    public var isValid: Bool { date.timeIntervalSince1970.isFinite && date.timeIntervalSince1970 >= 0 && (0...1_000_000).contains(intervalDays) }
}

public struct StudyDay: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    public var date: Date
    public var count: Int
}

public struct StudyStatistics: Sendable {
    public var dueNow: Int
    public var matureCards: Int
    public var totalCards: Int
    public var recordedReviews: Int
    public var recalledReviews: Int
    public var streakDays: Int
    public var recentDays: [StudyDay]
    public var forecast: [StudyDay]
    public static func make(cards: [StudyCard], events: [StudyReviewEvent], now: Date = Date(), calendar: Calendar = .current) -> StudyStatistics {
        let today = calendar.startOfDay(for: now)
        let events = events.filter { $0.isValid && $0.date <= now }
        let daily = Dictionary(grouping: events, by: { calendar.startOfDay(for: $0.date) })
        let recent: [StudyDay] = (-6...0).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return StudyDay(date: date, count: daily[date]?.count ?? 0)
        }
        var schedule = [Int](repeating: 0, count: 7)
        for card in cards {
            let offset = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: card.dueAt)).day ?? 7
            if offset < 7 { schedule[max(0, offset)] += 1 }
        }
        let forecast: [StudyDay] = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return StudyDay(date: date, count: schedule[offset])
        }
        var streak = 0
        var cursor = daily[today] == nil ? calendar.date(byAdding: .day, value: -1, to: today) : today
        while let date = cursor, daily[date] != nil, streak < 10_000 {
            streak += 1; cursor = calendar.date(byAdding: .day, value: -1, to: date)
        }
        return StudyStatistics(dueNow: cards.filter { $0.dueAt <= now }.count, matureCards: cards.filter { $0.reviewCount > 0 && $0.intervalDays >= 21 }.count,
            totalCards: cards.count, recordedReviews: events.count, recalledReviews: events.filter { $0.rating != .again }.count,
            streakDays: streak, recentDays: recent, forecast: forecast)
    }
}
