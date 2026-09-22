import SwiftUI
import Photos
import UIKit
import ImageIO
import LucideKit

// Composer'ın kendisi ek panelidir. Ayrı bir action sheet ya da tam ekran sistem
// picker'ı AÇILMAZ: aynı yuvarlak kap yerinde kalır, yayla büyür ve içeriği
// bulanık geçişle değişir. Üç durak: yazı alanı → ek menüsü → fotoğraf ızgarası.
// Sistem yüzeyleri yalnızca kap dışına çıkan işler için (kamera, tüm kütüphane).

enum MobileAttachStage: Equatable {
    case composer
    case menu
    case photos

    var isOpen: Bool { self != .composer }
}

// MARK: - Morph geçişi

/// Duraklar arası bulanık çapraz geçiş — kap yerinde kalırken içerik "odağa gelir".
/// Transition değil modifier: her durak hep ağaçta durur, böylece ZStack yüksekliği
/// geçiş sırasında sıçramaz ve kabın yayı tek başına yüksekliği sürer.
private struct MorphVisibility: ViewModifier {
    let visible: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: visible || reduceMotion ? 0 : 9)
            .opacity(visible ? 1 : 0)
            .scaleEffect(visible || reduceMotion ? 1 : 0.97, anchor: .bottom)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
    }
}

private extension View {
    func morphVisible(_ visible: Bool, reduceMotion: Bool) -> some View {
        modifier(MorphVisibility(visible: visible, reduceMotion: reduceMotion))
    }
}

// MARK: - Yüzey

/// Video referansındaki tek-yüzey morph'u. Çağıran kendi composer'ını verir;
/// yüzey onu ek menüsüne ve oradan fotoğraf ızgarasına dönüştürür.
struct MobileAttachSurface<Composer: View>: View {
    @Binding var stage: MobileAttachStage
    /// Kap dışına çıkan işler — sistem yüzeyleri çağıranda kalır.
    var onCamera: () -> Void
    var onFiles: () -> Void
    var onAllPhotos: () -> Void
    /// Izgaradan seçilen fotoğrafın küçültülmüş JPEG'i.
    var onPick: (Data) -> Void
    /// Kapalı durakta kenarı vurgulamak için — kap composer'ın değil yüzeyin, odak da öyle.
    var composerFocused: Bool = false
    @ViewBuilder var composer: () -> Composer

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var library = MobileRecentPhotos()
    @State private var composerHeight: CGFloat = 52
    /// İlk ölçüm animasyonsuz oturur — açılışta kabın "büyüyerek gelmesi" istenmiyor.
    @State private var measured = false

    private var cameraAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    private var surfaceHeight: CGFloat {
        switch stage {
        case .composer: return composerHeight
        case .menu:     return MobileAttachMetrics.menuHeight(cameraAvailable: cameraAvailable)
        case .photos:   return MobileAttachMetrics.photosHeight
        }
    }

    private var cornerRadius: CGFloat {
        stage.isOpen ? MobileAttachMetrics.openRadius : MobileAttachMetrics.composerRadius
    }

    private var borderColor: Color {
        if stage.isOpen { return ChatChrome.borderStrong.opacity(0.5) }
        // Masaüstü composer'ıyla aynı kural: odakta kenar güçlenir.
        return composerFocused ? ChatChrome.borderStrong : ChatChrome.borderStrong.opacity(0.5)
    }

    private var morph: Animation? {
        reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.86)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            composer()
                .measuringHeight { height in
                    composerHeight = height
                    if !measured { measured = true }
                }
                .morphVisible(stage == .composer, reduceMotion: reduceMotion)

            menuBody
                .morphVisible(stage == .menu, reduceMotion: reduceMotion)

            photosBody
                .morphVisible(stage == .photos, reduceMotion: reduceMotion)
        }
        .frame(maxWidth: .infinity)
        .frame(height: surfaceHeight, alignment: .bottom)
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(stage.isOpen ? ChatChrome.panelRaised : ChatChrome.background)
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        // Gölge YOK: Buzz composer kartında yükseklik hissi gölgeyle değil
        // kenarlıkla verilir (masaüstündeki kartla aynı kural).
        .shadow(color: .black.opacity(stage.isOpen ? 0.35 : 0), radius: stage.isOpen ? 18 : 0, y: stage.isOpen ? 8 : 0)
        .animation(morph, value: stage)
        .animation(measured ? morph : nil, value: composerHeight)
        .animation(.easeOut(duration: reduceMotion ? 0 : 0.15), value: composerFocused)
        .onChange(of: stage) { _, new in
            // İzin istemi ancak kullanıcı gerçekten fotoğraflara girince çıksın.
            if new == .photos { library.load() }
        }
    }

    // MARK: Durak 2 — ek menüsü

    private var menuBody: some View {
        VStack(spacing: 0) {
            if cameraAvailable {
                menuRow(icon: "camera", title: "Kamera") {
                    close()
                    onCamera()
                }
            }
            menuRow(icon: "photo.on.rectangle", title: "Fotoğraflar") {
                withAnimation(morph) { stage = .photos }
            }
            menuRow(icon: "folder", title: "Dosyalar") {
                close()
                onFiles()
            }
        }
        .padding(.vertical, MobileAttachMetrics.menuVerticalPadding)
    }

    private func menuRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Lucide(sf: icon, size: 16)
                    .foregroundStyle(ChatChrome.primary)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(ChatChrome.panelRaised))
                Text(title)
                    .font(.system(size: 15))
                    .foregroundStyle(ChatChrome.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(height: MobileAttachMetrics.menuRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(MobileAttachRowStyle())
    }

    // MARK: Durak 3 — ızgara

    private var photosBody: some View {
        ZStack(alignment: .bottom) {
            switch library.state {
            case .loading:
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .denied:
                deniedBody
            case .ready:
                grid
            }

            // Yüzen kontroller — nav bar değil, ızgaranın üstünde duran haplar.
            HStack {
                floatingButton(accessibility: "Geri") {
                    withAnimation(morph) { stage = .menu }
                } label: {
                    Lucide(sf: "chevron.left", size: 15)
                }
                Spacer()
                Button {
                    close()
                    onAllPhotos()
                } label: {
                    Text("Tüm fotoğraflar")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(ChatChrome.ink)
                        .padding(.horizontal, 16)
                        .frame(height: 36)
                        .background(Capsule().fill(ChatChrome.white.opacity(0.92)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 12)
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: MobileAttachMetrics.gridColumns, spacing: MobileAttachMetrics.gridSpacing) {
                ForEach(library.assets, id: \.localIdentifier) { asset in
                    MobileAttachPhotoCell(asset: asset) { data in
                        close()
                        onPick(data)
                    }
                }
            }
            // Yüzen kontrollerin altında ızgaranın bitmediği hissi kalsın.
            .padding(.bottom, 56)
        }
        .scrollIndicators(.hidden)
    }

    private var deniedBody: some View {
        VStack(spacing: 10) {
            Text("Fotoğraf erişimi kapalı")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(ChatChrome.primary)
            Text("Son fotoğrafları burada göstermek için Ayarlar'dan erişim ver — ya da tek seferlik seçim yap.")
                .font(.system(size: 12))
                .foregroundStyle(ChatChrome.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func floatingButton(
        accessibility: String,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> some View
    ) -> some View {
        Button(action: action) {
            label()
                .foregroundStyle(ChatChrome.primary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(ChatChrome.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    private func close() {
        withAnimation(morph) { stage = .composer }
    }
}

// MARK: - Ölçüler

enum MobileAttachMetrics {
    static let composerRadius: CGFloat = 16
    static let openRadius: CGFloat = 26
    static let menuRowHeight: CGFloat = 54
    static let menuVerticalPadding: CGFloat = 8
    static let photosHeight: CGFloat = 316
    static let gridSpacing: CGFloat = 2

    static var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: gridSpacing), count: 3)
    }

    static func menuHeight(cameraAvailable: Bool) -> CGFloat {
        CGFloat(cameraAvailable ? 3 : 2) * menuRowHeight + menuVerticalPadding * 2
    }
}

private struct MobileAttachRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? ChatChrome.panelRaised : .clear)
    }
}

/// Composer kendi boyunu ölçer — kabın kapalı yüksekliği yazı alanı büyüdükçe onu izler.
private extension View {
    func measuringHeight(_ onChange: @escaping (CGFloat) -> Void) -> some View {
        background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onChange(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, new in onChange(new) }
            }
        }
    }
}

// MARK: - Izgara hücresi

private struct MobileAttachPhotoCell: View {
    let asset: PHAsset
    var onPick: (Data) -> Void

    @State private var thumb: UIImage?
    @State private var loading = false

    var body: some View {
        Button {
            guard !loading else { return }
            loading = true
            Task {
                let data = await MobileRecentPhotos.jpeg(for: asset)
                loading = false
                if let data { onPick(data) }
            }
        } label: {
            Color.clear
                .aspectRatio(1, contentMode: .fill)
                .overlay {
                    if let thumb {
                        Image(uiImage: thumb).resizable().scaledToFill()
                    } else {
                        ChatChrome.panelRaised
                    }
                }
                .clipped()
                .contentShape(Rectangle())
                .overlay {
                    if loading {
                        ZStack {
                            Color.black.opacity(0.25)
                            ProgressView().controlSize(.small).tint(.white)
                        }
                    }
                }
        }
        .buttonStyle(.plain)
        .task(id: asset.localIdentifier) {
            guard thumb == nil else { return }
            thumb = await MobileRecentPhotos.thumbnail(for: asset)
        }
    }
}

// MARK: - Kütüphane

/// Son fotoğrafları okur. İzin `.photos` durağına girilene kadar İSTENMEZ.
/// Sınırlı erişimde (iOS 14+) yalnızca izin verilenler döner — "Tüm fotoğraflar"
/// hapı zaten sistem picker'ına düşürdüğü için bu yeterli.
@MainActor
final class MobileRecentPhotos: ObservableObject {
    enum State { case loading, denied, ready }

    @Published private(set) var state: State = .loading
    @Published private(set) var assets: [PHAsset] = []

    private var loaded = false

    func load() {
        guard !loaded else { return }
        loaded = true
        Task {
            let status = await Self.authorize()
            guard status == .authorized || status == .limited else {
                state = .denied
                return
            }
            assets = Self.fetchRecent(limit: 60)
            state = .ready
        }
    }

    private static func authorize() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        guard current == .notDetermined else { return current }
        return await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { continuation.resume(returning: $0) }
        }
    }

    nonisolated private static func fetchRecent(limit: Int) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)
        var assets: [PHAsset] = []
        assets.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in assets.append(asset) }
        return assets
    }

    nonisolated static func thumbnail(for asset: PHAsset) async -> UIImage? {
        let options = PHImageRequestOptions()
        // highQualityFormat handler'ı TEK kez çağırır — opportunistic'in çok-atışlı
        // davranışıyla continuation'ı iki kez resume etme riski hiç doğmuyor.
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false   // ızgara yerel önbellekten dolsun
        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 240, height: 240),
                contentMode: .aspectFill,
                options: options
            ) { image, _ in continuation.resume(returning: image) }
        }
    }

    /// Modele gidecek küçültülmüş JPEG — tam çözünürlük hiçbir zaman UI state'ine girmez.
    nonisolated static func jpeg(for asset: PHAsset) async -> Data? {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .exact
        options.isNetworkAccessAllowed = true
        let scale = min(1, 1280 / max(CGFloat(asset.pixelWidth), CGFloat(asset.pixelHeight), 1))
        let target = CGSize(width: CGFloat(asset.pixelWidth) * scale, height: CGFloat(asset.pixelHeight) * scale)
        let image: UIImage? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: target,
                contentMode: .aspectFit,
                options: options
            ) { image, _ in continuation.resume(returning: image) }
        }
        return image?.jpegData(compressionQuality: 0.78)
    }
}
