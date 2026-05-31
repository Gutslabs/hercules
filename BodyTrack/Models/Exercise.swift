import Foundation
import SwiftData

// MARK: - ExerciseCategory

enum ExerciseCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case push      = "push"
    case pull      = "pull"
    case legs      = "legs"
    case core      = "core"
    case fullBody  = "fullBody"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .push:     return "İtiş (Push)"
        case .pull:     return "Çekiş (Pull)"
        case .legs:     return "Bacak"
        case .core:     return "Karın / Core"
        case .fullBody: return "Tüm Vücut"
        }
    }

    var icon: String {
        switch self {
        case .push:     return "arrow.up.circle"
        case .pull:     return "arrow.down.circle"
        case .legs:     return "figure.walk"
        case .core:     return "rotate.3d"
        case .fullBody: return "figure.mixed.cardio"
        }
    }

    var shortLabel: String {
        switch self {
        case .push:     return "Push"
        case .pull:     return "Pull"
        case .legs:     return "Bacak"
        case .core:     return "Core"
        case .fullBody: return "Full Body"
        }
    }
}

// MARK: - Difficulty

enum Difficulty: String, Codable, CaseIterable, Identifiable, Sendable {
    case beginner     = "beginner"
    case intermediate = "intermediate"
    case advanced     = "advanced"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .beginner:     return "Başlangıç"
        case .intermediate: return "Orta"
        case .advanced:     return "İleri"
        }
    }

    var icon: String {
        switch self {
        case .beginner:     return "1.circle"
        case .intermediate: return "2.circle"
        case .advanced:     return "3.circle"
        }
    }

    var color: String {
        // Renk adı — SwiftUI'da Color(difficulty.color) ile kullanılır
        switch self {
        case .beginner:     return "green"
        case .intermediate: return "orange"
        case .advanced:     return "red"
        }
    }
}

// MARK: - Equipment

enum Equipment: String, Codable, CaseIterable, Identifiable, Sendable {
    case barbell, dumbbell, machine, cable, bodyweight, kettlebell, band, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .barbell:    return "Barbell"
        case .dumbbell:   return "Dumbbell"
        case .machine:    return "Makine"
        case .cable:      return "Kablo"
        case .bodyweight: return "Vücut Ağırlığı"
        case .kettlebell: return "Kettlebell"
        case .band:       return "Bant"
        case .other:      return "Diğer"
        }
    }

    var icon: String {
        switch self {
        case .barbell:    return "minus.circle.fill"
        case .dumbbell:   return "dumbbell.fill"
        case .machine:    return "gearshape.fill"
        case .cable:      return "cable.connector"
        case .bodyweight: return "figure.stand"
        case .kettlebell: return "bell.fill"
        case .band:       return "oval"
        case .other:      return "questionmark.circle"
        }
    }
}

// MARK: - MuscleRegion

/// Her bölge ya ön ya da arka görünümde yer alır.
enum MuscleRegion: String, Codable, CaseIterable, Identifiable, Sendable {
    // Ön
    case chest
    case frontDelt
    case biceps
    case forearmFront
    case upperAbs
    case lowerAbs
    case obliques
    case quadriceps
    case tibialis

    // Arka
    case traps
    case rearDelt
    case lats
    case triceps
    case forearmBack
    case lowerBack
    case glutes
    case hamstrings
    case calves

    var id: String { rawValue }

    /// Geniş kas grubu etiketi (kütüphane gruplandırması için)
    var muscleGroup: String {
        switch self {
        case .chest:                    return "Göğüs"
        case .frontDelt, .rearDelt:     return "Omuzlar"
        case .traps, .lats, .lowerBack: return "Sırt"
        case .biceps, .triceps,
             .forearmFront, .forearmBack: return "Kollar"
        case .upperAbs, .lowerAbs, .obliques: return "Karın"
        case .quadriceps, .hamstrings,
             .glutes, .calves, .tibialis: return "Bacaklar"
        }
    }

    var isFront: Bool {
        switch self {
        case .chest, .frontDelt, .biceps, .forearmFront,
             .upperAbs, .lowerAbs, .obliques, .quadriceps, .tibialis:
            return true
        default:
            return false
        }
    }

    var label: String {
        switch self {
        case .chest:        return "Göğüs"
        case .frontDelt:    return "Ön Deltoid"
        case .biceps:       return "Biseps"
        case .forearmFront: return "Ön Kol"
        case .upperAbs:     return "Üst Karın"
        case .lowerAbs:     return "Alt Karın"
        case .obliques:     return "Oblique"
        case .quadriceps:   return "Quadriceps"
        case .tibialis:     return "Tibialis"
        case .traps:        return "Trapez"
        case .rearDelt:     return "Arka Deltoid"
        case .lats:         return "Latissimus"
        case .triceps:      return "Triseps"
        case .forearmBack:  return "Arka Kol"
        case .lowerBack:    return "Alt Sırt"
        case .glutes:       return "Gluteus"
        case .hamstrings:   return "Hamstring"
        case .calves:       return "Baldır"
        }
    }
}

// MARK: - Exercise Model

@Model
final class Exercise {
    var name: String
    var equipmentRaw: String
    /// Virgülle ayrılmış MuscleRegion rawValue'ları
    var primaryMusclesRaw: String
    var secondaryMusclesRaw: String
    /// ExerciseCategory rawValue (Push/Pull/Legs/Core/FullBody)
    var categoryRaw: String
    /// Difficulty rawValue (beginner/intermediate/advanced) — nil = belirtilmemiş
    var difficultyRaw: String?
    /// Teknik notlar / cue'lar
    var notes: String?
    /// Referans video / makale URL'i
    var sourceURL: String?
    /// Virgülle ayrılmış varyasyon isimleri
    var variationsRaw: String?
    /// Virgülle ayrılmış görsel URL'leri (free-exercise-db başlangıç/bitiş fotoğrafları)
    var imageURLsRaw: String?
    var createdAt: Date

    init(
        name: String,
        equipment: Equipment = .barbell,
        primaryMuscles: [MuscleRegion] = [],
        secondaryMuscles: [MuscleRegion] = [],
        category: ExerciseCategory? = nil,
        difficulty: Difficulty? = nil,
        notes: String = "",
        sourceURL: String = "",
        variations: [String] = [],
        imageURLs: [String] = []
    ) {
        self.name = name
        self.equipmentRaw = equipment.rawValue
        self.primaryMusclesRaw   = primaryMuscles.map(\.rawValue).joined(separator: ",")
        self.secondaryMusclesRaw = secondaryMuscles.map(\.rawValue).joined(separator: ",")
        self.categoryRaw   = category?.rawValue ?? ""
        self.difficultyRaw = difficulty?.rawValue
        self.notes         = notes.isEmpty ? nil : notes
        self.sourceURL     = sourceURL.isEmpty ? nil : sourceURL
        self.variationsRaw = variations.isEmpty ? nil : variations.joined(separator: ",")
        self.imageURLsRaw = imageURLs.isEmpty ? nil : imageURLs.joined(separator: ",")
        self.createdAt = .now
    }

    var equipment: Equipment {
        get { Equipment(rawValue: equipmentRaw) ?? .other }
        set { equipmentRaw = newValue.rawValue }
    }

    var category: ExerciseCategory? {
        get { ExerciseCategory(rawValue: categoryRaw) }
        set { categoryRaw = newValue?.rawValue ?? "" }
    }

    var difficulty: Difficulty? {
        get { difficultyRaw.flatMap { Difficulty(rawValue: $0) } }
        set { difficultyRaw = newValue?.rawValue }
    }

    /// Virgülle ayrılmış varyasyon isimlerini dizi olarak döndürür
    var variations: [String] {
        get {
            (variationsRaw ?? "")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        set { variationsRaw = newValue.isEmpty ? nil : newValue.joined(separator: ",") }
    }

    /// Hareket görselleri (free-exercise-db başlangıç/bitiş fotoğrafları)
    var imageURLs: [URL] {
        get {
            (imageURLsRaw ?? "")
                .split(separator: ",")
                .compactMap { URL(string: $0.trimmingCharacters(in: .whitespaces)) }
        }
        set { imageURLsRaw = newValue.isEmpty ? nil : newValue.map(\.absoluteString).joined(separator: ",") }
    }

    /// Birincil kasların baskın kas grubu (kütüphane gruplandırması için)
    var primaryMuscleGroup: String {
        primaryMuscles.first?.muscleGroup ?? "Diğer"
    }

    var primaryMuscles: [MuscleRegion] {
        get {
            primaryMusclesRaw
                .split(separator: ",")
                .compactMap { MuscleRegion(rawValue: String($0)) }
        }
        set { primaryMusclesRaw = newValue.map(\.rawValue).joined(separator: ",") }
    }

    var secondaryMuscles: [MuscleRegion] {
        get {
            secondaryMusclesRaw
                .split(separator: ",")
                .compactMap { MuscleRegion(rawValue: String($0)) }
        }
        set { secondaryMusclesRaw = newValue.map(\.rawValue).joined(separator: ",") }
    }

    /// Tüm çalışılan kaslar (birincil + ikincil)
    var allMuscles: [MuscleRegion] {
        primaryMuscles + secondaryMuscles.filter { !primaryMuscles.contains($0) }
    }
}
