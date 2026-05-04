import SwiftUI
import SwiftData

struct ChatSidebar: View {
    @Environment(\.modelContext) private var ctx
    @ObservedObject var store: ChatStore
    @Binding var width: CGFloat
    var onClose: () -> Void

    @State private var currentProvider: AIProvider = AIKeyStore.shared.provider
    @State private var currentModel: String = AIKeyStore.shared.model
    @State private var currentIntelligence: IntelligenceLevel = AIKeyStore.shared.intelligence

    private let minWidth: CGFloat = 320
    private let maxWidth: CGFloat = 720

    var body: some View {
        HStack(spacing: 0) {
            resizeHandle
            VStack(spacing: 0) {
                header
                Hairline()
                messagesScroll
                Hairline()
                inputBar
            }
            .frame(maxWidth: .infinity)
            .background(Palette.background)
        }
        .frame(width: width)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Palette.border)
                .frame(width: 0.5)
        }
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: 6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { v in
                        let new = width - v.translation.width
                        width = min(maxWidth, max(minWidth, new))
                    }
            )
            .onHover { hovering in
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Palette.accent.opacity(0.18))
                    .frame(width: 26, height: 26)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
            }

            modelPicker

            Spacer()
            Button {
                store.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Palette.surfaceElevated))
                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .disabled(store.messages.isEmpty)
            .opacity(store.messages.isEmpty ? 0.4 : 1)
            .help("Sohbeti temizle")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Palette.surfaceElevated))
                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .help("Kapat")
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .onReceive(NotificationCenter.default.publisher(for: .aiClientChanged)) { _ in
            currentProvider = AIKeyStore.shared.provider
            currentModel = AIKeyStore.shared.model
        }
    }

    private var modelPicker: some View {
        Menu {
            Section("Sağlayıcı") {
                ForEach(AIProvider.selectable) { p in
                    Button {
                        AIKeyStore.shared.provider = p
                        currentProvider = p
                        currentModel = AIKeyStore.shared.model
                        NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                    } label: {
                        if p == currentProvider {
                            Label(p.label, systemImage: "checkmark")
                        } else {
                            Text(p.label)
                        }
                    }
                }
            }
            Section("Model") {
                ForEach(currentProvider.availableModels, id: \.self) { m in
                    Button {
                        AIKeyStore.shared.model = m
                        currentModel = m
                        NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                    } label: {
                        if m == currentModel {
                            Label(m, systemImage: "checkmark")
                        } else {
                            Text(m)
                        }
                    }
                }
            }
            if currentProvider.supportsIntelligence {
                Section("Intelligence") {
                    ForEach(IntelligenceLevel.allCases) { e in
                        Button {
                            AIKeyStore.shared.intelligence = e
                            currentIntelligence = e
                            NotificationCenter.default.post(name: .aiClientChanged, object: nil)
                        } label: {
                            if e == currentIntelligence {
                                Label(e.label, systemImage: "checkmark")
                            } else {
                                Text(e.label)
                            }
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(currentProvider.label)
                            .font(Typography.bodyBold)
                            .foregroundStyle(Palette.textPrimary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    HStack(spacing: 4) {
                        Text(currentModel)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                        if currentProvider.supportsIntelligence {
                            Text("· \(currentIntelligence.label)")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.accent.opacity(0.85))
                        }
                    }
                }
            }
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var messagesScroll: some View {
        if store.messages.isEmpty {
            VStack(spacing: 8) {
                Spacer()
                Image(systemName: "fork.knife.circle")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(Palette.textTertiary)
                Text("Yediklerini yaz, kalorisini söyleyeyim")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                Text("ör: \"300g pişmiş tavuk göğsü\"")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        ForEach(store.messages) { turn in
                            MessageBubble(turn: turn) {
                                store.saveFood(in: turn, ctx: ctx)
                            }
                            .id(turn.id)
                        }
                        if store.isSending {
                            TypingIndicator(searchQuery: store.searchingFor)
                        }
                    }
                    .padding(Spacing.lg)
                }
                .onChange(of: store.messages.count) { _, _ in
                    if let last = store.messages.last {
                        withAnimation(.easeOut(duration: 0.2)) {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    private var inputBar: some View {
        VStack(spacing: 0) {
            HStack(spacing: Spacing.sm) {
                TextField("ör: 200g pirinç pilavı", text: $store.input, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1...4)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(Palette.surfaceElevated)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
                    .onSubmit {
                        Task { await store.send() }
                    }
                Button {
                    Task { await store.send() }
                } label: {
                    Image(systemName: store.isSending ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle()
                                .fill(store.input.isEmpty ? Palette.textQuaternary : Palette.accent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(store.input.isEmpty || store.isSending)
            }
            .padding(Spacing.md)
        }
    }
}

private struct MessageBubble: View {
    let turn: ChatTurn
    var onSave: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if turn.role == .user { Spacer(minLength: 24) }

            VStack(alignment: .leading, spacing: 6) {
                if let q = turn.searchedFor {
                    HStack(spacing: 5) {
                        Image(systemName: "globe")
                            .font(.system(size: 9, weight: .semibold))
                        Text("Web'de arandı: \"\(q)\"")
                            .font(Typography.caption)
                    }
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.bottom, 2)
                }
                Text(turn.text)
                    .font(Typography.body)
                    .foregroundStyle(turn.role == .user ? Palette.textPrimary : Palette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let food = turn.food {
                    foodCard(food)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(turn.role == .user ? Palette.accent.opacity(0.18) : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )

            if turn.role == .assistant { Spacer(minLength: 24) }
        }
    }

    private func foodCard(_ food: AIFoodResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Hairline()
            HStack(spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name ?? "Yemek")
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                    if let g = food.grams {
                        Text("\(Fmt.int(g)) g")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(Fmt.int(food.calories ?? 0))
                            .font(Typography.monoLarge)
                            .foregroundStyle(Palette.textPrimary)
                        Text("kcal")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            }
            if food.protein_g != nil || food.carbs_g != nil || food.fat_g != nil {
                HStack(spacing: 10) {
                    macroChip("P", food.protein_g, Palette.macroProtein)
                    macroChip("K", food.carbs_g, Palette.macroCarbs)
                    macroChip("Y", food.fat_g, Palette.macroFat)
                }
            }
            Button(action: onSave) {
                HStack(spacing: 5) {
                    Image(systemName: turn.saved ? "checkmark" : "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text(turn.saved ? "Eklendi" : "Bugüne ekle")
                        .font(Typography.bodyBold)
                }
                .foregroundStyle(turn.saved ? Palette.positive : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                        .fill(turn.saved ? Palette.positive.opacity(0.15) : Palette.accent)
                )
            }
            .buttonStyle(.plain)
            .disabled(turn.saved)
        }
    }

    private func macroChip(_ letter: String, _ value: Double?, _ tint: Color) -> some View {
        HStack(spacing: 3) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(letter).font(Typography.caption).foregroundStyle(Palette.textTertiary)
            Text(value.map { "\(Fmt.int($0))g" } ?? "—")
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
        }
    }
}

private struct TypingIndicator: View {
    var searchQuery: String? = nil
    @State private var phase = 0
    var body: some View {
        HStack(spacing: 6) {
            if let q = searchQuery {
                Image(systemName: "globe")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Text("Web'de aranıyor: \"\(q)\"")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Palette.textTertiary)
                        .frame(width: 5, height: 5)
                        .opacity(phase == i ? 1 : 0.3)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { _ in
                phase = (phase + 1) % 3
            }
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
                            colors: [Palette.accent, Palette.accent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 48, height: 48)
                    .shadow(color: .black.opacity(0.4), radius: 10, y: 4)
                Image(systemName: isOpen ? "xmark" : "sparkles")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.black.opacity(0.85))
            }
            .scaleEffect(hovering ? 1.06 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Kalori Asistanı")
    }
}
