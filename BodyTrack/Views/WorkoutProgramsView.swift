import SwiftUI
import SwiftData

// MARK: - WorkoutProgramsView

struct WorkoutProgramsView: View {
    let exercises: [Exercise]
    let compact: Bool
    let expansive: Bool

    @Environment(\.modelContext) private var ctx
    @Query(sort: \TrainingProgram.createdAt, order: .reverse) private var programs: [TrainingProgram]

    @State private var viewingProgram: TrainingProgram? = nil
    @State private var buildingProgram: TrainingProgram? = nil
    @State private var isNewProgram = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Programlar")
                    .font(Typography.title)
                    .foregroundStyle(Palette.textPrimary)
                Spacer()
                Button {
                    let p = TrainingProgram(name: "Yeni Program")
                    ctx.insert(p)
                    let w = TrainingWeek(weekNumber: 1)
                    p.weeks.append(w)
                    ctx.insert(w)
                    for d in 1...7 {
                        let day = TrainingDay(dayNumber: d)
                        w.days.append(day)
                        ctx.insert(day)
                    }
                    try? ctx.save()
                    isNewProgram = true
                    buildingProgram = p
                } label: {
                    Label("Program Oluştur", systemImage: "plus")
                        .font(Typography.bodyBold)
                }
                .buttonStyle(.borderedProminent)
                .tint(Palette.accent)
            }
            .padding(.horizontal, compact ? Spacing.lg : (expansive ? 44 : Spacing.xxl))
            .padding(.vertical, Spacing.lg)

            if programs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Spacing.md) {
                        ForEach(programs) { program in
                            ProgramCard(program: program, exercises: exercises, onOpen: { viewingProgram = program }, onDelete: {
                                ctx.delete(program)
                                try? ctx.save()
                            })
                        }
                    }
                    .padding(.horizontal, compact ? Spacing.lg : (expansive ? 44 : Spacing.xxl))
                    .padding(.bottom, Spacing.xxl)
                }
            }
        }
        .sheet(item: $viewingProgram) { program in
            ProgramDetailView(program: program, exercises: exercises, onEdit: {
                viewingProgram = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    isNewProgram = false
                    buildingProgram = program
                }
            })
        }
        .sheet(item: $buildingProgram) { program in
            ProgramBuilderView(program: program, exercises: exercises, isNew: isNewProgram)
        }
    }

    private var emptyState: some View {
        VStack(spacing: Spacing.xl) {
            Spacer()
            VStack(spacing: Spacing.lg) {
                Image(systemName: "list.bullet.clipboard")
                    .font(.system(size: 48, weight: .ultraLight))
                    .foregroundStyle(Palette.textTertiary)
                VStack(spacing: 8) {
                    Text("Henüz Program Yok")
                        .font(Typography.title)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Kütüphanedeki hareketleri kullanarak antrenman programları oluştur.")
                        .font(Typography.body)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - ProgramMuscleHeat

/// Bir programın hareketlerinden kas bölgelerine düşen göreli yükü hesaplar.
/// Bloklar hareketi isimle tuttuğu için isim → Exercise eşlemesiyle kasları bulur.
struct ProgramMuscleHeat {
    /// Maks-normalize edilmiş bölge yoğunluğu (0...1) — gövde renklendirme için.
    let intensity: [MuscleRegion: Double]
    /// Kas grubuna göre pay (toplam ~1, azalan sıralı) — metinsel dağılım için.
    let groupShare: [(group: String, share: Double)]

    var isEmpty: Bool { intensity.isEmpty }

    static func compute(program: TrainingProgram, exercises: [Exercise]) -> ProgramMuscleHeat {
        var byName: [String: Exercise] = [:]
        for ex in exercises { byName[normalize(ex.name)] = ex }

        var raw: [MuscleRegion: Double] = [:]
        for week in program.weeks {
            for day in week.days where !day.isRestDay {
                for block in day.blocks where block.type == .exercise {
                    guard let name = block.exerciseName,
                          let ex = byName[normalize(name)] else { continue }
                    let sets = Double(block.sets ?? 3)
                    let primary = ex.primaryMuscles
                    for m in primary { raw[m, default: 0] += sets }
                    for m in ex.secondaryMuscles where !primary.contains(m) {
                        raw[m, default: 0] += sets * 0.5
                    }
                }
            }
        }

        guard let maxVal = raw.values.max(), maxVal > 0 else {
            return ProgramMuscleHeat(intensity: [:], groupShare: [])
        }
        let intensity = raw.mapValues { $0 / maxVal }

        var groupTotals: [String: Double] = [:]
        for (region, value) in raw { groupTotals[region.muscleGroup, default: 0] += value }
        let total = groupTotals.values.reduce(0, +)
        let groupShare = total > 0
            ? groupTotals.map { (group: $0.key, share: $0.value / total) }.sorted { $0.share > $1.share }
            : []

        return ProgramMuscleHeat(intensity: intensity, groupShare: groupShare)
    }

    private static func normalize(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - ProgramCard

private struct ProgramCard: View {
    let program: TrainingProgram
    let exercises: [Exercise]
    let onOpen: () -> Void
    let onDelete: () -> Void

    private var heat: ProgramMuscleHeat {
        ProgramMuscleHeat.compute(program: program, exercises: exercises)
    }

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: Spacing.lg) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: Spacing.sm) {
                        Text(program.name)
                            .font(Typography.bodyBold)
                            .foregroundStyle(Palette.textPrimary)
                        if program.isActive {
                            Text("AKTİF")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(Color.green))
                        }
                    }
                    HStack(spacing: Spacing.md) {
                        Label("\(program.weeks.count) hafta", systemImage: "calendar")
                        Label("\(program.activeDaysPerWeek) gün/hafta", systemImage: "figure.strengthtraining.traditional")
                    }
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textSecondary)

                    let groups = heat.groupShare.prefix(4)
                    if !groups.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(groups), id: \.group) { item in
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(MuscleHeat.color(item.share / (heat.groupShare.first?.share ?? 1)))
                                        .frame(width: 7, height: 7)
                                    Text("\(item.group) %\(Int((item.share * 100).rounded()))")
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundStyle(Palette.textSecondary)
                                }
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Capsule().fill(Palette.surfaceElevated))
                            }
                        }
                        .padding(.top, 2)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(Spacing.lg)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) { onDelete() } label: {
                Label("Sil", systemImage: "trash")
            }
        }
    }
}

// MARK: - ProgramDetailView

struct ProgramDetailView: View {
    let program: TrainingProgram
    let exercises: [Exercise]
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var ctx
    @State private var showActivate = false

    private let dayNames = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: Spacing.xl) {
                    activationBanner
                    heatSection
                    ForEach(program.sortedWeeks) { week in
                        WeekDetailSection(week: week, dayNames: dayNames)
                    }
                }
                .padding(.vertical, Spacing.lg)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle(program.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onEdit()
                    } label: {
                        Label("Düzenle", systemImage: "pencil")
                    }
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
        .sheet(isPresented: $showActivate) {
            ActivateProgramSheet(program: program) { startDate in
                activate(on: startDate)
            }
        }
    }

    @ViewBuilder private var activationBanner: some View {
        HStack(spacing: Spacing.md) {
            Image(systemName: program.isActive ? "checkmark.circle.fill" : "play.circle")
                .font(.system(size: 22))
                .foregroundStyle(program.isActive ? .green : Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                if program.isActive {
                    Text("Aktif Program")
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                    if let start = program.startDate {
                        Text("Başlangıç: \(start.formatted(date: .abbreviated, time: .omitted))")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                } else {
                    Text("Bu program aktif değil")
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                    Text("Aktif et, başlangıç tarihini seç ve takvimde takip et.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            Spacer()
            if program.isActive {
                Button("Pasifleştir") { deactivate() }
                    .buttonStyle(.bordered)
            } else {
                Button("Aktif Et") { showActivate = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Palette.accent)
            }
        }
        .padding(Spacing.lg)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
            program.isActive ? Color.green.opacity(0.4) : Palette.border, lineWidth: program.isActive ? 1 : 0.5))
        .padding(.horizontal, Spacing.lg)
    }

    @ViewBuilder private var heatSection: some View {
        let heat = ProgramMuscleHeat.compute(program: program, exercises: exercises)
        if !heat.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.md) {
                HStack {
                    Text("Kas Odağı")
                        .font(Typography.bodyBold)
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    HStack(spacing: 5) {
                        Text("az")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textTertiary)
                        LinearGradient(
                            colors: [MuscleHeat.color(0.05), MuscleHeat.color(0.5), MuscleHeat.color(1)],
                            startPoint: .leading, endPoint: .trailing
                        )
                        .frame(width: 60, height: 6)
                        .clipShape(Capsule())
                        Text("çok")
                            .font(.system(size: 9))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }

                MuscleHeatBody(intensities: heat.intensity)
                    .frame(maxWidth: 360)
                    .frame(maxWidth: .infinity)

                VStack(spacing: 6) {
                    ForEach(heat.groupShare.prefix(6), id: \.group) { item in
                        let relative = item.share / (heat.groupShare.first?.share ?? 1)
                        HStack(spacing: Spacing.sm) {
                            Text(item.group)
                                .font(Typography.caption)
                                .foregroundStyle(Palette.textSecondary)
                                .frame(width: 70, alignment: .leading)
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Palette.surfaceElevated)
                                    Capsule()
                                        .fill(MuscleHeat.color(relative))
                                        .frame(width: max(6, geo.size.width * relative))
                                }
                            }
                            .frame(height: 8)
                            Text("%\(Int((item.share * 100).rounded()))")
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Palette.textSecondary)
                                .frame(width: 38, alignment: .trailing)
                        }
                    }
                }
            }
            .padding(Spacing.lg)
            .background(RoundedRectangle(cornerRadius: 12).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.border, lineWidth: 0.5))
            .padding(.horizontal, Spacing.lg)
        }
    }

    private func activate(on startDate: Date) {
        // Tek aktif program: diğerlerini pasifleştir.
        let all = (try? ctx.fetch(FetchDescriptor<TrainingProgram>())) ?? []
        for p in all where p.persistentModelID != program.persistentModelID {
            p.isActive = false
        }
        program.isActive = true
        program.startDate = Calendar.current.startOfDay(for: startDate)
        try? ctx.save()
    }

    private func deactivate() {
        program.isActive = false
        try? ctx.save()
    }
}

// MARK: - ActivateProgramSheet

private struct ActivateProgramSheet: View {
    let program: TrainingProgram
    let onActivate: (Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var startDate: Date = .now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Başlangıç tarihi", selection: $startDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                } header: {
                    Text("\(program.name) ne zaman başlasın?")
                } footer: {
                    Text("\(program.weeks.count) haftalık program seçtiğin tarihten itibaren takvime yerleşir.")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .navigationTitle("Programı Aktif Et")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Aktif Et") {
                        onActivate(startDate)
                        dismiss()
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
    }
}

private struct WeekDetailSection: View {
    let week: TrainingWeek
    let dayNames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Hafta \(week.weekNumber)")
                .font(Typography.bodyBold)
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    ForEach(week.sortedDays) { day in
                        DayDetailColumn(day: day, dayNames: dayNames)
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
        }
    }
}

private struct DayDetailColumn: View {
    let day: TrainingDay
    let dayNames: [String]

    private var dayName: String { day.name?.isEmpty == false ? day.name! : dayNames[min(day.dayNumber - 1, 6)] }
    private let columnWidth: CGFloat = 130

    var body: some View {
        VStack(spacing: 0) {
            // Header
            Text(dayName)
                .font(Typography.captionBold)
                .foregroundStyle(Palette.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(Palette.surfaceElevated)

            Divider()

            if day.isRestDay {
                VStack(spacing: 4) {
                    Image(systemName: "moon.zzz")
                        .foregroundStyle(Palette.textTertiary)
                    Text("Dinlenme")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
                .padding(.vertical, Spacing.md)
            } else if day.sortedBlocks.isEmpty {
                Text("Boş")
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 60)
                    .padding(.vertical, Spacing.md)
            } else {
                VStack(spacing: 4) {
                    ForEach(day.sortedBlocks) { block in
                        BlockDetailRow(block: block)
                    }
                }
                .padding(6)
            }
        }
        .frame(width: columnWidth)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.border, lineWidth: 0.5))
    }
}

private struct BlockDetailRow: View {
    let block: TrainingBlock

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if block.type == .exercise {
                Text(block.exerciseName ?? "—")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text(block.summaryText)
                    if let rest = block.restSeconds {
                        Text("· \(TrainingBlock.formatSeconds(rest))")
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Palette.textSecondary)
                if let intensity = block.intensityText {
                    Text(intensity)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.accent.opacity(0.85))
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "timer")
                        .font(.system(size: 9))
                    Text(block.summaryText)
                        .font(.system(size: 10))
                }
                .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(block.type == .exercise ? Palette.accentSoft : Palette.surfaceElevated))
    }
}

// MARK: - ProgramBuilderView

struct ProgramBuilderView: View {
    let program: TrainingProgram
    let exercises: [Exercise]
    var isNew: Bool = false

    @Environment(\.modelContext) private var ctx
    @Environment(\.dismiss) private var dismiss

    @State private var programName: String = ""
    @State private var editingName = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Program name field
                HStack {
                    if editingName {
                        TextField("Program adı", text: $programName, onCommit: {
                            program.name = programName.isEmpty ? program.name : programName
                            try? ctx.save()
                            editingName = false
                        })
                        .textFieldStyle(.roundedBorder)
                        .font(Typography.bodyBold)
                    } else {
                        Text(program.name)
                            .font(Typography.bodyBold)
                            .foregroundStyle(Palette.textPrimary)
                            .onTapGesture { programName = program.name; editingName = true }
                        Image(systemName: "pencil")
                            .font(Typography.caption)
                            .foregroundStyle(Palette.textTertiary)
                            .onTapGesture { programName = program.name; editingName = true }
                    }
                    Spacer()
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.md)
                .background(Palette.surface)

                Divider()

                // Weeks scroll
                ScrollView(.vertical) {
                    LazyVStack(spacing: Spacing.xl) {
                        ForEach(program.sortedWeeks) { week in
                            WeekSection(week: week, exercises: exercises, onAddWeek: nil)
                        }
                        // Add Week button
                        Button {
                            addWeek()
                        } label: {
                            Label("Hafta Ekle", systemImage: "plus.circle")
                                .font(Typography.body)
                                .foregroundStyle(Palette.accent)
                                .padding(Spacing.lg)
                                .frame(maxWidth: .infinity)
                                .background(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.accent.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [6])))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, Spacing.lg)
                        .padding(.bottom, Spacing.xxl)
                    }
                    .padding(.top, Spacing.lg)
                }
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle(isNew ? "Yeni Program" : "Program Düzenle")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") {
                        if isNew { ctx.delete(program) }
                        try? ctx.save()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                }
            }
            .onAppear { programName = program.name }
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    private func addWeek() {
        let nextNum = (program.sortedWeeks.last?.weekNumber ?? 0) + 1
        let w = TrainingWeek(weekNumber: nextNum)
        program.weeks.append(w)
        ctx.insert(w)
        for d in 1...7 {
            let day = TrainingDay(dayNumber: d)
            w.days.append(day)
            ctx.insert(day)
        }
        try? ctx.save()
    }
}

// MARK: - WeekSection

private struct WeekSection: View {
    let week: TrainingWeek
    let exercises: [Exercise]
    let onAddWeek: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Hafta \(week.weekNumber)")
                .font(Typography.bodyBold)
                .foregroundStyle(Palette.textPrimary)
                .padding(.horizontal, Spacing.lg)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Spacing.md) {
                    ForEach(week.sortedDays) { day in
                        DayColumn(day: day, exercises: exercises)
                    }
                }
                .padding(.horizontal, Spacing.lg)
            }
        }
    }
}

// MARK: - DayColumn

private struct DayColumn: View {
    let day: TrainingDay
    let exercises: [Exercise]

    @Environment(\.modelContext) private var ctx

    // Add block dialog state
    @State private var showAddOptions = false
    @State private var showExercisePicker = false
    @State private var pendingBlock: TrainingBlock? = nil
    @State private var showSetsReps = false
    @State private var showRestPicker = false
    // Edit existing block
    @State private var editingBlock: TrainingBlock? = nil
    @State private var showEditSetsReps = false
    @State private var showEditRestPicker = false
    // Day name editing
    @State private var editingDayName = false
    @State private var dayNameDraft = ""

    private let defaultDayNames = ["Pzt", "Sal", "Çar", "Per", "Cum", "Cmt", "Paz"]
    private var dayName: String { day.name?.isEmpty == false ? day.name! : defaultDayNames[min(day.dayNumber - 1, 6)] }
    private let columnWidth: CGFloat = 130

    var body: some View {
        VStack(spacing: 0) {
            // Day header — tıklanabilir isim
            Group {
                if editingDayName {
                    TextField("Gün adı", text: $dayNameDraft, onCommit: {
                        day.name = dayNameDraft.trimmingCharacters(in: .whitespaces).isEmpty ? nil : dayNameDraft.trimmingCharacters(in: .whitespaces)
                        try? ctx.save()
                        editingDayName = false
                    })
                    .font(.system(size: 11, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .textFieldStyle(.plain)
                } else {
                    Text(dayName)
                        .font(Typography.captionBold)
                        .foregroundStyle(Palette.textSecondary)
                        .onTapGesture {
                            dayNameDraft = day.name ?? ""
                            editingDayName = true
                        }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(Palette.surfaceElevated)

            Divider()

            if day.isRestDay {
                // Rest day indicator
                VStack(spacing: 4) {
                    Image(systemName: "moon.zzz")
                        .foregroundStyle(Palette.textTertiary)
                    Text("Dinlenme")
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 60)
                .padding(.vertical, Spacing.md)
                .contentShape(Rectangle())
                .onTapGesture {
                    day.isRestDay = false
                    try? ctx.save()
                }
            } else {
                // Blocks
                VStack(spacing: 4) {
                    ForEach(day.sortedBlocks) { block in
                        BlockRow(block: block, onDelete: {
                            day.blocks.removeAll { $0.persistentModelID == block.persistentModelID }
                            ctx.delete(block)
                            try? ctx.save()
                        }, onEdit: {
                            editingBlock = block
                            if block.type == .exercise {
                                showEditSetsReps = true
                            } else {
                                showEditRestPicker = true
                            }
                        })
                    }

                    // Add button
                    Button {
                        showAddOptions = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.accent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Palette.accentSoft))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, day.sortedBlocks.isEmpty ? 0 : 2)
                }
                .padding(6)
            }
        }
        .frame(width: columnWidth)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.border, lineWidth: 0.5))
        // Add block dialog
        .confirmationDialog(
            day.isEmpty ? "Ne eklemek istersin?" : "Ne eklemek istersin?",
            isPresented: $showAddOptions,
            titleVisibility: .visible
        ) {
            Button("Hareket Ekle") { showExercisePicker = true }
            if day.isEmpty {
                Button("Dinlenme Günü") {
                    day.isRestDay = true
                    try? ctx.save()
                }
            } else {
                Button("Dinlenme Ekle") {
                    let order = (day.sortedBlocks.last?.order ?? 0) + 1
                    let block = TrainingBlock(order: order, type: .rest)
                    day.blocks.append(block)
                    ctx.insert(block)
                    pendingBlock = block
                    showRestPicker = true
                }
            }
            Button("İptal", role: .cancel) {}
        }
        .sheet(isPresented: $showExercisePicker) {
            ProgramExercisePickerSheet(exercises: exercises) { exName in
                let order = (day.sortedBlocks.last?.order ?? 0) + 1
                let block = TrainingBlock(order: order, type: .exercise, exerciseName: exName)
                day.blocks.append(block)
                ctx.insert(block)
                pendingBlock = block
                showExercisePicker = false
                showSetsReps = true
            }
        }
        .sheet(isPresented: $showSetsReps, onDismiss: { pendingBlock = nil }) {
            if let block = pendingBlock {
                SetsRepsSheet(block: block) {
                    try? ctx.save()
                }
            }
        }
        .sheet(isPresented: $showRestPicker, onDismiss: { pendingBlock = nil }) {
            if let block = pendingBlock {
                RestPickerSheet(block: block) {
                    try? ctx.save()
                }
            }
        }
        // Edit sheets
        .sheet(isPresented: $showEditSetsReps, onDismiss: { editingBlock = nil }) {
            if let block = editingBlock {
                SetsRepsSheet(block: block) {
                    try? ctx.save()
                }
            }
        }
        .sheet(isPresented: $showEditRestPicker, onDismiss: { editingBlock = nil }) {
            if let block = editingBlock {
                RestPickerSheet(block: block) {
                    try? ctx.save()
                }
            }
        }
    }
}

// MARK: - BlockRow

private struct BlockRow: View {
    let block: TrainingBlock
    let onDelete: () -> Void
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if block.type == .exercise {
                Text(block.exerciseName ?? "—")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    Text(block.summaryText)
                    if let rest = block.restSeconds {
                        Text("· \(TrainingBlock.formatSeconds(rest))")
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Palette.textSecondary)
                if let intensity = block.intensityText {
                    Text(intensity)
                        .font(.system(size: 9))
                        .foregroundStyle(Palette.accent.opacity(0.85))
                        .lineLimit(1)
                }
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "timer")
                        .font(.system(size: 9))
                    Text(block.summaryText)
                        .font(.system(size: 10))
                }
                .foregroundStyle(Palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 5).fill(block.type == .exercise ? Palette.accentSoft : Palette.surfaceElevated))
        .contentShape(Rectangle())
        .onTapGesture { onEdit() }
        .contextMenu {
            Button("Düzenle", action: onEdit)
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Kaldır", systemImage: "trash")
            }
        }
    }
}

// MARK: - ProgramExercisePickerSheet

struct ProgramExercisePickerSheet: View {
    let exercises: [Exercise]
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedCategory: ExerciseCategory? = nil

    /// Veride bulunan kategoriler (boş kategorileri filtrede gösterme)
    private var availableCategories: [ExerciseCategory] {
        let present = Set(exercises.compactMap(\.category))
        return ExerciseCategory.allCases.filter { present.contains($0) }
    }

    private var filtered: [Exercise] {
        exercises.filter { ex in
            let matchesCategory = selectedCategory == nil || ex.category == selectedCategory
            let matchesSearch = searchText.isEmpty || ex.name.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    /// Kas grubuna göre gruplanmış, alfabetik bölümler
    private var grouped: [(group: String, items: [Exercise])] {
        Dictionary(grouping: filtered) { $0.primaryMuscleGroup }
            .map { (group: $0.key, items: $0.value.sorted { $0.name < $1.name }) }
            .sorted { $0.group < $1.group }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryFilterBar

                if grouped.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(grouped, id: \.group) { section in
                            Section {
                                ForEach(section.items) { exercise in
                                    exerciseRow(exercise)
                                }
                            } header: {
                                Text(section.group)
                                    .font(Typography.captionBold)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .searchable(text: $searchText, prompt: "Hareket ara…")
            .navigationTitle("Hareket Seç")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
            }
        }
        .frame(minHeight: 460)
    }

    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                categoryChip(title: "Tümü", icon: "square.grid.2x2", category: nil)
                ForEach(availableCategories) { cat in
                    categoryChip(title: cat.shortLabel, icon: cat.icon, category: cat)
                }
            }
            .padding(.horizontal, Spacing.lg)
            .padding(.vertical, Spacing.sm)
        }
    }

    private func categoryChip(title: String, icon: String, category: ExerciseCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 11, weight: .semibold))
                Text(title).font(Typography.captionBold)
            }
            .foregroundStyle(isSelected ? Palette.accent : Palette.textSecondary)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(Capsule().fill(isSelected ? Palette.accentSoft : Palette.surfaceElevated))
            .overlay(Capsule().strokeBorder(isSelected ? Palette.accent.opacity(0.4) : Palette.border, lineWidth: 0.5))
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func exerciseRow(_ exercise: Exercise) -> some View {
        Button {
            onSelect(exercise.name)
        } label: {
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(Typography.body)
                        .foregroundStyle(Palette.textPrimary)
                    Text(exercise.primaryMuscles.map(\.label).joined(separator: ", "))
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer()
                Text(exercise.equipment.label)
                    .font(Typography.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
        }
        .listRowBackground(Palette.surface)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(Palette.textTertiary)
            Text("Sonuç bulunamadı")
                .font(Typography.body)
                .foregroundStyle(Palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - SetsRepsSheet

struct SetsRepsSheet: View {
    let block: TrainingBlock
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sets: String = ""
    @State private var reps: String = ""
    @State private var rest: String = ""
    @State private var load: String = ""
    @State private var rir: String = ""
    @State private var tempo: String = ""

    private let repPresets = ["5", "8", "10", "12", "15", "AMRAP"]
    private let setPresets = [1, 2, 3, 4, 5]
    private let restPresets: [(label: String, secs: Int)] = [
        ("30 sn", 30), ("1 dk", 60), ("90 sn", 90), ("2 dk", 120), ("3 dk", 180)
    ]
    private let rirPresets = ["0", "1", "2", "3"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Set Sayısı") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.md) {
                            ForEach(setPresets, id: \.self) { s in
                                Button("\(s)") { sets = "\(s)" }
                                    .buttonStyle(PresetButtonStyle(isSelected: sets == "\(s)"))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    TextField("Özel set sayısı", text: $sets)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }

                Section("Tekrar / Yoğunluk") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.md) {
                            ForEach(repPresets, id: \.self) { r in
                                Button(r) { reps = r }
                                    .buttonStyle(PresetButtonStyle(isSelected: reps == r))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    TextField("Özel (ör: 8-10)", text: $reps)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Setler Arası Dinlenme") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.md) {
                            ForEach(restPresets, id: \.secs) { p in
                                Button(p.label) { rest = "\(p.secs)" }
                                    .buttonStyle(PresetButtonStyle(isSelected: rest == "\(p.secs)"))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    TextField("Özel (saniye)", text: $rest)
                        .textFieldStyle(.roundedBorder)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }

                Section("Ağırlık / Şiddet") {
                    TextField("Ör: 60 kg, %75, RPE 8", text: $load)
                        .textFieldStyle(.roundedBorder)
                }

                Section("RIR (yedekteki tekrar)") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Spacing.md) {
                            ForEach(rirPresets, id: \.self) { r in
                                Button(r) { rir = r }
                                    .buttonStyle(PresetButtonStyle(isSelected: rir == r))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    TextField("Özel (ör: 1-2)", text: $rir)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Tempo") {
                    TextField("Ör: 3-1-1", text: $tempo)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .navigationTitle(block.exerciseName ?? "Hareket")
            
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        block.sets = Int(sets)
                        block.repsRaw = reps.isEmpty ? nil : reps
                        block.restSeconds = Int(rest)
                        block.load = load.trimmingCharacters(in: .whitespaces).isEmpty ? nil : load.trimmingCharacters(in: .whitespaces)
                        block.rir = rir.trimmingCharacters(in: .whitespaces).isEmpty ? nil : rir.trimmingCharacters(in: .whitespaces)
                        block.tempo = tempo.trimmingCharacters(in: .whitespaces).isEmpty ? nil : tempo.trimmingCharacters(in: .whitespaces)
                        onSave()
                        dismiss()
                    }
                    .disabled(sets.isEmpty || reps.isEmpty)
                }
            }
            .onAppear {
                sets = block.sets.map { "\($0)" } ?? ""
                reps = block.repsRaw ?? ""
                rest = block.restSeconds.map { "\($0)" } ?? ""
                load = block.load ?? ""
                rir = block.rir ?? ""
                tempo = block.tempo ?? ""
            }
        }
        .frame(minHeight: 340)
    }
}

// MARK: - RestPickerSheet

struct RestPickerSheet: View {
    let block: TrainingBlock
    let onSave: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var seconds: String = "60"

    private let presets: [(label: String, secs: Int)] = [
        ("30 sn", 30), ("1 dk", 60), ("90 sn", 90),
        ("2 dk", 120), ("3 dk", 180), ("5 dk", 300)
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Dinlenme Süresi") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: Spacing.md) {
                        ForEach(presets, id: \.secs) { preset in
                            Button(preset.label) {
                                seconds = "\(preset.secs)"
                            }
                            .buttonStyle(PresetButtonStyle(isSelected: seconds == "\(preset.secs)"))
                        }
                    }
                    HStack {
                        Text("Özel (saniye):")
                            .font(Typography.body)
                            .foregroundStyle(Palette.textSecondary)
                        TextField("60", text: $seconds)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }
            }
            .navigationTitle("Dinlenme Ekle")
            
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("İptal") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") {
                        block.restSeconds = Int(seconds) ?? 60
                        onSave()
                        dismiss()
                    }
                }
            }
            .onAppear {
                seconds = block.restSeconds.map { "\($0)" } ?? "60"
            }
        }
        .frame(minHeight: 300)
    }
}

// MARK: - PresetButtonStyle

private struct PresetButtonStyle: ButtonStyle {
    let isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Typography.captionBold)
            .foregroundStyle(isSelected ? .white : Palette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Palette.accent : Palette.surfaceElevated)
            )
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
