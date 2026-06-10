import SwiftUI
import SwiftData

/// Bilim Paneli — V1 dili: her kart bir SORU + kısa YARGI + görsel skala.
/// Deterministik analiz (AI değil); verinden hesaplanır. Açıklama paragrafları yok —
/// bilimsel notlar hover'da (.help), tüm metodoloji sayfa altında tek mikro satır.
struct AnalysisView: View {
    @Query(sort: \Measurement.date) private var measurements: [Measurement]
    @Query(sort: \FoodEntry.date) private var foods: [FoodEntry]
    @Query(sort: \WorkoutLog.date) private var workouts: [WorkoutLog]
    @Query(sort: \StepEntry.date) private var steps: [StepEntry]
    @Query private var programSessions: [WorkoutSession]
    @Query private var profiles: [UserProfile]

    private var profile: UserProfile? { profiles.first }
    private var goal: Goal { profile?.goal ?? .maintain }

    private let trLocale = Locale(identifier: "tr_TR")

    // MARK: - Motor çıktıları

    private var lifts: [ScienceEngine.LiftProgress] {
        ScienceEngine.strengthProgress(workouts: workouts)
    }

    /// Hacim kaynağı: Antrenman sayfasındaki PROGRAM varsa ondan (kullanıcı seansları
    /// tek tek loglamıyor — planlanan = uygulanan, CoachEngine ile aynı kabul);
    /// program boşsa son 7 günün loglarından.
    private var volumesFromProgram: Bool {
        ScienceEngine.weeklyVolumeFromProgram(sessions: programSessions)
            .contains { $0.sets > 0 }
    }

    private var volumes: [ScienceEngine.MuscleVolume] {
        let program = ScienceEngine.weeklyVolumeFromProgram(sessions: programSessions)
        if program.contains(where: { $0.sets > 0 }) { return program }
        return ScienceEngine.weeklyVolume(workouts: workouts)
    }

    private var energy: ScienceEngine.AdaptiveEnergy? {
        ScienceEngine.bestAdaptiveEnergy(measurements: measurements, foods: foods)
    }

    private var scoreItems: [ScienceEngine.ScoreItem] {
        ScienceEngine.scorecard(
            foods: foods, steps: steps, measurements: measurements,
            energy: energy, volumes: volumes,
            bodyWeightKg: energy?.trendWeightNow ?? latestWeight,
            goal: goal
        )
    }

    private var latestWeight: Double? {
        measurements.last(where: { $0.weight != nil })?.weight
    }
    private var latestBodyFat: Double? {
        measurements.last(where: { $0.bodyFat != nil })?.bodyFat
    }

    /// Karşılaştırma için statik TDEE (BMR × aktivite).
    private var staticTDEE: Double? {
        guard let p = profile, let w = latestWeight else { return nil }
        return CalorieCalculator.compute(
            weight: w, height: p.height, age: p.age, sex: p.sex,
            bodyFat: latestBodyFat ?? p.manualBodyFat,
            activity: p.activity, goal: p.goal
        ).tdee
    }

    private var projection: ScienceEngine.GoalProjection? {
        guard let e = energy else { return nil }
        return ScienceEngine.goalProjection(energy: e, targetWeight: profile?.targetWeight)
    }

    // MARK: - Body

    var body: some View {
        // Viewport'u doldur: kartlar (qCard maxHeight ∞) kalan boşluğu paylaşır,
        // metodoloji dipnotu dibe yapışır; pencere kısaysa sayfa yine kayar.
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    header
                    if let e = energy {
                        HStack(alignment: .top, spacing: Spacing.lg) {
                            tdeeCard(e)
                            speedCard(e)
                        }
                    } else {
                        insufficientCard
                    }
                    if !scoreItems.isEmpty { karneCard }
                    bottomRow
                    footnote
                }
                .padding(Spacing.xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(minHeight: proxy.size.height, alignment: .topLeading)
            }
        }
        .background(Palette.background.ignoresSafeArea())
    }

    @ViewBuilder private var bottomRow: some View {
        let hasVolume = volumes.contains { $0.sets > 0 }
        if hasVolume && !lifts.isEmpty {
            HStack(alignment: .top, spacing: Spacing.lg) {
                volumeCard
                strengthCard
            }
        } else if hasVolume {
            volumeCard
        } else if !lifts.isEmpty {
            strengthCard
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .lastTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("ANALİZ").eyebrow()
                Text("Bilim Paneli")
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.2)
                    .foregroundStyle(Palette.textPrimary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                Circle().fill(Palette.positive).frame(width: 6, height: 6)
                Text("VERİ").eyebrow()
                Text(dataBadge)
                    .font(.system(size: 12.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Palette.textPrimary)
            }
        }
    }

    private var dataBadge: String {
        let cal = Calendar.current
        let foodDays = Set(foods.map { cal.startOfDay(for: $0.date) }).count
        let weighIns = measurements.filter { $0.weight != nil }.count
        var parts = ["\(foodDays) yemek günü", "\(weighIns) tartı"]
        // Antrenman: program varsa haftalık gün sayısı (loglardan bağımsız), yoksa log sayısı.
        let programDays = programSessions.filter {
            !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && !$0.templateExercises.isEmpty
        }.count
        if programDays > 0 {
            parts.append("\(programDays) günlük program")
        } else if !workouts.isEmpty {
            parts.append("\(workouts.count) seans")
        }
        let stepDays = Set(steps.map { cal.startOfDay(for: $0.date) }).count
        if stepDays > 0 {
            parts.append("\(stepDays) adım günü")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Kart kabuğu: soru + yargı + içerik

    private func qCard<Content: View>(
        _ question: String,
        answer: String,
        answerColor: Color,
        meta: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(question)
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.textTertiary)
                Text(answer)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(answerColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                if let meta {
                    Text(meta)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
            }
            content()
        }
        .padding(EdgeInsets(top: 18, leading: 22, bottom: 16, trailing: 22))
        // maxHeight ∞: sayfa viewport'a gerilince kartlar kalan boşluğu eşit paylaşır.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .dashboardCard()
    }

    // MARK: - İstatistik hücre şeridi (hairline üstü, dikey ayraçlı)

    private struct Cell {
        let label: String
        let value: String
        var sub: String? = nil
        var valueColor: Color? = nil
    }

    private func statCells(_ cells: [Cell]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Hairline()
            HStack(alignment: .top, spacing: 16) {
                ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                    if i > 0 {
                        Rectangle().fill(Palette.border).frame(width: 1, height: 34)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(c.label)
                            .font(.system(size: 9.5, weight: .medium))
                            .tracking(0.7)
                            .textCase(.uppercase)
                            .foregroundStyle(Palette.textTertiary)
                        Text(c.value)
                            .font(.system(size: 14, weight: .regular, design: .monospaced))
                            .foregroundStyle(c.valueColor ?? Palette.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if let sub = c.sub {
                            Text(sub)
                                .font(.system(size: 10.5))
                                .foregroundStyle(Palette.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 12)
        }
    }

    // MARK: - 1) TDEE kartı

    private func tdeeCard(_ e: ScienceEngine.AdaptiveEnergy) -> some View {
        qCard("Gerçekten kaç kalori yakıyorum?", answer: tdeeAnswer(e), answerColor: Palette.textSecondary) {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text(Fmt.int(e.adaptiveTDEE))
                    .font(.system(size: 42, weight: .bold))
                    .monospacedDigit()
                    .tracking(-0.8)
                    .foregroundStyle(Palette.textPrimary)
                Text("kcal/gün")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                confidencePill(e.confidence)
            }
            .padding(.top, 10)

            statCells([
                Cell(label: "Ortalama alım", value: "\(Fmt.int(e.avgIntake)) kcal", sub: "\(e.loggedDays) kayıtlı gün"),
                Cell(label: "Trend kilo", value: "\(Fmt.num(e.trendWeightNow, digits: 1)) kg", sub: "ham: \(Fmt.num(e.rawWeightNow, digits: 1))"),
                Cell(label: "Haftalık", value: "\(Fmt.signed(e.slopeKgPerWeek, digits: 2)) kg", sub: "\(Fmt.signed(e.ratePercentPerWeek, digits: 2))%"),
                Cell(label: "Günlük denge", value: "\(Fmt.signed(e.dailyBalanceVsMaintenance)) kcal", sub: e.dailyBalanceVsMaintenance < 0 ? "açık" : "fazla"),
            ])
            .padding(.top, 14)
        }
    }

    private func tdeeAnswer(_ e: ScienceEngine.AdaptiveEnergy) -> String {
        guard let s = staticTDEE else { return e.confidence.detail }
        let diff = e.adaptiveTDEE - s
        if abs(diff) < 25 { return "Formül tahminiyle örtüşüyor." }
        return "Formülün dediğinden \(Fmt.int(abs(diff))) kcal daha \(diff < 0 ? "az" : "fazla")."
    }

    private func confidencePill(_ c: ScienceEngine.AdaptiveEnergy.Confidence) -> some View {
        let color: Color = c == .high ? Palette.positive : (c == .medium ? Palette.warning : Palette.textTertiary)
        return Text(c.label.uppercased(with: trLocale))
            .font(.system(size: 9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3.5)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(color.opacity(0.30), lineWidth: 1))
            .help(c.detail)
    }

    // MARK: - 2) Hız + ETA kartı

    private func speedCard(_ e: ScienceEngine.AdaptiveEnergy) -> some View {
        let v = ScienceEngine.rateVerdict(percentPerWeek: e.ratePercentPerWeek, goal: goal)
        return qCard("Doğru hızda mıyım, ne zaman varırım?", answer: v.label + ".", answerColor: toneColor(v.tone)) {
            rateBand(rate: e.ratePercentPerWeek)
                .padding(.top, 18)
                .help(v.note)
            etaSection(e)
                .padding(.top, 16)
        }
    }

    /// Hedefe göre üç bölgeli hız bandı: bölge genişlik oranları + imleç konumu (0…1).
    private struct Band {
        struct Zone {
            let width: Double
            let color: Color
            let label: String
            let ideal: Bool
        }
        let zones: [Zone]
        let position: Double
    }

    private func bandConfig(rate: Double) -> Band {
        let off = Palette.track
        let ideal = Palette.positive.opacity(0.45)
        let hot = Palette.negative.opacity(0.35)
        let rateText = Fmt.signed(rate, digits: 2) + "%"
        switch goal {
        case .lose, .loseFast:
            // skala 0…−1.5: 0–0.5 yavaş · 0.5–1.0 ideal · 1.0–1.5 çok hızlı
            return Band(zones: [
                .init(width: 1.0 / 3, color: off, label: "yavaş", ideal: false),
                .init(width: 1.0 / 3, color: ideal, label: "ideal · \(rateText)", ideal: true),
                .init(width: 1.0 / 3, color: hot, label: "çok hızlı", ideal: false),
            ], position: min(1, max(0, -rate / 1.5)))
        case .gain, .gainFast:
            // skala 0…+0.75: 0–0.25 yavaş · 0.25–0.5 ideal · 0.5–0.75 çok hızlı
            return Band(zones: [
                .init(width: 1.0 / 3, color: off, label: "yavaş", ideal: false),
                .init(width: 1.0 / 3, color: ideal, label: "ideal · \(rateText)", ideal: true),
                .init(width: 1.0 / 3, color: hot, label: "çok hızlı", ideal: false),
            ], position: min(1, max(0, rate / 0.75)))
        case .maintain:
            // skala −0.6…+0.6: ortada ±0.1 stabil bandı
            return Band(zones: [
                .init(width: 5.0 / 12, color: hot, label: "veriyor", ideal: false),
                .init(width: 2.0 / 12, color: ideal, label: "stabil · \(rateText)", ideal: true),
                .init(width: 5.0 / 12, color: hot, label: "alıyor", ideal: false),
            ], position: min(1, max(0, (rate + 0.6) / 1.2)))
        }
    }

    private func rateBand(rate: Double) -> some View {
        let band = bandConfig(rate: rate)
        return VStack(alignment: .leading, spacing: 7) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        ForEach(Array(band.zones.enumerated()), id: \.offset) { _, z in
                            Rectangle().fill(z.color).frame(width: w * z.width)
                        }
                    }
                    .frame(height: 10)
                    .clipShape(Capsule())
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(.white)
                        .frame(width: 2.5, height: 22)
                        .offset(x: min(w - 2.5, max(0, w * band.position - 1.25)))
                }
                .frame(height: 22, alignment: .leading)
            }
            .frame(height: 22)
            GeometryReader { geo in
                HStack(spacing: 0) {
                    ForEach(Array(band.zones.enumerated()), id: \.offset) { i, z in
                        Text(z.label)
                            .font(.system(size: 11.5, weight: z.ideal ? .semibold : .regular))
                            .foregroundStyle(z.ideal ? Palette.positive : Palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(
                                width: geo.size.width * z.width,
                                alignment: i == 0 ? .leading : (i == band.zones.count - 1 ? .trailing : .center)
                            )
                    }
                }
            }
            .frame(height: 14)
        }
    }

    @ViewBuilder private func etaSection(_ e: ScienceEngine.AdaptiveEnergy) -> some View {
        if let proj = projection {
            if proj.movingToward, let date = proj.etaDate, let days = proj.etaDays {
                statCells([
                    Cell(label: "Bugün", value: "\(Fmt.num(proj.trendNow, digits: 1)) kg"),
                    Cell(label: "Kalan", value: "\(Fmt.num(abs(proj.kgToGo), digits: 1)) kg"),
                    Cell(label: "Varış", value: Fmt.dateLong.string(from: date), valueColor: Palette.positive),
                    Cell(label: "Süre", value: "\(days) gün"),
                ])
            } else {
                statCells([
                    Cell(label: "Bugün", value: "\(Fmt.num(proj.trendNow, digits: 1)) kg"),
                    Cell(label: "Hedef", value: "\(Fmt.num(proj.targetWeight, digits: 1)) kg"),
                    Cell(label: "Kalan", value: "\(Fmt.num(abs(proj.kgToGo), digits: 1)) kg", sub: proj.kgToGo < 0 ? "vermen gerek" : "alman gerek"),
                    Cell(label: "Varış", value: "—", sub: "trend hedefe gitmiyor", valueColor: Palette.warning),
                ])
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Hairline()
                Text("Profil'de hedef kilo tanımlı değil — varış tahmini için hedef gir.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 12)
            }
        }
    }

    // MARK: - 3) Haftalık karne

    private var karneCard: some View {
        qCard("Bu hafta neyi iyi yaptım, neyi değil?", answer: karneAnswer, answerColor: Palette.textSecondary, meta: "son 14 gün") {
            VStack(spacing: 0) {
                ForEach(Array(scoreItems.enumerated()), id: \.element.id) { i, item in
                    if i > 0 { Hairline() }
                    karneRow(item)
                }
            }
            .padding(.top, 6)
        }
    }

    private var karneAnswer: String {
        let good = scoreItems.filter { $0.tone == .good }.count
        let watch = scoreItems.filter { $0.tone == .warn || $0.tone == .neutral }.count
        let bads = scoreItems.filter { $0.tone == .bad }
        var s = "\(good) yeşil · \(watch) izle · \(bads.count) kırmızı"
        if !bads.isEmpty {
            s += " — \(bads.map { $0.title.lowercased(with: trLocale) }.joined(separator: ", ")) zayıf."
        } else if good == scoreItems.count, !scoreItems.isEmpty {
            s += " — hepsi yolunda."
        } else {
            s += "."
        }
        return s
    }

    private func karneRow(_ item: ScienceEngine.ScoreItem) -> some View {
        HStack(spacing: 14) {
            Circle().fill(toneColor(item.tone)).frame(width: 7, height: 7)
            Text(item.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)
            Text(item.target)
                .font(.system(size: 11.5, weight: .regular, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .frame(width: 210, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.track)
                    Capsule()
                        .fill(toneColor(item.tone).opacity(0.8))
                        .frame(width: max(3, geo.size.width * item.progress))
                }
            }
            .frame(height: 3)
            Text(item.value)
                .font(.system(size: 13.5, weight: .regular, design: .monospaced))
                .foregroundStyle(toneColor(item.tone))
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(width: 138, alignment: .trailing)
        }
        .padding(.vertical, 10)
        .help(item.note)
    }

    // MARK: - 4) Haftalık hacim (MEV–MRV)

    private var volumeCard: some View {
        let trained = volumes.filter { $0.sets > 0 }
        let unders = trained.filter { $0.status == .under }
        let overs = trained.filter { $0.status == .over }
        let untrained = volumes.filter { $0.sets == 0 }

        let answer: String
        let answerColor: Color
        if !unders.isEmpty {
            answer = "\(joinNames(unders.map { $0.muscle.label })) minimumun altında."
            answerColor = Palette.warning
        } else if !overs.isEmpty {
            answer = "\(joinNames(overs.map { $0.muscle.label })) MRV üstünde."
            answerColor = Palette.negative
        } else {
            answer = "Tüm kaslar verimli bantta."
            answerColor = Palette.positive
        }

        return qCard(
            "Hangi kası az, hangisini fazla çalıştırıyorum?",
            answer: answer,
            answerColor: answerColor,
            meta: volumesFromProgram ? "haftalık programdan" : "son 7 gün logdan"
        ) {
            VStack(spacing: 2) {
                ForEach(trained) { volumeRow($0) }
            }
            .padding(.top, 10)
            if !untrained.isEmpty {
                Text("\(volumesFromProgram ? "Programda hiç" : "Bu hafta hiç"): \(untrained.map { $0.muscle.label }.joined(separator: ", "))")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
        }
    }

    private func joinNames(_ names: [String]) -> String {
        names.count == 2 ? "\(names[0]) ve \(names[1])" : names.joined(separator: ", ")
    }

    private func volumeRow(_ mv: ScienceEngine.MuscleVolume) -> some View {
        let l = mv.muscle.landmarks
        let color = volStatusColor(mv.status)
        let scale = l.mrv + 5
        let setsText = mv.sets == mv.sets.rounded() ? "\(Int(mv.sets))" : Fmt.num(mv.sets, digits: 1)
        return HStack(spacing: 14) {
            Text(mv.muscle.label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)
            GeometryReader { geo in
                let w = geo.size.width
                let mevX = CGFloat(min(1, l.mev / scale)) * w
                let mrvX = CGFloat(min(1, l.mrv / scale)) * w
                let fillW = CGFloat(min(1, mv.sets / scale)) * w
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Palette.track)
                        .frame(height: 6)
                    Rectangle()
                        .fill(Palette.positive.opacity(0.16))
                        .frame(width: max(0, mrvX - mevX), height: 6)
                        .offset(x: mevX)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color.opacity(0.85))
                        .frame(width: max(3, fillW), height: 6)
                    Rectangle().fill(Palette.textTertiary).frame(width: 1.5, height: 12).offset(x: mevX)
                    Rectangle().fill(Palette.textTertiary).frame(width: 1.5, height: 12).offset(x: mrvX)
                }
                .frame(height: 14, alignment: .leading)
            }
            .frame(height: 14)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(setsText)
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                Text(volStatusLabel(mv.status))
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(color)
            }
            .frame(width: 96, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .help("MEV \(Int(l.mev)) · MAV \(Int(l.mav)) · MRV \(Int(l.mrv)) set/hafta")
    }

    private func volStatusColor(_ s: ScienceEngine.VolumeStatus) -> Color {
        switch s {
        case .under:      return Palette.warning
        case .productive: return Palette.positive
        case .high:       return Palette.macroFat
        case .over:       return Palette.negative
        }
    }
    private func volStatusLabel(_ s: ScienceEngine.VolumeStatus) -> String {
        switch s {
        case .under:      return "AZ"
        case .productive: return "VERİMLİ"
        case .high:       return "YÜKSEK"
        case .over:       return "FAZLA"
        }
    }

    // MARK: - 5) Güç ilerlemesi (e1RM)

    private var strengthCard: some View {
        let shown = Array(lifts.prefix(8))
        let deloads = lifts.filter { $0.suggestsDeload }
        let improving = lifts.filter { $0.trend == .improving }.count

        let answer: String
        let answerColor: Color
        if !deloads.isEmpty {
            answer = "\(joinNames(deloads.prefix(3).map(\.name))) düşüşte — deload düşün."
            answerColor = Palette.warning
        } else {
            answer = "\(improving)/\(lifts.count) hareket artışta — deload gerekmiyor."
            answerColor = improving > 0 ? Palette.positive : Palette.textSecondary
        }

        return qCard("Güçleniyor muyum, deload lazım mı?", answer: answer, answerColor: answerColor, meta: "son 90 gün") {
            VStack(spacing: 0) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { i, lift in
                    if i > 0 { Hairline() }
                    liftRow(lift)
                }
            }
            .padding(.top, 6)
        }
    }

    private func liftRow(_ lift: ScienceEngine.LiftProgress) -> some View {
        HStack(spacing: 12) {
            Text(lift.name)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            SparklineView(values: lift.history, color: trendColor(lift.trend))
                .frame(width: 104, height: 20)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(Fmt.num(lift.latestE1RM, digits: 1))
                    .font(.system(size: 12.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.textPrimary)
                Text("kg")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(width: 76, alignment: .trailing)
            HStack(spacing: 3) {
                Image(systemName: trendIcon(lift.trend))
                    .font(.system(size: 8, weight: .bold))
                Text(Fmt.signed(lift.changePercent, digits: 1) + "%")
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
            }
            .foregroundStyle(trendColor(lift.trend))
            .frame(width: 76, alignment: .trailing)
        }
        .padding(.vertical, 8)
        .help("\(lift.sessions) seans · en iyi \(Fmt.num(lift.bestE1RM, digits: 1)) kg")
    }

    private func trendColor(_ t: ScienceEngine.LiftProgress.Trend) -> Color {
        switch t {
        case .improving: return Palette.positive
        case .declining: return Palette.negative
        case .flat:      return Palette.textTertiary
        }
    }
    private func trendIcon(_ t: ScienceEngine.LiftProgress.Trend) -> String {
        switch t {
        case .improving: return "arrow.up.right"
        case .declining: return "arrow.down.right"
        case .flat:      return "arrow.right"
        }
    }

    // MARK: - Yetersiz veri

    private var insufficientCard: some View {
        let weightCount = measurements.filter { $0.weight != nil }.count
        let loggedDays = Set(foods.map { Calendar.current.startOfDay(for: $0.date) }).count
        return qCard("Gerçekten kaç kalori yakıyorum?", answer: "Henüz hesaplayamıyorum — biraz daha veri lazım.", answerColor: Palette.warning) {
            Text("Gerçek TDEE'yi enerji dengesinden çözmek için en az ~10 günü kapsayan 2+ kilo ölçümü ve 7+ kayıtlı yemek günü gerekiyor. Logladıkça burası otomatik dolacak.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            statCells([
                Cell(label: "Kilo ölçümü", value: "\(weightCount)"),
                Cell(label: "Kayıtlı yemek günü", value: "\(loggedDays)"),
            ])
            .padding(.top, 14)
        }
    }

    // MARK: - Metodoloji dipnotu (tek mikro satır)

    private var footnote: some View {
        Text("TDEE enerji dengesinden geriye çözülür (alım − Δtrend kilo × 7700) · trend kilo regresyonla süzülür · ideal hız %0,5–1/hafta (Helms 2014) · hacim bantları MEV/MRV (RP) · e1RM Epley: ağırlık × (1 + tekrar/30)")
            .font(.system(size: 10))
            .foregroundStyle(Palette.textTertiary.opacity(0.75))
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 2)
    }

    // MARK: - Tone helpers

    private func toneColor(_ t: ScienceEngine.RateTone) -> Color {
        switch t {
        case .good:    return Palette.positive
        case .warn:    return Palette.warning
        case .bad:     return Palette.negative
        case .neutral: return Palette.textTertiary
        }
    }
}

// MARK: - Sparkline

/// Mini çizgi grafik — e1RM serisi gibi kısa skalar dizileri çizer.
private struct SparklineView: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = points(in: geo.size)
            ZStack {
                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, lineJoin: .round))
                if let last = pts.last {
                    Circle()
                        .fill(color)
                        .frame(width: 3.5, height: 3.5)
                        .position(last)
                }
            }
        }
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard values.count >= 2 else {
            return values.count == 1
                ? [CGPoint(x: 0, y: size.height / 2), CGPoint(x: size.width, y: size.height / 2)]
                : []
        }
        let lo = values.min() ?? 0
        let hi = values.max() ?? 1
        let span = hi - lo
        let inset: CGFloat = 2
        let h = size.height - inset * 2
        let stepX = size.width / CGFloat(values.count - 1)
        return values.enumerated().map { i, v in
            let t = span > 0.0001 ? (v - lo) / span : 0.5
            return CGPoint(x: CGFloat(i) * stepX, y: inset + h * CGFloat(1 - t))
        }
    }
}
