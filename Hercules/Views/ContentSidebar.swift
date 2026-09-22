import SwiftUI
import LucideKit
import SwiftData
#if os(macOS)
import AppKit
#endif

/// Sidebar kromu — Buzz kanvas gradient'inin ÜSTÜNDE yaşar: zemin şeffaf,
/// metin/etkileşim katmanları beyaz-tül (koyu) / siyah-tül (açık) overlay'lerdir
/// (Buzz `--buzz-hover-surface`, `--sidebar-row-subtle-active-surface` vb.).
enum SidebarChrome {
    /// Gradient görünsün diye sidebar kendi zeminini boyamaz.
    static var background: Color { .clear }
    static var backgroundRaised: Color { BuzzTheme.rowActive }
    static var rowHover: Color { BuzzTheme.rowHover }
    static var rowSelected: Color { BuzzTheme.rowActive }
    static var border: Color { dynColor(light: Color.black.opacity(0.10), dark: Color.white.opacity(0.10)) }
    static var borderStrong: Color { dynColor(light: Color.black.opacity(0.16), dark: Color.white.opacity(0.16)) }
    static var primary: Color { BuzzTheme.sidebarText }
    /// Pasif satırlar: Buzz satır içeriğini %80 opaklıkta tutar.
    static var secondary: Color { BuzzTheme.sidebarText.opacity(0.8) }
    static var tertiary: Color { BuzzTheme.sidebarText.opacity(0.8) }
    static var quiet: Color { BuzzTheme.sidebarMuted }
    /// Aktif (beyaz-tül pill) satırın metni.
    static var selectedText: Color { BuzzTheme.rowActiveText }
    /// Dolgulu (btnBg) yüzey üstündeki yazı/ikon.
    static var ink: Color { Palette.btnFg }
}

/// Buzz referanslı sidebar — TEK durumlu: kolon her zaman tam açık durur
/// (collapse/ikon-rayı yok). Gradient kanvas üstünde şeffaf; ikon solda,
/// aktif satır beyaz-tül pill. Birincil nav bloğunun altında, geniş bir
/// boşlukla ayrılmış "ikincil menü" bölgesi (renkli nokta + sakin tipografi) yer alır.
struct HerculesSidebar: View {
    @Binding var selection: NavTab?
    var onAskCoach: () -> Void = {}

    @Query(sort: \Measurement.date) private var measurements: [Measurement]
    @Query private var foods: [FoodEntry]
    @Query private var profiles: [UserProfile]
    @Query private var programSessions: [WorkoutSession]

    @State private var hoveredTab: NavTab?
    @State private var hoveredGroup: NavCategory?
    @State private var live = SidebarLiveData()

    /// KAPALI grupların id'leri (virgülle). "Açık olanlar" yerine "kapalı olanlar" tutuluyor:
    /// boş varsayılan = hepsi açık, yani ilk açılışta davranış eskisiyle aynı kalıyor.
    @AppStorage("hercules.sidebar.collapsedGroups") private var collapsedGroupsRaw = ""

    private var collapsedGroups: Set<String> {
        Set(collapsedGroupsRaw.split(separator: ",").map(String.init))
    }

    private func isExpanded(_ category: NavCategory) -> Bool {
        !collapsedGroups.contains(category.id)
    }

    private func toggle(_ category: NavCategory) {
        var set = collapsedGroups
        if set.contains(category.id) { set.remove(category.id) } else { set.insert(category.id) }
        collapsedGroupsRaw = set.sorted().joined(separator: ",")
    }

    /// Seçim kapalı bir gruba düşerse o grubu aç — dışarıdan (koç, rozet, geri
    /// dönüş) gidilen sayfa görünmez kalmasın. Yalnızca gerçekten kapalıysa
    /// yazıyoruz, gereksiz defaults yazımı olmasın.
    private func revealGroup(containing tab: NavTab?) {
        guard let tab,
              let category = NavCategory.allCases.first(where: { $0.tabs.contains(tab) })
        else { return }
        var set = collapsedGroups
        guard set.remove(category.id) != nil else { return }
        collapsedGroupsRaw = set.sorted().joined(separator: ",")
    }

    private var profile: UserProfile? { profiles.first }

    private static let orderedTabs: [NavTab] = NavCategory.allCases.flatMap(\.tabs)

    var body: some View {
        VStack(spacing: 0) {
            identity
                .padding(.bottom, 10)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Birincil nav — grup satırları artık tam boy satır, yani liste mockup'taki
                    // gibi kesintisiz akıyor; gruplar arası boşluk minimum tutuldu
                    // (satır arası 1 < grup arası 4 < ikincil bölge 28).
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(NavCategory.allCases) { category in
                            section(category)
                        }
                    }

                    // İkincil menü bölgesi — geniş boşlukla ayrılır, sakin tipografi.
                    VStack(alignment: .leading, spacing: 1) {
                        secondaryRow(.fotolar, dot: Palette.macroFat)
                    }
                    .padding(.top, 28)
                }
                .padding(.bottom, 14)
            }
            .focusable(false)

            footer
        }
        .padding(.horizontal, 12)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Kapalı bir gruptaki sayfaya gidilirse o grup açılsın.
        .onChange(of: selection) { _, newValue in
            revealGroup(containing: newValue)
        }
        // Rozetler yalnız veri değişince yeniden hesaplanır (hover'da değil).
        .task(id: liveRefreshKey) { recomputeLiveData() }
        // macOS focus ring'i sidebar'da kapat — klavye odağı satırlara halka çiziyordu.
        .focusEffectDisabled()
        .background(
            SidebarChrome.background
                .ignoresSafeArea(.container, edges: [.top, .bottom])
        )
        #if os(macOS)
        // SwiftUI .focusEffectDisabled() AppKit-backed NSScrollView / split-view
        // kolonunun çizdiği halkayı kapatmaz — AppKit seviyesinde kökten söküyoruz.
        .background(FocusRingKiller())
        #endif
    }

    // MARK: - Kimlik

    /// Kelime-markası. Referansta başlık, satır etiketleri ve alt blok aynı sol
    /// hizada durur — satırların iç yatay dolgusu (10) burada da tekrarlanır.
    private var identity: some View {
        HStack(spacing: 10) {
            Text("Hercules")
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.15)
                .foregroundStyle(SidebarChrome.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
    }

    // MARK: - Nav grupları

    private func section(_ category: NavCategory) -> some View {
        let expanded = isExpanded(category)
        // Buzz'da bölüm etiketi ve satırlar aynı sol hizada akar (girinti yok);
        // hiyerarşiyi girinti değil, etiketin soluk tipografisi verir.
        return VStack(alignment: .leading, spacing: 2) {
            groupHeader(category, expanded: expanded)
            if expanded {
                ForEach(category.tabs) { tab in
                    navRow(tab)
                }
            }
        }
    }

    /// Buzz bölüm etiketi: küçük, medium, soluk (beyaz %40) — satır değil başlık.
    /// Chevron yalnız hover'da belirir ve kapalıyken -90° döner; kapalı grup
    /// seçimi içeriyorsa soluk bir nokta bunu hatırlatır.
    private func groupHeader(_ category: NavCategory, expanded: Bool) -> some View {
        let isHovered = hoveredGroup == category
        let holdsSelection = selection.map { category.tabs.contains($0) } ?? false
        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                toggle(category)
            }
        } label: {
            HStack(spacing: 6) {
                Text(category.label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BuzzTheme.sidebarMuted)
                    .lineLimit(1)

                Lucide(sf: "chevron.down", size: 10)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
                    .foregroundStyle(BuzzTheme.sidebarMuted)
                    .opacity(isHovered ? 1 : 0)

                Spacer(minLength: 6)

                // Grup kapalıyken içindeki aktif sayfayı kaybetmeyelim.
                if !expanded && holdsSelection {
                    Circle()
                        .fill(SidebarChrome.primary)
                        .frame(width: 5, height: 5)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(SidebarPressStyle())
        .focusable(false)
        .onHover { hovering in
            hoveredGroup = hovering ? category : nil
        }
        .help(expanded ? "\(category.label) grubunu kapat" : "\(category.label) grubunu aç")
    }

    /// Buzz kanal satırı: ikon SOLDA (16pt kolon), 32pt yükseklik, 8px köşe.
    /// Aktif satır beyaz-tül pill + tam beyaz metin — Buzz aktif satırı bilinçli
    /// olarak normal ağırlıkta bırakır (yarı-kalın değil).
    private func navRow(_ tab: NavTab) -> some View {
        let isActive = selection == tab
        let isHovered = hoveredTab == tab
        return Button {
            // Anlık geçiş — ağır detay sayfaları arasında cross-fade yok.
            selection = tab
        } label: {
            HStack(spacing: 8) {
                Lucide(sf: tab.systemImage, size: 14)
                    .foregroundStyle(isActive ? SidebarChrome.selectedText : SidebarChrome.tertiary)
                    .frame(width: 16, alignment: .center)

                Text(tab.label)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isActive ? SidebarChrome.selectedText : (isHovered ? SidebarChrome.primary : SidebarChrome.secondary))
                    .lineLimit(1)

                Spacer(minLength: 6)

                trailing(for: tab, active: isActive)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? SidebarChrome.rowSelected : (isHovered ? SidebarChrome.rowHover : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(SidebarPressStyle())
        .focusable(false)
        .onHover { hovering in
            hoveredTab = hovering ? tab : nil
        }
        .help(tab.label)
    }

    /// Referanstaki sağ ikon hizasını bozmadan yalnızca gerçekten faydalı canlı
    /// veriyi göster.
    @ViewBuilder
    private func trailing(for tab: NavTab, active: Bool) -> some View {
        if let data = liveData(for: tab) {
            Text(data)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(active ? SidebarChrome.secondary : SidebarChrome.quiet)
                .lineLimit(1)
        }
    }

    // MARK: - Canlı mikro veriler

    /// Satır rozetleri hover'da DEĞİL, veri değişince hesaplanır. Eskiden her fare
    /// hareketi `navRow`'u yeniden kurduğu için tüm besin geçmişi + ölçümler taranıyor
    /// ve her program seansının ilişkisi fault'lanıyordu → geçmiş büyüdükçe ağırlaşan
    /// sidebar. Sidebar uygulama boyunca ekranda durduğu için etkisi her yerdeydi.
    struct SidebarLiveData: Equatable {
        var weight: String?
        var remainingKcal: Double?
        var nextWorkout: String?
    }

    /// Yeniden hesaplama tetikleyicisi — ucuz alanlar, tam tarama değil.
    private struct LiveRefreshKey: Equatable {
        var foods: Int
        var measurements: Int
        var sessions: Int
        var profileStamp: Date?
    }

    private var liveRefreshKey: LiveRefreshKey {
        LiveRefreshKey(
            foods: foods.count,
            measurements: measurements.count,
            sessions: programSessions.count,
            profileStamp: profile?.updatedAt
        )
    }

    private func recomputeLiveData() {
        live = SidebarLiveData(
            weight: measurements.last(where: { $0.weight != nil })?.weight
                .map { "\(Fmt.num($0, digits: 1)) kg" },
            remainingKcal: remainingKcalToday,
            nextWorkout: nextWorkoutLabel
        )
    }

    private func liveData(for tab: NavTab) -> String? {
        switch tab {
        case .measurements:
            return live.weight
        case .calendar:
            guard let remaining = live.remainingKcal else { return nil }
            return remaining >= 0 ? "\(Fmt.int(remaining)) kaldı" : "\(Fmt.int(-remaining)) fazla"
        case .workout:
            return live.nextWorkout
        default:
            return nil
        }
    }

    /// Bugünün kalan kalorisi (hedef − bugün yenen) — Dashboard ile aynı hesap.
    private var remainingKcalToday: Double? {
        guard let p = profile,
              let weight = measurements.last(where: { $0.weight != nil })?.weight else { return nil }
        let bodyFat = measurements.last(where: { $0.bodyFat != nil })?.bodyFat ?? p.manualBodyFat
        let result = CalorieCalculator.compute(
            weight: weight,
            height: p.height,
            age: p.age,
            sex: p.sex,
            bodyFat: bodyFat,
            activity: p.activity,
            goal: p.goal,
            manualOffset: p.manualCalorieOffset,
            manualOffsetMacro: p.manualCalorieOffsetMacro,
            manualProteinGrams: p.manualProteinGrams,
            manualCarbsGrams: p.manualCarbsGrams,
            manualFatGrams: p.manualFatGrams
        )
        let cal = Calendar.current
        let consumed = foods.filter { cal.isDateInToday($0.date) }.reduce(0) { $0 + $1.calories }
        return result.goalCalories - consumed
    }

    /// Programdaki bir sonraki antrenman günü: "bugün" / "yarın" / kısa gün adı.
    private var nextWorkoutLabel: String? {
        let trainingDays = Set(
            programSessions
                .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && !$0.templateExercises.isEmpty }
                .map(\.weekday)
        )
        guard !trainingDays.isEmpty else { return nil }
        let today = Calendar.current.component(.weekday, from: .now)
        for offset in 0...7 {
            let weekday = ((today - 1 + offset) % 7) + 1
            if trainingDays.contains(weekday) {
                if offset == 0 { return "bugün" }
                if offset == 1 { return "yarın" }
                return weekdayShort(weekday)
            }
        }
        return nil
    }

    /// Calendar.weekday (1=Pazar) → kısa TR gün adı.
    private func weekdayShort(_ weekday: Int) -> String {
        let symbols = ["paz", "pzt", "sal", "çar", "per", "cum", "cmt"]
        return symbols[(weekday - 1) % 7]
    }

    // MARK: - Koç satırı

    /// Sohbete giriş — profil kartıyla aynı kimlik satırı kabuğu (dolgulu buton değil).
    private var askCoachRow: some View {
        CoachFooter(onTap: onAskCoach)
    }

    // MARK: - İkincil menü (Fotoğraflar)

    /// Referanstaki ikincil bölge: nav bloğundan geniş boşlukla ayrılır, satır
    /// biraz daha sıkıdır ve etiketin önünde kimliği veren renkli bir nokta durur
    /// (sağ ikon yok — nokta zaten işaretleyici).
    @ViewBuilder
    private func secondaryRow(_ tab: NavTab, dot: Color) -> some View {
        let isActive = selection == tab
        let isHovered = hoveredTab == tab
        Button {
            selection = tab   // anlık geçiş (cross-fade yok)
        } label: {
            HStack(spacing: 9) {
                Circle()
                    .fill(dot)
                    .frame(width: 7, height: 7)
                    .frame(width: 16, alignment: .center)

                Text(tab.label)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(isActive ? SidebarChrome.selectedText : (isHovered ? SidebarChrome.primary : SidebarChrome.secondary))

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? SidebarChrome.rowSelected : (isHovered ? SidebarChrome.rowHover : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(SidebarPressStyle())
        .focusable(false)
        .onHover { hovering in
            hoveredTab = hovering ? tab : nil
        }
        .help(tab.label)
    }

    // MARK: - Alt blok

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Koç ve profil sidebar'ın dibinde eş bir çift: aynı kimlik satırı
            // kabuğu, aralarında yalnız "Tercihler" ayracı.
            askCoachRow
                .padding(.bottom, 4)

            // Gradient üstünde Palette hairline'ı kaybolur — beyaz/siyah-tül çizgi.
            Rectangle()
                .fill(SidebarChrome.border)
                .frame(height: 0.5)
                .padding(.bottom, 2)

            HStack(spacing: 8) {
                Text("Tercihler")
                    .font(.system(size: 10.5, weight: .regular))
                    .foregroundStyle(SidebarChrome.quiet)

                Spacer(minLength: 0)

                Image(systemName: "ellipsis")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(SidebarChrome.quiet)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 10)

            ProfileFooter(
                isSelected: selection == .profile,
                onTap: { selection = .profile }   // anlık geçiş (cross-fade yok)
            )
        }
    }
}

struct SidebarPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .animation(.spring(response: 0.22, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

extension View {
    /// macOS odak halkasını (AppKit NSScrollView / split-view kolonu) kökten söker.
    /// SwiftUI `.focusEffectDisabled()` AppKit-backed view'lara işlemediği için gerekli.
    @ViewBuilder
    func killFocusRing() -> some View {
        #if os(macOS)
        background(FocusRingKiller())
        #else
        self
        #endif
    }
}

#if os(macOS)
/// Buzz scrollbar dili (scrollbars.css): ray YOK, ince pill thumb, dinlenmede
/// görünmez — yalnız kaydırırken belirir. macOS'ta bunun birebir karşılığı
/// overlay scroller'dır; sistem tercihi "Always" olsa bile tüm NSScrollView'ları
/// overlay'e zorlarız (FocusRingKiller ile aynı pencere-süpürme deseni).
struct BuzzScrollerStyler: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        Self.schedule(from: v)
        return v
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Sayfa geçişleri yeni scroll view'lar yaratır — .id(...) ile yeniden
        // kurulduğumuzda makeNSView zaten tekrar süpürür; burada no-op.
    }

    /// Scroll view'lar geç kurulabiliyor (lazy sayfalar, açılan paneller) —
    /// süpürmeyi birkaç kez tekrarla.
    private static func schedule(from view: NSView) {
        for delay in [0.0, 0.4, 1.0, 2.2] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak view] in
                guard let root = view?.window?.contentView else { return }
                sweep(root)
            }
        }
    }

    private static func sweep(_ view: NSView) {
        if let scroll = view as? NSScrollView {
            if !(scroll.verticalScroller is BuzzThinScroller) {
                scroll.verticalScroller = BuzzThinScroller()
            }
            if !(scroll.horizontalScroller is BuzzThinScroller) {
                scroll.horizontalScroller = BuzzThinScroller()
            }
            scroll.scrollerStyle = .overlay
            scroll.autohidesScrollers = true
        }
        for sub in view.subviews { sweep(sub) }
    }
}

/// Buzz'daki ince, track'siz scrollbar. Sistem "Show scroll bars: Always" ayarında
/// `.overlay` ataması AppKit tarafından geri alinip kalin legacy scroller'a düşüyor;
/// overlay-uyumlu custom scroller kuruluysa stil her koşulda overlay kalır ve
/// thumb'ı kendimiz çizeriz.
final class BuzzThinScroller: NSScroller {
    override class var isCompatibleWithOverlayScrollers: Bool { true }

    override class func scrollerWidth(
        for controlSize: NSControl.ControlSize,
        scrollerStyle: NSScroller.Style
    ) -> CGFloat { 10 }

    override func draw(_ dirtyRect: NSRect) {
        // Track çizilmez — Buzz'da yalnız thumb var.
        drawKnob()
    }

    override func drawKnob() {
        let knob = rect(for: .knob)
        guard knob.width > 0, knob.height > 0 else { return }
        let isVertical = bounds.height >= bounds.width
        let thickness: CGFloat = 5
        let edgeInset: CGFloat = 2.5
        let r: NSRect
        if isVertical {
            r = NSRect(
                x: bounds.maxX - thickness - edgeInset,
                y: knob.minY + 1,
                width: thickness,
                height: max(20, knob.height - 2)
            )
        } else {
            r = NSRect(
                x: knob.minX + 1,
                y: bounds.maxY - thickness - edgeInset,
                width: max(20, knob.width - 2),
                height: thickness
            )
        }
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let fill = isDark
            ? NSColor.white.withAlphaComponent(0.28)
            : NSColor.black.withAlphaComponent(0.34)
        fill.setFill()
        NSBezierPath(roundedRect: r, xRadius: thickness / 2, yRadius: thickness / 2).fill()
    }
}

/// AppKit odak halkası söküğü: kendi NSView'ından yukarı doğru tüm zinciri (NSScrollView,
/// NavigationSplitView kolonu, kapsayan görünümler) dolaşıp `focusRingType = .none` yapar.
/// SwiftUI `.focusEffectDisabled()` bu AppKit-backed view'lara işlemiyor.
struct FocusRingKiller: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView(frame: .zero)
        Self.schedule(from: v)
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        // Kurulum makeNSView'da tek sefer (gecikmeli tekrarlarla) yapılır.
        // Burada — her SwiftUI güncellemesinde, yani her hover / animasyon karesi /
        // sayfa geçişinde — tüm pencere ağacını yeniden rekürsif taramak ana thread'i
        // kilitleyip ciddi kasmaya yol açıyordu. Bilerek no-op.
    }

    /// Halka view'ı first-responder olunca veya lazım split-view kolonu geç
    /// kurulabiliyor — taramayı birkaç kez tekrar et ki geç yaratılanı da yakalasın.
    private static func schedule(from view: NSView) {
        for delay in [0.0, 0.35, 0.7] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                disableRings(from: view)
            }
        }
    }
    private static func disableRings(from view: NSView) {
        guard let root = view.window?.contentView else {
            // Pencereye henüz bağlanmadıysa atalar zincirini yine de temizle.
            var node: NSView? = view
            while let n = node { n.focusRingType = .none; node = n.superview }
            return
        }
        // Pencere ağacındaki HER görünümün odak halkasını kapat (split-view kolonu,
        // scroll view'lar, butonlar dahil) — yapışan halka hangi katmandaysa orada söker.
        sweepAll(root)
    }

    private static func sweepAll(_ view: NSView) {
        view.focusRingType = .none
        for sub in view.subviews { sweepAll(sub) }
    }
}
#endif
