import SwiftUI
import SwiftData

struct CreateDate: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}

// MARK: - Workout design atoms

struct WorkoutHeaderSignal: View {
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

struct WorkoutHeaderDivider: View {
    var height: CGFloat = 38

    var body: some View {
        Rectangle()
            .fill(Palette.borderStrong)
            .frame(width: 0.5, height: height)
            .padding(.horizontal, Spacing.md)
    }
}

struct ProgramSummaryDatum: View {
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

struct WorkoutMiniButtonStyle: ButtonStyle {
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

struct WorkoutIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.16, dampingFraction: 0.72), value: configuration.isPressed)
    }
}

// MARK: - Active program board

struct WorkoutTermCard: View {
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

struct WorkoutProgramDayCard: View {
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

struct WorkoutProgramSessionEditor: View {
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

struct WorkoutProgramArchiveSheet: View {
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

struct WorkoutDayCell: View {
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
