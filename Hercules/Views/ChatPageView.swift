import SwiftUI
import LucideKit
import SwiftData
import PhotosUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit

private extension NSImage {
    /// PNG Data — pano/sürükle-bırak görsellerini composer'a eklemek için.
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
#endif

#if os(macOS)
/// SwiftUI TextEditor'ın altındaki NSTextView, sürüklenen dosyaları/görselleri KENDİ içine metin
/// (dosya yolu) olarak alıyor → composer'ın `.onDrop`'u hiç tetiklenmiyordu. Çözüm: o NSTextView'ın
/// dragged type'larını kaldır; böylece drop, görseli ekleyen `.onDrop`'a düşer. Tarama bir kez yapılır
/// (NSTextView bulununca kalıcı durur) — her-update tam-ağaç taraması YAPILMAZ (kasma sebebi olurdu).
/// Composer'daki NSTextView'ın imleç konumunu dışarı taşır.
///
/// NEDEN: mention menüsü "metnin SON kelimesi @ ile başlıyor mu" diye bakıyordu, yani `@`
/// ancak metnin en sonundayken açılıyordu. Cümlenin ortasına `@` yazınca son kelime bambaşka
/// bir şey oluyor ve menü hiç görünmüyordu. Doğru soru "imlecin SOLUNDAKİ kelime" — bunun için
/// imleç konumu şart, SwiftUI TextEditor onu vermiyor.
private struct CaretObserver: NSViewRepresentable {
    @Binding var location: Int

    final class Coordinator {
        var observer: NSObjectProtocol?
        var tries = 0
        var bound = false
        deinit { if let observer { NotificationCenter.default.removeObserver(observer) } }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        bind(from: v, context.coordinator)
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private func bind(from view: NSView, _ coord: Coordinator) {
        guard !coord.bound, coord.tries < 20 else { return }
        coord.tries += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard !coord.bound else { return }
            guard let tv = TextEditorDropDisabler.firstTextView(in: view.window?.contentView) else {
                bind(from: view, coord)
                return
            }
            coord.bound = true
            coord.observer = NotificationCenter.default.addObserver(
                forName: NSTextView.didChangeSelectionNotification,
                object: tv, queue: .main
            ) { note in
                guard let tv = note.object as? NSTextView else { return }
                location = tv.selectedRange().location
            }
            location = tv.selectedRange().location
        }
    }
}

private struct TextEditorDropDisabler: NSViewRepresentable {
    final class Coordinator { var done = false; var tries = 0 }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        scheduleApply(from: v, context.coordinator)
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {}   // no-op: tarama yalnız makeNSView zincirinde

    private func scheduleApply(from view: NSView, _ coord: Coordinator) {
        guard !coord.done, coord.tries < 20 else { return }
        coord.tries += 1
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            guard !coord.done else { return }
            let editors = Self.textViews(in: view.window?.contentView)
            if editors.isEmpty {
                scheduleApply(from: view, coord)   // window/editor henüz yok → tekrar dene
            } else {
                editors.forEach { $0.unregisterDraggedTypes() }
                coord.done = true
            }
        }
    }

    static func firstTextView(in view: NSView?) -> NSTextView? {
        textViews(in: view).first
    }

    fileprivate static func textViews(in view: NSView?) -> [NSTextView] {
        guard let view else { return [] }
        var out: [NSTextView] = []
        if let tv = view as? NSTextView { out.append(tv) }
        for sub in view.subviews { out.append(contentsOf: Self.textViews(in: sub)) }
        return out
    }
}
#endif

/// "Hızlı → Akıllı" ayrık (snap'li) sürüklenebilir effort slider'ı — Claude Code "Effort"
/// dili: kalın track içinde sağa doğru yoğunlaşan, SÜREKLİ parıldayan pixel-dither dolgu +
/// köşeli beyaz thumb. `levels` sırası dumb→smart; sürükleyince en yakın durağa oturur.
private struct EffortSlider: View {
    let levels: [IntelligenceLevel]
    let selection: IntelligenceLevel
    var onChange: (IntelligenceLevel) -> Void

    @State private var dragIndex: Int? = nil
    private let handleR: CGFloat = 8          // thumb yarı-genişliği (drag matematiği buna bağlı)
    private let trackH: CGFloat = 18
    private let rowH: CGFloat = 24

    var body: some View {
        let n = max(levels.count, 1)
        let selIdx = levels.firstIndex(of: selection) ?? 0
        let idx = dragIndex ?? selIdx

        return GeometryReader { geo in
            let w = geo.size.width
            let usable = max(w - handleR * 2, 1)
            let stepX = n > 1 ? usable / CGFloat(n - 1) : 0
            let handleX = handleR + CGFloat(idx) * stepX

            ZStack(alignment: .leading) {
                // Piksel taraması: yalnız popover açıkken canlı → maliyeti yok denecek kadar az.
                TimelineView(.animation(minimumInterval: 1.0 / 9.0)) { tl in
                    let step = (tl.date.timeIntervalSinceReferenceDate * 9).rounded(.down)
                    Canvas { ctx, size in
                        Self.dither(&ctx, size, fillW: handleX + handleR, step: step)
                    }
                }
                .frame(height: trackH)
                .background(RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(ChatChrome.whiteSoft))
                .clipShape(RoundedRectangle(cornerRadius: 5.5, style: .continuous))

                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(ChatChrome.primary)
                    .frame(width: handleR * 2, height: rowH)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
                    .offset(x: handleX - handleR)
            }
            .frame(height: rowH)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let clamped = min(max(v.location.x, handleR), w - handleR)
                        let ratio = (clamped - handleR) / usable
                        let nearest = min(max(Int((ratio * CGFloat(n - 1)).rounded()), 0), n - 1)
                        if nearest != dragIndex { dragIndex = nearest }
                        if levels[nearest] != selection { onChange(levels[nearest]) }
                    }
                    .onEnded { _ in dragIndex = nil }
            )
        }
        .frame(height: rowH)
    }

    /// Dolu bölge: sola→sağa seyrekten yoğuna piksel rampası, her karede farklı hücreler
    /// yanıp söner ("piksel piksel sürekli"). Boş bölge: çok seyrek soluk noktalar.
    private static func dither(_ ctx: inout GraphicsContext, _ size: CGSize,
                               fillW: CGFloat, step: Double) {
        let cell: CGFloat = 2.4
        let pitch: CGFloat = 3.8
        let inset: CGFloat = 2.0
        let cols = Int((size.width - inset * 2) / pitch) + 1
        let rows = max(Int((size.height - inset * 2 - cell) / pitch) + 1, 1)
        for row in 0..<rows {
            for col in 0..<cols {
                let x = inset + CGFloat(col) * pitch
                let y = inset + CGFloat(row) * pitch
                guard x + cell <= size.width - inset + 0.5 else { continue }
                let filled = x < fillW
                // Yoğunluk rampası thumb'a normalize: thumb'a yaklaştıkça hep dolu görünür.
                let prob: Double = filled
                    ? 0.10 + 0.90 * Double(min(x / max(fillW, 1), 1))
                    : 0.05
                guard hash(col, row, step) < prob else { continue }
                let o = filled ? 0.35 + 0.65 * hash(col &+ 57, row &+ 31, step) : 0.5
                ctx.fill(Path(CGRect(x: x, y: y, width: cell, height: cell)),
                         with: .color((filled ? ChatChrome.accent : ChatChrome.quaternary).opacity(o)))
            }
        }
    }

    /// Deterministik hücre+zaman hash'i (0..1) — GPU dither'ının CPU muadili.
    private static func hash(_ x: Int, _ y: Int, _ s: Double) -> Double {
        let v = sin(Double(x) * 127.1 + Double(y) * 311.7 + s * 74.7) * 43758.5453
        return v - v.rounded(.down)
    }
}

/// Tam sayfa AI sohbeti (sidebar nav'da "Sohbet"). Mevcut sidebar + bottom-dock
/// chat ile AYNI `ChatStore`'u paylaşır → konuşmalar her üç yüzeyde de senkron.
/// Üç sütun: konuşma listesi rail · ortalı konuşma kolonu · şık composer.
struct ChatPageView: View {
    @Bindable var store: ChatStore
    @Environment(\.modelContext) private var ctx
    @FocusState private var inputFocused: Bool
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var dropTargeted = false
    #if os(macOS)
    @State private var pasteMonitor: Any? = nil
    #endif

    @State private var provider: AIProvider = AIKeyStore.shared.provider
    @State private var model: String = AIKeyStore.shared.model
    @State private var intelligence: IntelligenceLevel = AIKeyStore.shared.intelligence
    @State private var selectedMentionIndex: Int = 0
    /// İkinci adım: bir etiket seçildi, şimdi tarih aralığı seçiliyor.
    @State private var pendingRangeTag: MentionTag?
    /// Composer imlecinin konumu — mention menüsü buna göre açılır.
    @State private var caretLocation: Int = 0
    /// Aralık adımında işaretlenenler — onaylanana kadar burada birikir.
    @State private var pendingRanges: [MentionRange] = []
    /// Composer'ın üstündeki veri chip'leri. Sohbet metnine hiçbir şey yazılmıyor.
    @State private var attachments: [ContextAttachment] = []
    @State private var dismissedAt: String? = nil
    // Composer altındaki model/effort seçici popover'ları (foto 1 & 2)
    @State private var showingModelPicker = false
    @State private var showingEffortPicker = false

    // Hızlı ekle: veriden türetilen "sık girdiklerin" + elle presetler (composer'daki "+")
    @Query(sort: \FoodEntry.date, order: .reverse) private var foodEntries: [FoodEntry]
    @Query private var profiles: [UserProfile]
    @Query(sort: \FoodPreset.sortOrder) private var foodPresets: [FoodPreset]
    @State private var showingQuickAdd = false
    @State private var quickAddQuery = ""


    // Mesaj etkileşimleri: hover'da kopyala / telefona gönder + zaman damgası
    @State private var hoveredMessageID: UUID? = nil
    @State private var copiedMessageID: UUID? = nil
    // Akıllı oto-takip: kullanıcı yukarı kaydırıp okuyorsa typewriter onu geri çekmez
    @State private var autoFollow = true
    @State private var nearBottom = true
    @State private var suppressAutoFollowUntil = Date.distantPast
    /// Akış sırasındaki takip-scroll'unun son zamanı (kare başına bir kez yeter).
    @State private var lastFollowScroll = Date.distantPast
    // Rail'de hover-ile-sil
    @State private var hoveredConversationID: UUID? = nil
    // Buzz kanal+thread modeli: sağ panel bir "Geçmiş listesi" değil, seçili
    // konuşmanın THREAD'i. Kanal akışı kök mesajları + yanıt haplarını gösterir.
    @State private var threadOpen = false
    @State private var channelDraft = ""
    @FocusState private var channelComposerFocused: Bool
    // Buzz thread paneli boyutlandırması: sol kenardan sürüklenir, çift tık
    // varsayılana döner; genişlik oturumlar arası kalıcı (auxiliaryPanelLayout.ts).
    @State private var hoveredReplyPillID: UUID? = nil
    @State private var confirmingArchive = false
    @State private var sendStartedAt: Date? = nil
    private let activity = AgentActivityCenter.shared
    @AppStorage("hercules.chat.threadPanelWidth") private var threadPanelWidth: Double = 380
    @State private var threadResizeStartWidth: Double? = nil
    @State private var threadResizeHovering = false
    private static let threadPanelMinWidth: Double = 340
    private static let threadPanelDefaultWidth: Double = 380
    @State private var confirmingDeleteID: UUID? = nil
    @State private var showingDeleteConfirmation = false

    private static let bottomID = "chatpage-bottom"
    private static let scrollSpace = "chatpage-scroll-space"

    var body: some View {
        GeometryReader { geometry in
            let layout = ChatPaneLayout(availableWidth: geometry.size.width, preferredThreadWidth: threadPanelWidth)
            HStack(spacing: 0) {
                if !layout.isCompact || !threadOpen {
                    channelColumn
                        .frame(minWidth: 0, maxWidth: .infinity)
                }
                if threadOpen {
                    if !layout.isCompact { threadResizeHandle(layout: layout) }
                    threadPanel(compact: layout.isCompact)
                        .frame(width: layout.threadWidth)
                        .animation(nil, value: threadPanelWidth)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Koç sayfası da aynı kademeli zemin (diğer sayfalarla tek dil).
        .background(DashboardBackground().ignoresSafeArea())
        .alert(
            "Bu sohbet silinsin mi?",
            isPresented: $showingDeleteConfirmation,
            presenting: confirmingDeleteID
        ) { id in
            Button("Sohbeti sil", role: .destructive) {
                let wasCurrent = id == store.currentConversationID
                if store.deleteConversation(id), wasCurrent { threadOpen = false }
            }
            Button("İptal", role: .cancel) {}
        } message: { id in
            Text(store.isSending && id == store.currentConversationID
                 ? "Devam eden yanıt durdurulur ve bu sohbetteki tüm mesajlar kalıcı olarak silinir."
                 : "Bu sohbetteki tüm mesajlar kalıcı olarak silinir.")
        }
        .alert("Kanal arşivlensin mi?", isPresented: $confirmingArchive) {
            Button("Arşivle ve sıfırla", role: .destructive) {
                withAnimation(.easeOut(duration: 0.18)) { threadOpen = false }
                store.archiveAllConversations()
            }
            Button("İptal", role: .cancel) {}
        } message: {
            Text("Geçmiş, tarihli bir arşiv dosyasına kopyalanır ve kanal sıfırdan başlar.")
        }
        .onChange(of: store.isSending) { _, sending in
            sendStartedAt = sending ? .now : nil
        }
        #if os(macOS)
        // Thread paneli sonradan açılır — scroll view'ları Buzz overlay stiline çek.
        .background(BuzzScrollerStyler().id(threadOpen))
        #endif
        // preferredColorScheme sunum-kapsamlıydı: açık temada TÜM pencereyi (gradient
        // dahil) koyuya çeviriyordu. environment yalnız bu alt-ağacı koyu bırakır.
        .environment(\.colorScheme, .dark)
        .onAppear {
            provider = AIKeyStore.shared.provider
            model = AIKeyStore.shared.model
            intelligence = AIKeyStore.shared.intelligence
            // Gateway seçiliyse havuz model listesini tazele (chat menüsü dolsun).
            if provider == .gateway { Task { await AIKeyStore.shared.refreshGatewayModels() } }
            // Başka bir sayfadan hazır istem gelmiş olabilir (Tahliller ▸ "Koça analiz
            // ettir", Fotoğraflar ▸ "Koça gönder"). Onlar `store.input`'a yazıyor ama
            // KANAL görünümünde composer `channelDraft` kullanır — taşımazsak istem
            // ekrana hiç gelmeden kaybolur.
            let handoff = store.input.trimmingCharacters(in: .whitespacesAndNewlines)
            if !store.isSending, !threadOpen, !handoff.isEmpty {
                channelDraft = store.input
                store.input = ""
            }
            let startedInChannel = !channelDraft.isEmpty
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                if startedInChannel { channelComposerFocused = true } else { inputFocused = true }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiClientChanged)) { _ in
            provider = AIKeyStore.shared.provider
            model = AIKeyStore.shared.model
            intelligence = AIKeyStore.shared.intelligence
        }
        // Sidebar'a ya da detay kolonuna tıklanınca yazma alanının focus'unu bırak.
        // Bunu eskiden sağ AI paneli (ChatSidebar) dinliyordu; panel kaldırılınca
        // ContentView boşluğa post ediyordu — dinleyici tam sayfa sohbete taşındı.
        .onReceive(NotificationCenter.default.publisher(for: .aiChatShouldResignInputFocus)) { _ in
            inputFocused = false
        }
    }

    // MARK: - Kanal kolonu (Buzz: kök mesajlar + yanıt hapları + hızlı composer)

    private var channelColumn: some View {
        let conversations = channelConversations
        return VStack(spacing: 0) {
            chatHeader
            Rectangle().fill(ChatChrome.border).frame(height: 0.5)
            if conversations.isEmpty {
                emptyState
            } else {
                channelTimeline(conversations)
            }
            channelComposer
        }
    }

    /// Kanal akışı kronolojik (eski üstte, yeni altta) — Buzz timeline düzeni.
    /// Henüz mesajı olmayan taslak konuşmalar kanalda çizilmez.
    private var channelConversations: [ChatConversation] {
        store.conversations
            .filter { !$0.messages.isEmpty }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func showsChannelDaySeparator(at index: Int, in list: [ChatConversation]) -> Bool {
        guard list.indices.contains(index) else { return false }
        if index == 0 { return true }
        return !Calendar.current.isDate(list[index].createdAt, inSameDayAs: list[index - 1].createdAt)
    }

    private func channelTimeline(_ conversations: [ChatConversation]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(conversations.enumerated()), id: \.element.id) { index, convo in
                    if showsChannelDaySeparator(at: index, in: conversations) {
                        daySeparator(convo.createdAt)
                    }
                    conversationRootRow(convo)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, Spacing.lg)
        }
        .defaultScrollAnchor(.bottom)
        .background(ChatChrome.background)
    }

    /// Kanal satırı: konuşmanın KÖK mesajı + Buzz yanıt hapı. Satır tıklanmaz
    /// (metin seçilebilir kalır) — thread'e giriş yanıt hapı ve hover'daki
    /// aksiyon çubuğundan olur (MessageRow.tsx + MessageActionBar.tsx davranışı).
    private func conversationRootRow(_ conversation: ChatConversation) -> some View {
        let hovered = hoveredConversationID == conversation.id
        let isCurrent = conversation.id == store.currentConversationID
        let root = conversation.messages.first
        let replyCount = max(0, conversation.messages.count - 1)
        let streaming = isCurrent && store.isSending
        return VStack(alignment: .leading, spacing: 4) {
            if let root {
                MessageBubble(turn: root, isStreaming: false, userName: chatUserName) { _ in
                } onConfirmAction: { _ in
                } onRejectAction: { _ in
                }
            } else {
                Text(conversation.title.isEmpty ? "Yeni sohbet" : conversation.title)
                    .font(ChatChrome.messageBody)
                    .foregroundStyle(ChatChrome.secondary)
            }
            // Günün thread'i yanıtsızken de hapını gösterir: kanaldan thread'e tek
            // giriş kapısı bu (satır tıklanmaz, aksiyon çubuğu hover'da gizli).
            if replyCount > 0 || streaming || ChatDailyThread.isDaily(conversation) {
                replyPill(conversation, replyCount: streaming ? max(replyCount, 1) : replyCount, streaming: streaming)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(hovered ? ChatChrome.panelRaised.opacity(0.45) : Color.clear)
        )
        .overlay(alignment: .topTrailing) {
            if hovered {
                rootActionBar(conversation)
                    .padding(.top, 4)
                    .padding(.trailing, 8)
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            if hovering { hoveredConversationID = conversation.id }
            else if hoveredConversationID == conversation.id { hoveredConversationID = nil }
        }
        .animation(.easeInOut(duration: 0.12), value: hovered)
        .contextMenu {
            Button("Thread'i aç") { openThread(conversation.id) }
            Button("Sohbeti sil", role: .destructive) { requestDelete(conversation.id) }
        }
    }

    /// Buzz MessageActionBar: satırın üst kenarına oturan yüzen aksiyon hapı —
    /// thread'i aç · kopyala · sil.
    private func rootActionBar(_ conversation: ChatConversation) -> some View {
        let copied = copiedMessageID == conversation.messages.first?.id
        return HStack(spacing: 2) {
            Button { openThread(conversation.id) } label: {
                Lucide(sf: "text.bubble", size: 12)
                    .foregroundStyle(ChatChrome.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Thread'i aç")

            Button {
                guard let root = conversation.messages.first else { return }
                copyToClipboard(root.text)
                copiedMessageID = root.id
                let id = root.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                    if copiedMessageID == id { copiedMessageID = nil }
                }
            } label: {
                Lucide(sf: copied ? "checkmark" : "doc.on.doc", size: 11)
                    .foregroundStyle(copied ? ChatChrome.positive : ChatChrome.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Kök mesajı kopyala")

            Button { requestDelete(conversation.id) } label: {
                Lucide(sf: "trash", size: 11)
                    .foregroundStyle(ChatChrome.tertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Sohbeti sil")
        }
        .padding(.horizontal, 3)
        .background(Capsule().fill(ChatChrome.whiteSoft))
    }

    /// Buzz MessageThreadSummaryRow: 30pt rounded-full hap — facepile + "N yanıt ·
    /// son yanıt X"; hapın KENDİ hover'ında yüzey belirir ve etiket "Thread'i aç"
    /// olur; tıklamak thread panelini açar.
    private func replyPill(_ conversation: ChatConversation, replyCount: Int, streaming: Bool) -> some View {
        let hovered = hoveredReplyPillID == conversation.id
        return Button {
            openThread(conversation.id)
        } label: {
            HStack(spacing: 6) {
                HStack(spacing: -4) {
                    ChatUserAvatar(name: chatUserName, size: 20)
                    AssistantMark(size: 20, cornerRadius: 10)
                }
                HStack(spacing: 4) {
                    Text(replyCount == 0 ? ChatDailyThread.emptyReplyLabel(for: conversation) : "\(replyCount) yanıt")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(hovered ? ChatChrome.primary : ChatChrome.secondary)
                    Text("·")
                        .font(.system(size: 12))
                        .foregroundStyle(ChatChrome.quaternary)
                    Text(streaming ? "yazıyor…" : ((hovered || replyCount == 0) ? "Thread'i aç" : "son yanıt \(Fmt.relative(conversation.updatedAt))"))
                        .font(.system(size: 12))
                        .foregroundStyle(streaming ? ChatChrome.positive : ChatChrome.tertiary)
                }
                .lineLimit(1)
            }
            .padding(.leading, 4)
            .padding(.trailing, 12)
            .frame(height: 30)
            .background(Capsule().fill(hovered ? ChatChrome.background.opacity(0.95) : Color.clear))
            .overlay(Capsule().strokeBorder(hovered ? ChatChrome.borderStrong.opacity(0.7) : Color.clear, lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            if hovering { hoveredReplyPillID = conversation.id }
            else if hoveredReplyPillID == conversation.id { hoveredReplyPillID = nil }
        }
        // Gövde hizası: avatar (32) + boşluk (10).
        .padding(.leading, 42)
        .help("Thread'i aç")
        .accessibilityIdentifier("chat-thread-\(conversation.id.uuidString)")
    }

    private func openThread(_ id: UUID) {
        guard store.selectConversation(id) else { return }
        // Repeated clicks keep the thread open. During streaming, insert the panel
        // immediately so text-update transactions cannot interrupt its transition.
        if store.isSending {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { threadOpen = true }
        } else {
            withAnimation(.easeOut(duration: 0.22)) { threadOpen = true }
        }
        channelComposerFocused = false
        inputFocused = true
    }

    private func requestDelete(_ id: UUID) {
        confirmingDeleteID = id
        showingDeleteConfirmation = true
    }

    /// Kanal composer'ı: Buzz "Message #kanal" — buradan yazmak YENİ konuşma
    /// (kök mesaj) başlatır; tam donanımlı composer thread'dedir.
    private var channelComposer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("\(CoachIdentity.dative) yeni bir soru başlat…", text: $channelDraft, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                // Alan gönder butonuyla aynı boyda: tek satır metin kutunun
                // ortasında durur. Boyu vermeden `.bottom` hizası metni
                // butonun altına düşürüyordu.
                .frame(minHeight: 30)
                .font(ChatChrome.messageBody)
                .foregroundStyle(ChatChrome.primary)
                .focused($channelComposerFocused)
                .onSubmit { startConversationFromChannel() }

            Button { startConversationFromChannel() } label: {
                Lucide(sf: "arrow.up", size: 14)
                    .foregroundStyle(channelDraftSendable ? ChatChrome.ink : ChatChrome.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(channelDraftSendable ? ChatChrome.white : ChatChrome.whiteSoft))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!channelDraftSendable || store.isSending)
            .help("Yeni konuşma başlat (↵)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        // Düz dil: kutu yerine odak durumunda beliren yumuşak peçe.
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(channelComposerFocused ? ChatChrome.accentSoft : ChatChrome.whiteSoft)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .animation(.easeInOut(duration: 0.15), value: channelComposerFocused)
    }

    private var channelDraftSendable: Bool {
        !channelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func startConversationFromChannel() {
        let text = channelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !store.isSending else { return }
        // Buzz davranışı: kanala yazmak thread AÇMAZ — kök mesaj kanala düşer,
        // koç arkada yanıtlar (hap "yazıyor…" gösterir). Açık panel varsa kapat:
        // store tek-güncel-konuşma tuttuğu için panel yeni konuşmaya zıplardı.
        store.newChat()
        store.input = text
        channelDraft = ""
        withAnimation(.easeOut(duration: 0.18)) { threadOpen = false }
        sendWithContext()
    }

    // MARK: - Thread paneli (Buzz MessageThreadPanel: başlık + transkript + composer)

    /// Buzz resize kolu (auxiliaryPanelLayout.ts): layout'ta yalnız 1px hairline
    /// durur; 13pt'lik görünmez tutma alanı kenarın ÜSTÜNE biner (görünür boşluk
    /// yok). Sürükleme GLOBAL uzayda mutlak imleç konumundan hesaplanır — panel
    /// büyürken tutamacın kendisi kaydığı için lokal translation zıplatıyordu.
    /// Çift tık varsayılan genişliğe döner.
    private func threadResizeHandle(layout: ChatPaneLayout) -> some View {
        Rectangle()
            .fill((threadResizeHovering || threadResizeStartWidth != nil)
                  ? ChatChrome.borderStrong.opacity(0.9)
                  : ChatChrome.borderStrong.opacity(0.45))
            .frame(width: 1)
            .overlay(
                Color.clear
                    .frame(width: 13)
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        threadResizeHovering = hovering
                        #if os(macOS)
                        if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                        #endif
                    }
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { value in
                                if threadResizeStartWidth == nil { threadResizeStartWidth = layout.threadWidth }
                                // Sol kenar: imleç sola gittikçe panel büyür. Anlık clamp,
                                // sınırda birikip geri dönerken oluşan "yapışmayı" önler.
                                let proposed = (threadResizeStartWidth ?? Self.threadPanelDefaultWidth)
                                    - Double(value.location.x - value.startLocation.x)
                                threadPanelWidth = min(max(proposed, Self.threadPanelMinWidth), layout.maximumThreadWidth)
                            }
                            .onEnded { _ in
                                threadResizeStartWidth = nil
                            }
                    )
                    .simultaneousGesture(
                        TapGesture(count: 2).onEnded {
                            threadPanelWidth = Self.threadPanelDefaultWidth
                        }
                    )
            )
            .help("Sürükleyerek genişlet · çift tık: sıfırla")
    }

    private func threadPanel(compact: Bool) -> some View {
        VStack(spacing: 0) {
            threadHeader(compact: compact)
            Rectangle().fill(ChatChrome.border).frame(height: 0.5)
            if store.messages.isEmpty {
                emptyState
            } else {
                conversation
            }
            if store.isSending {
                activityRail
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            composer
        }
        .background(ChatChrome.background)
        .animation(.easeOut(duration: 0.2), value: store.isSending)
    }

    /// Buzz ComposerActivityAccessory: composer üstünde ince aktivite rayı —
    /// nabız + "çalışıyor · geçen süre" + ACP'den akan son araç çağrısı.
    private var activityRail: some View {
        HStack(spacing: 7) {
            TimelineView(.animation(minimumInterval: 0.6)) { context in
                Circle()
                    .fill(ChatChrome.positive)
                    .frame(width: 5, height: 5)
                    .opacity(0.45 + 0.55 * abs(sin(context.date.timeIntervalSinceReferenceDate * 2)))
            }

            TimelineView(.periodic(from: .now, by: 1)) { context in
                let elapsed = Int(context.date.timeIntervalSince(sendStartedAt ?? context.date))
                Text("\(CoachIdentity.name) çalışıyor · \(max(0, elapsed))sn")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(ChatChrome.secondary)
            }

            if let tool = activity.toolEvents.last {
                Text("·")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ChatChrome.quaternary)
                HStack(spacing: 4) {
                    Lucide(sf: tool.status == "completed" ? "checkmark" : "wrench.and.screwdriver", size: 9)
                    Text(tool.title)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(ChatChrome.tertiary)
            } else if activity.thinking {
                Text("· düşünüyor…")
                    .font(.system(size: 10.5))
                    .foregroundStyle(ChatChrome.tertiary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 6)
    }

    private func threadHeader(compact: Bool) -> some View {
        HStack(spacing: 8) {
            if compact {
                Button { threadOpen = false } label: {
                    Lucide(sf: "chevron.left", size: 14)
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Tüm sohbetlere dön")
                .accessibilityLabel("Tüm sohbetlere dön")
            }
            Text("Thread")
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(ChatChrome.primary)
            if store.currentConversationTitle != "Yeni sohbet" {
                Text(store.currentConversationTitle)
                    .font(.system(size: 11))
                    .foregroundStyle(ChatChrome.quaternary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            Button {
                if let id = store.currentConversationID { requestDelete(id) }
            } label: {
                Lucide(sf: "trash", size: 13)
                    .foregroundStyle(ChatChrome.secondary)
                    .frame(width: 40, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Sohbeti sil")
            .accessibilityLabel("Sohbeti sil")
            Button { withAnimation(.easeOut(duration: 0.18)) { threadOpen = false } } label: {
                Lucide(sf: "xmark", size: 12)
                    .foregroundStyle(ChatChrome.secondary)
                    .frame(width: 40, height: 44)
                    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Thread'i kapat")
        }
        .padding(.leading, 14)
        .padding(.trailing, 10)
        .frame(minHeight: 52)
        .background(ChatChrome.background)
    }

    private var chatHeader: some View {
        HStack(spacing: 10) {
            AssistantMark(size: 24, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(CoachIdentity.name)
                    .font(.system(size: 15, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(ChatChrome.primary)
                if store.currentConversationTitle != "Yeni sohbet" {
                    Text(store.currentConversationTitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(ChatChrome.quaternary)
                        .lineLimit(1)
                }
            }
            Spacer()
            HStack(spacing: 7) {
                Circle()
                    .fill(store.isSending ? ChatChrome.primary : ChatChrome.positive)
                    .frame(width: 5, height: 5)
                Text(store.isSending ? "çalışıyor" : "hazır")
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(ChatChrome.tertiary)
                    .lineLimit(1)
            }

            // Minimal kanal menüsü: tek eylem — arşivle ve sıfırdan başla.
            Menu {
                Button(role: .destructive) { confirmingArchive = true } label: {
                    Label("Arşivle ve sıfırla", systemImage: "archivebox")
                }
            } label: {
                Lucide(sf: "ellipsis", size: 13)
                    .foregroundStyle(ChatChrome.tertiary)
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(store.isSending)
            .help("Kanalı arşivle ve sıfırdan başla")
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 52)
        .background(ChatChrome.background)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            GeometryReader { viewport in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(store.messages.enumerated()), id: \.element.id) { index, turn in
                            // Boş asistan turu (ilk-token öncesi placeholder / durdurulmuş üretim) çizilmez
                            // → yalnız aşağıdaki TypingIndicator durur; yoksa yalnız/yetim bir avatar belirir.
                            if turn.role != .assistant || !turn.text.isEmpty {
                                if showsDaySeparator(at: index) {
                                    daySeparator(turn.createdAt)
                                }
                                messageRow(turn)
                                    .id(turn.id)
                            }
                        }
                        if store.isSending,
                           let last = store.messages.last,
                           last.role == .assistant, last.text.isEmpty {
                            TypingIndicator(searchQuery: store.searchingFor)
                        }
                        Color.clear.frame(height: 1).id(Self.bottomID)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: ChatNearBottomKey.self,
                                        value: geo.frame(in: .named(Self.scrollSpace)).maxY - viewport.size.height < 90
                                    )
                                }
                            )
                    }
                    // Buzz kanal akışı: kolon ortalanmaz — sola yaslı, tam genişlik,
                    // dar gutter (MessageTimeline px-2 + satır mx/px'i).
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6)
                    .padding(.vertical, Spacing.lg)
                }
                .defaultScrollAnchor(.bottom)   // kısa sohbet alta yaslanır (boşluk üstte kalır)
                .coordinateSpace(name: Self.scrollSpace)
                .background(ChatChrome.background)
                .onPreferenceChange(ChatNearBottomKey.self) { value in
                    nearBottom = value
                    if value {
                        autoFollow = true
                    } else if Date() > suppressAutoFollowUntil {
                        autoFollow = false
                    }
                }
                .onChange(of: store.messages.count) { _, _ in
                    autoFollow = true
                    scrollDown(proxy, animated: true)
                }
                .onChange(of: store.messages.last?.text) { _, _ in
                    guard store.isSending, autoFollow else { return }
                    // Harf harf akışta HER karakterde scrollTo çağırmak
                    // scroll → geometri → ChatNearBottomKey → state → layout
                    // döngüsünü kare başına defalarca tetikliyordu ("Bound preference
                    // ChatNearBottomKey tried to update multiple times per frame").
                    // Takip hissi aynı kalacak şekilde ~20 Hz'e iniyor; akış bitince
                    // aşağıdaki isSending değişimi son konumu zaten düzeltiyor.
                    let now = Date()
                    guard now.timeIntervalSince(lastFollowScroll) > 0.05 else { return }
                    lastFollowScroll = now
                    scrollDown(proxy, animated: false)
                }
                .onChange(of: store.isSending) { _, sending in
                    if !sending, autoFollow { scrollDown(proxy, animated: false) }
                }
                .onAppear { scrollDown(proxy, animated: false) }
                .overlay(alignment: .bottomTrailing) {
                    if !nearBottom {
                        Button {
                            suppressAutoFollowUntil = Date().addingTimeInterval(0.15)
                            autoFollow = true
                            scrollDown(proxy, animated: true)
                        } label: {
                            Lucide(sf: "arrow.down", size: 13)
                                .foregroundStyle(ChatChrome.primary)
                                .frame(width: 34, height: 34)
                                .background(Circle().fill(ChatChrome.whiteSoft))
                                .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, Spacing.xl)
                        .padding(.bottom, 14)
                        .transition(.scale.combined(with: .opacity))
                        .help("En alta in")
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.82), value: nearBottom)
            }
        }
    }

    private func scrollDown(_ proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
        } else {
            proxy.scrollTo(Self.bottomID, anchor: .bottom)
        }
    }

    // MARK: - Message row (Buzz kanal satırı: hover yüzeyi + sağ üstte kopyala)

    private var chatUserName: String {
        let name = profiles.first?.name.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "Sen" : name
    }

    private func messageRow(_ turn: ChatTurn) -> some View {
        let streaming = store.isSending && turn.id == store.messages.last?.id && turn.role == .assistant
        let hovered = hoveredMessageID == turn.id
        return VStack(alignment: .leading, spacing: 3) {
            if let ids = turn.imageIDs, !ids.isEmpty { attachmentRow(ids) }
            MessageBubble(
                turn: turn,
                isStreaming: streaming,
                userName: chatUserName,
                // Geçmiş bir günün thread'inde kart o güne ayarlı açılır, bugüne değil.
                defaultDayOffset: store.currentLogDayOffset
            ) { date in
                store.saveFood(in: turn, ctx: ctx, on: date)
            } onConfirmAction: { action in
                store.confirmAction(turnID: turn.id, actionID: action.id, ctx: ctx)
            } onRejectAction: { action in
                store.rejectAction(turnID: turn.id, actionID: action.id)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        // Buzz satır hover'ı: rounded-2xl, muted/50.
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(hovered ? ChatChrome.panelRaised.opacity(0.45) : Color.clear)
        )
        .overlay(alignment: .topTrailing) {
            if hovered && !turn.text.isEmpty {
                copyButton(turn)
                    .padding(.top, 4)
                    .padding(.trailing, 6)
                    .transition(.opacity)
            }
        }
        .onHover { hovering in
            if hovering { hoveredMessageID = turn.id }
            else if hoveredMessageID == turn.id { hoveredMessageID = nil }
        }
        .animation(.easeInOut(duration: 0.12), value: hovered)
    }

    /// Kullanıcının mesaja iliştirdiği görseller — balonun üstünde, sağa hizalı küçük resimler.
    /// Decode `body` içinde DEĞİL: eskiden her kare (akış sırasında saniyede ~60 kez)
    /// diskten okuyup tam çözünürlük decode ediyordu.
    private func attachmentRow(_ ids: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(ids, id: \.self) { id in
                CoachStoredThumb(id: id)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Satır anatomisiyle hizalı: avatar (32) + boşluk (10).
        .padding(.leading, 42)
    }

    private func copyButton(_ turn: ChatTurn) -> some View {
        let copied = copiedMessageID == turn.id
        return Button {
            copyToClipboard(turn.text)
            copiedMessageID = turn.id
            let id = turn.id
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                if copiedMessageID == id { copiedMessageID = nil }
            }
        } label: {
            // Buzz hover aksiyon çubuğu dili: satır köşesinde border'lı opak hap.
            Lucide(sf: copied ? "checkmark" : "doc.on.doc", size: 11)
                .foregroundStyle(copied ? ChatChrome.positive : ChatChrome.secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(ChatChrome.whiteSoft))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(copied ? "Kopyalandı" : "Mesajı kopyala")
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    // MARK: - Gün ayracı (Bugün / Dün / tarih)

    private func showsDaySeparator(at index: Int) -> Bool {
        guard store.messages.indices.contains(index) else { return false }
        if index == 0 { return true }
        return !Calendar.current.isDate(
            store.messages[index].createdAt,
            inSameDayAs: store.messages[index - 1].createdAt
        )
    }

    /// Buzz gün ayracı: ortalanmış pill chip — 11pt medium, çizgi yok
    /// (DayDivider.tsx: rounded-full, border/70, opak zemin, muted %70 metin).
    private func daySeparator(_ date: Date) -> some View {
        Text(dayLabel(date))
            .font(.system(size: 11, weight: .medium))
            .tracking(0.22)
            .foregroundStyle(ChatChrome.tertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(ChatChrome.whiteSoft))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
    }

    private func dayLabel(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Bugün" }
        if cal.isDateInYesterday(date) { return "Dün" }
        return Fmt.dateLong.string(from: date)
    }

    // MARK: - Empty state

    /// "Ne sormak istersin?" — eski sidebar "AI ipuçları" overlay'inin içeriği artık
    /// yeni sohbetin boş ekranı. Tıklanan kalıp inputa yazılır.
    private var emptyState: some View {
        GeometryReader { viewport in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer(minLength: 52)
                    AssistantMark(size: 30, cornerRadius: 8)
                    Text("Bugün neye bakalım?")
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.4)
                        .foregroundStyle(ChatChrome.primary)
                        .padding(.top, 17)
                    Text("Yemeğini, ölçümlerini ve antrenman geçmişini birlikte okuyabilirim.")
                        .font(.system(size: 13))
                        .foregroundStyle(ChatChrome.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 480, alignment: .leading)
                        .padding(.top, 6)

                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 8, alignment: .leading)
                    ], alignment: .leading, spacing: 8) {
                        ForEach(Self.starterPrompts, id: \.self) { prompt in
                            CoachSuggestionChip(text: prompt, compact: false) {
                                channelDraft = prompt
                                channelComposerFocused = true
                            }
                        }
                    }
                    .padding(.top, 28)
                    Spacer(minLength: 52)
                }
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .frame(minHeight: viewport.size.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ChatChrome.background)
    }

    private static let starterPrompts = [
        "Bugünkü planımı özetle",
        "Protein açığımı nasıl kapatırım?",
        "Son 7 günü analiz et",
        "Kilo trendimi yorumla",
        "Bugüne uygun öğün öner",
        "Antrenman programıma bak"
    ]

    private static let followUpPrompts = [
        "Bugünkü özeti çıkar",
        "Protein açığını tamamla",
        "Son haftayla karşılaştır",
        "Yarın için plan oluştur"
    ]

    private var suggestionStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Self.followUpPrompts, id: \.self) { prompt in
                    CoachSuggestionChip(text: prompt, compact: true) {
                        store.input = prompt
                        inputFocused = true
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .scrollClipDisabled()
    }

    // MARK: - Composer

    private var composer: some View {
        VStack(spacing: 10) {
            // Aralık adımı kendi başına ayakta durmalı: `@...` metni silinse ya da sorgu
            // eşleşmesi kalmasa bile seçim yarıda kesilmesin.
            if pendingRangeTag != nil || activeMentionQuery != nil {
                mentionPopup(query: activeMentionQuery ?? "")
            }
            if !store.messages.isEmpty && !store.isSending {
                suggestionStrip
            }
            if !attachments.isEmpty { attachmentStrip }
            if !store.pendingImages.isEmpty { pendingImagesStrip }
            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    if store.input.isEmpty {
                        Text("\(CoachIdentity.dative) yaz…")
                            .font(.system(size: 13))
                            .foregroundStyle(ChatChrome.quaternary)
                            .padding(.horizontal, 14).padding(.vertical, 12)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $store.input)
                        .focused($inputFocused)
                        .font(.system(size: 13))
                        .foregroundStyle(ChatChrome.primary)
                        .scrollContentBackground(.hidden)
                        #if os(macOS)
                        .background(TextEditorDropDisabler())   // NSTextView'ın path-drop'unu kapat
                        .background(CaretObserver(location: $caretLocation))
                        #endif
                        .tint(ChatChrome.primary.opacity(0.7))
                        .frame(minHeight: 34, maxHeight: 148)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 10).padding(.top, 6).padding(.bottom, 2)
                        .onKeyPress(.escape) {
                            if pendingRangeTag != nil {
                                pendingRangeTag = nil; pendingRanges = []; return .handled
                            }
                            if activeMentionQuery != nil { dismissedAt = store.input; return .handled }
                            return .ignored
                        }
                        .onKeyPress(.downArrow) {
                            if pendingRangeTag != nil {
                                let n = rangeChoices.count
                                selectedMentionIndex = (clampedSelection(in: n) + 1) % n
                                return .handled
                            }
                            guard let q = activeMentionQuery else { return .ignored }
                            let matches = filteredMentions(query: q)
                            guard !matches.isEmpty else { return .ignored }
                            selectedMentionIndex = (clampedSelection(in: matches.count) + 1) % matches.count
                            return .handled
                        }
                        .onKeyPress(.upArrow) {
                            if pendingRangeTag != nil {
                                let n = rangeChoices.count
                                selectedMentionIndex = (clampedSelection(in: n) - 1 + rangeChoices.count) % n
                                return .handled
                            }
                            guard let q = activeMentionQuery else { return .ignored }
                            let matches = filteredMentions(query: q)
                            guard !matches.isEmpty else { return .ignored }
                            selectedMentionIndex = (clampedSelection(in: matches.count) - 1 + matches.count) % matches.count
                            return .handled
                        }
                        .onKeyPress(.space) {
                            guard pendingRangeTag != nil else { return .ignored }
                            let choices = rangeChoices
                            guard !choices.isEmpty else { return .ignored }
                            toggleRange(choices[clampedSelection(in: choices.count)])
                            return .handled
                        }
                        .onKeyPress(.return) {
                            #if os(macOS)
                            if NSEvent.modifierFlags.contains(.shift) { return .ignored }
                            #endif
                            if let tag = pendingRangeTag {
                                commit(tag: tag, ranges: pendingRanges)
                                return .handled
                            }
                            if let q = activeMentionQuery {
                                let matches = filteredMentions(query: q)
                                guard !matches.isEmpty else { return .ignored }
                                insert(tag: matches[clampedSelection(in: matches.count)])
                                return .handled
                            }
                            if canSend && !store.isSending { sendWithContext() }
                            return .handled
                        }
                        .onKeyPress(.tab) {
                            if let tag = pendingRangeTag {
                                commit(tag: tag, ranges: pendingRanges)
                                return .handled
                            }
                            if let q = activeMentionQuery {
                                let matches = filteredMentions(query: q)
                                guard !matches.isEmpty else { return .ignored }
                                insert(tag: matches[clampedSelection(in: matches.count)])
                                return .handled
                            }
                            return .ignored
                        }
                        .onChange(of: activeMentionQuery) { _, newQuery in
                            if newQuery != nil { selectedMentionIndex = 0 }
                        }
                        .onChange(of: store.input) { _, newValue in
                            if let d = dismissedAt, d != newValue { dismissedAt = nil }
                        }
                }
                composerToolbar
            }
            .padding(6)
            // Buzz composer kartı: rounded-2xl (16), border/50, gölgesiz —
            // yükseklik hissi gölgeyle değil kenarlıkla verilir.
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(ChatChrome.background))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        dropTargeted ? ChatChrome.primary : (inputFocused ? ChatChrome.borderStrong : ChatChrome.borderStrong.opacity(0.5)),
                        lineWidth: 1
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: inputFocused)
            .animation(.easeInOut(duration: 0.12), value: dropTargeted)
            .onDrop(of: [.image, .fileURL], isTargeted: $dropTargeted) { providers in handleDrop(providers) }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [ChatChrome.background.opacity(0), ChatChrome.background, ChatChrome.background],
                startPoint: .top,
                endPoint: UnitPoint(x: 0.5, y: 0.28)
            )
        )
        .onChange(of: pickerItems) { _, items in loadPickedImages(items) }
        #if os(macOS)
        .onAppear { installPasteMonitor() }
        .onDisappear { removePasteMonitor() }
        #endif
    }

    // MARK: - Model & Effort şeridi (composer altı)

    private var composerToolbar: some View {
        HStack(spacing: 4) {
            quickAddButton
            photoPickerButton
            Spacer(minLength: 8)
            sendButton
        }
        .padding(.leading, 6).padding(.trailing, 2).padding(.bottom, 2)
    }

    /// Model chip — tıkla → foto-1 tarzı seçim paneli.
    private var modelChip: some View {
        Button { showingModelPicker.toggle() } label: {
            HStack(spacing: 5) {
                Text(modelDisplay(model))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(ChatChrome.tertiary)
                    .lineLimit(1)
                Lucide(sf: "chevron.up.chevron.down", size: 7).foregroundStyle(ChatChrome.quaternary)
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Model / sağlayıcı seç")
        .popover(isPresented: $showingModelPicker, arrowEdge: .top) { modelPickerPanel }
    }

    /// Effort chip — tıkla → foto-2 tarzı "Hızlı→Akıllı" slider'ı (yalnız Codex).
    private var effortChip: some View {
        Button { showingEffortPicker.toggle() } label: {
            HStack(spacing: 5) {
                Lucide(sf: "gauge.medium", size: 9).foregroundStyle(ChatChrome.quaternary)
                Text(intelligence.label)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(ChatChrome.tertiary)
                Lucide(sf: "chevron.up.chevron.down", size: 7).foregroundStyle(ChatChrome.quaternary)
            }
            .padding(.horizontal, 6).padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Zeka (reasoning) seviyesi — hızlıdan akıllıya")
        .popover(isPresented: $showingEffortPicker, arrowEdge: .top) { effortSliderPanel }
    }

    /// Foto 1: üstte sağlayıcı pill'leri, altta numaralı + seçili-tikli model listesi.
    /// Border YOK — balon dahil her katman dolgu + sistem gölgesiyle ayrışır; ferah boşluklar.
    private var modelPickerPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            panelHeader("SAĞLAYICI")
            HStack(spacing: 7) {
                ForEach(AIProvider.selectable) { p in
                    let on = p == provider
                    Button { selectProvider(p) } label: {
                        Text(shortProvider(p))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(on ? ChatChrome.ink : ChatChrome.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 6.5)
                            .background(Capsule().fill(on ? ChatChrome.white : ChatChrome.panelRaised))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)

            panelHeader("MODEL")
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(Array(panelModels.indices), id: \.self) { i in
                        modelRow(panelModels[i], index: i)
                    }
                }
                .padding(.horizontal, 9)
            }
            .frame(maxHeight: 264)
            .padding(.bottom, 12)
        }
        .frame(width: 288)
        .presentationBackground(ChatChrome.card)
    }

    private func panelHeader(_ t: String) -> some View {
        Text(t)
            .font(.system(size: 9.5, weight: .semibold)).tracking(1.2)
            .foregroundStyle(ChatChrome.quaternary)
            .padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 9)
    }

    private func modelRow(_ m: String, index: Int) -> some View {
        let on = m == model
        return Button { selectModel(m); showingModelPicker = false } label: {
            HStack(spacing: 8) {
                Text(modelDisplay(m))
                    .font(.system(size: 13, weight: on ? .semibold : .regular, design: .monospaced))
                    .foregroundStyle(ChatChrome.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if on { Lucide(sf: "checkmark", size: 11).foregroundStyle(ChatChrome.accent) }
                if index < 9 {
                    Text("\(index + 1)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(ChatChrome.quaternary)
                        .frame(width: 12, alignment: .trailing)
                }
            }
            .padding(.horizontal, 11).padding(.vertical, 8.5)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(on ? ChatChrome.panelRaised : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Foto 2: "Hızlı → Akıllı" sürüklenebilir slider paneli — bordersız, ferah.
    private var effortSliderPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text("Zeka seviyesi")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(ChatChrome.tertiary)
                Text(intelligence.label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ChatChrome.primary)
                Spacer(minLength: 0)
            }
            EffortSlider(levels: IntelligenceLevel.allCases, selection: intelligence) { lvl in
                selectIntelligence(lvl)
            }
            HStack {
                Text("Hızlı").font(.system(size: 10)).foregroundStyle(ChatChrome.quaternary)
                Spacer()
                Text("Akıllı").font(.system(size: 10)).foregroundStyle(ChatChrome.quaternary)
            }
        }
        .padding(18)
        .frame(width: 260)
        .presentationBackground(ChatChrome.card)
    }

    // Model/effort yardımcıları — hepsi AIKeyStore'a yazıp `.aiClientChanged` post eder
    // (chat + sidebar + ayarlar aynı state'i paylaşır).

    private var panelModels: [String] { AIKeyStore.shared.pickerModels(for: provider) }

    private func shortProvider(_ p: AIProvider) -> String {
        switch p {
        case .codex:      return "ChatGPT"
        case .openRouter: return "OpenRouter"
        case .gateway:    return "Gateway"
        case .claudeCode: return "Claude"
        case .cursor:     return "Cursor"
        case .grok:       return "Grok"
        }
    }

    /// "openai/gpt-5.4-mini" → "gpt-5.4-mini"; prefix'siz slug'ı aynen döndürür (asla eskimez).
    private func modelDisplay(_ m: String) -> String {
        if let slash = m.lastIndex(of: "/") { return String(m[m.index(after: slash)...]) }
        return m
    }

    private func selectProvider(_ p: AIProvider) {
        AIKeyStore.shared.provider = p
        provider = p
        model = AIKeyStore.shared.model
        if p == .gateway { Task { await AIKeyStore.shared.refreshGatewayModels() } }
        NotificationCenter.default.post(name: .aiClientChanged, object: nil)
    }

    private func selectModel(_ m: String) {
        AIKeyStore.shared.model = m
        model = m
        NotificationCenter.default.post(name: .aiClientChanged, object: nil)
    }

    private func selectIntelligence(_ lvl: IntelligenceLevel) {
        AIKeyStore.shared.intelligence = lvl
        intelligence = lvl
        NotificationCenter.default.post(name: .aiClientChanged, object: nil)
    }

    // MARK: - Hızlı ekle ("+") — sık girdiklerin + presetler

    private var quickAddButton: some View {
        Button { showingQuickAdd = true } label: {
            Lucide(sf: "plus", size: 15)
                .foregroundStyle(showingQuickAdd ? ChatChrome.primary : ChatChrome.secondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(showingQuickAdd ? ChatChrome.panelPressed : Color.clear)
                )
        }
        .buttonStyle(.plain)
        .disabled(store.isSending)
        .help("Sık girdiklerin · hızlı ekle")
        .onChange(of: showingQuickAdd) { _, isOpen in
            // Panel kapanınca (dışarı tık) composer'a odaklan — eklenen metni düzenle/gönder.
            if !isOpen && !store.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                inputFocused = true
            }
        }
        .popover(isPresented: $showingQuickAdd, arrowEdge: .bottom) {
            QuickAddPanel(
                frequent: FrequentFoodDetector.detect(from: foodEntries),
                presets: foodPresets,
                query: $quickAddQuery,
                onInsert: { insertQuickText($0, send: false) },
                onSend: { insertQuickText($0, send: true) }
            )
            .frame(width: 380)
            .frame(maxHeight: 520)
            .presentationBackground(ChatChrome.card)
        }
    }

    /// Bir hızlı-ekle satırı seçildiğinde: metni composer'a yaz (boşsa set, doluysa " + " ile
    /// ekle — kullanıcının komboları böyle yazması gibi), sonra ya odaklan ya da hemen gönder.
    private func insertQuickText(_ text: String, send: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let current = store.input
        if current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.input = trimmed
        } else {
            let sep = (current.hasSuffix(" ") || current.hasSuffix("\n")) ? "" : " + "
            store.input = current + sep + trimmed
        }
        if send {
            // Ok → hemen gönder: paneli kapat + gönder.
            showingQuickAdd = false
            quickAddQuery = ""
            sendWithContext()
        }
        // Satıra dokunma (send=false): panel AÇIK kalsın ki üst üste ekleyebilesin
        // ("tavuk + muz + badem"). Odağı ÇALMA — macOS popover focus kaybında kapanır.
        // Composer'a odak, panel kapandığında (dışarı tık) otomatik gelir.
    }

    // MARK: - Görsel ekleme (vision)

    private var photoPickerButton: some View {
        // isSending'i @Sendable PhotosPicker label closure'ından ÖNCE main-actor'da oku
        // (macOS 26 SDK: label closure Sendable → içeride main-actor property referansı uyarı verir).
        let sending = store.isSending
        #if os(macOS)
        // Mac: "herhangi bir yerden" → Finder paneli (çoklu). Ayrıca sürükle-bırak + ⌘V de var.
        return Button { openFilePicker() } label: {
            Lucide(sf: "photo.badge.plus", size: 15)
                .foregroundStyle(sending ? ChatChrome.quaternary : ChatChrome.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(sending)
        .help("Fotoğraf ekle — dosyadan seç, sürükle-bırak ya da ⌘V ile yapıştır")
        #else
        return PhotosPicker(selection: $pickerItems, maxSelectionCount: 8, matching: .images) {
            Lucide(sf: "photo.badge.plus", size: 15)
                .foregroundStyle(sending ? ChatChrome.quaternary : ChatChrome.secondary)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .disabled(sending)
        .help("Fotoğraf ekle")
        #endif
    }

    private var pendingImagesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(store.pendingImages.enumerated()), id: \.offset) { idx, data in
                    if let image = imageFromData(data) {
                        ZStack(alignment: .topTrailing) {
                            image.resizable().scaledToFill()
                                .frame(width: 54, height: 54)
                                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                            Button {
                                if store.pendingImages.indices.contains(idx) { store.pendingImages.remove(at: idx) }
                            } label: {
                                Lucide(sf: "xmark.circle.fill", size: 15)
                                    .foregroundStyle(.white, .black.opacity(0.5))
                            }
                            .buttonStyle(.plain).padding(2)
                        }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadPickedImages(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        Task {
            var datas: [Data] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) { datas.append(data) }
            }
            await MainActor.run {
                store.pendingImages.append(contentsOf: datas)
                pickerItems = []
            }
        }
    }

    private func imageFromData(_ data: Data) -> Image? {
        #if canImport(UIKit)
        return UIImage(data: data).map { Image(uiImage: $0) }
        #elseif canImport(AppKit)
        return NSImage(data: data).map { Image(nsImage: $0) }
        #else
        return nil
        #endif
    }

    /// Bekleyen görsellere ekle (toplam 8 ile sınırlı). Main-actor'da çağrılır.
    private func attach(_ datas: [Data]) {
        guard !datas.isEmpty else { return }
        let room = max(0, 8 - store.pendingImages.count)
        guard room > 0 else { return }
        store.pendingImages.append(contentsOf: datas.prefix(room))
    }

    /// Sürükle-bırak: her sağlayıcıyı görsele çevirip ekler. true → en az biri kabul edildi.
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            #if canImport(AppKit)
            let canImage = provider.canLoadObject(ofClass: NSImage.self)
            #elseif canImport(UIKit)
            let canImage = provider.canLoadObject(ofClass: UIImage.self)
            #else
            let canImage = false
            #endif

            if canImage {
                accepted = true
                #if canImport(AppKit)
                _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                    guard let img = obj as? NSImage, let data = img.pngData() else { return }
                    DispatchQueue.main.async { attach([data]) }
                }
                #elseif canImport(UIKit)
                _ = provider.loadObject(ofClass: UIImage.self) { obj, _ in
                    guard let img = obj as? UIImage, let data = img.pngData() else { return }
                    DispatchQueue.main.async { attach([data]) }
                }
                #endif
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    DispatchQueue.main.async { attach([data]) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                // Düz dosya yolu (Finder) — dosyayı oku, görselse ekle.
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    var url: URL?
                    if let u = item as? URL { url = u }
                    else if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                    guard let url, let data = try? Data(contentsOf: url), imageFromData(data) != nil else { return }
                    DispatchQueue.main.async { attach([data]) }
                }
            }
        }
        return accepted
    }

    #if os(macOS)
    /// "Herhangi bir yerden" görsel seç — Finder açma paneli (çoklu seçim).
    private func openFilePicker() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.prompt = "Ekle"
        guard panel.runModal() == .OK else { return }
        attach(panel.urls.compactMap { try? Data(contentsOf: $0) })
    }

    /// ⌘V — panoda görsel varsa (ve düz metin yoksa) composer'a yapıştırır ve olayı tüketir ki
    /// TextEditor görseli metne gömmesin. Sohbet sayfası görünürken (composer onAppear) aktif.
    private func installPasteMonitor() {
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "v" else { return event }
            let pb = NSPasteboard.general
            if let s = pb.string(forType: .string), !s.isEmpty { return event }  // metin → normal yapıştırma
            let datas = imagesFromPasteboard(pb)
            guard !datas.isEmpty else { return event }
            attach(datas)
            return nil
        }
    }

    private func removePasteMonitor() {
        if let monitor = pasteMonitor { NSEvent.removeMonitor(monitor); pasteMonitor = nil }
    }

    private func imagesFromPasteboard(_ pb: NSPasteboard) -> [Data] {
        if let urls = pb.readObjects(forClasses: [NSURL.self],
                                     options: [.urlReadingContentsConformToTypes: [UTType.image.identifier]]) as? [URL],
           !urls.isEmpty {
            let datas = urls.compactMap { try? Data(contentsOf: $0) }
            if !datas.isEmpty { return datas }
        }
        if let imgs = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage] {
            let datas = imgs.compactMap { $0.pngData() }
            if !datas.isEmpty { return datas }
        }
        return []
    }
    #endif

    // MARK: - Mention picker (@ ile veri etiketleme)

    /// İmlecin SOLUNDAKİ kelime `@` ile başlıyorsa, `@` sonrası query string döner.
    /// Metnin sonuna değil imlece bakıyoruz; yoksa cümle ortasına yazılan `@` menüyü açmıyordu.
    private var activeMentionQuery: String? {
        let text = store.input
        if let dismissed = dismissedAt, dismissed == text { return nil }

        // İmleç konumu henüz gelmediyse (ilk kare) metnin sonunu varsay.
        let cursor = min(max(caretLocation, 0), text.count)
        let head = String(text.prefix(cursor))
        if let last = head.last, last.isWhitespace || last.isNewline { return nil }
        let parts = head.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        guard let word = parts.last, word.hasPrefix("@") else { return nil }
        // Zaten tamamlanmış bir seçimin ("@Ölçümler[2026-06]") üstünde menü açma.
        guard !word.contains("]") else { return nil }
        return String(word.dropFirst())
    }

    private func filteredMentions(query: String) -> [MentionTag] {
        MentionTag.pickerCases.filter { $0.matches(prefix: query) }
    }

    private func clampedSelection(in count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((selectedMentionIndex % count) + count) % count
    }

    /// "@partial" yerine "@DisplayName " yerleştir. Etiket zaman serisi taşıyorsa önce
    /// aralık sorulur — tarih tahminini metinden çıkarmak yerine kullanıcı seçsin.
    private func insert(tag: MentionTag) {
        if tag.supportsRange {
            pendingRangeTag = tag
            pendingRanges = []
            selectedMentionIndex = 0
            return
        }
        commit(tag: tag, ranges: [])
    }

    /// Seçimi chip'e çevirir ve kullanıcının yazdığı `@...` parçasını metinden SİLER.
    /// Sohbet metnine token yazmıyoruz: hem çirkindi hem her aralık için menüyü yeniden
    /// açmayı gerektiriyordu.
    private func commit(tag: MentionTag, ranges: [MentionRange]) {
        let text = store.input
        let cursor = min(max(caretLocation, 0), text.count)
        let headEnd = text.index(text.startIndex, offsetBy: cursor)
        if let atIndex = text[..<headEnd].lastIndex(of: "@") {
            let afterAt = text.index(after: atIndex)
            let consumed = Self.matchedNameLength(in: text[afterAt...], of: tag.displayName)
            var replaceEnd = text.index(afterAt, offsetBy: consumed)
            if replaceEnd < text.endIndex, text[replaceEnd] == " " {
                replaceEnd = text.index(after: replaceEnd)
            }
            store.input = String(text[..<atIndex]) + String(text[replaceEnd...])
        }

        if let idx = attachments.firstIndex(where: { $0.tag == tag }) {
            // Aynı etiket ikinci kez seçilirse aralıkları BİRLEŞTİR, üstüne yazma.
            var merged = attachments[idx].ranges
            for r in ranges where !merged.contains(r) { merged.append(r) }
            attachments[idx].ranges = merged
        } else {
            attachments.append(ContextAttachment(tag: tag, ranges: ranges))
        }

        pendingRangeTag = nil
        pendingRanges = []
        selectedMentionIndex = 0
        inputFocused = true
    }

    /// `metin`in başındaki, `displayName`in bir ÖNEKİ olan en uzun parçanın uzunluğu.
    /// Türkçe aksanlara ve büyük/küçük harfe duyarsız; çok kelimeli adları da kapsar.
    private static func matchedNameLength(in text: Substring, of displayName: String) -> Int {
        let target = UserContextSnapshot.publicNormalize(displayName)
        var best = 0
        var probe = ""
        for (i, ch) in text.enumerated() {
            if i >= displayName.count { break }
            probe.append(ch)
            if target.hasPrefix(UserContextSnapshot.publicNormalize(probe)) {
                best = i + 1
            }
        }
        return best
    }

    /// Sunulan aralıklar: presetler + son 6 ay tek tek. Ay adları burada artık
    /// ayrıştırılmıyor, seçiliyor.
    private var rangeChoices: [MentionRange] {
        var out: [MentionRange] = [.today, .lastDays(7), .lastDays(30), .lastDays(90)]
        let cal = Calendar.current
        let now = Date.now
        for back in 0..<6 {
            guard let d = cal.date(byAdding: .month, value: -back, to: now) else { continue }
            out.append(.months(fromYear: cal.component(.year, from: d),
                               fromMonth: cal.component(.month, from: d),
                               toYear: cal.component(.year, from: d),
                               toMonth: cal.component(.month, from: d)))
        }
        return out
    }

    private func icon(for tag: MentionTag) -> String {
        switch tag {
        case .genelBakis: return "square.grid.2x2"
        case .olcumler:   return "list.bullet"
        case .grafikler:  return "chart.xyaxis.line"
        case .antrenman:  return "dumbbell"
        case .takvim:     return "calendar"
        case .kalori:     return "gauge.medium"
        case .yemekPlani: return "menucard"
        case .tarifler:   return "fork.knife"
        case .profil:     return "person.crop.circle"
        case .tahlil:     return "drop"
        case .hepsi:      return "sparkles"
        }
    }

    @ViewBuilder
    private func mentionPopup(query: String) -> some View {
        if let tag = pendingRangeTag {
            rangePopup(for: tag)
        } else {
            tagPopup(query: query)
        }
    }

    /// İkinci adım: tarih aralığı — ÇOKLU seçim. Tık tık işaretle, sonra Ekle.
    /// Tek seçimde her ay için menüyü baştan açmak gerekiyordu.
    private func rangePopup(for tag: MentionTag) -> some View {
        let choices = rangeChoices
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Lucide(sf: icon(for: tag), size: 11).foregroundStyle(ChatChrome.accent)
                Text(tag.displayName).font(Typography.bodyBold).foregroundStyle(ChatChrome.primary)
                Text("— aralık seç").font(Typography.caption).foregroundStyle(ChatChrome.tertiary)
                Spacer(minLength: 0)
                if !pendingRanges.isEmpty {
                    Text("\(pendingRanges.count) seçili")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ChatChrome.accent)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            Divider().opacity(0.5)

            ForEach(Array(choices.enumerated()), id: \.offset) { idx, range in
                let checked = pendingRanges.contains(range)
                let isSelected = idx == clampedSelection(in: choices.count)
                Button { toggleRange(range) } label: {
                    HStack(spacing: 9) {
                        Lucide(sf: checked ? "checkmark.square.fill" : "square", size: 11)
                            .foregroundStyle(checked ? ChatChrome.accent : ChatChrome.tertiary)
                            .frame(width: 18)
                        Text(range.displayLabel)
                            .font(Typography.body)
                            .foregroundStyle(checked ? ChatChrome.primary : ChatChrome.secondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? ChatChrome.whiteSoft : Color.clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { if $0 { selectedMentionIndex = idx } }
            }

            Divider().opacity(0.5)
            HStack(spacing: 8) {
                Text("Space işaretle · Enter ekle · Esc iptal")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(ChatChrome.quaternary)
                Spacer(minLength: 0)
                Button { commit(tag: tag, ranges: pendingRanges) } label: {
                    Text(pendingRanges.isEmpty ? "Aralıksız ekle" : "Ekle (\(pendingRanges.count))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(ChatChrome.ink)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(Capsule().fill(ChatChrome.accent))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
            .fill(ChatChrome.whiteSoft))
        .frame(maxWidth: 340, alignment: .leading)
    }

    private func toggleRange(_ range: MentionRange) {
        if let i = pendingRanges.firstIndex(of: range) { pendingRanges.remove(at: i) }
        else { pendingRanges.append(range) }
    }

    /// Composer'ın üstündeki veri chip'leri.
    private var attachmentStrip: some View {
        HStack(spacing: 6) {
            ForEach(attachments) { att in
                HStack(spacing: 6) {
                    Lucide(sf: icon(for: att.tag), size: 10).foregroundStyle(ChatChrome.accent)
                    Text(att.displayLabel)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(ChatChrome.primary)
                        .lineLimit(1)
                    Button { attachments.removeAll { $0.id == att.id } } label: {
                        Lucide(sf: "xmark", size: 8).foregroundStyle(ChatChrome.tertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(Capsule().fill(ChatChrome.whiteSoft))
                .overlay(Capsule().strokeBorder(ChatChrome.borderStrong, lineWidth: 0.5))
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func tagPopup(query: String) -> some View {
        let matches = filteredMentions(query: query)
        if !matches.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { idx, tag in
                    let isSelected = idx == clampedSelection(in: matches.count)
                    Button {
                        selectedMentionIndex = idx
                        insert(tag: tag)
                    } label: {
                        HStack(spacing: 9) {
                            Lucide(sf: icon(for: tag), size: 11)
                                .foregroundStyle(isSelected ? ChatChrome.accent : ChatChrome.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("@\(tag.displayName)")
                                    .font(Typography.bodyBold).foregroundStyle(ChatChrome.primary)
                                Text(tag.hintAlias)
                                    .font(Typography.caption)
                                    .foregroundStyle(isSelected ? ChatChrome.secondary : ChatChrome.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            if isSelected {
                                Lucide(sf: "return", size: 9).foregroundStyle(ChatChrome.secondary)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(isSelected ? ChatChrome.whiteSoft : Color.clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovering in if hovering { selectedMentionIndex = idx } }
                }
                Divider().opacity(0.5)
                HStack(spacing: 8) {
                    Label { Text("Enter/Tab seç") } icon: { Lucide(sf: "return") }.font(.system(size: 9, weight: .medium))
                    Text("·")
                    Label { Text("↑↓ gez") } icon: { Lucide(sf: "arrow.up.arrow.down") }.font(.system(size: 9, weight: .medium))
                    Text("·")
                    Label { Text("Esc kapat") } icon: { Lucide(sf: "escape") }.font(.system(size: 9, weight: .medium))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(ChatChrome.quaternary)
                .padding(.horizontal, 10).padding(.vertical, 6)
            }
            .padding(4)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(ChatChrome.whiteSoft))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var sendButton: some View {
        Button {
            if store.isSending { store.stop() } else { sendWithContext() }
        } label: {
            // Buzz gönder butonu: 32pt tam daire, primary dolgu (koyuda yakın-beyaz),
            // ArrowUp 16 — ComposerSendButton ile aynı dil.
            Lucide(sf: store.isSending ? "stop.fill" : "arrow.up", size: 14)
                .foregroundStyle(store.isSending ? ChatChrome.primary : (canSend ? ChatChrome.ink : ChatChrome.secondary))
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(store.isSending ? ChatChrome.panelPressed : (canSend ? ChatChrome.white : ChatChrome.whiteSoft))
                )
                .overlay(
                    Circle()
                        .strokeBorder(store.isSending ? ChatChrome.borderStrong : Color.clear, lineWidth: 0.6)
                )
        }
        .buttonStyle(.plain)
        .disabled(!store.isSending && !canSend)
        .help(store.isSending ? "Durdur" : "Gönder (↵)")
    }

    private var canSend: Bool {
        !store.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !store.pendingImages.isEmpty
    }

    private func sendWithContext() {
        guard canSend, !store.isSending else { return }
        // Etiketler iki kaynaktan gelebilir: composer chip'leri (picker) ve metne elle
        // yazılmış "@..." ifadeleri. Aralık YALNIZ chip'lerden gelir — metinden tarih
        // tahmini, chip varken hiç çalışmaz.
        let chipTags = Set(attachments.map(\.tag))
        let typedTags = UserContextSnapshot.parseMentions(store.input)
        let mentions = chipTags.union(typedTags)
        let allMentions = mentions.union(UserContextSnapshot.aboutMentionTags(ctx: ctx))
        let chipRange = attachments.compactMap(\.effectiveRange).first
        let snapshot = UserContextSnapshot.coachContext(
            for: store.input,
            explicitTags: mentions,
            ctx: ctx,
            explicitRange: chipRange
        )
        let skillScope = AgentDataScope.infer(query: store.input, explicitTags: allMentions)
        let skillData = AgentDataSnapshot.make(ctx: ctx, scope: skillScope)
        // Seçilen aralık mesajın kendisinde de görünsün: kullanıcı ne gönderdiğini
        // transcript'ten görebilmeli, chip gönderimle birlikte kayboluyor.
        if !attachments.isEmpty {
            let summary = attachments.map(\.displayLabel).joined(separator: " · ")
            let body = store.input.trimmingCharacters(in: .whitespacesAndNewlines)
            store.input = body.isEmpty ? "[Veri: \(summary)]" : body + "\n\n[Veri: \(summary)]"
        }
        store.startSend(userContext: snapshot, skillData: skillData, ctx: ctx)
        attachments = []
    }
}

/// Referanstaki ince, dolgudan çok kenar ve tipografiyle ayrışan takip önerisi.
private struct CoachSuggestionChip: View {
    let text: String
    let compact: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if !compact {
                    Lucide(sf: "arrow.up.right", size: 9)
                        .foregroundStyle(hovering ? ChatChrome.primary : ChatChrome.quaternary)
                }
                Text(text)
                    .font(.system(size: compact ? 10.5 : 12, weight: .regular))
                    .foregroundStyle(hovering ? ChatChrome.primary : ChatChrome.secondary)
                    .lineLimit(compact ? 1 : 2)
                    .multilineTextAlignment(.leading)
                if !compact { Spacer(minLength: 4) }
            }
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 6 : 10)
            .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
            // Buzz outline butonu: border-input/40 + bg-background, hover bg-muted/70.
            .background(
                RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                    .fill(hovering ? ChatChrome.panelRaised.opacity(0.7) : ChatChrome.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 8 : 10, style: .continuous)
                    .strokeBorder(hovering ? ChatChrome.borderStrong : ChatChrome.borderStrong.opacity(0.4), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

/// Transkriptteki ekli görsel karesi — diskten okuma ve decode `body` DIŞINDA,
/// `.task`'ta bir kez yapılır ve süreç ömrü boyunca (sınırlı) önbellekte kalır.
/// Hedef boyutta decode ediliyor: 132 pt'lik kare için tam çözünürlük açmak
/// hem CPU hem bellek israfıydı.
private struct CoachStoredThumb: View {
    let id: String
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image.resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(ChatChrome.panel)
            }
        }
        .frame(width: 132, height: 132)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
            .strokeBorder(ChatChrome.borderStrong, lineWidth: 1))
        .task(id: id) {
            if let cached = await CoachChatThumbCache.shared.image(for: id) {
                image = cached
            }
        }
    }
}

/// Sınırlı (NSCache) decode önbelleği — bellek baskısında kendini boşaltır.
@MainActor
private final class CoachChatThumbCache {
    static let shared = CoachChatThumbCache()

    private let cache: NSCache<NSString, ImageBox> = {
        let c = NSCache<NSString, ImageBox>()
        c.countLimit = 60
        return c
    }()

    private final class ImageBox { 
        let image: Image
        init(_ image: Image) { self.image = image }
    }

    func image(for id: String) async -> Image? {
        if let hit = cache.object(forKey: id as NSString) { return hit.image }
        // Disk okuma + yeniden boyutlandırma arka planda; platform görseli main'de
        // kurulur (NSImage/UIImage ve Image sınır ötesine taşınmaz).
        guard let small = await Task.detached(priority: .userInitiated, operation: { () -> Data? in
            guard let data = ChatImageStore.load(id) else { return nil }
            return ChatImageStore.downscaledJPEG(from: data, maxPixel: 320) ?? data
        }).value else { return nil }

        #if canImport(AppKit)
        guard let platform = NSImage(data: small) else { return nil }
        let decoded = Image(nsImage: platform)
        #else
        guard let platform = UIImage(data: small) else { return nil }
        let decoded = Image(uiImage: platform)
        #endif
        cache.setObject(ImageBox(decoded), forKey: id as NSString)
        return decoded
    }
}
