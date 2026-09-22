import SwiftUI
import SwiftData

/// Grafikler · V1 "İzleme listesi": solda seçili ölçümün büyük grafiği, sağda izleme listesi.
/// Görünümler ChartsWatchlist.swift'te; burada veri toplama, seçim ve pencereyi doldurma.
struct ChartsView: View {
    @Query(sort: \Measurement.date) private var measurements: [Measurement]
    @Query private var profiles: [UserProfile]
    @Query(sort: \FoodEntry.date) private var foods: [FoodEntry]
    @Query(sort: \StepEntry.date) private var stepEntries: [StepEntry]

    private let initialSelection: GraphMetric
    /// Önizleme/test kancası: grafiği bu günde imleç varmış gibi çizer (nil → normal hâl).
    private let scrubPreview: Date?

    init(selected: GraphMetric = .body(.weight), scrubPreview: Date? = nil) {
        self.initialSelection = selected
        self.scrubPreview = scrubPreview
    }

    /// Kilo verme ve korumada düşüş olumlu; yalnız kütle alma hedefinde artış.
    private var weightLowerIsBetter: Bool { (profiles.first?.goal.calorieAdjustment ?? 0) <= 0 }

    var body: some View {
        // SwiftData fields stay observed here. Selection/range/hover state belongs
        // to child views, so interacting with a chart cannot rescan the store.
        ChartsRangeContent(
            sources: GraphSources(measurements: measurements, foods: foods, steps: stepEntries),
            weightLowerIsBetter: weightLowerIsBetter,
            initialSelection: initialSelection,
            scrubPreview: scrubPreview
        )
    }
}

private struct ChartsRangeContent: View {
    let sources: GraphSources
    let weightLowerIsBetter: Bool
    let initialSelection: GraphMetric
    let scrubPreview: Date?
    @State private var span: GraphSpan = .all

    var body: some View {
        let bodyRows = GraphMetric.bodyMetrics.map {
            ($0, sources.series($0, span: span, weightLowerIsBetter: weightLowerIsBetter))
        }
        let dailyRows = GraphMetric.dailyMetrics.map {
            ($0, sources.series($0, span: span, weightLowerIsBetter: weightLowerIsBetter))
        }
        ChartsSelectionContent(bodyRows: bodyRows, dailyRows: dailyRows, span: $span,
                               initialSelection: initialSelection, scrubPreview: scrubPreview)
    }
}

private struct ChartsSelectionContent: View {
    let bodyRows: [(GraphMetric, GraphSeries?)]
    let dailyRows: [(GraphMetric, GraphSeries?)]
    @Binding var span: GraphSpan
    @State private var selected: GraphMetric
    let scrubPreview: Date?

    /// Liste panelinin sığdığı taban boy; daha kısa pencerede sayfa kayar.
    private static let minHeight: CGFloat = 880

    init(bodyRows: [(GraphMetric, GraphSeries?)], dailyRows: [(GraphMetric, GraphSeries?)],
         span: Binding<GraphSpan>, initialSelection: GraphMetric, scrubPreview: Date?) {
        self.bodyRows = bodyRows
        self.dailyRows = dailyRows
        self._span = span
        self._selected = State(initialValue: initialSelection)
        self.scrubPreview = scrubPreview
    }

    var body: some View {
        let current = (bodyRows + dailyRows).first { $0.0 == selected }?.1

        GeometryReader { proxy in
            ScrollView {
                content(size: proxy.size, current: current, bodyRows: bodyRows, dailyRows: dailyRows)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
            }
        }
        .background(DashboardBackground().ignoresSafeArea())
    }

    /// Geniş pencere: grafik | liste (tasarım ölçüsünde 1029 | 440), pencereyi doldurur.
    /// Dar pencere: alt alta, sabit boylarla.
    @ViewBuilder
    private func content(size: CGSize, current: GraphSeries?,
                         bodyRows: [(GraphMetric, GraphSeries?)],
                         dailyRows: [(GraphMetric, GraphSeries?)]) -> some View {
        let innerW = max(0, size.width - 48)
        let chart = GraphChartPanel(metric: selected, series: current, span: $span, scrubPreview: scrubPreview)
        let list = GraphWatchlistPanel(bodyRows: bodyRows, dailyRows: dailyRows, selected: selected) { metric in
            withAnimation(.snappy(duration: 0.25)) { selected = metric }
        }
        if innerW >= 900 {
            let innerH = max(size.height - 36, Self.minHeight)
            let listW = min(440, max(360, floor((innerW - 24) * 0.3)))
            HStack(spacing: 24) {
                chart.frame(width: innerW - 24 - listW)
                list.frame(width: listW)
            }
            .frame(width: innerW, height: innerH)
        } else {
            VStack(spacing: 18) {
                chart.frame(height: 640)
                list.frame(height: Self.minHeight)
            }
            .frame(width: innerW)
        }
    }
}
