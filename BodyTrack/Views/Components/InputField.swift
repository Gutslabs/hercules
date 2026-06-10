import SwiftUI

struct LabeledNumberField: View {
    let label: String
    let unit: String
    @Binding var value: Double?
    var placeholder: String = "—"
    var step: Double = 0.1
    var range: ClosedRange<Double> = 0...500

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).eyebrow()
            HStack(spacing: 0) {
                TextField(
                    placeholder,
                    value: $value,
                    format: .number.precision(.fractionLength(0...2)).locale(Locale(identifier: "tr_TR"))
                )
                .textFieldStyle(.plain)
                .font(Typography.monoLarge)
                .foregroundStyle(Palette.textPrimary)
                .focused($focused)
                .multilineTextAlignment(.leading)
                Text(unit)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(focused ? Palette.borderStrong : Palette.border, lineWidth: 0.5)
            )
        }
    }
}

struct LabeledNumberFieldRequired: View {
    let label: String
    let unit: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...500

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).eyebrow()
            HStack(spacing: 0) {
                TextField(
                    "",
                    value: $value,
                    format: .number.precision(.fractionLength(0...2)).locale(Locale(identifier: "tr_TR"))
                )
                .textFieldStyle(.plain)
                .font(Typography.monoLarge)
                .foregroundStyle(Palette.textPrimary)
                .focused($focused)
                Text(unit)
                    .font(Typography.body)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(focused ? Palette.borderStrong : Palette.border, lineWidth: 0.5)
            )
        }
    }
}

struct SegmentedChoice<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options) { option in
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .font(Typography.bodyBold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(selection == option ? Palette.textPrimary : Palette.textSecondary)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm - 2, style: .continuous)
                                .fill(selection == option ? Palette.track : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .fill(Palette.surfaceElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                .strokeBorder(Palette.border, lineWidth: 0.5)
        )
    }
}

struct ChoiceRow<Option: Hashable & Identifiable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let label: (Option) -> String
    var detail: ((Option) -> String)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).eyebrow()
            VStack(spacing: 2) {
                ForEach(options) { option in
                    Button {
                        selection = option
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(label(option))
                                    .font(Typography.bodyBold)
                                    .foregroundStyle(selection == option ? Palette.textPrimary : Palette.textSecondary)
                                if let detail = detail?(option) {
                                    Text(detail)
                                        .font(Typography.caption)
                                        .foregroundStyle(Palette.textTertiary)
                                }
                            }
                            Spacer()
                            ZStack {
                                Circle()
                                    .strokeBorder(selection == option ? Palette.accent : Palette.borderStrong, lineWidth: 1)
                                    .frame(width: 14, height: 14)
                                if selection == option {
                                    Circle()
                                        .fill(Palette.accent)
                                        .frame(width: 7, height: 7)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .fill(selection == option ? Palette.fieldFill : Color.clear)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
        }
    }
}

struct StyledDateField: View {
    let label: String
    @Binding var date: Date
    var includesTime: Bool = true
    var range: ClosedRange<Date>? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).eyebrow()
            HStack(spacing: 8) {
                Image(systemName: includesTime ? "calendar.badge.clock" : "calendar")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Palette.accent)
                Group {
                    if let range {
                        DatePicker("", selection: $date, in: range,
                                   displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date])
                    } else {
                        DatePicker("", selection: $date,
                                   displayedComponents: includesTime ? [.date, .hourAndMinute] : [.date])
                    }
                }
                .datePickerStyle(.compact)
                .labelsHidden()
                .colorScheme(.dark)
                .tint(Palette.accent)
                .controlSize(.regular)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
        }
    }
}

struct PrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(Typography.bodyBold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(.black)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Color.white)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct GhostButton: View {
    let title: String
    var systemImage: String? = nil
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(title).font(Typography.bodyBold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 11)
            .foregroundStyle(Palette.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(Palette.surfaceElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: 0.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
