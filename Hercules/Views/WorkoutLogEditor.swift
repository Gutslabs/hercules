import SwiftUI
import LucideKit
import SwiftData

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
        SheetChrome(
            eyebrow: "Antrenman",
            title: isEditing ? "Seansı Düzenle" : "Yeni Seans",
            size: .standard,
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                SheetSection("Antrenman") {
                    DatePicker("Tarih", selection: $date, displayedComponents: [.date])
                    TextField("Ad", text: $name, prompt: Text("ör: Sırt + Göğüs"))
                    LabeledContent("Süre (dk)") {
                        TextField("", value: $duration, format: .number)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    LabeledContent("Tahmini kcal") {
                        TextField("", value: $calories, format: .number)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                ForEach($exercises) { $draft in
                    SheetSection {
                        TextField("Hareket adı", text: $draft.name, prompt: Text("ör: Bench Press"))
                            .textFieldStyle(.plain)

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
                        ForEach($draft.sets) { $setDraft in
                            let setNum = (draft.sets.firstIndex(where: { $0.id == setDraft.id }) ?? 0) + 1
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
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                Button {
                                    let setId = setDraft.id
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        if draft.sets.count > 1 {
                                            draft.sets.removeAll { $0.id == setId }
                                        }
                                    }
                                } label: {
                                    Lucide(sf: "minus.circle.fill", size: 12)
                                        .foregroundStyle(draft.sets.count > 1 ? Palette.textTertiary : Palette.textQuaternary)
                                }
                                .buttonStyle(.borderless)
                                .frame(width: 24)
                                .disabled(draft.sets.count <= 1)
                            }
                        }

                        Button {
                            // Önceki setten reps/kg kopyala (pyramid kolaylığı)
                            let prev = draft.sets.last
                            draft.sets.append(DraftSet(
                                reps: prev?.reps ?? 10,
                                weight: prev?.weight
                            ))
                        } label: {
                            Label { Text("Set Ekle") } icon: { Lucide(sf: "plus.circle") }
                                .font(Typography.caption)
                        }
                        .buttonStyle(.borderless)

                        // Hareketi tamamen sil
                        Button(role: .destructive) {
                            exercises.removeAll { $0.id == draft.id }
                        } label: {
                            Label { Text("Hareketi Sil") } icon: { Lucide(sf: "trash") }
                                .font(Typography.caption)
                        }
                        .buttonStyle(.borderless)
                    } header: {
                        let num = (exercises.firstIndex(where: { $0.id == draft.id }) ?? 0) + 1
                        HStack {
                            Text(draft.name.isEmpty ? "Hareket \(num)" : draft.name)
                            Spacer()
                            Text(draft.previewSummary)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textTertiary)
                                .textCase(nil)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                }

                SheetSection {
                    SheetActionRow("Hareket Ekle", icon: "plus.circle.fill") {
                        exercises.append(DraftExercise(name: "", sets: [DraftSet()]))
                    }
                }

                SheetSection("Not") {
                    TextField("ör: pump iyiydi, son set zorlandım", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                if isEditing, let onDelete {
                    SheetSection {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label { Text("Seansı Sil") } icon: { Lucide(sf: "trash") }
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        } footer: {
            Spacer(minLength: 0)
            SheetSecondaryButton("İptal") { dismiss() }
            SheetPrimaryButton(isEditing ? "Kaydet" : "Ekle") {
                save()
                dismiss()
            }
        }
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

struct DraftExercise: Identifiable {
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

struct DraftSet: Identifiable {
    let id = UUID()
    var reps: Int = 10
    var weight: Double? = nil
}
