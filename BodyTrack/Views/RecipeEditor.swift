import SwiftUI
import SwiftData

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
                .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.fieldFill))
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
