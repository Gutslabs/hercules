import SwiftUI
import SwiftData

// MARK: - Workout Tab

private enum WorkoutTab: String, CaseIterable {
    case overview  = "Genel Bakış"
    case programs  = "Programlar"
    case library   = "Kütüphane"

    var icon: String {
        switch self {
        case .overview:  return "calendar"
        case .programs:  return "list.bullet.clipboard"
        case .library:   return "books.vertical"
        }
    }
}

struct WorkoutView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \WorkoutLog.date, order: .reverse) private var logs: [WorkoutLog]
    @Query(sort: \WorkoutSession.weekday) private var templates: [WorkoutSession]
    @Query(sort: \WorkoutPlanOverride.createdAt) private var planOverrides: [WorkoutPlanOverride]
    @Query(sort: \WorkoutProgramArchive.archivedAt, order: .reverse) private var archivedPrograms: [WorkoutProgramArchive]
    @Query(sort: \Exercise.name) private var exercises: [Exercise]
    @Query(filter: #Predicate<TrainingProgram> { $0.isActive }) private var activePrograms: [TrainingProgram]

    @State private var workoutTab: WorkoutTab = .overview
    @State private var currentMonth: Date = Self.startOfMonth(.now)
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    @State private var editing: WorkoutLog? = nil
    @State private var creatingForDate: Date? = nil
    @State private var creatingPrefill: WorkoutLog? = nil
    @State private var creatingPlanned: [PlannedExercise] = []
    @State private var editingProgramSession: WorkoutSession? = nil
    @State private var showingArchives = false
    @State private var highlightedProgramWeekday: Int? = nil
    @State private var showingExerciseForm = false
    @State private var editingExercise: Exercise? = nil
    @Namespace private var tabNamespace

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

            VStack(spacing: 0) {
                // ── Tab bar ──
                workoutTabBar(compact: compact)

                // ── İçerik ──
                switch workoutTab {
                case .overview:
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: compact ? Spacing.lg : Spacing.xl) {
                                header(compact: compact)
                                workoutCalendarSection(exact: exact, templatesByWeekday: tplsByWeekday) { date in
                                    focusProgramDay(for: date, proxy: proxy)
                                }
                                programDaySection(exact: exact)
                                if activeProgram == nil {
                                    activeProgramSection(compact: compact, expansive: expansive)
                                        .id("active-program")
                                }
                                statsStrip(exact: exact, templatesByWeekday: tplsByWeekday, compact: compact)
                                Spacer(minLength: 24)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, compact ? Spacing.lg : (expansive ? 44 : Spacing.xxl))
                            .padding(.vertical, compact ? Spacing.lg : Spacing.xxl)
                        }
                    }
                case .programs:
                    WorkoutProgramsView(exercises: exercises, compact: compact, expansive: expansive)
                case .library:
                    ExerciseLibraryView(
                        exercises: exercises,
                        compact: compact,
                        expansive: expansive,
                        onAdd: { showingExerciseForm = true },
                        onEdit: { editingExercise = $0 },
                        onDelete: { ex in
                            ctx.delete(ex)
                            try? ctx.save()
                        }
                    )
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                switch workoutTab {
                case .overview:
                    Button {
                        let eff = effectiveLog(for: selectedDay)
                        if let exact = eff.log, !eff.isTemplate {
                            editing = exact
                        } else {
                            creatingPlanned = plannedExercises(for: selectedDay)
                            creatingForDate = selectedDay
                            creatingPrefill = eff.log
                        }
                    } label: {
                        Label("Yeni Seans", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("Bu güne antrenman ekle (⌘N)")
                case .programs:
                    EmptyView()
                case .library:
                    Button { showingExerciseForm = true } label: {
                        Label("Hareket Ekle", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .help("Yeni hareket ekle (⌘N)")
                }
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
                if $0 == nil { creatingPrefill = nil; creatingPlanned = [] }
            }
        )) { wrap in
            WorkoutLogEditor(
                mode: .create(
                    date: wrap.date,
                    suggestedName: creatingPrefill?.name ?? suggestedName(for: wrap.date),
                    prefillFrom: creatingPrefill,
                    planOverrides: overrides(for: wrap.date),
                    plannedExercises: creatingPlanned
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
        .sheet(isPresented: $showingExerciseForm) {
            ExerciseFormSheet(mode: .create, allExercises: exercises) { exercise in
                ctx.insert(exercise)
                try? ctx.save()
            }
        }
        .sheet(item: $editingExercise) { exercise in
            ExerciseFormSheet(mode: .edit(exercise), allExercises: exercises) { _ in
                try? ctx.save()
            }
        }
    }

    // MARK: Tab Bar

    private func workoutTabBar(compact: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(WorkoutTab.allCases, id: \.rawValue) { tab in
                let isSelected = workoutTab == tab
                Button {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                        workoutTab = tab
                    }
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 12, weight: .semibold))
                        Text(tab.rawValue)
                            .font(Typography.bodyBold)
                    }
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 7)
                    .background(
                        Group {
                            if isSelected {
                                RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                                    .fill(Palette.surfaceElevated)
                                    .matchedGeometryEffect(id: "workout-tab", in: tabNamespace)
                            }
                        }
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, compact ? Spacing.lg : Spacing.xxl)
        .padding(.top, compact ? Spacing.md : Spacing.lg)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    /// Aktif programın seçili güne denk gelen antrenmanını gösterir + kaydetme aksiyonu.
    @ViewBuilder
    private func programDaySection(exact: [Date: WorkoutLog]) -> some View {
        if let program = activeProgram, let start = program.startDate {
            let day = trainingDay(for: selectedDay)
            let logged = exact[Calendar.current.startOfDay(for: selectedDay)]
            VStack(alignment: .leading, spacing: Spacing.lg) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.sm) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(program.name).eyebrow()
                        Text(Self.fullDayFormatter.string(from: selectedDay))
                            .font(Typography.title)
                            .foregroundStyle(Palette.textPrimary)
                    }
                    Spacer()
                    if let day, let week = day.week {
                        PillTag(text: "Hafta \(week.weekNumber) · Gün \(day.dayNumber)", tint: Palette.accent)
                    }
                }

                if let day {
                    if day.isRestDay {
                        programRestRow
                    } else if day.sortedBlocks.isEmpty {
                        Text("Bu gün için program boş.")
                            .font(Typography.body)
                            .foregroundStyle(Palette.textTertiary)
                            .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(day.sortedBlocks) { block in
                                ProgramDayBlockRow(block: block)
                            }
                        }
                        logActionRow(logged: logged)
                    }
                } else {
                    let cal = Calendar.current
                    let before = cal.startOfDay(for: selectedDay) < cal.startOfDay(for: start)
                    Text(before
                         ? "Program \(start.formatted(date: .abbreviated, time: .omitted)) tarihinde başlıyor."
                         : "Program bu tarihte sona ermiş.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
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
    }

    private var programRestRow: some View {
        HStack(spacing: Spacing.sm) {
            Image(systemName: "moon.zzz.fill").foregroundStyle(Palette.textSecondary)
            Text("Dinlenme günü — toparlanmaya odaklan.")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, minHeight: 60)
        .padding(.horizontal, Spacing.md)
        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surfaceElevated.opacity(0.45)))
    }

    @ViewBuilder
    private func logActionRow(logged: WorkoutLog?) -> some View {
        HStack(spacing: Spacing.md) {
            if let logged {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.positive)
                    Text("Kaydedildi · \(logged.exercises.count) hareket · \(logged.durationMinutes) dk")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Button {
                    editing = logged
                } label: {
                    Label("Düzenle", systemImage: "pencil").font(Typography.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Spacer()
                Button {
                    creatingPlanned = plannedExercises(for: selectedDay)
                    creatingForDate = selectedDay
                    creatingPrefill = nil
                } label: {
                    Label("Bu Günü Kaydet", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
            }
        }
        .padding(.top, 4)
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
                        scheduleHint: programScheduleHint(for: date) ?? templateName(for: date),
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

    // MARK: Aktif program → takvim eşlemesi

    private var activeProgram: TrainingProgram? { activePrograms.first }

    /// Verilen tarihin aktif programdaki hangi antrenman gününe denk geldiğini döndürür.
    /// Gün 1 = başlangıç tarihi; sonra ardışık günler. Program bitince nil.
    private func trainingDay(for date: Date) -> TrainingDay? {
        guard let program = activeProgram, let start = program.startDate else { return nil }
        let cal = Calendar.current
        let startDay = cal.startOfDay(for: start)
        let target = cal.startOfDay(for: date)
        guard target >= startDay else { return nil }
        let offset = cal.dateComponents([.day], from: startDay, to: target).day ?? 0
        let weeks = program.sortedWeeks
        guard !weeks.isEmpty, offset < weeks.count * 7 else { return nil }
        let week = weeks[offset / 7]
        return week.day(offset % 7 + 1)
    }

    /// Takvim hücresinde gösterilecek program ipucu (gün adı / "Dinlenme").
    private func programScheduleHint(for date: Date) -> String? {
        guard let day = trainingDay(for: date) else { return nil }
        if day.isRestDay { return "Dinlenme" }
        guard !day.blocks.isEmpty else { return nil }
        return day.name?.isEmpty == false ? day.name : "Antrenman"
    }

    /// Program gününün hareket reçetesini kayıt formu için PlannedExercise listesine çevirir.
    private func plannedExercises(for date: Date) -> [PlannedExercise] {
        guard let day = trainingDay(for: date), !day.isRestDay else { return [] }
        return day.sortedBlocks
            .filter { $0.type == .exercise }
            .compactMap { block in
                guard let name = block.exerciseName, !name.isEmpty else { return nil }
                return PlannedExercise(
                    name: name,
                    sets: block.sets ?? 3,
                    reps: Self.firstInt(block.repsRaw) ?? 10,
                    weight: Self.firstDouble(block.load)
                )
            }
    }

    /// "8-10", "AMRAP", "12" gibi metinden ilk tam sayıyı çeker.
    private static func firstInt(_ s: String?) -> Int? {
        guard let s else { return nil }
        let digits = s.prefix { $0.isNumber }
        return Int(digits)
    }

    /// "60 kg", "%75", "RPE 8" gibi metinden ilk ondalık sayıyı çeker (yoksa nil).
    private static func firstDouble(_ s: String?) -> Double? {
        guard let s, !s.contains("%"), s.lowercased().contains("kg") else { return nil }
        let num = s.prefix { $0.isNumber || $0 == "." || $0 == "," }
            .replacingOccurrences(of: ",", with: ".")
        return Double(num)
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

// MARK: - Workout design atoms

private struct WorkoutHeaderSignal: View {
    let icon: String
    let label: String
    let value: String
    let detail: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Palette.accent)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Palette.accentSoft)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Palette.accent.opacity(0.16), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 1) {
                Text(label.uppercased())
                    .font(Typography.label)
                    .tracking(0.8)
                    .foregroundStyle(Palette.textQuaternary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(Typography.monoLarge)
                        .foregroundStyle(Palette.textPrimary)
                    Text(detail)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }
            .frame(minWidth: 70, alignment: .leading)
        }
    }
}

private struct WorkoutHeaderDivider: View {
    var height: CGFloat = 38

    var body: some View {
        Rectangle()
            .fill(Palette.borderStrong)
            .frame(width: 0.5, height: height)
            .padding(.horizontal, Spacing.md)
    }
}

private struct ProgramSummaryDatum: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(Typography.label)
                .tracking(0.8)
                .foregroundStyle(Palette.textQuaternary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textPrimary)
                Text(unit)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .frame(minWidth: 66, alignment: .leading)
    }
}

private struct WorkoutMiniButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.captionBold)
            .foregroundStyle(isEnabled ? Palette.textSecondary : Palette.textQuaternary)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(configuration.isPressed ? Palette.surfaceElevated.opacity(0.78) : Palette.surfaceElevated.opacity(0.52))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(Palette.borderStrong, lineWidth: 0.55)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(isEnabled ? 1 : 0.45)
            .animation(.spring(response: 0.18, dampingFraction: 0.78), value: configuration.isPressed)
    }
}

private struct WorkoutIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.16, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - Active program board

private struct WorkoutTermCard: View {
    let term: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.md) {
            Text(term)
                .font(Typography.mono)
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(Palette.accentSoft)
                )

            Text(detail)
                .font(Typography.caption)
                .foregroundStyle(Palette.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(Spacing.md)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Palette.surfaceElevated.opacity(0.36))
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
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(WorkoutSession.weekdayNames[weekday])
                        .font(Typography.captionBold)
                        .foregroundStyle(session == nil ? Palette.textTertiary : Palette.accent)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(session == nil ? Color.white.opacity(0.045) : Palette.accentSoft))

                    Text(session?.name ?? "Serbest / Dinlenme")
                        .font(Typography.titleSmall)
                        .foregroundStyle(session == nil ? Palette.textTertiary : Palette.textPrimary)
                        .lineLimit(2)
                }

                Spacer(minLength: Spacing.md)

                HStack(spacing: 6) {
                    iconAction(systemName: session == nil ? "plus" : "pencil", help: session == nil ? "Güne plan ekle" : "Planı düzenle", action: onEdit)
                    if let session {
                        iconAction(systemName: "archivebox", help: "Bu günü aktif plandan kaldır") {
                            onDelete(session)
                        }
                        .opacity(hovering ? 1 : 0.28)
                    }
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

                if let warmup = session.warmup, !warmup.isEmpty {
                    labelBlock("Isınma", warmup)
                }

                let exercises = session.sortedTemplateExercises
                if !exercises.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                            exerciseRow(exercise)
                            if index < exercises.count - 1 {
                                Hairline()
                                    .padding(.leading, 30)
                                    .padding(.vertical, 7)
                            }
                        }
                    }
                    .padding(.top, 2)
                } else {
                    emptyLine("Hareket reçetesi yok")
                }

                if let progression = session.progression, !progression.isEmpty {
                    Hairline()
                    labelBlock("Progression", progression)
                }

                if let notes = session.notes, !notes.isEmpty {
                    labelBlock("Not", notes)
                }
            } else if !legacyOverrides.isEmpty {
                labelBlock("Eski AI eklemeleri", legacyOverrides.map { "+ \($0.exerciseName) · \($0.prescriptionText)" }.joined(separator: "\n"))
            } else {
                Spacer(minLength: 10)
                emptyLine("Plan yok")
            }
        }
        .padding(Spacing.lg)
        .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .fill(isHighlighted ? Palette.accent.opacity(0.11) : (hovering ? Palette.surfaceElevated.opacity(0.68) : Palette.surfaceElevated.opacity(0.44)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(isHighlighted ? Palette.accent.opacity(0.95) : Palette.border, lineWidth: isHighlighted ? 1.2 : 0.5)
        )
        .shadow(color: isHighlighted ? Palette.accent.opacity(0.12) : .clear, radius: 18, x: 0, y: 8)
        .contentShape(Rectangle())
        .onTapGesture(perform: onEdit)
        .onHover { hovering = $0 }
    }

    private func iconAction(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 26, height: 26)
                .background(
                    Circle().fill(Palette.surface.opacity(0.86))
                )
                .overlay(
                    Circle().strokeBorder(Palette.borderStrong, lineWidth: 0.55)
                )
        }
        .buttonStyle(WorkoutIconButtonStyle())
        .help(help)
    }

    private func exerciseRow(_ exercise: WorkoutTemplateExercise) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(exercise.order + 1).")
                .font(Typography.mono)
                .foregroundStyle(Palette.textQuaternary)
                .frame(width: 22, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(exercise.name)
                        .font(Typography.captionBold)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)

                    if let sourceURL = exercise.sourceURL,
                       let url = URL(string: sourceURL) {
                        Link(destination: url) {
                            Image(systemName: "link")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Palette.accent)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Palette.accentSoft))
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
            }
        }
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

/// Genel bakıştaki program günü kartında tek bir reçete satırı.
private struct ProgramDayBlockRow: View {
    let block: TrainingBlock

    var body: some View {
        HStack(alignment: .center, spacing: Spacing.md) {
            if block.type == .exercise {
                Image(systemName: "dumbbell.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(block.exerciseName ?? "—")
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                    if let intensity = block.intensityText {
                        Text(intensity)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(block.summaryText)
                        .font(Typography.mono)
                        .foregroundStyle(Palette.textPrimary)
                    if let rest = block.restSeconds {
                        Text(TrainingBlock.formatSeconds(rest))
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            } else {
                Image(systemName: "timer")
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.textSecondary)
                Text("Dinlenme · \(block.summaryText)")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                Spacer()
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(block.type == .exercise ? Palette.accentSoft.opacity(0.5) : Palette.surfaceElevated.opacity(0.4))
        )
    }
}

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

/// Aktif programdaki bir günün reçetesinden kayıt formunu önden doldurmak için.
struct PlannedExercise {
    let name: String
    let sets: Int
    let reps: Int
    let weight: Double?
}

enum WorkoutEditorMode {
    /// `prefillFrom`: template / başka bir günden kopyalanacak log (örn. recurring workout).
    /// `plannedExercises`: aktif programdaki günün reçetesi (set/tekrar hedefleri).
    case create(date: Date, suggestedName: String, prefillFrom: WorkoutLog?, planOverrides: [WorkoutPlanOverride], plannedExercises: [PlannedExercise])
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
        case .create(let d, let sugg, let prefill, let planOverrides, let planned):
            _date = State(initialValue: d)
            _name = State(initialValue: sugg)
            if let p = prefill {
                _duration = State(initialValue: p.durationMinutes)
                _calories = State(initialValue: p.estimatedCalories)
                _notes = State(initialValue: p.notes ?? "")
                _exercises = State(initialValue: Self.initialExercises(prefill: p, planOverrides: planOverrides, planned: planned))
            } else {
                _duration = State(initialValue: 60)
                _calories = State(initialValue: 300)
                _notes = State(initialValue: "")
                _exercises = State(initialValue: Self.initialExercises(prefill: nil, planOverrides: planOverrides, planned: planned))
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
        planOverrides: [WorkoutPlanOverride],
        planned: [PlannedExercise]
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
        // Aktif programdaki günün hareketleri (set/tekrar hedefleriyle).
        for item in planned {
            let key = normalizedExerciseKey(item.name)
            guard !existingNames.contains(key) else { continue }
            let setCount = max(item.sets, 1)
            drafts.append(DraftExercise(
                name: item.name,
                sets: (0..<setCount).map { _ in DraftSet(reps: item.reps, weight: item.weight) }
            ))
            existingNames.insert(key)
        }
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

// MARK: - Workout Programs View

// MARK: - Exercise Library View

private enum LibraryGroupMode: String, CaseIterable {
    case muscle   = "Kas Grubu"
    case category = "Hareket Tipi"

    var icon: String {
        switch self {
        case .muscle:   return "figure.arms.open"
        case .category: return "rectangle.3.group"
        }
    }
}

/// Unique geniş kas grubu listesi — sabit sıra
private let muscleGroupOrder: [String] = [
    "Göğüs", "Sırt", "Omuzlar", "Kollar", "Karın", "Bacaklar", "Diğer"
]

private struct ExerciseLibraryView: View {
    let exercises: [Exercise]
    let compact: Bool
    let expansive: Bool
    let onAdd: () -> Void
    let onEdit: (Exercise) -> Void
    let onDelete: (Exercise) -> Void

    @State private var searchText = ""
    @State private var filterEquipment: Set<Equipment> = []
    @State private var filterMuscleGroup: Set<String> = []
    @State private var filterDifficulty: Set<Difficulty> = []
    @State private var groupMode: LibraryGroupMode = .muscle
    @State private var showFilterPopover = false
    @Namespace private var modeNS

    // MARK: Active filter count (badge)
    private var activeFilterCount: Int {
        (filterEquipment.isEmpty ? 0 : 1) +
        (filterMuscleGroup.isEmpty ? 0 : 1) +
        (filterDifficulty.isEmpty ? 0 : 1)
    }

    // MARK: Filtered list
    private var filtered: [Exercise] {
        exercises.filter { ex in
            let matchSearch = searchText.isEmpty ||
                ex.name.localizedCaseInsensitiveContains(searchText)
            let matchEq = filterEquipment.isEmpty || filterEquipment.contains(ex.equipment)
            let matchMuscle = filterMuscleGroup.isEmpty ||
                ex.primaryMuscles.contains { filterMuscleGroup.contains($0.muscleGroup) } ||
                ex.secondaryMuscles.contains { filterMuscleGroup.contains($0.muscleGroup) }
            let matchDiff = filterDifficulty.isEmpty ||
                ex.difficulty.map { filterDifficulty.contains($0) } ?? false
            return matchSearch && matchEq && matchMuscle && matchDiff
        }
    }

    // MARK: Grouped
    private var groupedByMuscle: [(String, [Exercise])] {
        var groups: [String: [Exercise]] = [:]
        for ex in filtered { groups[ex.primaryMuscleGroup, default: []].append(ex) }
        return muscleGroupOrder.compactMap { key in
            guard let list = groups[key], !list.isEmpty else { return nil }
            return (key, list)
        }
    }

    private var groupedByCategory: [(String, [Exercise])] {
        var groups: [String: [Exercise]] = [:]
        for ex in filtered { groups[ex.category?.label ?? "Kategorisiz", default: []].append(ex) }
        let order = ExerciseCategory.allCases.map(\.label) + ["Kategorisiz"]
        return order.compactMap { key in
            guard let list = groups[key], !list.isEmpty else { return nil }
            return (key, list)
        }
    }

    private var activeGroups: [(String, [Exercise])] {
        groupMode == .muscle ? groupedByMuscle : groupedByCategory
    }

    private var availableMuscleGroups: [String] {
        let used = Set(exercises.flatMap { ($0.primaryMuscles + $0.secondaryMuscles).map(\.muscleGroup) })
        return muscleGroupOrder.filter { used.contains($0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                libraryHeader
                searchAndControls
                // Aktif filtre özetini göster
                if activeFilterCount > 0 { activeFilterSummary }
                if filtered.isEmpty { libraryEmptyState } else { libraryContent }
                Spacer(minLength: 24)
            }
            .padding(.horizontal, compact ? Spacing.lg : (expansive ? 44 : Spacing.xxl))
            .padding(.vertical, compact ? Spacing.lg : Spacing.xxl)
        }
    }

    // MARK: Header
    private var libraryHeader: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Hareket Kütüphanesi").eyebrow()
                Text("Egzersizler")
                    .font(Typography.display(36))
                    .foregroundStyle(Palette.textPrimary)
                Text("\(exercises.count) hareket kayıtlı")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
            }
            Spacer()
            Button(action: onAdd) {
                Label("Yeni Hareket", systemImage: "plus")
                    .font(Typography.bodyBold)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.accent))
                    .foregroundStyle(.white)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: Search + controls row
    private var searchAndControls: some View {
        HStack(spacing: Spacing.sm) {
            // Arama
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.textTertiary)
                    .font(.system(size: 13))
                TextField("Hareket ara…", text: $searchText)
                    .font(Typography.body)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))

            // Filtre butonu
            Button { showFilterPopover.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 11, weight: .semibold))
                    Text("Filtre")
                        .font(Typography.captionBold)
                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(Palette.accent))
                    }
                }
                .foregroundStyle(activeFilterCount > 0 ? Palette.accent : Palette.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(activeFilterCount > 0 ? Palette.accentSoft : Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .strokeBorder(activeFilterCount > 0 ? Palette.accent.opacity(0.4) : Palette.border, lineWidth: 0.5)
                )
            }
            .buttonStyle(PlainButtonStyle())
            .popover(isPresented: $showFilterPopover, arrowEdge: .bottom) {
                ExerciseFilterPopover(
                    availableMuscleGroups: availableMuscleGroups,
                    filterEquipment: $filterEquipment,
                    filterMuscleGroup: $filterMuscleGroup,
                    filterDifficulty: $filterDifficulty
                )
            }

            // Gruplama modu
            groupModePicker
        }
    }

    // MARK: Active filter summary chips
    private var activeFilterSummary: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(filterEquipment), id: \.rawValue) { eq in
                    activeChip(label: eq.label) { filterEquipment.remove(eq) }
                }
                ForEach(Array(filterMuscleGroup), id: \.self) { g in
                    activeChip(label: g) { filterMuscleGroup.remove(g) }
                }
                ForEach(Array(filterDifficulty), id: \.rawValue) { d in
                    activeChip(label: d.label) { filterDifficulty.remove(d) }
                }
                if activeFilterCount > 1 {
                    Button {
                        filterEquipment.removeAll()
                        filterMuscleGroup.removeAll()
                        filterDifficulty.removeAll()
                    } label: {
                        Text("Tümünü Temizle")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func activeChip(label: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.system(size: 10, weight: .medium)).foregroundStyle(Palette.accent)
            Button(action: onRemove) {
                Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(Palette.accent.opacity(0.7))
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Palette.accentSoft))
        .overlay(Capsule().strokeBorder(Palette.accent.opacity(0.25), lineWidth: 0.5))
    }

    // MARK: Group mode picker
    private var groupModePicker: some View {
        HStack(spacing: 2) {
            ForEach(LibraryGroupMode.allCases, id: \.rawValue) { mode in
                let sel = groupMode == mode
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.80)) { groupMode = mode }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: mode.icon).font(.system(size: 10, weight: .semibold))
                        Text(mode.rawValue).font(Typography.captionBold)
                    }
                    .foregroundStyle(sel ? Palette.textPrimary : Palette.textSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
                    .background(
                        Group {
                            if sel {
                                RoundedRectangle(cornerRadius: Radius.sm - 3, style: .continuous)
                                    .fill(Palette.surfaceElevated)
                                    .matchedGeometryEffect(id: "lib-mode", in: modeNS)
                            }
                        }
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(3)
        .background(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: Radius.sm, style: .continuous).strokeBorder(Palette.border, lineWidth: 0.5))
        .fixedSize(horizontal: true, vertical: true)
    }

    // MARK: Content
    private var libraryContent: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            ForEach(activeGroups, id: \.0) { group, groupExercises in
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    HStack(spacing: 8) {
                        Text(group).eyebrow()
                        Text("\(groupExercises.count)")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Palette.textQuaternary)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Palette.surfaceElevated))
                    }
                    .padding(.bottom, 2)

                    if compact {
                        LazyVStack(spacing: Spacing.sm) {
                            ForEach(groupExercises) { ex in
                                ExerciseRow(exercise: ex, allExercises: exercises, onEdit: { onEdit(ex) }, onDelete: { onDelete(ex) })
                            }
                        }
                    } else {
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: Spacing.sm), GridItem(.flexible(), spacing: Spacing.sm)],
                            spacing: Spacing.sm
                        ) {
                            ForEach(groupExercises) { ex in
                                ExerciseRow(exercise: ex, allExercises: exercises, onEdit: { onEdit(ex) }, onDelete: { onDelete(ex) })
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Empty state
    private var libraryEmptyState: some View {
        VStack(spacing: Spacing.lg) {
            Image(systemName: "books.vertical")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            VStack(spacing: 6) {
                Text(searchText.isEmpty && activeFilterCount == 0 ? "Henüz hareket yok" : "Sonuç bulunamadı")
                    .font(Typography.title).foregroundStyle(Palette.textPrimary)
                Text(searchText.isEmpty && activeFilterCount == 0
                     ? "\"Yeni Hareket\" ile kütüphaneni oluşturmaya başla."
                     : "Arama veya filtre kriterini değiştir.")
                    .font(Typography.body).foregroundStyle(Palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if searchText.isEmpty && activeFilterCount == 0 {
                Button(action: onAdd) {
                    Label("İlk Hareketi Ekle", systemImage: "plus")
                }
                .buttonStyle(PlainButtonStyle())
                .foregroundStyle(Palette.accent)
                .font(Typography.bodyBold)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Filter Popover

private struct ExerciseFilterPopover: View {
    let availableMuscleGroups: [String]
    @Binding var filterEquipment: Set<Equipment>
    @Binding var filterMuscleGroup: Set<String>
    @Binding var filterDifficulty: Set<Difficulty>

    private var totalActive: Int {
        (filterEquipment.isEmpty ? 0 : filterEquipment.count) +
        filterMuscleGroup.count + filterDifficulty.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Başlık
            HStack {
                Text("Filtrele")
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                if totalActive > 0 {
                    Button("Temizle") {
                        filterEquipment.removeAll()
                        filterMuscleGroup.removeAll()
                        filterDifficulty.removeAll()
                    }
                    .font(Typography.caption)
                    .foregroundStyle(Palette.accent)
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.lg) {
                    // Ekipman
                    filterSection(title: "Ekipman") {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(Equipment.allCases) { eq in
                                filterToggleRow(
                                    icon: eq.icon,
                                    label: eq.label,
                                    active: filterEquipment.contains(eq)
                                ) {
                                    if filterEquipment.contains(eq) { filterEquipment.remove(eq) }
                                    else { filterEquipment.insert(eq) }
                                }
                            }
                        }
                    }

                    Divider()

                    // Kas grubu
                    if !availableMuscleGroups.isEmpty {
                        filterSection(title: "Kas Grubu") {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                ForEach(availableMuscleGroups, id: \.self) { g in
                                    filterToggleRow(
                                        icon: "figure.arms.open",
                                        label: g,
                                        active: filterMuscleGroup.contains(g)
                                    ) {
                                        if filterMuscleGroup.contains(g) { filterMuscleGroup.remove(g) }
                                        else { filterMuscleGroup.insert(g) }
                                    }
                                }
                            }
                        }
                        Divider()
                    }

                    // Zorluk
                    filterSection(title: "Zorluk") {
                        HStack(spacing: 8) {
                            ForEach(Difficulty.allCases) { diff in
                                let active = filterDifficulty.contains(diff)
                                let c: Color = diff == .beginner ? .green : (diff == .intermediate ? .orange : .red)
                                Button {
                                    if active { filterDifficulty.remove(diff) }
                                    else { filterDifficulty.insert(diff) }
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: diff.icon).font(.system(size: 10, weight: .semibold))
                                        Text(diff.label).font(Typography.captionBold)
                                    }
                                    .foregroundStyle(active ? .white : Palette.textSecondary)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .frame(maxWidth: .infinity)
                                    .background(RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                                        .fill(active ? c : Palette.surface))
                                    .overlay(RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                                        .strokeBorder(active ? c : Palette.border, lineWidth: 0.5))
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
                .padding(Spacing.lg)
            }
        }
        .frame(width: 320)
        .background(Palette.background)
    }

    private func filterSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text(title).eyebrow()
            content()
        }
    }

    private func filterToggleRow(icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(active ? Palette.accent : Palette.textTertiary)
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textSecondary)
                Text(label)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                    .fill(active ? Palette.accentSoft : Palette.surface.opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                    .strokeBorder(active ? Palette.accent.opacity(0.3) : Palette.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Exercise Row

private struct ExerciseRow: View {
    let exercise: Exercise
    let allExercises: [Exercise]
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var hovering = false
    @State private var showingDetail = false

    var body: some View {
        Button { showingDetail = true } label: {
            HStack(spacing: Spacing.md) {
                // Ekipman ikonu
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                        .fill(Palette.accentSoft)
                        .frame(width: 36, height: 36)
                    Image(systemName: exercise.equipment.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Palette.accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.name)
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        Text(exercise.equipment.label)
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                        if let cat = exercise.category {
                            Text("·").foregroundStyle(Palette.textQuaternary)
                            Text(cat.shortLabel)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(Palette.accent.opacity(0.85))
                        }
                        if !exercise.primaryMuscles.isEmpty {
                            Text("·")
                                .foregroundStyle(Palette.textQuaternary)
                            Text(exercise.primaryMuscles.map(\.label).joined(separator: ", "))
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textTertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 0)

                // Zorluk rozeti
                if let diff = exercise.difficulty {
                    let c: Color = diff == .beginner ? .green : (diff == .intermediate ? .orange : .red)
                    Image(systemName: diff.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(c)
                }

                // Kas görseli (küçük)
                if !exercise.allMuscles.isEmpty {
                    muscleDots
                }

                // Aksiyon butonları
                if hovering {
                    HStack(spacing: 4) {
                        Button { onEdit() } label: {
                            Image(systemName: "pencil")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 28, height: 28)
                                .background(Palette.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button { onDelete() } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 12, weight: .medium))
                                .frame(width: 28, height: 28)
                                .background(Palette.surface)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .foregroundStyle(Palette.negative)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(Spacing.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .fill(hovering ? Palette.surfaceElevated : Palette.surface.opacity(0.82))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.22, dampingFraction: 0.82), value: hovering)
        .sheet(isPresented: $showingDetail) {
            ExerciseDetailSheet(exercise: exercise, allExercises: allExercises, onEdit: onEdit)
        }
    }

    private var muscleDots: some View {
        HStack(spacing: 2) {
            ForEach(exercise.primaryMuscles.prefix(3), id: \.rawValue) { _ in
                Circle().fill(Color.red.opacity(0.65)).frame(width: 5, height: 5)
            }
            ForEach(exercise.secondaryMuscles.prefix(2), id: \.rawValue) { _ in
                Circle().fill(Color.orange.opacity(0.55)).frame(width: 5, height: 5)
            }
        }
    }
}

// MARK: - Exercise Progress Chart

/// Bir hareketin geçmiş antrenman kayıtlarından ileriye dönük gelişim grafiği.
private struct ExerciseProgressChart: View {
    let exerciseName: String
    @Query(sort: \WorkoutLog.date) private var logs: [WorkoutLog]
    @State private var metric: Metric = .maxWeight

    enum Metric: String, CaseIterable, Identifiable {
        case maxWeight, volume, oneRM, reps
        var id: String { rawValue }
        var label: String {
            switch self {
            case .maxWeight: return "Maks kg"
            case .volume:    return "Hacim"
            case .oneRM:     return "1RM"
            case .reps:      return "Tekrar"
            }
        }
        var unit: String {
            switch self {
            case .maxWeight, .oneRM: return "kg"
            case .volume:            return "kg·tekrar"
            case .reps:              return "tekrar"
            }
        }
    }

    private static func normalizedKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private var points: [TrendPoint] {
        let key = Self.normalizedKey(exerciseName)
        var result: [TrendPoint] = []
        for log in logs {
            let matching = log.exercises.filter { Self.normalizedKey($0.name) == key }
            guard !matching.isEmpty else { continue }
            let sets = matching.flatMap { $0.setEntries }
            guard !sets.isEmpty else { continue }
            let value: Double
            switch metric {
            case .maxWeight:
                value = sets.compactMap { $0.weight }.max() ?? 0
            case .volume:
                value = sets.reduce(0) { $0 + Double($1.reps) * ($1.weight ?? 0) }
            case .oneRM:
                value = sets.compactMap { set -> Double? in
                    guard let w = set.weight, w > 0, set.reps > 0 else { return nil }
                    return w * (1 + Double(set.reps) / 30)
                }.max() ?? 0
            case .reps:
                value = Double(sets.reduce(0) { $0 + $1.reps })
            }
            guard value > 0 else { continue }
            result.append(TrendPoint(date: log.date, value: value))
        }
        return result.sorted { $0.date < $1.date }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Picker("", selection: $metric) {
                ForEach(Metric.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            MetricChart(title: "Gelişim", unit: metric.unit, points: points, height: 200)
        }
    }
}

// MARK: - Exercise Detail Sheet

/// İki fotoğrafı (başlangıç/bitiş) belirli aralıkla değiştirerek "gif" hissi verir.
private struct AnimatedExerciseImage: View {
    let urls: [URL]
    @State private var index = 0
    private let timer = Timer.publish(every: 0.9, on: .main, in: .common).autoconnect()

    var body: some View {
        AsyncImage(url: urls[index % urls.count]) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .empty:
                ProgressView()
            case .failure:
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundStyle(Palette.textQuaternary)
            @unknown default:
                EmptyView()
            }
        }
        .padding(Spacing.sm)
        .onReceive(timer) { _ in
            guard urls.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                index = (index + 1) % urls.count
            }
        }
    }
}

private struct ExerciseDetailSheet: View {
    let exercise: Exercise
    let allExercises: [Exercise]
    let onEdit: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var navigationStack: [Exercise] = []   // varyasyon navigasyonu

    /// Şu an gösterilen egzersiz: stack varsa en üstteki, yoksa ana egzersiz
    private var current: Exercise {
        navigationStack.last ?? exercise
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Başlık
            HStack {
                HStack(spacing: Spacing.sm) {
                    // Geri butonu (stack'te önceki varsa)
                    if !navigationStack.isEmpty {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                _ = navigationStack.removeLast()
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.accent)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        // Breadcrumb
                        if !navigationStack.isEmpty {
                            Button {
                                withAnimation { navigationStack.removeAll() }
                            } label: {
                                Text(exercise.name)
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.accent.opacity(0.7))
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        Text(current.name)
                            .font(Typography.title)
                            .foregroundStyle(Palette.textPrimary)
                        HStack(spacing: 6) {
                            Text(current.equipment.label)
                                .font(Typography.body)
                                .foregroundStyle(Palette.textSecondary)
                            if let cat = current.category {
                                Text("·").foregroundStyle(Palette.textQuaternary)
                                Text(cat.label)
                                    .font(Typography.body)
                                    .foregroundStyle(Palette.accent.opacity(0.85))
                            }
                        }
                    }
                }
                Spacer()
                HStack(spacing: Spacing.sm) {
                    Button("Düzenle") { dismiss(); onEdit() }
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.accent)
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            }
            .padding(Spacing.xl)

            Divider().background(Palette.border)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // Meta bilgiler (zorluk + kategori)
                    if current.difficulty != nil || current.category != nil {
                        HStack(spacing: 8) {
                            if let diff = current.difficulty {
                                let c: Color = diff == .beginner ? .green : (diff == .intermediate ? .orange : .red)
                                HStack(spacing: 5) {
                                    Image(systemName: diff.icon).font(.system(size: 10, weight: .semibold))
                                    Text(diff.label).font(Typography.captionBold)
                                }
                                .foregroundStyle(c)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Capsule().fill(c.opacity(0.12)))
                                .overlay(Capsule().strokeBorder(c.opacity(0.3), lineWidth: 0.5))
                            }
                            if let cat = current.category {
                                HStack(spacing: 5) {
                                    Image(systemName: cat.icon).font(.system(size: 10, weight: .semibold))
                                    Text(cat.shortLabel).font(Typography.captionBold)
                                }
                                .foregroundStyle(Palette.accent)
                                .padding(.horizontal, 9).padding(.vertical, 5)
                                .background(Capsule().fill(Palette.accentSoft))
                                .overlay(Capsule().strokeBorder(Palette.accent.opacity(0.3), lineWidth: 0.5))
                            }
                        }
                    }

                    // Hareket görseli (başlangıç/bitiş fotoğraflarını sırayla gösterir)
                    if !current.imageURLs.isEmpty {
                        AnimatedExerciseImage(urls: current.imageURLs)
                            .frame(maxWidth: .infinity)
                            .frame(height: 260)
                            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .fill(Palette.surfaceElevated.opacity(0.5)))
                            .clipShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                                .strokeBorder(Palette.border, lineWidth: 0.5))
                    }

                    // Vücut diyagramı
                    MuscleBodyDisplay(
                        primaryMuscles: Set(current.primaryMuscles),
                        secondaryMuscles: Set(current.secondaryMuscles)
                    )

                    // Kas listesi
                    if !current.primaryMuscles.isEmpty || !current.secondaryMuscles.isEmpty {
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            if !current.primaryMuscles.isEmpty {
                                muscleChips(label: "Birincil", muscles: current.primaryMuscles, color: .red.opacity(0.75))
                            }
                            if !current.secondaryMuscles.isEmpty {
                                muscleChips(label: "İkincil", muscles: current.secondaryMuscles, color: .orange.opacity(0.75))
                            }
                        }
                    }

                    // Gelişim grafiği (geçmiş antrenman kayıtlarından)
                    ExerciseProgressChart(exerciseName: current.name)

                    // Teknik notlar
                    if let notesText = current.notes, !notesText.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Teknik Notlar").eyebrow()
                            Text(notesText)
                                .font(Typography.body)
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(Spacing.md)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .fill(Palette.surfaceElevated.opacity(0.5)))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 0.5))
                    }

                    // Varyasyonlar
                    if !current.variations.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Varyasyonlar").eyebrow()
                            FlowLayout(spacing: 6) {
                                ForEach(current.variations, id: \.self) { v in
                                    let linked = allExercises.first { $0.name == v }
                                    Button {
                                        if let target = linked {
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                                navigationStack.append(target)
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 4) {
                                            Text(v)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(linked != nil ? Palette.accent : Palette.textSecondary)
                                            if linked != nil {
                                                Image(systemName: "arrow.right")
                                                    .font(.system(size: 8, weight: .semibold))
                                                    .foregroundStyle(Palette.accent.opacity(0.7))
                                            }
                                        }
                                        .padding(.horizontal, 9).padding(.vertical, 5)
                                        .background(Capsule().fill(linked != nil ? Palette.accentSoft : Palette.surfaceElevated))
                                        .overlay(Capsule().strokeBorder(linked != nil ? Palette.accent.opacity(0.3) : Palette.border, lineWidth: 0.5))
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                    .disabled(linked == nil)
                                }
                            }
                        }
                    }

                    // Referans linki
                    if let rawURL = current.sourceURL, !rawURL.isEmpty, let url = URL(string: rawURL) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Referans").eyebrow()
                            Link(destination: url) {
                                HStack(spacing: 6) {
                                    Image(systemName: "link")
                                        .font(.system(size: 11, weight: .semibold))
                                    Text(rawURL)
                                        .font(Typography.caption)
                                        .lineLimit(1)
                                }
                                .foregroundStyle(Palette.accent)
                            }
                        }
                    }
                }
                .padding(Spacing.xl)
            }
        }
        .frame(width: 540, height: 680)
        .background(Palette.background)
    }

    private func muscleChips(label: String, muscles: [MuscleRegion], color: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.md) {
            Text(label)
                .font(Typography.captionBold)
                .foregroundStyle(color)
                .frame(width: 52, alignment: .trailing)
            FlowLayout(spacing: 6) {
                ForEach(muscles, id: \.rawValue) { muscle in
                    Text(muscle.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule().fill(color.opacity(0.15))
                        )
                        .overlay(
                            Capsule().strokeBorder(color.opacity(0.35), lineWidth: 0.5)
                        )
                }
            }
        }
    }
}

// MARK: - Exercise Form Sheet

enum ExerciseFormMode {
    case create
    case edit(Exercise)
}

struct ExerciseFormSheet: View {
    let mode: ExerciseFormMode
    let allExercises: [Exercise]   // varyasyon seçimi için kütüphane listesi
    let onSave: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String = ""
    @State private var equipment: Equipment = .barbell
    @State private var category: ExerciseCategory? = nil
    @State private var difficulty: Difficulty? = nil
    @State private var notes: String = ""
    @State private var sourceURL: String = ""
    @State private var variations: [String] = []
    @State private var showVariationPicker = false
    @State private var primaryMuscles: Set<MuscleRegion> = []
    @State private var secondaryMuscles: Set<MuscleRegion> = []

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !primaryMuscles.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Başlık
            HStack {
                Text(isEditing ? "Hareketi Düzenle" : "Yeni Hareket")
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(Spacing.xl)

            Divider().background(Palette.border)

            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.xl) {
                    // Ad + Ekipman
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Temel Bilgiler").eyebrow()

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Hareket Adı")
                                .font(Typography.captionBold)
                                .foregroundStyle(Palette.textSecondary)
                            TextField("örn. Bench Press", text: $name)
                                .font(Typography.body)
                                .textFieldStyle(.plain)
                                .padding(Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                        .fill(Palette.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                        .strokeBorder(Palette.border, lineWidth: 0.5)
                                )
                        }

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Ekipman")
                                .font(Typography.captionBold)
                                .foregroundStyle(Palette.textSecondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Equipment.allCases) { eq in
                                        equipmentChip(eq)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack {
                                Text("Hareket Tipi")
                                    .font(Typography.captionBold)
                                    .foregroundStyle(Palette.textSecondary)
                                Text("(isteğe bağlı)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.textQuaternary)
                            }
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(ExerciseCategory.allCases) { cat in
                                        categoryChip(cat)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }
                    .padding(Spacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(Palette.surface.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )

                    // Kas seçimi
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("Çalışılan Kaslar").eyebrow()
                            if primaryMuscles.isEmpty {
                                Text("· En az 1 birincil kas gerekli")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundStyle(Color.red.opacity(0.7))
                            }
                        }
                        Text("Kas bölgesine dokun: 1. tap birincil 🔴 · 2. tap ikincil 🟠 · 3. tap kaldır")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)

                        MuscleBodyDiagram(
                            primaryMuscles: $primaryMuscles,
                            secondaryMuscles: $secondaryMuscles
                        )
                    }
                    .padding(Spacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(Palette.surface.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )

                    // Detaylar
                    VStack(alignment: .leading, spacing: Spacing.md) {
                        Text("Detaylar").eyebrow()

                        // Zorluk seviyesi
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack {
                                Text("Zorluk Seviyesi")
                                    .font(Typography.captionBold)
                                    .foregroundStyle(Palette.textSecondary)
                                Text("(isteğe bağlı)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.textQuaternary)
                            }
                            HStack(spacing: 8) {
                                ForEach(Difficulty.allCases) { diff in
                                    difficultyChip(diff)
                                }
                            }
                        }

                        Hairline()

                        // Teknik notlar
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Teknik Notlar / Cue'lar")
                                .font(Typography.captionBold)
                                .foregroundStyle(Palette.textSecondary)
                            TextField(
                                "örn. Dirsekler içe, göğsü sıkıştır, nötr sırt...",
                                text: $notes,
                                axis: .vertical
                            )
                            .font(Typography.body)
                            .textFieldStyle(.plain)
                            .lineLimit(3...6)
                            .padding(Spacing.md)
                            .background(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .fill(Palette.surface)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                    .strokeBorder(Palette.border, lineWidth: 0.5)
                            )
                        }

                        Hairline()

                        // Referans linki
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            Text("Referans Linki")
                                .font(Typography.captionBold)
                                .foregroundStyle(Palette.textSecondary)
                            TextField("https://exrx.net/...", text: $sourceURL)
                                .font(Typography.body)
                                .textFieldStyle(.plain)
                                .textContentType(.URL)
                                .padding(Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                        .fill(Palette.surface)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                        .strokeBorder(Palette.border, lineWidth: 0.5)
                                )
                        }

                        Hairline()

                        // Varyasyonlar
                        VStack(alignment: .leading, spacing: Spacing.sm) {
                            HStack {
                                Text("Varyasyonlar")
                                    .font(Typography.captionBold)
                                    .foregroundStyle(Palette.textSecondary)
                                Text("(isteğe bağlı)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(Palette.textQuaternary)
                                Spacer()
                                Button {
                                    showVariationPicker = true
                                } label: {
                                    Label("Hareket Seç", systemImage: "plus")
                                        .font(Typography.captionBold)
                                        .foregroundStyle(Palette.accent)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }

                            if variations.isEmpty {
                                Text("Bu hareketin varyasyonlarını kütüphaneden seçerek ekle")
                                    .font(Typography.caption)
                                    .foregroundStyle(Palette.textQuaternary)
                            } else {
                                FlowLayout(spacing: 6) {
                                    ForEach(variations, id: \.self) { v in
                                        HStack(spacing: 4) {
                                            Text(v)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(Palette.textSecondary)
                                            Button {
                                                variations.removeAll { $0 == v }
                                            } label: {
                                                Image(systemName: "xmark")
                                                    .font(.system(size: 8, weight: .bold))
                                                    .foregroundStyle(Palette.textTertiary)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                        }
                                        .padding(.horizontal, 9).padding(.vertical, 5)
                                        .background(Capsule().fill(Palette.surfaceElevated))
                                        .overlay(Capsule().strokeBorder(Palette.border, lineWidth: 0.5))
                                    }
                                }
                            }
                        }
                        .sheet(isPresented: $showVariationPicker) {
                            VariationPickerSheet(
                                allExercises: allExercises,
                                currentName: { if case .edit(let ex) = mode { return ex.name } else { return name } }(),
                                selected: variations
                            ) { picked in
                                for p in picked where !variations.contains(p) {
                                    variations.append(p)
                                }
                            }
                        }
                    }
                    .padding(Spacing.lg)
                    .background(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .fill(Palette.surface.opacity(0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                            .strokeBorder(Palette.border, lineWidth: 0.5)
                    )
                }
                .padding(Spacing.xl)
            }

            Divider().background(Palette.border)

            // Kaydet butonu
            HStack {
                Spacer()
                Button("İptal") { dismiss() }
                    .font(Typography.body)
                    .foregroundStyle(Palette.textSecondary)
                    .buttonStyle(PlainButtonStyle())

                Button(isEditing ? "Kaydet" : "Ekle") {
                    save()
                }
                .font(Typography.bodyBold)
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(canSave ? Palette.accent : Palette.textTertiary)
                )
                .buttonStyle(PlainButtonStyle())
                .disabled(!canSave)
            }
            .padding(Spacing.xl)
        }
        .frame(width: 580, height: 740)
        .background(Palette.background)
        .onAppear { loadIfEditing() }
    }

    private func difficultyChip(_ diff: Difficulty) -> some View {
        let selected = difficulty == diff
        let accentColor: Color = diff == .beginner ? .green : (diff == .intermediate ? .orange : .red)
        return Button {
            difficulty = difficulty == diff ? nil : diff
        } label: {
            HStack(spacing: 6) {
                Image(systemName: diff.icon).font(.system(size: 11, weight: .semibold))
                Text(diff.label).font(Typography.captionBold)
            }
            .foregroundStyle(selected ? .white : Palette.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                    .fill(selected ? accentColor : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                    .strokeBorder(selected ? accentColor : Palette.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func categoryChip(_ cat: ExerciseCategory) -> some View {
        let selected = category == cat
        return Button {
            category = category == cat ? nil : cat
        } label: {
            HStack(spacing: 6) {
                Image(systemName: cat.icon).font(.system(size: 11, weight: .semibold))
                Text(cat.shortLabel).font(Typography.captionBold)
            }
            .foregroundStyle(selected ? .white : Palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                    .fill(selected ? Palette.accent : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                    .strokeBorder(selected ? Palette.accent : Palette.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func equipmentChip(_ eq: Equipment) -> some View {
        let selected = equipment == eq
        return Button { equipment = eq } label: {
            HStack(spacing: 6) {
                Image(systemName: eq.icon).font(.system(size: 11, weight: .semibold))
                Text(eq.label).font(Typography.captionBold)
            }
            .foregroundStyle(selected ? .white : Palette.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                    .fill(selected ? Palette.accent : Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                    .strokeBorder(selected ? Palette.accent : Palette.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func loadIfEditing() {
        if case .edit(let ex) = mode {
            name = ex.name
            equipment = ex.equipment
            category = ex.category
            difficulty = ex.difficulty
            notes = ex.notes ?? ""
            sourceURL = ex.sourceURL ?? ""
            variations = ex.variations
            primaryMuscles = Set(ex.primaryMuscles)
            secondaryMuscles = Set(ex.secondaryMuscles)
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !primaryMuscles.isEmpty else { return }

        switch mode {
        case .create:
            let ex = Exercise(
                name: trimmed,
                equipment: equipment,
                primaryMuscles: Array(primaryMuscles),
                secondaryMuscles: Array(secondaryMuscles),
                category: category,
                difficulty: difficulty,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceURL: sourceURL.trimmingCharacters(in: .whitespacesAndNewlines),
                variations: variations
            )
            onSave(ex)
        case .edit(let ex):
            ex.name = trimmed
            ex.equipment = equipment
            ex.primaryMuscles = Array(primaryMuscles)
            ex.secondaryMuscles = Array(secondaryMuscles)
            ex.category = category
            ex.difficulty = difficulty
            let nt = notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let su = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
            ex.notes = nt.isEmpty ? nil : nt
            ex.sourceURL = su.isEmpty ? nil : su
            ex.variations = variations
            onSave(ex)
        }
        dismiss()
    }
}

// MARK: - Variation Picker Sheet

private struct VariationPickerSheet: View {
    let allExercises: [Exercise]
    let currentName: String          // düzenlenen hareketin adı — listeden çıkarılır
    let selected: [String]           // zaten seçili olanlar
    let onAdd: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var pending: Set<String> = []

    private var available: [Exercise] {
        allExercises.filter { ex in
            ex.name != currentName &&
            !selected.contains(ex.name) &&
            (searchText.isEmpty || ex.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Başlık
            HStack {
                Text("Varyasyon Ekle")
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(Palette.textTertiary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(Spacing.xl)

            Divider()

            // Arama
            HStack(spacing: Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Palette.textTertiary)
                    .font(.system(size: 13))
                TextField("Hareket ara…", text: $searchText)
                    .font(Typography.body)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.md)

            Divider()

            // Liste
            if available.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Palette.textTertiary)
                    Text(searchText.isEmpty ? "Eklenecek hareket yok" : "Sonuç bulunamadı")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(available) { ex in
                    let isPending = pending.contains(ex.name)
                    Button {
                        if isPending { pending.remove(ex.name) }
                        else { pending.insert(ex.name) }
                    } label: {
                        HStack(spacing: Spacing.md) {
                            Image(systemName: isPending ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(isPending ? Palette.accent : Palette.textTertiary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(ex.name)
                                    .font(Typography.bodyBold)
                                    .foregroundStyle(Palette.textPrimary)
                                HStack(spacing: 4) {
                                    Text(ex.equipment.label)
                                        .font(Typography.caption)
                                        .foregroundStyle(Palette.textTertiary)
                                    if !ex.primaryMuscles.isEmpty {
                                        Text("·").foregroundStyle(Palette.textQuaternary)
                                        Text(ex.primaryMuscles.prefix(2).map(\.label).joined(separator: ", "))
                                            .font(Typography.caption)
                                            .foregroundStyle(Palette.textTertiary)
                                    }
                                }
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .listStyle(.plain)
            }

            Divider()

            // Alt butonlar
            HStack {
                if !pending.isEmpty {
                    Text("\(pending.count) seçildi")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Button("İptal") { dismiss() }
                    .foregroundStyle(Palette.textSecondary)
                    .buttonStyle(PlainButtonStyle())
                Button("Ekle") {
                    onAdd(Array(pending))
                    dismiss()
                }
                .font(Typography.bodyBold)
                .foregroundStyle(.white)
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(pending.isEmpty ? Palette.textTertiary : Palette.accent)
                )
                .buttonStyle(PlainButtonStyle())
                .disabled(pending.isEmpty)
            }
            .padding(Spacing.xl)
        }
        .frame(width: 480, height: 540)
        .background(Palette.background)
    }
}

// MARK: - Flow Layout (kas chip'leri için)

private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var height: CGFloat = 0
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                height += rowHeight + spacing
                x = 0; rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX; rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
