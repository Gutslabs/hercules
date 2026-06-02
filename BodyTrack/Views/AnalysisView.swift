import SwiftUI
import SwiftData

/// Bilim Paneli — verinden hesaplanan deterministik analiz (AI değil). İlk modül:
/// adaptif metabolizma (gerçek TDEE), trend kilo, kayıp-hızı bekçisi, hedef ETA.
struct AnalysisView: View {
    @Query(sort: \Measurement.date) private var measurements: [Measurement]
    @Query(sort: \FoodEntry.date) private var foods: [FoodEntry]
    @Query(sort: \WorkoutLog.date) private var workouts: [WorkoutLog]
    @Query(sort: \StepEntry.date) private var steps: [StepEntry]
    @Query private var profiles: [UserProfile]

    private var profile: UserProfile? { profiles.first }

    private var lifts: [ScienceEngine.LiftProgress] {
        ScienceEngine.strengthProgress(workouts: workouts)
    }

    private var volumes: [ScienceEngine.MuscleVolume] {
        ScienceEngine.weeklyVolume(workouts: workouts)
    }

    private var scoreItems: [ScienceEngine.ScoreItem] {
        ScienceEngine.scorecard(
            foods: foods, steps: steps, measurements: measurements,
            energy: energy, volumes: volumes,
            bodyWeightKg: energy?.trendWeightNow ?? latestWeight,
            goal: profile?.goal ?? .maintain
        )
    }

    private var energy: ScienceEngine.AdaptiveEnergy? {
        ScienceEngine.bestAdaptiveEnergy(measurements: measurements, foods: foods)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                header
                if !scoreItems.isEmpty {
                    scorecardView
                }
                if let e = energy {
                    metabolismCard(e)
                } else {
                    insufficientCard
                }
                methodFootnote
                if volumes.contains(where: { $0.sets > 0 }) {
                    volumeCard
                }
                if !lifts.isEmpty {
                    strengthCard
                }
            }
            .padding(Spacing.xl)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.background.ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("ANALİZ").eyebrow()
            Text("Bilim Paneli")
                .font(Typography.titleSmall)
                .foregroundStyle(Palette.textPrimary)
            Text("Verinden hesaplanan gerçek metabolizma — formül tahmini değil, enerji dengesinden geriye çözülmüş.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Metabolizma kartı

    private func metabolismCard(_ e: ScienceEngine.AdaptiveEnergy) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            // Adaptif TDEE büyük gösterim
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("ADAPTİF BAKIM (TDEE)")
                        .font(Typography.label).tracking(0.6)
                        .foregroundStyle(Palette.textTertiary)
                    confidencePill(e.confidence)
                    Spacer(minLength: 0)
                }
                HStack(alignment: .lastTextBaseline, spacing: 6) {
                    Text(Fmt.int(e.adaptiveTDEE))
                        .font(.system(size: 42, weight: .bold, design: .rounded))
                        .foregroundStyle(Palette.textPrimary)
                    Text("kcal/gün")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textTertiary)
                }
                if let s = staticTDEE {
                    let diff = e.adaptiveTDEE - s
                    Text("Statik formül tahmini \(Fmt.int(s)) kcal — gerçeğin \(Fmt.int(abs(diff))) kcal \(diff >= 0 ? "altında" : "üstünde").")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Hairline()

            // İstatistik tablosu
            let cols = [GridItem(.adaptive(minimum: 150), spacing: Spacing.md)]
            LazyVGrid(columns: cols, alignment: .leading, spacing: Spacing.md) {
                statTile("Ortalama alım",
                         "\(Fmt.int(e.avgIntake)) kcal",
                         "\(e.loggedDays) kayıtlı gün")
                statTile("Trend kilo",
                         "\(Fmt.num(e.trendWeightNow, digits: 1)) kg",
                         "ham: \(Fmt.num(e.rawWeightNow, digits: 1)) kg")
                statTile("Haftalık değişim",
                         "\(Fmt.signed(e.slopeKgPerWeek, digits: 2)) kg",
                         "\(Fmt.signed(e.ratePercentPerWeek, digits: 2))%/hafta")
                statTile("Günlük denge",
                         "\(Fmt.signed(e.dailyBalanceVsMaintenance)) kcal",
                         e.dailyBalanceVsMaintenance < 0 ? "açık" : "fazla")
            }

            // Hız bekçisi
            verdictBanner(ScienceEngine.rateVerdict(percentPerWeek: e.ratePercentPerWeek, goal: profile?.goal ?? .maintain))

            // Hedef ETA
            if let proj = ScienceEngine.goalProjection(energy: e, targetWeight: profile?.targetWeight) {
                goalRow(proj)
            }
        }
        .padding(Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    private func statTile(_ label: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased(with: Locale(identifier: "tr_TR")))
                .font(Typography.label).tracking(0.5)
                .foregroundStyle(Palette.textTertiary)
            Text(value)
                .font(Typography.bodyBold)
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(sub)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.surfaceElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    private func verdictBanner(_ v: ScienceEngine.RateVerdict) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: toneIcon(v.tone))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(toneColor(v.tone))
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(v.label)
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                Text(v.note)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(toneColor(v.tone).opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(toneColor(v.tone).opacity(0.22), lineWidth: 0.5))
    }

    private func goalRow(_ proj: ScienceEngine.GoalProjection) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "target")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Hedef \(Fmt.num(proj.targetWeight, digits: 1)) kg")
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                if proj.movingToward, let date = proj.etaDate, let days = proj.etaDays {
                    Text("Bu hızla ~\(Fmt.dateLong.string(from: date)) (\(days) gün). \(Fmt.num(abs(proj.kgToGo), digits: 1)) kg kaldı.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Trend şu an hedefe doğru gitmiyor (\(Fmt.num(abs(proj.kgToGo), digits: 1)) kg \(proj.kgToGo < 0 ? "vermen" : "alman") gerek). Açığı/fazlayı ayarla.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.surfaceElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    private func confidencePill(_ c: ScienceEngine.AdaptiveEnergy.Confidence) -> some View {
        let color: Color = c == .high ? Palette.positive : (c == .medium ? Color.orange : Palette.textTertiary)
        return Text(c.label.uppercased(with: Locale(identifier: "tr_TR")))
            .font(.system(size: 9, weight: .bold)).tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.14)))
            .help(c.detail)
    }

    // MARK: - Yetersiz veri

    private var insufficientCard: some View {
        let recent = ScienceEngine.kcalPerKg // unused placeholder to keep type-checker calm
        let weightCount = measurements.filter { $0.weight != nil }.count
        let loggedDays = Set(foods.map { Calendar.current.startOfDay(for: $0.date) }).count
        _ = recent
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                Image(systemName: "hourglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Text("Adaptif metabolizma için biraz daha veri lazım")
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
            }
            Text("Gerçek TDEE'yi enerji dengesinden çözmek için en az ~10 günü kapsayan 2+ kilo ölçümü ve 7+ kayıtlı yemek günü gerekiyor. Logladıkça burası otomatik dolacak.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                miniStat("\(weightCount)", "kilo ölçümü")
                miniStat("\(loggedDays)", "kayıtlı yemek günü")
            }
            .padding(.top, 2)
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(Typography.bodyBold).foregroundStyle(Palette.accent)
            Text(label).font(Typography.caption).foregroundStyle(Palette.textTertiary)
        }
    }

    // MARK: - Yöntem dipnotu

    private var methodFootnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("NASIL HESAPLANIYOR")
                .font(Typography.label).tracking(0.6)
                .foregroundStyle(Palette.textTertiary)
            Text("TDEE ≈ ortalama alım − (Δtrend kilo × ~7700 kcal/kg). Trend kilo, ölçümlere en-küçük-kareler regresyonuyla uydurulup günlük su gürültüsü süzülerek bulunur. Bu, statik BMR×aktivite formülünün yakalayamadığı metabolik adaptasyonu (Rosenbaum & Leibel) yansıtır; MacroFactor'ın yaklaşımıdır. Sağlıklı kayıp hızı referansı ~%0.5–1 BW/hafta (Garthe 2011; Helms 2014).")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    // MARK: - Haftalık karne (scorecard)

    private var scorecardView: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: 8) {
                Text("HAFTALIK KARNE")
                    .font(Typography.label).tracking(0.6).foregroundStyle(Palette.textTertiary)
                Spacer()
                Text("son 14 gün").font(Typography.label).foregroundStyle(Palette.textTertiary)
            }
            VStack(spacing: 8) {
                ForEach(scoreItems) { scoreRow($0) }
            }
        }
        .padding(Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    private func scoreRow(_ item: ScienceEngine.ScoreItem) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: toneIcon(item.tone))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(toneColor(item.tone))
                .frame(width: 18)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(item.title).font(Typography.bodyBold).foregroundStyle(Palette.textPrimary)
                    Spacer(minLength: 0)
                    Text(item.value).font(Typography.bodyBold).foregroundStyle(toneColor(item.tone))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Text(item.target)
                    .font(Typography.label).foregroundStyle(Palette.textTertiary)
                Text(item.note)
                    .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.surfaceElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    // MARK: - Hacim landmark kartı

    private var volumeCard: some View {
        let trained = volumes.filter { $0.sets > 0 }.sorted { a, b in
            if volRank(a.status) != volRank(b.status) { return volRank(a.status) < volRank(b.status) }
            return a.sets > b.sets
        }
        let untrained = volumes.filter { $0.sets == 0 }
        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: 8) {
                Text("HAFTALIK HACİM (set/kas)")
                    .font(Typography.label).tracking(0.6).foregroundStyle(Palette.textTertiary)
                Spacer()
                Text("son 7 gün").font(Typography.label).foregroundStyle(Palette.textTertiary)
            }
            VStack(spacing: 11) {
                ForEach(trained) { volumeRow($0) }
            }
            if !untrained.isEmpty {
                Text("Bu hafta hiç: \(untrained.map { $0.muscle.label }.joined(separator: ", "))")
                    .font(Typography.caption).foregroundStyle(Palette.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                legendDot("az", Color.orange)
                legendDot("verimli", Palette.positive)
                legendDot("yüksek", Color.yellow)
                legendDot("fazla", Palette.negative)
                Spacer(minLength: 0)
            }
            Text("Çizgiler MEV (min etkili) ve MRV (maks toparlanabilir) hacmi gösterir. Referans: RP/Israetel landmarkları + Schoenfeld doz-yanıt (~10+ set/hafta). Eşleşmeyen hareketler atlanır.")
                .font(Typography.caption).foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    private func volumeRow(_ mv: ScienceEngine.MuscleVolume) -> some View {
        let l = mv.muscle.landmarks
        let color = volStatusColor(mv.status)
        let setsText = mv.sets == mv.sets.rounded() ? "\(Int(mv.sets))" : Fmt.num(mv.sets, digits: 1)
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text(mv.muscle.label).font(Typography.captionBold).foregroundStyle(Palette.textPrimary)
                Spacer(minLength: 0)
                Text("\(setsText) set").font(Typography.captionBold).foregroundStyle(color)
                Text(volStatusLabel(mv.status)).font(Typography.label).foregroundStyle(color)
            }
            GeometryReader { geo in
                let w = max(1, geo.size.width)
                let maxScale = l.mrv * 1.18
                let fillW = min(w, CGFloat(mv.sets / maxScale) * w)
                let mevX = min(w, CGFloat(l.mev / maxScale) * w)
                let mrvX = min(w, CGFloat(l.mrv / maxScale) * w)
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surfaceElevated).frame(height: 7)
                    Capsule().fill(color).frame(width: max(3, fillW), height: 7)
                    Rectangle().fill(Palette.textSecondary.opacity(0.7)).frame(width: 1.5, height: 13).offset(x: mevX)
                    Rectangle().fill(Palette.textTertiary.opacity(0.7)).frame(width: 1.5, height: 13).offset(x: mrvX)
                }
                .frame(height: 13, alignment: .leading)
            }
            .frame(height: 13)
        }
    }

    private func legendDot(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label).font(Typography.label).foregroundStyle(Palette.textTertiary)
        }
    }

    private func volRank(_ s: ScienceEngine.VolumeStatus) -> Int {
        switch s {
        case .under: return 0
        case .over:  return 1
        case .high:  return 2
        case .productive: return 3
        }
    }
    private func volStatusColor(_ s: ScienceEngine.VolumeStatus) -> Color {
        switch s {
        case .under:      return Color.orange
        case .productive: return Palette.positive
        case .high:       return Color.yellow
        case .over:       return Palette.negative
        }
    }
    private func volStatusLabel(_ s: ScienceEngine.VolumeStatus) -> String {
        switch s {
        case .under:      return "az"
        case .productive: return "verimli"
        case .high:       return "yüksek"
        case .over:       return "fazla"
        }
    }

    // MARK: - Güç ilerlemesi kartı

    private var strengthCard: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: 8) {
                Text("GÜÇ İLERLEMESİ (e1RM)")
                    .font(Typography.label).tracking(0.6)
                    .foregroundStyle(Palette.textTertiary)
                Spacer()
                Text("son 90 gün")
                    .font(Typography.label).foregroundStyle(Palette.textTertiary)
            }

            let deloadLifts = lifts.filter { $0.suggestsDeload }
            if !deloadLifts.isEmpty {
                deloadBanner(deloadLifts)
            }

            VStack(spacing: 8) {
                ForEach(lifts.prefix(8)) { liftRow($0) }
            }

            Text("e1RM = ağırlık × (1 + tekrar/30) (Epley). Progressive overload'ın gerçek göstergesi; düşüş + yüksek hacim deload sinyalidir.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    private func liftRow(_ lift: ScienceEngine.LiftProgress) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(lift.name)
                    .font(Typography.bodyBold).foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text("\(lift.sessions) seans · en iyi \(Fmt.num(lift.bestE1RM, digits: 1)) kg")
                    .font(Typography.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(Fmt.num(lift.latestE1RM, digits: 1)) kg")
                    .font(Typography.bodyBold).foregroundStyle(Palette.textPrimary)
                HStack(spacing: 3) {
                    Image(systemName: trendIcon(lift.trend)).font(.system(size: 9, weight: .bold))
                    Text("\(Fmt.signed(lift.changePercent, digits: 1))%")
                        .font(Typography.caption)
                }
                .foregroundStyle(trendColor(lift.trend))
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.surfaceElevated))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
    }

    private func deloadBanner(_ lifts: [ScienceEngine.LiftProgress]) -> some View {
        let names = lifts.prefix(3).map(\.name).joined(separator: ", ")
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: "battery.25percent")
                .font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.orange).padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text("Deload düşünülebilir")
                    .font(Typography.bodyBold).foregroundStyle(Palette.textPrimary)
                Text("\(names) e1RM'i düşüşte. Birikmiş yorgunluk olabilir — 1 haftalık deload (hacmi ~%40-50 azalt, yoğunluğu koru) toparlanmayı hızlandırır.")
                    .font(Typography.caption).foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Color.orange.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Color.orange.opacity(0.22), lineWidth: 0.5))
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

    // MARK: - Tone helpers

    private func toneColor(_ t: ScienceEngine.RateTone) -> Color {
        switch t {
        case .good:    return Palette.positive
        case .warn:    return Color.orange
        case .bad:     return Palette.negative
        case .neutral: return Palette.textSecondary
        }
    }
    private func toneIcon(_ t: ScienceEngine.RateTone) -> String {
        switch t {
        case .good:    return "checkmark.seal.fill"
        case .warn:    return "exclamationmark.triangle.fill"
        case .bad:     return "exclamationmark.octagon.fill"
        case .neutral: return "equal.circle.fill"
        }
    }
}
