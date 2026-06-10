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

/// V1 preset popover'ı — kompakt satırlar: eyebrow başlık + arama, hairline ayraçlı
/// satır listesi (marka/ad/makro solda · kcal + ölçek pill'leri sağda), mikro dipnot.
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
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("PRESETLER")
                        .font(Typography.label)
                        .tracking(0.9)
                        .foregroundStyle(ChatChrome.quaternary)
                    Text("sık kullandıklarını bugüne ekle")
                        .font(Typography.caption)
                        .foregroundStyle(ChatChrome.tertiary)
                    Spacer(minLength: 0)
                    Text("\(filteredPresets.count)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(ChatChrome.primary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(Capsule().fill(ChatChrome.panelRaised))
                        .overlay(Capsule().strokeBorder(ChatChrome.border, lineWidth: 0.5))
                }

                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ChatChrome.tertiary)
                    TextField("Protein, marka, ürün ara", text: $query)
                        .textFieldStyle(.plain)
                        .font(Typography.body)
                        .foregroundStyle(ChatChrome.primary)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(ChatChrome.panelRaised.opacity(0.55))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(ChatChrome.border, lineWidth: 0.55)
                )

                if let feedback {
                    Label(feedback, systemImage: "checkmark.circle.fill")
                        .font(Typography.captionBold)
                        .foregroundStyle(ChatChrome.positive)
                        .lineLimit(2)
                }
            }
            .padding(EdgeInsets(top: 13, leading: 14, bottom: 11, trailing: 14))

            Hairline()

            if filteredPresets.isEmpty {
                VStack(spacing: 6) {
                    Text("Preset bulunamadı")
                        .font(Typography.bodyBold)
                        .foregroundStyle(ChatChrome.secondary)
                    Text("Aramayı biraz kısaltmayı dene.")
                        .font(Typography.caption)
                        .foregroundStyle(ChatChrome.tertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
                .padding(20)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(filteredPresets.enumerated()), id: \.element.id) { i, preset in
                            if i > 0 { Hairline().padding(.horizontal, 14) }
                            FoodPresetRow(preset: preset, onAdd: onAdd)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Hairline()

            Text("Eklenen kayıt bugünün günlüğüne düşer · sağdaki buton varsayılan ölçeği ekler")
                .font(.system(size: 9.5))
                .foregroundStyle(ChatChrome.quaternary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .frame(maxWidth: .infinity, alignment: .leading)
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

/// V1 kompakt preset satırı. Not (varsa) hover'da görünür.
struct FoodPresetRow: View {
    let preset: FoodPreset
    var onAdd: (FoodPreset, Double) -> Void

    private var defaultServings: Double {
        max(1, preset.defaultServings)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if !preset.brand.isEmpty {
                    Text(preset.brand.uppercased(with: Locale(identifier: "tr_TR")))
                        .font(Typography.label)
                        .tracking(0.8)
                        .foregroundStyle(ChatChrome.quaternary)
                }
                Text(preset.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ChatChrome.primary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                macroLine
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 8) {
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(Fmt.int(preset.calories(for: defaultServings)))
                        .font(.system(size: 15, weight: .regular, design: .monospaced))
                        .foregroundStyle(ChatChrome.primary)
                    Text("kcal")
                        .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(ChatChrome.quaternary)
                }
                HStack(spacing: 6) {
                    servingButton(preset.servingCountText(1), prominent: false) {
                        onAdd(preset, 1)
                    }
                    servingButton("+ " + preset.servingCountText(defaultServings), prominent: true) {
                        onAdd(preset, defaultServings)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
        .help(preset.note)
    }

    private var macroLine: some View {
        HStack(spacing: 4) {
            macroPair("P", preset.protein(for: defaultServings))
            Text("·").font(.system(size: 10.5)).foregroundStyle(ChatChrome.quaternary)
            macroPair("K", preset.carbs(for: defaultServings))
            Text("·").font(.system(size: 10.5)).foregroundStyle(ChatChrome.quaternary)
            macroPair("Y", preset.fat(for: defaultServings))
            Text("· \(Fmt.int(preset.servingGrams)) g / \(preset.servingLabel)")
                .font(.system(size: 10.5))
                .foregroundStyle(ChatChrome.quaternary)
        }
        .lineLimit(1)
        .padding(.top, 2)
    }

    private func macroPair(_ letter: String, _ value: Double?) -> some View {
        HStack(spacing: 3) {
            Text(letter)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ChatChrome.tertiary)
            Text(value.map { Fmt.num($0, digits: 1) } ?? "—")
                .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                .foregroundStyle(ChatChrome.secondary)
        }
    }

    private func servingButton(_ title: String, prominent: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(prominent ? ChatChrome.ink : ChatChrome.secondary)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(prominent ? ChatChrome.white : ChatChrome.panelRaised.opacity(0.7))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(prominent ? Color.clear : ChatChrome.border, lineWidth: 0.6)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

    /// V1 "Tek Akış": yalnızca kullanıcı balonda; asistan düz metin + mercan nokta işareti.
    var body: some View {
        if turn.role == .user {
            userRow
        } else {
            assistantRow
        }
    }

    private var userRow: some View {
        HStack(alignment: .top, spacing: 8) {
            Spacer(minLength: 32)
            Text(turn.text)
                .font(Typography.body)
                .foregroundStyle(ChatChrome.primary)
                .lineSpacing(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .padding(.horizontal, 15)
                .padding(.vertical, 10)
                .background(userBubbleShape.fill(ChatChrome.userBubble))
                .frame(maxWidth: 460, alignment: .trailing)
        }
    }

    private var assistantRow: some View {
        HStack(alignment: .top, spacing: 13) {
            Circle()
                .fill(ChatChrome.accent)
                .frame(width: 6, height: 6)
                .padding(.top, 7)

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
                // Streaming sırasında satır sonunda blinking cursor (ham metin — token
                // başına markdown parse etmemek için). Bitince markdown'a render edilir.
                if isStreaming && !turn.text.isEmpty {
                    Text(turn.text + " ▍")
                        .font(Typography.body)
                        .foregroundStyle(ChatChrome.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else if !turn.text.isEmpty {
                    MarkdownText(text: turn.text)
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
            .lineSpacing(3)
            .frame(maxWidth: 680, alignment: .leading)

            Spacer(minLength: 0)
        }
    }

    /// Kullanıcı balonu — sahibine yakın köşe (sağ alt) sivri.
    private var userBubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 14,
            bottomLeadingRadius: 14,
            bottomTrailingRadius: 4,
            topTrailingRadius: 14,
            style: .continuous
        )
    }

    /// V1 öğün kartı: isim + gram + makro noktaları · mono kcal · altta "Günlüğe eklendi" şeridi.
    private func foodCard(_ food: AIFoodResult) -> some View {
        VStack(spacing: 0) {
            // Dar yüzeylerde (chat sidebar/dock) makrolar isim kolonuna sıkışıp karakter
            // bazında kırılmasın: makro satırı kartın TAM genişliğini kullanır, her makro
            // bölünmez birimdir ve gerekirse satır olarak sarar.
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(food.name ?? "Yemek")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(ChatChrome.primary)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                        if let g = food.grams {
                            Text("\(Fmt.int(g)) g")
                                .font(Typography.caption)
                                .foregroundStyle(ChatChrome.quaternary)
                        }
                    }
                    Spacer(minLength: 8)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(Fmt.int(food.calories ?? 0))
                            .font(.system(size: 19, weight: .regular, design: .monospaced))
                            .foregroundStyle(ChatChrome.primary)
                        Text("kcal")
                            .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                            .foregroundStyle(ChatChrome.quaternary)
                    }
                    .fixedSize()
                }
                if food.protein_g != nil || food.carbs_g != nil || food.fat_g != nil {
                    ChatHintFlow(spacing: 14) {
                        macroDot("P", food.protein_g, Palette.macroProtein)
                        macroDot("K", food.carbs_g, Palette.macroCarbs)
                        macroDot("Y", food.fat_g, Palette.macroFat)
                    }
                    .padding(.top, 9)
                }
            }
            .padding(.init(top: 14, leading: 18, bottom: 12, trailing: 18))

            Hairline()

            if turn.saved {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(ChatChrome.positive)
                    Text("Günlüğe eklendi")
                        .font(Typography.captionBold)
                        .foregroundStyle(ChatChrome.secondary)
                        .lineLimit(1)
                        .fixedSize()
                    Spacer(minLength: 8)
                    Text("\(Fmt.dayMonth.string(from: turn.createdAt)) · Takvim'de")
                        .font(.system(size: 10.5))
                        .foregroundStyle(ChatChrome.quaternary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            } else {
                Button(action: onSave) {
                    HStack(spacing: 7) {
                        Image(systemName: "plus")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(ChatChrome.accent)
                        Text("Günlüğe ekle")
                            .font(Typography.captionBold)
                            .foregroundStyle(ChatChrome.primary)
                            .lineLimit(1)
                            .fixedSize()
                        Spacer(minLength: 8)
                        Text("\(Fmt.dayMonth.string(from: turn.createdAt)) · Takvim'e")
                            .font(.system(size: 10.5))
                            .foregroundStyle(ChatChrome.quaternary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(ChatChrome.card))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(ChatChrome.border, lineWidth: 1))
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.top, 6)
    }

    /// Uygulama aksiyonu — öğün kartıyla aynı V1 kart kabında.
    private func actionCard(_ action: AIAppAction) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
                            .foregroundStyle(action.status == .failed ? Palette.negative : ChatChrome.tertiary)
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
        .padding(.init(top: 12, leading: 18, bottom: 12, trailing: 18))
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(ChatChrome.card))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous).strokeBorder(ChatChrome.border, lineWidth: 1))
        .frame(maxWidth: 560, alignment: .leading)
        .padding(.top, 6)
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
        case .applied: return Palette.positive
        case .rejected: return ChatChrome.tertiary
        case .failed: return Palette.negative
        case .pending: return action.requiresConfirmation ? ChatChrome.white : ChatChrome.secondary
        }
    }

    /// V1 makro noktası: renkli 5px nokta + harf + mono değer.
    private func macroDot(_ letter: String, _ value: Double?, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(letter).font(Typography.caption).foregroundStyle(ChatChrome.tertiary)
            Text(value.map { "\(Fmt.int($0))g" } ?? "—")
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(ChatChrome.primary)
        }
        .fixedSize()   // makro birimi asla içinden kırılmaz; dar kartta satır olarak sarar
    }
}

struct TypingIndicator: View {
    var searchQuery: String? = nil
    @State private var phase = 0
    @State private var timer: Timer? = nil

    /// V1 akış dili: balon yok — asistan satırlarıyla aynı mercan nokta hizası.
    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Circle()
                .fill(ChatChrome.accent)
                .frame(width: 6, height: 6)
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
        }
        .padding(.vertical, 6)
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

/// Yüzen "Koç'a sor" affordance'ı — boşta yıldız işaretli dolgulu daire + canlı yeşil
/// durum noktası; hover'da pill'e açılıp "Koç'a sor" etiketini gösterir. Kart diliyle
/// aynı çift gölge + ışık rim; bordo yok, nötr btnBg/btnFg.
struct FloatingChatButton: View {
    var isOpen: Bool
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: hovering ? 9 : 0) {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Palette.btnFg)
                if hovering {
                    Text("Koç'a sor")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.btnFg)
                        .fixedSize()
                        .transition(.opacity.combined(with: .scale(scale: 0.9, anchor: .leading)))
                }
            }
            .frame(height: 50)
            .frame(minWidth: 50)
            .padding(.horizontal, hovering ? 19 : 0)
            .background(Capsule(style: .continuous).fill(Palette.btnBg))
            .overlay(Capsule(style: .continuous).strokeBorder(Palette.cardRim, lineWidth: 0.75))
            .overlay(alignment: .topTrailing) {
                // Boştayken "AI hazır" yeşil noktası; pill açılınca kaybolur.
                Circle()
                    .fill(Palette.positive)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().strokeBorder(Palette.background, lineWidth: 2))
                    .offset(x: 1, y: -1)
                    .opacity(hovering ? 0 : 1)
            }
            .shadow(color: Palette.cardShadow, radius: 15, x: 0, y: 7)
            .shadow(color: Palette.cardShadowTight, radius: 3, x: 0, y: 1.5)
            .animation(.spring(response: 0.32, dampingFraction: 0.8), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Koç'a sor")
    }
}

// MARK: - Markdown rendering (AI cevapları için)

/// Hafif blok-seviyesi markdown render'ı: başlık / madde listesi / numaralı liste /
/// kod bloğu / alıntı / paragraf. Satır-içi (kalın, italik, `kod`, [link](url))
/// AttributedString ile çözülür. Streaming bitince çağrılır (token başına değil).
struct MarkdownText: View {
    let text: String
    var baseFont: Font = Typography.body

    private enum Block {
        case heading(level: Int, text: String)
        case paragraph(String)
        case bullet([String])
        case numbered([String])
        case code(String)
        case quote(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(parseBlocks(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
    }

    @ViewBuilder
    private func blockView(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .foregroundStyle(ChatChrome.primary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, level <= 2 ? 2 : 0)
        case .paragraph(let text):
            Text(inline(text))
                .font(baseFont)
                .foregroundStyle(ChatChrome.primary)
                .tint(ChatChrome.accent)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        case .bullet(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").font(baseFont).foregroundStyle(ChatChrome.tertiary)
                        Text(inline(item)).font(baseFont).foregroundStyle(ChatChrome.primary)
                            .tint(ChatChrome.accent)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        case .numbered(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(idx + 1).")
                            .font(baseFont).fontWeight(.semibold).monospacedDigit()
                            .foregroundStyle(ChatChrome.tertiary)
                        Text(inline(item)).font(baseFont).foregroundStyle(ChatChrome.primary)
                            .tint(ChatChrome.accent)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
        case .code(let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(ChatChrome.secondary)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(ChatChrome.background))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(ChatChrome.border, lineWidth: 0.5))
        case .quote(let text):
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 1).fill(ChatChrome.accent.opacity(0.55)).frame(width: 2.5)
                Text(inline(text)).font(baseFont).italic()
                    .foregroundStyle(ChatChrome.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1:  return .system(size: 17, weight: .bold)
        case 2:  return .system(size: 15, weight: .bold)
        default: return .system(size: 13.5, weight: .semibold)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attr = try? AttributedString(markdown: s, options: options) {
            return attr
        }
        return AttributedString(s)
    }

    // MARK: Parser

    private func parseBlocks(_ text: String) -> [Block] {
        var blocks: [Block] = []
        let lines = text.components(separatedBy: "\n")
        var i = 0
        var paragraph: [String] = []

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
        }

        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespaces)

            if line.hasPrefix("```") {
                flushParagraph()
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                i += 1 // kapanış fence
                blocks.append(.code(code.joined(separator: "\n")))
                continue
            }
            if line.isEmpty {
                flushParagraph(); i += 1; continue
            }
            if let level = headingLevel(line) {
                flushParagraph()
                let txt = String(line.drop(while: { $0 == "#" })).trimmingCharacters(in: .whitespaces)
                blocks.append(.heading(level: level, text: txt))
                i += 1; continue
            }
            if isBullet(line) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if isBullet(l) { items.append(stripBullet(l)); i += 1 } else { break }
                }
                blocks.append(.bullet(items)); continue
            }
            if isNumbered(line) {
                flushParagraph()
                var items: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if isNumbered(l) { items.append(stripNumber(l)); i += 1 } else { break }
                }
                blocks.append(.numbered(items)); continue
            }
            if line.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while i < lines.count {
                    let l = lines[i].trimmingCharacters(in: .whitespaces)
                    if l.hasPrefix(">") {
                        quote.append(String(l.dropFirst()).trimmingCharacters(in: .whitespaces)); i += 1
                    } else { break }
                }
                blocks.append(.quote(quote.joined(separator: " "))); continue
            }
            paragraph.append(line); i += 1
        }
        flushParagraph()
        return blocks
    }

    private func headingLevel(_ line: String) -> Int? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return min(hashes, 3)
    }
    private func isBullet(_ line: String) -> Bool {
        line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") || line.hasPrefix("+ ")
    }
    private func stripBullet(_ line: String) -> String {
        for p in ["- ", "* ", "• ", "+ "] where line.hasPrefix(p) {
            return String(line.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
        }
        return line
    }
    private func isNumbered(_ line: String) -> Bool {
        var idx = line.startIndex
        var digits = 0
        while idx < line.endIndex, line[idx].isNumber { idx = line.index(after: idx); digits += 1 }
        guard digits > 0, idx < line.endIndex, line[idx] == "." || line[idx] == ")" else { return false }
        let next = line.index(after: idx)
        return next < line.endIndex && line[next] == " "
    }
    private func stripNumber(_ line: String) -> String {
        guard let sep = line.firstIndex(where: { $0 == "." || $0 == ")" }) else { return line }
        return String(line[line.index(after: sep)...]).trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - V1 model satırı yardımcıları

enum ChatModelInfo {
    /// Segment/başlık için kısa sağlayıcı adı ("Codex (ChatGPT)" → "Codex").
    static func shortProvider(_ p: AIProvider) -> String {
        p == .codex ? "Codex" : p.label
    }

    /// Kompakt düşünme etiketi (segment'e sığsın diye).
    static func compactLevel(_ l: IntelligenceLevel) -> String {
        switch l {
        case .low:       return "Low"
        case .medium:    return "Mid"
        case .high:      return "High"
        case .extraHigh: return "Max"
        }
    }

    /// "Codex · gpt-5.4 · High" — sidebar/dock üst şeridi.
    static func line(provider: AIProvider, model: String, intelligence: IntelligenceLevel) -> String {
        var s = "\(shortProvider(provider)) · \(model)"
        if provider.supportsIntelligence { s += " · \(compactLevel(intelligence))" }
        return s
    }
}

// MARK: - V1 chat ayarları paneli (sidebar + dock "···" popover'ı)

/// Native Menu yerine V1 dilinde panel: SOHBET satırları + MODEL kontrolleri
/// (segmented sağlayıcı/düşünme, mono model pill'i) + kırmızı sil satırı.
struct ChatOptionsPanel: View {
    var store: ChatStore
    var presetCount: Int
    /// Yüzey değiştirme (sidebar↔dock) opsiyonel — nil ise satır gösterilmez.
    var modeSwitchLabel: String? = nil
    var modeSwitchIcon: String? = nil
    var canDelete: Bool
    var onOpenPresets: () -> Void
    var onSwitchMode: (() -> Void)? = nil
    var onDelete: () -> Void
    var onDismiss: () -> Void

    @State private var provider: AIProvider = AIKeyStore.shared.provider
    @State private var model: String = AIKeyStore.shared.model
    @State private var intelligence: IntelligenceLevel = AIKeyStore.shared.intelligence
    @State private var historyOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("SOHBET")
            VStack(spacing: 5) {
                panelRow(icon: "square.and.pencil", title: "Yeni sohbet", detail: nil, showsChevron: false) {
                    store.newChat()
                    onDismiss()
                }
                .disabled(store.isSending)

                panelRow(
                    icon: "clock",
                    title: "Geçmiş sohbetler",
                    detail: "\(store.conversationList.count)",
                    chevron: historyOpen ? "chevron.down" : "chevron.right"
                ) {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.9)) { historyOpen.toggle() }
                }
                .disabled(store.conversationList.isEmpty)

                if historyOpen { historyList }

                panelRow(icon: "takeoutbag.and.cup.and.straw", title: "Presetler", detail: "\(presetCount)") {
                    onDismiss()
                    onOpenPresets()
                }

                if let onSwitchMode, let modeSwitchLabel, let modeSwitchIcon {
                    panelRow(icon: modeSwitchIcon, title: modeSwitchLabel, detail: nil) {
                        onDismiss()
                        onSwitchMode()
                    }
                }
            }

            sectionLabel("MODEL")
            VStack(spacing: 9) {
                controlRow("Sağlayıcı") { providerSegment }
                controlRow("Model") { modelMenu }
                if provider.supportsIntelligence {
                    controlRow("Düşünme") { intelligenceSegment }
                }
            }

            Hairline()

            deleteRow
        }
        .padding(13)
        .frame(width: 312)
        .onReceive(NotificationCenter.default.publisher(for: .aiClientChanged)) { _ in
            provider = AIKeyStore.shared.provider
            model = AIKeyStore.shared.model
            intelligence = AIKeyStore.shared.intelligence
        }
    }

    // MARK: bölümler

    private func sectionLabel(_ s: String) -> some View {
        Text(s)
            .font(Typography.label)
            .tracking(0.9)
            .foregroundStyle(ChatChrome.quaternary)
    }

    private func panelRow(
        icon: String,
        title: String,
        detail: String?,
        chevron: String = "chevron.right",
        showsChevron: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ChatChrome.tertiary)
                    .frame(width: 16)
                Text(title)
                    .font(Typography.bodyBold)
                    .foregroundStyle(ChatChrome.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                if let detail {
                    Text(detail)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(ChatChrome.tertiary)
                }
                if showsChevron {
                    Image(systemName: chevron)
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ChatChrome.quaternary)
                }
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 8.5)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(ChatChrome.panelRaised.opacity(0.55))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var historyList: some View {
        ScrollView {
            VStack(spacing: 1) {
                ForEach(store.conversationList) { conversation in
                    let isCurrent = conversation.id == store.currentConversationID
                    Button {
                        store.selectConversation(conversation.id)
                        onDismiss()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: isCurrent ? "checkmark" : "message")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(isCurrent ? ChatChrome.accent : ChatChrome.quaternary)
                                .frame(width: 14)
                            Text(conversation.title)
                                .font(Typography.caption)
                                .foregroundStyle(isCurrent ? ChatChrome.primary : ChatChrome.secondary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isCurrent ? ChatChrome.whiteSoft.opacity(0.55) : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(store.isSending)
                }
            }
        }
        .frame(maxHeight: 168)
        .padding(.leading, 22)
    }

    private func controlRow<C: View>(_ label: String, @ViewBuilder control: () -> C) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(Typography.bodyBold)
                .foregroundStyle(ChatChrome.primary)
            Spacer(minLength: 0)
            control()
        }
    }

    private var providerSegment: some View {
        segmented(
            AIProvider.selectable.map { ($0, ChatModelInfo.shortProvider($0)) },
            selection: provider
        ) { p in
            AIKeyStore.shared.provider = p
            NotificationCenter.default.post(name: .aiClientChanged, object: nil)
        }
    }

    private var intelligenceSegment: some View {
        segmented(
            IntelligenceLevel.allCases.map { ($0, ChatModelInfo.compactLevel($0)) },
            selection: intelligence
        ) { l in
            AIKeyStore.shared.intelligence = l
            NotificationCenter.default.post(name: .aiClientChanged, object: nil)
        }
    }

    private var modelMenu: some View {
        Menu {
            ForEach(provider.availableModels, id: \.self) { m in
                Button {
                    AIKeyStore.shared.model = m
                    NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                } label: {
                    if m == model {
                        Label(m, systemImage: "checkmark")
                    } else {
                        Text(m)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(model)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(ChatChrome.primary)
                    .lineLimit(1)
                    .truncationMode(.head)
                Image(systemName: "chevron.down")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundStyle(ChatChrome.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5.5)
            .frame(maxWidth: 190)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(ChatChrome.panelRaised)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(ChatChrome.border, lineWidth: 0.5)
            )
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }

    private func segmented<T: Hashable>(
        _ items: [(T, String)],
        selection: T,
        onSelect: @escaping (T) -> Void
    ) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                let isOn = item.0 == selection
                Button {
                    onSelect(item.0)
                } label: {
                    Text(item.1)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(isOn ? ChatChrome.ink : ChatChrome.secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(isOn ? ChatChrome.white : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(ChatChrome.panelRaised)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(ChatChrome.border, lineWidth: 0.5)
        )
    }

    private var deleteRow: some View {
        Button {
            onDismiss()
            onDelete()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .bold))
                Text("Bu sohbeti sil")
                    .font(Typography.bodyBold)
                Spacer(minLength: 0)
            }
            .foregroundStyle(canDelete ? Palette.negative : ChatChrome.quaternary)
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(ChatChrome.panelRaised.opacity(0.55))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canDelete)
    }
}
