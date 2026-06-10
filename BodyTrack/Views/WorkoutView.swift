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
    @State private var sessionPendingDelete: WorkoutSession?

    private static let workoutTerms: [(term: String, detail: String)] = [
        ("RIR", "Reps in reserve. Set bitince tankta kaç temiz tekrar kaldı demek. RIR 2 = iki tekrar daha çıkarırdın."),
        ("4×6–10", "4 set yap. Her sette hedef tekrar aralığı 6 ile 10. Tüm setlerde üst banda yaklaşırsan ağırlık artır."),
        ("Rest 2–3 dk", "Setler arası dinlenme. Ana liftlerde performans düşmesin diye daha uzun, izolasyonda daha kısa olabilir."),
        ("Progression", "Zamanla yük, tekrar, set veya teknik kalite artırma planı. Programın gelişim kuralı burada yazıyor.")
    ]

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
            if let editorSession = editingProgramSession {
                // Sayfa-içi program günü editörü (popup değil) — geri ile geri dönülür.
                WorkoutProgramSessionEditor(
                    session: editorSession,
                    onDone: { ctx.saveOrReport(); editingProgramSession = nil },
                    onCancel: { editingProgramSession = nil }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            let compact = geometry.size.width < 1080

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(compact: compact)
                        tempoStrip(exact: exact, templatesByWeekday: tplsByWeekday, compact: compact)

                        if compact {
                            VStack(alignment: .leading, spacing: 16) {
                                calendarCard(exact: exact) { date in
                                    focusProgramDay(for: date, proxy: proxy)
                                }
                                nextSessionCard
                                termsCard
                            }
                        } else {
                            HStack(alignment: .top, spacing: 16) {
                                calendarCard(exact: exact) { date in
                                    focusProgramDay(for: date, proxy: proxy)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                VStack(spacing: 16) {
                                    nextSessionCard
                                    termsCard
                                        .frame(maxHeight: .infinity)
                                }
                                .frame(width: 420)
                                .frame(maxHeight: .infinity)
                            }
                            .fixedSize(horizontal: false, vertical: true)
                        }

                        programSection(compact: compact)
                            .id("active-program")
                    }
                    .padding(.horizontal, compact ? 20 : 40)
                    .padding(.vertical, compact ? 24 : 32)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            }
        }
        .toolbar {
            if editingProgramSession == nil {
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
        }
        .background(DashboardBackground().ignoresSafeArea())
        .sheet(item: $editing) { log in
            WorkoutLogEditor(mode: .edit(log)) { _ in
                ctx.saveOrReport()
            } onDelete: {
                ctx.delete(log)
                ctx.saveOrReport()
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
                ctx.saveOrReport()
            }
        }
        .sheet(isPresented: $showingArchives) {
            WorkoutProgramArchiveSheet(
                archives: archivedPrograms,
                onRestore: restoreArchivedProgram,
                onDelete: { archive in
                    ctx.delete(archive)
                    ctx.saveOrReport()
                }
            )
        }
        .confirmationDialog(
            "Bu antrenman günü silinsin mi?",
            isPresented: Binding(get: { sessionPendingDelete != nil }, set: { if !$0 { sessionPendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: sessionPendingDelete
        ) { session in
            Button("Sil", role: .destructive) {
                ctx.delete(session)
                ctx.saveOrReport()
                sessionPendingDelete = nil
            }
            Button("İptal", role: .cancel) { sessionPendingDelete = nil }
        } message: { session in
            Text("\(session.name) ve içindeki tüm hareketler silinir.")
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(compact: Bool) -> some View {
        if compact {
            VStack(alignment: .leading, spacing: 8) {
                headerTitle
                headerSignals
            }
        } else {
            HStack(alignment: .bottom) {
                headerTitle
                Spacer()
                headerSignals
            }
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Antrenman").eyebrow()
            Text("Seans Takvimi")
                .font(.system(size: 22, weight: .bold))
                .tracking(-0.2)
                .foregroundStyle(Palette.textPrimary)
            Text("Günlük log, aktif program ve teknik notlar tek yerde. Takvimden güne dokun, program kartına ak.")
                .font(Typography.caption)
                .foregroundStyle(Palette.textQuaternary)
                .frame(maxWidth: 560, alignment: .leading)
                .padding(.top, 2)
        }
    }

    private var headerSignals: some View {
        HStack(spacing: 18) {
            HStack(spacing: 7) {
                Circle().fill(Palette.positive).frame(width: 6, height: 6)
                Text("Aktif").eyebrow()
                Text("\(activeProgramWeekdays.count) gün")
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
            }
            HStack(spacing: 7) {
                Text("Arşiv").eyebrow()
                Text("\(archivedPrograms.count) plan")
                    .font(Typography.bodyBold)
                    .foregroundStyle(Palette.textPrimary)
            }
        }
    }

    // MARK: - Tempo strip

    private func tempoStrip(
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

        let cells: [(label: String, value: String, unit: String, sub: String)] = [
            ("Bu Hafta", "\(weekSessions)", "seans", "\(weekMin) dk · \(Fmt.int(weekKcal)) kcal"),
            ("Bu Ay", "\(monthSessions)", "seans", "\(monthMin) dk ay başından beri"),
            ("Son 30 Gün", "\(last30Sess)", "seans", String(format: "%.1f seans/hafta", Double(last30Sess) / (30.0 / 7.0))),
            ("Kayıt", "\(logs.count)", "log", "\(uniqueWeekdaysWithLog) gün/hafta temeli")
        ]

        return Group {
            if compact {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 18) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                        tempoCell(cell)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(cells.enumerated()), id: \.offset) { index, cell in
                        if index > 0 {
                            Rectangle()
                                .fill(Palette.border)
                                .frame(width: 0.5, height: 44)
                                .padding(.trailing, 24)
                        }
                        tempoCell(cell)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .dashboardCard(radius: 14)
    }

    private func tempoCell(_ cell: (label: String, value: String, unit: String, sub: String)) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(cell.label).eyebrow()
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(cell.value)
                    .font(.system(size: 24, weight: .bold))
                    .monospacedDigit()
                    .tracking(-0.4)
                    .foregroundStyle(Palette.textPrimary)
                    .contentTransition(.numericText())
                Text(cell.unit)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(Palette.textQuaternary)
            }
            Text(cell.sub)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Palette.textQuaternary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Haftanın kaç farklı gününde bir log var (template tabanı = haftalık tempo).
    private var uniqueWeekdaysWithLog: Int {
        let cal = Calendar.current
        let weekdays = Set(logs.map { cal.component(.weekday, from: $0.date) })
        return weekdays.count
    }

    // MARK: - Takvim

    private func calendarCard(
        exact: [Date: WorkoutLog],
        onSelectProgramDay: @escaping (Date) -> Void
    ) -> some View {
        let cal = Calendar.current
        let cols = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                navChevron("chevron.left") { jumpMonth(by: -1) }
                Text(Self.monthTitleFormatter.string(from: currentMonth))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                navChevron("chevron.right") { jumpMonth(by: 1) }
                Text("\(logsInCurrentMonth.count) seans yapıldı · ✓ loglandı")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
                Spacer()
                Button {
                    let today = cal.startOfDay(for: .now)
                    currentMonth = Self.startOfMonth(.now)
                    selectedDay = today
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Palette.accent).frame(width: 5, height: 5)
                        Text("Bugün")
                    }
                }
                .buttonStyle(WorkoutMiniButtonStyle())
                .help("Bugüne dön")
            }
            .padding(.bottom, 14)

            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(Self.weekdayHeaders, id: \.self) { wd in
                    Text(wd).eyebrow()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 9)
                }
            }
            .padding(.bottom, 6)

            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(monthGridDays(), id: \.self) { date in
                    let weekday = cal.component(.weekday, from: date)
                    let session = templates.first(where: { $0.weekday == weekday })
                    WorkoutDayCell(
                        date: date,
                        inMonth: cal.isDate(date, equalTo: currentMonth, toGranularity: .month),
                        isToday: cal.isDateInToday(date),
                        isSelected: cal.isDate(date, inSameDayAs: selectedDay),
                        logged: exact[cal.startOfDay(for: date)] != nil,
                        programName: session?.name,
                        programMinutes: session?.durationMinutes,
                        programColor: programColor(weekday)
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
        .padding(.horizontal, 26)
        .padding(.vertical, 22)
        .dashboardCard()
    }

    private func navChevron(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.textTertiary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(WorkoutIconButtonStyle())
    }

    // MARK: - Sıradaki seans

    private var nextSessionCard: some View {
        let next = nextProgramOccurrence()
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Sıradaki Seans").eyebrow()
                Spacer()
                if let next {
                    Text(relativeTag(next.offset))
                        .font(.system(size: 11, weight: .regular, design: .monospaced))
                        .foregroundStyle(Palette.textQuaternary)
                }
            }
            if let next {
                HStack(spacing: 10) {
                    Circle().fill(programColor(next.session.weekday)).frame(width: 6, height: 6)
                    Text(next.session.name)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                }
                .padding(.top, 10)
                Text("\(Self.nextSessionFormatter.string(from: next.date)) · \(next.session.durationMinutes) dk · \(next.session.sortedTemplateExercises.count) hareket")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
                    .padding(.top, 4)
            } else {
                Text("Aktif program günü yok. Bir güne plan ekleyerek başla.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .dashboardCard()
    }

    private func nextProgramOccurrence() -> (session: WorkoutSession, date: Date, offset: Int)? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let exact = exactLogByDay
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: today) else { continue }
            let wd = cal.component(.weekday, from: day)
            guard let session = templates.first(where: { $0.weekday == wd }),
                  isVisibleProgramSession(session) else { continue }
            // Bugünün seansı zaten loglandıysa bir sonrakine bak.
            if offset == 0, exact[day] != nil { continue }
            return (session, day, offset)
        }
        return nil
    }

    private func relativeTag(_ offset: Int) -> String {
        switch offset {
        case 0: return "bugün"
        case 1: return "yarın"
        default: return "\(offset) gün sonra"
        }
    }

    // MARK: - Terimler

    private var termsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Terimler").eyebrow()
                Text("AI plan yazarken aynı dili kullansın diye kısa referans.")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(2)
            }
            .padding(.bottom, 4)

            ForEach(Array(Self.workoutTerms.enumerated()), id: \.offset) { index, term in
                VStack(alignment: .leading, spacing: 0) {
                    if index > 0 { Hairline() }
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(term.term)
                            .font(.system(size: 11, weight: .regular, design: .monospaced))
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Palette.accent.opacity(0.09))
                            )
                            .fixedSize()
                        Text(term.detail)
                            .font(.system(size: 11.5, weight: .regular))
                            .foregroundStyle(Palette.textSecondary)
                            .lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 11)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.horizontal, 26)
        .padding(.vertical, 20)
        .dashboardCard()
    }

    // MARK: - Aktif program

    private func programSection(compact: Bool) -> some View {
        let programWeekdays = activeProgramWeekdays
        let activeDays = programWeekdays.compactMap { weekday in templates.first(where: { $0.weekday == weekday }) }
        let totalExercises = activeDays.reduce(0) { $0 + $1.templateExercises.count } + planOverrides.count
        let totalMinutes = activeDays.reduce(0) { $0 + $1.durationMinutes }
        let totalCalories = activeDays.reduce(0) { $0 + $1.estimatedCalories }
        let columnCount = compact ? 1 : max(1, min(3, programWeekdays.count))
        let columns = Array(
            repeating: GridItem(.flexible(), spacing: 16, alignment: .top),
            count: columnCount
        )

        return VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .lastTextBaseline, spacing: 14) {
                    programHeaderTitle(dayCount: programWeekdays.count, exerciseCount: totalExercises, totalMinutes: totalMinutes)
                    Spacer()
                    programMetaCells(totalMinutes: totalMinutes, totalCalories: totalCalories)
                    programActions(hasProgram: !programWeekdays.isEmpty)
                }
                VStack(alignment: .leading, spacing: 10) {
                    programHeaderTitle(dayCount: programWeekdays.count, exerciseCount: totalExercises, totalMinutes: totalMinutes)
                    HStack(spacing: 14) {
                        programMetaCells(totalMinutes: totalMinutes, totalCalories: totalCalories)
                        Spacer(minLength: 8)
                        programActions(hasProgram: !programWeekdays.isEmpty)
                    }
                }
            }

            if programWeekdays.isEmpty {
                Text("Aktif program yok. AI'dan yeni program yazmasını isteyebilir veya bir güne plan ekleyebilirsin.")
                    .font(Typography.body)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 92, alignment: .center)
                    .dashboardCard()
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 16) {
                    ForEach(programWeekdays, id: \.self) { weekday in
                        WorkoutProgramDayCard(
                            weekday: weekday,
                            session: templates.first(where: { $0.weekday == weekday }),
                            legacyOverrides: planOverrides.filter { $0.weekday == weekday },
                            isHighlighted: highlightedProgramWeekday == weekday,
                            accent: programColor(weekday)
                        ) {
                            editProgramSession(weekday)
                        } onDelete: { session in
                            sessionPendingDelete = session
                        }
                        .id("program-day-\(weekday)")
                    }
                }
            }
        }
    }

    private func programHeaderTitle(dayCount: Int, exerciseCount: Int, totalMinutes: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Aktif Program").eyebrow()
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Haftalık reçete")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                Text("\(dayCount) gün · \(exerciseCount) hareket · \(totalMinutes) dk/hafta")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textQuaternary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
    }

    private func programMetaCells(totalMinutes: Int, totalCalories: Double) -> some View {
        HStack(spacing: 14) {
            programMetaCell("Süre", "\(totalMinutes) dk")
            programMetaCell("Yakım", "\(Fmt.int(totalCalories)) kcal")
            programMetaCell("AI", "\(planOverrides.count) ekleme")
        }
    }

    private func programMetaCell(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label).eyebrow()
            Text(value)
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
        }
    }

    private func programActions(hasProgram: Bool) -> some View {
        HStack(spacing: 8) {
            Button("Arşivle") { archiveActiveProgram() }
                .buttonStyle(WorkoutMiniButtonStyle())
                .disabled(!hasProgram)
                .help("Aktif programı arşive kaldır")
            Button("Arşiv") { showingArchives = true }
                .buttonStyle(WorkoutMiniButtonStyle())
                .disabled(archivedPrograms.isEmpty)
                .help("Arşivlenmiş programları aç")
        }
    }

    /// Program günü rengi — gün sırasına göre sabit palet (Salı mercan, Perşembe adaçayı, Cumartesi amber).
    private func programColor(_ weekday: Int) -> Color {
        let palette: [Color] = [Palette.accent, Palette.positive, Palette.warning, Color(red: 0.62, green: 0.71, blue: 0.92)]
        guard let idx = activeProgramWeekdays.firstIndex(of: weekday) else { return Palette.textSecondary }
        return palette[idx % palette.count]
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
        ctx.saveOrReport()
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
        ctx.saveOrReport()
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
        ctx.saveOrReport()
        showingArchives = false
    }

    private func formatLoad(_ weight: Double?) -> String? {
        guard let weight else { return nil }
        return weight == weight.rounded() ? "@ \(Int(weight)) kg" : "@ \(String(format: "%.1f", weight)) kg"
    }

    // MARK: - Helpers

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

    fileprivate static let nextSessionFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "EEEE d MMMM"
        return f
    }()

    static let archiveDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM yyyy HH:mm"
        return f
    }()
}
