import Foundation
import SwiftData

@Model
final class Measurement {
    var date: Date
    var weight: Double?
    var bodyFat: Double?
    var waist: Double?
    var chest: Double?
    var neck: Double?
    var note: String?

    init(
        date: Date = .now,
        weight: Double? = nil,
        bodyFat: Double? = nil,
        waist: Double? = nil,
        chest: Double? = nil,
        neck: Double? = nil,
        note: String? = nil
    ) {
        self.date = date
        self.weight = weight
        self.bodyFat = bodyFat
        self.waist = waist
        self.chest = chest
        self.neck = neck
        self.note = note
    }

    var leanMass: Double? {
        guard let w = weight, let bf = bodyFat else { return nil }
        return w * (1.0 - bf / 100.0)
    }

    var fatMass: Double? {
        guard let w = weight, let bf = bodyFat else { return nil }
        return w * (bf / 100.0)
    }

    var isFullCheckIn: Bool {
        bodyFat != nil || waist != nil || chest != nil || neck != nil
    }
}

enum MeasurementCadence {
    static let fullCheckInWeekday = 7 // Saturday in Calendar.current

    static func isFullCheckInDay(_ date: Date = .now, calendar: Calendar = .current) -> Bool {
        calendar.component(.weekday, from: date) == fullCheckInWeekday
    }

    static func nextFullCheckIn(from date: Date = .now, calendar: Calendar = .current) -> Date {
        if isFullCheckInDay(date, calendar: calendar) {
            return calendar.startOfDay(for: date)
        }

        var components = DateComponents()
        components.weekday = fullCheckInWeekday

        return calendar.nextDate(
            after: date,
            matching: components,
            matchingPolicy: .nextTimePreservingSmallerComponents
        ).map { calendar.startOfDay(for: $0) } ?? calendar.startOfDay(for: date)
    }

    static func hasFullCheckInThisWeek(_ measurements: [Measurement], from date: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: date)?.start,
              let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart)
        else { return false }

        return measurements.contains { measurement in
            measurement.isFullCheckIn && measurement.date >= weekStart && measurement.date < weekEnd
        }
    }
}

enum MetricKind: String, CaseIterable, Identifiable {
    case weight, bodyFat, leanMass, fatMass
    case waist, chest, neck
    case protein, carbs, fat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weight: return "Vücut Ağırlığı"
        case .bodyFat: return "Yağ Oranı"
        case .leanMass: return "Yağsız Kütle"
        case .fatMass: return "Yağ Kütlesi"
        case .waist: return "Bel"
        case .chest: return "Göğüs"
        case .neck: return "Boyun"
        case .protein: return "Protein"
        case .carbs: return "Karbonhidrat"
        case .fat: return "Yağ"
        }
    }

    var unit: String {
        switch self {
        case .weight, .leanMass, .fatMass: return "kg"
        case .bodyFat: return "%"
        case .waist, .chest, .neck: return "cm"
        case .protein, .carbs, .fat: return "g"
        }
    }

    var category: MetricCategory {
        switch self {
        case .weight, .bodyFat, .leanMass, .fatMass: return .composition
        case .waist, .chest, .neck: return .torso
        case .protein, .carbs, .fat: return .macros
        }
    }

    func value(from m: Measurement) -> Double? {
        switch self {
        case .weight: return m.weight
        case .bodyFat: return m.bodyFat
        case .leanMass: return m.leanMass
        case .fatMass: return m.fatMass
        case .waist: return m.waist
        case .chest: return m.chest
        case .neck: return m.neck
        case .protein, .carbs, .fat: return nil
        }
    }

    var lowerIsBetter: Bool {
        switch self {
        case .bodyFat, .fatMass, .waist: return true
        default: return false
        }
    }
}

enum MetricCategory: String, CaseIterable, Identifiable {
    case composition, torso, macros
    var id: String { rawValue }
    var label: String {
        switch self {
        case .composition: return "Vücut Kompozisyonu"
        case .torso: return "Gövde Çevreleri"
        case .macros: return "Makrolar"
        }
    }
}
