import SwiftUI
import SwiftData
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Navigation tabs

enum NavTab: String, CaseIterable, Identifiable, Hashable {
    case dashboard, measurements, charts, workout, analysis, calendar, recipes, chat, profile, progress, fotolar, labs
    var id: String { rawValue }

    var label: String {
        switch self {
        case .dashboard:    return "Genel Bakış"
        case .progress:     return "İlerleme"
        case .fotolar:      return "Fotoğraflar"
        case .measurements: return "Ölçümler"
        case .labs:         return "Tahliller"
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
        case .labs:         return "drop"
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
        case .takip:    return [.measurements, .labs, .charts, .workout]
        case .beslenme: return [.calendar, .recipes]
        }
    }
}

// MARK: - Root view

struct ContentView: View {
    @State private var selection: NavTab? = .dashboard
    // Sunucu (telefon istekleri) ile aynı örnek — bkz. ChatStore.shared.
    @State private var chatStore = ChatStore.shared
    @State private var saveErrors = SaveErrorReporter.shared
    @Environment(\.modelContext) private var modelContext
    /// CloudKit + seed UserProfile'ı çiftleyebilir (tekil olmalı); birden fazla olunca tekle.
    @Query private var allProfiles: [UserProfile]
    // Tema: görünüm @AppStorage'tan canlı okunur; semantik/grafik değişiminde
    // ağaç epoch ile tazelenir (renkler çizim anında defaults'tan çözülür).
    @AppStorage(ThemeSettings.appearanceKey) private var appearanceRaw: String = AppAppearance.dark.rawValue
    @State private var themeEpoch = 0
    // Sidebar kalıcı kolondur: collapse / ikon-rayı yok, her zaman tam açık.
    private let sidebarWidth: CGFloat = 280   // Buzz varsayılanı 300; Hercules penceresine oranlı

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

    #endif

    var body: some View {
        // Düz HStack — NavigationSplitView değil. macOS (Tahoe) split view'ı sidebar'ı
        // kendi kromuyla (yuvarlak panel + kenarlık + tıklamada focus halkası) çiziyordu;
        // collapse zaten kullanılmadığı için sistem kromundan tamamen çıkıyoruz.
        // Buzz kanvası: pencere zeminine tek dikey gradient boyanır (zeytin → gece),
        // sidebar bu gradient üstünde şeffaf durur, içerik 16px köşeli bir kart
        // olarak üstte yüzer (Buzz `content-surface`: üst 1px, sağ/alt 8px inset).
        GeometryReader { geometry in
            HStack(spacing: 0) {
                sidebar
                    .frame(width: geometry.size.width < 1000 ? 220 : sidebarWidth)

                detailColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        // Koyuda tek kenar vurgusu (hairline); açıkta kenar + yumuşak kaldırma.
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(BuzzTheme.contentEdge, lineWidth: 1)
                    )
                    .shadow(color: dynColor(light: Color.black.opacity(0.07), dark: .clear), radius: 4)
                    .padding(.top, 1)
                    .padding(.trailing, 8)
                    .padding(.bottom, 8)
            }
        }
        .background(
            LinearGradient(
                colors: [BuzzTheme.gradientTop, BuzzTheme.gradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .preferredColorScheme((AppAppearance(rawValue: appearanceRaw) ?? .dark).colorScheme)
        #if os(macOS)
        // Buzz overlay scrollbar'ları: her sayfa geçişinde yeni scroll view'ları da yakala.
        .background(BuzzScrollerStyler().id(selection))
        .onAppear { syncAppKitAppearance() }
        .onChange(of: appearanceRaw) { _, _ in syncAppKitAppearance() }
        #endif
        .id(themeEpoch)
        .onReceive(NotificationCenter.default.publisher(for: .herculesThemeChanged)) { _ in
            themeEpoch += 1
        }
        #if os(macOS)
        // Toolbar şeridi şeffaf: Buzz'ın üst kromu gibi gradient'in zeytin bandı
        // trafik ışıklarının ve toolbar butonlarının arkasında görünür.
        .toolbarBackground(.hidden, for: .windowToolbar)
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

    // MARK: Detail column (eski sağ AI paneli ve yüzen dock kaldırıldı; Koç'a Sor sidebar'da)

    private var detailColumn: some View {
        // GeometryReader ile sar: GR "greedy"dir — içeriğine pencereden gelen SABİT boyutu önerir
        // ve kendi raporladığı boyut içeriğinden BAĞIMSIZDIR. Böylece içerideki Takvim'in belirsiz
        // `maxHeight: .infinity` zinciri, boyut-raporlama zincirine GERİ BESLENEMEZ (layout döngüsü
        // kapanır). Commit'li kabukta detailColumn zaten GR ile sarılıydı; chat sadeleştirmesinde
        // onu kaldırınca Takvim "boştayken bile" sürekli yeniden layout'a giriyordu.
        GeometryReader { _ in
            // Buzz sayfa geçişi: kısa crossfade — sayfa değişirken kartlar
            // zıplamadan eski sayfa 140ms'de yenisine karışır.
            ZStack {
                selectedDetail
                    .id(selection ?? .dashboard)
                    .transition(.opacity)
            }
            .animation(.easeOut(duration: 0.14), value: selection)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(TapGesture().onEnded {
                resignAIChatInputFocus()
            })
            // Input DIŞINDA bir yere tıklayınca metin alanı focus'unu bırak (cursor kalmasın).
            .onTapGesture { dismissTextFocus() }
        }
        .background(DashboardBackground())
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
        case .labs:
            LabsView(onAskCoach: { prompt in
                chatStore.input = prompt
                selection = .chat
            })
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
