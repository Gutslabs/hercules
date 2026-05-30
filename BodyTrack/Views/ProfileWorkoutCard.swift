import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

struct WorkoutScheduleCard: View {
    @Environment(\.modelContext) private var ctx
    @Query(sort: \WorkoutSession.weekday) private var workouts: [WorkoutSession]
    @State private var editing: WorkoutSession? = nil

    private var totalCalories: Double {
        workouts.reduce(0) { $0 + $1.estimatedCalories }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.accent)
                    Text("Antrenman Programı").eyebrow()
                }
                Spacer()
                Text("\(workouts.count) gün · \(Fmt.int(totalCalories)) kcal/hafta")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            VStack(spacing: 1) {
                ForEach(1...7, id: \.self) { weekday in
                    WorkoutRow(
                        weekday: weekday,
                        workout: workouts.first(where: { $0.weekday == weekday })
                    ) { existing in
                        if let existing { editing = existing }
                        else {
                            let new = WorkoutSession(weekday: weekday, name: "Antrenman", estimatedCalories: 300)
                            ctx.insert(new)
                            try? ctx.save()
                            editing = new
                        }
                    } onDelete: { w in
                        ctx.delete(w)
                        try? ctx.save()
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
        .sheet(item: $editing) { w in
            WorkoutEditor(workout: w) {
                try? ctx.save()
                editing = nil
            }
        }
    }
}

struct WorkoutRow: View {
    let weekday: Int
    let workout: WorkoutSession?
    var onTap: (WorkoutSession?) -> Void
    var onDelete: (WorkoutSession) -> Void
    @State private var hovering = false

    private var isToday: Bool {
        Calendar.current.component(.weekday, from: Date()) == weekday
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(workout != nil ? Palette.surfaceElevated : Color.white.opacity(0.03))
                    .frame(width: 28, height: 28)
                if isToday {
                    Circle()
                        .strokeBorder(Palette.borderStrong, lineWidth: 1)
                        .frame(width: 28, height: 28)
                }
                Text(WorkoutSession.weekdayShortName(weekday))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(workout != nil || isToday ? Palette.textPrimary : Palette.textTertiary)
            }

            Text(WorkoutSession.weekdayName(weekday))
                .font(Typography.body)
                .foregroundStyle(workout != nil ? Palette.textPrimary : Palette.textTertiary)
                .frame(width: 90, alignment: .leading)

            if let w = workout {
                Text(w.name)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(Fmt.int(w.estimatedCalories)) kcal")
                    .font(Typography.mono)
                    .foregroundStyle(Palette.textSecondary)
                Button {
                    onDelete(w)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Palette.surfaceElevated))
                }
                .buttonStyle(.plain)
                .opacity(hovering ? 1 : 0)
            } else {
                Spacer(minLength: 0)
                Text(hovering ? "+ ekle" : "—")
                    .font(Typography.caption)
                    .foregroundStyle(hovering ? Palette.accent : Palette.textQuaternary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .background(
            RoundedRectangle(cornerRadius: Radius.sm - 2)
                .fill(hovering ? Color.white.opacity(0.025) : Color.clear)
        )
        .onHover { hovering = $0 }
        .onTapGesture { onTap(workout) }
    }
}

struct WorkoutEditor: View {
    @Bindable var workout: WorkoutSession
    var onDone: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var nameEdit: String = ""
    @State private var caloriesEdit: Double = 300

    var body: some View {
        NavigationStack {
            Form {
                Section(WorkoutSession.weekdayName(workout.weekday)) {
                    TextField("Antrenman", text: $nameEdit, prompt: Text("ör: Sırt + Göğüs"))
                    LabeledContent("Tahmini kcal") {
                        TextField("", value: $caloriesEdit, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Antrenman")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        workout.name = nameEdit.trimmingCharacters(in: .whitespaces)
                        workout.estimatedCalories = caloriesEdit
                        onDone()
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(width: 420, height: 260)
        .onAppear {
            nameEdit = workout.name
            caloriesEdit = workout.estimatedCalories
        }
    }
}

// MARK: - Activity sync card
