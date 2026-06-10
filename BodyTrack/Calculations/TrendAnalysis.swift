import Foundation

struct TrendPoint: Identifiable, Hashable {
    let date: Date
    let value: Double

    var id: Int64 {
        Int64((date.timeIntervalSinceReferenceDate * 1000).rounded())
    }
}

struct LinearFit {
    let slope: Double
    let intercept: Double
    let stdError: Double
    let referenceDate: Date

    func value(at date: Date) -> Double {
        let x = date.timeIntervalSince(referenceDate) / 86_400
        return slope * x + intercept
    }
}

struct TrendStats {
    let current: Double?
    let previous: Double?
    let delta: Double?
    let percentDelta: Double?
    let weeklyChange: Double?
    let min: Double?
    let max: Double?
    let average: Double?
    let firstDate: Date?
    let lastDate: Date?
    let pointCount: Int

    var hasData: Bool { current != nil }
}

enum TrendAnalysis {
    static func points(_ measurements: [Measurement], for kind: MetricKind) -> [TrendPoint] {
        measurements
            .compactMap { m in
                guard let v = kind.value(from: m) else { return nil }
                return TrendPoint(date: m.date, value: v)
            }
            .sorted { $0.date < $1.date }
    }

    static func stats(_ points: [TrendPoint]) -> TrendStats {
        guard !points.isEmpty else {
            return TrendStats(
                current: nil, previous: nil, delta: nil, percentDelta: nil,
                weeklyChange: nil, min: nil, max: nil, average: nil,
                firstDate: nil, lastDate: nil, pointCount: 0
            )
        }
        let sorted = points.sorted { $0.date < $1.date }
        let current = sorted.last!.value
        let previous = sorted.count > 1 ? sorted[sorted.count - 2].value : nil
        let delta = previous.map { current - $0 }
        let percent = previous.map { ($0 == 0) ? 0 : ((current - $0) / $0) * 100 }

        let values = sorted.map(\.value)
        let mn = values.min()
        let mx = values.max()
        let avg = values.reduce(0, +) / Double(values.count)

        let weeklyChange: Double? = {
            guard sorted.count >= 2 else { return nil }
            let first = sorted.first!
            let last = sorted.last!
            let days = max(1, last.date.timeIntervalSince(first.date) / 86_400)
            let total = last.value - first.value
            return (total / days) * 7
        }()

        return TrendStats(
            current: current,
            previous: previous,
            delta: delta,
            percentDelta: percent,
            weeklyChange: weeklyChange,
            min: mn,
            max: mx,
            average: avg,
            firstDate: sorted.first?.date,
            lastDate: sorted.last?.date,
            pointCount: sorted.count
        )
    }

    /// Trailing time-windowed moving average ("trend weight").
    /// For each point, averages every sample within the preceding `windowDays`
    /// (inclusive of the point itself). Windows by *date*, not by sample count,
    /// so it stays correct when weigh-ins are irregular (some days skipped).
    /// Returns one smoothed point per input point, preserving original dates —
    /// this is what filters daily water-weight noise out of the weight flow.
    static func movingAverage(_ points: [TrendPoint], windowDays: Double) -> [TrendPoint] {
        guard windowDays > 0, points.count > 1 else { return points }
        let sorted = points.sorted { $0.date < $1.date }
        let window = windowDays * 86_400
        var result: [TrendPoint] = []
        result.reserveCapacity(sorted.count)
        // Kayan-pencere toplamı: her noktada iç döngüyle yeniden toplamak yerine (O(n·w)),
        // yeni noktayı ekleyip pencereden çıkanları düşerek toplamı O(1) güncelle → toplam O(n).
        var start = 0
        var runningSum = 0.0
        for i in sorted.indices {
            runningSum += sorted[i].value                    // pencere artık i'yi içeriyor
            let cutoff = sorted[i].date.addingTimeInterval(-window)
            while start < i && sorted[start].date < cutoff {
                runningSum -= sorted[start].value            // pencereden düşen noktaları çıkar
                start += 1
            }
            let avg = runningSum / Double(i - start + 1)
            result.append(TrendPoint(date: sorted[i].date, value: avg))
        }
        return result
    }

    /// Latest value of the trailing `windowDays` moving average — the smoothed
    /// reading anchored at the most recent weigh-in. nil when there is no data.
    static func movingAverageNow(_ points: [TrendPoint], windowDays: Double) -> Double? {
        guard !points.isEmpty else { return nil }
        let sorted = points.sorted { $0.date < $1.date }
        guard let last = sorted.last else { return nil }
        let cutoff = last.date.addingTimeInterval(-windowDays * 86_400)
        let recent = sorted.filter { $0.date >= cutoff }
        guard !recent.isEmpty else { return last.value }
        return recent.map(\.value).reduce(0, +) / Double(recent.count)
    }

    static func goalBand(
        from points: [TrendPoint],
        target: Double?,
        weeksAhead: Int = 12
    ) -> (start: TrendPoint, end: TrendPoint)? {
        guard let first = points.first else { return nil }
        let endDate = Calendar.current.date(
            byAdding: .day,
            value: weeksAhead * 7,
            to: points.last?.date ?? first.date
        ) ?? first.date
        let endValue = target ?? first.value
        return (
            TrendPoint(date: first.date, value: first.value),
            TrendPoint(date: endDate, value: endValue)
        )
    }

    static func linearFit(_ points: [TrendPoint]) -> LinearFit? {
        guard points.count >= 3 else { return nil }
        let sorted = points.sorted { $0.date < $1.date }
        let ref = sorted.first!.date
        let xs = sorted.map { $0.date.timeIntervalSince(ref) / 86_400 }
        let ys = sorted.map(\.value)
        let n = Double(sorted.count)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n

        var num = 0.0
        var den = 0.0
        for i in xs.indices {
            let dx = xs[i] - meanX
            num += dx * (ys[i] - meanY)
            den += dx * dx
        }
        guard den > 0 else { return nil }
        let slope = num / den
        let intercept = meanY - slope * meanX

        var ssRes = 0.0
        for i in xs.indices {
            let pred = slope * xs[i] + intercept
            let r = ys[i] - pred
            ssRes += r * r
        }
        let stdErr = sqrt(ssRes / max(1, n - 2))
        return LinearFit(slope: slope, intercept: intercept, stdError: stdErr, referenceDate: ref)
    }

    static func daysSinceLast(_ measurements: [Measurement]) -> Int? {
        guard let last = measurements.map(\.date).max() else { return nil }
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: last), to: cal.startOfDay(for: .now)).day ?? 0
        return max(0, days)
    }
}
