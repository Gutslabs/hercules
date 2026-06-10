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

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 1040

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(compact: compact)
                    filterRow

                    if searchVisible || !searchText.isEmpty {
                        searchField
                    }

                    content(compact: compact)

                    Text("AI tarif eklerken özet, malzeme, yapılış ve makrolar dolu gelirse burası gerçek kütüphane gibi çalışır.")
                        .font(.system(size: 10.5, weight: .regular))
                        .foregroundStyle(Palette.textQuaternary)
                        .padding(.top, 4)
                }
                .padding(.horizontal, compact ? 20 : 40)
                .padding(.vertical, compact ? 24 : 32)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .background(DashboardBackground().ignoresSafeArea())
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

    // MARK: - Header

    @ViewBuilder
    private func header(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 10) {
                headerTitle
                newRecipeButton
            }
        } else {
            HStack(alignment: .bottom) {
                headerTitle
                Spacer()
                newRecipeButton
            }
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Yemekler").eyebrow()
            Text("Tarifler")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(Palette.textPrimary)
            Text("AI'ın eklediği tarifler — detay, makro ve kaynak bilgisiyle. \(statsLine).")
                .font(Typography.caption)
                .foregroundStyle(Palette.textQuaternary)
                .padding(.top, 2)
        }
    }

    private var statsLine: String {
        var parts = ["\(recipes.count) tarif"]
        if !recipes.isEmpty {
            if detailedRecipeCount == recipes.count && sourceRecipeCount == recipes.count {
                parts.append("hepsi detaylı + kaynaklı")
            } else {
                parts.append("\(detailedRecipeCount) detaylı")
            }
            if let avg = averageProtein {
                parts.append("ort. \(Fmt.int(avg))g protein")
            }
        }
        return parts.joined(separator: " · ")
    }

    private var newRecipeButton: some View {
        Button {
            showingNew = true
        } label: {
            Text("+ Yeni Tarif")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.btnFg)
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Palette.accent)
                )
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: .command)
        .help("Yeni tarif ekle (⌘N)")
    }

    // MARK: - Filtre satırı

    private var filterRow: some View {
        HStack(spacing: 8) {
            categoryPill(nil)
            ForEach(RecipeCategory.allCases) { c in
                categoryPill(c)
            }
            Spacer(minLength: 8)
            filterPill(
                title: "Favoriler",
                icon: showingFavoritesOnly ? "heart.fill" : "heart",
                isActive: showingFavoritesOnly,
                activeTint: Palette.warning
            ) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    showingFavoritesOnly.toggle()
                }
            }
            filterPill(
                title: "Ara",
                icon: "magnifyingglass",
                isActive: searchVisible || !searchText.isEmpty,
                activeTint: Palette.textPrimary
            ) {
                toggleSearch()
            }
            .keyboardShortcut("f", modifiers: .command)
        }
    }

    private func categoryPill(_ category: RecipeCategory?) -> some View {
        let count = categoryCount(category)
        let isSelected = selectedCategory == category
        return Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                selectedCategory = category
            }
        } label: {
            HStack(spacing: 5) {
                Text(category?.label ?? "Tümü")
                    .font(.system(size: 11.5, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .opacity(0.6)
            }
            .foregroundStyle(isSelected ? Palette.background : (count == 0 ? Palette.textQuaternary : Palette.textSecondary))
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Palette.btnBg : Palette.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Palette.border, lineWidth: 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func filterPill(
        title: String,
        icon: String,
        isActive: Bool,
        activeTint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(isActive ? activeTint : Palette.textSecondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? activeTint.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isActive ? activeTint.opacity(0.25) : Palette.border, lineWidth: 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private var searchField: some View {
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .dashboardCard(radius: Radius.md)
    }

    // MARK: - İçerik

    @ViewBuilder
    private func content(compact: Bool) -> some View {
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
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 16, alignment: .top),
                    count: compact ? 1 : 2
                ),
                alignment: .leading,
                spacing: 16
            ) {
                ForEach(filtered) { r in
                    RecipeCard(recipe: r, onOpen: { viewing = r }, onEdit: { editing = r })
                }
            }
        }
    }

    // MARK: - Yardımcılar

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
