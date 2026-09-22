import SwiftUI
import LucideKit
import SwiftData

struct RecipesView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \Recipe.createdAt, order: .reverse) private var recipes: [Recipe]

    @State private var selectedCategory: RecipeCategory? = nil
    @State private var searchText = ""
    @State private var searchVisible = false
    @State private var showingFavoritesOnly = false
    @State private var showingNew = false
    @State private var showingInstagramImport = false
    @State private var editing: Recipe? = nil
    @State private var viewing: Recipe? = nil
    /// Masaüstü editoryal paneli: sağ raydan seçilen tarif solda metin olarak açılır.
    @State private var selected: Recipe? = nil
    /// Rail kartı hover'ı + tarif fotoğrafı değişim sayacı (disk store yenilenince artar).
    @State private var hoveredRailID: PersistentIdentifier? = nil
    @State private var recipeImageEpoch = 0
    /// Tarif videoları artık sayfada değil, bu popover'da.
    @State private var showingVideos = false
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



    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 1040

            if compact {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            // Üst şerit yok: aksiyonlar filtre satırının yanında.
                            HStack(spacing: 8) {
                                Spacer(minLength: 0)
                                instagramImportButton.fixedSize()
                                newRecipeButton.fixedSize()
                            }
                            filterRow

                            if searchVisible || !searchText.isEmpty {
                                searchField
                            }

                            content(compact: true)
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                // Editoryal düzen: solda akan metin (giriş ya da seçili tarif),
                // sağda arama + öğün sekmeleri + kayan tarif kartları rayı.
                // İki panel de pencerenin dibine iner: sol panel kendi boyunu
                // GeometryReader'dan okuyup içeriği o yüksekliğe yayar, ayırıcı
                // çizgi ve ray tam boy uzar (HStack .top hizalı ama kimse kısa değil).
                VStack(spacing: 0) {
                    HStack(alignment: .top, spacing: 0) {
                        GeometryReader { pane in
                            ScrollView {
                                editorialContent(
                                    available: pane.size.height,
                                    column: min(720, max(280, pane.size.width - 56)) // 28pt yatay padding × 2
                                )
                                .padding(.horizontal, 28)
                                .padding(.vertical, 18)
                                .frame(maxWidth: .infinity, minHeight: pane.size.height, alignment: .topLeading)
                            }
                        }

                        Rectangle()
                            .fill(Palette.border.opacity(0.6))
                            .frame(width: 1)
                            .frame(maxHeight: .infinity)

                        recipeRail
                            .frame(width: 348)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                }
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
        .sheet(isPresented: $showingInstagramImport) {
            InstagramImportView()
        }
        .onAppear(perform: mergeDuplicateRecipes)
        .onReceive(NotificationCenter.default.publisher(for: RecipeImageStore.changed)) { _ in
            recipeImageEpoch += 1
        }
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
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.btnBg)
                )
        }
        .buttonStyle(.plain)
        .help("Yeni tarif ekle")
    }

    private var instagramImportButton: some View {
        Button {
            showingInstagramImport = true
        } label: {
            Text("Instagram'dan Aktar")
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.surfaceElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Palette.border, lineWidth: 1)
                        )
                )
        }
        .buttonStyle(.plain)
        .help("Instagram'da kaydettiğin gönderileri tarife çevir")
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
            .foregroundStyle(isSelected ? Palette.btnFg : (count == 0 ? Palette.textQuaternary : Palette.textSecondary))
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Palette.btnBg : Palette.fieldFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color.clear : Palette.border, lineWidth: 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
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
                Lucide(sf: icon, size: 10)
                Text(title)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(isActive ? activeTint : Palette.textSecondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? activeTint.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isActive ? activeTint.opacity(0.25) : Palette.border, lineWidth: 0.6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private var searchField: some View {
        HStack(spacing: Spacing.sm) {
            Lucide(sf: "magnifyingglass", size: 12)
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
                    Lucide(sf: "xmark.circle.fill", size: 13)
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
        // Odaklanınca aynı yumuşak halka: sistem odak halkası yerine tema dili.
        .selectionRing(searchFocused, cornerRadius: Radius.md)
    }

    // MARK: - Editoryal panel (sol)

    /// Vurgu: metin içi "fosforlu kalem" — AttributedString backgroundColor.
    private func hl(_ s: String, _ tint: Color) -> AttributedString {
        var a = AttributedString(s)
        a.backgroundColor = tint.opacity(0.26)
        a.font = .system(size: 15, weight: .medium)
        return a
    }

    private func plain(_ s: String) -> AttributedString {
        AttributedString(s)
    }

    /// Sol panelin gövdesi — panelin TAM boyunu kaplar (altta ölü boşluk kalmaz):
    /// giriş metni dikeyde ortalanır, seçili tarif üstte akar ve artan yükseklik
    /// hero fotoğrafına gider. Videolar rafı her iki durumda da panelin dibinde.
    /// Sığmayan içerikte esnek boşluklar sıfırlanır, ScrollView devreye girer.
    @ViewBuilder
    /// Giriş de seçili tarif de aynı dilde: metin bloğu panelin dikey ortasında,
    /// üstte ve altta eşit nefes. (Videolar artık akışta değil, popover'da.)
    private func editorialContent(available: CGFloat, column: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)
            if let r = selected {
                editorialDetail(r, photo: heroPhotoHeight(r, available: available, column: column))
            } else {
                editorialIntro
            }
            Spacer(minLength: 0)
        }
    }

    /// Hero fotoğrafı esnek: sabit kabuk + metin bloğu yer ayırdıktan sonra ARTAN
    /// yükseklik fotoğrafa gider — kısa tarifte büyür, uzun tarifte tabana iner.
    /// `chrome` = dikey padding (18×2) + başlık satırı + makro cümlesi + aksiyon
    /// satırı + detay VStack aralıkları (18 × 5). Videolar kartı artık akışta
    /// değil (popover'a taşındı), payı da düştü. Metin tahmini `proseHeight`'tan.
    /// Taban 240, tavan 420 (foto sayfayı yutmasın); tahmin şaşarsa fark üstteki
    /// ve alttaki esnek boşluğa gider, düzen bozulmaz.
    private func heroPhotoHeight(_ r: Recipe, available: CGFloat, column: CGFloat) -> CGFloat {
        let chrome: CGFloat = 36 + 33 + 28 + 32 + 18 * 5
        return min(420, max(240, available - chrome - proseHeight(r, column: column)))
    }

    /// Metin bloğu kaba tahmini: satır sayısı × satır yüksekliği (14pt yazı +
    /// 6–7pt lineSpacing ≈ 21pt) + bölüm başlıkları ("Malzemeler" / "Yapılış"
    /// 12pt ≈ 15 + 7pt aralık). Sütun genişliği panelden gelir.
    private func proseHeight(_ r: Recipe, column: CGFloat) -> CGFloat {
        let perLine = max(28, column / 7.4)   // 14pt sistem yazısında ~7.4pt/karakter
        var h: CGFloat = 0
        if let s = r.summary, !s.isEmpty { h += estimatedLines(s, perLine: perLine) * 21 }
        if let ing = r.ingredientsText, !ing.isEmpty { h += 22 + estimatedLines(ing, perLine: perLine) * 21 }
        if let inst = r.instructionsText, !inst.isEmpty { h += 22 + estimatedLines(inst, perLine: perLine) * 21 }
        return h
    }

    /// Satır tahmini: her gerçek satır, sütuna sığmayıp kaç kez sarılıyorsa o kadar.
    private func estimatedLines(_ text: String, perLine: CGFloat) -> CGFloat {
        text.split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { total, line in
            total + max(1, (CGFloat(line.count) / perLine).rounded(.up))
        }
    }

    /// Giriş metni — kütüphane özeti, sayılar fosforlu.
    private var editorialIntro: some View {
        let counts = RecipeCategory.allCases.map { c in
            (c, recipes.filter { $0.category == c }.count)
        }
        var text = plain("Tarif kütüphanen. Şu an ")
        text += hl("\(recipes.count) tarif", Palette.macroCarbs)
        text += plain(" kayıtlı — ")
        for (i, pair) in counts.enumerated() {
            text += hl("\(pair.1) \(pair.0.label.lowercased(with: Locale(identifier: "tr_TR")))", Palette.macroFat)
            text += plain(i < counts.count - 1 ? ", " : ". ")
        }
        if let avg = averageProtein {
            text += plain("Detaylı tariflerde ortalama ")
            text += hl("\(Fmt.int(avg)) g protein", Palette.positive)
            text += plain(" var. ")
        }
        let favs = recipes.filter(\.isFavorite).count
        if favs > 0 {
            text += plain("Favorilerinde ")
            text += hl("\(favs) tarif", Palette.chart)
            text += plain(" duruyor. ")
        }
        text += plain("Sağdaki raydan bir karta tıkla — malzemeler ve yapılış burada açılır.")

        return Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Palette.textSecondary)
            .lineSpacing(7)
            .frame(maxWidth: 720, alignment: .leading)
            .padding(.top, 8)
    }

    /// Seçili tarif — editoryal akış: büyük başlık, fosforlu makro cümlesi,
    /// malzemeler ve yapılış düz metin bölümleri.
    /// `photo`: hero fotoğrafının boyu — panel yüksekliğinden hesaplanır (bkz. `heroPhotoHeight`).
    private func editorialDetail(_ r: Recipe, photo: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(r.title)
                .font(.system(size: 27, weight: .bold))
                .tracking(-0.4)
                .foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            metaSentence(r)

            if let img = RecipeImageStore.image(for: r) {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: photo)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Palette.border.opacity(0.5), lineWidth: 1))
            }

            if let summary = r.summary, !summary.isEmpty {
                Text(summary)
                    .font(.system(size: 14.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let ing = r.ingredientsText, !ing.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Malzemeler")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                    Text(ing)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textPrimary)
                        .lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let inst = r.instructionsText, !inst.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Yapılış")
                        .font(.system(size: 12))
                        .foregroundStyle(Palette.textTertiary)
                    Text(inst)
                        .font(.system(size: 14))
                        .foregroundStyle(Palette.textPrimary)
                        .lineSpacing(7)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 6) {
                Button {
                    r.isFavorite.toggle()
                    ctx.saveOrReport()
                } label: {
                    HStack(spacing: 6) {
                        Lucide(sf: r.isFavorite ? "star.fill" : "star", size: 12)
                        Text(r.isFavorite ? "Favoride" : "Favorile")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(r.isFavorite ? Palette.warning : Palette.textSecondary)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .flatButtonChrome()
                }
                .buttonStyle(.plain)

                Button { editing = r } label: {
                    HStack(spacing: 6) {
                        Lucide(sf: "pencil", size: 12)
                        Text("Düzenle").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .flatButtonChrome()
                }
                .buttonStyle(.plain)

                if let url = r.url {
                    Link(destination: url) {
                        HStack(spacing: 6) {
                            Lucide(sf: "arrow.up.right", size: 11)
                            Text("Kaynak").font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .flatButtonChrome()
                    }
                }

                Button {
                    showingVideos = true
                } label: {
                    HStack(spacing: 6) {
                        Lucide("video", size: 12)
                        Text("Videolar").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .flatButtonChrome()
                }
                .buttonStyle(.plain)
                .help("Tarif videoları")
                .popover(isPresented: $showingVideos, arrowEdge: .top) {
                    RecipeVideosSection()
                        .frame(width: 460)
                        .padding(16)
                }

                Menu {
                    Button(RecipeImageStore.hasImage(for: r) ? "Fotoğrafı değiştir…" : "Fotoğraf seç…") {
                        RecipeImageStore.pickImage(for: r)
                    }
                    if RecipeImageStore.hasImage(for: r) {
                        Button("Fotoğrafı kaldır", role: .destructive) {
                            RecipeImageStore.clear(for: r)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Lucide(sf: "photo", size: 12)
                        Text("Fotoğraf").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .flatButtonChrome()
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Button {
                    withAnimation(.easeOut(duration: 0.18)) { selected = nil }
                } label: {
                    HStack(spacing: 6) {
                        Lucide(sf: "xmark", size: 11)
                        Text("Kapat").font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.horizontal, 11)
                    .frame(height: 30)
                    .flatButtonChrome()
                }
                .buttonStyle(.plain)
                .help("Girişe dön")

                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: 720, alignment: .leading)
        .id(r.id)
        .transition(.opacity)
    }

    /// Makro cümlesi: sayılar fosforlu — "Porsiyon başına 520 kalori, 42 g protein…"
    private func metaSentence(_ r: Recipe) -> some View {
        var text = plain(r.servings.map { "\($0) porsiyon · porsiyon başına " } ?? "Porsiyon başına ")
        var parts = 0
        if let kcal = r.calories { text += hl("\(Fmt.int(kcal)) kalori", Palette.warning); parts += 1 }
        if let pr = r.protein {
            text += plain(parts > 0 ? ", " : "")
            text += hl("\(Fmt.int(pr)) g protein", Palette.positive); parts += 1
        }
        if let cb = r.carbs {
            text += plain(parts > 0 ? ", " : "")
            text += hl("\(Fmt.int(cb)) g karb", Palette.macroCarbs); parts += 1
        }
        if let ft = r.fat {
            text += plain(parts > 0 ? ", " : "")
            text += hl("\(Fmt.int(ft)) g yağ", Palette.macroFat); parts += 1
        }
        if let dk = r.prepMinutes {
            text += plain(parts > 0 ? " — " : "")
            text += hl("\(dk) dk'da hazır", Palette.chart)
        }
        if parts == 0 && r.prepMinutes == nil {
            text = plain("Makro bilgisi girilmemiş — düzenleyip ekleyebilirsin.")
        }
        return Text(text)
            .font(.system(size: 15))
            .foregroundStyle(Palette.textSecondary)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Tarif rayı (sağ)

    private var railTabIndex: Binding<Int> {
        Binding(
            get: {
                switch selectedCategory {
                case nil: return 0
                case .breakfast: return 1
                case .dinner: return 2
                case .dessert: return 3
                }
            },
            set: { idx in
                selectedCategory = [nil, .breakfast, .dinner, .dessert][idx]
            }
        )
    }

    private var recipeRail: some View {
        VStack(alignment: .leading, spacing: 10) {
            searchField

            HStack(spacing: 6) {
                BoardPeriodSwitcher(
                    options: ["Tümü", "Kahvaltı", "Akşam", "Tatlı"],
                    selection: railTabIndex
                )
                Spacer(minLength: 0)
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { showingFavoritesOnly.toggle() }
                } label: {
                    Lucide(sf: showingFavoritesOnly ? "star.fill" : "star", size: 12)
                        .foregroundStyle(showingFavoritesOnly ? Palette.warning : Palette.textTertiary)
                        .frame(width: 26, height: 26)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(showingFavoritesOnly ? Palette.warning.opacity(0.12) : Palette.surfaceElevated.opacity(0.6)))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Sadece favoriler")
            }

            if filtered.isEmpty {
                Text(recipes.isEmpty ? "Henüz tarif yok — koça tarif çıkarttır ya da elle ekle." : "Bu filtrede tarif yok.")
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 14)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 8) {
                        ForEach(filtered) { r in
                            railCard(r)
                        }
                    }
                    .padding(.bottom, 20)
                    .id(recipeImageEpoch)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                newRecipeButton
                instagramImportButton
                Button {
                    showingVideos = true
                } label: {
                    Lucide("video", size: 12)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Palette.surfaceElevated))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Tarif videoları")
                .popover(isPresented: $showingVideos, arrowEdge: .top) {
                    RecipeVideosSection()
                        .frame(width: 460)
                        .padding(16)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private func railCard(_ r: Recipe) -> some View {
        let isSelected = selected?.id == r.id
        let isHovered = hoveredRailID == r.id
        return Button {
            withAnimation(.easeOut(duration: 0.14)) { selected = r }
        } label: {
            HStack(spacing: 11) {
                railThumb(r)

                VStack(alignment: .leading, spacing: 3) {
                    Text(r.title)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 5) {
                        if let kcal = r.calories {
                            Text("\(Fmt.int(kcal)) kalori")
                                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(Palette.textTertiary)
                        }
                        if let pr = r.protein {
                            Text("·").font(.system(size: 10.5)).foregroundStyle(Palette.textQuaternary)
                            Text("P \(Fmt.int(pr))g")
                                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                                .foregroundStyle(Palette.positive.opacity(0.85))
                        }
                        if let dk = r.prepMinutes {
                            Text("·").font(.system(size: 10.5)).foregroundStyle(Palette.textQuaternary)
                            Text("\(dk) dk")
                                .font(.system(size: 10.5).monospacedDigit())
                                .foregroundStyle(Palette.textQuaternary)
                        }
                        if r.calories == nil && r.protein == nil && r.prepMinutes == nil {
                            Text(r.category.label)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.textQuaternary)
                        }
                    }
                    .lineLimit(1)
                }

                Spacer(minLength: 0)

                if r.isFavorite {
                    Lucide(sf: "star.fill", size: 10)
                        .foregroundStyle(Palette.warning)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .selectionRing(isSelected, cornerRadius: 12, isHovered: isHovered,
                           base: Palette.surface, baseShadow: true)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside {
                hoveredRailID = r.id
            } else if hoveredRailID == r.id {
                hoveredRailID = nil
            }
        }
        .help(r.title)
    }

    /// Kart görseli: foto varsa 44pt thumbnail, yoksa kategori-renkli ikon fayansı.
    @ViewBuilder
    private func railThumb(_ r: Recipe) -> some View {
        if let img = RecipeImageStore.image(for: r) {
            Image(nsImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Palette.border.opacity(0.5), lineWidth: 1))
        } else {
            Image(systemName: r.category.icon)
                .font(.system(size: 14))
                .foregroundStyle(categoryTint(r.category))
                .frame(width: 44, height: 44)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(categoryTint(r.category).opacity(0.12)))
        }
    }

    private func categoryTint(_ c: RecipeCategory) -> Color {
        switch c {
        case .breakfast: return Palette.warning
        case .dinner:    return Palette.chart
        case .dessert:   return Palette.macroFat
        }
    }

    private func railSubtitle(_ r: Recipe) -> String {
        var bits: [String] = []
        if let kcal = r.calories { bits.append("\(Fmt.int(kcal)) kalori") }
        if let pr = r.protein { bits.append("P \(Fmt.int(pr))g") }
        if let dk = r.prepMinutes { bits.append("\(dk) dk") }
        return bits.isEmpty ? r.category.label : bits.joined(separator: " · ")
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

    /// Kaynak URL anahtara DAHİL: yalnız kategori+başlık ile eşleşen iki GERÇEKTEN
    /// farklı tarif (aynı isimli iki "tavuklu salata") sessizce birleştirilip biri
    /// siliniyordu — geri alınamaz veri kaybı. Farklı kaynaklar artık ayrı kalır;
    /// aynı kaynaktan gelen gerçek tekrarlar hâlâ birleşir.
    private func duplicateKey(for recipe: Recipe) -> String {
        let source = recipe.urlString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(recipe.category.rawValue)|\(normalizedRecipeTitle(recipe.title))|\(source)"
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


// MARK: - Tarif görselleri (disk)

/// Tarif fotoğrafları — SwiftData'ya DOKUNMADAN diskte saklanır (CloudKit production
/// şeması kilitli; modele alan eklenmez, ProfileAvatarStore ile aynı desen).
/// Anahtar: createdAt (ms hassasiyet) — başlık düzenlense de sabit kalır.
enum RecipeImageStore {
    static let changed = Notification.Name("hercules.recipeImage.changed")

    private static let lock = NSLock()
    /// İç değer Optional: nil = "diskte yok" da önbelleğe alınır (her render'da disk I/O olmasın).
    nonisolated(unsafe) private static var cache: [String: NSImage?] = [:]

    private static var dir: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        let d = base.appendingPathComponent("Hercules/RecipeImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private static func key(_ r: Recipe) -> String {
        String(Int(r.createdAt.timeIntervalSince1970 * 1000))
    }

    private static func url(_ r: Recipe) -> URL? {
        dir?.appendingPathComponent("\(key(r)).jpg")
    }

    static func image(for r: Recipe) -> NSImage? {
        let k = key(r)
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[k] { return hit }
        let img = url(r).flatMap { NSImage(contentsOf: $0) }
        cache.updateValue(img, forKey: k)
        return img
    }

    static func hasImage(for r: Recipe) -> Bool { image(for: r) != nil }

    static func set(imageAt sourceURL: URL, for r: Recipe) {
        guard let dest = url(r), let img = NSImage(contentsOf: sourceURL),
              let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85]) else { return }
        try? jpg.write(to: dest)
        lock.lock(); cache.updateValue(img, forKey: key(r)); lock.unlock()
        NotificationCenter.default.post(name: changed, object: nil)
    }

    static func clear(for r: Recipe) {
        if let u = url(r) { try? FileManager.default.removeItem(at: u) }
        lock.lock(); cache.updateValue(nil, forKey: key(r)); lock.unlock()
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// NSOpenPanel ile görsel seçtir (sandbox yok — direkt dosya erişimi).
    @MainActor
    static func pickImage(for r: Recipe) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let picked = panel.url {
            set(imageAt: picked, for: r)
        }
    }
}
