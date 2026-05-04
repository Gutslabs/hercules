import Foundation

enum Fmt {
    static let trNumber: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        f.minimumFractionDigits = 1
        return f
    }()

    static let trInt: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f
    }()

    static func num(_ v: Double, digits: Int = 1) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = digits
        f.minimumFractionDigits = digits
        return f.string(from: NSNumber(value: v)) ?? "—"
    }

    static func numOpt(_ v: Double?, digits: Int = 1) -> String {
        guard let v else { return "—" }
        return num(v, digits: digits)
    }

    static func int(_ v: Double) -> String {
        trInt.string(from: NSNumber(value: v.rounded())) ?? "—"
    }

    static func intOpt(_ v: Double?) -> String {
        guard let v else { return "—" }
        return int(v)
    }

    static let date: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM"
        return f
    }()

    static let dateLong: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM yyyy"
        return f
    }()

    static let dateMonthAxis: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMM"
        return f
    }()

    static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.unitsStyle = .full
        return f.localizedString(for: date, relativeTo: .now)
    }

    static func signed(_ v: Double, digits: Int = 1) -> String {
        let prefix = v > 0 ? "+" : ""
        return prefix + num(v, digits: digits)
    }
}
