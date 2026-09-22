import SwiftUI
import LucideKit
import SwiftData

/// Antrenman · V2 "Hafta": üstte haftanın 7 günü, altında seçili günün seansı ve sağda ayın
/// tutarlılığı + program eylemleri. Görünümler WorkoutWeek.swift'te; burada veri, seçim, kayıt /
/// program düzenleme sheet'leri ve arşiv mantığı.
struct WorkoutView: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \WorkoutLog.date, order: .reverse) private var logs: [WorkoutLog]
    @Query(sort: \WorkoutSession.weekday) private var templates: [WorkoutSession]
    @Query(sort: \WorkoutPlanOverride.createdAt) private var planOverrides: [WorkoutPlanOverride]
    @Query(sort: \WorkoutProgramArchive.archivedAt, order: .reverse) private var archivedPrograms: [WorkoutProgramArchive]

    /// Görünen haftanın pazartesisi.
    @State private var weekStart: Date = Self.monday(of: .now)
    @State private var selectedDay: Date = Calendar.current.startOfDay(for: .now)
    @State private var editing: WorkoutLog? = nil
    @State private var creatingForDate: Date? = nil
    @State private var creatingPrefill: WorkoutLog? = nil
    @State private var editingProgramSession: WorkoutSession? = nil
    @State private var showingArchives = false
    @State private var sessionPendingDelete: WorkoutSession?
    /// Program penceresinde "Günü kaldır" onaylandı; pencere kapanınca silinir.
    @State private var programDayToDelete: WorkoutSession?

    /// `initialDay`: sayfa bu gün seçili açılır (önizleme/test); nil → bugün.
    init(initialDay: Date? = nil) {
        let day = Calendar.current.startOfDay(for: initialDay ?? .now)
        _selectedDay = State(initialValue: day)
        _weekStart = State(initialValue: Self.monday(of: day))
    }

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
    /// Yeni kayıt açılırken hareketleri buradan önceden doldurulur.
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
        // Tüm alt görünümler tek dict precompute'unu paylaşır — render başına 1 scan.
        let exact = exactLogByDay
        return GeometryReader { geometry in
            ScrollView {
                content(size: geometry.size, exact: exact)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(DashboardBackground().ignoresSafeArea())
        // Program günü: "Antrenmanı kaydet" ile aynı pencere. Silme, pencere kapandıktan sonra
        // yapılır (açık pencere silinmiş modele dokunmasın).
        .sheet(item: $editingProgramSession, onDismiss: deletePendingProgramDay) { session in
            WorkoutProgramEditor(
                session: session,
                history: logs,
                onSave: { ctx.saveOrReport() },
                onDelete: isVisibleProgramSession(session) ? { programDayToDelete = session } : nil
            )
        }
        .sheet(item: $editing) { log in
            WorkoutLogEditor(mode: .edit(log, program: programSession(for: log.date), history: logs)) { _ in
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
                    planOverrides: overrides(for: wrap.date),
                    program: programSession(for: wrap.date),
                    history: logs
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

    // MARK: - Sayfa (pencereyi doldurma matematiği)

    /// Geniş pencere: hafta şeridi (250) + altta seçili gün | ay (tasarım ölçüsünde 922 | 547),
    /// pencereyi doldurur; kısa pencerede taban 900. Dar pencere: alt alta, sabit boylarla.
    @ViewBuilder
    private func content(size: CGSize, exact: [Date: WorkoutLog]) -> some View {
        let innerW = max(0, size.width - 48)
        let week = weekPanel(exact: exact)
        let day = dayPanel(exact: exact)
        let month = monthPanel(exact: exact)
        if innerW >= 980 {
            let innerH = max(size.height - 36, 900)
            let side = min(560, max(420, floor((innerW - 24) * 0.3724)))
            VStack(spacing: 24) {
                week.frame(height: 250)
                HStack(spacing: 24) {
                    day.frame(width: innerW - 24 - side)
                    month.frame(width: side)
                }
                .frame(height: innerH - 274)
            }
            .frame(width: innerW, height: innerH, alignment: .top)
        } else {
            VStack(spacing: 18) {
                week.frame(height: 250)
                day.frame(height: 760)
                month.frame(height: 796)
            }
            .frame(width: innerW)
        }
    }

    // MARK: - Hafta

    private func weekPanel(exact: [Date: WorkoutLog]) -> some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        let sessions = sessionByWeekday
        let days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: weekStart) }
        let items = days.map { date -> WorkoutWeekDay in
            let session = sessions[cal.component(.weekday, from: date)]
            let log = exact[date]
            let meta = session.map { "\($0.durationMinutes) dk · \($0.sortedTemplateExercises.count) hareket" }
                ?? log.map { "\($0.durationMinutes) dk · \($0.exercises.count) hareket" }
            return WorkoutWeekDay(date: date, status: status(for: date, exact: exact, sessions: sessions),
                                  title: session?.name ?? log?.name, meta: meta, isToday: date == today)
        }
        return WorkoutWeekPanel(
            days: items,
            selected: selectedDay,
            rangeLabel: Self.rangeLabel(days.first ?? weekStart, days.last ?? weekStart),
            done: items.filter { $0.status == .done }.count,
            planned: days.filter { sessions[cal.component(.weekday, from: $0)] != nil || exact[$0] != nil }.count,
            showsToday: weekStart != Self.monday(of: .now),
            onSelect: { selectedDay = cal.startOfDay(for: $0) },
            onShift: shiftWeek,
            onToday: {
                weekStart = Self.monday(of: .now)
                selectedDay = today
            }
        ) { date in
            dayMenu(for: date, exact: exact)
        }
    }

    @ViewBuilder
    private func dayMenu(for date: Date, exact: [Date: WorkoutLog]) -> some View {
        let weekday = Calendar.current.component(.weekday, from: date)
        if let log = exact[date] {
            Button("Kaydı düzenle") { editing = log }
        } else {
            Button("Antrenmanı kaydet") { selectedDay = date; addSessionForSelectedDay() }
        }
        Button(sessionByWeekday[weekday] == nil ? "Güne plan ekle" : "Planı düzenle") { editProgramSession(weekday) }
        if let session = templates.first(where: { $0.weekday == weekday }) {
            Button("Bu günü plandan kaldır", role: .destructive) { sessionPendingDelete = session }
        }
    }

    private func shiftWeek(_ step: Int) {
        let cal = Calendar.current
        guard let next = cal.date(byAdding: .day, value: 7 * step, to: weekStart) else { return }
        let offset = cal.dateComponents([.day], from: weekStart, to: selectedDay).day ?? 0
        weekStart = next
        selectedDay = cal.date(byAdding: .day, value: min(6, max(0, offset)), to: next) ?? next
    }

    // MARK: - Seçili gün

    private func dayPanel(exact: [Date: WorkoutLog]) -> some View {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: selectedDay)
        let session = sessionByWeekday[weekday]
        let log = exact[selectedDay]
        return WorkoutDayPanel(
            title: WorkoutSession.weekdayName(weekday),
            subtitle: cal.isDateInToday(selectedDay) ? "bugün" : Fmt.dayMonth.string(from: selectedDay),
            plan: log.map { loggedPlan($0, session: session) } ?? session.map { plannedPlan($0) }
        ) {
            HStack(spacing: 8) {
                if log == nil && session == nil {
                    WorkoutPanelButton(title: "Güne plan ekle", icon: "plus", help: "Bu haftanın gününe program ekle") {
                        editProgramSession(weekday)
                    }
                } else if session != nil {
                    WorkoutPanelButton(title: "Düzenle", icon: "pencil", help: "Bu günün programını düzenle") {
                        editProgramSession(weekday)
                    }
                }
                if let log {
                    WorkoutPanelButton(title: "Kaydı düzenle", icon: "pencil", primary: true, help: "Bu günün kaydını düzenle") {
                        editing = log
                    }
                } else {
                    WorkoutPanelButton(title: "Antrenmanı kaydet", icon: "plus", primary: true, help: "Bu güne antrenman kaydı ekle") {
                        addSessionForSelectedDay()
                    }
                }
            }
        }
    }

    /// Planlı gün: programdaki hareketler (hedef reçete) + her hareketin son en ağır seti.
    private func plannedPlan(_ session: WorkoutSession) -> WorkoutDayPlan {
        let cal = Calendar.current
        let dayEnd = cal.date(byAdding: .day, value: 1, to: selectedDay) ?? selectedDay
        var rows: [WorkoutDayRow] = session.sortedTemplateExercises.map { exercise in
            let last = lastTopSet(named: exercise.name, before: dayEnd)
            return WorkoutDayRow(
                id: 0,
                name: exercise.name,
                primary: Self.target(sets: exercise.sets, reps: exercise.reps),
                load: exercise.load,
                extra: [exercise.rir.flatMap { $0.isEmpty ? nil : "RIR \($0)" }, exercise.rest]
                    .compactMap { $0?.isEmpty == false ? $0 : nil }.joined(separator: " · "),
                best: last.map { (Self.kg($0.weight), $0.reps) },
                bestLabel: last.map { "son · \(Fmt.dateMonthAxis.string(from: $0.date))" },
                link: exercise.sourceURL.flatMap(URL.init(string:)),
                note: exercise.notes
            )
        }
        for override in planOverrides where override.weekday == session.weekday {
            rows.append(WorkoutDayRow(id: 0, name: override.exerciseName, primary: override.prescriptionText,
                                      load: nil, extra: "AI eklemesi", best: nil, bestLabel: nil, link: nil,
                                      note: override.note))
        }
        return WorkoutDayPlan(
            name: session.name,
            chips: ["\(session.durationMinutes) dk", "\(rows.count) hareket"],
            focus: session.focus,
            rows: Self.numbered(rows),
            notes: Self.notes(session)
        )
    }

    /// Kayıtlı gün: yapılan hareketler ve setleri ("81 × 12 · 80 × 8 …"), sağda o günün en ağır seti.
    private func loggedPlan(_ log: WorkoutLog, session: WorkoutSession?) -> WorkoutDayPlan {
        let rows = log.exercises.sorted { $0.order < $1.order }.map { entry -> WorkoutDayRow in
            let sets = entry.sortedSets
            let top = sets.filter { ($0.weight ?? 0) > 0 }.max { ($0.weight ?? 0, $0.reps) < ($1.weight ?? 0, $1.reps) }
            let text = sets.map { set in set.weight.map { "\(Self.number($0)) × \(set.reps)" } ?? "\(set.reps)" }
                .joined(separator: " · ")
            return WorkoutDayRow(
                id: 0,
                name: entry.name,
                primary: text.isEmpty ? "set yok" : text,
                load: nil,
                extra: sets.isEmpty ? nil : "\(sets.count) set",
                best: top.map { (Self.kg($0.weight ?? 0), $0.reps) },
                bestLabel: top == nil ? nil : "en ağır set",
                link: nil,
                note: nil
            )
        }
        var chips = ["\(log.durationMinutes) dk", "\(rows.count) hareket"]
        if log.estimatedCalories > 0 { chips.append("\(Fmt.int(log.estimatedCalories)) kalori") }
        var notes: [(label: String, text: String)] = []
        if let text = log.notes, !text.isEmpty { notes.append((label: "Not", text: text)) }
        if let session { notes += Self.notes(session).filter { $0.label == "Gelişim" } }
        return WorkoutDayPlan(
            name: log.name,
            chips: chips,
            focus: "kaydedildi",
            rows: Self.numbered(rows),
            notes: notes
        )
    }

    /// `name` hareketinin `before`dan önceki son kayıttaki en ağır seti.
    private func lastTopSet(named name: String, before: Date) -> (weight: Double, reps: Int, date: Date)? {
        let key = name.lowercased(with: Locale(identifier: "tr_TR"))
        for log in logs where log.date < before {
            guard let entry = log.exercises.first(where: { $0.name.lowercased(with: Locale(identifier: "tr_TR")) == key }) else { continue }
            let weighted = entry.sortedSets.filter { ($0.weight ?? 0) > 0 }
            if let top = weighted.max(by: { ($0.weight ?? 0, $0.reps) < ($1.weight ?? 0, $1.reps) }) {
                return (top.weight ?? 0, top.reps, log.date)
            }
        }
        return nil
    }

    // MARK: - Ay + program

    private func monthPanel(exact: [Date: WorkoutLog]) -> some View {
        let cal = Calendar.current
        let sessions = sessionByWeekday
        let month = cal.dateInterval(of: .month, for: selectedDay)
        let start = month?.start ?? selectedDay
        let count = cal.range(of: .day, in: .month, for: selectedDay)?.count ?? 30
        let days = (0..<count).compactMap { cal.date(byAdding: .day, value: $0, to: start) }
        let programDays = activeProgramWeekdays.compactMap { weekday in templates.first(where: { $0.weekday == weekday }) }
        let exercises = programDays.reduce(0) { $0 + $1.templateExercises.count } + planOverrides.count
        let minutes = programDays.reduce(0) { $0 + $1.durationMinutes }
        return WorkoutMonthPanel(
            monthTitle: Self.monthFormatter.string(from: start),
            count: days.filter { exact[$0] != nil }.count,
            days: days.map { (date: $0, status: status(for: $0, exact: exact, sessions: sessions)) },
            onSelect: { date in
                selectedDay = cal.startOfDay(for: date)
                weekStart = Self.monday(of: date)
            }
        ) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Program")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Text(activeProgramWeekdays.isEmpty
                         ? "aktif program yok"
                         : "\(activeProgramWeekdays.count) gün · \(exercises) hareket · \(minutes) dk/hafta")
                        .font(.system(size: 12.5))
                        .foregroundStyle(Palette.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    WorkoutPanelButton(title: "", icon: "plus", help: "Seçili güne program ekle") {
                        editProgramSession(Calendar.current.component(.weekday, from: selectedDay))
                    }
                    WorkoutPanelButton(title: "Arşivle", help: "Aktif programı arşive kaldır") { archiveActiveProgram() }
                        .disabled(activeProgramWeekdays.isEmpty)
                    WorkoutPanelButton(title: "Arşiv", help: "Arşivlenmiş programları aç") { showingArchives = true }
                        .disabled(archivedPrograms.isEmpty)
                }
            }
        }
    }

    // MARK: - Gün durumu

    /// Görünür program seansları, haftanın gününe göre.
    private var sessionByWeekday: [Int: WorkoutSession] {
        var dict: [Int: WorkoutSession] = [:]
        for session in templates where isVisibleProgramSession(session) && dict[session.weekday] == nil {
            dict[session.weekday] = session
        }
        return dict
    }

    private func status(for day: Date, exact: [Date: WorkoutLog], sessions: [Int: WorkoutSession]) -> WorkoutDayStatus {
        let cal = Calendar.current
        let key = cal.startOfDay(for: day)
        if exact[key] != nil { return .done }
        let weekday = cal.component(.weekday, from: key)
        guard sessions[weekday] != nil || planOverrides.contains(where: { $0.weekday == weekday }) else { return .rest }
        let today = cal.startOfDay(for: .now)
        if key == today { return .today }
        return key > today ? .planned : .missed
    }

    // MARK: - Program eylemleri

    /// Seçili güne antrenman ekle — kayıt varsa düzenlemeye açar, yoksa
    /// template'ten yeni kayıt oluşturur.
    private func addSessionForSelectedDay() {
        let eff = effectiveLog(for: selectedDay, exact: exactLogByDay, templates: templateLogByWeekday)
        if let exact = eff.log, !eff.isTemplate {
            editing = exact
        } else {
            creatingForDate = selectedDay
            creatingPrefill = eff.log  // template log varsa prefill
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

    private func deletePendingProgramDay() {
        guard let session = programDayToDelete else { return }
        programDayToDelete = nil
        ctx.delete(session)
        ctx.saveOrReport()
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

    // MARK: - Yardımcılar

    /// O günün görünür program seansı — kayıt penceresi hareketleri ve set sayılarını buradan doldurur.
    private func programSession(for day: Date) -> WorkoutSession? {
        sessionByWeekday[Calendar.current.component(.weekday, from: day)]
    }

    private func templateName(for day: Date) -> String? {
        let weekday = Calendar.current.component(.weekday, from: day)
        return templates.first(where: { $0.weekday == weekday })?.name
    }

    private func suggestedName(for day: Date) -> String {
        templateName(for: day) ?? "Antrenman"
    }

    /// "4 × 6–8", "3 set", "AMRAP".
    private static func target(sets: Int?, reps: String?) -> String {
        let reps = reps.map { $0.replacingOccurrences(of: "-", with: "–") }
        if let sets, let reps, !reps.isEmpty { return "\(sets) × \(reps)" }
        if let sets { return "\(sets) set" }
        if let reps, !reps.isEmpty { return reps }
        return "reçete yok"
    }

    private static func number(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : Fmt.num(value, digits: 1)
    }

    private static func kg(_ value: Double) -> String { "\(number(value)) kg" }

    private static func notes(_ session: WorkoutSession) -> [(label: String, text: String)] {
        var out: [(label: String, text: String)] = []
        if let warmup = session.warmup, !warmup.isEmpty { out.append(("Isınma", warmup)) }
        if let progression = session.progression, !progression.isEmpty { out.append(("Gelişim", progression)) }
        if out.count < 2, let notes = session.notes, !notes.isEmpty { out.append(("Not", notes)) }
        return out
    }

    private static func numbered(_ rows: [WorkoutDayRow]) -> [WorkoutDayRow] {
        rows.enumerated().map { index, row in
            WorkoutDayRow(id: index, name: row.name, primary: row.primary, load: row.load, extra: row.extra,
                          best: row.best, bestLabel: row.bestLabel, link: row.link, note: row.note)
        }
    }

    /// "21–27 Eylül" · ay dönümünde "29 Eyl – 5 Eki".
    private static func rangeLabel(_ first: Date, _ last: Date) -> String {
        let cal = Calendar.current
        if cal.isDate(first, equalTo: last, toGranularity: .month) {
            return "\(Fmt.dayNumber.string(from: first))–\(Fmt.dayMonth.string(from: last))"
        }
        return "\(Fmt.dateMonthAxis.string(from: first)) – \(Fmt.dateMonthAxis.string(from: last))"
    }

    fileprivate static func monday(of date: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    fileprivate static let orderedWeekdays: [Int] = [2, 3, 4, 5, 6, 7, 1]

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "LLLL"
        return f
    }()

    static let archiveDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM yyyy HH:mm"
        return f
    }()
}
