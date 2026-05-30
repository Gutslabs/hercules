import Foundation
import SwiftData

enum WorkoutPlanOverrideOperation: String, Codable, CaseIterable, Hashable {
    case addExercise = "add_exercise"
}

struct WorkoutProgramSessionSnapshot: Codable, Equatable, Identifiable {
    var id: Int { weekday }
    var weekday: Int
    var name: String
    var estimatedCalories: Double
    var durationMinutes: Int
    var focus: String?
    var warmup: String?
    var progression: String?
    var notes: String?
    var exercises: [WorkoutTemplateExerciseSnapshot]
}

struct WorkoutTemplateExerciseSnapshot: Codable, Equatable, Identifiable {
    var id: Int { order }
    var name: String
    var order: Int
    var sets: Int?
    var reps: String?
    var load: String?
    var rir: String?
    var rest: String?
    var sourceURL: String?
    var notes: String?
}

@Model
final class WorkoutPlanOverride {
    /// Calendar.weekday convention: 1=Pazar, 2=Pazartesi, ... 7=Cumartesi
    var weekday: Int
    var operationRaw: String
    var exerciseName: String
    var sets: Int?
    var reps: Int?
    var weight: Double?
    var note: String?
    var source: String
    var createdAt: Date

    init(
        weekday: Int,
        operation: WorkoutPlanOverrideOperation = .addExercise,
        exerciseName: String,
        sets: Int? = nil,
        reps: Int? = nil,
        weight: Double? = nil,
        note: String? = nil,
        source: String = "manual",
        createdAt: Date = .now
    ) {
        self.weekday = weekday
        self.operationRaw = operation.rawValue
        self.exerciseName = exerciseName
        self.sets = sets
        self.reps = reps
        self.weight = weight
        self.note = note
        self.source = source
        self.createdAt = createdAt
    }

    var operation: WorkoutPlanOverrideOperation {
        WorkoutPlanOverrideOperation(rawValue: operationRaw) ?? .addExercise
    }

    var prescriptionText: String {
        var parts: [String] = []
        if let sets, let reps {
            parts.append("\(sets)×\(reps)")
        } else if let sets {
            parts.append("\(sets) set")
        } else if let reps {
            parts.append("\(reps) tekrar")
        }
        if let weight {
            let formatted = weight == weight.rounded() ? "\(Int(weight))" : String(format: "%.1f", weight)
            parts.append("@ \(formatted) kg")
        }
        return parts.isEmpty ? "plan eklemesi" : parts.joined(separator: " ")
    }
}

@Model
final class WorkoutProgramArchive {
    var title: String
    var summary: String?
    var notes: String?
    var source: String
    var archivedAt: Date
    var sessionsJSON: String

    init(
        title: String,
        summary: String? = nil,
        notes: String? = nil,
        source: String = "manual",
        archivedAt: Date = .now,
        sessionsJSON: String
    ) {
        self.title = title
        self.summary = summary
        self.notes = notes
        self.source = source
        self.archivedAt = archivedAt
        self.sessionsJSON = sessionsJSON
    }

    var sessions: [WorkoutProgramSessionSnapshot] {
        guard let data = sessionsJSON.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([WorkoutProgramSessionSnapshot].self, from: data)
        else { return [] }
        return decoded
    }
}

@Model
final class WorkoutTemplateExercise {
    var name: String
    var order: Int
    var sets: Int?
    var reps: String?
    var load: String?
    var rir: String?
    var rest: String?
    var sourceURL: String?
    var notes: String?

    init(
        name: String,
        order: Int = 0,
        sets: Int? = nil,
        reps: String? = nil,
        load: String? = nil,
        rir: String? = nil,
        rest: String? = nil,
        sourceURL: String? = nil,
        notes: String? = nil
    ) {
        self.name = name
        self.order = order
        self.sets = sets
        self.reps = reps
        self.load = load
        self.rir = rir
        self.rest = rest
        self.sourceURL = sourceURL
        self.notes = notes
    }

    var prescriptionText: String {
        var parts: [String] = []
        if let sets, let reps, !reps.isEmpty {
            parts.append("\(sets)×\(reps)")
        } else if let sets {
            parts.append("\(sets) set")
        } else if let reps, !reps.isEmpty {
            parts.append(reps)
        }
        if let load, !load.isEmpty {
            parts.append(load)
        }
        if let rir, !rir.isEmpty {
            parts.append("RIR \(rir)")
        }
        if let rest, !rest.isEmpty {
            parts.append(rest)
        }
        return parts.isEmpty ? "reçete yok" : parts.joined(separator: " · ")
    }

    var snapshot: WorkoutTemplateExerciseSnapshot {
        WorkoutTemplateExerciseSnapshot(
            name: name,
            order: order,
            sets: sets,
            reps: reps,
            load: load,
            rir: rir,
            rest: rest,
            sourceURL: sourceURL,
            notes: notes
        )
    }
}

@Model
final class WorkoutSession {
    /// Calendar.weekday convention: 1=Pazar, 2=Pazartesi, …, 7=Cumartesi
    var weekday: Int
    var name: String
    var estimatedCalories: Double
    /// Optional on disk so older stores can migrate without losing data.
    var durationMinutesValue: Int?
    var focus: String?
    var warmup: String?
    var progression: String?
    var notes: String?
    /// Sync merge: son değişiklik zamanı (çakışmada yenisi kazanır).
    var updatedAt: Date = Date.now
    @Relationship(deleteRule: .cascade) var templateExercises: [WorkoutTemplateExercise] = []

    init(
        weekday: Int,
        name: String,
        estimatedCalories: Double = 300,
        durationMinutes: Int = 60,
        focus: String? = nil,
        warmup: String? = nil,
        progression: String? = nil,
        notes: String? = nil
    ) {
        self.weekday = weekday
        self.name = name
        self.estimatedCalories = estimatedCalories
        self.durationMinutesValue = durationMinutes
        self.focus = focus
        self.warmup = warmup
        self.progression = progression
        self.notes = notes
    }

    static let weekdayNames: [String] = [
        "", "Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"
    ]

    static let weekdayShort: [String] = [
        "", "Pa", "Pt", "Sa", "Ça", "Pe", "Cu", "Ct"
    ]

    var weekdayName: String {
        guard weekday >= 1 && weekday <= 7 else { return "?" }
        return Self.weekdayNames[weekday]
    }

    /// Sınır-güvenli statik gün adı (geçersiz/decoded index → "?"). Çökmeyi önler.
    static func weekdayName(_ index: Int) -> String {
        weekdayNames.indices.contains(index) ? weekdayNames[index] : "?"
    }

    /// Sınır-güvenli statik kısa gün adı.
    static func weekdayShortName(_ index: Int) -> String {
        weekdayShort.indices.contains(index) ? weekdayShort[index] : "?"
    }

    var sortedTemplateExercises: [WorkoutTemplateExercise] {
        templateExercises.sorted { $0.order < $1.order }
    }

    var durationMinutes: Int {
        get { durationMinutesValue ?? 60 }
        set { durationMinutesValue = newValue }
    }

    var snapshot: WorkoutProgramSessionSnapshot {
        WorkoutProgramSessionSnapshot(
            weekday: weekday,
            name: name,
            estimatedCalories: estimatedCalories,
            durationMinutes: durationMinutes,
            focus: focus,
            warmup: warmup,
            progression: progression,
            notes: notes,
            exercises: sortedTemplateExercises.map(\.snapshot)
        )
    }
}
