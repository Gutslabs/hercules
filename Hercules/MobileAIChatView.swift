import SwiftUI
import SwiftData
import LucideKit
import PhotosUI
import UIKit
import ImageIO
import UniformTypeIdentifiers

struct MobileAIChatView: View {
    let userContext: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.modelContext) private var modelContext
    /// Geçmiş `.task`'ta bir kez yüklenir. `@State` varsayılanı view struct'ının
    /// init'inde çalışır; MobileRootView.body her yenilendiğinde (11 canlı @Query'den
    /// herhangi biri değişince) UserDefaults okuyup 40 turu JSON decode ediyordu.
    @State private var messages: [ChatTurn] = []
    @State private var didLoadHistory = false
    @State private var input = ""
    @State private var isSending = false
    @State private var errorText: String?
    @State private var health: RemoteAIHealthResponse?
    @State private var healthError: String?
    @State private var sendTask: Task<Void, Never>?
    @State private var composerTextFieldFrame: CGRect = .zero
    @State private var pendingImages: [MobilePendingImage] = []
    @State private var isLoadingAttachments = false
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var attachStage: MobileAttachStage = .composer
    @State private var showPhotoLibrary = false
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var nearBottom = true
    @FocusState private var composerFocused: Bool

    private let suggestions: [(title: String, prompt: String)] = [
        ("Bugün", "Bugünkü verilerime göre kısa bir değerlendirme yap."),
        ("Beslenme", "Bu hafta beslenmede en çok neyi düzeltmeliyim?"),
        ("Antrenman", "Son ölçümlerime göre antrenman öner.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Palette.border).frame(height: 0.5)

            ScrollViewReader { proxy in
                GeometryReader { viewport in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18) {
                            if messages.isEmpty { emptyState }
                            ForEach(messages) { turn in
                                messageRow(turn)
                                    .id(turn.id)
                                    .transition(messageTransition)
                            }
                            if isSending {
                                thinkingRow
                                    .id("thinking")
                                    .transition(messageTransition)
                            }
                            if let errorText {
                                errorRow(errorText)
                                    .id("error")
                                    .transition(messageTransition)
                            }
                            // En-alt çapası + dibe-yakınlık ölçümü (aşağı-in butonu için).
                            Color.clear.frame(height: 1).id("coachBottom")
                                .background(GeometryReader { geo in
                                    Color.clear.preference(
                                        key: MobileChatNearBottomKey.self,
                                        value: geo.frame(in: .named(MobileAIChatCoordinateSpace.name)).maxY
                                            - viewport.size.height < 90
                                    )
                                })
                        }
                        .padding(.top, 22)
                        .padding(.bottom, 20)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .defaultScrollAnchor(.bottom)   // kısa sohbet alta yaslanır
                    .onPreferenceChange(MobileChatNearBottomKey.self) { nearBottom = $0 }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                    .onChange(of: isSending) { _, sending in
                        if sending { withAnimation { proxy.scrollTo("thinking", anchor: .bottom) } }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if !nearBottom {
                            Button {
                                withAnimation { proxy.scrollTo("coachBottom", anchor: .bottom) }
                            } label: {
                                Lucide(sf: "arrow.down", size: 14)
                                    .foregroundStyle(Palette.textPrimary)
                                    .frame(width: 34, height: 34)
                                    .background(Circle().fill(Palette.surface))
                                    .overlay(Circle().strokeBorder(Palette.border, lineWidth: 1))
                                    .shadow(color: Palette.cardShadow, radius: 6, y: 2)
                            }
                            .buttonStyle(.plain)
                            .padding(.trailing, 16)
                            .padding(.bottom, 12)
                            .transition(.opacity.combined(with: .scale(scale: 0.85)))
                            .accessibilityLabel("En alta in")
                        }
                    }
                    .animation(.easeInOut(duration: 0.18), value: nearBottom)
                }
            }
            // Panel açıkken transkripte dokunmak onu kapatır (video: kabın dışına dokun → geri kapan).
            .overlay {
                if attachStage.isOpen {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { closeAttach() }
                }
            }
            VStack(spacing: 0) {
                if !pendingImages.isEmpty || isLoadingAttachments {
                    pendingImagesStrip
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                attachSurface
            }
            .padding(.bottom, MobileChrome.composerClearance)
            // Transkript composer'ın altına doğru sessizce siliniyor.
            .background(
                LinearGradient(
                    colors: [Palette.background.opacity(0), Palette.background, Palette.background],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.28)
                )
                .allowsHitTesting(false)
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
        .coordinateSpace(name: MobileAIChatCoordinateSpace.name)
        .onPreferenceChange(MobileAIComposerFramePreferenceKey.self) { frame in
            composerTextFieldFrame = frame
        }
        .simultaneousGesture(
            SpatialTapGesture().onEnded { tap in
                guard composerFocused, !composerTextFieldFrame.contains(tap.location) else { return }
                composerFocused = false
            }
        )
        .task {
            if !didLoadHistory {
                didLoadHistory = true
                messages = MobileAIChatHistory.load()
                // Yalnız geçmiş yüklendikten sonra karar ver: yarım kalan tur uyarısı
                // boş listeye bakıp yanlış zamanda tetiklenmesin.
                if !isSending, messages.last?.role == .user {
                    errorText = "Önceki yanıt tamamlanmadı."
                }
            }
            await refreshHealth()
        }
        .onDisappear {
            composerFocused = false
            attachStage = .composer
            // Sekme değişince view (ve @State'i) yok oluyor; iptal edilmeyen istek
            // görünmez şekilde ağda kalıp bitince ESKİ mesaj dizisini diske yazarak
            // yeni geçmişin üstüne yazabiliyordu.
            sendTask?.cancel()
            sendTask = nil
        }
        .fileImporter(
            isPresented: $showFiles,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in loadImportedFiles(result) }
        .photosPicker(
            isPresented: $showPhotoLibrary,
            selection: $pickerItems,
            maxSelectionCount: 4,
            matching: .images,
            preferredItemEncoding: .current
        )
        .onChange(of: pickerItems) { _, items in loadPickedImages(items) }
        .fullScreenCover(isPresented: $showCamera) {
            MobileCameraPicker { image in
                showCamera = false
                guard let image else { return }
                isLoadingAttachments = true
                Task {
                    if let pending = await Self.preparePending(camera: image) {
                        appendPending([pending])
                    } else {
                        errorText = "Fotoğraf işlenemedi. Tekrar dener misin?"
                    }
                    isLoadingAttachments = false
                }
            }
            .ignoresSafeArea()
        }
    }

    /// Sayfa başlığı değil sohbet başlığı — avatar + ad + durum.
    private var header: some View {
        HStack(spacing: 10) {
            MobileCoachAvatar(active: isSending)
            Text("Koç")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(Palette.textPrimary)
            Spacer()
            Button { Task { await refreshHealth() } } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(connectionColor)
                        .frame(width: 5, height: 5)
                    Text(isSending ? "çalışıyor" : (health != nil ? "hazır" : "bağlı değil"))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(health == nil ? "Koç bağlantısını yenile" : "Koç bağlı")

            Button { newChat() } label: {
                Lucide(sf: "square.and.pencil", size: 15)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Yeni sohbet")
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 54)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Başlık kayan parlaklıkla karşılıyor (düz bold değil).
            VStack(alignment: .leading, spacing: 6) {
                MobileCoachShimmerText(
                    text: "Ne sormak istersin?",
                    font: .system(size: 24, weight: .semibold),
                    base: Palette.textPrimary,
                    shimmer: Palette.textQuaternary,
                    cycleLimit: 3
                )
                Text("Hedeflerin, ölçümlerin, öğünlerin ve antrenmanların üzerinden birlikte ilerleyelim.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textQuaternary)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, 28)

            ForEach(Array(suggestions.enumerated()), id: \.offset) { _, suggestion in
                HStack(spacing: 7) {
                    Circle().fill(Palette.accent).frame(width: 5, height: 5)
                    Text(suggestion.title.uppercased(with: Locale(identifier: "tr_TR")))
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(1)
                        .foregroundStyle(Palette.textTertiary)
                }
                Button {
                    input = suggestion.prompt
                    send()
                } label: {
                    HStack(spacing: 10) {
                        Text(suggestion.prompt)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.textPrimary)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                        Lucide(sf: "arrow.up.right", size: 11)
                            .foregroundStyle(Palette.textQuaternary)
                    }
                    .padding(.vertical, 12)
                    .overlay(Rectangle().fill(Palette.border).frame(height: 1), alignment: .bottom)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 18)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
    }

    @ViewBuilder
    private func messageRow(_ turn: ChatTurn) -> some View {
        if turn.role == .user {
            VStack(alignment: .trailing, spacing: 6) {
                if let ids = turn.imageIDs, !ids.isEmpty {
                    attachmentThumbs(ids)
                }
                HStack(alignment: .top, spacing: 8) {
                    Spacer(minLength: 36)
                    Text(turn.text)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.textPrimary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 15)
                        .padding(.vertical, 10)
                        .background(userBubbleShape.fill(Palette.surfaceElevated))
                        .frame(maxWidth: 310, alignment: .trailing)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 20)
        } else {
            HStack(alignment: .top, spacing: 10) {
                MobileCoachAvatar(active: false)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 7) {
                    if let searched = turn.searchedFor {
                        HStack(spacing: 5) {
                            Lucide(sf: "globe", size: 9)
                            Text("Web'de arandı: \"\(searched)\"")
                                .font(Typography.caption)
                        }
                        .foregroundStyle(Palette.textTertiary)
                    }
                    Text(turn.text)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Palette.textPrimary)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if let food = turn.food { foodSummary(food, turn: turn) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
        }
    }

    private var thinkingRow: some View {
        HStack(alignment: .top, spacing: 10) {
            AgentThinkingGlyph(tint: Palette.textPrimary, dim: Palette.textQuaternary)
            MobileCoachShimmerText(text: "Düşünüyor…")
                .frame(minHeight: 28, alignment: .center)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 2)
    }

    private func errorRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Lucide("wifi-off", size: 14)
                .foregroundStyle(Palette.negative)
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if messages.last?.role == .user {
                    Button("Tekrar dene") { retryLast() }
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                        .buttonStyle(.plain)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
    }

    /// Composer'ın kendisi ek panelidir — aynı kap büyüyerek menüye, oradan
    /// fotoğraf ızgarasına dönüşür. Ayrı sheet/action sheet yok.
    private var attachSurface: some View {
        MobileAttachSurface(
            stage: $attachStage,
            onCamera: { showCamera = true },
            onFiles: { showFiles = true },
            onAllPhotos: { showPhotoLibrary = true },
            onPick: { data in
                isLoadingAttachments = true
                Task {
                    if let pending = await Self.preparePending(raw: data) {
                        appendPending([pending])
                    } else {
                        errorText = "Fotoğraf işlenemedi. Tekrar dener misin?"
                    }
                    isLoadingAttachments = false
                }
            },
            composerFocused: composerFocused,
            composer: { composer }
        )
        .background {
            MobileCoachComposerGlow(active: isSending && !reduceMotion, cornerRadius: 15)
                .padding(-4)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    /// Mobil composer dili: yazı alanı ÜSTTE tam genişlik, eylemler ALTTA aynı
    /// kabın içinde. Telefonda tek satırlık HStack'e göre çok daha fazla yazma alanı.
    /// Kap (zemin/kenar/köşe) MobileAttachSurface'ın — burası yalnız içerik.
    private var composer: some View {
        VStack(spacing: 0) {
            TextField(
                "",
                text: $input,
                prompt: Text("Koç'a sor…").foregroundStyle(Palette.textQuaternary),
                axis: .vertical
            )
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .tint(Palette.accent.opacity(0.7))
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 34, alignment: .top)
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .background {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: MobileAIComposerFramePreferenceKey.self,
                            value: proxy.frame(in: .named(MobileAIChatCoordinateSpace.name))
                        )
                    }
                }
                .focused($composerFocused)
                .submitLabel(.send)
                .onSubmit { send() }

            composerToolbar
        }
        .padding(4)
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.16), value: canSend)
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.16), value: isSending)
    }

    /// Kabın İÇİNDEki alt eylem şeridi.
    private var composerToolbar: some View {
        HStack(spacing: 4) {
            attachButton
            Spacer(minLength: 8)
            sendButton
        }
        .padding(.leading, 6)
        .padding(.trailing, 2)
        .padding(.bottom, 2)
    }

    /// Daire değil, 3pt köşeli kağıt-beyazı kare.
    private var sendButton: some View {
        Button {
            isSending ? stop() : send()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(canSend || isSending ? Palette.accent : Palette.fieldFill)
                if isSending {
                    Lucide(sf: "stop.fill", size: 12.5)
                        .foregroundStyle(Palette.btnFg)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                } else {
                    Lucide(sf: "arrow.up", size: 12.5)
                        .foregroundStyle(canSend ? Palette.btnFg : Palette.textQuaternary)
                        .transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .frame(width: 32, height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(MobileCoachSendButtonStyle())
        .disabled(!canSend && !isSending)
        .accessibilityLabel(isSending ? "Yanıtı durdur" : "Gönder")
    }

    private var canSend: Bool {
        (!input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !pendingImages.isEmpty)
            && !isSending && !isLoadingAttachments
    }

    /// Video referansındaki "+" — menüyü açarken 45° dönüp kapatma jestine dönüşür.
    private var attachButton: some View {
        Button {
            composerFocused = false
            withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
                attachStage = attachStage.isOpen ? .composer : .menu
            }
        } label: {
            Lucide(sf: "plus", size: 16)
                .foregroundStyle(isSending ? Palette.textQuaternary : Palette.textSecondary)
                .rotationEffect(.degrees(attachStage.isOpen ? 45 : 0))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSending)
        .accessibilityLabel(attachStage.isOpen ? "Ek panelini kapat" : "Ek ekle")
    }

    private func closeAttach() {
        withAnimation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)) {
            attachStage = .composer
        }
    }

    /// Dosyalar uygulamasından gelen görselleri composer'a ekler (security-scoped okuma).
    private func loadImportedFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else {
            if case .failure = result { errorText = "Dosya açılamadı." }
            return
        }
        isLoadingAttachments = true
        Task {
            var prepared: [MobilePendingImage] = []
            for url in urls.prefix(4) {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard let raw = try? Data(contentsOf: url),
                      let pending = await Self.preparePending(raw: raw) else { continue }
                prepared.append(pending)
            }
            if prepared.isEmpty {
                errorText = "Seçilen dosya okunamadı."
            } else {
                appendPending(prepared)
            }
            isLoadingAttachments = false
        }
    }

    private var pendingImagesStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingImages) { item in
                    ZStack(alignment: .topTrailing) {
                        Image(uiImage: item.thumb)
                            .resizable().scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        Button {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                                pendingImages.removeAll { $0.id == item.id }
                            }
                        } label: {
                            Lucide(sf: "xmark.circle.fill", size: 16)
                                .foregroundStyle(.white, .black.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                        .padding(3)
                    }
                }
                if isLoadingAttachments {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Palette.surface)
                        .frame(width: 56, height: 56)
                        .overlay(ProgressView().controlSize(.small))
                }
            }
            .padding(.horizontal, 2)
        }
    }

    private var connectionColor: Color {
        if health != nil { return Palette.positive }
        if healthError != nil { return Palette.negative }
        return Palette.textQuaternary
    }

    private var messageTransition: AnyTransition {
        reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6))
    }

    private var userBubbleShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 14,
            bottomLeadingRadius: 14,
            bottomTrailingRadius: 4,
            topTrailingRadius: 14,
            style: .continuous
        )
    }

    private func send() {
        let rawText = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let images = pendingImages.map(\.data)
        guard (!rawText.isEmpty || !images.isEmpty), !isSending, !isLoadingAttachments else { return }
        // Görsel-yalnız mesajda modele/UI'a anlamlı bir metin ver.
        let text = (rawText.isEmpty && !images.isEmpty) ? "Bu görsele bakar mısın?" : rawText
        composerFocused = false
        let history = messages

        // Görselleri diske kaydet; tura id'leriyle bağla. Modele giden bayt zaten
        // elimizde (preparePending 1280px'e küçültmüştü) — eskiden gönder'e basınca
        // aynı veriyi ana thread'de yeniden decode+encode edip diske yazıyor, sonra
        // geri OKUYORDUK. Kayıt artık arka planda, gönderimi bekletmeden.
        let imageIDs = images.map { _ in UUID().uuidString }
        if !imageIDs.isEmpty {
            let pairs = Array(zip(imageIDs, images))
            Task.detached(priority: .utility) {
                for (id, data) in pairs { ChatImageStore.save(data, id: id) }
            }
        }

        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
            messages.append(ChatTurn(role: .user, text: text, imageIDs: imageIDs.isEmpty ? nil : imageIDs))
        }
        input = ""
        pendingImages = []
        MobileAIChatHistory.save(messages)
        beginRequest(text: text, images: images, history: history)
    }

    private func beginRequest(text: String, images: [Data] = [], history: [ChatTurn]) {
        errorText = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            isSending = true
        }
        sendTask = Task {
            do {
                let client = RemoteAIClient()
                health = try await client.health()
                healthError = nil
                try Task.checkCancellation()
                let (result, searchEvidence) = try await client.send(
                    history: history,
                    newUserText: text,
                    userContext: userContext,
                    images: images,
                    onSearchStart: { _ in },
                    onMessageUpdate: { _ in }
                )
                try Task.checkCancellation()
                let answer = result.message.trimmingCharacters(in: .whitespacesAndNewlines)
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    messages.append(ChatTurn(
                        role: .assistant,
                        text: answer.isEmpty ? (result.name ?? "Yanıt boş geldi.") : answer,
                        food: result.isFood ? result : nil,
                        actions: result.actionList,
                        searchedFor: (
                            searchEvidence?.completedSuccessfully == true
                            && searchEvidence?.sourceURLs.isEmpty == false
                        ) ? searchEvidence?.query : nil
                    ))
                }
                healthError = nil
                MobileAIChatHistory.save(messages)
            } catch is CancellationError {
                errorText = nil
            } catch {
                errorText = MobileAIChatHistory.friendlyError(error)
                health = nil
                healthError = "Koç çevrimdışı"
            }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
                isSending = false
            }
            sendTask = nil
        }
    }

    private func retryLast() {
        guard !isSending,
              let index = messages.lastIndex(where: { $0.role == .user })
        else { return }
        let turn = messages[index]
        let images = (turn.imageIDs ?? []).compactMap { ChatImageStore.load($0) }
        beginRequest(text: turn.text, images: images, history: Array(messages.prefix(index)))
    }

    private func stop() {
        sendTask?.cancel()
        sendTask = nil
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            isSending = false
        }
    }

    private func newChat() {
        stop()
        // Sohbetin görselleri de gitsin: eskiden JPEG'ler Application Support'ta
        // sonsuza dek öksüz kalıyordu (geçmiş 40 turla sınırlı, dosyalar sınırsız).
        let orphaned = messages.flatMap { $0.imageIDs ?? [] }
        if !orphaned.isEmpty {
            Task.detached(priority: .utility) {
                for id in orphaned { ChatImageStore.delete(id) }
            }
        }
        messages = []
        input = ""
        pendingImages = []
        errorText = nil
        MobileAIChatHistory.save([])
    }

    @MainActor
    private func refreshHealth() async {
        do {
            health = try await RemoteAIClient().health()
            healthError = nil
        } catch {
            health = nil
            healthError = "Koç çevrimdışı"
        }
    }

    private func foodSummary(_ food: AIFoodResult, turn: ChatTurn) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(food.name ?? "Öğün")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    if let grams = food.grams {
                        Text("\(Fmt.int(grams)) g")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textQuaternary)
                    }
                }
                Spacer(minLength: 8)
                if let calories = food.calories {
                    Text("\(Fmt.int(calories)) kcal")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .padding(12)

            Rectangle().fill(Palette.border).frame(height: 0.5)
            Button { saveFood(turn) } label: {
                HStack(spacing: 6) {
                    Lucide(sf: turn.saved ? "checkmark.circle.fill" : "plus.circle.fill", size: 12)
                    Text(turn.saved ? "Bugüne eklendi" : "Bugüne ekle")
                        .font(Typography.captionBold)
                }
                .foregroundStyle(turn.saved ? Palette.positive : Palette.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(turn.saved)
        }
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.18), value: turn.saved)
    }

    /// Koç kartındaki yemeği bugünün öğünlerine FoodEntry olarak yazar (Mac ChatStore.saveFood paritesi).
    private func saveFood(_ turn: ChatTurn) {
        guard let food = turn.food, let calories = food.calories, !turn.saved else { return }
        let entry = FoodEntry(
            date: .now,
            name: food.name?.nilIfBlank ?? "AI yemek",
            grams: food.grams,
            calories: calories,
            protein: food.protein_g,
            carbs: food.carbs_g,
            fat: food.fat_g
        )
        modelContext.insert(entry)
        guard modelContext.saveOrReport("Koç yemeğini bugüne ekleme") else { return }
        if let idx = messages.firstIndex(where: { $0.id == turn.id }) {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                messages[idx].saved = true
            }
            MobileAIChatHistory.save(messages)
        }
    }

    /// Kullanıcının mesaja iliştirdiği görseller — balonun üstünde, sağa hizalı küçük resimler.
    private func attachmentThumbs(_ ids: [String]) -> some View {
        HStack(spacing: 6) {
            ForEach(ids, id: \.self) { MobileStoredThumb(id: $0) }
        }
    }

    private func loadPickedImages(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        isLoadingAttachments = true
        Task {
            var loaded: [MobilePendingImage] = []
            for item in items {
                guard let raw = await Self.loadPickerData(item, timeout: 25) else { continue }
                if let pending = await Self.preparePending(raw: raw) { loaded.append(pending) }
            }
            appendPending(loaded)
            if loaded.count < items.count {
                errorText = loaded.isEmpty
                    ? "Fotoğraf yüklenemedi — iCloud'dan inmemiş olabilir. Wi-Fi'da tekrar dener misin?"
                    : "Bazı fotoğraflar yüklenemedi."
            }
            pickerItems = []
            isLoadingAttachments = false
        }
    }

    /// loadTransferable, iCloud indirmesi/transcode yüzünden çok uzayabiliyor ya da hiç dönmüyor —
    /// spinner'ın sonsuza kadar dönmemesi için süre sınırıyla yarıştırılır.
    nonisolated private static func loadPickerData(_ item: PhotosPickerItem, timeout seconds: Double) async -> Data? {
        await withTaskGroup(of: Data?.self) { group in
            group.addTask {
                if let data = try? await item.loadTransferable(type: Data.self) { return data }
                // Picker ilk denemede boş dönebiliyor — bir kez daha dene.
                return try? await item.loadTransferable(type: Data.self)
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(seconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func appendPending(_ items: [MobilePendingImage]) {
        guard !items.isEmpty else { return }
        let room = max(0, 4 - pendingImages.count)
        guard room > 0 else { return }
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
            pendingImages.append(contentsOf: items.prefix(room))
        }
    }

    /// Ham kütüphane verisini arka planda 1280px JPEG'e küçültür + strip için küçük decode üretir.
    /// pendingImages'ta hep KÜÇÜK veri durur; tam çözünürlük asla UI state'ine girmez.
    nonisolated private static func preparePending(raw: Data) async -> MobilePendingImage? {
        let small = ChatImageStore.downscaledJPEG(from: raw) ?? raw
        guard let thumb = decodedChatThumb(from: small, maxPixel: 320) else { return nil }
        return MobilePendingImage(data: small, thumb: thumb)
    }

    /// Kamera çekimini arka planda küçültüp JPEG'e çevirir (tam çözünürlük JPEG encode main'i kilitliyordu).
    nonisolated private static func preparePending(camera image: UIImage) async -> MobilePendingImage? {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let scale = min(1, 1280 / max(pixelWidth, pixelHeight, 1))
        let target = CGSize(width: pixelWidth * scale, height: pixelHeight * scale)
        let small = await image.byPreparingThumbnail(ofSize: target) ?? image
        guard let data = small.jpegData(compressionQuality: 0.78),
              let thumb = decodedChatThumb(from: data, maxPixel: 320) else { return nil }
        return MobilePendingImage(data: data, thumb: thumb)
    }
}

/// Composer'da bekleyen görsel: modele gidecek küçültülmüş JPEG + strip için hazır decode edilmiş thumbnail.
private struct MobilePendingImage: Identifiable {
    let id = UUID()
    let data: Data
    let thumb: UIImage
}

/// Veriyi hedef piksel boyutunda decode eder — tam çözünürlük decode etmekten çok daha ucuz.
private func decodedChatThumb(from data: Data, maxPixel: CGFloat) -> UIImage? {
    guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel
    ]
    guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
    return UIImage(cgImage: thumb)
}

/// Transkript görselleri için decode önbelleği — her body yenilenişinde (örn. her tuş vuruşu)
/// diskten okuyup tam boy decode etmeyi engeller.
@MainActor
private enum MobileChatThumbCache {
    /// NSCache: düz sözlük hiç boşalmıyordu — oturum boyunca görülen her 360 px
    /// decode'u kalıcı tutuyordu. NSCache bellek baskısında kendini boşaltır.
    private static let cache: NSCache<NSString, UIImage> = {
        let c = NSCache<NSString, UIImage>()
        c.countLimit = 60
        return c
    }()

    static func image(for id: String) async -> UIImage? {
        if let hit = cache.object(forKey: id as NSString) { return hit }
        guard let decoded = await decode(id) else { return nil }
        cache.setObject(decoded, forKey: id as NSString)
        return decoded
    }

    nonisolated private static func decode(_ id: String) async -> UIImage? {
        guard let data = ChatImageStore.load(id) else { return nil }
        return decodedChatThumb(from: data, maxPixel: 360)
    }
}

/// Mesaja bağlı tek görsel karesi — decode'u task'ta yapıp state'te tutar.
private struct MobileStoredThumb: View {
    let id: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Palette.surface)
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            }
        }
        .frame(width: 112, height: 112)
        .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
        .task(id: id) {
            if image == nil { image = await MobileChatThumbCache.image(for: id) }
        }
    }
}

/// Kamera ile tek çekim → UIImage (nil = iptal). PhotosPicker kamerayı açamadığı için UIKit köprüsü.
/// Kapanma çağıranın state'iyle yapılır (@Environment(\.dismiss) coordinator kopyasında güvenilir değil).
private struct MobileCameraPicker: UIViewControllerRepresentable {
    var onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        private let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

private struct MobileCoachAvatar: View {
    let active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if active { halo }
            Circle().fill(Palette.surfaceElevated)
            Lucide(LIcon.ai, size: 12)
                .foregroundStyle(Palette.accent)
        }
        .frame(width: 28, height: 28)
        .overlay(Circle().strokeBorder(Palette.border, lineWidth: 0.5))
    }

    /// Nabız `TimelineView`'dan sürülür, `withAnimation(.repeatForever)`'dan DEĞİL:
    /// o desen view ağaçtan çıkınca render döngüsünü ekran tazeleme hızında dönmeye
    /// devam ettiriyor (bkz. `Pulse` dokümanı). Sohbet listesinde avatarlar kaydırma
    /// boyunca sürekli görünüp kaybolduğu için her biri ayrı bir sızıntı bırakıyordu.
    @ViewBuilder private var halo: some View {
        if reduceMotion {
            Circle()
                .fill(Palette.accent.opacity(0.12))
                .scaleEffect(0.86)
                .opacity(0.75)
        } else {
            TimelineView(.animation) { tl in
                let b = Pulse.breathe(tl.date, period: 1.8, 0, 1)
                Circle()
                    .fill(Palette.accent.opacity(0.12))
                    .scaleEffect(0.86 + 0.32 * b)
                    .opacity(0.75 - 0.57 * b)
            }
        }
    }
}

private struct MobileCoachSendButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(
                reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.76),
                value: configuration.isPressed
            )
    }
}

/// Masaüstü Koç composer'ındaki dönen renk akışının mobil karşılığı.
private struct MobileCoachComposerGlow: View {
    let active: Bool
    let cornerRadius: CGFloat

    private let colors: [Color] = [
        Color(red: 0.031, green: 0.580, blue: 1.000),
        Color(red: 0.788, green: 0.349, blue: 0.867),
        Color(red: 1.000, green: 0.180, blue: 0.329),
        Color(red: 1.000, green: 0.565, blue: 0.016)
    ]

    var body: some View {
        TimelineView(.animation(paused: !active)) { timeline in
            let degrees = (timeline.date.timeIntervalSinceReferenceDate * 55)
                .truncatingRemainder(dividingBy: 360)
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    AngularGradient(
                        gradient: Gradient(colors: colors + [colors[0]]),
                        center: .center,
                        angle: .degrees(degrees)
                    ),
                    lineWidth: 3
                )
                .blur(radius: 9)
        }
        .opacity(active ? 0.9 : 0)
        .animation(.easeOut(duration: 0.24), value: active)
        .allowsHitTesting(false)
    }
}

/// Koç'un ilk-token öncesi durumuyla aynı, metin boyunca kayan sakin ışık bandı.
private struct MobileCoachShimmerText: View {
    let text: String
    /// Boş-ekran başlığı da bunu kullanıyor → font/renkler dışarıdan verilebilir.
    var font: Font = Typography.caption
    var base: Color = Palette.textTertiary
    var shimmer: Color = Palette.textPrimary
    /// Kaç tur döndükten sonra dursun. "Düşünüyor" göstergesi zaten kısa ömürlü
    /// (nil = sınırsız); boş ekran başlığı ise kullanıcı orada okurken sonsuza dek
    /// ekranı 60/120 Hz yeniden çizdiriyordu — birkaç tur sonra donuyor.
    var cycleLimit: Int? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var finished = false

    var body: some View {
        if reduceMotion || finished {
            label.foregroundStyle(base)
        } else {
            TimelineView(.animation) { timeline in
                let duration = 2.4
                let progress = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: duration) / duration
                label
                    .foregroundStyle(base)
                    .overlay {
                        GeometryReader { geometry in
                            let width = geometry.size.width
                            LinearGradient(
                                colors: [.clear, shimmer, .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: width * 0.55)
                            .offset(x: -width * 0.55 + (width * 1.55 * progress))
                        }
                        .mask(label)
                    }
            }
            .task(id: text) {
                guard let cycleLimit else { return }
                try? await Task.sleep(for: .seconds(2.4 * Double(cycleLimit)))
                finished = true
            }
        }
    }

    private var label: some View {
        Text(text)
            .font(font)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private enum MobileAIChatCoordinateSpace {
    static let name = "hercules.mobile-ai-chat"
}

/// Dibe-yakınlık sinyali (aşağı-in butonu görünürlüğü).
private struct MobileChatNearBottomKey: PreferenceKey {
    static let defaultValue = true
    static func reduce(value: inout Bool, nextValue: () -> Bool) { value = nextValue() }
}

private struct MobileAIComposerFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private enum MobileAIChatHistory {
    private static let key = "hercules.mobile.remote-ai.chat.v1"
    private static let maxTurns = 40

    static func load() -> [ChatTurn] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let turns = try? JSONDecoder().decode([ChatTurn].self, from: data)
        else { return [] }
        return Array(turns.suffix(maxTurns))
    }

    static func save(_ turns: [ChatTurn]) {
        let kept = Array(turns.suffix(maxTurns))
        if kept.isEmpty {
            UserDefaults.standard.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(kept) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    static func friendlyError(_ error: Error) -> String {
        if case RemoteAIClientError.server(let status, _) = error {
            if status == 429 { return "Koç şu an önceki isteği tamamlıyor. Birazdan tekrar dene." }
            if status == 403 { return "Koç bağlantısı bu cihaz için yetkili değil." }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost, .timedOut:
                return "Koç'a bağlanamadım. Tailscale bağlantını kontrol edip tekrar dene."
            case .cancelled:
                return ""
            default:
                break
            }
        }
        return "Koç yanıt veremedi. Birazdan tekrar dene."
    }
}
