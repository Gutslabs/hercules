import SwiftUI
import SwiftData

struct RecipesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]

    @State private var selectedCategory: RecipeCategory? = nil
    @State private var searchText = ""
    @State private var searchVisible = false
    @State private var showingFavoritesOnly = false
    @State private var showingNew = false
    @State private var editing: Recipe? = nil
    @State private var viewing: Recipe? = nil
    @FocusState private var searchFocused: Bool

    private var filtered: [Recipe] {
        var result = recipes
        if showingFavoritesOnly {
            result = result.filter(\.isFavorite)
        }
        if let c = selectedCategory {
            result = result.filter { $0.category == c }
        }
        let query = normalizedSearchText(searchText)
        if !query.isEmpty {
            result = result.filter { recipeMatchesSearch($0, query: query) }
        }
        return result.sorted { lhs, rhs in
            if lhs.isFavorite != rhs.isFavorite {
                return lhs.isFavorite && !rhs.isFavorite
            }
            return lhs.createdAt > rhs.createdAt
        }
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

    private var favoriteRecipeCount: Int {
        recipes.filter(\.isFavorite).count
    }

    private var quickRecipeCount: Int {
        recipes.filter { ($0.prepMinutes ?? Int.max) <= 20 }.count
    }

    private var highProteinRecipeCount: Int {
        recipes.filter { ($0.protein ?? 0) >= 30 }.count
    }

    private var missingDetailCount: Int {
        recipes.filter { !$0.hasDetail }.count
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
                Button {
                    toggleSearch()
                } label: {
                    Label("Ara", systemImage: "magnifyingglass")
                }
                .keyboardShortcut("f", modifiers: .command)
                .help("Tariflerde ara (⌘F)")
            }
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
                toggleSearch()
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(searchVisible || !searchText.isEmpty ? Palette.background : Palette.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(searchVisible || !searchText.isEmpty ? Palette.textPrimary : Palette.surfaceElevated)
                    )
            }
            .buttonStyle(.plain)
            .keyboardShortcut("f", modifiers: .command)
            .help("Tariflerde ara (⌘F)")

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
            recipeStat("Favori", value: "\(favoriteRecipeCount)", detail: "hızlı erişim", icon: "heart.fill")
            stripDivider
            recipeStat("Detaylı", value: "\(detailedRecipeCount)", detail: "malzeme + yapılış", icon: "doc.text")
            stripDivider
            recipeStat(
                "Ort. Protein",
                value: averageProtein.map { "\(Fmt.int($0))g" } ?? "-",
                detail: "makrolu tariflerde",
                icon: "bolt"
            )
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
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack(spacing: Spacing.sm) {
                categoryTab(
                    "Tümü",
                    count: categoryCount(nil),
                    icon: "square.grid.2x2",
                    tint: Palette.textPrimary,
                    isSelected: selectedCategory == nil
                ) { selectedCategory = nil }
                ForEach(RecipeCategory.allCases) { c in
                    categoryTab(
                        c.label,
                        count: categoryCount(c),
                        icon: c.icon,
                        tint: tint(for: c),
                        isSelected: selectedCategory == c
                    ) { selectedCategory = c }
                }
                Spacer()
                filterToggle(
                    title: "Favoriler",
                    icon: showingFavoritesOnly ? "heart.fill" : "heart",
                    isActive: showingFavoritesOnly,
                    activeTint: Palette.warning
                ) {
                    showingFavoritesOnly.toggle()
                }
                filterToggle(
                    title: "Ara",
                    icon: "magnifyingglass",
                    isActive: searchVisible || !searchText.isEmpty,
                    activeTint: Palette.textPrimary
                ) {
                    toggleSearch()
                }
                Text("\(filtered.count) tarif")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(minWidth: 58, alignment: .trailing)
            }

            if searchVisible || !searchText.isEmpty {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                    TextField("Tarif, malzeme, yapılış veya kaynak ara", text: $searchText)
                        .font(Typography.body)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                            searchFocused = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.textQuaternary)
                                .frame(width: 24, height: 24)
                        }
                        .buttonStyle(.plain)
                        .help("Aramayı temizle")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                        .fill(Palette.surfaceElevated.opacity(0.72))
                )
            }
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

    private func filterToggle(
        title: String,
        icon: String,
        isActive: Bool,
        activeTint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(Typography.captionBold)
            }
            .foregroundStyle(isActive ? activeTint : Palette.textSecondary)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                    .fill(isActive ? activeTint.opacity(0.13) : Color.white.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                    .strokeBorder(isActive ? activeTint.opacity(0.22) : Palette.border, lineWidth: 0.6)
            )
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func categoryCount(_ category: RecipeCategory?) -> Int {
        let base = showingFavoritesOnly ? recipes.filter(\.isFavorite) : recipes
        guard let category else { return base.count }
        return base.filter { $0.category == category }.count
    }

    private func toggleSearch() {
        let opening = !(searchVisible || searchFocused)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            searchVisible = opening
        }
        if opening {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                searchFocused = true
            }
        } else if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchFocused = false
        }
    }

    private func clearFilters() {
        withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
            selectedCategory = nil
            showingFavoritesOnly = false
            searchText = ""
            searchVisible = false
        }
        searchFocused = false
    }

    private func recipeMatchesSearch(_ recipe: Recipe, query: String) -> Bool {
        recipe.searchCorpus.contains(query)
    }

    private func normalizedSearchText(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased(with: Locale(identifier: "tr_TR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    @ViewBuilder
    private var content: some View {
        if recipes.isEmpty {
            EmptyRecipesState { showingNew = true }
        } else if filtered.isEmpty {
            RecipeNoResultsState(
                query: searchText,
                favoritesOnly: showingFavoritesOnly,
                selectedCategory: selectedCategory,
                onClear: clearFilters
            )
        } else {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                if let lead = filtered.first {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: Spacing.lg) {
                            RecipeSpotlightCard(recipe: lead, onOpen: { viewing = lead }) { editing = lead }
                                .frame(minWidth: 560, maxWidth: .infinity)
                            RecipeInsightPanel(
                                total: recipes.count,
                                favorites: favoriteRecipeCount,
                                detailed: detailedRecipeCount,
                                sourced: sourceRecipeCount,
                                quick: quickRecipeCount,
                                highProtein: highProteinRecipeCount,
                                missingDetail: missingDetailCount,
                                filteredCount: filtered.count,
                                selectedCategory: selectedCategory
                            )
                            .frame(width: 330)
                        }

                        VStack(alignment: .leading, spacing: Spacing.lg) {
                            RecipeSpotlightCard(recipe: lead, onOpen: { viewing = lead }) { editing = lead }
                            RecipeInsightPanel(
                                total: recipes.count,
                                favorites: favoriteRecipeCount,
                                detailed: detailedRecipeCount,
                                sourced: sourceRecipeCount,
                                quick: quickRecipeCount,
                                highProtein: highProteinRecipeCount,
                                missingDetail: missingDetailCount,
                                filteredCount: filtered.count,
                                selectedCategory: selectedCategory
                            )
                        }
                    }
                }

                let rest = Array(filtered.dropFirst())
                if !rest.isEmpty {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Tarif Rafı")
                                .font(Typography.titleSmall)
                                .foregroundStyle(Palette.textPrimary)
                            Text("\(rest.count) kayıt")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textTertiary)
                            Spacer()
                        }

                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(minimum: 320), spacing: Spacing.lg),
                                GridItem(.flexible(minimum: 320), spacing: Spacing.lg)
                            ],
                            alignment: .leading,
                            spacing: Spacing.lg
                        ) {
                            ForEach(rest) { r in
                                RecipeLibraryCard(recipe: r, onOpen: { viewing = r }) { editing = r }
                            }
                        }
                    }
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
        keeper.isFavorite = keeper.isFavorite || duplicate.isFavorite
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
        .shadow(color: Palette.background.opacity(hovering ? 0.42 : 0.25), radius: hovering ? 28 : 18, x: 0, y: hovering ? 18 : 10)
        .scaleEffect(hovering ? 1.004 : 1)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onOpen() }
    }

    private var cardActions: some View {
        HStack(spacing: 7) {
            RecipeFavoriteButton(recipe: recipe, size: 28, iconSize: 11)

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
            if recipe.isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: prominent ? 11 : 9, weight: .semibold))
            }
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

struct RecipeInsightPanel: View {
    let total: Int
    let favorites: Int
    let detailed: Int
    let sourced: Int
    let quick: Int
    let highProtein: Int
    let missingDetail: Int
    let filteredCount: Int
    let selectedCategory: RecipeCategory?

    private var activeLabel: String {
        selectedCategory?.label ?? "Tüm tarifler"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AKTİF RAF")
                        .font(Typography.label)
                        .tracking(0.8)
                        .foregroundStyle(Palette.textQuaternary)
                    Text(activeLabel)
                        .font(Typography.title)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                Text("\(filteredCount)")
                    .font(Typography.display(34))
                    .foregroundStyle(Palette.textPrimary)
            }

            Divider().overlay(Palette.border)

            VStack(spacing: 0) {
                insightRow(label: "Favori", value: favorites, total: total, icon: "heart.fill")
                Divider().overlay(Palette.border)
                insightRow(label: "Detaylı", value: detailed, total: total, icon: "checkmark.seal")
                Divider().overlay(Palette.border)
                insightRow(label: "Kaynaklı", value: sourced, total: total, icon: "link")
                Divider().overlay(Palette.border)
                insightRow(label: "20 dk altı", value: quick, total: total, icon: "timer")
                Divider().overlay(Palette.border)
                insightRow(label: "Protein yüksek", value: highProtein, total: total, icon: "bolt")
                Divider().overlay(Palette.border)
                insightRow(label: "Detay bekliyor", value: missingDetail, total: total, icon: "doc.badge.plus")
            }

            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Text("AI tarif eklerken özet, malzeme, yapılış ve makrolar dolu gelirse burası gerçek kütüphane gibi çalışır.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(Palette.surfaceElevated.opacity(0.78))
            )
        }
        .padding(Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.borderStrong.opacity(0.75), lineWidth: 0.6)
        )
        .shadow(color: Palette.background.opacity(0.32), radius: 24, x: 0, y: 18)
    }

    private func insightRow(label: String, value: Int, total: Int, icon: String) -> some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.white.opacity(0.055)))
            Text(label)
                .font(Typography.bodyBold)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(value)")
                    .font(Typography.monoLarge)
                    .foregroundStyle(Palette.textPrimary)
                Text(total > 0 ? "\(Int((Double(value) / Double(total)) * 100))%" : "-")
                    .font(Typography.micro)
                    .foregroundStyle(Palette.textQuaternary)
            }
        }
        .padding(.vertical, 12)
    }
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
                        if recipe.isFavorite {
                            Image(systemName: "heart.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.warning)
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
        .overlay(alignment: .topLeading) {
            Capsule(style: .continuous)
                .fill(recipe.category.displayTint.opacity(0.72))
                .frame(width: hovering ? 96 : 56, height: 2)
                .padding(.leading, Spacing.lg)
                .padding(.top, 1)
                .animation(.easeOut(duration: 0.18), value: hovering)
        }
        .shadow(color: Palette.background.opacity(hovering ? 0.34 : 0.18), radius: hovering ? 18 : 10, x: 0, y: hovering ? 10 : 6)
        .scaleEffect(hovering ? 1.006 : 1)
        .animation(.easeOut(duration: 0.18), value: hovering)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { onOpen() }
    }

    private var cardActions: some View {
        HStack(spacing: 5) {
            RecipeFavoriteButton(recipe: recipe, size: 25, iconSize: 10.5)
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
                        try? ctx.save()
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
        detailPanel("Malzemeler", icon: "list.bullet") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), alignment: .top)], alignment: .leading, spacing: 10) {
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

private struct RecipeMetric {
    let label: String
    let value: String
    let tint: Color
}

private struct RecipeFavoriteButton: View {
    @Environment(\.modelContext) private var ctx
    let recipe: Recipe
    var size: CGFloat = 28
    var iconSize: CGFloat = 11

    var body: some View {
        Button {
            recipe.isFavorite.toggle()
            try? ctx.save()
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

struct RecipeNoResultsState: View {
    let query: String
    let favoritesOnly: Bool
    let selectedCategory: RecipeCategory?
    var onClear: () -> Void

    private var detail: String {
        var parts: [String] = []
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cleanQuery.isEmpty {
            parts.append("\"\(cleanQuery)\" araması")
        }
        if favoritesOnly {
            parts.append("favoriler")
        }
        if let selectedCategory {
            parts.append(selectedCategory.label)
        }
        return parts.isEmpty ? "Bu filtrelerde tarif görünmüyor." : "\(parts.joined(separator: " · ")) filtresiyle eşleşme yok."
    }

    var body: some View {
        VStack(spacing: Spacing.md) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 25, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text("Sonuç yok")
                .font(Typography.title)
                .foregroundStyle(Palette.textPrimary)
            Text(detail)
                .font(Typography.body)
                .foregroundStyle(Palette.textTertiary)
                .multilineTextAlignment(.center)
            Button {
                onClear()
            } label: {
                Label("Filtreleri temizle", systemImage: "xmark.circle")
                    .font(Typography.captionBold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.surfaceElevated)
            )
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
    @State private var isFavorite: Bool
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
            _isFavorite = State(initialValue: false)
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
            _isFavorite = State(initialValue: r.isFavorite)
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
        !trimmedTitle.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            editorHeader
            Divider().overlay(Palette.border)
            ScrollView {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Spacing.xl) {
                        editorPreview
                            .frame(width: 285)
                        editorForm
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }

                    VStack(alignment: .leading, spacing: Spacing.lg) {
                        editorPreview
                        editorForm
                    }
                }
                .padding(Spacing.xxl)
            }
        }
        .background(Palette.background)
        .frame(width: 920, height: 760)
        .preferredColorScheme(.dark)
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var editorHeader: some View {
        HStack(spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(category.displayTint.opacity(0.16))
                    .frame(width: 42, height: 42)
                Image(systemName: category.icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(category.displayTint)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(isEditing ? "TARİFİ DÜZENLE" : "YENİ TARİF")
                    .font(Typography.label)
                    .tracking(0.8)
                    .foregroundStyle(Palette.textTertiary)
                Text(trimmedTitle.isEmpty ? "Tarif taslağı" : trimmedTitle)
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("İptal")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(Capsule(style: .continuous).fill(Palette.surfaceElevated))
            }
            .buttonStyle(.plain)

            Button {
                save()
                dismiss()
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text(isEditing ? "Kaydet" : "Ekle")
                        .font(Typography.captionBold)
                }
                .foregroundStyle(canSave ? Palette.background : Palette.textQuaternary)
                .padding(.horizontal, 15)
                .padding(.vertical, 9)
                .background(Capsule(style: .continuous).fill(canSave ? Palette.textPrimary : Palette.surfaceElevated))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, Spacing.xxl)
        .padding(.vertical, Spacing.lg)
        .background(Palette.surface.opacity(0.72))
    }

    private var editorPreview: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(spacing: Spacing.sm) {
                    Image(systemName: category.icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(category.label)
                        .font(Typography.captionBold)
                    Spacer()
                    if isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Palette.warning)
                    }
                    Text("\(servings > 0 ? servings : 1)x")
                        .font(Typography.mono)
                        .foregroundStyle(Palette.textSecondary)
                }
                .foregroundStyle(category.displayTint)

                Text(trimmedTitle.isEmpty ? "Tarif adı" : trimmedTitle)
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                Text(previewSummary)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if previewMetrics.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Makro boş")
                        .font(Typography.captionBold)
                        .foregroundStyle(Palette.textSecondary)
                    Text("Kalori ve makrolar girilince AI chat ve takvim daha net konuşur.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .lineSpacing(3)
                }
                .padding(Spacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Color.white.opacity(0.035)))
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.sm) {
                    ForEach(previewMetrics, id: \.label) { metric in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(metric.label.uppercased())
                                .font(.system(size: 8, weight: .semibold))
                                .tracking(0.5)
                                .foregroundStyle(Palette.textQuaternary)
                            Text(metric.value)
                                .font(Typography.mono)
                                .foregroundStyle(metric.tint)
                        }
                        .padding(Spacing.sm)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.surfaceElevated))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                sectionLabel("Durum")
                ForEach(Array(completionRows.enumerated()), id: \.offset) { _, row in
                    HStack(spacing: Spacing.sm) {
                        Image(systemName: row.1 ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(row.1 ? Palette.positive : Palette.textQuaternary)
                        Text(row.0)
                            .font(Typography.caption)
                            .foregroundStyle(row.1 ? Palette.textSecondary : Palette.textTertiary)
                    }
                }
            }

            if let sourcePreview {
                VStack(alignment: .leading, spacing: 6) {
                    sectionLabel("Kaynak")
                    Text(sourcePreview)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.88))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.7)
        )
        .overlay(alignment: .topLeading) {
            Capsule(style: .continuous)
                .fill(category.displayTint)
                .frame(width: 74, height: 2)
                .padding(.leading, Spacing.lg)
        }
    }

    private var editorForm: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            editorSection("Kimlik", icon: "tag") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    textFieldBlock("Başlık", text: $title, prompt: "ör: Yoğurtlu tavuklu bulgur bowl", helper: "Kartlarda ve AI aksiyonlarında görünen ana isim.")
                    if trimmedTitle.isEmpty {
                        Text("Başlık zorunlu.")
                            .font(Typography.captionBold)
                            .foregroundStyle(Palette.negative)
                    }
                    textFieldBlock("Kaynak URL", text: $urlString, prompt: "opsiyonel", helper: "Tarif bir siteden geldiyse linki burada tut.")
                    VStack(alignment: .leading, spacing: Spacing.sm) {
                        sectionLabel("Kategori")
                        Picker("", selection: $category) {
                            ForEach(RecipeCategory.allCases) {
                                Text($0.label).tag($0)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                    Toggle(isOn: $isFavorite) {
                        HStack(spacing: Spacing.sm) {
                            Image(systemName: isFavorite ? "heart.fill" : "heart")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isFavorite ? Palette.warning : Palette.textTertiary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Favori")
                                    .font(Typography.bodyBold)
                                    .foregroundStyle(Palette.textPrimary)
                                Text("Tarif rafında öne çıksın ve favori filtresinde görünsün.")
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.textQuaternary)
                            }
                        }
                    }
                    .toggleStyle(.switch)
                    .padding(.horizontal, Spacing.md)
                    .padding(.vertical, 10)
                    .background(inputBackground)
                }
            }

            editorSection("İçerik", icon: "text.alignleft") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    textEditorBlock("Kısa özet", text: $summary, minHeight: 76, helper: "Ucuz, yüksek proteinli, pratik gibi karar cümlesi.")
                    textEditorBlock("Malzemeler", text: $ingredientsText, minHeight: 132, helper: "Her malzemeyi ayrı satıra yazarsan popup daha düzgün listeler.")
                    textEditorBlock("Yapılış", text: $instructionsText, minHeight: 156, helper: "Adım adım yaz. Numara koymasan da app sıralar.")
                }
            }

            editorSection("Servis ve makro", icon: "chart.bar") {
                VStack(alignment: .leading, spacing: Spacing.md) {
                    HStack(alignment: .top, spacing: Spacing.md) {
                        numberFieldBlock("Porsiyon", value: $servings, unit: "adet")
                        numberFieldBlock("Hazırlık", value: $prepMinutes, unit: "dk")
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                        macroInput("Kalori", value: $caloriesText, unit: "kcal", tint: Palette.textPrimary)
                        macroInput("Protein", value: $proteinText, unit: "g", tint: Palette.macroProtein)
                        macroInput("Karbonhidrat", value: $carbsText, unit: "g", tint: Palette.macroCarbs)
                        macroInput("Yağ", value: $fatText, unit: "g", tint: Palette.macroFat)
                    }
                }
            }

            if isEditing, let onDelete {
                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    Label("Tarifi Sil", systemImage: "trash")
                        .font(Typography.captionBold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.negative)
                .background(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .fill(Palette.negative.opacity(0.10))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                        .strokeBorder(Palette.negative.opacity(0.18), lineWidth: 0.7)
                )
            }
        }
    }

    private var previewSummary: String {
        let trimmed = summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Kısa özet yazılınca burada görünecek. Bu alan tarifin neden listende olduğunu netleştirir." : trimmed
    }

    private var sourcePreview: String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return trimmed
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: "www.", with: "")
    }

    private var previewMetrics: [RecipeMetric] {
        [
            optionalDouble(caloriesText).map { RecipeMetric(label: "Kalori", value: "\(Fmt.int($0))", tint: Palette.textPrimary) },
            optionalDouble(proteinText).map { RecipeMetric(label: "Protein", value: "\(Fmt.int($0))g", tint: Palette.macroProtein) },
            optionalDouble(carbsText).map { RecipeMetric(label: "Karb", value: "\(Fmt.int($0))g", tint: Palette.macroCarbs) },
            optionalDouble(fatText).map { RecipeMetric(label: "Yağ", value: "\(Fmt.int($0))g", tint: Palette.macroFat) },
        ].compactMap { $0 }
    }

    private var completionRows: [(String, Bool)] {
        [
            ("Başlık", !trimmedTitle.isEmpty),
            ("Özet", !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
            ("Malzeme", !ingredientsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
            ("Yapılış", !instructionsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
            ("Makro", !previewMetrics.isEmpty),
        ]
    }

    private func editorSection<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(category.displayTint)
                Text(title.uppercased())
                    .font(Typography.captionBold)
                    .tracking(0.8)
                    .foregroundStyle(Palette.textSecondary)
            }
            content()
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.82))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.6)
        )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(Typography.label)
            .tracking(0.8)
            .foregroundStyle(Palette.textTertiary)
    }

    private func textFieldBlock(_ label: String, text: Binding<String>, prompt: String, helper: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionLabel(label)
            TextField("", text: text, prompt: Text(prompt))
                .font(Typography.body)
                .textFieldStyle(.plain)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, 11)
                .background(inputBackground)
            Text(helper)
                .font(Typography.caption)
                .foregroundStyle(Palette.textQuaternary)
        }
    }

    private func textEditorBlock(_ label: String, text: Binding<String>, minHeight: CGFloat, helper: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionLabel(label)
            TextEditor(text: text)
                .font(Typography.body)
                .foregroundStyle(Palette.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(Spacing.sm)
                .frame(minHeight: minHeight)
                .background(inputBackground)
            Text(helper)
                .font(Typography.caption)
                .foregroundStyle(Palette.textQuaternary)
        }
    }

    private func numberFieldBlock(_ label: String, value: Binding<Int>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionLabel(label)
            HStack(spacing: Spacing.sm) {
                TextField("", value: value, format: .number)
                    .font(Typography.monoLarge)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                Text(unit)
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(inputBackground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func macroInput(_ label: String, value: Binding<String>, unit: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            sectionLabel(label)
            HStack(spacing: Spacing.sm) {
                TextField("", text: value, prompt: Text("0"))
                    .font(Typography.monoLarge)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .foregroundStyle(tint)
                Text(unit)
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 10)
            .background(inputBackground)
        }
    }

    private var inputBackground: some View {
        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
            .fill(Palette.surfaceElevated.opacity(0.82))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.6)
            )
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
                isFavorite: isFavorite,
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
            r.isFavorite = isFavorite
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
