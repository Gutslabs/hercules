import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

/// Sidebar kromu — Palette'e bağlı: tema değişimi sidebar'a da otomatik yansır.
enum SidebarChrome {
    static var background: Color { Palette.background }
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

/// V1 sidebar — ikon kutuları ve grup sayaçları yok; gruplar küçük caps,
/// aktif öğe mercan nokta + mercan zemin, sağda mono ⌘kısayol ya da canlı
/// mikro veri (kilo / kalan kcal / sonraki antrenman). Altta "Koç'a sor".
struct HerculesSidebar: View {
    @Binding var selection: NavTab?
    var onAskCoach: () -> Void = {}

    @Query(sort: \Measurement.date) private var measurements: [Measurement]
    @Query private var foods: [FoodEntry]
    @Query private var profiles: [UserProfile]
    @Query private var programSessions: [WorkoutSession]

    @State private var hoveredTab: NavTab?
    @State private var coachHovering = false

    private var profile: UserProfile? { profiles.first }

    /// ⌘1…⌘7 sırası — gruplardaki düz akış. ⌘8 Koç'a ayrılmıştır.
    private static let orderedTabs: [NavTab] = NavCategory.allCases.flatMap(\.tabs)

    var body: some View {
        VStack(spacing: 0) {
            identity

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(NavCategory.allCases) { category in
                        section(category)
                    }
                }
                .padding(.top, 20)
                .padding(.bottom, 16)
            }
            .focusable(false)

            askCoachButton
                .padding(.bottom, 12)

            footer
        }
        .padding(.horizontal, 14)
        .padding(.top, 22)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private var identity: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Palette.accent.opacity(0.13))
                    Text("H")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(Palette.accent)
                }
                .frame(width: 34, height: 34)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Palette.accent.opacity(0.35), lineWidth: 1)
                )

                Text("Hercules")
                    .font(.system(size: 15, weight: .bold))
                    .tracking(-0.2)
                    .foregroundStyle(SidebarChrome.primary)
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 18)

            Hairline()
        }
    }

    // MARK: - Nav grupları

    private func section(_ category: NavCategory) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(category.label)
                .font(Typography.label)
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundStyle(SidebarChrome.quiet)
                .padding(.leading, 28)
                .padding(.trailing, 14)
                .padding(.bottom, 7)

            ForEach(category.tabs) { tab in
                navRow(tab)
            }
        }
    }

    private func navRow(_ tab: NavTab) -> some View {
        let isActive = selection == tab
        let isHovered = hoveredTab == tab
        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                selection = tab
            }
        } label: {
            HStack(spacing: 0) {
                Circle()
                    .fill(isActive ? Palette.accent : Color.clear)
                    .frame(width: 5, height: 5)
                    .frame(width: 14, alignment: .leading)

                Text(tab.label)
                    .font(.system(size: 13, weight: isActive ? .bold : .medium))
                    .tracking(isActive ? -0.1 : 0)
                    .foregroundStyle(isActive || isHovered ? SidebarChrome.primary : SidebarChrome.secondary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                trailing(for: tab, active: isActive, hovered: isHovered)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8.5)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isActive ? Palette.accent.opacity(0.14) : (isHovered ? SidebarChrome.rowHover : Color.clear))
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(SidebarPressStyle())
        .focusable(false)
        .onHover { hovering in
            hoveredTab = hovering ? tab : nil
        }
        .keyboardShortcut(shortcutKey(for: tab), modifiers: .command)
        .help(tab.label)
    }

    /// Sağ uç: canlı mikro veri varsa o (aktifken mercan), yoksa mono ⌘kısayol.
    @ViewBuilder
    private func trailing(for tab: NavTab, active: Bool, hovered: Bool) -> some View {
        if let data = liveData(for: tab) {
            Text(data)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(active ? Palette.accent : SidebarChrome.quiet)
                .lineLimit(1)
        } else if let key = shortcutLabel(for: tab) {
            Text(key)
                .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                .foregroundStyle(SidebarChrome.quiet)
                .opacity(hovered ? 0.85 : 0.55)
        }
    }

    // MARK: - Kısayollar

    private func shortcutLabel(for tab: NavTab) -> String? {
        guard let idx = Self.orderedTabs.firstIndex(of: tab), idx < 8 else { return nil }
        return "⌘\(idx + 1)"
    }

    private func shortcutKey(for tab: NavTab) -> KeyEquivalent {
        guard let idx = Self.orderedTabs.firstIndex(of: tab), idx < 8 else { return KeyEquivalent("0") }
        return KeyEquivalent(Character("\(idx + 1)"))
    }

    // MARK: - Canlı mikro veriler

    private func liveData(for tab: NavTab) -> String? {
        switch tab {
        case .measurements:
            guard let w = measurements.last(where: { $0.weight != nil })?.weight else { return nil }
            return "\(Fmt.num(w, digits: 1)) kg"
        case .calendar:
            guard let remaining = remainingKcalToday else { return nil }
            return remaining >= 0 ? "\(Fmt.int(remaining)) kaldı" : "\(Fmt.int(-remaining)) fazla"
        case .workout:
            return nextWorkoutLabel
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
                Circle()
                    .fill(Palette.accent)
                    .frame(width: 6, height: 6)
                Text("Koç'a sor")
                    .font(.system(size: 12.5, weight: isActive ? .bold : .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(SidebarChrome.primary)
                Spacer(minLength: 0)
                Text("⌘8")
                    .font(.system(size: 9.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.accent.opacity(0.75))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.accent.opacity(isActive ? 0.16 : (coachHovering ? 0.13 : 0.09)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isActive ? Palette.accent.opacity(0.4) : Color.clear, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(SidebarPressStyle())
        .focusable(false)
        .onHover { coachHovering = $0 }
        .keyboardShortcut("8", modifiers: .command)
        .help("Tam sayfa AI koç sohbetini aç (⌘8)")
    }

    // MARK: - Alt blok

    private var footer: some View {
        VStack(spacing: 12) {
            Hairline()
            ProfileFooter(
                isSelected: selection == .profile,
                onTap: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                        selection = .profile
                    }
                }
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
        Self.schedule(from: nsView)
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
