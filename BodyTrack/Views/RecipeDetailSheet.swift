import SwiftUI
import SwiftData

/// V1 tarif detayı — plan şeridi + makro satırı + malzeme/yapılış iki kolonda,
/// altta "Bugüne logla" (tarifi bugünün öğünlerine FoodEntry olarak ekler).
struct RecipeDetailSheet: View {
    let recipe: Recipe
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Kategori + aksiyonlar
            HStack(spacing: 8) {
                Circle().fill(recipe.category.displayTint).frame(width: 5, height: 5)
                Text(recipe.category.label).eyebrow()
                Spacer()
                Button {
                    recipe.isFavorite.toggle()
                    ctx.saveOrReport()
                } label: {
                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(recipe.isFavorite ? Palette.warning : Palette.textTertiary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(recipe.isFavorite ? "Favoriden çıkar" : "Favoriye ekle")
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .help("Kapat")
            }

            // Başlık + kcal/makro
            HStack(alignment: .top, spacing: 32) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.title)
                        .font(.system(size: 21, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(Palette.textPrimary)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                    if let summary = cleanText(recipe.summary) {
                        Text(summary)
                            .font(.system(size: 12.5, weight: .regular))
                            .foregroundStyle(Palette.textTertiary)
                            .lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 0) {
                    if let kcal = recipe.calories {
                        Text(Fmt.int(kcal))
                            .font(.system(size: 36, weight: .bold))
                            .monospacedDigit()
                            .tracking(-0.5)
                            .foregroundStyle(Palette.textPrimary)
                        Text("kcal / porsiyon")
                            .font(.system(size: 10.5, weight: .regular))
                            .foregroundStyle(Palette.textQuaternary)
                    }
                    RecipeMacroDots(recipe: recipe, fontSize: 12)
                        .padding(.top, 10)
                }
                .fixedSize()
            }
            .padding(.top, 12)

            // Plan meta satırı
            Hairline().padding(.top, 14)
            HStack(spacing: 0) {
                Text(metaLine)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.textSecondary)
                if let host = recipe.sourceHost, let url = recipe.url {
                    Text(" · ")
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                    Button {
                        openURL(url)
                    } label: {
                        HStack(spacing: 3) {
                            Text(host)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 8, weight: .semibold))
                        }
                        .foregroundStyle(Palette.textPrimary)
                    }
                    .buttonStyle(.plain)
                    .help("Kaynağı aç")
                }
                Spacer(minLength: 0)
            }
            .padding(.top, 12)

            // Malzemeler + Yapılış — popup içeriğe sarılır, sabit boşluk yok
            if recipe.hasDetail {
                HStack(alignment: .top, spacing: 36) {
                    ingredientsColumn
                        .frame(width: 300, alignment: .topLeading)
                    stepsColumn
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .padding(.top, 20)
            } else {
                Text("Bu tarif eski link formatında kayıtlı. AI ile yeniden ekletirsen malzeme, yapılış ve makrolar da burada görünür.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
            }

            // Footer
            Hairline().padding(.top, 22)
            HStack(spacing: 12) {
                Button {
                    logToToday()
                } label: {
                    Text("Bugüne logla")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.btnFg)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 7)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(recipe.calories == nil ? Palette.accent.opacity(0.35) : Palette.accent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(recipe.calories == nil)
                .help(recipe.calories == nil ? "Kalori bilgisi olmadan loglanamaz" : "Bu tarifi bugünün öğünlerine ekle")
                Spacer()
                Text("eklendi \(Fmt.dateLong.string(from: recipe.createdAt))")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(Palette.textQuaternary)
            }
            .padding(.top, 16)
        }
        .padding(.horizontal, 36)
        .padding(.top, 28)
        .padding(.bottom, 24)
        .frame(width: 780)
        .background(Palette.background)
    }

    // MARK: - Kolonlar

    private var ingredientsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Malzemeler").eyebrow()
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(recipe.ingredientLines.enumerated()), id: \.offset) { _, line in
                    let parts = Self.splitIngredient(line)
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text(parts.name)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(Palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let qty = parts.qty {
                            Text(qty)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundStyle(Palette.textQuaternary)
                                .fixedSize()
                        }
                    }
                }
            }
        }
    }

    private var stepsColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Yapılış").eyebrow()
            VStack(alignment: .leading, spacing: 11) {
                ForEach(Array(recipe.instructionLines.enumerated()), id: \.offset) { idx, step in
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(idx + 1)")
                            .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(Palette.accent)
                            .frame(width: 15, alignment: .leading)
                        Text(step)
                            .font(.system(size: 13.5, weight: .regular))
                            .foregroundStyle(Palette.textSecondary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Derived

    private var metaLine: String {
        var parts: [String] = []
        if let s = recipe.servings { parts.append("\(s) porsiyon") }
        if let m = recipe.prepMinutes { parts.append("\(m) dk") }
        let ing = recipe.ingredientLines.count
        if ing > 0 { parts.append("\(ing) malzeme") }
        let steps = recipe.instructionLines.count
        if steps > 0 { parts.append("\(steps) adım") }
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

    var searchCorpus: String {
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

extension RecipeCategory {
    var displayTint: Color {
        switch self {
        case .breakfast: return Palette.warning
        case .dinner: return Palette.accent
        case .dessert: return Color(red: 0.90, green: 0.62, blue: 0.78)
        }
    }
}
