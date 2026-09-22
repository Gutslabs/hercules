import SwiftUI
import LucideKit
import SwiftData

struct EmptyRecipesState: View {
    var action: () -> Void
    var body: some View {
        VStack(spacing: Spacing.lg) {
            Lucide(sf: "fork.knife", size: 28)
                .foregroundStyle(Palette.textTertiary)
            Text("Henüz tarif yok")
                .font(Typography.title)
                .foregroundStyle(Palette.textPrimary)
            PrimaryButton(title: "İlk tarifi ekle", systemImage: "plus", action: action)
                .frame(width: 220)
        }
        .padding(Spacing.xxxl)
        .frame(maxWidth: .infinity)
        .dashboardCard()
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
            Lucide(sf: "magnifyingglass", size: 25)
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
                Label { Text("Filtreleri temizle") } icon: { Lucide(sf: "xmark.circle") }
                    .font(Typography.captionBold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.surfaceElevated)
            )
        }
        .padding(Spacing.xxxl)
        .frame(maxWidth: .infinity)
        .dashboardCard()
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

    @State private var confirmingDelete = false

    var body: some View {
        SadeSheet(title: isEditing ? "Tarifi düzenle" : "Yeni tarif", onClose: { dismiss() }) {
            HStack(alignment: .top, spacing: 0) {
                identityColumn
                    .frame(width: 430)
                SadeRule(vertical: true)
                contentColumn
            }
            .overlay(alignment: .top) { SadeRule() }
            .padding(.top, 18)
        } footerLeading: {
            if isEditing, onDelete != nil {
                SadeButton(title: "Tarifi sil", role: .destructive) { confirmingDelete = true }
            }
        } footerTrailing: {
            SadeButton(title: "İptal") { dismiss() }
            SadeButton(title: isEditing ? "Kaydet" : "Ekle", role: .primary, enabled: canSave) {
                save()
                dismiss()
            }
        }
        .frame(width: 980, height: 660)
        .confirmationDialog("Tarif silinsin mi?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Tarifi Sil", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("Vazgeç", role: .cancel) {}
        }
    }

    private var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Sol: kimlik · servis · makro

    private var identityColumn: some View {
        VStack(alignment: .leading, spacing: 18) {
            SadeField(label: "Başlık") {
                TextField("", text: $title, prompt: Text("ör: Yoğurtlu tavuklu bulgur bowl").foregroundStyle(Palette.textTertiary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
            }
            VStack(alignment: .leading, spacing: 6) {
                label("Kategori")
                HStack(spacing: 10) {
                    SadeSegmented(options: RecipeCategory.allCases.map { (value: $0, label: $0 == .dinner ? "Akşam" : $0.label) },
                                  selection: $category)
                    Button { isFavorite.toggle() } label: {
                        Lucide(sf: isFavorite ? "heart.fill" : "heart", size: 15)
                            .foregroundStyle(isFavorite ? Palette.negative : Palette.textTertiary)
                            .frame(width: 38, height: 38)
                            .sadeBox(radius: 10)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isFavorite ? "Favoriden çıkar" : "Favori")
                }
            }
            SadeField(label: "Kaynak") {
                TextField("", text: $urlString, prompt: Text("isteğe bağlı").foregroundStyle(Palette.textTertiary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                Lucide(sf: "link", size: 13)
                    .foregroundStyle(Palette.textTertiary)
            }
            HStack(spacing: 12) {
                intStepper("Porsiyon", value: $servings, unit: nil, step: 1)
                intStepper("Hazırlık", value: $prepMinutes, unit: "dk", step: 5)
            }
            VStack(alignment: .leading, spacing: 8) {
                label("Makro")
                HStack(spacing: 8) {
                    macroBox($caloriesText, unit: "kcal")
                    macroBox($proteinText, unit: "P")
                    macroBox($carbsText, unit: "K")
                    macroBox($fatText, unit: "Y")
                }
                SadeMacroBar(protein: optionalDouble(proteinText), carbs: optionalDouble(carbsText), fat: optionalDouble(fatText), height: 6)
                    .padding(.top, 4)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    // MARK: Sağ: özet · malzemeler · yapılış

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            editor("Özet", text: $summary, height: 62)
            editor("Malzemeler", text: $ingredientsText, height: 170)
            editor("Yapılış", text: $instructionsText, height: nil)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.textTertiary)
    }

    private func editor(_ title: String, text: Binding<String>, height: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            label(title)
            TextEditor(text: text)
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.textPrimary)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 7)
                .padding(.vertical, 8)
                .frame(height: height)
                .frame(maxHeight: height == nil ? .infinity : nil)
                .sadeBox(radius: 10)
        }
    }

    private func intStepper(_ title: String, value: Binding<Int>, unit: String?, step: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            label(title)
            SadeStepper(unit: unit, width: 181) {
                value.wrappedValue = max(0, value.wrappedValue - step)
            } increment: {
                value.wrappedValue += step
            } field: {
                TextField("", value: value, format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(width: 44)
            }
        }
    }

    private func macroBox(_ text: Binding<String>, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            TextField("", text: text, prompt: Text("0").foregroundStyle(Palette.textQuaternary))
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
            Text(unit)
                .font(.system(size: 12))
                .foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .leading)
        .sadeBox(radius: 10)
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
