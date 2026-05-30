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
                ctx.saveOrReport()
            }
        }
        .sheet(item: $editing) { r in
            RecipeEditor(mode: .edit(r)) { _ in
                ctx.saveOrReport()
            } onDelete: {
                ctx.delete(r)
                ctx.saveOrReport()
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
            ctx.saveOrReport()
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
