import SwiftUI
import LucideKit
import SwiftData

struct CreateDate: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}

// MARK: - Program günü penceresi

/// Program günü penceresi — "Antrenmanı kaydet"in açtığı pencereyle aynı (tuval ▸ Antrenman ·
/// Yeni seans V2 Odak): üstte ad · süre · kalori; solda günün notları ve hareketler, sağda seçili
/// hareketin reçetesi (set · tekrar · RIR · dinlenme · yük), kaynak linki ve notu.
struct WorkoutProgramEditor: View {
    let session: WorkoutSession
    let history: [WorkoutLog]
    var onSave: () -> Void
    /// Günü programdan kaldır (pencerede onaylandıktan sonra); nil → düğme yok.
    var onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx

    @State private var name: String
    @State private var duration: Int
    @State private var calories: Double
    @State private var focus: String
    @State private var warmup: String
    @State private var progression: String
    @State private var notes: String
    @State private var exercises: [ProgramExerciseDraft]
    @State private var selection: Selection?
    @State private var confirmingDelete = false
    private let weekdayName: String
    private let isNew: Bool

    private enum Selection: Hashable {
        case notes
        case exercise(UUID)
    }

    init(session: WorkoutSession, history: [WorkoutLog] = [], onSave: @escaping () -> Void, onDelete: (() -> Void)? = nil) {
        self.session = session
        self.history = history.sorted { $0.date > $1.date }
        self.onSave = onSave
        self.onDelete = onDelete
        let drafts = session.sortedTemplateExercises.map {
            ProgramExerciseDraft(name: $0.name, order: $0.order, sets: $0.sets, reps: $0.reps ?? "", load: $0.load ?? "",
                                 rir: $0.rir ?? "", rest: $0.rest ?? "", sourceURL: $0.sourceURL ?? "", notes: $0.notes ?? "")
        }
        // Varsayılan ad (gün adı) alanda boş görünür; boş kaydedilince yine gün adı olur.
        _name = State(initialValue: session.name == WorkoutSession.weekdayName(session.weekday) ? "" : session.name)
        _duration = State(initialValue: session.durationMinutes)
        _calories = State(initialValue: session.estimatedCalories)
        _focus = State(initialValue: session.focus ?? "")
        _warmup = State(initialValue: session.warmup ?? "")
        _progression = State(initialValue: session.progression ?? "")
        _notes = State(initialValue: session.notes ?? "")
        _exercises = State(initialValue: drafts)
        _selection = State(initialValue: drafts.first.map { .exercise($0.id) } ?? .notes)
        weekdayName = WorkoutSession.weekdayName(session.weekday)
        isNew = drafts.isEmpty
    }

    var body: some View {
        SadeSheet(title: isNew ? "Güne plan ekle" : "Programı düzenle", subtitle: "\(weekdayName) · her hafta", onClose: { dismiss() }) {
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
            if onDelete != nil {
                SadeButton(title: "Günü kaldır", role: .destructive) { confirmingDelete = true }
            }
            Text("\(exercises.count) hareket · \(exercises.reduce(0) { $0 + ($1.sets ?? 0) }) set")
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(Palette.textTertiary)
        } footerTrailing: {
            SadeButton(title: "İptal") { dismiss() }
            SadeButton(title: "Kaydet", role: .primary) {
                save()
                onSave()
                dismiss()
            }
        }
        .frame(width: 1000, height: 800)
        .confirmationDialog("Bu antrenman günü silinsin mi?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                onDelete?()
                dismiss()
            }
            Button("İptal", role: .cancel) {}
        } message: {
            Text("\(name.isEmpty ? weekdayName : name) ve içindeki tüm hareketler silinir.")
        }
    }

    // MARK: - Üst: ad · süre · kalori

    private var metaRow: some View {
        HStack(alignment: .bottom, spacing: 12) {
            SadeField(label: "Ad") {
                TextField("", text: $name, prompt: Text("ör: Push · Göğüs & Omuz").foregroundStyle(Palette.textTertiary))
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
            }
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

    // MARK: - Sol: günün notları + hareketler

    private var rail: some View {
        ScrollView(.vertical) {
            VStack(spacing: 2) {
                SadeRailRow(icon: "text.alignleft", title: "Günün notları", meta: notesSummary,
                            selected: selection == .notes) { selection = .notes }
                SadeRule()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                ForEach(Array(exercises.enumerated()), id: \.element.id) { index, exercise in
                    SadeRailRow(index: index, title: exercise.name, meta: Self.recipe(exercise),
                                selected: selection == .exercise(exercise.id)) { selection = .exercise(exercise.id) }
                        .contextMenu { exerciseMenuItems(exercise.id) }
                }
                SadeDashedButton(title: "Hareket ekle") {
                    let draft = ProgramExerciseDraft(order: exercises.count)
                    exercises.append(draft)
                    selection = .exercise(draft.id)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// Dolu not alanlarının adları ("amaç · ısınma"); hiçbiri yoksa "boş".
    private var notesSummary: String {
        let filled = [("amaç", focus), ("ısınma", warmup), ("gelişim", progression), ("not", notes)]
            .filter { !$0.1.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map(\.0)
        return filled.isEmpty ? "boş" : filled.joined(separator: " · ")
    }

    // MARK: - Sağ: seçili hareket ya da notlar

    private var pane: some View {
        Group {
            switch selection {
            case .notes:
                notesPane
            case .exercise(let id):
                if let index = exercises.firstIndex(where: { $0.id == id }) {
                    exercisePane($exercises[index])
                } else {
                    emptyPane
                }
            case nil:
                emptyPane
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyPane: some View {
        Text("Soldan bir hareket seç ya da yeni hareket ekle.")
            .font(.system(size: 13))
            .foregroundStyle(Palette.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func exercisePane(_ exercise: Binding<ProgramExerciseDraft>) -> some View {
        let id = exercise.wrappedValue.id
        let url = Self.link(exercise.wrappedValue.sourceURL)
        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("", text: exercise.name, prompt: Text("Hareket adı").foregroundStyle(Palette.textTertiary))
                            .textFieldStyle(.plain)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Palette.textPrimary)
                        Text(lastSummary(for: exercise.wrappedValue.name).map { "son · \($0)" } ?? "henüz kayıt yok")
                            .font(.system(size: 12.5).monospacedDigit())
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    SadeMenuButton(help: "Hareket seçenekleri") { exerciseMenuItems(id) }
                }

                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        fieldLabel("Set")
                        SadeStepper(width: 132) {
                            exercise.wrappedValue.sets = max(1, (exercise.wrappedValue.sets ?? 1) - 1)
                        } increment: {
                            exercise.wrappedValue.sets = min(20, (exercise.wrappedValue.sets ?? 0) + 1)
                        } field: {
                            TextField("", value: exercise.sets, format: .number, prompt: Text("–").foregroundStyle(Palette.textTertiary))
                                .textFieldStyle(.plain)
                                .font(.system(size: 17, weight: .semibold).monospacedDigit())
                                .multilineTextAlignment(.center)
                                .frame(width: 40)
                        }
                    }
                    textField("Tekrar", exercise.reps, prompt: "6–8").frame(width: 150)
                    textField("RIR", exercise.rir, prompt: "1–2").frame(width: 110)
                    textField("Dinlenme", exercise.rest, prompt: "2 dk").frame(width: 130)
                }
                .padding(.top, 26)

                HStack(alignment: .bottom, spacing: 12) {
                    textField("Yük / tempo", exercise.load, prompt: "ör: 80 kg · 3-1-1").frame(width: 294)
                    SadeField(label: "Kaynak") {
                        TextField("", text: exercise.sourceURL, prompt: Text("https://…").foregroundStyle(Palette.textTertiary))
                            .textFieldStyle(.plain)
                            .font(.system(size: 13.5))
                        if let url {
                            Link(destination: url) {
                                Lucide(sf: "arrow.up.right", size: 12)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            .help("Linki aç")
                        }
                    }
                }
                .padding(.top, 16)

                SadeTextArea(label: "Hareket notu", text: exercise.notes, prompt: "ör: dirsekler 45°, kontrollü iniş", lines: 2...4)
                    .padding(.top, 16)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var notesPane: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Günün notları")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .padding(.bottom, 6)
                SadeTextArea(label: "Günün amacı", text: $focus, prompt: "ör: ağır bas, teknik temiz")
                SadeTextArea(label: "Isınma", text: $warmup, prompt: "ör: 8 dk bisiklet + hareket hazırlığı")
                SadeTextArea(label: "Gelişim", text: $progression, prompt: "ör: üst set hedef tekrarı tutarsa +2,5 kg")
                SadeTextArea(label: "Ek not", text: $notes, prompt: "ör: süper set, deload haftası")
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(Palette.textTertiary)
    }

    private func textField(_ label: String, _ text: Binding<String>, prompt: String) -> some View {
        SadeField(label: label) {
            TextField("", text: text, prompt: Text(prompt).foregroundStyle(Palette.textTertiary))
                .textFieldStyle(.plain)
                .font(.system(size: 14).monospacedDigit())
        }
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
        if selection == .exercise(id) {
            let next = exercises.indices.contains(index) ? exercises[index] : exercises.last
            selection = next.map { .exercise($0.id) } ?? .notes
        }
    }

    // MARK: - Kaydet

    private func save() {
        session.name = clean(name) ?? weekdayName
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
        // Sync-merge: içerik (hareketler/detay) değişti → updatedAt'i bump'la ki autosave
        // sonrası diğer cihaz bu sürümü devralsın. Bump olmazsa iki cihaz aynı eski zaman
        // damgasıyla farklı içerik tutar ve merge (strict u > local) asla yakınsamaz.
        session.updatedAt = .now
    }

    private func clean(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Metinler

    /// Liste alt satırı: "3 × 4–6 · 100 kg"; reçete boşsa "reçete yok".
    private static func recipe(_ draft: ProgramExerciseDraft) -> String {
        var parts: [String] = []
        let reps = draft.reps.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "-", with: "–")
        if let sets = draft.sets, !reps.isEmpty { parts.append("\(sets) × \(reps)") }
        else if let sets = draft.sets { parts.append("\(sets) set") }
        else if !reps.isEmpty { parts.append(reps) }
        let load = draft.load.trimmingCharacters(in: .whitespaces)
        if !load.isEmpty { parts.append(load) }
        return parts.isEmpty ? "reçete yok" : parts.joined(separator: " · ")
    }

    /// Hareketin son kaydı: "26 May · 100 × 6 · 97,5 × 6".
    private func lastSummary(for name: String) -> String? {
        let key = WorkoutLogEditor.key(name)
        guard !key.isEmpty else { return nil }
        for log in history {
            guard let entry = log.exercises.first(where: { WorkoutLogEditor.key($0.name) == key }),
                  !entry.sortedSets.isEmpty else { continue }
            let sets = entry.sortedSets.map { set in set.weight.map { "\(WorkoutLogEditor.kg($0)) × \(set.reps)" } ?? "× \(set.reps)" }
            return ([Fmt.dateMonthAxis.string(from: log.date)] + sets).joined(separator: " · ")
        }
        return nil
    }

    /// Kaynak alanı → açılabilir link (şema yoksa https).
    private static func link(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let full = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: full), url.host != nil else { return nil }
        return url
    }
}

struct ProgramExerciseDraft: Identifiable {
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

/// Program arşivi — tasarım: tuval ▸ Pencereler · Veriler (az yazı). Her arşiv tek kart: ad, tarih,
/// haftanın hangi günleri dolu (üzerine gelince o günün adı), geri yükle ve sil (ikisi de onaylı:
/// geri yüklemek mevcut programın yerini alır).
struct WorkoutProgramArchiveSheet: View {
    let archives: [WorkoutProgramArchive]
    var onRestore: (WorkoutProgramArchive) -> Void
    var onDelete: (WorkoutProgramArchive) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var restoring: WorkoutProgramArchive?
    @State private var deleting: WorkoutProgramArchive?

    /// Pazartesiden başlayan hafta (WorkoutSession.weekday: 1 = Pazar).
    private static let week: [(weekday: Int, letter: String)] = [(2, "P"), (3, "S"), (4, "Ç"), (5, "P"), (6, "C"), (7, "C"), (1, "P")]

    var body: some View {
        SadeSheet(title: "Program arşivi", onClose: { dismiss() }) {
            Group {
                if archives.isEmpty {
                    Text("Arşiv boş")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else {
                    ScrollView {
                        VStack(spacing: 10) {
                            ForEach(archives) { archive in
                                card(archive)
                            }
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, 18)
                        .padding(.bottom, 28)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .frame(height: min(CGFloat(archives.count) * 74 + 36, 560))
                }
            }
        } footerLeading: {
            EmptyView()
        } footerTrailing: {
            EmptyView()
        }
        .frame(width: 640)
        .confirmationDialog("Mevcut program değiştirilsin mi?",
                            isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }),
                            titleVisibility: .visible, presenting: restoring) { archive in
            Button("Geri yükle") {
                onRestore(archive)
                restoring = nil
                dismiss()
            }
            Button("Vazgeç", role: .cancel) { restoring = nil }
        } message: { archive in
            Text("\(archive.title) etkin program olur; şimdiki program günleri ve plan eklemeleri silinir.")
        }
        .confirmationDialog("Arşiv silinsin mi?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { archive in
            Button("Sil", role: .destructive) {
                onDelete(archive)
                deleting = nil
            }
            Button("Vazgeç", role: .cancel) { deleting = nil }
        }
    }

    private func card(_ archive: WorkoutProgramArchive) -> some View {
        let sessions = archive.sessions
        let used = Dictionary(sessions.map { ($0.weekday, $0.name) }, uniquingKeysWith: { first, _ in first })
        return HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(archive.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text(Self.dateFormatter.string(from: archive.archivedAt))
                    .font(.system(size: 12.5).monospacedDigit())
                    .foregroundStyle(Palette.textTertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .help(archive.summary ?? "")
            HStack(spacing: 4) {
                ForEach(Array(Self.week.enumerated()), id: \.offset) { _, day in
                    let name = used[day.weekday]
                    Text(day.letter)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(name == nil ? Palette.textQuaternary : Palette.textPrimary)
                        .frame(width: 24, height: 24)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(name == nil ? Palette.textPrimary.opacity(0.035) : Palette.chart.opacity(0.16)))
                        .help(name.map { "\(WorkoutSession.weekdayShortName(day.weekday)) · \($0)" } ?? "")
                }
            }
            HStack(spacing: 6) {
                archiveButton("arrow.clockwise", help: "Geri yükle", tint: Palette.textSecondary) { restoring = archive }
                archiveButton("trash", help: "Sil", tint: Palette.negative) { deleting = archive }
            }
        }
        .padding(.leading, 18)
        .padding(.trailing, 14)
        .padding(.vertical, 14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.textPrimary.opacity(0.03)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.textPrimary.opacity(0.06), lineWidth: 1))
    }

    private func archiveButton(_ icon: String, help: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Lucide(sf: icon, size: 13)
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.textPrimary.opacity(0.05)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM yyyy"
        return f
    }()
}
