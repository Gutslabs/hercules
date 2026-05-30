import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct AssistantMark: View {
    var size: CGFloat
    var cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(ChatChrome.panelRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(ChatChrome.borderStrong, lineWidth: 0.6)
                )
            Image(systemName: "sparkles")
                .font(.system(size: max(10, size * 0.38), weight: .semibold))
                .foregroundStyle(ChatChrome.primary)
        }
        .frame(width: size, height: size)
    }
}

struct FoodPresetWidget: View {
    let presets: [FoodPreset]
    @Binding var query: String
    let feedback: String?
    var onAdd: (FoodPreset, Double) -> Void

    private var filteredPresets: [FoodPreset] {
        let q = normalized(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !q.isEmpty else { return presets }
        return presets.filter { preset in
            normalized([preset.brand, preset.name, preset.category, preset.note, preset.searchText].joined(separator: " "))
                .contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(ChatChrome.panelRaised)
                            .frame(width: 34, height: 34)
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(ChatChrome.borderStrong, lineWidth: 0.5))
                        Image(systemName: "takeoutbag.and.cup.and.straw")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ChatChrome.white)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text("Presetler")
                            .font(Typography.bodyBold)
                            .foregroundStyle(ChatChrome.primary)
                        Text("Sık kullandıklarını bugüne ekle")
                            .font(Typography.caption)
                            .foregroundStyle(ChatChrome.tertiary)
                    }

                    Spacer(minLength: 0)

                    Text("\(filteredPresets.count)")
                        .font(Typography.captionBold)
                        .foregroundStyle(ChatChrome.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(ChatChrome.whiteSoft))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("ARA")
                        .font(Typography.label)
                        .tracking(0.8)
                        .foregroundStyle(ChatChrome.quaternary)
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ChatChrome.tertiary)
                        TextField("Protein, marka, ürün ara", text: $query)
                            .textFieldStyle(.plain)
                            .font(Typography.body)
                            .foregroundStyle(ChatChrome.primary)
                    }
                    .padding(.horizontal, 11)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(ChatChrome.panelRaised)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(ChatChrome.border, lineWidth: 0.5)
                    )
                }

                if let feedback {
                    Label(feedback, systemImage: "checkmark.circle.fill")
                        .font(Typography.captionBold)
                        .foregroundStyle(ChatChrome.positive)
                        .lineLimit(2)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(ChatChrome.positive.opacity(0.12))
                        )
                }
            }
            .padding(14)

            Hairline()

            if filteredPresets.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(ChatChrome.quaternary)
                    Text("Preset bulunamadı")
                        .font(Typography.bodyBold)
                        .foregroundStyle(ChatChrome.secondary)
                    Text("Aramayı biraz kısaltmayı dene.")
                        .font(Typography.caption)
                        .foregroundStyle(ChatChrome.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 190)
                .padding(24)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredPresets) { preset in
                            FoodPresetRow(preset: preset, onAdd: onAdd)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .background(ChatChrome.background)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(ChatChrome.borderStrong, lineWidth: 0.6)
        )
    }

    private func normalized(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "tr_TR"))
            .lowercased(with: Locale(identifier: "tr_TR"))
    }
}

struct FoodPresetRow: View {
    let preset: FoodPreset
    var onAdd: (FoodPreset, Double) -> Void

    private var defaultServings: Double {
        max(1, preset.defaultServings)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(ChatChrome.whiteSoft)
                        .frame(width: 34, height: 34)
                    Image(systemName: "bolt.heart")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(ChatChrome.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(preset.brand)
                        .font(Typography.captionBold)
                        .foregroundStyle(ChatChrome.tertiary)
                    Text(preset.name)
                        .font(Typography.bodyBold)
                        .foregroundStyle(ChatChrome.primary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(Fmt.int(preset.servingGrams)) g / \(preset.servingLabel)")
                        .font(Typography.caption)
                        .foregroundStyle(ChatChrome.tertiary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 1) {
                    Text(Fmt.int(preset.calories(for: defaultServings)))
                        .font(Typography.monoLarge)
                        .foregroundStyle(ChatChrome.primary)
                    Text("kcal")
                        .font(Typography.caption)
                        .foregroundStyle(ChatChrome.tertiary)
                }
            }

            Text(preset.note)
                .font(Typography.caption)
                .foregroundStyle(ChatChrome.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                presetMacroChip("P", preset.protein(for: defaultServings))
                presetMacroChip("K", preset.carbs(for: defaultServings))
                presetMacroChip("Y", preset.fat(for: defaultServings))
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Button {
                    onAdd(preset, defaultServings)
                } label: {
                    Label(preset.servingCountText(defaultServings), systemImage: "plus")
                        .font(Typography.captionBold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ChatChrome.ink)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: Radius.sm - 2).fill(ChatChrome.white))

                Button {
                    onAdd(preset, 1)
                } label: {
                    Text(preset.servingCountText(1))
                        .font(Typography.captionBold)
                        .frame(width: 82)
                }
                .buttonStyle(.plain)
                .foregroundStyle(ChatChrome.secondary)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: Radius.sm - 2).fill(ChatChrome.whiteSoft))
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(ChatChrome.assistantBubble)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(ChatChrome.border, lineWidth: 0.5)
        )
    }

    private func presetMacroChip(_ label: String, _ value: Double?) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(Typography.captionBold)
                .foregroundStyle(ChatChrome.tertiary)
            Text(value.map { "\(Fmt.num($0, digits: 1))g" } ?? "—")
                .font(Typography.captionBold)
                .foregroundStyle(ChatChrome.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(ChatChrome.whiteSoft))
    }
}

struct ChatNearBottomKey: PreferenceKey {
    static var defaultValue = true

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

struct ChatHintFlow<Content: View>: View {
    var spacing: CGFloat = 5
    @ViewBuilder var content: Content

    var body: some View {
        ChatHintWrappingHStack(spacing: spacing) {
            content
        }
    }
}

struct ChatHintWrappingHStack: Layout {
    var spacing: CGFloat = 5

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? 0
        guard maxWidth > 0 else {
            let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            return CGSize(
                width: sizes.map(\.width).reduce(0, +) + spacing * CGFloat(max(0, sizes.count - 1)),
                height: sizes.map(\.height).max() ?? 0
            )
        }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var measuredWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            measuredWidth = max(measuredWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }

        return CGSize(width: measuredWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct MessageBubble: View {
    let turn: ChatTurn
    let isStreaming: Bool
    var onSave: () -> Void
    var onConfirmAction: (AIAppAction) -> Void
    var onRejectAction: (AIAppAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if turn.role == .user {
                Spacer(minLength: 32)
            } else {
                AssistantMark(size: 22, cornerRadius: 7)
                .padding(.top, 2)
            }

            VStack(alignment: .leading, spacing: 6) {
                if let q = turn.searchedFor {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Web'de arandı: \"\(q)\"")
                            .font(Typography.caption)
                    }
                    .foregroundStyle(ChatChrome.tertiary)
                    .padding(.bottom, 2)
                }
                // Streaming sırasında satır sonunda blinking cursor.
                if isStreaming && !turn.text.isEmpty {
                    Text(turn.text + " ▍")
                        .font(Typography.body)
                        .foregroundStyle(ChatChrome.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(turn.text)
                        .font(Typography.body)
                        .foregroundStyle(ChatChrome.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }

                if let food = turn.food {
                    foodCard(food)
                }
                if !turn.actions.isEmpty {
                    ForEach(turn.actions) { action in
                        actionCard(action)
                    }
                }
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                bubbleShape
                    .fill(turn.role == .user ? ChatChrome.userBubble : ChatChrome.assistantBubble)
            )
            .overlay(
                bubbleShape
                    .strokeBorder(turn.role == .user ? ChatChrome.borderStrong : ChatChrome.border, lineWidth: 0.5)
            )

            if turn.role == .assistant {
                Spacer(minLength: 32)
            }
        }
    }

    /// Asimetrik bubble köşeleri — chat app pattern'i (mesaj sahibine yakın köşe sivri).
    private var bubbleShape: UnevenRoundedRectangle {
        let r: CGFloat = Radius.md
        let small: CGFloat = 4
        if turn.role == .user {
            return UnevenRoundedRectangle(
                topLeadingRadius: r,
                bottomLeadingRadius: r,
                bottomTrailingRadius: small,
                topTrailingRadius: r,
                style: .continuous
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: small,
                bottomLeadingRadius: r,
                bottomTrailingRadius: r,
                topTrailingRadius: r,
                style: .continuous
            )
        }
    }

    private func foodCard(_ food: AIFoodResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name ?? "Yemek")
                        .font(Typography.bodyBold)
                        .foregroundStyle(ChatChrome.primary)
                    if let g = food.grams {
                        Text("\(Fmt.int(g)) g")
                            .font(Typography.caption)
                            .foregroundStyle(ChatChrome.tertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(Fmt.int(food.calories ?? 0))
                            .font(Typography.monoLarge)
                            .foregroundStyle(ChatChrome.primary)
                        Text("kcal")
                            .font(Typography.caption)
                            .foregroundStyle(ChatChrome.tertiary)
                    }
                }
            }
            if food.protein_g != nil || food.carbs_g != nil || food.fat_g != nil {
                HStack(spacing: 10) {
                    macroChip("P", food.protein_g)
                    macroChip("K", food.carbs_g)
                    macroChip("Y", food.fat_g)
                }
            }
            Button(action: onSave) {
                HStack(spacing: 5) {
                    Image(systemName: turn.saved ? "checkmark" : "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text(turn.saved ? "Eklendi" : "Bugüne ekle")
                        .font(Typography.bodyBold)
                }
                .foregroundStyle(turn.saved ? ChatChrome.secondary : ChatChrome.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                        .fill(turn.saved ? ChatChrome.whiteSoft : ChatChrome.white)
                )
            }
            .buttonStyle(.plain)
            .disabled(turn.saved)
        }
    }

    private func actionCard(_ action: AIAppAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: actionIcon(action))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(actionTint(action))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(actionTint(action).opacity(0.14)))

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(action.displayTitle)
                            .font(Typography.bodyBold)
                            .foregroundStyle(ChatChrome.primary)
                        statusPill(action)
                    }
                    Text(action.displaySummary)
                        .font(Typography.caption)
                        .foregroundStyle(ChatChrome.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let result = action.resultMessage, !result.isEmpty {
                        Text(result)
                            .font(Typography.caption)
                            .foregroundStyle(action.status == .failed ? Color.red.opacity(0.85) : ChatChrome.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }

            if action.status == .pending && action.requiresConfirmation {
                HStack(spacing: 8) {
                    Button {
                        onConfirmAction(action)
                    } label: {
                        Label("Onayla", systemImage: "checkmark")
                            .font(Typography.captionBold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ChatChrome.ink)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Radius.sm - 2).fill(ChatChrome.white))

                    Button {
                        onRejectAction(action)
                    } label: {
                        Text("Vazgeç")
                            .font(Typography.captionBold)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(ChatChrome.secondary)
                    .padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: Radius.sm - 2).fill(ChatChrome.whiteSoft))
                }
            }
        }
        .padding(.top, 2)
    }

    private func statusPill(_ action: AIAppAction) -> some View {
        Text(statusText(action.status, requiresConfirmation: action.requiresConfirmation))
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(actionTint(action))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Capsule().fill(actionTint(action).opacity(0.13)))
    }

    private func statusText(_ status: AIAppActionStatus, requiresConfirmation: Bool) -> String {
        switch status {
        case .pending: return requiresConfirmation ? "ONAY BEKLİYOR" : "BEKLİYOR"
        case .applied: return "UYGULANDI"
        case .rejected: return "VAZGEÇİLDİ"
        case .failed: return "HATA"
        }
    }

    private func actionIcon(_ action: AIAppAction) -> String {
        switch action.status {
        case .applied: return "checkmark.circle.fill"
        case .rejected: return "xmark.circle"
        case .failed: return "exclamationmark.triangle.fill"
        case .pending:
            switch action.tool {
            case .logFood: return "plus.circle"
            case .addRecipe: return "book.closed"
            case .updateWorkoutPlan: return "dumbbell"
            }
        }
    }

    private func actionTint(_ action: AIAppAction) -> Color {
        switch action.status {
        case .applied: return Color(red: 0.54, green: 0.82, blue: 0.68)
        case .rejected: return ChatChrome.tertiary
        case .failed: return Color(red: 1.0, green: 0.45, blue: 0.42)
        case .pending: return action.requiresConfirmation ? ChatChrome.white : ChatChrome.secondary
        }
    }

    private func macroChip(_ letter: String, _ value: Double?) -> some View {
        HStack(spacing: 3) {
            Circle().fill(ChatChrome.quaternary).frame(width: 5, height: 5)
            Text(letter).font(Typography.caption).foregroundStyle(ChatChrome.tertiary)
            Text(value.map { "\(Fmt.int($0))g" } ?? "—")
                .font(Typography.caption)
                .foregroundStyle(ChatChrome.secondary)
        }
    }
}

struct TypingIndicator: View {
    var searchQuery: String? = nil
    @State private var phase = 0
    @State private var timer: Timer? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let q = searchQuery {
                Image(systemName: "globe")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(ChatChrome.white)
                Text("Web'de aranıyor: \"\(q)\"")
                    .font(Typography.caption)
                    .foregroundStyle(ChatChrome.secondary)
            } else {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(ChatChrome.tertiary)
                        .frame(width: 5, height: 5)
                        .opacity(phase == i ? 1 : 0.3)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(ChatChrome.assistantBubble)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(ChatChrome.border, lineWidth: 0.5)
        )
        .onAppear {
            // Timer @State'e bağlı → onDisappear'da invalidate'lenir.
            // Daha önce her appear yeni timer açıyordu, leak yapıyordu.
            timer?.invalidate()
            let t = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                Task { @MainActor in
                    phase = (phase + 1) % 3
                }
            }
            timer = t
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }
}

struct FloatingChatButton: View {
    var isOpen: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.96), Color.white.opacity(0.72)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.45), radius: 12, y: 5)
                Image(systemName: isOpen ? "xmark" : "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(ChatChrome.ink)
            }
            .scaleEffect(hovering ? 1.06 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Kalori Asistanı")
    }
}
