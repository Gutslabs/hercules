import SwiftUI
import SwiftData

struct CreateDate: Identifiable {
    let date: Date
    var id: TimeInterval { date.timeIntervalSince1970 }
}

// MARK: - Workout design atoms

/// V1 pill button — transparent, hairline border (Bugün / Arşivle / Arşiv).
struct WorkoutMiniButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .semibold))
            .foregroundStyle(isEnabled ? Palette.textSecondary : Palette.textQuaternary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(configuration.isPressed ? Palette.fieldFill : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.8)
            )
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
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

// MARK: - Aktif program day card (V1)

struct WorkoutProgramDayCard: View {
    let weekday: Int
    let session: WorkoutSession?
    let legacyOverrides: [WorkoutPlanOverride]
    let isHighlighted: Bool
    var accent: Color = Palette.accent
    var onEdit: () -> Void
    var onDelete: (WorkoutSession) -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Circle().fill(accent).frame(width: 6, height: 6)
                Text(WorkoutSession.weekdayName(weekday)).eyebrow()
                Spacer(minLength: 8)
                if let session {
                    iconAction(systemName: "pencil", help: "Planı düzenle", action: onEdit)
                        .opacity(hovering ? 1 : 0)
                    iconAction(systemName: "trash", help: "Bu günü aktif plandan kaldır") {
                        onDelete(session)
                    }
                    .opacity(hovering ? 1 : 0)
                    Text("\(session.durationMinutes) dk · \(session.sortedTemplateExercises.count) hareket")
                        .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(Palette.textQuaternary)
                        .lineLimit(1)
                } else {
                    iconAction(systemName: "plus", help: "Güne plan ekle", action: onEdit)
                }
            }

            Text(session?.name ?? "Serbest / Dinlenme")
                .font(.system(size: 15.5, weight: .bold))
                .foregroundStyle(session == nil ? Palette.textTertiary : Palette.textPrimary)
                .lineLimit(2)
                .padding(.top, 7)
                .padding(.bottom, 6)

            if let session {
                if let focus = session.focus, !focus.isEmpty {
                    Text(focus)
                        .font(Typography.caption)
                        .foregroundStyle(Palette.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 6)
                }

                let exercises = session.sortedTemplateExercises
                if exercises.isEmpty && legacyOverrides.isEmpty {
                    emptyLine("Hareket reçetesi yok")
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(exercises.enumerated()), id: \.offset) { index, exercise in
                            if index > 0 { Hairline() }
                            exerciseRow(number: index + 1, exercise: exercise)
                        }
                        ForEach(Array(legacyOverrides.enumerated()), id: \.offset) { index, override in
                            if index > 0 || !exercises.isEmpty { Hairline() }
                            overrideRow(override)
                        }
                    }
                }

                if let progression = session.progression, !progression.isEmpty {
                    Hairline().padding(.top, 4)
                    labelBlock("Progression", progression)
                        .padding(.top, 8)
                }
                if let notes = session.notes, !notes.isEmpty {
                    labelBlock("Not", notes)
                        .padding(.top, 8)
                }
            } else if !legacyOverrides.isEmpty {
                labelBlock("Eski AI eklemeleri", legacyOverrides.map { "+ \($0.exerciseName) · \($0.prescriptionText)" }.joined(separator: "\n"))
            } else {
                emptyLine("Plan yok")
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .dashboardCard()
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .strokeBorder(isHighlighted ? accent.opacity(0.65) : Color.clear, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .onTapGesture(perform: onEdit)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }

    private func iconAction(systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Palette.fieldFill))
        }
        .buttonStyle(WorkoutIconButtonStyle())
        .help(help)
    }

    private func exerciseRow(number: Int, exercise: WorkoutTemplateExercise) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Text("\(number)")
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(Palette.textQuaternary)
                .frame(width: 14, alignment: .leading)

            VStack(alignment: .leading, spacing: 2.5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(exercise.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    if let sourceURL = exercise.sourceURL,
                       let url = URL(string: sourceURL) {
                        Link(destination: url) {
                            Image(systemName: "link")
                                .font(.system(size: 8.5, weight: .bold))
                                .foregroundStyle(Palette.accent)
                                .frame(width: 16, height: 16)
                                .background(Circle().fill(Palette.accentSoft))
                        }
                        .buttonStyle(.plain)
                        .help("Hareket videosunu / kaynağını aç")
                    }

                    Spacer(minLength: 0)
                }

                Text(exercise.prescriptionText)
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8.5)
    }

    private func overrideRow(_ override: WorkoutPlanOverride) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            Text("+")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(Palette.positive)
                .frame(width: 14, alignment: .leading)
            VStack(alignment: .leading, spacing: 2.5) {
                Text(override.exerciseName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text("\(override.prescriptionText) · AI eklemesi")
                    .font(.system(size: 10.5, weight: .regular, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8.5)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(Typography.caption)
            .foregroundStyle(Palette.textQuaternary)
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .center)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.fieldFill.opacity(0.55))
            )
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

// MARK: - Day cell (V1 mini takvim — nokta kodlu, tekrar eden etiket yok)

struct WorkoutDayCell: View {
    let date: Date
    let inMonth: Bool
    let isToday: Bool
    let isSelected: Bool
    /// O gün için GERÇEK log var (template propagation değil).
    let logged: Bool
    /// Haftalık programda o weekday'e atanmış seans (varsa).
    let programName: String?
    let programMinutes: Int?
    let programColor: Color
    let onTap: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(Fmt.dayNumber.string(from: date))
                        .font(.system(size: 11.5, weight: isToday ? .bold : .semibold))
                        .monospacedDigit()
                        .foregroundStyle(isToday ? Palette.accent : Palette.textPrimary)
                    if isToday {
                        Text("BUGÜN")
                            .font(.system(size: 8, weight: .bold))
                            .tracking(0.8)
                            .foregroundStyle(Palette.accent)
                    }
                    Spacer(minLength: 0)
                    if logged {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Palette.positive)
                    }
                }

                Spacer(minLength: 0)

                if let programName {
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(programColor.opacity(0.85))
                            .frame(width: 3, height: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(programName)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(1)
                            if let programMinutes {
                                Text("\(programMinutes) dk")
                                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                                    .foregroundStyle(Palette.textQuaternary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .topLeading)
            // Çizgisiz: opak yüzey + hafif gölge; yalnız bugün/seçili mercan halka.
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Palette.background)
            )
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isToday ? Palette.accent.opacity(0.07) : (hovering ? Palette.surfaceElevated : Palette.surface))
                    .shadow(color: Palette.cardShadowTight, radius: 4, x: 0, y: 2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        isToday ? Palette.accent.opacity(0.5) : (isSelected ? Palette.accent.opacity(0.3) : .clear),
                        lineWidth: 1
                    )
            )
            .opacity(inMonth ? 1 : 0.32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: - Editor sheet

/// Program günü editörü — V1 sayfa-içi (popup değil). Üstte ‹ Antrenman geri kırması,
/// meta + Koç Notları kartları, kompakt hareket tablosu (yalnız seçili satır genişler).
struct WorkoutProgramSessionEditor: View {
    @Bindable var session: WorkoutSession
    var onDone: () -> Void
    var onCancel: () -> Void
    @Environment(\.modelContext) private var ctx

    @State private var name = ""
    @State private var duration = 60
    @State private var calories: Double = 0
    @State private var focus = ""
    @State private var warmup = ""
    @State private var progression = ""
    @State private var notes = ""
    @State private var exercises: [ProgramExerciseDraft] = []
    @State private var expandedID: UUID? = nil
    @State private var dirty = false
    @FocusState private var focusedField: Bool

    // Satır grid kolonları (header + satır + genişleme aynı hizayı kullanır).
    private let colNum: CGFloat = 20
    private let colSet: CGFloat = 52
    private let colRep: CGFloat = 70
    private let colRir: CGFloat = 56
    private let colRest: CGFloat = 92
    private let colLoad: CGFloat = 172
    private let colChevron: CGFloat = 24

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                metaCard
                notesCard
                exercisesCard
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 32)
            .frame(maxWidth: 1240, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Palette.background.ignoresSafeArea())
        .contentShape(Rectangle())
        .onTapGesture { focusedField = false }
        .onAppear(perform: load)
    }

    // MARK: - Header (‹ Antrenman + başlık + İptal/Kaydet)

    private var header: some View {
        HStack(alignment: .bottom, spacing: Spacing.lg) {
            VStack(alignment: .leading, spacing: 3) {
                Button(action: onCancel) {
                    HStack(spacing: 6) {
                        Text("‹ Antrenman")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(Palette.textTertiary)
                        Text("/").font(.system(size: 10)).foregroundStyle(Palette.textQuaternary)
                        Text("PROGRAM GÜNÜ")
                            .font(.system(size: 10, weight: .medium)).tracking(0.9)
                            .foregroundStyle(Palette.textQuaternary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Antrenman sayfasına dön")

                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("\(WorkoutSession.weekdayName(session.weekday)) — \(name.isEmpty ? "Program Günü" : name)")
                        .font(.system(size: 22, weight: .bold))
                        .tracking(-0.2)
                        .foregroundStyle(Palette.textPrimary)
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        Circle().fill(Palette.macroCarbs).frame(width: 5, height: 5)
                        Text("\(exercises.count) hareket · \(duration) dk")
                            .font(.system(size: 11.5))
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
            }
            Spacer(minLength: Spacing.lg)
            Button(action: onCancel) {
                Text("İptal")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, 18).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)

            Button {
                save(); onDone()
            } label: {
                Text("✓ Kaydet")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Palette.btnFg)
                    .padding(.horizontal, 20).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Palette.accent))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: - Meta (gün adı / süre / yakım)

    private var metaCard: some View {
        HStack(spacing: 28) {
            metaField("Gün adı", width: 280) {
                TextField("Upper A / Lower / Full Body", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textPrimary)
                    .onChange(of: name) { _, _ in dirty = true }
            }
            divider
            metaField("Süre", width: 70) {
                HStack(spacing: 3) {
                    TextField("", value: $duration, format: .number)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Palette.textPrimary)
                        .onChange(of: duration) { _, _ in dirty = true }
                    Text("dk").font(.system(size: 10.5)).foregroundStyle(Palette.textQuaternary)
                }
            }
            divider
            metaField("Yakım", width: 80) {
                HStack(spacing: 3) {
                    TextField("", value: $calories, format: .number)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(Palette.textPrimary)
                        .onChange(of: calories) { _, _ in dirty = true }
                    Text("kcal").font(.system(size: 10.5)).foregroundStyle(Palette.textQuaternary)
                }
            }
            Spacer(minLength: 0)
            Text(dirty ? "Değişiklikler kaydedilmedi" : "Tüm değişiklikler kayıtlı")
                .font(.system(size: 11))
                .foregroundStyle(dirty ? Palette.warning : Palette.textTertiary)
        }
        .padding(.horizontal, 28).padding(.vertical, 14)
        .dashboardCard()
    }

    private var divider: some View {
        Rectangle().fill(Palette.border).frame(width: 0.5, height: 22)
    }

    private func metaField<C: View>(_ label: String, width: CGFloat, @ViewBuilder field: () -> C) -> some View {
        HStack(spacing: 10) {
            Text(label).eyebrow()
            field()
                .padding(.horizontal, 10).padding(.vertical, 5)
                .frame(width: width, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        }
    }

    // MARK: - Koç Notları

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Koç Notları").eyebrow()
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 28),
                GridItem(.flexible(), spacing: 28)
            ], spacing: 10) {
                noteField("Günün amacı", text: $focus)
                noteField("Isınma", text: $warmup)
                noteField("Progression", text: $progression)
                noteField("Ek not", text: $notes)
            }
        }
        .padding(.horizontal, 28).padding(.top, 18).padding(.bottom, 16)
        .dashboardCard()
    }

    private func noteField(_ label: String, text: Binding<String>) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(Palette.textSecondary)
                .frame(width: 96, alignment: .leading)
            TextField("—", text: text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1...4)
                .focused($focusedField)
                .onChange(of: text.wrappedValue) { _, _ in dirty = true }
                .padding(.horizontal, 11).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.fieldFill))
                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
        }
    }

    // MARK: - Hareketler tablosu

    private var exercisesCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("Hareketler").eyebrow()
                Text("satıra tıkla → detay açılır")
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                Spacer(minLength: 0)
                Text("\(exercises.count) hareket")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 10)

            columnHeader
            Hairline()

            ForEach(Array(exercises.enumerated()), id: \.element.id) { idx, _ in
                exerciseRow(idx)
            }

            Hairline()
            Button {
                let draft = ProgramExerciseDraft(order: exercises.count)
                exercises.append(draft)
                expandedID = draft.id
                dirty = true
            } label: {
                HStack(spacing: 8) {
                    Text("+ Hareket ekle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                    Text("· isim yaz, gerisini AI reçeteden doldurur")
                        .font(.system(size: 10.5))
                        .foregroundStyle(Palette.textTertiary)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24).padding(.vertical, 11)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .dashboardCard()
    }

    private var columnHeader: some View {
        HStack(spacing: 12) {
            colCap("#", width: colNum, align: .leading)
            colCap("Hareket", width: nil, align: .leading)
            colCap("Set", width: colSet, align: .center)
            colCap("Tekrar", width: colRep, align: .center)
            colCap("RIR", width: colRir, align: .center)
            colCap("Dinlenme", width: colRest, align: .center)
            colCap("Yük / tempo", width: colLoad, align: .leading)
            Spacer().frame(width: colChevron)
        }
        .padding(.horizontal, 24).padding(.bottom, 8)
    }

    private func colCap(_ text: String, width: CGFloat?, align: Alignment) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium)).tracking(0.8).textCase(.uppercase)
            .foregroundStyle(Palette.textQuaternary)
            .frame(width: width, alignment: align)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: align)
    }

    @ViewBuilder
    private func exerciseRow(_ idx: Int) -> some View {
        let isOpen = exercises[idx].id == expandedID
        VStack(spacing: 0) {
            if idx > 0 { Hairline() }
            HStack(spacing: 12) {
                Text("\(idx + 1)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(Palette.textQuaternary)
                    .frame(width: colNum, alignment: .leading)

                // İsme tıkla → satırı aç/kapat
                Button {
                    expandedID = isOpen ? nil : exercises[idx].id
                } label: {
                    Text(exercises[idx].name.isEmpty ? "Yeni hareket" : exercises[idx].name)
                        .font(.system(size: 12.5, weight: isOpen ? .bold : .semibold))
                        .foregroundStyle(exercises[idx].name.isEmpty ? Palette.textTertiary : Palette.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                pill(setBinding(idx), width: colSet, align: .center)
                pill($exercises[idx].reps, width: colRep, align: .center)
                pill($exercises[idx].rir, width: colRir, align: .center)
                pill($exercises[idx].rest, width: colRest, align: .center)
                pill($exercises[idx].load, width: colLoad, align: .leading)

                Button {
                    expandedID = isOpen ? nil : exercises[idx].id
                } label: {
                    Image(systemName: isOpen ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Palette.textTertiary)
                        .frame(width: colChevron, height: 20)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 24).padding(.vertical, 9)

            if isOpen {
                exerciseDetail(idx)
            }
        }
        .background(isOpen ? Palette.fieldFill.opacity(0.6) : Color.clear)
    }

    private func exerciseDetail(_ idx: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Kaynak").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.textSecondary).frame(width: 70, alignment: .leading)
                TextField("https://exrx.net/...", text: $exercises[idx].sourceURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(Palette.macroCarbs)
                    .onChange(of: exercises[idx].sourceURL) { _, _ in dirty = true }
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Not").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.textSecondary).frame(width: 70, alignment: .leading)
                TextField("hareket notu", text: $exercises[idx].notes, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Palette.textSecondary)
                    .lineLimit(1...4)
                    .onChange(of: exercises[idx].notes) { _, _ in dirty = true }
            }
            HStack(spacing: 8) {
                detailButton("Hareketi sil", tint: Palette.negative) {
                    let id = exercises[idx].id
                    exercises.removeAll { $0.id == id }
                    if expandedID == id { expandedID = nil }
                    dirty = true
                }
                detailButton("Yukarı taşı", tint: Palette.textSecondary) { move(idx, by: -1) }
                    .disabled(idx == 0)
                detailButton("Aşağı taşı", tint: Palette.textSecondary) { move(idx, by: 1) }
                    .disabled(idx == exercises.count - 1)
                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
        .padding(.leading, 56).padding(.trailing, 24).padding(.top, 4).padding(.bottom, 14)
    }

    private func detailButton(_ title: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.horizontal, 12).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(tint.opacity(0.3), lineWidth: 1))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Düzenlenebilir mono pill (set/tekrar/rir/dinlenme/yük).
    private func pill(_ text: Binding<String>, width: CGFloat, align: TextAlignment) -> some View {
        TextField("", text: text)
            .textFieldStyle(.plain)
            .font(.system(size: 11.5, design: .monospaced))
            .multilineTextAlignment(align)
            .foregroundStyle(Palette.textPrimary)
            .onChange(of: text.wrappedValue) { _, _ in dirty = true }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .frame(width: width)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Palette.fieldFill))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
    }

    /// set Int? ↔ String köprüsü ("3 set" yerine sade sayı düzenlenir).
    private func setBinding(_ idx: Int) -> Binding<String> {
        Binding(
            get: { exercises[idx].sets.map(String.init) ?? "" },
            set: { exercises[idx].sets = Int($0.filter(\.isNumber)) }
        )
    }

    private func move(_ idx: Int, by offset: Int) {
        let target = idx + offset
        guard exercises.indices.contains(target) else { return }
        exercises.swapAt(idx, target)
        dirty = true
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
        session.name = clean(name) ?? WorkoutSession.weekdayName(session.weekday)
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
                        Text(archive.sessions.map { "\(WorkoutSession.weekdayShortName($0.weekday)) \($0.name)" }.joined(separator: " · "))
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
