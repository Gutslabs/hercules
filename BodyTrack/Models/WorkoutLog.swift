import Foundation
import SwiftData

/// Bir günde yapılan antrenman kaydı — `WorkoutSession` weekly template'ten farklı:
/// Bu, GERÇEK seans logu (tarih + isim + hareketler + süre).
@Model
final class WorkoutLog {
    var date: Date
    var name: String
    var durationMinutes: Int
    var notes: String?
    /// Tahmini kalori — kullanıcı manuel girer ya da süre × yoğunluk hesaplaması.
    var estimatedCalories: Double
    /// Sync merge: son değişiklik zamanı (çakışmada yenisi kazanır).
    var updatedAt: Date = Date.now
    @Relationship(deleteRule: .cascade) var exercises: [WorkoutExerciseEntry] = []

    init(
        date: Date = .now,
        name: String = "",
        durationMinutes: Int = 60,
        estimatedCalories: Double = 300,
        notes: String? = nil
    ) {
        self.date = date
        self.name = name
        self.durationMinutes = durationMinutes
        self.estimatedCalories = estimatedCalories
        self.notes = notes
    }
}

/// Tek bir hareket — `WorkoutLog`'a bağlı. Her hareket [ExerciseSet] tutar.
@Model
final class WorkoutExerciseEntry {
    var name: String
    /// Hareketin listede sırası (1. hareket = order 0).
    var order: Int
    @Relationship(deleteRule: .cascade) var setEntries: [ExerciseSet] = []

    init(name: String = "", order: Int = 0) {
        self.name = name
        self.order = order
    }

    var sortedSets: [ExerciseSet] {
        setEntries.sorted { $0.order < $1.order }
    }

    var totalReps: Int {
        setEntries.reduce(0) { $0 + $1.reps }
    }

    /// Toplam tonaj — Σ(reps × weight). Eğer hiçbir set'te kg yoksa nil.
    var totalVolume: Double? {
        let volumes = setEntries.compactMap { s -> Double? in
            guard let w = s.weight else { return nil }
            return Double(s.reps) * w
        }
        return volumes.isEmpty ? nil : volumes.reduce(0, +)
    }

    /// Insan-okunabilir özet, akıllı format:
    /// - Tüm setler aynı kg + reps → "3×10 @ 80 kg"
    /// - Aynı reps, farklı kg → "10 @ 60/80/100 kg"
    /// - Aynı kg, farklı reps → "12/10/8 @ 80 kg"
    /// - Hepsi farklı → "60×12, 80×8, 100×6 kg"
    /// - Bodyweight (kg yok) → "12, 10, 8"
    var summary: String {
        let sorted = sortedSets
        guard !sorted.isEmpty else { return "—" }
        let allReps = sorted.map(\.reps)
        let allWeights = sorted.map(\.weight)
        let uniformReps = allReps.allSatisfy { $0 == allReps[0] }
        let uniformWeights = allWeights.allSatisfy { $0 == allWeights[0] }
        let allHaveWeight = allWeights.allSatisfy { $0 != nil }
        let noneHaveWeight = allWeights.allSatisfy { $0 == nil }

        if uniformReps && uniformWeights {
            if let w = allWeights[0] {
                return "\(sorted.count)×\(allReps[0]) @ \(formatWeight(w)) kg"
            }
            return "\(sorted.count)×\(allReps[0])"
        }
        if uniformReps && allHaveWeight {
            let kgList = allWeights.compactMap { $0 }.map(formatWeight).joined(separator: "/")
            return "\(allReps[0]) @ \(kgList) kg"
        }
        if uniformWeights && !uniformReps {
            let repList = allReps.map(String.init).joined(separator: "/")
            if let w = allWeights[0] {
                return "\(repList) @ \(formatWeight(w)) kg"
            }
            return repList
        }
        // Tamamen farklı
        if noneHaveWeight {
            return allReps.map(String.init).joined(separator: ", ")
        }
        let parts = sorted.map { s -> String in
            if let w = s.weight {
                return "\(formatWeight(w))×\(s.reps)"
            }
            return "BW×\(s.reps)"
        }
        let suffix = allHaveWeight ? " kg" : ""
        return parts.joined(separator: ", ") + suffix
    }

    private func formatWeight(_ w: Double) -> String {
        w == w.rounded() ? "\(Int(w))" : String(format: "%.1f", w)
    }
}

/// Tek bir set — bir hareketin bir tekrarı (örn. 60 kg × 12 tekrar).
@Model
final class ExerciseSet {
    /// Sıra (1. set = order 0).
    var order: Int
    var reps: Int
    /// kg cinsinden. Bodyweight için nil.
    var weight: Double?

    init(order: Int = 0, reps: Int = 10, weight: Double? = nil) {
        self.order = order
        self.reps = reps
        self.weight = weight
    }
}
