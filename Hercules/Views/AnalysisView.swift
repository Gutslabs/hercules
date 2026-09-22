import SwiftUI
import SwiftData

/// Bilim Paneli — "Sade" dili (Views/AnalizFlow.swift): Yakım + Hız · Protein · Mikro kartları.
/// Deterministik analiz (AI değil); verinden hesaplanır. Bu kabuk yalnız veriyi toplar:
/// SwiftData sorguları ve mikro besin deposu (disk önbelleği + aylık tur).
struct AnalysisView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Measurement.date) private var measurements: [Measurement]
    @Query(sort: \FoodEntry.date) private var foods: [FoodEntry]
    @Query private var profiles: [UserProfile]

    /// Mikro besin tahminleri (disk önbelleği + toplu tahmin motoru).
    @StateObject private var micros = MicroNutrientStore.shared

    private var profile: UserProfile? { profiles.first }

    var body: some View {
        AnalizFlowView(
            measurements: measurements,
            foods: foods,
            profile: profile,
            micro: microState,
            onMicroRefresh: refreshMicros
        )
        .background(DashboardBackground().ignoresSafeArea())
        // Uygulama uzun süre açık kalırsa ay dönümünü burada da yakala.
        .task { await MicroNutrientStore.runMonthlyPassIfDue(in: modelContext) }
    }

    // MARK: - Mikro besinler (elle tetiklenen aylık tur)

    private var microEntries: [(name: String, grams: Double?, date: Date)] {
        foods.map { (name: $0.name, grams: $0.grams, date: $0.date) }
    }

    /// Yemek adı + gramdan türetilen vitamin/mineral tahmini. Veri diskte, SwiftData'ya
    /// dokunulmaz; tur ELLE başlatılır ve sıradaki tur için geri sayım gösterilir.
    private var microState: AnalizMicroState {
        let entries = microEntries
        let age = profile.map { Calendar.current.dateComponents([.year], from: $0.birthDate, to: .now).year ?? 30 } ?? 30
        let report = MicroNutrition.report(
            entries: entries,
            profiles: micros.profiles,
            isMale: profile?.sex != .female,
            age: age
        )
        return AnalizMicroState(
            findings: report?.findings ?? [],
            hasProfiles: !micros.profiles.isEmpty,
            isRunning: micros.isRunning,
            progress: micros.progress,
            lastError: micros.lastError,
            missing: micros.missingNames(from: entries).count,
            cycleText: micros.cycleText
        )
    }

    private func refreshMicros() {
        let entries = microEntries
        Task { await micros.refresh(entries: entries) }
    }
}
