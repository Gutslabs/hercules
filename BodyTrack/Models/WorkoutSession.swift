import Foundation
import SwiftData

enum WorkoutPlanOverrideOperation: String, Codable, CaseIterable, Hashable {
    case addExercise = "add_exercise"
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
final class WorkoutSession {
    /// Calendar.weekday convention: 1=Pazar, 2=Pazartesi, …, 7=Cumartesi
    var weekday: Int
    var name: String
    var estimatedCalories: Double

    init(weekday: Int, name: String, estimatedCalories: Double = 300) {
        self.weekday = weekday
        self.name = name
        self.estimatedCalories = estimatedCalories
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
}
