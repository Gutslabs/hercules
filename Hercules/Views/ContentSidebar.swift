import SwiftUI
import LucideKit
import SwiftData
#if os(macOS)
import AppKit
#endif

/// Sidebar kromu — Palette'e bağlı: tema değişimi sidebar'a da otomatik yansır.
enum SidebarChrome {
    /// Sidebar bir yan kolondur → içerik zemininden bir basamak yukarıda durur.
    static var background: Color { Palette.panel }
    static var backgroundRaised: Color { Palette.surfaceElevated }
    static var rowHover: Color { Palette.fieldFill }
    static var rowSelected: Color { Palette.track }
    static var border: Color { Palette.border }
    static var borderStrong: Color { Palette.borderStrong }
    static var primary: Color { Palette.textPrimary }
    static var secondary: Color { Palette.textSecondary }
    static var tertiary: Color { Palette.textTertiary }
    static var quiet: Color { Palette.textQuaternary }
    /// Dolgulu (btnBg) yüzey üstündeki yazı/ikon.
    static var ink: Color { Palette.btnFg }
}

/// Nova referansındaki sade sidebar yapısı — TEK durumlu: kolon her zaman tam
/// açık durur (collapse/ikon-rayı yok). Metin solda, ikon sağda; aktif satır
/// sessiz bir yüzeyle belirtilir. Birincil nav bloğunun altında, geniş bir
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
    @State private var coachHovering = false
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

    /// Seçim kapalı bir gruba düşerse o grubu aç — ⌘ kısayoluyla gidilen sayfa görünmez
    /// kalmasın. Yalnızca gerçekten kapalıysa yazıyoruz, gereksiz defaults yazımı olmasın.
    private func revealGroup(containing tab: NavTab?) {
        guard let tab,
              let category = NavCategory.allCases.first(where: { $0.tabs.contains(tab) })
        else { return }
        var set = collapsedGroups
        guard set.remove(category.id) != nil else { return }
        collapsedGroupsRaw = set.sorted().joined(separator: ",")
    }

    private var profile: UserProfile? { profiles.first }

    /// ⌘1…⌘7 gruplardaki düz akış; ⌘8 Koç'a sor.
    private static let orderedTabs: [NavTab] = NavCategory.allCases.flatMap(\.tabs)

    var body: some View {
        VStack(spacing: 0) {
            identity

            askCoachButton
                .padding(.top, 16)
                .padding(.bottom, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // Birincil nav — grup satırları artık tam boy satır, yani liste mockup'taki
                    // gibi kesintisiz akıyor; gruplar arası boşluk minimum tutuldu
                    // (satır arası 1 < grup arası 4 < ikincil bölge 28).
                    VStack(alignment: .leading, spacing: 4) {
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
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // ⌘ kısayoluyla kapalı bir gruptaki sayfaya gidilirse o grup açılsın.
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
        return VStack(alignment: .leading, spacing: 1) {
            groupHeader(category, expanded: expanded)
            if expanded {
                ForEach(category.tabs) { tab in
                    navRow(tab)
                        // Çocuklar ebeveynin altında girintili — hit alanı da kayıyor ki
                        // tıklanabilir yüzey görünen satırla aynı olsun.
                        .padding(.leading, 10)
                }
            }
        }
    }

    /// Grubun açılır-kapanır satırı. Soluk bir bölüm başlığı DEĞİL, gerçek bir satır: aynı
    /// yükseklik, aynı tipografi boyu, aynı köşe yarıçapı. Ayırt edici tek şey yarı-kalın yazı
    /// ve ikon yerine chevron. Chevron, satır ikonlarıyla aynı 16pt kolonda duruyor; çocuklar
    /// yalnızca soldan girintili olduğu için sağ kenar ortak ve ikon kolonu dikey hizalı kalıyor.
    private func groupHeader(_ category: NavCategory, expanded: Bool) -> some View {
        let isHovered = hoveredGroup == category
        let holdsSelection = selection.map { category.tabs.contains($0) } ?? false
        return Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.9)) {
                toggle(category)
            }
        } label: {
            HStack(spacing: 9) {
                Text(category.label)
                    .font(.system(size: 12.5, weight: .semibold))
                    .tracking(-0.08)
                    .foregroundStyle(isHovered ? SidebarChrome.primary : SidebarChrome.secondary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                // Grup kapalıyken içindeki aktif sayfayı kaybetmeyelim.
                if !expanded && holdsSelection {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: 5, height: 5)
                }

                Lucide(sf: "chevron.right", size: 12)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .foregroundStyle(isHovered ? SidebarChrome.primary : SidebarChrome.tertiary)
                    .frame(width: 16, alignment: .center)
            }
            .padding(.horizontal, 10)
            .frame(height: 33)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isHovered ? SidebarChrome.rowHover : Color.clear)
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(SidebarPressStyle())
        .focusable(false)
        .onHover { hovering in
            hoveredGroup = hovering ? category : nil
        }
        .help(expanded ? "\(category.label) grubunu kapat" : "\(category.label) grubunu aç")
    }

    private func navRow(_ tab: NavTab) -> some View {
        let isActive = selection == tab
        let isHovered = hoveredTab == tab
        return Button {
            // Anlık geçiş — ağır detay sayfaları arasında cross-fade yok.
            selection = tab
        } label: {
            HStack(spacing: 9) {
                Text(tab.label)
                    .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                    .tracking(isActive ? -0.08 : 0)
                    .foregroundStyle(isActive || isHovered ? SidebarChrome.primary : SidebarChrome.secondary)
                    .lineLimit(1)

                Spacer(minLength: 6)

                trailing(for: tab, active: isActive)

                Lucide(sf: tab.systemImage, size: 13)
                    .foregroundStyle(isActive || isHovered ? SidebarChrome.primary : SidebarChrome.tertiary)
                    .frame(width: 16, alignment: .center)
            }
            .padding(.horizontal, 10)
            .frame(height: 33)
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
        .keyboardShortcut(shortcutKey(for: tab), modifiers: .command)
        .help(tab.label)
    }

    /// Referanstaki sağ ikon hizasını bozmadan yalnızca gerçekten faydalı canlı
    /// veriyi göster; klavye kısayolları görünmez kalır ama çalışmaya devam eder.
    @ViewBuilder
    private func trailing(for tab: NavTab, active: Bool) -> some View {
        if let data = liveData(for: tab) {
            Text(data)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(active ? SidebarChrome.secondary : SidebarChrome.quiet)
                .lineLimit(1)
        }
    }

    // MARK: - Kısayollar

    private func shortcutKey(for tab: NavTab) -> KeyEquivalent {
        guard let idx = Self.orderedTabs.firstIndex(of: tab), idx < 7 else { return KeyEquivalent("0") }
        return KeyEquivalent(Character("\(idx + 1)"))
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

    // MARK: - Koç'a sor

    private var askCoachButton: some View {
        let isActive = selection == .chat
        return Button(action: onAskCoach) {
            HStack(spacing: 9) {
                Text("Koç'a sor")
                    .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                    .tracking(isActive ? -0.08 : 0)
                    .foregroundStyle(isActive || coachHovering ? SidebarChrome.primary : SidebarChrome.secondary)

                Spacer(minLength: 0)

                Lucide(sf: "sparkles", size: 13)
                    .foregroundStyle(isActive || coachHovering ? SidebarChrome.primary : SidebarChrome.tertiary)
                    .frame(width: 16)
            }
            .padding(.horizontal, 10)
            .frame(height: 33)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isActive ? SidebarChrome.rowSelected : (coachHovering ? SidebarChrome.rowHover : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(SidebarPressStyle())
        .focusable(false)
        .onHover { coachHovering = $0 }
        .keyboardShortcut("8", modifiers: .command)
        .help("Tam sayfa AI koç sohbetini aç (⌘8)")
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
            HStack(spacing: 10) {
                Circle()
                    .fill(dot)
                    .frame(width: 7, height: 7)

                Text(tab.label)
                    .font(.system(size: 12.5, weight: isActive ? .semibold : .regular))
                    .tracking(isActive ? -0.08 : 0)
                    .foregroundStyle(isActive || isHovered ? SidebarChrome.primary : SidebarChrome.secondary)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
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
            Hairline()
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
