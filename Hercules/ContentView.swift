import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif
#if os(macOS)
import WebKit
#endif

// MARK: - Navigation tabs

enum NavTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard, measurements, charts, workout, analysis, calendar, recipes, chat, profile, progress, fotolar
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard:    return "Genel Bakış"
        case .progress:     return "İlerleme"
        case .fotolar:      return "Fotoğraflar"
        case .measurements: return "Ölçümler"
        case .charts:       return "Grafikler"
        case .workout:      return "Antrenman"
        case .analysis:     return "Analiz"
        case .calendar:     return "Öğün Takip"
        case .recipes:      return "Tarifler"
        case .chat:         return "Sohbet"
        case .profile:      return "Profil"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard:    return "square.grid.2x2"
        case .progress:     return "target"
        case .fotolar:      return "camera"
        case .measurements: return "list.bullet"
        case .charts:       return "chart.xyaxis.line"
        case .workout:      return "dumbbell"
        case .analysis:     return "gauge.medium"
        case .calendar:     return "calendar"
        case .recipes:      return "fork.knife"
        case .chat:         return "bubble.left.and.text.bubble.right"
        case .profile:      return "person.crop.circle"
        }
    }
}

/// Sidebar grupları — GENEL / VERİLER / BESLENME. Her grup sidebar'da açılır-kapanır bir
/// başlık satırı olarak çizilir; çocuklar içeride girintili durur.
/// (Sohbet nav'dan çıktı: "Koç'a sor" butonu chat panelini açar.
///  Fotoğraflar ikincil bölgede — bkz. HerculesSidebar.
///  Hafıza ve sistem promptları Profil'in sekmeleri.)
enum NavCategory: String, CaseIterable, Identifiable, Hashable {
    case genel, takip, beslenme

    var id: String { rawValue }

    var label: String {
        switch self {
        // "Takip" yerine "Veriler": grubun içi Ölçümler/Grafikler/Antrenman, yani ham veri.
        // Öğün takibi Beslenme'de duruyor, iki "takip" olması kafa karıştırıyordu.
        case .genel:    return "Genel"
        case .takip:    return "Veriler"
        case .beslenme: return "Beslenme"
        }
    }

    var tabs: [NavTab] {
        switch self {
        case .genel:    return [.dashboard, .analysis, .progress]
        case .takip:    return [.measurements, .charts, .workout]
        case .beslenme: return [.calendar, .recipes]
        }
    }
}

// MARK: - Root view

struct ContentView: View {
    @State private var selection: NavTab? = .dashboard
    @State private var chatStore = ChatStore()
    @State private var saveErrors = SaveErrorReporter.shared
    @Environment(\.modelContext) private var modelContext
    /// CloudKit + seed UserProfile'ı çiftleyebilir (tekil olmalı); birden fazla olunca tekle.
    @Query private var allProfiles: [UserProfile]
    // Tema: görünüm @AppStorage'tan canlı okunur; semantik/grafik değişiminde
    // ağaç epoch ile tazelenir (renkler çizim anında defaults'tan çözülür).
    @AppStorage(ThemeSettings.appearanceKey) private var appearanceRaw: String = AppAppearance.dark.rawValue
    @State private var themeEpoch = 0
    // Sidebar kalıcı kolondur: collapse / ikon-rayı yok, her zaman tam açık.
    private let sidebarWidth: CGFloat = 244
    @State private var keyNavMonitor: Any? = nil   // tek-harf sekme kısayolları (K→Koç vb.)

    #if os(macOS)
    /// SwiftUI'nin `.preferredColorScheme`'i yalnız SwiftUI ağacını boyar; native menü,
    /// context-menu ve popover gibi AppKit yüzeyleri `NSApp.appearance`'ı izler. İkisi
    /// ayrışınca (zorlanan koyu tema + sistem açık) native menü item YAZILARI koyu-üstüne-
    /// koyu kalıp görünmez oluyordu. App genel appearance'ını tema tercihiyle eşitleyerek
    /// tüm native menüleri de doğru boyarız.
    private func syncAppKitAppearance() {
        switch AppAppearance(rawValue: appearanceRaw) ?? .dark {
        case .system: NSApp.appearance = nil                          // sistemi izle
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        }
    }

    /// Tek-harf sekme kısayolları — metin girişi DIŞINDA ve modifier'sız basınca ilgili sekmeye atlar.
    /// (Superhuman/Linear tarzı hızlı gezinme. TextEditor/TextField odaktayken harf yazılır, yutulmaz.)
    static let navShortcuts: [String: NavTab] = [
        "k": .chat,        // Koç
        "g": .dashboard,   // Genel Bakış
        "a": .analysis,    // Analiz
        "f": .fotolar,     // Fotoğraflar (ikincil bölgede, ⌘ kısayolu yok)
        "p": .profile,     // Profil
    ]

    private func installKeyNavMonitor() {
        guard keyNavMonitor == nil else { return }
        let bind = $selection
        keyNavMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // ⌘/⌥/⌃/fn varsa dokunma (sistem + diğer kısayollar serbest kalsın).
            guard event.modifierFlags.intersection([.command, .control, .option, .function]).isEmpty
            else { return event }
            let window = NSApp.keyWindow
            // Sheet açıkken arkadaki sayfayı değiştirmek istemiyoruz: sheet modal bir bağlam,
            // oradaki tuşlar gezinmeye ait değil.
            if window?.isSheet == true { return event }
            // Metin girişi yapılan her yerde harfi yutmuyoruz.
            if ContentView.wantsTextInput(window?.firstResponder) { return event }
            guard let ch = event.charactersIgnoringModifiers?.lowercased(),
                  let tab = ContentView.navShortcuts[ch] else { return event }
            bind.wrappedValue = tab
            return nil   // olayı tüket → harf başka yere gitmesin
        }
    }

    /// Odaktaki şey metin girişi bekliyor mu?
    ///
    /// Eskiden yalnızca `NSTextView` kontrol ediliyordu (SwiftUI TextField/TextEditor'ın field
    /// editor'ı o). Ama web içeriğinde odak WKWebView'ın kendi iç view'ında oluyor ve o
    /// NSTextView değil — sonuç olarak Instagram giriş formuna yazılan "a" yutulup Analiz
    /// sekmesine atıyordu. İki kontrol birlikte:
    ///   1. NSTextInputClient — native metin alanları ve IME kabul eden view'lar,
    ///   2. görünüm zincirinde WKWebView — iç view'ın sınıfına bel bağlamadan web içeriği.
    static func wantsTextInput(_ responder: NSResponder?) -> Bool {
        guard let responder else { return false }
        if responder is NSTextInputClient { return true }
        var view = responder as? NSView
        while let current = view {
            if current is WKWebView { return true }
            view = current.superview
        }
        return false
    }

    private func removeKeyNavMonitor() {
        if let m = keyNavMonitor { NSEvent.removeMonitor(m); keyNavMonitor = nil }
    }
    #endif

    var body: some View {
        // Düz HStack — NavigationSplitView değil. macOS (Tahoe) split view'ı sidebar'ı
        // kendi kromuyla (yuvarlak panel + kenarlık + tıklamada focus halkası) çiziyordu;
        // collapse zaten kullanılmadığı için sistem kromundan tamamen çıkıyoruz.
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)
                .overlay(alignment: .trailing) {
                    // Kalıcı kolon: gölge yok (her karede yeniden çizilen büyük
                    // gölge kasmaya yol açıyordu), ince ayraç yeter.
                    Rectangle()
                        .fill(Palette.border)
                        .frame(width: 0.5)
                        .ignoresSafeArea()
                }

            detailColumn
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.background.ignoresSafeArea())
        .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .dark).colorScheme)
        #if os(macOS)
        .onAppear { syncAppKitAppearance(); installKeyNavMonitor() }
        .onChange(of: appearanceRaw) { _, _ in syncAppKitAppearance() }
        .onDisappear { removeKeyNavMonitor() }
        #endif
        .id(themeEpoch)
        .onReceive(NotificationCenter.default.publisher(for: .herculesThemeChanged)) { _ in
            themeEpoch += 1
        }
        #if os(macOS)
        // Toolbar şeridi tüm pencere genişliğini kaplar → yan kolonun değil,
        // içerik zemininin rengini alır (yoksa sohbetin üstüne yanlış basamak biner).
        .toolbarBackground(Palette.background, for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        #endif
        .alert("Kaydedilemedi", isPresented: Binding(
            get: { saveErrors.message != nil },
            set: { if !$0 { saveErrors.message = nil } }
        )) {
            Button("Tamam", role: .cancel) { saveErrors.message = nil }
        } message: {
            Text(saveErrors.message ?? "")
        }
        .onChange(of: allProfiles.count) { _, count in
            if count > 1 { DemoSeed.dedupUserProfiles(modelContext) }
        }
    }

    // MARK: Sidebar

    private var sidebar: some View {
        HerculesSidebar(
            selection: $selection,
            onAskCoach: {
                // Tam sayfa sohbete götür. Anlık geçiş — cross-fade YOK: animasyonlu
                // geçişte eski + yeni sayfa aynı anda canlı kalıp ağır sayfa animasyon
                // sırasında inşa oluyordu ("zor yükleniyor" hissinin ana sebebi).
                selection = .chat
            }
        )
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {
            resignAIChatInputFocus()
        })
    }

    /// Hızlı tartı ekleme — dock popover'ından gelen kg'ı bugünün ölçümü olarak kaydeder.
    private func addQuickWeight(_ kg: Double) {
        let measurement = Measurement(date: .now, weight: kg)
        modelContext.insert(measurement)
        modelContext.saveOrReport("tartı ekle")
    }

    // MARK: Detail column (yüzen Koç'a Sor dock'u; eski sağ AI paneli kaldırıldı)

    private var detailColumn: some View {
        // GeometryReader ile sar: GR "greedy"dir — içeriğine pencereden gelen SABİT boyutu önerir
        // ve kendi raporladığı boyut içeriğinden BAĞIMSIZDIR. Böylece içerideki Takvim'in belirsiz
        // `maxHeight: .infinity` zinciri, boyut-raporlama zincirine GERİ BESLENEMEZ (layout döngüsü
        // kapanır). Commit'li kabukta detailColumn zaten GR ile sarılıydı; chat sadeleştirmesinde
        // onu kaldırınca Takvim "boştayken bile" sürekli yeniden layout'a giriyordu.
        GeometryReader { _ in
            ZStack(alignment: .bottom) {
                selectedDetail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .contentShape(Rectangle())
                    .simultaneousGesture(TapGesture().onEnded {
                        resignAIChatInputFocus()
                    })
                    // Input DIŞINDA bir yere tıklayınca metin alanı focus'unu bırak (cursor kalmasın).
                    .onTapGesture { dismissTextFocus() }

                // "Koç'a Sor" → tam sayfa sohbeti (.chat) açar. Chat'te dock gizli.
                if selection != .chat {
                    FloatingActionDock(
                        onAskCoach: { selection = .chat },   // anlık geçiş (cross-fade yok)
                        onAddWeight: addQuickWeight
                    )
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Palette.background)
    }

    private func resignAIChatInputFocus() {
        NotificationCenter.default.post(name: .aiChatShouldResignInputFocus, object: nil)
    }

    /// O an düzenlenen metin alanının (TextField/TextEditor) focus'unu bırakır — böylece
    /// input dışına tıklayınca yanıp sönen cursor kalmaz. macOS first-responder'ı temizler;
    /// her sayfa için tek noktadan, alan başına @FocusState gerektirmeden çalışır.
    private func dismissTextFocus() {
        #if canImport(AppKit)
        NSApp.keyWindow?.makeFirstResponder(nil)
        #endif
    }

    @ViewBuilder
    private var selectedDetail: some View {
        switch selection ?? .dashboard {
        case .dashboard:    DashboardView()
        case .progress:     IlerlemeView()
        case .fotolar:
            ProgressPhotosView(onSendToCoach: { datas, prompt in
                let room = max(0, 8 - chatStore.pendingImages.count)
                chatStore.pendingImages.append(contentsOf: datas.prefix(room))
                if chatStore.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    chatStore.input = prompt
                }
                selection = .chat
            })
        case .measurements: MeasurementsView()
        case .charts:       ChartsView()
        case .workout:      WorkoutView()
        case .analysis:     AnalysisView()
        case .calendar:     CalendarView()
        case .recipes:      RecipesView()
        case .chat:         ChatPageView(store: chatStore)
        case .profile:      ProfileView()
        }
    }
}

// MARK: - Custom sidebar
