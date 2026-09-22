import SwiftUI
import LucideKit
import SwiftData

enum WorkoutEditorMode {
    /// `prefillFrom`: template / başka bir günden kopyalanacak log (örn. recurring workout).
    /// `program`: o günün program seansı — varsa form ondan dolar (hareketler + set sayısı),
    /// değerler her hareketin `history`deki son kaydından gelir.
    case create(date: Date, suggestedName: String, prefillFrom: WorkoutLog?, planOverrides: [WorkoutPlanOverride],
                program: WorkoutSession? = nil, history: [WorkoutLog] = [])
    case edit(WorkoutLog, program: WorkoutSession? = nil, history: [WorkoutLog] = [])
}

/// Antrenman kaydı penceresi — tasarım: "Hercules Mac Tasarımı" tuvali ▸ Antrenman · Yeni seans
/// V2 Odak. Üstte ad · tarih · süre · kalori; solda hareket listesi, sağda seçili hareketin setleri
/// (kg ve tekrar −/+ ya da yazarak), önceki kayıttaki değerler ve seans notu.
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
    @State private var selectedID: UUID?
    @State private var pickingDate = false
    /// Form programdan mı doldu (alt satırda söylenir).
    private let fromProgram: Bool

    init(mode: WorkoutEditorMode, onSave: @escaping (WorkoutLog) -> Void, onDelete: (() -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        var drafts: [DraftExercise]
        var usedProgram = false
        switch mode {
        case .create(let d, let sugg, let prefill, let planOverrides, let program, let history):
            _date = State(initialValue: d)
            if let program, !program.sortedTemplateExercises.isEmpty {
                usedProgram = true
                _name = State(initialValue: program.name)
                _duration = State(initialValue: program.durationMinutes)
                _calories = State(initialValue: program.estimatedCalories > 0 ? program.estimatedCalories : (prefill?.estimatedCalories ?? 300))
                _notes = State(initialValue: "")
                drafts = Self.programExercises(program, history: history, before: d)
                Self.appendOverrides(planOverrides, to: &drafts)
            } else {
                _name = State(initialValue: sugg)
                _duration = State(initialValue: prefill?.durationMinutes ?? 60)
                _calories = State(initialValue: prefill?.estimatedCalories ?? 300)
                _notes = State(initialValue: prefill?.notes ?? "")
                drafts = Self.logExercises(prefill, history: history, before: d)
                Self.appendOverrides(planOverrides, to: &drafts)
            }
        case .edit(let log, let program, let history):
            _date = State(initialValue: log.date)
            _name = State(initialValue: log.name)
            _duration = State(initialValue: log.durationMinutes)
            _calories = State(initialValue: log.estimatedCalories)
            _notes = State(initialValue: log.notes ?? "")
            drafts = Self.logExercises(log, history: history.filter { $0 !== log }, before: log.date)
            if let program {
                let targets = Dictionary(program.sortedTemplateExercises.map { (Self.key($0.name), Self.target($0)) },
                                         uniquingKeysWith: { first, _ in first })
                for i in drafts.indices { drafts[i].target = targets[Self.key(drafts[i].name)] }
            }
        }
        _exercises = State(initialValue: drafts)
        _selectedID = State(initialValue: drafts.first?.id)
        fromProgram = usedProgram
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    private var subtitle: String {
        let day = "\(Self.weekdayFormatter.string(from: date)) · \(Fmt.dayMonth.string(from: date))"
        return fromProgram ? "\(day) · programdan dolduruldu" : day
    }

    var body: some View {
        SadeSheet(title: isEditing ? "Seansı düzenle" : "Yeni seans", subtitle: subtitle, onClose: { dismiss() }) {
            VStack(spacing: 0) {
                metaRow
                    .padding(.horizontal, 28)
                    .padding(.top, 18)
                    .padding(.bottom, 20)
                SadeRule()
                HStack(spacing: 0) {
                    rail
                        .frame(width: 290)
                        .background(Palette.textPrimary.opacity(0.015))
                    SadeRule(vertical: true)
                    pane
                }
            }
        } footerLeading: {
            if isEditing, let onDelete {
                SadeButton(title: "Seansı sil", role: .destructive) {
                    onDelete()
                    dismiss()
                }
            }
            Text("\(exercises.count) hareket · \(exercises.reduce(0) { $0 + $1.sets.count }) set")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(Palette.textTertiary)
        } footerTrailing: {
            SadeButton(title: "İptal") { dismiss() }
            SadeButton(title: "Kaydet", role: .primary) {
                save()
                dismiss()
            }
        }
        .frame(width: 1000, height: 800)
    }

    // MARK: - Üst: ad · tarih · süre · kalori

    private var metaRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            SadeField(label: "Ad") {
                TextField("", text: $name, prompt: Text("ör: Pull · Sırt & Biceps").foregroundStyle(Palette.textTertiary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
            }
            SadeField(label: "Tarih") {
                Button { pickingDate = true } label: {
                    HStack {
                        Text(Fmt.dateLong.string(from: date))
                            .font(.system(size: 14).monospacedDigit())
                            .foregroundStyle(Palette.textPrimary)
                        Spacer(minLength: 4)
                        Lucide(sf: "calendar", size: 13)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $pickingDate, arrowEdge: .bottom) {
                    DatePicker("", selection: $date, displayedComponents: [.date])
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .padding(12)
                }
            }
            .frame(width: 180)
            SadeField(label: "Süre") {
                TextField("", value: $duration, format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14).monospacedDigit())
                    .fixedSize()
                Text("dk")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textTertiary)
                Spacer(minLength: 0)
            }
            .frame(width: 130)
            SadeField(label: "Kalori") {
                TextField("", value: $calories, format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14).monospacedDigit())
            }
            .frame(width: 130)
        }
    }

    // MARK: - Sol: hareketler

    private var rail: some View {
        ScrollView(.vertical) {
            VStack(spacing: 2) {
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    railRow(index: index, exercise: exercise)
                }
                SadeDashedButton(title: "Hareket ekle") {
                    let draft = DraftExercise(name: "", sets: [DraftSet()])
                    exercises.append(draft)
                    selectedID = draft.id
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func railRow(index: Int, exercise: DraftExercise) -> some View {
        let top = exercise.sets.compactMap(\.weight).max()
        return SadeRailRow(index: index, title: exercise.name,
                           meta: "\(exercise.sets.count) set" + (top.map { " · \(Self.kg($0)) kg" } ?? ""),
                           selected: exercise.id == selectedID) { selectedID = exercise.id }
            .contextMenu { exerciseMenuItems(exercise.id) }
    }

    // MARK: - Sağ: seçili hareket

    @ViewBuilder
    private var pane: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let index = exercises.firstIndex(where: { $0.id == selectedID }) {
                exercisePane($exercises[index])
            } else {
                Text("Soldan bir hareket seç ya da yeni hareket ekle.")
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            noteField
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 20)
    }

    private func exercisePane(_ exercise: Binding<DraftExercise>) -> some View {
        let id = exercise.wrappedValue.id
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("", text: exercise.name, prompt: Text("Hareket adı").foregroundStyle(Palette.textTertiary))
                        .textFieldStyle(.plain)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    HStack(spacing: 10) {
                        if let target = exercise.wrappedValue.target {
                            Text("hedef \(target)")
                                .font(.system(size: 12, weight: .medium).monospacedDigit())
                                .foregroundStyle(Palette.textTertiary)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 3)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Palette.textPrimary.opacity(0.05)))
                        }
                        if let last = exercise.wrappedValue.last {
                            Text("son · \(last)")
                                .font(.system(size: 12.5).monospacedDigit())
                                .foregroundStyle(Palette.textTertiary)
                        }
                    }
                    .lineLimit(1)
                }
                Spacer(minLength: 8)
                SadeMenuButton(help: "Hareket seçenekleri") { exerciseMenuItems(id) }
            }

            HStack(spacing: 12) {
                columnTitle("SET").frame(width: 52, alignment: .leading)
                columnTitle("KG").frame(width: 150, alignment: .leading)
                columnTitle("TEKRAR").frame(width: 150, alignment: .leading)
                columnTitle("ÖNCEKİ").frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 30, height: 1)
            }
            .padding(.top, 26)
            .padding(.bottom, 8)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                        setRow(number: index + 1, set: set, canDelete: exercise.wrappedValue.sets.count > 1) {
                            let setID = set.wrappedValue.id
                            withAnimation(.easeInOut(duration: 0.15)) {
                                exercise.wrappedValue.sets.removeAll { $0.id == setID }
                            }
                        }
                    }
                    Button {
                        // Önceki setten reps/kg kopyala (piramit kolaylığı)
                        let prev = exercise.wrappedValue.sets.last
                        exercise.wrappedValue.sets.append(DraftSet(reps: prev?.reps ?? 10, weight: prev?.weight))
                    } label: {
                        HStack(spacing: 7) {
                            Lucide(sf: "plus", size: 13)
                            Text("Set ekle")
                                .font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 9)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.textPrimary.opacity(0.05)))
                        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 12)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func columnTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Palette.textTertiary)
    }

    private func setRow(number: Int, set: Binding<DraftSet>, canDelete: Bool, onDelete: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Text("\(number)")
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Palette.textPrimary.opacity(0.06)))
                .frame(width: 52, alignment: .leading)
            SadeStepper(unit: "kg", width: 132) {
                if let w = set.wrappedValue.weight { set.wrappedValue.weight = w > 2.5 ? w - 2.5 : nil }
            } increment: {
                set.wrappedValue.weight = (set.wrappedValue.weight ?? 0) + 2.5
            } field: {
                TextField("", value: set.weight, format: .number, prompt: Text("BW").foregroundStyle(Palette.textTertiary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(width: 46)
            }
            .frame(width: 150, alignment: .leading)
            SadeStepper(width: 132) {
                set.wrappedValue.reps = max(1, set.wrappedValue.reps - 1)
            } increment: {
                set.wrappedValue.reps = min(100, set.wrappedValue.reps + 1)
            } field: {
                TextField("", value: set.reps, format: .number)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17, weight: .semibold).monospacedDigit())
                    .multilineTextAlignment(.center)
                    .frame(width: 40)
            }
            .frame(width: 150, alignment: .leading)
            Text(set.wrappedValue.previous ?? "—")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(Palette.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onDelete) {
                Lucide(sf: "minus.circle", size: 15)
                    .foregroundStyle(canDelete ? Palette.textTertiary : Palette.textQuaternary.opacity(0.5))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!canDelete)
            .help("Seti sil")
        }
        .padding(.vertical, 7)
    }

    @ViewBuilder
    private func exerciseMenuItems(_ id: UUID) -> some View {
        let index = exercises.firstIndex(where: { $0.id == id })
        Button("Yukarı taşı") { move(id, by: -1) }
            .disabled(index == nil || index == 0)
        Button("Aşağı taşı") { move(id, by: 1) }
            .disabled(index == nil || index == exercises.count - 1)
        Divider()
        Button("Hareketi sil", role: .destructive) { removeExercise(id) }
    }

    private var noteField: some View {
        SadeTextArea(label: "Seans notu", text: $notes, prompt: "ör. son sette zorlandım")
            .padding(.top, 16)
    }

    // MARK: - Düzenleme

    private func move(_ id: UUID, by step: Int) {
        guard let from = exercises.firstIndex(where: { $0.id == id }) else { return }
        let to = from + step
        guard exercises.indices.contains(to) else { return }
        withAnimation(.easeInOut(duration: 0.15)) { exercises.swapAt(from, to) }
    }

    private func removeExercise(_ id: UUID) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        exercises.remove(at: index)
        if selectedID == id {
            selectedID = exercises.indices.contains(index) ? exercises[index].id : exercises.last?.id
        }
    }

    // MARK: - Kaydet

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
        case .edit(let log, _, _):
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

    // MARK: - Doldurma

    /// Program seansının hareketleri; set sayısı programdan, kg/tekrar her hareketin son kaydından
    /// (yoksa programdaki yük ve tekrar aralığının alt ucu).
    private static func programExercises(_ program: WorkoutSession, history: [WorkoutLog], before date: Date) -> [DraftExercise] {
        program.sortedTemplateExercises.map { template in
            let last = lastEntry(named: template.name, in: history, before: date)
            let lastSets = last?.entry.sortedSets ?? []
            let count = max(1, template.sets ?? (lastSets.isEmpty ? 3 : lastSets.count))
            let sets = (0..<count).map { i -> DraftSet in
                if lastSets.indices.contains(i) {
                    let s = lastSets[i]
                    return DraftSet(reps: s.reps, weight: s.weight, previous: setText(s.weight, s.reps))
                }
                return DraftSet(reps: lowerReps(template.reps) ?? lastSets.last?.reps ?? 10,
                                weight: kgValue(template.load) ?? lastSets.last?.weight)
            }
            return DraftExercise(name: template.name, sets: sets, target: target(template),
                                 last: last.map { lastSummary($0.date, $0.entry) })
        }
    }

    /// Bir kaydın (şablon ya da düzenlenen) hareketleri; "önceki" değerler o hareketin daha eski kaydından.
    private static func logExercises(_ log: WorkoutLog?, history: [WorkoutLog], before date: Date) -> [DraftExercise] {
        guard let log else { return [] }
        return log.exercises.sorted { $0.order < $1.order }.map { entry in
            let last = lastEntry(named: entry.name, in: history, before: date)
            let lastSets = last?.entry.sortedSets ?? []
            return DraftExercise(
                name: entry.name,
                sets: entry.sortedSets.enumerated().map { i, s in
                    DraftSet(reps: s.reps, weight: s.weight,
                             previous: lastSets.indices.contains(i) ? setText(lastSets[i].weight, lastSets[i].reps) : nil)
                },
                last: last.map { lastSummary($0.date, $0.entry) }
            )
        }
    }

    private static func appendOverrides(_ planOverrides: [WorkoutPlanOverride], to drafts: inout [DraftExercise]) {
        var existing = Set(drafts.map { key($0.name) })
        for item in planOverrides {
            let k = key(item.exerciseName)
            guard !existing.contains(k) else { continue }
            let setCount = max(item.sets ?? 1, 1)
            let reps = item.reps ?? 10
            drafts.append(DraftExercise(
                name: item.exerciseName,
                sets: (0..<setCount).map { _ in DraftSet(reps: reps, weight: item.weight) },
                target: item.prescriptionText
            ))
            existing.insert(k)
        }
    }

    /// `name` hareketini içeren, `date` gününden önceki en yeni kayıt.
    private static func lastEntry(named name: String, in history: [WorkoutLog], before date: Date) -> (date: Date, entry: WorkoutExerciseEntry)? {
        let k = key(name)
        let dayStart = Calendar.current.startOfDay(for: date)
        for log in history.sorted(by: { $0.date > $1.date }) where log.date < dayStart {
            if let entry = log.exercises.first(where: { key($0.name) == k }), !entry.sortedSets.isEmpty {
                return (log.date, entry)
            }
        }
        return nil
    }

    static func key(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    /// "4 × 6–8 · 75 kg"
    private static func target(_ template: WorkoutTemplateExercise) -> String {
        var parts: [String] = []
        let reps = template.reps.map { $0.replacingOccurrences(of: "-", with: "–") }
        if let sets = template.sets, let reps, !reps.isEmpty { parts.append("\(sets) × \(reps)") }
        else if let sets = template.sets { parts.append("\(sets) set") }
        else if let reps, !reps.isEmpty { parts.append(reps) }
        if let load = template.load, !load.isEmpty { parts.append(load) }
        return parts.isEmpty ? "reçete yok" : parts.joined(separator: " · ")
    }

    private static func lastSummary(_ date: Date, _ entry: WorkoutExerciseEntry) -> String {
        ([Fmt.dateMonthAxis.string(from: date)] + entry.sortedSets.map { setText($0.weight, $0.reps) }).joined(separator: " · ")
    }

    private static func setText(_ weight: Double?, _ reps: Int) -> String {
        weight.map { "\(kg($0)) × \(reps)" } ?? "× \(reps)"
    }

    /// "6-8" → 6, "15" → 15, "AMRAP" → nil.
    private static func lowerReps(_ reps: String?) -> Int? {
        guard let reps else { return nil }
        let digits = reps.prefix { $0.isNumber }
        return Int(digits)
    }

    /// "75 kg", "@ 80 kg" → 75 / 80; kg içermeyen yük (vücut, km/s) → nil.
    private static func kgValue(_ load: String?) -> Double? {
        guard let load, load.lowercased().contains("kg") else { return nil }
        let number = load.replacingOccurrences(of: ",", with: ".")
            .components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
            .first { !$0.isEmpty && Double($0) != nil }
        return number.flatMap(Double.init)
    }

    static func kg(_ w: Double) -> String {
        w == w.rounded() ? "\(Int(w))" : Fmt.num(w, digits: 1)
    }

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "EEEE"
        return f
    }()
}

struct DraftExercise: Identifiable {
    let id = UUID()
    var name: String = ""
    var sets: [DraftSet] = [DraftSet()]
    /// Programdaki hedef ("4 × 6–8 · 75 kg"); yoksa nil.
    var target: String? = nil
    /// Hareketin son kaydı ("15 Eyl · 73 × 11 · 71 × 7 …"); yoksa nil.
    var last: String? = nil
}

struct DraftSet: Identifiable {
    let id = UUID()
    var reps: Int = 10
    var weight: Double? = nil
    /// Önceki kayıtta aynı sıradaki set ("73 × 11").
    var previous: String? = nil
}
