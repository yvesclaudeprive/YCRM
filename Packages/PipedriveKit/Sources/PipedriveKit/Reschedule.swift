import Foundation

/// Un choix rapide du bouton « Décaler » : « Lundi prochain », le jour visé et sa date en clair.
public struct RescheduleChoice: Hashable, Sendable, Identifiable {
    public let id: String
    public let title: String
    /// Jour visé à l'heure de Paris (AAAA-MM-JJ).
    public let day: String
    /// « lun. 16 novembre ».
    public let dateText: String
}

/// Bouton « Décaler » (demande d'Yves du 09/11/2026) : nouvelle échéance d'une alerte Pipedrive, avec des choix rapides
/// « malins » (jamais un samedi ni un dimanche) et un calendrier pour choisir n'importe quelle date.
public enum Reschedule {
    static let weekdayNames = ["dim.", "lun.", "mar.", "mer.", "jeu.", "ven.", "sam."]

    /// Choix rapides à partir d'aujourd'hui (heure de Paris). Un jour qui tombe un week-end passe au lundi ;
    /// deux choix qui donnent le même jour n'apparaissent qu'une fois. Avec un rendez-vous à venir, son jour est le
    /// premier choix (demande d'Yves du 09/11/2026), tel quel (même un samedi, même aujourd'hui).
    public static func choices(now: Date = Date(), timeZone: TimeZone, meeting: UpcomingMeeting? = nil) -> [RescheduleChoice] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today) // 1 = dimanche … 7 = samedi
        let month = calendar.component(.month, from: today)
        let year = calendar.component(.year, from: today)
        func plus(_ component: Calendar.Component, _ value: Int) -> Date {
            calendar.date(byAdding: component, value: value, to: today) ?? today
        }
        func next(weekday target: Int) -> Date {
            let gap = (target - weekday + 7) % 7
            return plus(.day, gap == 0 ? 7 : gap)
        }
        func firstMonday(onOrAfter date: Date) -> Date {
            let day = calendar.component(.weekday, from: date)
            let gap = (2 - day + 7) % 7
            return calendar.date(byAdding: .day, value: gap, to: date) ?? date
        }
        func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
            calendar.date(from: DateComponents(year: y, month: m, day: d)) ?? today
        }

        var raw: [(String, String, Date)] = [
            ("tomorrow", "Demain", plus(.day, 1)),
            ("in2days", "Après-demain", plus(.day, 2)),
        ]
        // Lundi à jeudi : « Vendredi » de cette semaine.
        if (2...5).contains(weekday) { raw.append(("friday", "Vendredi", next(weekday: 6))) }
        raw += [
            ("monday", "Lundi prochain", next(weekday: 2)),
            ("1week", "Dans une semaine", plus(.day, 7)),
            ("2weeks", "Dans 2 semaines", plus(.day, 14)),
            ("nextMonth", "Début du mois prochain",
             calendar.date(from: DateComponents(year: year, month: month, day: 1))
                .flatMap { calendar.date(byAdding: .month, value: 1, to: $0) } ?? plus(.month, 1)),
            ("1month", "Dans un mois", plus(.month, 1)),
        ]
        // Fin d'année : après les fêtes (premier lundi à partir du 4 janvier).
        if month >= 11 {
            raw.append(("holidays", "Après les fêtes", firstMonday(onOrAfter: date(year + 1, 1, 4))))
        }
        // Printemps et été : à la rentrée (premier lundi de septembre).
        if (5...8).contains(month) {
            raw.append(("september", "À la rentrée", firstMonday(onOrAfter: date(year, 9, 1))))
        }
        raw += [
            ("3months", "Dans 3 mois", plus(.month, 3)),
            ("6months", "Dans 6 mois", plus(.month, 6)),
        ]

        var seen = Set<String>()
        var result: [RescheduleChoice] = []
        let todayText = FrenchFormat.apiDay(from: today, timeZone: timeZone)
        if let meeting, meeting.day >= todayText {
            seen.insert(meeting.day)
            let date = dateText(meeting.day, now: now, timeZone: timeZone)
            result.append(RescheduleChoice(id: "meeting", title: "Jour du RDV",
                                           day: meeting.day, dateText: meeting.time.map { "\(date) · RDV à \($0)" } ?? date))
        }
        for (id, title, target) in raw {
            let workday = Self.workday(target, calendar: calendar)
            let day = FrenchFormat.apiDay(from: workday, timeZone: timeZone)
            guard day > todayText, seen.insert(day).inserted else { continue }
            result.append(RescheduleChoice(id: id, title: title, day: day, dateText: dateText(day, now: now, timeZone: timeZone)))
        }
        return result
    }

    /// Samedi ou dimanche → lundi suivant.
    static func workday(_ date: Date, calendar: Calendar) -> Date {
        switch calendar.component(.weekday, from: date) {
        case 7: return calendar.date(byAdding: .day, value: 2, to: date) ?? date
        case 1: return calendar.date(byAdding: .day, value: 1, to: date) ?? date
        default: return date
        }
    }

    /// « lun. 16 novembre » (année seulement si elle diffère).
    public static func dateText(_ day: String, now: Date = Date(), timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let date = FrenchFormat.date(fromAPIDay: day, timeZone: timeZone) else { return day }
        let weekday = weekdayNames[calendar.component(.weekday, from: date) - 1]
        return "\(weekday) \(FrenchFormat.longDate(fromAPI: day, now: now, timeZone: timeZone))"
    }

    /// Heure de l'alerte à Paris (« 14:30 »), nil si elle n'a pas d'heure.
    public static func parisTime(of activity: Activity, timeZone: TimeZone) -> String? {
        guard let instant = activity.dueInstant else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: instant)
        return String(format: "%02ld:%02ld", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Nouvelle échéance au format Pipedrive : jour (et heure) en UTC si une heure de Paris est donnée, sinon le jour seul.
    public static func due(day: String, parisTime: String?, timeZone: TimeZone) -> (date: String, time: String?) {
        guard let parisTime, let parts = FrenchFormat.dayParts(day) else { return (day, nil) }
        let clock = parisTime.split(separator: ":").compactMap { Int($0) }
        guard clock.count == 2 else { return (day, nil) }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        guard let instant = calendar.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day,
                                                               hour: clock[0], minute: clock[1])) else { return (day, nil) }
        let utc = TimeZone(identifier: "UTC")!
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = utc
        let time = utcCalendar.dateComponents([.hour, .minute], from: instant)
        return (FrenchFormat.apiDay(from: instant, timeZone: utc),
                String(format: "%02ld:%02ld", time.hour ?? 0, time.minute ?? 0))
    }
}

public extension Activity {
    /// La même alerte avec une nouvelle échéance (format Pipedrive : UTC si une heure est renseignée).
    func withDue(date: String, time: String?) -> Activity {
        Activity(id: id, subject: subject, type: type, dueDate: date, dueTime: time, dealID: dealID, personID: personID,
                 orgID: orgID, done: done, note: note, ownerID: ownerID)
    }
}
