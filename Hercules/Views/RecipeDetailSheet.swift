import SwiftUI
import LucideKit
import SwiftData

/// Tarif penceresi — tasarım: tuval ▸ Pencereler · Beslenme (az yazı). Başlıkta ad + kategori/süre/
/// porsiyon, sağda favori kalbi; kalori + makro çubuğu, kısa özet, malzeme/yapılış iki kolonda;
/// altta kaynak linki ve "Bugüne logla" (tarifi bugünün öğünlerine FoodEntry olarak ekler).
struct RecipeDetailSheet: View {
    let recipe: Recipe
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        SadeSheet(title: recipe.title, subtitle: metaLine, onClose: { dismiss() }, accessory: AnyView(favoriteButton)) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 30) {
                    if let kcal = recipe.calories {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(Fmt.int(kcal))
                                .font(.system(size: 38, weight: .semibold).monospacedDigit())
                                .tracking(-0.5)
                                .foregroundStyle(Palette.textPrimary)
                            Text("kcal")
                                .font(.system(size: 13))
                                .foregroundStyle(Palette.textTertiary)
                        }
                        .fixedSize()
                    }
                    if recipe.protein != nil || recipe.carbs != nil || recipe.fat != nil {
                        VStack(alignment: .leading, spacing: 10) {
                            SadeMacroBar(protein: recipe.protein, carbs: recipe.carbs, fat: recipe.fat)
                            SadeMacroLegend(protein: recipe.protein, carbs: recipe.carbs, fat: recipe.fat)
                        }
                    } else if recipe.calories == nil {
                        Text("Makro yok")
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .padding(.top, 18)

                if let summary = cleanText(recipe.summary) {
                    Text(summary)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textSecondary)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 14)
                }
            }
            .padding(.horizontal, 28)

            SadeRule()
                .padding(.top, 18)

            if recipe.hasDetail {
                ScrollView {
                    HStack(alignment: .top, spacing: 36) {
                        ingredientsColumn
                            .frame(width: 280, alignment: .topLeading)
                        stepsColumn
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 24)
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                Text("Eski link kaydı — malzeme ve yapılış yok")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 22)
            }
        } footerLeading: {
            if let host = recipe.sourceHost, let url = recipe.url {
                Button { openURL(url) } label: {
                    HStack(spacing: 4) {
                        Text(host)
                            .font(.system(size: 13))
                        Lucide(sf: "arrow.up.right", size: 11)
                    }
                    .foregroundStyle(Palette.textSecondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Kaynağı aç")
            }
        } footerTrailing: {
            SadeButton(title: "Bugüne logla", icon: "plus", role: .primary, enabled: recipe.calories != nil, bindsKey: false) {
                logToToday()
            }
            .help(recipe.calories == nil ? "Kalori bilgisi olmadan loglanamaz" : "Bu tarifi bugünün öğünlerine ekle")
        }
        .frame(width: 840, height: recipe.hasDetail ? 600 : nil)
    }

    private var favoriteButton: some View {
        Button {
            recipe.isFavorite.toggle()
            ctx.saveOrReport()
        } label: {
            Lucide(sf: recipe.isFavorite ? "heart.fill" : "heart", size: 13)
                .foregroundStyle(recipe.isFavorite ? Palette.negative : Palette.textSecondary)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.textPrimary.opacity(0.05)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(recipe.isFavorite ? "Favoriden çıkar" : "Favoriye ekle")
    }

    // MARK: - Kolonlar

    private var ingredientsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnTitle("Malzemeler")
            ForEach(Array(recipe.ingredientLines.enumerated()), id: \.offset) { _, line in
                let parts = Self.splitIngredient(line)
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(parts.name)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let qty = parts.qty {
                        Text(qty)
                            .font(.system(size: 13).monospacedDigit())
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize()
                    }
                }
                .padding(.vertical, 10)
                .overlay(alignment: .top) { SadeRule().opacity(0.8) }
            }
        }
    }

    private var stepsColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            columnTitle("Yapılış")
            ForEach(Array(recipe.instructionLines.enumerated()), id: \.offset) { idx, step in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(idx + 1)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 22, height: 22)
                        .overlay(Circle().strokeBorder(Palette.textPrimary.opacity(0.16), lineWidth: 1.5))
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 4 }
                    Text(step)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.textSecondary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
            }
        }
    }

    private func columnTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Palette.textSecondary)
            .padding(.bottom, 8)
    }

    // MARK: - Derived

    /// "Akşam · 35 dk · 2 porsiyon"
    private var metaLine: String {
        var parts = [recipe.category == .dinner ? "Akşam" : recipe.category.label]
        if let m = recipe.prepMinutes { parts.append("\(m) dk") }
        if let s = recipe.servings { parts.append("\(s) porsiyon") }
        return parts.joined(separator: " · ")
    }

    /// "250g süzme yoğurt" → (name: "süzme yoğurt", qty: "250g").
    /// Baş kısımda miktar+birim deseni yoksa satır olduğu gibi isim olur.
    static func splitIngredient(_ line: String) -> (name: String, qty: String?) {
        let pattern = #"^([0-9][0-9.,xX\-–/ ]*(?:g|gr|kg|ml|lt|l|cl|adet|ölçek|tk|yk|sk|dilim|porsiyon|tutam|kaşık|bardak|ölçü)\.?)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let qtyRange = Range(match.range(at: 1), in: line),
              let nameRange = Range(match.range(at: 2), in: line)
        else { return (line, nil) }
        return (
            String(line[nameRange]).trimmingCharacters(in: .whitespaces),
            String(line[qtyRange]).trimmingCharacters(in: .whitespaces)
        )
    }

    private func cleanText(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    /// Tarifi bugünün öğünlerine FoodEntry olarak ekler ve kapanır —
    /// Genel Bakış'taki ring/makrolar anında güncellenir.
    private func logToToday() {
        guard let kcal = recipe.calories else { return }
        let entry = FoodEntry(
            date: .now,
            name: recipe.title,
            calories: kcal,
            protein: recipe.protein,
            carbs: recipe.carbs,
            fat: recipe.fat
        )
        ctx.insert(entry)
        ctx.saveOrReport()
        dismiss()
    }
}

struct RecipeMetric {
    let label: String
    let value: String
    let tint: Color
}

extension Recipe {
    var displaySummary: String {
        let summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !summary.isEmpty { return summary }
        if let sourceHost { return sourceHost }
        return hasDetail ? "Tarif metni kayıtlı" : "Detay eklenmemiş"
    }

    var sourceHost: String? {
        guard let host = url?.host else { return nil }
        return host.replacingOccurrences(of: "www.", with: "")
    }

    /// Aranabilir metin — normalize edilmiş hâli önbellekte. Computed olarak her
    /// tuş vuruşunda HER tarifin tam malzeme+tarif gövdesini birleştirip fold
    /// ediyordu; yazma gecikmesi defter büyüdükçe artıyordu. Önbellek `updatedAt`
    /// ile anahtarlanır, düzenleme sonrası kendini yeniler.
    var searchCorpus: String {
        RecipeSearchCorpusCache.shared.corpus(for: self)
    }

    fileprivate var rawSearchCorpus: String {
        [
            title,
            category.label,
            summary,
            ingredientsText,
            instructionsText,
            sourceHost,
            urlString
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
        .lowercased(with: Locale(identifier: "tr_TR"))
    }

    var recipeMetrics: [RecipeMetric] {
        [
            calories.map { RecipeMetric(label: "Kalori", value: "\(Fmt.int($0))", tint: Palette.textPrimary) },
            protein.map { RecipeMetric(label: "Protein", value: "\(Fmt.int($0))g", tint: Palette.macroProtein) },
            carbs.map { RecipeMetric(label: "Karb", value: "\(Fmt.int($0))g", tint: Palette.macroCarbs) },
            fat.map { RecipeMetric(label: "Yağ", value: "\(Fmt.int($0))g", tint: Palette.macroFat) },
        ].compactMap { $0 }
    }

    var ingredientLines: [String] {
        cleanRecipeLines(ingredientsText)
    }

    var instructionLines: [String] {
        cleanRecipeLines(instructionsText)
    }

    private func cleanRecipeLines(_ value: String?) -> [String] {
        (value ?? "")
            .split(whereSeparator: \.isNewline)
            .map { line in
                String(line)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: #"^[-*•]\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^\d+[\.)]\s*"#, with: "", options: .regularExpression)
            }
            .filter { !$0.isEmpty }
    }
}

/// Tarif arama metni önbelleği — `(kayıt, updatedAt)` ile anahtarlı.
/// Tuş başına tüm defterin yeniden fold edilmesini engeller.
private final class RecipeSearchCorpusCache: @unchecked Sendable {
    static let shared = RecipeSearchCorpusCache()

    private let lock = NSLock()
    private var values: [PersistentIdentifier: (stamp: Date, corpus: String)] = [:]

    func corpus(for recipe: Recipe) -> String {
        let id = recipe.persistentModelID
        let stamp = recipe.updatedAt
        lock.lock()
        if let hit = values[id], hit.stamp == stamp {
            lock.unlock()
            return hit.corpus
        }
        lock.unlock()
        let made = recipe.rawSearchCorpus
        lock.lock()
        if values.count > 2_048 { values.removeAll(keepingCapacity: true) }
        values[id] = (stamp, made)
        lock.unlock()
        return made
    }
}

extension RecipeCategory {
    var displayTint: Color {
        switch self {
        case .breakfast: return Palette.warning
        case .dinner: return Palette.accent
        case .dessert: return Color(red: 0.90, green: 0.62, blue: 0.78)
        }
    }
}
