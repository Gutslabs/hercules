import SwiftUI
import SwiftData

struct RecipeDetailSheet: View {
    let recipe: Recipe
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        ZStack {
            Palette.background
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    detailHero

                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: Spacing.xl) {
                            leftRail
                                .frame(width: 255)
                            contentColumn
                        }

                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            leftRail
                            contentColumn
                        }
                    }
                }
                .padding(Spacing.xxl)
            }
        }
        .frame(width: 920, height: 760)
    }

    private var detailHero: some View {
        HStack(alignment: .top, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: recipe.category.icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(recipe.category.label)
                        .font(Typography.captionBold)
                    Text(recipe.hasDetail ? "Detaylı" : "Link")
                        .font(Typography.captionBold)
                        .foregroundStyle(recipe.hasDetail ? Palette.positive : Palette.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule(style: .continuous).fill(Color.white.opacity(0.055)))
                }
                .foregroundStyle(categoryTint)

                Text(recipe.title)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(clean(recipe.summary) ?? "Tarif detayları kayda geçince malzeme, yapılış ve makrolar burada düzenli okunur.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(4)
                    .lineLimit(3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .trailing, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Button {
                        recipe.isFavorite.toggle()
                        ctx.saveOrReport()
                    } label: {
                        Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                            .font(.system(size: 12, weight: .semibold))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(recipe.isFavorite ? Palette.warning.opacity(0.16) : Palette.surfaceElevated))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(recipe.isFavorite ? Palette.warning : Palette.textSecondary)
                    .help(recipe.isFavorite ? "Favoriden çıkar" : "Favoriye ekle")

                    if let url = recipe.url {
                        Button {
                            openURL(url)
                        } label: {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(Palette.surfaceElevated))
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Palette.textSecondary)
                        .help("Kaynağı aç")
                    }

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Palette.surfaceElevated))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.textSecondary)
                    .help("Kapat")
                }

                if let calories = recipe.calories {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Fmt.int(calories))
                            .font(.system(size: 34, weight: .light, design: .monospaced))
                            .foregroundStyle(Palette.textPrimary)
                        Text("kcal / porsiyon")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            }
        }
        .padding(Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.86))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.7)
        )
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(Color.white.opacity(0.035), lineWidth: 1)
                .blendMode(.plusLighter)
        }
        .overlay(alignment: .topLeading) {
            Capsule(style: .continuous)
                .fill(categoryTint)
                .frame(width: 116, height: 2)
                .padding(.leading, Spacing.xl)
        }
    }

    private var leftRail: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                sectionHeader("Plan", icon: "square.grid.2x2")
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    railStat(label: "Porsiyon", value: recipe.servings.map { "\($0)" } ?? "-")
                    railStat(label: "Hazırlık", value: recipe.prepMinutes.map { "\($0) dk" } ?? "-")
                    railStat(label: "Malzeme", value: ingredientLines.isEmpty ? "-" : "\(ingredientLines.count)")
                    railStat(label: "Adım", value: instructionLines.isEmpty ? "-" : "\(instructionLines.count)")
                    railStat(label: "Eklendi", value: Fmt.dateLong.string(from: recipe.createdAt))
                }
            }
            .padding(Spacing.lg)
            .background(railBackground)

            VStack(alignment: .leading, spacing: Spacing.md) {
                sectionHeader("Makro", icon: "chart.pie")
                if macroMetrics.isEmpty {
                    Text("Makro eklenmemiş")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                } else {
                    VStack(spacing: Spacing.sm) {
                        ForEach(macroMetrics, id: \.label) { metric in
                            metricTile(metric)
                        }
                    }
                }
            }
            .padding(Spacing.lg)
            .background(railBackground)

            if let host = recipe.sourceHost {
                VStack(alignment: .leading, spacing: 8) {
                    sectionHeader("Kaynak", icon: "link")
                    Text(host)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                    if let url = recipe.url {
                        Button {
                            openURL(url)
                        } label: {
                            HStack(spacing: 6) {
                                Text("Kaynağı aç")
                                    .font(Typography.captionBold)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 9, weight: .semibold))
                            }
                            .foregroundStyle(Palette.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(railBackground)
            }
        }
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            if let summary = clean(recipe.summary) {
                summaryPanel(summary)
            }
            if !ingredientLines.isEmpty {
                ingredientPanel
            }
            if !instructionLines.isEmpty {
                instructionPanel
            }
            if !recipe.hasDetail {
                emptyDetailPanel
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var railBackground: some View {
        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(Palette.surface.opacity(0.78))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.6)
            )
    }

    private func railStat(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
            Spacer()
            Text(value)
                .font(Typography.captionBold)
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.border)
                .frame(height: 0.6)
        }
    }

    private func metricTile(_ metric: RecipeMetric) -> some View {
        HStack(spacing: Spacing.md) {
            Text(metric.label.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Palette.textQuaternary)
            Spacer()
            Text(metric.value)
                .font(Typography.mono)
                .foregroundStyle(metric.tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
    }

    private func summaryPanel(_ summary: String) -> some View {
        detailPanel("Özet", icon: "text.alignleft") {
            Text(summary)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var ingredientPanel: some View {
        let columns = ingredientColumns
        return detailPanel("Malzemeler", icon: "list.bullet") {
            HStack(alignment: .top, spacing: Spacing.xl) {
                ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(Array(column.enumerated()), id: \.offset) { _, line in
                            ingredientRow(line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private func ingredientRow(_ line: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle()
                .fill(categoryTint)
                .frame(width: 5, height: 5)
                .padding(.top, 7)
            Text(line)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Malzemeleri 2 dengeli kolona böl (≤3 madde tek kolon). Her kolon bağımsız aktığı için
    /// LazyVGrid'in değişken satır yüksekliğinden gelen kayık hizayı (staggered) önler.
    private var ingredientColumns: [[String]] {
        let items = ingredientLines
        guard items.count > 3 else { return [items] }
        let perColumn = Int((Double(items.count) / 2).rounded(.up))
        return stride(from: 0, to: items.count, by: perColumn).map {
            Array(items[$0..<min($0 + perColumn, items.count)])
        }
    }

    private var instructionPanel: some View {
        detailPanel("Yapılış", icon: "flame") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(instructionLines.enumerated()), id: \.offset) { idx, line in
                    HStack(alignment: .top, spacing: Spacing.md) {
                        Text("\(idx + 1)")
                            .font(Typography.captionBold)
                            .foregroundStyle(Palette.background)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(categoryTint))
                        Text(line)
                            .font(Typography.body)
                            .foregroundStyle(Palette.textPrimary)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var emptyDetailPanel: some View {
        detailPanel("Detay", icon: "doc.text") {
            Text("Bu tarif eski link formatında kayıtlı. AI ile yeniden ekletirsen malzeme, yapılış ve makrolar da burada görünür.")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func detailPanel<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader(title, icon: icon)
            content()
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surface.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(categoryTint)
            Text(title.uppercased())
                .font(Typography.captionBold)
                .tracking(0.8)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var macroMetrics: [RecipeMetric] {
        [
            recipe.calories.map { RecipeMetric(label: "Kalori", value: "\(Fmt.int($0))", tint: Palette.textPrimary) },
            recipe.protein.map { RecipeMetric(label: "Protein", value: "\(Fmt.int($0))g", tint: Palette.macroProtein) },
            recipe.carbs.map { RecipeMetric(label: "Karb", value: "\(Fmt.int($0))g", tint: Palette.macroCarbs) },
            recipe.fat.map { RecipeMetric(label: "Yağ", value: "\(Fmt.int($0))g", tint: Palette.macroFat) },
        ].compactMap { $0 }
    }

    private var ingredientLines: [String] {
        cleanLines(recipe.ingredientsText)
    }

    private var instructionLines: [String] {
        cleanLines(recipe.instructionsText)
    }

    private var categoryTint: Color {
        switch recipe.category {
        case .breakfast: return Palette.warning
        case .dinner: return Palette.accent
        case .dessert: return Color(red: 0.90, green: 0.62, blue: 0.78)
        }
    }

    private func clean(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func cleanLines(_ value: String?) -> [String] {
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

struct RecipeMetric {
    let label: String
    let value: String
    let tint: Color
}

struct RecipeFavoriteButton: View {
    @Environment(\.modelContext) private var ctx
    let recipe: Recipe
    var size: CGFloat = 28
    var iconSize: CGFloat = 11

    var body: some View {
        Button {
            recipe.isFavorite.toggle()
            ctx.saveOrReport()
        } label: {
            Image(systemName: recipe.isFavorite ? "heart.fill" : "heart")
                .font(.system(size: iconSize, weight: .semibold))
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .foregroundStyle(recipe.isFavorite ? Palette.warning : Palette.textSecondary)
        .background(
            Circle()
                .fill(recipe.isFavorite ? Palette.warning.opacity(0.16) : Palette.surfaceElevated)
        )
        .help(recipe.isFavorite ? "Favoriden çıkar" : "Favoriye ekle")
    }
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
