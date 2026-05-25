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
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    header
                    monthNavBar
                    calendarGrid(exact: exact, templatesByWeekday: tplsByWeekday) { date in
                        focusProgramDay(for: date, proxy: proxy)
                    }
                    activeProgramSection
                        .id("active-program")
                    workoutTermsSection
                    statsStrip(exact: exact, templatesByWeekday: tplsByWeekday)
                    Spacer(minLength: 24)
                }
                .padding(Spacing.xxl)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Antrenman").eyebrow()
            Text("Seans Takvimi")
                .font(Typography.display(40))
                .foregroundStyle(Palette.textPrimary)
            Text("Yaptığın antrenmanları gün gün kaydet, haftalık tempoyu gör.")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
        }
    }

    private var activeProgramSection: some View {
        let programWeekdays = activeProgramWeekdays
        let activeDays = programWeekdays.compactMap { weekday in templates.first(where: { $0.weekday == weekday }) }
        let totalExercises = activeDays.reduce(0) { $0 + $1.templateExercises.count }
        let totalMinutes = activeDays.reduce(0) { $0 + $1.durationMinutes }

        return VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .center, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "list.clipboard")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                        Text("Aktif Program").eyebrow()
                    }
                    Text("\(programWeekdays.count) gün · \(totalExercises + planOverrides.count) hareket · \(totalMinutes) dk/hafta")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                }

                Spacer()

                Button {
                    archiveActiveProgram()
                } label: {
                    Label("Arşivle", systemImage: "archivebox")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(programWeekdays.isEmpty)

                Button {
                    showingArchives = true
                } label: {
                    Label("Arşiv", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(archivedPrograms.isEmpty)
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
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 3), spacing: Spacing.md) {
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
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
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

    private var workoutTermsSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(spacing: 6) {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Text("Terimler").eyebrow()
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Spacing.md), count: 4), spacing: Spacing.md) {
                WorkoutTermCard(term: "RIR", detail: "Reps in reserve. Set bitince tankta kaç temiz tekrar kaldı demek. RIR 2 = iki tekrar daha çıkarırdın.")
                WorkoutTermCard(term: "4×6-10", detail: "4 set yap. Her sette hedef tekrar aralığı 6 ile 10. Tüm setlerde üst banda yaklaşırsan ağırlık artır.")
                WorkoutTermCard(term: "Rest 2-3 dk", detail: "Setler arası dinlenme. Ana liftlerde performans düşmesin diye daha uzun, izolasyonda daha kısa olabilir.")
                WorkoutTermCard(term: "Progression", detail: "Zamanla yük, tekrar, set veya teknik kalite artırma planı. Programın gelişim kuralı burada yazıyor.")
            }
        }
        .padding(Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }

    private func editProgramSession(_ weekday: Int) {
        if let existing = templates.first(where: { $0.weekday == weekday }) {
            editingProgramSession = existing
            return
        }
        let created = WorkoutSession(
            weekday: weekday,
            name: WorkoutSession.weekdayNames[weekday],
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
        templatesByWeekday: [Int: WorkoutLog]
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

        return HStack(spacing: Spacing.md) {
            statCard(
                eyebrow: "Bu Hafta",
                primary: "\(weekSessions) seans",
                secondaryLeft: "\(weekMin) dk",
                detail: "\(Fmt.int(weekKcal)) kcal yakım"
            )
            statCard(
                eyebrow: "Bu Ay",
                primary: "\(monthSessions) seans",
                secondaryLeft: "\(monthMin) dk",
                detail: "ay başından beri"
            )
            statCard(
                eyebrow: "Son 30 Gün",
                primary: "\(last30Sess) seans",
                secondaryLeft: String(format: "%.1f /hafta", Double(last30Sess) / (30.0 / 7.0)),
                detail: "ortalama frekans"
            )
            statCard(
                eyebrow: "Kayıt",
                primary: "\(logs.count) log",
                secondaryLeft: "\(uniqueWeekdaysWithLog) gün/hafta",
                detail: "template tabanı"
            )
        }
    }

    /// Haftanın kaç farklı gününde bir log var (template tabanı = haftalık tempo).
    private var uniqueWeekdaysWithLog: Int {
        let cal = Calendar.current
        let weekdays = Set(logs.map { cal.component(.weekday, from: $0.date) })
        return weekdays.count
    }

    private func statCard(eyebrow: String, primary: String, secondaryLeft: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eyebrow.uppercased()).eyebrow()
            Text(primary)
                .font(Typography.hero(20))
                .foregroundStyle(Palette.textPrimary)
                .contentTransition(.numericText())
                .animation(.snappy, value: primary)
            Text(secondaryLeft)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.textQuaternary)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
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
                Text("Bugün")
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .fill(Palette.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
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
        .buttonStyle(.plain)
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

    fileprivate static let archiveDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM yyyy HH:mm"
        return f
    }()
}

private struct CreateDate: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}

// MARK: - Active program board

private struct WorkoutTermCard: View {
    let term: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(term)
                .font(Typography.bodyBold)
                .foregroundStyle(Palette.textPrimary)
            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surfaceElevated.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }
}

private struct WorkoutProgramDayCard: View {
    let weekday: Int
    let session: WorkoutSession?
    let legacyOverrides: [WorkoutPlanOverride]
    let isHighlighted: Bool
    var onEdit: () -> Void
    var onDelete: (WorkoutSession) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(WorkoutSession.weekdayNames[weekday])
                        .font(Typography.bodyBold)
                        .foregroundStyle(session == nil ? Palette.textTertiary : Palette.textPrimary)
                    Text(session?.name ?? "Serbest / Dinlenme")
                        .font(Typography.caption)
                        .foregroundStyle(session == nil ? Palette.textQuaternary : Palette.textSecondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: onEdit) {
                    Image(systemName: session == nil ? "plus" : "pencil")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Palette.surfaceElevated))
                }
                .buttonStyle(.plain)
                .help(session == nil ? "Güne plan ekle" : "Planı düzenle")
                if let session {
                    Button {
                        onDelete(session)
                    } label: {
                        Image(systemName: "archivebox")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Palette.textTertiary)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(Palette.surfaceElevated))
                    }
                    .buttonStyle(.plain)
                    .help("Bu günü aktif plandan kaldır")
                    .opacity(hovering ? 1 : 0.2)
                }
            }

            if let session {
                HStack(spacing: 6) {
                    smallMetric("\(session.durationMinutes) dk")
                    smallMetric("\(session.sortedTemplateExercises.count) hareket")
                    if session.estimatedCalories > 0 {
                        smallMetric("\(Fmt.int(session.estimatedCalories)) kcal")
                    }
                }

                if let focus = session.focus, !focus.isEmpty {
                    Text(focus)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                let exercises = session.sortedTemplateExercises
                if !exercises.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(exercises) { exercise in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("\(exercise.order + 1).")
                                        .font(Typography.mono)
                                        .foregroundStyle(Palette.textQuaternary)
                                        .frame(width: 20, alignment: .leading)
                                    Text(exercise.name)
                                        .font(Typography.captionBold)
                                        .foregroundStyle(Palette.textPrimary)
                                        .lineLimit(1)
                                    if let sourceURL = exercise.sourceURL,
                                       let url = URL(string: sourceURL) {
                                        Link(destination: url) {
                                            Image(systemName: "link")
                                                .font(.system(size: 9, weight: .bold))
                                                .foregroundStyle(Palette.textTertiary)
                                                .frame(width: 18, height: 18)
                                                .background(Circle().fill(Color.white.opacity(0.05)))
                                        }
                                        .buttonStyle(.plain)
                                        .help("Hareket kaynağını aç")
                                    }
                                    Spacer(minLength: 0)
                                }
                                Text(exercise.prescriptionText)
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.textTertiary)
                                    .lineLimit(2)
                                    .padding(.leading, 26)
                            }
                        }
                    }
                } else {
                    emptyLine("Hareket reçetesi yok")
                }

                if let progression = session.progression, !progression.isEmpty {
                    Hairline()
                    labelBlock("Progression", progression)
                }
            } else if !legacyOverrides.isEmpty {
                labelBlock("Eski AI eklemeleri", legacyOverrides.map { "+ \($0.exerciseName) · \($0.prescriptionText)" }.joined(separator: "\n"))
            } else {
                Spacer(minLength: 10)
                emptyLine("Plan yok")
            }
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 260, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(isHighlighted ? Palette.accent.opacity(0.12) : (hovering ? Palette.surfaceElevated.opacity(0.7) : Palette.surfaceElevated.opacity(0.52)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(isHighlighted ? Palette.accent.opacity(0.95) : Palette.border, lineWidth: isHighlighted ? 1.2 : 0.5)
        )
        .shadow(color: isHighlighted ? Palette.accent.opacity(0.18) : .clear, radius: 18, x: 0, y: 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .onHover { hovering = $0 }
    }

    private func smallMetric(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.055)))
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Palette.textQuaternary)
            .frame(maxWidth: .infinity, minHeight: 68, alignment: .center)
            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Color.white.opacity(0.025)))
    }

    private func labelBlock(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Typography.label)
                .foregroundStyle(Palette.textQuaternary)
            Text(text)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct WorkoutProgramSessionEditor: View {
    @Bindable var session: WorkoutSession
    var onDone: () -> Void
    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var duration = 60
    @State private var calories: Double = 0
    @State private var focus = ""
    @State private var warmup = ""
    @State private var progression = ""
    @State private var notes = ""
    @State private var exercises: [ProgramExerciseDraft] = []

    var body: some View {
        NavigationStack {
            Form {
                Section(WorkoutSession.weekdayNames[session.weekday]) {
                    TextField("Gün adı", text: $name, prompt: Text("Upper A / Lower / Full Body"))
                    LabeledContent("Süre") {
                        TextField("", value: $duration, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                    LabeledContent("Yakım") {
                        TextField("", value: $calories, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 90)
                    }
                }

                Section("Koç Notları") {
                    TextField("Günün amacı", text: $focus, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Isınma", text: $warmup, axis: .vertical)
                        .lineLimit(2...4)
                    TextField("Progression", text: $progression, axis: .vertical)
                        .lineLimit(2...5)
                    TextField("Ek not", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                ForEach(Array(exercises.enumerated()), id: \.element.id) { idx, _ in
                    Section {
                        TextField("Hareket", text: $exercises[idx].name, prompt: Text("Incline Bench Press"))
                        HStack {
                            LabeledContent("Set") {
                                TextField("", value: $exercises[idx].sets, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 64)
                            }
                            LabeledContent("Tekrar") {
                                TextField("6-10", text: $exercises[idx].reps)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 88)
                            }
                            LabeledContent("RIR") {
                                TextField("1-2", text: $exercises[idx].rir)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                            }
                        }
                        TextField("Yük / tempo", text: $exercises[idx].load, prompt: Text("@ 80 kg / kontrollü eccentric"))
                        TextField("Dinlenme", text: $exercises[idx].rest, prompt: Text("2-3 dk"))
                        TextField("Kaynak linki", text: $exercises[idx].sourceURL, prompt: Text("https://exrx.net/..."))
                            .textContentType(.URL)
                        TextField("Not", text: $exercises[idx].notes, axis: .vertical)
                            .lineLimit(1...4)
                        Button(role: .destructive) {
                            exercises.remove(at: idx)
                        } label: {
                            Label("Hareketi Sil", systemImage: "trash")
                        }
                        .buttonStyle(.borderless)
                    } header: {
                        Text(exercises[idx].name.isEmpty ? "Hareket \(idx + 1)" : exercises[idx].name)
                    }
                }

                Section {
                    Button {
                        exercises.append(ProgramExerciseDraft(order: exercises.count))
                    } label: {
                        Label("Hareket Ekle", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Program Günü")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        save()
                        onDone()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 720, height: 760)
        .onAppear(perform: load)
    }

    private func load() {
        name = session.name
        duration = session.durationMinutes
        calories = session.estimatedCalories
        focus = session.focus ?? ""
        warmup = session.warmup ?? ""
        progression = session.progression ?? ""
        notes = session.notes ?? ""
        exercises = session.sortedTemplateExercises.map {
            ProgramExerciseDraft(
                name: $0.name,
                order: $0.order,
                sets: $0.sets,
                reps: $0.reps ?? "",
                load: $0.load ?? "",
                rir: $0.rir ?? "",
                rest: $0.rest ?? "",
                sourceURL: $0.sourceURL ?? "",
                notes: $0.notes ?? ""
            )
        }
    }

    private func save() {
        session.name = clean(name) ?? WorkoutSession.weekdayNames[session.weekday]
        session.durationMinutes = duration
        session.estimatedCalories = calories
        session.focus = clean(focus)
        session.warmup = clean(warmup)
        session.progression = clean(progression)
        session.notes = clean(notes)

        for old in session.templateExercises {
            ctx.delete(old)
        }
        session.templateExercises.removeAll()
        for (idx, draft) in exercises.enumerated() {
            guard let exerciseName = clean(draft.name) else { continue }
            let exercise = WorkoutTemplateExercise(
                name: exerciseName,
                order: idx,
                sets: draft.sets,
                reps: clean(draft.reps),
                load: clean(draft.load),
                rir: clean(draft.rir),
                rest: clean(draft.rest),
                sourceURL: clean(draft.sourceURL),
                notes: clean(draft.notes)
            )
            ctx.insert(exercise)
            session.templateExercises.append(exercise)
        }
    }

    private func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct ProgramExerciseDraft: Identifiable {
    let id = UUID()
    var name: String = ""
    var order: Int = 0
    var sets: Int? = 3
    var reps: String = ""
    var load: String = ""
    var rir: String = ""
    var rest: String = ""
    var sourceURL: String = ""
    var notes: String = ""
}

private struct WorkoutProgramArchiveSheet: View {
    let archives: [WorkoutProgramArchive]
    var onRestore: (WorkoutProgramArchive) -> Void
    var onDelete: (WorkoutProgramArchive) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(archives) { archive in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(archive.title)
                                    .font(Typography.bodyBold)
                                Text(WorkoutView.archiveDateFormatter.string(from: archive.archivedAt))
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            Spacer()
                            Text("\(archive.sessions.count) gün")
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        if let summary = archive.summary, !summary.isEmpty {
                            Text(summary)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                        Text(archive.sessions.map { "\(WorkoutSession.weekdayShort[$0.weekday]) \($0.name)" }.joined(separator: " · "))
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textQuaternary)
                            .lineLimit(2)
                        HStack {
                            Button {
                                onRestore(archive)
                                dismiss()
                            } label: {
                                Label("Geri Yükle", systemImage: "arrow.clockwise")
                            }
                            Button(role: .destructive) {
                                onDelete(archive)
                            } label: {
                                Label("Sil", systemImage: "trash")
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 6)
                }
            }
            .navigationTitle("Program Arşivi")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .frame(width: 560, height: 560)
    }
}

// MARK: - Day cell

private struct WorkoutDayCell: View {
    let date: Date
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    /// Hem exact log hem template log buradan gelir.
    let log: WorkoutLog?
    /// log nil değil ama gerçek bir log değil, başka bir günden alınmış template ise true.
    let isTemplate: Bool
    /// WorkoutSession weekly planındaki isim (her zaman gösterilir, log yoksa).
    let scheduleHint: String?
    let overrideCount: Int
    let onTap: () -> Void
    @State private var hovering = false

    private var dayNumber: String {
        Fmt.dayNumber.string(from: date)
    }

    private var borderColor: Color {
        if isSelected { return Palette.borderStrong }
        if isToday { return Palette.accent.opacity(0.55) }
        return Palette.border
    }

    /// Template-only hücreleri dim gösterilir.
    private var bodyOpacity: Double {
        if !inMonth { return 0.45 }
        if isTemplate { return 0.78 }
        return 1.0
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 6) {
                    Text(dayNumber)
                        .font(Typography.bodyBold)
                        .foregroundStyle(isToday ? Palette.accent : (inMonth ? Palette.textPrimary : Palette.textQuaternary))
                    if isToday {
                        Text("BUGÜN")
                            .font(.system(size: 8.5, weight: .semibold))
                            .tracking(0.6)
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Palette.accent.opacity(0.14)))
                    }
                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)

                if let log {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: isTemplate ? "repeat" : "dumbbell.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(isTemplate ? Palette.textSecondary : Palette.accent)
                            Text(log.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(1)
                        }
                        Text("\(log.exercises.count) hareket · \(log.durationMinutes) dk")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                        if overrideCount > 0 {
                            Text("+\(overrideCount) AI hareket")
                                .font(.system(size: 9))
                                .foregroundStyle(Palette.positive)
                                .lineLimit(1)
                        }
                    }
                } else if let tpl = scheduleHint, inMonth {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tpl)
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textQuaternary)
                            .lineLimit(1)
                        if overrideCount > 0 {
                            Text("+\(overrideCount) AI hareket")
                                .font(.system(size: 9))
                                .foregroundStyle(Palette.positive)
                                .lineLimit(1)
                        }
                    }
                } else if overrideCount > 0, inMonth {
                    Text("+\(overrideCount) AI hareket")
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.positive)
                        .lineLimit(1)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(isSelected ? Palette.surfaceElevated : (hovering ? Palette.surface.opacity(0.7) : Palette.surface))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(
                        borderColor,
                        style: StrokeStyle(
                            lineWidth: isToday && !isSelected ? 1.0 : 0.5,
                            dash: isTemplate && !isSelected ? [3, 2] : []
                        )
                    )
            )
            .opacity(bodyOpacity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Editor sheet

enum WorkoutEditorMode {
    /// `prefillFrom`: template / başka bir günden kopyalanacak log (örn. recurring workout).
    case create(date: Date, suggestedName: String, prefillFrom: WorkoutLog?, planOverrides: [WorkoutPlanOverride])
    case edit(WorkoutLog)
}

struct WorkoutLogEditor: View {
    let mode: WorkoutEditorMode
    var onSave: (WorkoutLog) -> Void
    var onDelete: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @State private var date: Date
    @State private var name: String
    @State private var duration: Int
    @State private var calories: Double
    @State private var notes: String
    @State private var exercises: [DraftExercise]

    init(mode: WorkoutEditorMode, onSave: @escaping (WorkoutLog) -> Void, onDelete: (() -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        switch mode {
        case .create(let d, let sugg, let prefill, let planOverrides):
            _date = State(initialValue: d)
            _name = State(initialValue: sugg)
            if let p = prefill {
                _duration = State(initialValue: p.durationMinutes)
                _calories = State(initialValue: p.estimatedCalories)
                _notes = State(initialValue: p.notes ?? "")
                _exercises = State(initialValue: Self.initialExercises(prefill: p, planOverrides: planOverrides))
            } else {
                _duration = State(initialValue: 60)
                _calories = State(initialValue: 300)
                _notes = State(initialValue: "")
                _exercises = State(initialValue: Self.initialExercises(prefill: nil, planOverrides: planOverrides))
            }
        case .edit(let log):
            _date = State(initialValue: log.date)
            _name = State(initialValue: log.name)
            _duration = State(initialValue: log.durationMinutes)
            _calories = State(initialValue: log.estimatedCalories)
            _notes = State(initialValue: log.notes ?? "")
            _exercises = State(initialValue: log.exercises
                .sorted { $0.order < $1.order }
                .map { ex in
                    DraftExercise(
                        name: ex.name,
                        sets: ex.sortedSets.map { DraftSet(reps: $0.reps, weight: $0.weight) }
                    )
                })
        }
    }

    private static func initialExercises(
        prefill: WorkoutLog?,
        planOverrides: [WorkoutPlanOverride]
    ) -> [DraftExercise] {
        var drafts = prefill?.exercises
            .sorted { $0.order < $1.order }
            .map { ex in
                DraftExercise(
                    name: ex.name,
                    sets: ex.sortedSets.map { DraftSet(reps: $0.reps, weight: $0.weight) }
                )
            } ?? []

        var existingNames = Set(drafts.map { normalizedExerciseKey($0.name) })
        for item in planOverrides {
            let key = normalizedExerciseKey(item.exerciseName)
            guard !existingNames.contains(key) else { continue }
            let setCount = max(item.sets ?? 1, 1)
            let reps = item.reps ?? 10
            drafts.append(DraftExercise(
                name: item.exerciseName,
                sets: (0..<setCount).map { _ in DraftSet(reps: reps, weight: item.weight) }
            ))
            existingNames.insert(key)
        }
        return drafts
    }

    private static func normalizedExerciseKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Antrenman") {
                    DatePicker("Tarih", selection: $date, displayedComponents: [.date])
                    TextField("Ad", text: $name, prompt: Text("ör: Sırt + Göğüs"))
                    LabeledContent("Süre (dk)") {
                        TextField("", value: $duration, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    LabeledContent("Tahmini kcal") {
                        TextField("", value: $calories, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                ForEach(Array(exercises.enumerated()), id: \.element.id) { exIdx, _ in
                    Section {
                        TextField("Hareket adı", text: $exercises[exIdx].name, prompt: Text("ör: Bench Press"))
                            .textFieldStyle(.roundedBorder)

                        // Set başlık satırı
                        HStack(spacing: 8) {
                            Text("SET")
                                .font(.system(size: 9, weight: .medium))
                                .tracking(0.6)
                                .foregroundStyle(Palette.textQuaternary)
                                .frame(width: 30, alignment: .leading)
                            Text("TEKRAR")
                                .font(.system(size: 9, weight: .medium))
                                .tracking(0.6)
                                .foregroundStyle(Palette.textQuaternary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("KG")
                                .font(.system(size: 9, weight: .medium))
                                .tracking(0.6)
                                .foregroundStyle(Palette.textQuaternary)
                                .frame(width: 80, alignment: .trailing)
                            Color.clear.frame(width: 24)
                        }

                        // id-based binding loop — index'i stale capture etmemek için
                        ForEach($exercises[exIdx].sets) { $setDraft in
                            let setNum = (exercises[exIdx].sets.firstIndex(where: { $0.id == setDraft.id }) ?? 0) + 1
                            HStack(spacing: 8) {
                                Text("\(setNum)")
                                    .font(Typography.bodyBold)
                                    .foregroundStyle(Palette.textSecondary)
                                    .frame(width: 30, alignment: .leading)
                                Stepper(value: $setDraft.reps, in: 1...100) {
                                    Text("\(setDraft.reps) tek")
                                        .font(Typography.mono)
                                        .foregroundStyle(Palette.textPrimary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                TextField("BW", value: $setDraft.weight, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                Button {
                                    let setId = setDraft.id
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        if exercises[exIdx].sets.count > 1 {
                                            exercises[exIdx].sets.removeAll { $0.id == setId }
                                        }
                                    }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                        .font(.system(size: 12))
                                        .foregroundStyle(exercises[exIdx].sets.count > 1 ? Palette.textTertiary : Palette.textQuaternary)
                                }
                                .buttonStyle(.borderless)
                                .frame(width: 24)
                                .disabled(exercises[exIdx].sets.count <= 1)
                            }
                        }

                        Button {
                            // Önceki setten reps/kg kopyala (pyramid kolaylığı)
                            let prev = exercises[exIdx].sets.last
                            exercises[exIdx].sets.append(DraftSet(
                                reps: prev?.reps ?? 10,
                                weight: prev?.weight
                            ))
                        } label: {
                            Label("Set Ekle", systemImage: "plus.circle")
                                .font(Typography.caption)
                        }
                        .buttonStyle(.borderless)

                        // Hareketi tamamen sil
                        Button(role: .destructive) {
                            exercises.remove(at: exIdx)
                        } label: {
                            Label("Hareketi Sil", systemImage: "trash")
                                .font(Typography.caption)
                        }
                        .buttonStyle(.borderless)
                    } header: {
                        HStack {
                            Text(exercises[exIdx].name.isEmpty ? "Hareket \(exIdx + 1)" : exercises[exIdx].name)
                            Spacer()
                            Text(exercises[exIdx].previewSummary)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textTertiary)
                                .textCase(nil)
                        }
                    }
                }

                Section {
                    Button {
                        exercises.append(DraftExercise(name: "", sets: [DraftSet()]))
                    } label: {
                        Label("Hareket Ekle", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.regular)
                }

                Section("Not") {
                    TextField("ör: pump iyiydi, son set zorlandım", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if isEditing, let onDelete {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("Seansı Sil", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Seansı Düzenle" : "Yeni Seans")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Kaydet" : "Ekle") {
                        save()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 560, height: 640)
    }

    private func save() {
        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        switch mode {
        case .create:
            let log = WorkoutLog(
                date: date,
                name: name.trimmingCharacters(in: .whitespaces),
                durationMinutes: duration,
                estimatedCalories: calories,
                notes: trimmedNotes.isEmpty ? nil : trimmedNotes
            )
            ctx.insert(log)
            attachExercises(to: log)
            onSave(log)
        case .edit(let log):
            log.date = date
            log.name = name.trimmingCharacters(in: .whitespaces)
            log.durationMinutes = duration
            log.estimatedCalories = calories
            log.notes = trimmedNotes.isEmpty ? nil : trimmedNotes
            // Eski exercise + set'leri sil (cascade halleder ama açık silelim)
            for old in log.exercises {
                ctx.delete(old)
            }
            log.exercises.removeAll()
            attachExercises(to: log)
            onSave(log)
        }
    }

    private func attachExercises(to log: WorkoutLog) {
        for (idx, draft) in exercises.enumerated()
        where !draft.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let entry = WorkoutExerciseEntry(
                name: draft.name.trimmingCharacters(in: .whitespaces),
                order: idx
            )
            ctx.insert(entry)
            for (sIdx, setDraft) in draft.sets.enumerated() {
                let setEntry = ExerciseSet(
                    order: sIdx,
                    reps: setDraft.reps,
                    weight: setDraft.weight
                )
                ctx.insert(setEntry)
                entry.setEntries.append(setEntry)
            }
            log.exercises.append(entry)
        }
    }
}

private struct DraftExercise: Identifiable {
    let id = UUID()
    var name: String = ""
    var sets: [DraftSet] = [DraftSet()]

    /// Header'da gösterilen küçük özet (canlı güncellenir).
    var previewSummary: String {
        guard !sets.isEmpty else { return "—" }
        let allReps = sets.map(\.reps)
        let allWeights = sets.map(\.weight)
        let uniformReps = allReps.allSatisfy { $0 == allReps[0] }
        let uniformWeights = allWeights.allSatisfy { $0 == allWeights[0] }
        let allHaveWeight = allWeights.allSatisfy { $0 != nil }

        if uniformReps && uniformWeights {
            if let w = allWeights[0] {
                return "\(sets.count)×\(allReps[0]) @ \(Self.kg(w))"
            }
            return "\(sets.count)×\(allReps[0])"
        }
        let parts: [String] = sets.map { s in
            if let w = s.weight { return "\(Self.kg(w))×\(s.reps)" }
            return "BW×\(s.reps)"
        }
        return parts.joined(separator: ", ") + (allHaveWeight ? " kg" : "")
    }

    private static func kg(_ w: Double) -> String {
        w == w.rounded() ? "\(Int(w))" : String(format: "%.1f", w)
    }
}

private struct DraftSet: Identifiable {
    let id = UUID()
    var reps: Int = 10
    var weight: Double? = nil
}

/// Form içinde küçük label + control sarmalayıcı.
private struct LabeledControl<Content: View>: View {
    let label: String
    let content: Content
    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 8.5, weight: .medium))
                .tracking(0.6)
                .foregroundStyle(Palette.textQuaternary)
            content
        }
    }
}
