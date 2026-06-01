import SwiftUI
import SwiftData

/// Mac "Koç" sayfası — iki mod:
///   • Genel Analiz: her sabah 08:00 üretilen detaylı koç raporu (rapor listesi + detay).
///   • Tarif: her gün 10:00 üretilen, internetten ARAŞTIRILMIŞ (kaynaklı) yüksek
///     proteinli bowl tarifi (tarif listesi + detay).
struct CoachView: View {
    enum Mode: String, CaseIterable { case analysis, recipe }

    @Environment(\.modelContext) private var ctx
    @Environment(\.openURL) private var openURL
    @Query(sort: \CoachReport.day, order: .reverse) private var reports: [CoachReport]
    @Query(sort: \CoachFocusItem.firstAdvisedAt) private var focusItems: [CoachFocusItem]
    @Query(sort: \CoachRecipe.day, order: .reverse) private var dailyRecipes: [CoachRecipe]

    @State private var mode: Mode = .analysis
    @State private var isGeneratingReport = false
    @State private var isGeneratingRecipe = false
    @State private var errorText: String?
    @State private var selectedReportID: PersistentIdentifier?
    @State private var selectedRecipeID: PersistentIdentifier?
    @State private var savedRecipeIDs: Set<PersistentIdentifier> = []

    // MARK: Derived
    private var todayReport: CoachReport? { reports.first { Calendar.current.isDateInToday($0.day) } }
    private var shownReport: CoachReport? {
        if let id = selectedReportID, let m = reports.first(where: { $0.persistentModelID == id }) { return m }
        return todayReport ?? reports.first
    }
    private var todayRecipe: CoachRecipe? { dailyRecipes.first { Calendar.current.isDateInToday($0.day) } }
    private var shownRecipe: CoachRecipe? {
        if let id = selectedRecipeID, let m = dailyRecipes.first(where: { $0.persistentModelID == id }) { return m }
        return todayRecipe ?? dailyRecipes.first
    }
    private var openItems: [CoachFocusItem] { focusItems.filter { $0.status.isOpen }.sorted { $0.firstAdvisedAt < $1.firstAdvisedAt } }
    private var resolvedItems: [CoachFocusItem] {
        focusItems.filter { $0.status == .resolved }.sorted { ($0.resolvedAt ?? .distantPast) > ($1.resolvedAt ?? .distantPast) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, Spacing.xxl).padding(.top, Spacing.xxl).padding(.bottom, Spacing.md)
            Picker("", selection: $mode) {
                Text("Genel Analiz").tag(Mode.analysis)
                Text("Tarif").tag(Mode.recipe)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 320)
            .padding(.horizontal, Spacing.xxl)
            .padding(.bottom, Spacing.lg)

            Rectangle().fill(Palette.border).frame(height: 0.6)

            switch mode {
            case .analysis: analysisContent
            case .recipe:   recipeContent
            }
        }
        .background(coachBackground)
        .onAppear { CoachEngine.maybeRunDaily(ctx: ctx) }
    }

    private var coachBackground: some View {
        ZStack(alignment: .topLeading) {
            Palette.background.ignoresSafeArea()
            LinearGradient(colors: [Palette.accent.opacity(0.10), Palette.background.opacity(0)], startPoint: .topLeading, endPoint: .center).ignoresSafeArea()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Koç").eyebrow()
                    Text("Günlük koç")
                        .font(Typography.display(36)).foregroundStyle(Palette.textPrimary)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Text(mode == .analysis
                         ? "Her sabah 08:00 verini okuyup detaylı, kaynaklı analiz çıkarır; önerdiklerini günden güne takip eder."
                         : "Her gün 10:00 yediklerine ve tariflerine bakıp internetten araştırıp kaynaklı bir yüksek proteinli bowl önerir.")
                        .font(Typography.body).foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true).frame(maxWidth: 660, alignment: .leading)
                }
                Spacer(minLength: Spacing.lg)
                generateButton
            }
            if let errorText {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                    Text(errorText).font(Typography.caption).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.warning.opacity(0.10)))
            }
        }
    }

    private var generateButton: some View {
        let generating = mode == .analysis ? isGeneratingReport : isGeneratingRecipe
        let title: String = {
            if mode == .analysis { return generating ? "Analiz ediliyor…" : (todayReport == nil ? "Bugünü analiz et" : "Yeniden analiz et") }
            return generating ? "Araştırılıyor…" : (todayRecipe == nil ? "Tarif öner" : "Yeni tarif öner")
        }()
        return Button { mode == .analysis ? generateReport() : generateRecipe() } label: {
            HStack(spacing: 8) {
                if generating { ProgressView().controlSize(.small) }
                else { Image(systemName: mode == .analysis ? "sparkles" : "fork.knife").font(.system(size: 12, weight: .semibold)) }
                Text(title).font(Typography.bodyBold)
            }
            .foregroundStyle(generating ? Palette.textSecondary : Palette.background)
            .padding(.horizontal, 15).padding(.vertical, 10)
            .background(Capsule(style: .continuous).fill(generating ? Palette.surfaceElevated : Palette.accent))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6))
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain).disabled(generating)
    }

    // MARK: - Analysis (rapor)

    private var analysisContent: some View {
        HStack(alignment: .top, spacing: 0) {
            reportListRail.frame(width: 300)
            Rectangle().fill(Palette.border).frame(width: 0.6)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    if let r = shownReport { reportCard(r) } else { emptyState(recipe: false) }
                    Spacer(minLength: 24)
                }
                .padding(Spacing.xxl).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var reportListRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Raporlar").eyebrow()
                    if reports.isEmpty {
                        Text("Henüz rapor yok.").font(Typography.caption).foregroundStyle(Palette.textTertiary).padding(.vertical, 4)
                    } else {
                        ForEach(reports.prefix(90)) { report in
                            dateRow(day: report.day,
                                    isSelected: shownReport?.persistentModelID == report.persistentModelID,
                                    preview: reportPreview(report.narrative)) {
                                selectedReportID = report.persistentModelID
                            }
                        }
                    }
                }
                if !openItems.isEmpty || !resolvedItems.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack { Text("Takip rotası").eyebrow(); Spacer(); Text("\(openItems.count) açık").font(Typography.label).foregroundStyle(Palette.textQuaternary) }
                        ForEach(openItems) { railFocusRow($0) }
                        ForEach(resolvedItems.prefix(4)) { railFocusRow($0) }
                    }
                }
            }
            .padding(Spacing.lg)
        }
        .background(Palette.surface.opacity(0.35))
    }

    private func railFocusRow(_ item: CoachFocusItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: statusIcon(item.status)).font(.system(size: 11, weight: .semibold)).foregroundStyle(statusTint(item.status)).frame(width: 16)
            Text(item.title).font(Typography.caption).foregroundStyle(item.status == .resolved ? Palette.textTertiary : Palette.textSecondary).lineLimit(2)
            Spacer(minLength: 4)
            Text(item.status == .resolved ? "✓" : "\(item.daysOpen)g").font(.system(size: 10, weight: .semibold)).foregroundStyle(statusTint(item.status)).fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 8).padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.surfaceElevated.opacity(item.status == .resolved ? 0.3 : 0.55)))
    }

    private func reportCard(_ report: CoachReport) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            detailHeader(title: Fmt.dateLong.string(from: report.day),
                         eyebrow: Calendar.current.isDateInToday(report.day) ? "Bugünün raporu" : "Rapor",
                         by: report.generatedBy, at: report.createdAt)
            metricRow(report)
            Rectangle().fill(Palette.border).frame(height: 0.6)
            Text(report.narrative)
                .font(Typography.body).foregroundStyle(Palette.textPrimary).lineSpacing(5)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Spacing.xl).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(Palette.surface.opacity(0.86)))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(Palette.borderStrong, lineWidth: 0.7))
    }

    @ViewBuilder
    private func metricRow(_ r: CoachReport) -> some View {
        let chips: [(String, String, Color)] = [
            r.weight.map { ("Kilo", "\(Fmt.num($0, digits: 1)) kg", Palette.textPrimary) },
            r.weeklyDelta.map { ("Haftalık", "\(Fmt.signed($0, digits: 1)) kg", $0 <= 0 ? Palette.positive : Palette.warning) },
            r.avgCalories.map { ("Ort. kcal", "\(Fmt.int($0))", Palette.textPrimary) },
            r.avgProtein.map { ("Ort. protein", "\(Fmt.int($0)) g", Palette.macroProtein) },
            r.sessionsLast30.map { ("30g antrenman", "\($0)", Palette.accent) }
        ].compactMap { $0 }
        if !chips.isEmpty { chipGrid(chips) }
    }

    // MARK: - Recipe (tarif)

    private var recipeContent: some View {
        HStack(alignment: .top, spacing: 0) {
            recipeListRail.frame(width: 300)
            Rectangle().fill(Palette.border).frame(width: 0.6)
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    if let r = shownRecipe { recipeCard(r) } else { emptyState(recipe: true) }
                    Spacer(minLength: 24)
                }
                .padding(Spacing.xxl).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var recipeListRail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Tarifler").eyebrow()
                if dailyRecipes.isEmpty {
                    Text("Henüz tarif yok.").font(Typography.caption).foregroundStyle(Palette.textTertiary).padding(.vertical, 4)
                } else {
                    ForEach(dailyRecipes.prefix(90)) { r in
                        dateRow(day: r.day, isSelected: shownRecipe?.persistentModelID == r.persistentModelID, preview: r.title) { selectedRecipeID = r.persistentModelID }
                    }
                }
            }
            .padding(Spacing.lg)
        }
        .background(Palette.surface.opacity(0.35))
    }

    private func recipeCard(_ recipe: CoachRecipe) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            detailHeader(title: recipe.title,
                         eyebrow: Calendar.current.isDateInToday(recipe.day) ? "Bugünün tarifi" : Fmt.dateLong.string(from: recipe.day),
                         by: recipe.generatedBy, at: recipe.createdAt, titleLineLimit: 2)

            if let summary = recipe.summary, !summary.isEmpty {
                Text(summary).font(Typography.body).foregroundStyle(Palette.textSecondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }

            recipeMacroRow(recipe)
            recipeMetaRow(recipe)
            sourceRow(recipe)

            Rectangle().fill(Palette.border).frame(height: 0.6)

            if let ing = recipe.ingredientsText, !ing.isEmpty { recipeSection("Malzemeler", ing) }
            if let ins = recipe.instructionsText, !ins.isEmpty { recipeSection("Yapılış", ins) }

            HStack {
                let saved = savedRecipeIDs.contains(recipe.persistentModelID)
                Button { saveRecipeToLibrary(recipe) } label: {
                    HStack(spacing: 7) {
                        Image(systemName: saved ? "checkmark" : "bookmark").font(.system(size: 11, weight: .semibold))
                        Text(saved ? "Tariflerime kaydedildi" : "Tariflerime kaydet").font(Typography.captionBold)
                    }
                    .foregroundStyle(saved ? Palette.positive : Palette.textPrimary)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule(style: .continuous).fill(saved ? Palette.positive.opacity(0.12) : Color.white.opacity(0.06)))
                    .overlay(Capsule(style: .continuous).strokeBorder(Palette.border, lineWidth: 0.6))
                }
                .buttonStyle(.plain).disabled(saved)
                Spacer()
            }
        }
        .padding(Spacing.xl).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(Palette.surface.opacity(0.86)))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(Palette.borderStrong, lineWidth: 0.7))
    }

    @ViewBuilder
    private func recipeMacroRow(_ r: CoachRecipe) -> some View {
        let chips: [(String, String, Color)] = [
            r.calories.map { ("Kalori", "\(Fmt.int($0))", Palette.textPrimary) },
            r.protein.map { ("Protein", "\(Fmt.int($0)) g", Palette.macroProtein) },
            r.carbs.map { ("Karb", "\(Fmt.int($0)) g", Palette.macroCarbs) },
            r.fat.map { ("Yağ", "\(Fmt.int($0)) g", Palette.macroFat) }
        ].compactMap { $0 }
        if !chips.isEmpty { chipGrid(chips) }
    }

    @ViewBuilder
    private func recipeMetaRow(_ r: CoachRecipe) -> some View {
        let tags: [(String, String)] = [
            r.servings.map { ("person.2.fill", "\($0) porsiyon") },
            r.prepMinutes.map { ("clock.fill", "\($0) dk") }
        ].compactMap { $0 }
        if !tags.isEmpty {
            HStack(spacing: Spacing.sm) {
                ForEach(Array(tags.enumerated()), id: \.offset) { _, t in
                    HStack(spacing: 5) {
                        Image(systemName: t.0).font(.system(size: 10, weight: .semibold))
                        Text(t.1).font(Typography.captionBold)
                    }
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule(style: .continuous).fill(Palette.surfaceElevated.opacity(0.7)))
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder
    private func sourceRow(_ recipe: CoachRecipe) -> some View {
        if let urlString = recipe.sourceURL, let url = URL(string: urlString) {
            Button { openURL(url) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "link").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("KAYNAK").font(Typography.label).tracking(0.6).foregroundStyle(Palette.textQuaternary)
                        Text(recipe.sourceName ?? urlString).font(Typography.captionBold).foregroundStyle(Palette.textPrimary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer(minLength: 8)
                    Text("Aç").font(Typography.captionBold).foregroundStyle(Palette.accent)
                    Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.accent)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.accent.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.accent.opacity(0.3), lineWidth: 0.6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.warning)
                Text("Kaynak belirtilmedi — yeniden öner ile tekrar dene.").font(Typography.caption).foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.warning.opacity(0.10)))
        }
    }

    private func recipeSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased()).font(Typography.captionBold).tracking(0.6).foregroundStyle(Palette.textSecondary)
            Text(text).font(Typography.body).foregroundStyle(Palette.textPrimary).lineSpacing(4)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func saveRecipeToLibrary(_ recipe: CoachRecipe) {
        guard !savedRecipeIDs.contains(recipe.persistentModelID) else { return }
        let category = RecipeCategory(rawValue: recipe.category ?? "breakfast") ?? .breakfast
        let r = Recipe(
            title: recipe.title,
            urlString: recipe.sourceURL ?? "",
            category: category,
            summary: recipe.summary,
            ingredientsText: recipe.ingredientsText,
            instructionsText: recipe.instructionsText,
            servings: recipe.servings,
            prepMinutes: recipe.prepMinutes,
            calories: recipe.calories,
            protein: recipe.protein,
            carbs: recipe.carbs,
            fat: recipe.fat
        )
        ctx.insert(r)
        ctx.saveOrReport()
        BackupService.shared.exportAsync(from: ctx)
        savedRecipeIDs.insert(recipe.persistentModelID)
    }

    // MARK: - Shared bits

    private func detailHeader(title: String, eyebrow: String, by: String?, at createdAt: Date, titleLineLimit: Int = 1) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(eyebrow).eyebrow()
                Text(title).font(Typography.title).foregroundStyle(Palette.textPrimary).lineLimit(titleLineLimit).minimumScaleFactor(0.7).fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let by { Text(by).font(Typography.caption).foregroundStyle(Palette.textTertiary).lineLimit(1) }
                Text("\(Fmt.timeShort.string(from: createdAt)) üretildi").font(Typography.caption).foregroundStyle(Palette.textQuaternary).lineLimit(1)
            }
        }
    }

    private func chipGrid(_ chips: [(String, String, Color)]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 122), spacing: Spacing.md, alignment: .leading)], alignment: .leading, spacing: Spacing.md) {
            ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in
                VStack(alignment: .leading, spacing: 3) {
                    Text(chip.0.uppercased()).font(Typography.label).tracking(0.6).foregroundStyle(Palette.textQuaternary)
                    Text(chip.1).font(Typography.monoLarge).foregroundStyle(chip.2).lineLimit(1).minimumScaleFactor(0.6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.surfaceElevated.opacity(0.7)))
            }
        }
    }

    private func dateRow(day: Date, isSelected: Bool, preview: String, action: @escaping () -> Void) -> some View {
        let isToday = Calendar.current.isDateInToday(day)
        return Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(Fmt.dateLong.string(from: day)).font(Typography.bodyBold)
                            .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary).lineLimit(1).minimumScaleFactor(0.82)
                        if isToday {
                            Text("BUGÜN").font(.system(size: 8, weight: .bold)).tracking(0.5).foregroundStyle(Palette.accent)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Capsule(style: .continuous).fill(Palette.accent.opacity(0.14)))
                        }
                    }
                    Text(preview).font(Typography.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 9).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(isSelected ? Palette.surfaceElevated.opacity(0.92) : Color.clear))
            .overlay(alignment: .leading) { if isSelected { Capsule(style: .continuous).fill(Palette.accent).frame(width: 2.5).padding(.vertical, 9) } }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func emptyState(recipe: Bool) -> some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.lg, style: .continuous).fill(Palette.accent.opacity(0.12)).frame(width: 54, height: 54)
                Image(systemName: recipe ? "fork.knife" : "sparkles").font(.system(size: 24, weight: .light)).foregroundStyle(Palette.accent)
            }
            Text(recipe ? "Henüz tarif yok" : "Henüz koç raporu yok").font(Typography.title).foregroundStyle(Palette.textPrimary)
            Text(recipe
                 ? "İlk tarifi öner — yediklerine ve tariflerine bakıp internetten araştırarak kaynaklı, yüksek proteinli bir bowl çıkarır. Sonra her gün 10:00 otomatik yeniler."
                 : "İlk analizi başlat — tüm ölçüm, beslenme ve antrenman verini okuyup kaynaklı, detaylı bir koç raporu çıkarır. Sonra her sabah otomatik yeniler.")
                .font(Typography.body).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 540, alignment: .leading)
            generateButton.padding(.top, 4)
        }
        .padding(Spacing.xxl).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).fill(Palette.surface.opacity(0.7)))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.55))
    }

    private func reportPreview(_ narrative: String) -> String {
        String(narrative.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines).prefix(48))
    }

    private func statusIcon(_ s: CoachItemStatus) -> String {
        switch s {
        case .advised:   return "exclamationmark.circle.fill"
        case .improving: return "arrow.up.forward.circle.fill"
        case .resolved:  return "checkmark.seal.fill"
        case .dropped:   return "minus.circle"
        }
    }
    private func statusTint(_ s: CoachItemStatus) -> Color {
        switch s {
        case .advised:   return Palette.warning
        case .improving: return Palette.accent
        case .resolved:  return Palette.positive
        case .dropped:   return Palette.textTertiary
        }
    }

    // MARK: - Actions

    private func generateReport() {
        guard !isGeneratingReport else { return }
        isGeneratingReport = true; errorText = nil
        Task { @MainActor in
            do { let r = try await CoachEngine.generateDailyReport(ctx: ctx); selectedReportID = r.persistentModelID }
            catch { errorText = error.localizedDescription }
            isGeneratingReport = false
        }
    }

    private func generateRecipe() {
        guard !isGeneratingRecipe else { return }
        isGeneratingRecipe = true; errorText = nil
        Task { @MainActor in
            do { let r = try await CoachEngine.generateDailyRecipe(ctx: ctx); selectedRecipeID = r.persistentModelID }
            catch { errorText = error.localizedDescription }
            isGeneratingRecipe = false
        }
    }
}
