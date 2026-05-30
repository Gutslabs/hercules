import SwiftUI
import SwiftData

struct WorkoutView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \WorkoutLog.date, order: .reverse) private var logs: [WorkoutLog]
    @Query(sort: \WorkoutSession.weekday) private var templates: [WorkoutSession]
    @Query(sort: \WorkoutPlanOverride.createdAt) private var planOverrides: [WorkoutPlanOverride]
    @Query(sort: \WorkoutProgramArchive.archivedAt, order: .reverse) private var archivedPrograms: [WorkoutProgramArchive]

    @State private var currentMonth: Date = Self.startOfMonth(.now)
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    @State private var editing: WorkoutLog? = nil
    @State private var creatingForDate: Date? = nil
    @State private var creatingPrefill: WorkoutLog? = nil
    @State private var editingProgramSession: WorkoutSession? = nil
    @State private var showingArchives = false
    @State private var highlightedProgramWeekday: Int? = nil

    /// Exact log dict: startOfDay → log (her gün için doğrudan kayıt).
    private var exactLogByDay: [Date: WorkoutLog] {
        let cal = Calendar.current
        var dict: [Date: WorkoutLog] = [:]
        for log in logs {
            let key = cal.startOfDay(for: log.date)
            // logs DESC sıralı → ilki o günün en yenisi
            if dict[key] == nil { dict[key] = log }
        }
        return dict
    }

    /// Template dict: weekday (1-7) → o weekday'in en SON log'u.
    /// Recurring workouts buradan beslenir (haftalık template).
    private var templateLogByWeekday: [Int: WorkoutLog] {
        let cal = Calendar.current
        var dict: [Int: WorkoutLog] = [:]
        // logs DESC sıralı → ilk gördüğümüz weekday en yenisidir
        for log in logs {
            let wd = cal.component(.weekday, from: log.date)
            if dict[wd] == nil { dict[wd] = log }
        }
        return dict
    }

    private func overrides(for day: Date) -> [WorkoutPlanOverride] {
        let weekday = Calendar.current.component(.weekday, from: day)
        return planOverrides.filter { $0.weekday == weekday }
    }

    /// Tek bir tarih için "etkin" antrenmanı O(1) lookup ile döndür.
    private func effectiveLog(
        for day: Date,
        exact: [Date: WorkoutLog],
        templates: [Int: WorkoutLog]
    ) -> (log: WorkoutLog?, isTemplate: Bool) {
        let cal = Calendar.current
        let dayKey = cal.startOfDay(for: day)
        if let direct = exact[dayKey] { return (direct, false) }
        let wd = cal.component(.weekday, from: day)
        if let tpl = templates[wd], cal.startOfDay(for: tpl.date) < dayKey {
            return (tpl, true)
        }
        return (nil, false)
    }

    var body: some View {
        // Tüm subviews tek dict precompute'unu paylaşır — render başına 1 scan.
        let exact = exactLogByDay
        let tplsByWeekday = templateLogByWeekday
        return GeometryReader { geometry in
            let contentWidth = geometry.size.width
            let compact = contentWidth < 980
            let expansive = contentWidth >= 1500

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: compact ? Spacing.lg : Spacing.xl) {
                        header(compact: compact)
                        workoutCalendarSection(exact: exact, templatesByWeekday: tplsByWeekday) { date in
                            focusProgramDay(for: date, proxy: proxy)
                        }
                        activeProgramSection(compact: compact, expansive: expansive)
                            .id("active-program")
                        workoutTermsSection(compact: compact)
                        statsStrip(exact: exact, templatesByWeekday: tplsByWeekday, compact: compact)
                        Spacer(minLength: 24)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, compact ? Spacing.lg : (expansive ? 44 : Spacing.xxl))
                    .padding(.vertical, compact ? Spacing.lg : Spacing.xxl)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    let eff = effectiveLog(for: selectedDay)
                    if let exact = eff.log, !eff.isTemplate {
                        editing = exact
                    } else {
                        creatingForDate = selectedDay
                        creatingPrefill = eff.log  // template log varsa prefill
                    }
                } label: {
                    Label("Yeni Seans", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Bu güne antrenman ekle (⌘N) — kayıt varsa düzenle, yoksa template'ten oluştur")
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .sheet(item: $editing) { log in
            WorkoutLogEditor(mode: .edit(log)) { _ in
                try? ctx.save()
            } onDelete: {
                ctx.delete(log)
                try? ctx.save()
            }
        }
        .sheet(item: Binding(
            get: { creatingForDate.map { CreateDate(date: $0) } },
            set: {
                creatingForDate = $0?.date
                if $0 == nil { creatingPrefill = nil }
            }
        )) { wrap in
            WorkoutLogEditor(
                mode: .create(
                    date: wrap.date,
                    suggestedName: creatingPrefill?.name ?? suggestedName(for: wrap.date),
                    prefillFrom: creatingPrefill,
                    planOverrides: overrides(for: wrap.date)
                )
            ) { log in
                ctx.insert(log)
                try? ctx.save()
            }
        }
        .sheet(item: $editingProgramSession) { session in
            WorkoutProgramSessionEditor(session: session) {
                try? ctx.save()
                editingProgramSession = nil
            }
        }
        .sheet(isPresented: $showingArchives) {
            WorkoutProgramArchiveSheet(
                archives: archivedPrograms,
                onRestore: restoreArchivedProgram,
                onDelete: { archive in
                    ctx.delete(archive)
                    try? ctx.save()
                }
            )
        }
    }

    // MARK: Header

    private func header(compact: Bool) -> some View {
        Group {
            if compact {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    headerCopy(maxTextWidth: nil)
                    headerSignals(compact: true)
                }
            } else {
                HStack(alignment: .bottom, spacing: Spacing.xxxl) {
                    headerCopy(maxTextWidth: 560)
                    Spacer(minLength: Spacing.xxxl)
                    headerSignals(compact: false)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerCopy(maxTextWidth: CGFloat?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Antrenman").eyebrow()
            Text("Seans Takvimi")
                .font(Typography.display(42))
                .foregroundStyle(Palette.textPrimary)
            Text("Günlük log, aktif program ve teknik notlar tek yerde. Takvimden güne dokun, program kartına ak.")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: maxTextWidth, alignment: .leading)
        }
    }

    private func headerSignals(compact: Bool) -> some View {
        HStack(spacing: 0) {
            WorkoutHeaderSignal(
                icon: "calendar",
                label: "Bu ay",
                value: "\(logsInCurrentMonth.count)",
                detail: "seans"
            )
            WorkoutHeaderDivider()
            WorkoutHeaderSignal(
                icon: "list.clipboard",
                label: "Aktif",
                value: "\(activeProgramWeekdays.count)",
                detail: "gün"
            )
            WorkoutHeaderDivider()
            WorkoutHeaderSignal(
                icon: "archivebox",
                label: "Arşiv",
                value: "\(archivedPrograms.count)",
                detail: "plan"
            )
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.md)
        .frame(maxWidth: compact ? .infinity : 430, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.6)
        )
    }

    private func workoutCalendarSection(
        exact: [Date: WorkoutLog],
        templatesByWeekday: [Int: WorkoutLog],
        onSelectProgramDay: @escaping (Date) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            monthNavBar
            calendarGrid(exact: exact, templatesByWeekday: templatesByWeekday, onSelectProgramDay: onSelectProgramDay)
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Palette.surface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.6)
        )
    }

    private func activeProgramSection(compact: Bool, expansive: Bool) -> some View {
        let programWeekdays = activeProgramWeekdays
        let activeDays = programWeekdays.compactMap { weekday in templates.first(where: { $0.weekday == weekday }) }
        let totalExercises = activeDays.reduce(0) { $0 + $1.templateExercises.count }
        let totalMinutes = activeDays.reduce(0) { $0 + $1.durationMinutes }
        let totalCalories = activeDays.reduce(0) { $0 + $1.estimatedCalories }
        let maxColumns = compact ? 1 : (expansive ? 3 : 2)
        let columnCount = max(1, min(programWeekdays.count, maxColumns))
        let columns = Array(
            repeating: GridItem(.flexible(minimum: compact ? 240 : 280), spacing: Spacing.md, alignment: .top),
            count: columnCount
        )

        return VStack(alignment: .leading, spacing: Spacing.lg) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: Spacing.md) {
                    activeProgramTitle(
                        dayCount: programWeekdays.count,
                        exerciseCount: totalExercises + planOverrides.count,
                        totalMinutes: totalMinutes
                    )

                    Spacer()

                    activeProgramSummary(totalMinutes: totalMinutes, totalCalories: totalCalories)
                    activeProgramActions(hasProgram: !programWeekdays.isEmpty)
                }

                VStack(alignment: .leading, spacing: Spacing.md) {
                    activeProgramTitle(
                        dayCount: programWeekdays.count,
                        exerciseCount: totalExercises + planOverrides.count,
                        totalMinutes: totalMinutes
                    )
                    HStack(alignment: .center, spacing: Spacing.md) {
                        activeProgramSummary(totalMinutes: totalMinutes, totalCalories: totalCalories)
                        Spacer(minLength: Spacing.md)
                        activeProgramActions(hasProgram: !programWeekdays.isEmpty)
                    }
                }
            }

            if programWeekdays.isEmpty {
                Text("Aktif program yok. AI'dan yeni program yazmasını isteyebilir veya bir güne plan ekleyebilirsin.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(Palette.surfaceElevated.opacity(0.45))
                    )
            } else {
                LazyVGrid(columns: columns, spacing: Spacing.md) {
                    ForEach(programWeekdays, id: \.self) { weekday in
                        WorkoutProgramDayCard(
                            weekday: weekday,
                            session: templates.first(where: { $0.weekday == weekday }),
                            legacyOverrides: planOverrides.filter { $0.weekday == weekday },
                            isHighlighted: highlightedProgramWeekday == weekday
                        ) {
                            editProgramSession(weekday)
                        } onDelete: { session in
                            ctx.delete(session)
                            try? ctx.save()
                        }
                        .id("program-day-\(weekday)")
                    }
                }
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Palette.surface.opacity(0.74))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.6)
        )
    }

    private func activeProgramTitle(dayCount: Int, exerciseCount: Int, totalMinutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Aktif Program").eyebrow()
            Text("Haftalık reçete")
                .font(Typography.title)
                .foregroundStyle(Palette.textPrimary)
            Text("\(dayCount) gün · \(exerciseCount) hareket · \(totalMinutes) dk/hafta")
                .font(Typography.caption)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private func activeProgramSummary(totalMinutes: Int, totalCalories: Double) -> some View {
        HStack(spacing: 0) {
            ProgramSummaryDatum(label: "Süre", value: "\(totalMinutes)", unit: "dk")
            WorkoutHeaderDivider(height: 30)
            ProgramSummaryDatum(label: "Yakım", value: "\(Fmt.int(totalCalories))", unit: "kcal")
            WorkoutHeaderDivider(height: 30)
            ProgramSummaryDatum(label: "AI", value: "\(planOverrides.count)", unit: "ekleme")
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surfaceElevated.opacity(0.46))
        )
    }

    private func activeProgramActions(hasProgram: Bool) -> some View {
        HStack(spacing: Spacing.sm) {
            Button {
                archiveActiveProgram()
            } label: {
                Label("Arşivle", systemImage: "archivebox")
            }
            .buttonStyle(WorkoutMiniButtonStyle())
            .disabled(!hasProgram)

            Button {
                showingArchives = true
            } label: {
                Label("Arşiv", systemImage: "clock.arrow.circlepath")
            }
            .buttonStyle(WorkoutMiniButtonStyle())
            .disabled(archivedPrograms.isEmpty)
        }
    }

    private var activeProgramWeekdays: [Int] {
        var weekdays = Set(templates.filter(isVisibleProgramSession).map(\.weekday))
        for override in planOverrides {
            weekdays.insert(override.weekday)
        }
        return Self.orderedWeekdays.filter { weekdays.contains($0) }
    }

    private func isVisibleProgramSession(_ session: WorkoutSession) -> Bool {
        let defaultName = WorkoutSession.weekdayNames.indices.contains(session.weekday) ? WorkoutSession.weekdayNames[session.weekday] : ""
        return !session.sortedTemplateExercises.isEmpty
            || session.estimatedCalories > 0
            || session.name.trimmingCharacters(in: .whitespacesAndNewlines) != defaultName
            || hasText(session.focus)
            || hasText(session.warmup)
            || hasText(session.progression)
            || hasText(session.notes)
    }

    private func hasText(_ value: String?) -> Bool {
        guard let value else { return false }
        return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func focusProgramDay(for date: Date, proxy: ScrollViewProxy) {
        let weekday = Calendar.current.component(.weekday, from: date)
        guard activeProgramWeekdays.contains(weekday) else { return }
        highlightedProgramWeekday = weekday
        withAnimation(.easeInOut(duration: 0.35)) {
            proxy.scrollTo("program-day-\(weekday)", anchor: .center)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            guard highlightedProgramWeekday == weekday else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                highlightedProgramWeekday = nil
            }
        }
    }

    private func workoutTermsSection(compact: Bool) -> some View {
        let gridMinimum: CGFloat = compact ? 230 : 280

        return VStack(alignment: .leading, spacing: Spacing.lg) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Terimler").eyebrow()
                    Text("Programı okuma sözlüğü")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                Text("AI plan yazarken aynı dili kullansın diye kısa referans.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: gridMinimum), spacing: Spacing.md)
            ], spacing: Spacing.md) {
                WorkoutTermCard(term: "RIR", detail: "Reps in reserve. Set bitince tankta kaç temiz tekrar kaldı demek. RIR 2 = iki tekrar daha çıkarırdın.")
                WorkoutTermCard(term: "4×6-10", detail: "4 set yap. Her sette hedef tekrar aralığı 6 ile 10. Tüm setlerde üst banda yaklaşırsan ağırlık artır.")
                WorkoutTermCard(term: "Rest 2-3 dk", detail: "Setler arası dinlenme. Ana liftlerde performans düşmesin diye daha uzun, izolasyonda daha kısa olabilir.")
                WorkoutTermCard(term: "Progression", detail: "Zamanla yük, tekrar, set veya teknik kalite artırma planı. Programın gelişim kuralı burada yazıyor.")
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Palette.surface.opacity(0.68))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.55)
        )
    }

    private func editProgramSession(_ weekday: Int) {
        if let existing = templates.first(where: { $0.weekday == weekday }) {
            editingProgramSession = existing
            return
        }
        let created = WorkoutSession(
            weekday: weekday,
            name: WorkoutSession.weekdayName(weekday),
            estimatedCalories: 0,
            durationMinutes: 60
        )
        ctx.insert(created)
        try? ctx.save()
        editingProgramSession = created
    }

    private func archiveActiveProgram() {
        let snapshots = activeProgramSnapshots()
        guard !snapshots.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshots),
              let json = String(data: data, encoding: .utf8)
        else { return }
        let title = "Program \(Self.archiveDateFormatter.string(from: .now))"
        ctx.insert(WorkoutProgramArchive(
            title: title,
            summary: "\(snapshots.count) gün · \(snapshots.reduce(0) { $0 + $1.exercises.count }) hareket",
            notes: "Manuel arşiv",
            source: "manual",
            sessionsJSON: json
        ))
        try? ctx.save()
    }

    private func activeProgramSnapshots() -> [WorkoutProgramSessionSnapshot] {
        var snapshots = templates.sorted { $0.weekday < $1.weekday }.map(\.snapshot)
        for override in planOverrides.sorted(by: { $0.createdAt < $1.createdAt }) {
            let exercise = WorkoutTemplateExerciseSnapshot(
                name: override.exerciseName,
                order: snapshots.first(where: { $0.weekday == override.weekday })?.exercises.count ?? 0,
                sets: override.sets,
                reps: override.reps.map(String.init),
                load: formatLoad(override.weight),
                rir: nil,
                rest: nil,
                sourceURL: nil,
                notes: override.note
            )
            if let idx = snapshots.firstIndex(where: { $0.weekday == override.weekday }) {
                snapshots[idx].exercises.append(exercise)
            } else {
                snapshots.append(WorkoutProgramSessionSnapshot(
                    weekday: override.weekday,
                    name: WorkoutSession.weekdayNames.indices.contains(override.weekday) ? WorkoutSession.weekdayNames[override.weekday] : "Antrenman",
                    estimatedCalories: 0,
                    durationMinutes: 60,
                    focus: "Eski AI eklemesi",
                    warmup: nil,
                    progression: nil,
                    notes: override.note,
                    exercises: [exercise]
                ))
            }
        }
        return snapshots.sorted { $0.weekday < $1.weekday }
    }

    private func restoreArchivedProgram(_ archive: WorkoutProgramArchive) {
        for session in templates {
            ctx.delete(session)
        }
        for override in planOverrides {
            ctx.delete(override)
        }
        for snapshot in archive.sessions {
            let session = WorkoutSession(
                weekday: snapshot.weekday,
                name: snapshot.name,
                estimatedCalories: snapshot.estimatedCalories,
                durationMinutes: snapshot.durationMinutes,
                focus: snapshot.focus,
                warmup: snapshot.warmup,
                progression: snapshot.progression,
                notes: snapshot.notes
            )
            ctx.insert(session)
            for exerciseSnapshot in snapshot.exercises.sorted(by: { $0.order < $1.order }) {
                let exercise = WorkoutTemplateExercise(
                    name: exerciseSnapshot.name,
                    order: exerciseSnapshot.order,
                    sets: exerciseSnapshot.sets,
                    reps: exerciseSnapshot.reps,
                    load: exerciseSnapshot.load,
                    rir: exerciseSnapshot.rir,
                    rest: exerciseSnapshot.rest,
                    sourceURL: exerciseSnapshot.sourceURL,
                    notes: exerciseSnapshot.notes
                )
                ctx.insert(exercise)
                session.templateExercises.append(exercise)
            }
        }
        try? ctx.save()
        showingArchives = false
    }

    private func formatLoad(_ weight: Double?) -> String? {
        guard let weight else { return nil }
        return weight == weight.rounded() ? "@ \(Int(weight)) kg" : "@ \(String(format: "%.1f", weight)) kg"
    }

    // MARK: Stats strip

    private func statsStrip(
        exact: [Date: WorkoutLog],
        templatesByWeekday: [Int: WorkoutLog],
        compact: Bool
    ) -> some View {
        let cal = Calendar.current
        let now = Date()
        var weekCal = cal
        weekCal.firstWeekday = 2
        let weekStart = weekCal.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let weekEnd = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now)) ?? now
        let monthStart = cal.dateInterval(of: .month, for: now)?.start ?? now
        let thirtyAgo = cal.date(byAdding: .day, value: -30, to: now) ?? now

        // Tek pass — son 30 günü dolaş, week/month range içine düşenleri ayrı topla.
        var weekSessions = 0, weekMin = 0
        var weekKcal: Double = 0
        var monthSessions = 0, monthMin = 0
        var last30Sess = 0

        var date = cal.startOfDay(for: thirtyAgo)
        while date < weekEnd {
            let eff = effectiveLog(for: date, exact: exact, templates: templatesByWeekday)
            if let log = eff.log {
                last30Sess += 1
                if date >= weekStart {
                    weekSessions += 1
                    weekMin += log.durationMinutes
                    weekKcal += log.estimatedCalories
                }
                if date >= monthStart {
                    monthSessions += 1
                    monthMin += log.durationMinutes
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: date) else { break }
            date = next
        }

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tempo").eyebrow()
                    Text("Gerçek seans ritmi")
                        .font(Typography.titleSmall)
                        .foregroundStyle(Palette.textPrimary)
                }
                Spacer()
                Text(String(format: "son 30 gün %.1f seans/hafta", Double(last30Sess) / (30.0 / 7.0)))
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }

            Hairline()

            if compact {
                VStack(spacing: Spacing.md) {
                    statDatum(
                        eyebrow: "Bu Hafta",
                        primary: "\(weekSessions)",
                        unit: "seans",
                        secondary: "\(weekMin) dk · \(Fmt.int(weekKcal)) kcal"
                    )
                    Hairline()
                    statDatum(
                        eyebrow: "Bu Ay",
                        primary: "\(monthSessions)",
                        unit: "seans",
                        secondary: "\(monthMin) dk ay başından beri"
                    )
                    Hairline()
                    statDatum(
                        eyebrow: "Son 30 Gün",
                        primary: "\(last30Sess)",
                        unit: "seans",
                        secondary: String(format: "%.1f /hafta", Double(last30Sess) / (30.0 / 7.0))
                    )
                    Hairline()
                    statDatum(
                        eyebrow: "Kayıt",
                        primary: "\(logs.count)",
                        unit: "log",
                        secondary: "\(uniqueWeekdaysWithLog) gün/hafta temeli"
                    )
                }
            } else {
                HStack(spacing: 0) {
                    statDatum(
                        eyebrow: "Bu Hafta",
                        primary: "\(weekSessions)",
                        unit: "seans",
                        secondary: "\(weekMin) dk · \(Fmt.int(weekKcal)) kcal"
                    )
                    WorkoutHeaderDivider(height: 42)
                    statDatum(
                        eyebrow: "Bu Ay",
                        primary: "\(monthSessions)",
                        unit: "seans",
                        secondary: "\(monthMin) dk ay başından beri"
                    )
                    WorkoutHeaderDivider(height: 42)
                    statDatum(
                        eyebrow: "Son 30 Gün",
                        primary: "\(last30Sess)",
                        unit: "seans",
                        secondary: String(format: "%.1f /hafta", Double(last30Sess) / (30.0 / 7.0))
                    )
                    WorkoutHeaderDivider(height: 42)
                    statDatum(
                        eyebrow: "Kayıt",
                        primary: "\(logs.count)",
                        unit: "log",
                        secondary: "\(uniqueWeekdaysWithLog) gün/hafta temeli"
                    )
                }
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Palette.surface.opacity(0.68))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .strokeBorder(Palette.borderStrong, lineWidth: 0.55)
        )
    }

    /// Haftanın kaç farklı gününde bir log var (template tabanı = haftalık tempo).
    private var uniqueWeekdaysWithLog: Int {
        let cal = Calendar.current
        let weekdays = Set(logs.map { cal.component(.weekday, from: $0.date) })
        return weekdays.count
    }

    private func statDatum(eyebrow: String, primary: String, unit: String, secondary: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased()).eyebrow()
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(primary)
                    .font(Typography.hero(24))
                    .foregroundStyle(Palette.textPrimary)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: primary)
                Text(unit)
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textSecondary)
            }
            Text(secondary)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Month nav

    private var monthNavBar: some View {
        HStack(spacing: Spacing.md) {
            navButton(icon: "chevron.left") { jumpMonth(by: -1) }
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.monthTitleFormatter.string(from: currentMonth))
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                Text("\(logsInCurrentMonth.count) seans bu ay")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            navButton(icon: "chevron.right") { jumpMonth(by: 1) }

            Spacer()

            Button {
                let today = Calendar.current.startOfDay(for: .now)
                currentMonth = Self.startOfMonth(.now)
                selectedDay = today
            } label: {
                Label("Bugün", systemImage: "scope")
            }
            .buttonStyle(WorkoutMiniButtonStyle())
        }
    }

    private func navButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: 0.5)
                )
        }
        .buttonStyle(WorkoutIconButtonStyle())
    }

    // MARK: Grid

    private func calendarGrid(
        exact: [Date: WorkoutLog],
        templatesByWeekday: [Int: WorkoutLog],
        onSelectProgramDay: @escaping (Date) -> Void
    ) -> some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
        let cal = Calendar.current
        return VStack(spacing: 6) {
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(Self.weekdayHeaders, id: \.self) { wd in
                    Text(wd)
                        .font(Typography.label)
                        .tracking(0.8)
                        .foregroundStyle(Palette.textQuaternary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(monthGridDays(), id: \.self) { date in
                    let eff = effectiveLog(for: date, exact: exact, templates: templatesByWeekday)
                    WorkoutDayCell(
                        date: date,
                        inMonth: cal.isDate(date, equalTo: currentMonth, toGranularity: .month),
                        isToday: cal.isDateInToday(date),
                        isSelected: cal.isDate(date, inSameDayAs: selectedDay),
                        log: eff.log,
                        isTemplate: eff.isTemplate,
                        scheduleHint: templateName(for: date),
                        overrideCount: overrides(for: date).count
                    ) {
                        selectedDay = cal.startOfDay(for: date)
                        if !cal.isDate(date, equalTo: currentMonth, toGranularity: .month) {
                            currentMonth = Self.startOfMonth(date)
                        }
                        onSelectProgramDay(date)
                    }
                }
            }
        }
    }

    // MARK: Selected day detail

    private func selectedDayDetail(
        exact: [Date: WorkoutLog],
        templatesByWeekday: [Int: WorkoutLog]
    ) -> some View {
        let eff = effectiveLog(for: selectedDay, exact: exact, templates: templatesByWeekday)
        let dayOverrides = overrides(for: selectedDay)
        let plannedSession = programSession(for: selectedDay)
        return Card(padding: Spacing.lg) {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack(alignment: .firstTextBaseline) {
                    Text(Self.fullDayFormatter.string(from: selectedDay))
                        .font(Typography.title)
                        .foregroundStyle(Palette.textPrimary)
                    if Calendar.current.isDateInToday(selectedDay) {
                        PillTag(text: "Bugün", tint: Palette.accent)
                    }
                    if eff.isTemplate {
                        PillTag(text: "Plan", tint: Palette.textSecondary)
                    }
                    Spacer()
                    if let l = eff.log {
                        Text("\(l.durationMinutes) dk · \(Fmt.int(l.estimatedCalories)) kcal")
                            .font(Typography.mono)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }

                if let log = eff.log {
                    HStack(spacing: 6) {
                        Image(systemName: eff.isTemplate ? "repeat" : "dumbbell.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(eff.isTemplate ? Palette.textSecondary : Palette.accent)
                        Text(log.name.isEmpty ? "İsimsiz Antrenman" : log.name)
                            .font(Typography.bodyBold)
                            .foregroundStyle(Palette.textPrimary)
                        Spacer()
                        if eff.isTemplate {
                            Button {
                                // Template'i bu güne özel olarak değiştir → yeni log (prefilled)
                                creatingForDate = selectedDay
                                creatingPrefill = log
                            } label: {
                                Label("Bu güne özel düzenle", systemImage: "pencil")
                                    .font(Typography.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else {
                            Button { editing = log } label: {
                                Label("Düzenle", systemImage: "pencil")
                                    .font(Typography.caption)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    if eff.isTemplate {
                        HStack(spacing: 5) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 9))
                            Text("Bu, son \(weekdayName(of: selectedDay)) antrenmanından kopyalandı. Aynısını yapacaksan ekstra giriş gerekmiyor.")
                                .font(Typography.caption)
                        }
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.vertical, 4)
                    }

                    if !log.exercises.isEmpty {
                        Hairline()
                        let sorted = log.exercises.sorted { $0.order < $1.order }
                        VStack(spacing: 6) {
                            // enumerated → index'i lookup yerine doğrudan al (force-unwrap yok)
                            ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, ex in
                                HStack(spacing: Spacing.md) {
                                    Text("\(idx + 1).")
                                        .font(Typography.mono)
                                        .foregroundStyle(Palette.textQuaternary)
                                        .frame(width: 20, alignment: .leading)
                                    Text(ex.name)
                                        .font(Typography.body)
                                        .foregroundStyle(Palette.textPrimary)
                                    Spacer()
                                    Text(ex.summary)
                                        .font(Typography.mono)
                                        .foregroundStyle(Palette.textSecondary)
                                }
                            }
                        }
                    }

                    if !dayOverrides.isEmpty {
                        Hairline()
                        overrideExercises(dayOverrides)
                    }

                    if let note = log.notes, !note.isEmpty {
                        Hairline()
                        Text(note)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else if let plannedSession {
                    HStack(spacing: 6) {
                        Image(systemName: "list.clipboard")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.accent)
                        Text(plannedSession.name)
                            .font(Typography.bodyBold)
                            .foregroundStyle(Palette.textPrimary)
                        Spacer()
                        Button {
                            editProgramSession(plannedSession.weekday)
                        } label: {
                            Label("Programı düzenle", systemImage: "pencil")
                                .font(Typography.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        Button {
                            creatingForDate = selectedDay
                            creatingPrefill = nil
                        } label: {
                            Label("Seans ekle", systemImage: "plus")
                                .font(Typography.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if let focus = plannedSession.focus, !focus.isEmpty {
                        Text(focus)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    let exercises = plannedSession.sortedTemplateExercises
                    if !exercises.isEmpty {
                        Hairline()
                        VStack(spacing: 6) {
                            ForEach(exercises) { ex in
                                HStack(spacing: Spacing.md) {
                                    Text("\(ex.order + 1).")
                                        .font(Typography.mono)
                                        .foregroundStyle(Palette.textQuaternary)
                                        .frame(width: 20, alignment: .leading)
                                    Text(ex.name)
                                        .font(Typography.body)
                                        .foregroundStyle(Palette.textPrimary)
                                    Spacer()
                                    Text(ex.prescriptionText)
                                        .font(Typography.mono)
                                        .foregroundStyle(Palette.textSecondary)
                                }
                            }
                        }
                    }
                    if let progression = plannedSession.progression, !progression.isEmpty {
                        Hairline()
                        Text(progression)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: "moon.zzz.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textTertiary)
                        Text("Bu gün için seans yok.")
                            .font(Typography.body)
                            .foregroundStyle(Palette.textTertiary)
                        if let tplName = templateName(for: selectedDay) {
                            Text("(Plan: \(tplName))")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textQuaternary)
                        }
                        Spacer()
                        Button {
                            creatingForDate = selectedDay
                            creatingPrefill = nil
                        } label: {
                            Label("Seans ekle", systemImage: "plus")
                                .font(Typography.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    if !dayOverrides.isEmpty {
                        Hairline()
                        overrideExercises(dayOverrides)
                    }
                }
            }
        }
    }

    private func overrideExercises(_ overrides: [WorkoutPlanOverride]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.positive)
                Text("AI plan eklemeleri")
                    .font(Typography.captionBold)
                    .foregroundStyle(Palette.textSecondary)
            }
            ForEach(overrides) { item in
                HStack(spacing: Spacing.md) {
                    Text("+")
                        .font(Typography.mono)
                        .foregroundStyle(Palette.positive)
                        .frame(width: 20, alignment: .leading)
                    Text(item.exerciseName)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Text(item.prescriptionText)
                        .font(Typography.mono)
                        .foregroundStyle(Palette.textSecondary)
                    Button {
                        ctx.delete(item)
                        try? ctx.save()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .help("AI eklemesini sil")
                }
            }
        }
    }

    private func weekdayName(of date: Date) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        let names = ["", "Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"]
        guard weekday >= 1 && weekday <= 7 else { return "" }
        return names[weekday]
    }

    // MARK: Helpers

    private var logsInCurrentMonth: [WorkoutLog] {
        let cal = Calendar.current
        return logs.filter { cal.isDate($0.date, equalTo: currentMonth, toGranularity: .month) }
    }

    /// Toolbar/aksiyon path için convenience — dict bir kez build edilir, sonra lookup.
    /// Body render yolunda kullanılmamalı (orada body-level dict precompute var).
    private func effectiveLog(for day: Date) -> (log: WorkoutLog?, isTemplate: Bool) {
        effectiveLog(for: day, exact: exactLogByDay, templates: templateLogByWeekday)
    }

    private func templateName(for day: Date) -> String? {
        let weekday = Calendar.current.component(.weekday, from: day)
        return templates.first(where: { $0.weekday == weekday })?.name
    }

    private func programSession(for day: Date) -> WorkoutSession? {
        let weekday = Calendar.current.component(.weekday, from: day)
        return templates.first(where: { $0.weekday == weekday })
    }

    private func suggestedName(for day: Date) -> String {
        templateName(for: day) ?? "Antrenman"
    }

    private func monthGridDays() -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.locale = Locale(identifier: "tr_TR")
        guard let interval = cal.dateInterval(of: .month, for: currentMonth) else { return [] }
        let monthStart = interval.start
        let weekday = cal.component(.weekday, from: monthStart)
        let leadingOffset = (weekday - cal.firstWeekday + 7) % 7
        guard let gridStart = cal.date(byAdding: .day, value: -leadingOffset, to: monthStart) else { return [] }
        return (0..<42).compactMap { cal.date(byAdding: .day, value: $0, to: gridStart) }
    }

    private func jumpMonth(by step: Int) {
        guard let new = Calendar.current.date(byAdding: .month, value: step, to: currentMonth) else { return }
        currentMonth = Self.startOfMonth(new)
    }

    fileprivate static func startOfMonth(_ date: Date) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }

    fileprivate static let weekdayHeaders: [String] = ["PZT", "SAL", "ÇAR", "PER", "CUM", "CMT", "PAZ"]
    fileprivate static let orderedWeekdays: [Int] = [2, 3, 4, 5, 6, 7, 1]

    fileprivate static let monthTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    fileprivate static let fullDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM EEEE"
        return f
    }()

    static let archiveDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM yyyy HH:mm"
        return f
    }()
}
