import SwiftUI
import SwiftData

struct RecipesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]

    @State private var selectedCategory: RecipeCategory? = nil
    @State private var showingNew = false
    @State private var editing: Recipe? = nil
    @State private var viewing: Recipe? = nil

    private var filtered: [Recipe] {
        guard let c = selectedCategory else { return recipes }
        return recipes.filter { $0.category == c }
    }

    private var averageProtein: Double? {
        let values = recipes.compactMap(\.protein)
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private var detailedRecipeCount: Int {
        recipes.filter(\.hasDetail).count
    }

    private var sourceRecipeCount: Int {
        recipes.filter { $0.url != nil }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                header
                summaryStrip
                categoryPicker
                content
                Spacer(minLength: 24)
            }
            .padding(Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.background.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingNew = true } label: {
                    Label("Yeni Tarif", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Yeni tarif ekle (⌘N)")
            }
        }
        .sheet(isPresented: $showingNew) {
            RecipeEditor(mode: .create) { r in
                ctx.insert(r)
                try? ctx.save()
            }
        }
        .sheet(item: $editing) { r in
            RecipeEditor(mode: .edit(r)) { _ in
                try? ctx.save()
            } onDelete: {
                ctx.delete(r)
                try? ctx.save()
            }
        }
        .sheet(item: $viewing) { r in
            RecipeDetailSheet(recipe: r)
        }
        .onAppear(perform: mergeDuplicateRecipes)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: Spacing.xl) {
            VStack(alignment: .leading, spacing: 7) {
                Text("Yemekler").eyebrow()
                Text("Tarifler")
                    .font(Typography.display(40))
                    .foregroundStyle(Palette.textPrimary)
                Text("AI'ın eklediği tarifleri detay, makro ve kaynak bilgisiyle sakla.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textTertiary)
            }

            Spacer()

            Button {
                showingNew = true
            } label: {
                Label("Yeni Tarif", systemImage: "plus")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.background)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(Palette.textPrimary)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("n", modifiers: .command)
            .help("Yeni tarif ekle (⌘N)")
        }
    }

    private var summaryStrip: some View {
        HStack(spacing: 0) {
            recipeStat("Toplam", value: "\(recipes.count)", detail: "kayıtlı tarif", icon: "book.closed")
            stripDivider
            recipeStat("Detaylı", value: "\(detailedRecipeCount)", detail: "malzeme + yapılış", icon: "doc.text")
            stripDivider
            recipeStat(
                "Ort. Protein",
                value: averageProtein.map { "\(Fmt.int($0))g" } ?? "-",
                detail: "makrolu tariflerde",
                icon: "bolt"
            )
            stripDivider
            recipeStat("Kaynaklı", value: "\(sourceRecipeCount)", detail: "link kayıtlı", icon: "link")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var stripDivider: some View {
        Rectangle()
            .fill(Palette.border)
            .frame(width: 1)
            .padding(.vertical, 4)
    }

    private func recipeStat(_ label: String, value: String, detail: String, icon: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.accentSoft)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(Typography.label)
                    .tracking(0.7)
                    .foregroundStyle(Palette.textQuaternary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(value)
                        .font(Typography.monoLarge)
                        .foregroundStyle(Palette.textPrimary)
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Spacing.md)
    }

    private var categoryPicker: some View {
        HStack(spacing: Spacing.sm) {
            categoryTab(
                "Tümü",
                count: recipes.count,
                icon: "square.grid.2x2",
                tint: Palette.textPrimary,
                isSelected: selectedCategory == nil
            ) { selectedCategory = nil }
            ForEach(RecipeCategory.allCases) { c in
                categoryTab(
                    c.label,
                    count: recipes.filter { $0.category == c }.count,
                    icon: c.icon,
                    tint: tint(for: c),
                    isSelected: selectedCategory == c
                ) { selectedCategory = c }
            }
            Spacer()
            Text("\(filtered.count) tarif")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func categoryTab(
        _ title: String,
        count: Int,
        icon: String,
        tint: Color,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isSelected ? tint : Palette.textTertiary)
                Text(title)
                    .font(Typography.bodyBold)
                Text("\(count)")
                    .font(Typography.micro)
                    .foregroundStyle(isSelected ? Palette.textSecondary : Palette.textQuaternary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Capsule(style: .continuous).fill(Color.white.opacity(isSelected ? 0.08 : 0.035)))
            }
            .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                    .fill(isSelected ? Color.white.opacity(0.075) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if filtered.isEmpty {
            EmptyRecipesState { showingNew = true }
        } else {
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: Spacing.lg),
                    count: 3
                ),
                alignment: .leading,
                spacing: Spacing.lg
            ) {
                ForEach(filtered) { r in
                    RecipeLibraryCard(recipe: r, onOpen: { viewing = r }) { editing = r }
                }
            }
        }
    }

    private func tint(for category: RecipeCategory) -> Color {
        switch category {
        case .breakfast: return Palette.warning
        case .dinner: return Palette.accent
        case .dessert: return Color(red: 0.90, green: 0.62, blue: 0.78)
        }
    }

    private func mergeDuplicateRecipes() {
        var keepers: [String: Recipe] = [:]
        var didChange = false

        for recipe in recipes.sorted(by: { $0.createdAt > $1.createdAt }) {
            let key = duplicateKey(for: recipe)
            if let keeper = keepers[key] {
                merge(recipe, into: keeper)
                ctx.delete(recipe)
                didChange = true
            } else {
                keepers[key] = recipe
            }
        }

        if didChange {
            try? ctx.save()
        }
    }

    private func duplicateKey(for recipe: Recipe) -> String {
        "\(recipe.category.rawValue)|\(normalizedRecipeTitle(recipe.title))"
    }

    private func normalizedRecipeTitle(_ title: String) -> String {
        title
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private func merge(_ duplicate: Recipe, into keeper: Recipe) {
        fillString(&keeper.urlString, with: duplicate.urlString)
        fillOptionalString(&keeper.summary, with: duplicate.summary)
        fillOptionalString(&keeper.ingredientsText, with: duplicate.ingredientsText)
        fillOptionalString(&keeper.instructionsText, with: duplicate.instructionsText)
        keeper.servings = keeper.servings ?? duplicate.servings
        keeper.prepMinutes = keeper.prepMinutes ?? duplicate.prepMinutes
        keeper.calories = keeper.calories ?? duplicate.calories
        keeper.protein = keeper.protein ?? duplicate.protein
        keeper.carbs = keeper.carbs ?? duplicate.carbs
        keeper.fat = keeper.fat ?? duplicate.fat
    }

    private func fillString(_ target: inout String, with source: String) {
        guard target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            target = trimmed
        }
    }

    private func fillOptionalString(_ target: inout String?, with source: String?) {
        guard target?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true else { return }
        let trimmed = source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            target = trimmed
        }
    }
}

struct RecipeSpotlightCard: View {
    let recipe: Recipe
    var onOpen: () -> Void
    var onEdit: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top, spacing: Spacing.md) {
                recipeBadge(prominent: true)
                Spacer()
                cardActions
            }

            HStack(alignment: .top, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    Text(recipe.title)
                        .font(Typography.hero(28))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                    Text(subtitleText)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                        .lineSpacing(3)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let calories = recipe.calories {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(Fmt.int(calories))
                            .font(Typography.display(34))
                            .foregroundStyle(Palette.textPrimary)
                        Text("kcal")
                            .font(Typography.captionBold)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .frame(minWidth: 92, alignment: .trailing)
                }
            }

            Divider().overlay(Palette.border)

            HStack(alignment: .top, spacing: Spacing.md) {
                macroSummary
                Divider().overlay(Palette.border).frame(height: 48)
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: Spacing.sm) {
                        infoChip(icon: "person.2", text: recipe.servings.map { "\($0) porsiyon" } ?? "Porsiyon yok")
                        infoChip(icon: "clock", text: recipe.prepMinutes.map { "\($0) dk" } ?? "Süre yok")
                        infoChip(icon: recipe.hasDetail ? "checkmark.seal" : "doc.text", text: recipe.hasDetail ? "Detaylı" : "Link formatı")
                    }
                    HStack(spacing: Spacing.sm) {
                        infoChip(icon: "list.bullet", text: "\(ingredientCount) malzeme")
                        infoChip(icon: "flame", text: "\(instructionCount) adım")
                        if let host = sourceHost {
                            infoChip(icon: "link", text: host)
                        }
                    }
                }
            }

            HStack(spacing: 7) {
                Text("Tarifi aç")
                    .font(Typography.captionBold)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(Palette.textPrimary)
            .padding(.top, 2)
        }
        .padding(Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(hovering ? Palette.surfaceElevated : Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(hovering ? Palette.borderStrong : Palette.border, lineWidth: 0.7)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onOpen() }
    }

    private var cardActions: some View {
        HStack(spacing: 7) {
            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textSecondary)
            .background(Circle().fill(Palette.surfaceElevated))

            if let url = recipe.url {
                Button {
                    openURL(url)
                } label: {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.textSecondary)
                .background(Circle().fill(Palette.surfaceElevated))
            }
        }
    }

    @ViewBuilder
    private var macroSummary: some View {
        if macroMetrics.isEmpty {
            Text("Makro eklenmemiş")
                .font(Typography.captionBold)
                .foregroundStyle(Palette.textTertiary)
                .frame(minWidth: 260, maxWidth: 320, alignment: .leading)
                .padding(.vertical, 12)
        } else {
            HStack(spacing: Spacing.sm) {
                ForEach(macroMetrics, id: \.label) { metric in
                    metricTile(metric, minWidth: 62)
                }
            }
            .frame(minWidth: 260, maxWidth: 320, alignment: .leading)
        }
    }

    private func recipeBadge(prominent: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: recipe.category.icon)
                .font(.system(size: prominent ? 13 : 11, weight: .semibold))
            Text(recipe.category.label)
                .font(Typography.captionBold)
        }
        .foregroundStyle(categoryTint)
        .padding(.horizontal, prominent ? 11 : 9)
        .padding(.vertical, prominent ? 7 : 6)
        .background(
            Capsule(style: .continuous)
                .fill(categoryTint.opacity(0.14))
        )
    }

    private func metricTile(_ metric: RecipeMetric, minWidth: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.label.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Palette.textQuaternary)
            Text(metric.value)
                .font(Typography.mono)
                .foregroundStyle(metric.tint)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .frame(minWidth: minWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
    }

    private func infoChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(Typography.caption)
                .lineLimit(1)
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
    }

    private var macroMetrics: [RecipeMetric] {
        recipe.recipeMetrics
    }

    private var subtitleText: String {
        recipe.displaySummary
    }

    private var ingredientCount: Int { recipe.ingredientLines.count }
    private var instructionCount: Int { recipe.instructionLines.count }
    private var sourceHost: String? { recipe.sourceHost }
    private var categoryTint: Color { recipe.category.displayTint }
}

struct RecipeLibraryCard: View {
    let recipe: Recipe
    var onOpen: () -> Void
    var onEdit: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(recipe.category.displayTint.opacity(0.14))
                        .frame(width: 42, height: 42)
                    Image(systemName: recipe.category.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(recipe.category.displayTint)
                }

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(recipe.category.label)
                            .font(Typography.micro)
                            .foregroundStyle(recipe.category.displayTint)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Capsule(style: .continuous).fill(recipe.category.displayTint.opacity(0.13)))
                        if recipe.hasDetail {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.positive)
                        }
                    }
                    Text(recipe.title)
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)
                cardActions
            }

            Text(recipe.displaySummary)
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .lineSpacing(2)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            if recipe.recipeMetrics.isEmpty {
                Text("Makro eklenmemiş")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.vertical, 7)
            } else {
                HStack(spacing: Spacing.sm) {
                    ForEach(recipe.recipeMetrics, id: \.label) { metric in
                        compactMetric(metric)
                    }
                }
            }

            HStack(spacing: Spacing.sm) {
                footerChip(icon: "clock", text: recipe.prepMinutes.map { "\($0) dk" } ?? "Süre yok")
                footerChip(icon: "person.2", text: recipe.servings.map { "\($0) porsiyon" } ?? "Porsiyon yok")
                if let host = recipe.sourceHost {
                    footerChip(icon: "link", text: host)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Text("Aç")
                    .font(Typography.captionBold)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundStyle(hovering ? Palette.textPrimary : Palette.textSecondary)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 210, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(hovering ? Palette.surfaceElevated : Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(hovering ? Palette.borderStrong : Palette.border, lineWidth: 0.6)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onOpen() }
    }

    private var cardActions: some View {
        HStack(spacing: 5) {
            iconButton("pencil", action: onEdit)
            if let url = recipe.url {
                iconButton("arrow.up.right") {
                    openURL(url)
                }
            }
        }
        .opacity(hovering ? 1 : 0.72)
    }

    private func iconButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 25, height: 25)
                .background(Circle().fill(Color.white.opacity(0.045)))
        }
        .buttonStyle(.plain)
    }

    private func compactMetric(_ metric: RecipeMetric) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.label.uppercased())
                .font(.system(size: 7.5, weight: .semibold))
                .tracking(0.45)
                .foregroundStyle(Palette.textQuaternary)
            Text(metric.value)
                .font(Typography.mono)
                .foregroundStyle(metric.tint)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
    }

    private func footerChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 8.5, weight: .semibold))
            Text(text)
                .font(Typography.caption)
                .lineLimit(1)
        }
        .foregroundStyle(Palette.textTertiary)
    }
}

struct RecipeDetailSheet: View {
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 0) {
            topBar
            Divider().overlay(Palette.border)
            ScrollView {
                HStack(alignment: .top, spacing: Spacing.xl) {
                    leftRail
                        .frame(width: 210)
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
                .padding(Spacing.xxl)
            }
        }
        .background(Palette.background)
        .frame(width: 820, height: 700)
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(categoryTint.opacity(0.16))
                    .frame(width: 48, height: 48)
                Image(systemName: recipe.category.icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(categoryTint)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(recipe.category.label.uppercased())
                    .font(Typography.label)
                    .tracking(0.8)
                    .foregroundStyle(categoryTint)
                Text(recipe.title)
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
            }

            Spacer()

            if let url = recipe.url {
                Button {
                    openURL(url)
                } label: {
                    Label("Kaynak", systemImage: "arrow.up.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Palette.surfaceElevated))
            }
            .buttonStyle(.plain)
            .help("Kapat")
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.vertical, Spacing.lg)
        .background(Palette.surface.opacity(0.65))
    }

    private var leftRail: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                Text("ÖZET")
                    .font(Typography.label)
                    .tracking(0.8)
                    .foregroundStyle(Palette.textTertiary)
                HStack(spacing: 8) {
                    metaPill(recipe.servings.map { "\($0) porsiyon" } ?? "Porsiyon yok", icon: "person.2")
                    metaPill(recipe.prepMinutes.map { "\($0) dk" } ?? "Süre yok", icon: "clock")
                }
                if macroMetrics.isEmpty {
                    Text("Makro eklenmemiş")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                        ForEach(macroMetrics, id: \.label) { metric in
                            metricTile(metric)
                        }
                    }
                }
            }
            .padding(Spacing.lg)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )

            if let host = recipe.url?.host {
                VStack(alignment: .leading, spacing: 8) {
                    Text("KAYNAK")
                        .font(Typography.label)
                        .tracking(0.8)
                        .foregroundStyle(Palette.textTertiary)
                    Text(host)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
                .padding(Spacing.lg)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
            }
        }
    }

    private func metaPill(_ text: String, icon: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(Typography.captionBold)
                .lineLimit(1)
        }
        .foregroundStyle(Palette.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(Palette.surfaceElevated)
        )
    }

    private func metricTile(_ metric: RecipeMetric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.label.uppercased())
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(Palette.textQuaternary)
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
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Özet", icon: "text.alignleft")
            Text(summary)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .lineSpacing(3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var ingredientPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Malzemeler", icon: "list.bullet")
            VStack(alignment: .leading, spacing: 9) {
                ForEach(Array(ingredientLines.enumerated()), id: \.offset) { _, line in
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
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var instructionPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Yapılış", icon: "flame")
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
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private var emptyDetailPanel: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            sectionHeader("Detay", icon: "doc.text")
            Text("Bu tarif eski link formatında kayıtlı. AI ile yeniden ekletirsen malzeme, yapılış ve makrolar da burada görünür.")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surface)
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

private struct RecipeMetric {
    let label: String
    let value: String
    let tint: Color
}

private extension Recipe {
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

private extension RecipeCategory {
    var displayTint: Color {
        switch self {
        case .breakfast: return Palette.warning
        case .dinner: return Palette.accent
        case .dessert: return Color(red: 0.90, green: 0.62, blue: 0.78)
        }
    }
}

struct EmptyRecipesState: View {
    var action: () -> Void
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "fork.knife")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text("Henüz tarif yok")
                .font(Typography.title)
                .foregroundStyle(Palette.textPrimary)
            PrimaryButton(title: "İlk tarifi ekle", systemImage: "plus", action: action)
                .frame(width: 220)
        }
        .padding(Spacing.xxxl)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }
}

enum RecipeEditorMode {
    case create
    case edit(Recipe)
}

struct RecipeEditor: View {
    let mode: RecipeEditorMode
    var onSave: (Recipe) -> Void
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var urlString: String
    @State private var category: RecipeCategory
    @State private var summary: String
    @State private var ingredientsText: String
    @State private var instructionsText: String
    @State private var servings: Int
    @State private var prepMinutes: Int
    @State private var caloriesText: String
    @State private var proteinText: String
    @State private var carbsText: String
    @State private var fatText: String

    init(mode: RecipeEditorMode, onSave: @escaping (Recipe) -> Void, onDelete: (() -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        switch mode {
        case .create:
            _title = State(initialValue: "")
            _urlString = State(initialValue: "")
            _category = State(initialValue: .dinner)
            _summary = State(initialValue: "")
            _ingredientsText = State(initialValue: "")
            _instructionsText = State(initialValue: "")
            _servings = State(initialValue: 1)
            _prepMinutes = State(initialValue: 15)
            _caloriesText = State(initialValue: "")
            _proteinText = State(initialValue: "")
            _carbsText = State(initialValue: "")
            _fatText = State(initialValue: "")
        case .edit(let r):
            _title = State(initialValue: r.title)
            _urlString = State(initialValue: r.urlString)
            _category = State(initialValue: r.category)
            _summary = State(initialValue: r.summary ?? "")
            _ingredientsText = State(initialValue: r.ingredientsText ?? "")
            _instructionsText = State(initialValue: r.instructionsText ?? "")
            _servings = State(initialValue: r.servings ?? 1)
            _prepMinutes = State(initialValue: r.prepMinutes ?? 15)
            _caloriesText = State(initialValue: Self.numberText(r.calories))
            _proteinText = State(initialValue: Self.numberText(r.protein))
            _carbsText = State(initialValue: Self.numberText(r.carbs))
            _fatText = State(initialValue: Self.numberText(r.fat))
        }
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tarif") {
                    TextField("Başlık", text: $title, prompt: Text("ör: Az kalorili tavuk"))
                    TextField("URL", text: $urlString, prompt: Text("opsiyonel"))
                        .textContentType(.URL)
                    Picker("Kategori", selection: $category) {
                        ForEach(RecipeCategory.allCases) {
                            Text($0.label).tag($0)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("İçerik") {
                    TextField("Kısa özet", text: $summary, prompt: Text("Ucuz, yüksek proteinli, pratik..."), axis: .vertical)
                        .lineLimit(2...4)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Malzemeler")
                            .font(Typography.captionBold)
                            .foregroundStyle(Palette.textSecondary)
                        TextEditor(text: $ingredientsText)
                            .frame(minHeight: 110)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Yapılış")
                            .font(Typography.captionBold)
                            .foregroundStyle(Palette.textSecondary)
                        TextEditor(text: $instructionsText)
                            .frame(minHeight: 140)
                    }
                }

                Section("Porsiyon ve makro") {
                    LabeledContent("Porsiyon") {
                        TextField("", value: $servings, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    LabeledContent("Hazırlık (dk)") {
                        TextField("", value: $prepMinutes, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    macroInput("Kalori", value: $caloriesText, unit: "kcal")
                    macroInput("Protein", value: $proteinText, unit: "g")
                    macroInput("Karbonhidrat", value: $carbsText, unit: "g")
                    macroInput("Yağ", value: $fatText, unit: "g")
                }

                if isEditing, let onDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Tarifi Sil", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Tarifi Düzenle" : "Yeni Tarif")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Kaydet" : "Ekle") {
                        save()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
                }
            }
        }
        .frame(width: 620, height: isEditing ? 760 : 700)
    }

    private func macroInput(_ label: String, value: Binding<String>, unit: String) -> some View {
        LabeledContent(label) {
            HStack(spacing: 6) {
                TextField("", text: value)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 90)
                Text(unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        var trimmedURL = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedURL.isEmpty &&
            !trimmedURL.lowercased().hasPrefix("http://") &&
            !trimmedURL.lowercased().hasPrefix("https://") {
            trimmedURL = "https://" + trimmedURL
        }
        let cleanedSummary = optionalText(summary)
        let cleanedIngredients = optionalText(ingredientsText)
        let cleanedInstructions = optionalText(instructionsText)
        switch mode {
        case .create:
            let r = Recipe(
                title: trimmedTitle,
                urlString: trimmedURL,
                category: category,
                summary: cleanedSummary,
                ingredientsText: cleanedIngredients,
                instructionsText: cleanedInstructions,
                servings: servings > 0 ? servings : nil,
                prepMinutes: prepMinutes > 0 ? prepMinutes : nil,
                calories: optionalDouble(caloriesText),
                protein: optionalDouble(proteinText),
                carbs: optionalDouble(carbsText),
                fat: optionalDouble(fatText)
            )
            onSave(r)
        case .edit(let r):
            r.title = trimmedTitle
            r.urlString = trimmedURL
            r.category = category
            r.summary = cleanedSummary
            r.ingredientsText = cleanedIngredients
            r.instructionsText = cleanedInstructions
            r.servings = servings > 0 ? servings : nil
            r.prepMinutes = prepMinutes > 0 ? prepMinutes : nil
            r.calories = optionalDouble(caloriesText)
            r.protein = optionalDouble(proteinText)
            r.carbs = optionalDouble(carbsText)
            r.fat = optionalDouble(fatText)
            onSave(r)
        }
    }

    private func optionalText(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func optionalDouble(_ value: String) -> Double? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard !normalized.isEmpty else { return nil }
        return Double(normalized)
    }

    private static func numberText(_ value: Double?) -> String {
        guard let value else { return "" }
        return value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
