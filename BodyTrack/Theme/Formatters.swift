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

    // Per-digit cache so num()/signed()/numOpt() don't allocate a new
    // NumberFormatter on every call (these get hit dozens of times per render).
    private static let formatterLock = NSLock()
    private static var numFormatterCache: [Int: NumberFormatter] = [:]

    private static func numFormatter(digits: Int) -> NumberFormatter {
        formatterLock.lock()
        defer { formatterLock.unlock() }
        if let cached = numFormatterCache[digits] { return cached }
        let f = NumberFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.numberStyle = .decimal
        f.maximumFractionDigits = digits
        f.minimumFractionDigits = digits
        numFormatterCache[digits] = f
        return f
    }

    static func num(_ v: Double, digits: Int = 1) -> String {
        numFormatter(digits: digits).string(from: NSNumber(value: v)) ?? "—"
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

    /// Shared formatters used by per-row cell views (DayCell/WorkoutDayCell/etc).
    /// Hoisted here so a 42-cell calendar grid doesn't allocate 42 formatters per render.
    static let dayNumber: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d"
        return f
    }()

    static let timeShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "HH:mm"
        return f
    }()

    static let monthShort: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "MMM"
        return f
    }()

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.unitsStyle = .full
        return f
    }()

    static func relative(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: .now)
    }

    static func signed(_ v: Double, digits: Int = 1) -> String {
        let prefix = v > 0 ? "+" : ""
        return prefix + num(v, digits: digits)
    }
}
