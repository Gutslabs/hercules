import SwiftUI
import LucideKit
import SwiftData

// MARK: - Board kartı kiti
// BoardUI referansının (boardui.com) görünümüne sadık, sıfırdan SwiftUI:
// kart kabuğu + delta çipi + periyot anahtarı + aşama barları.
// Veri ve token'lar tamamen Hercules'ün.

/// Yüzde/birim delta çipi — pozitif yeşil, negatif bordo, nötr gri; %12 tül zemin.
struct BoardDeltaChip: View {
    let text: String
    let direction: Int   // 1 pozitif, -1 negatif, 0 nötr

    private var tint: Color {
        direction > 0 ? Palette.positive : (direction < 0 ? Palette.negative : Palette.textTertiary)
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold).monospacedDigit())
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.13)))
            .lineLimit(1)
    }
}

/// Haftalık/Aylık/Yıllık tarzı metin anahtarı — aktif seçenek kalkık hap.
struct BoardPeriodSwitcher: View {
    let options: [String]
    @Binding var selection: Int

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { idx, opt in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selection = idx }
                } label: {
                    Text(opt)
                        .font(.system(size: 11.5, weight: selection == idx ? .semibold : .regular))
                        .foregroundStyle(selection == idx ? Palette.textPrimary : Palette.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == idx ? Palette.surfaceElevated : Color.clear)
                        )
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Kart kabuğu: 16px köşe yüzey; çizim alanı hafif koyu inset panelde oturur.
struct BoardChartCard<Header: View, Content: View>: View {
    /// Düz mod (Genel Bakış dili): kart zemini ve inset panel yok — içerik
    /// doğrudan sayfa yüzeyinde durur, derinlik çizimin kendi gradyanından gelir.
    /// Kapanışlardan ÖNCE gelmeli ki `BoardChartCard(flat: true) { … } content: { … }` derlensin.
    var flat: Bool = false
    @ViewBuilder let header: Header
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(flat ? 0 : 12)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(flat ? Color.clear : Palette.background.opacity(0.55))
                )
        }
        .padding(flat ? 0 : 18)
        // Satır içinde eşit boy: kabuk kendisine önerilen yüksekliği doldurur,
        // artan alanı çizim paneli yutar (içerik üstte kalır).
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(flat ? Color.clear : Palette.surface)
                .shadow(color: Color.black.opacity(flat ? 0 : 0.05), radius: flat ? 0 : 2, y: flat ? 0 : 1)
        )
    }
}

/// Aşama barları: sol etiket kolonu, renkli kapsül bar (soluk ray üstünde),
/// sağda değer + en büyük aşamaya oranı; altında renk-noktalı özet fayansları.
struct BoardStageBars: View {
    struct Stage: Identifiable {
        var id: String { label }
        let label: String
        let value: Double
        let display: String
        let color: Color
        /// Hedefe doluluk (tüketilen / hedef). Verilirse bar DAĞILIM değil
        /// İLERLEME gösterir: hedefe ulaşınca ray dolar, aşan pay barın sağ
        /// ucunda ayrı tonda görünür. nil ise eski davranış (en büyük aşamaya oran).
        var progress: Double? = nil
    }

    let stages: [Stage]
    /// Değer sütununda yüzde etiketi (varsayılan: var). "12 / 202 g" gibi uzun
    /// gösterimlerde kapatılır — yoksa 84pt sütun iki satıra kırılıyor.
    var showsPercent: Bool = true
    /// Değer sütunu genişliği; uzun gösterimler için çağıran büyütür.
    var valueWidth: CGFloat = 84
    /// Altındaki lejant fayansları (varsayılan: var). Barlar zaten etiket + değer
    /// gösterdiğinden, aynı sayıyı tekrarlaması istenmeyen yerlerde kapatılır.
    var showsTiles: Bool = true

    private var top: Double { max(stages.map(\.value).max() ?? 1, 0.001) }
    /// Barın okuduğu oran: ilerleme verilmişse o, yoksa en büyük aşamaya oran.
    private func ratio(_ s: Stage) -> Double { s.progress ?? (s.value / top) }
    @State private var hoveredID: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 9) {
                ForEach(stages) { s in
                    HStack(spacing: 10) {
                        Text(s.label)
                            .font(.system(size: 11))
                            .foregroundStyle(Palette.textTertiary)
                            .frame(width: 58, alignment: .trailing)
                            .lineLimit(1)
                        GeometryReader { geo in
                            let dim = hoveredID != nil && hoveredID != s.id
                            let filled = min(1, max(0, ratio(s)))
                            let barWidth = max(14, geo.size.width * filled)
                            // Aşım payı: yenenin ne kadarı hedefin üstündeydi.
                            // 222% tüketimde barın sağ %55'i uyarı tonunda çizilir.
                            let over = s.progress.map { $0 > 1 ? ($0 - 1) / $0 : 0 } ?? 0
                            ZStack(alignment: .leading) {
                                Capsule().fill(Palette.track.opacity(0.55))
                                Capsule()
                                    .fill(s.color.opacity(dim ? 0.3 : 0.9))
                                    .frame(width: barWidth)
                                    .overlay(alignment: .trailing) {
                                        if over > 0 {
                                            Rectangle()
                                                .fill(Palette.negative.opacity(dim ? 0.3 : 0.95))
                                                .frame(width: barWidth * over)
                                        }
                                    }
                                    .clipShape(Capsule())
                            }
                        }
                        .frame(height: 14)
                        HStack(spacing: 5) {
                            Text(s.display)
                                .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                                .foregroundStyle(Palette.textPrimary)
                                .lineLimit(1)
                            if showsPercent {
                                Text("%\(Int((ratio(s) * 100).rounded()))")
                                    .font(.system(size: 10).monospacedDigit())
                                    .foregroundStyle(Palette.textQuaternary)
                            }
                        }
                        .frame(width: valueWidth, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .onHover { inside in
                        hoveredID = inside ? s.id : (hoveredID == s.id ? nil : hoveredID)
                    }
                }
            }
            .animation(.easeOut(duration: 0.14), value: hoveredID)

            if showsTiles {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                ForEach(stages) { s in
                    let dimmed = hoveredID != nil && hoveredID != s.id
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 5) {
                            Circle().fill(s.color).frame(width: 6, height: 6)
                            Text(s.label)
                                .font(.system(size: 10))
                                .foregroundStyle(Palette.textTertiary)
                                .lineLimit(1)
                        }
                        Text(s.display)
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(Palette.textPrimary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Palette.surfaceElevated.opacity(hoveredID == s.id ? 1 : 0.6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(hoveredID == s.id ? Palette.borderStrong.opacity(0.6) : .clear, lineWidth: 1)
                    )
                    .opacity(dimmed ? 0.55 : 1)
                    .onHover { inside in
                        hoveredID = inside ? s.id : (hoveredID == s.id ? nil : hoveredID)
                    }
                }
            }
            }
        }
    }
}
