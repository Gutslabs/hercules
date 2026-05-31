import Foundation
import SwiftData

// MARK: - TrainingProgram

@Model final class TrainingProgram {
    var name: String
    var notes: String?
    var isActive: Bool
    var startDate: Date?
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TrainingWeek.program)
    var weeks: [TrainingWeek] = []

    init(name: String, notes: String? = nil) {
        self.name     = name
        self.notes    = notes
        self.isActive = false
        self.startDate = nil
        self.createdAt = .now
    }

    var sortedWeeks: [TrainingWeek] {
        weeks.sorted { $0.weekNumber < $1.weekNumber }
    }

    /// Hafta 1'deki aktif antrenman günü sayısı (dinlenme günü olmayanlar)
    var activeDaysPerWeek: Int {
        sortedWeeks.first.map { $0.days.filter { !$0.isRestDay && !$0.isEmpty }.count } ?? 0
    }
}

// MARK: - TrainingWeek

@Model final class TrainingWeek {
    var weekNumber: Int
    var program: TrainingProgram?

    @Relationship(deleteRule: .cascade, inverse: \TrainingDay.week)
    var days: [TrainingDay] = []

    init(weekNumber: Int) {
        self.weekNumber = weekNumber
    }

    var sortedDays: [TrainingDay] {
        days.sorted { $0.dayNumber < $1.dayNumber }
    }

    func day(_ number: Int) -> TrainingDay? {
        days.first { $0.dayNumber == number }
    }
}

// MARK: - TrainingDay

@Model final class TrainingDay {
    var dayNumber: Int   // 1–7
    var isRestDay: Bool  // tüm gün dinlenme (blok yok)
    var name: String?    // ör. "Push", "Göğüs & Omuz" — nil ise gün adı gösterilir
    var week: TrainingWeek?

    @Relationship(deleteRule: .cascade, inverse: \TrainingBlock.day)
    var blocks: [TrainingBlock] = []

    init(dayNumber: Int) {
        self.dayNumber  = dayNumber
        self.isRestDay  = false
        self.name       = nil
    }

    var sortedBlocks: [TrainingBlock] {
        blocks.sorted { $0.order < $1.order }
    }

    /// Dinlenme günü değil ve hiç blok yok
    var isEmpty: Bool { !isRestDay && blocks.isEmpty }
}

// MARK: - TrainingBlock

@Model final class TrainingBlock {
    var order: Int
    var typeRaw: String           // "exercise" | "rest"
    var exerciseName: String?
    var sets: Int?
    var repsRaw: String?          // "8", "8-10", "AMRAP" …
    var restSeconds: Int?
    /// Hedef ağırlık / şiddet — ör. "60 kg", "%75", "RPE 8"
    var load: String?
    /// Reserve-in-reserve (yedekte kalan tekrar) — ör. "2", "1-2"
    var rir: String?
    /// Tempo — ör. "3-1-1" (eksantrik-duraklama-konsantrik)
    var tempo: String?
    var notes: String?
    var day: TrainingDay?

    init(
        order: Int,
        type: TrainingBlockType,
        exerciseName: String? = nil,
        sets: Int? = nil,
        reps: String? = nil,
        restSeconds: Int? = nil,
        load: String? = nil,
        rir: String? = nil,
        tempo: String? = nil,
        notes: String? = nil
    ) {
        self.order        = order
        self.typeRaw      = type.rawValue
        self.exerciseName = exerciseName
        self.sets         = sets
        self.repsRaw      = reps
        self.restSeconds  = restSeconds
        self.load         = load
        self.rir          = rir
        self.tempo        = tempo
        self.notes        = notes
    }

    var type: TrainingBlockType {
        TrainingBlockType(rawValue: typeRaw) ?? .exercise
    }

    var summaryText: String {
        switch type {
        case .exercise:
            let s = sets.map { "\($0)" } ?? "?"
            let r = repsRaw ?? "?"
            return "\(s)×\(r)"
        case .rest:
            return Self.formatSeconds(restSeconds ?? 60)
        }
    }

    /// Şiddet satırı: ağırlık + RIR + tempo (varsa) "·" ile birleştirilir.
    var intensityText: String? {
        var parts: [String] = []
        if let load, !load.isEmpty { parts.append(load) }
        if let rir, !rir.isEmpty { parts.append("RIR \(rir)") }
        if let tempo, !tempo.isEmpty { parts.append("Tempo \(tempo)") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func formatSeconds(_ secs: Int) -> String {
        if secs >= 60 {
            let m = secs / 60
            let s = secs % 60
            return s > 0 ? "\(m) dk \(s) sn" : "\(m) dk"
        }
        return "\(secs) sn"
    }
}

// MARK: - TrainingBlockType

enum TrainingBlockType: String, Codable, Sendable {
    case exercise = "exercise"
    case rest     = "rest"
}
