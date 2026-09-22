import SwiftUI

/// SwiftData kayıtları iCloud (CloudKit) ile cihazlar arasında otomatik taşınır.
struct CloudSyncCard: View {
    @State private var sync = CloudSyncMonitor.shared

    private var statusColor: Color {
        switch sync.state {
        case .ready: return Palette.positive
        case .checking, .syncing: return Palette.warning
        case .unavailable, .error: return Palette.negative
        }
    }

    /// `compact`: sayfanın dibinde tek satır (durum + nokta), açıklama tooltip'te.
    /// Varsayılan: eski iki satırlık blok (başka yerde kullanılırsa bozulmasın).
    var compact = false

    var body: some View {
        if compact {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 5, height: 5)
                Text(sync.statusText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            .help(sync.detailText)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 7) {
                    Text("Senkron").eyebrow()
                    Circle()
                        .fill(statusColor)
                        .frame(width: 5, height: 5)
                    Text(sync.statusText)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Palette.textSecondary)
                }

                Text(sync.detailText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Palette.textTertiary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            .padding(.init(top: 20, leading: 28, bottom: 18, trailing: 28))
        }
    }
}
