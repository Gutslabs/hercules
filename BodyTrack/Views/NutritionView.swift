import SwiftUI
import SwiftData

// MARK: - Ana View

struct NutritionView: View {
    @Query(sort: \FoodEntry.date, order: .reverse) private var allEntries: [FoodEntry]
    @State private var selectedRange: NutritionRange = .today

    private var entries: [FoodEntry] {
        let calendar = Calendar.current
        let now = Date()
        switch selectedRange {
        case .today:
            return allEntries.filter { calendar.isDateInToday($0.date) }
        case .week:
            let weekAgo = calendar.date(byAdding: .day, value: -7, to: now)!
            return allEntries.filter { $0.date >= weekAgo }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Başlık + range seçici
                HStack {
                    Text("Besinler")
                        .font(.title2).bold()
                    Spacer()
                    Picker("", selection: $selectedRange) {
                        ForEach(NutritionRange.allCases) { r in
                            Text(r.label).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                .padding(.horizontal)

                if entries.isEmpty {
                    emptyState
                } else {
                    // Günlük vitaminler
                    NutritionSection(
                        title: "Günlük Vitaminler",
                        subtitle: "Suda çözünür — her gün tüketilmeli",
                        items: dailyItems(from: entries)
                    )

                    // Haftalık vitaminler & mineraller
                    NutritionSection(
                        title: selectedRange == .today ? "Haftalık Vitaminler & Mineraller" : "Bu Hafta",
                        subtitle: "Yağda çözünür — haftalık ortalama önemli",
                        items: weeklyItems(from: entries)
                    )
                }
            }
            .padding(.vertical)
        }
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "pill.circle")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Henüz yemek kaydı yok")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("AI ile yemek ekledikçe vitamin ve mineral değerlerin burada görünecek.")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - Veri hesaplama

    private func dailyItems(from entries: [FoodEntry]) -> [NutritionItem] {
        let c  = entries.compactMap(\.vitaminC_mg).reduce(0, +)
        let b1 = entries.compactMap(\.vitaminB1_mg).reduce(0, +)
        let b6 = entries.compactMap(\.vitaminB6_mg).reduce(0, +)
        let k  = entries.compactMap(\.potassium_mg).reduce(0, +)
        let mg = entries.compactMap(\.magnesium_mg).reduce(0, +)

        return [
            NutritionItem(name: "C Vitamini",  value: c,  unit: "mg",  hasData: entries.contains { $0.vitaminC_mg != nil }),
            NutritionItem(name: "B1 (Tiamin)", value: b1, unit: "mg",  hasData: entries.contains { $0.vitaminB1_mg != nil }),
            NutritionItem(name: "B6 Vitamini", value: b6, unit: "mg",  hasData: entries.contains { $0.vitaminB6_mg != nil }),
            NutritionItem(name: "Potasyum",    value: k,  unit: "mg",  hasData: entries.contains { $0.potassium_mg != nil }),
            NutritionItem(name: "Magnezyum",   value: mg, unit: "mg",  hasData: entries.contains { $0.magnesium_mg != nil }),
        ]
    }

    private func weeklyItems(from entries: [FoodEntry]) -> [NutritionItem] {
        let a   = entries.compactMap(\.vitaminA_ug).reduce(0, +)
        let d   = entries.compactMap(\.vitaminD_ug).reduce(0, +)
        let e   = entries.compactMap(\.vitaminE_mg).reduce(0, +)
        let k   = entries.compactMap(\.vitaminK_ug).reduce(0, +)
        let b12 = entries.compactMap(\.vitaminB12_ug).reduce(0, +)
        let fol = entries.compactMap(\.folate_ug).reduce(0, +)
        let fe  = entries.compactMap(\.iron_mg).reduce(0, +)
        let zn  = entries.compactMap(\.zinc_mg).reduce(0, +)
        let ca  = entries.compactMap(\.calcium_mg).reduce(0, +)
        let om  = entries.compactMap(\.omega3_g).reduce(0, +)

        return [
            NutritionItem(name: "A Vitamini",  value: a,   unit: "µg", hasData: entries.contains { $0.vitaminA_ug != nil }),
            NutritionItem(name: "D Vitamini",  value: d,   unit: "µg", hasData: entries.contains { $0.vitaminD_ug != nil }),
            NutritionItem(name: "E Vitamini",  value: e,   unit: "mg", hasData: entries.contains { $0.vitaminE_mg != nil }),
            NutritionItem(name: "K Vitamini",  value: k,   unit: "µg", hasData: entries.contains { $0.vitaminK_ug != nil }),
            NutritionItem(name: "B12",         value: b12, unit: "µg", hasData: entries.contains { $0.vitaminB12_ug != nil }),
            NutritionItem(name: "Folat (B9)",  value: fol, unit: "µg", hasData: entries.contains { $0.folate_ug != nil }),
            NutritionItem(name: "Demir",       value: fe,  unit: "mg", hasData: entries.contains { $0.iron_mg != nil }),
            NutritionItem(name: "Çinko",       value: zn,  unit: "mg", hasData: entries.contains { $0.zinc_mg != nil }),
            NutritionItem(name: "Kalsiyum",    value: ca,  unit: "mg", hasData: entries.contains { $0.calcium_mg != nil }),
            NutritionItem(name: "Omega-3",     value: om,  unit: "g",  hasData: entries.contains { $0.omega3_g != nil }),
        ]
    }
}

// MARK: - Range enum

enum NutritionRange: String, CaseIterable, Identifiable {
    case today, week
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: return "Bugün"
        case .week:  return "Bu Hafta"
        }
    }
}

// MARK: - Section

struct NutritionSection: View {
    let title: String
    let subtitle: String
    let items: [NutritionItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)

            VStack(spacing: 1) {
                ForEach(items) { item in
                    NutritionRow(item: item)
                }
            }
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.horizontal)
        }
    }
}

// MARK: - Row

struct NutritionRow: View {
    let item: NutritionItem

    var body: some View {
        HStack {
            Text(item.name)
                .font(.subheadline)
            Spacer()
            if item.hasData {
                Text(item.formattedValue)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(item.value > 0 ? .primary : .secondary)
            } else {
                Text("—")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(NSColor.controlBackgroundColor))
    }
}

// MARK: - Model

struct NutritionItem: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let unit: String
    let hasData: Bool

    var formattedValue: String {
        if unit == "g" {
            return String(format: "%.1f g", value)
        } else if unit == "µg" {
            return String(format: "%.1f µg", value)
        } else {
            return String(format: "%.1f mg", value)
        }
    }
}
