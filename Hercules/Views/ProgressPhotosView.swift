import SwiftUI
import SwiftData
import LucideKit
import UniformTypeIdentifiers
import ImageIO
import LocalAuthentication
#if canImport(AppKit)
import AppKit
#endif

/// Fotoğraflar — haftalık gelişim takibi (karın + tüm vücud). Aylık klasörler (Haziran → Ocak);
/// gelecek aylar kilitli, içinde bulunulan ay açık. Klasöre girince haftalara (Hafta 1-4) bölünmüş
/// 4'lü ızgara; aktif ayda "Yükle" → açılan boş alana sürükle-bırak (ya da Finder'dan seç).
/// Tasarım: Hercules ana Palette'i (İlerleme sayfası diliyle aynı).
struct ProgressPhotosView: View {
    /// Seçili fotoğraf(lar)ı koç sohbetine taşır: composer'a ekler + prompt'u doldurur + .chat'e geçer.
    /// ContentView sağlar (paylaşılan ChatStore + tab geçişi). Görseller chat'in vision boru hattından AI'ya gider.
    var onSendToCoach: ([Data], String) -> Void = { _, _ in }

    @Query(sort: \ProgressPhoto.capturedAt, order: .reverse) private var photos: [ProgressPhoto]
    @Environment(\.modelContext) private var ctx

    @State private var selectedMonth: String? = nil
    @State private var showUpload = false
    @State private var dropTargeted = false
    @State private var preview: ProgressPhoto? = nil
    @State private var deleteCandidate: ProgressPhoto? = nil

    // Touch ID kapısı — sayfaya her girişte sorulur (tab değişince view sıfırlanır → tekrar sorar).
    @State private var unlocked = false
    @State private var authenticating = false
    @State private var authError: String? = nil

    // Program penceresi: Haziran 2026 → Ocak 2027.
    private static let startComps = DateComponents(year: 2026, month: 6, day: 1)
    private static let endComps = DateComponents(year: 2027, month: 1, day: 1)

    var body: some View {
        Group {
            if unlocked {
                if let key = selectedMonth, let info = months.first(where: { $0.key == key }) {
                    monthDetail(info)
                } else {
                    foldersOverview
                }
            } else {
                lockScreen
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(DashboardBackground().ignoresSafeArea())
        .onAppear { if !unlocked { authenticate() } }
        .sheet(item: $preview) { photo in previewSheet(photo) }
        .confirmationDialog("Bu fotoğraf silinsin mi?",
                            isPresented: Binding(get: { deleteCandidate != nil },
                                                 set: { if !$0 { deleteCandidate = nil } }),
                            titleVisibility: .visible) {
            Button("Sil", role: .destructive) {
                if let p = deleteCandidate {
                    ctx.delete(p)
                    ctx.saveOrReport("ilerleme fotoğrafını silme")
                }
                deleteCandidate = nil
            }
            Button("İptal", role: .cancel) { deleteCandidate = nil }
        }
    }

    // MARK: - Kilit (Touch ID)

    private var lockScreen: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Palette.accentSoft).frame(width: 78, height: 78)
                Lucide("fingerprint", size: 32).foregroundStyle(Palette.accent)
            }
            VStack(spacing: 6) {
                Text("Fotoğraflar kilitli")
                    .font(.system(size: 19, weight: .semibold)).foregroundStyle(Palette.textPrimary)
                Text("Gelişim fotoğraflarını görmek için kimliğini doğrula.")
                    .font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320).fixedSize(horizontal: false, vertical: true)
            }
            if let authError {
                Text(authError)
                    .font(.system(size: 12)).foregroundStyle(Palette.negative)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320).fixedSize(horizontal: false, vertical: true)
            }
            Button { authenticate() } label: {
                HStack(spacing: 8) {
                    if authenticating { ProgressView().controlSize(.small) }
                    else { Lucide("fingerprint", size: 14) }
                    Text(authenticating ? "Doğrulanıyor…" : "Touch ID ile aç")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .foregroundStyle(Palette.btnFg)
                .padding(.horizontal, 18).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Palette.btnBg))
            }
            .buttonStyle(.plain)
            .disabled(authenticating)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    /// Touch ID (yoksa cihaz parolası) sor; geçerse içeriği aç.
    private func authenticate() {
        guard !authenticating, !unlocked else { return }
        authenticating = true
        authError = nil
        let context = LAContext()
        context.localizedFallbackTitle = "Şifre Kullan"
        let policy: LAPolicy = .deviceOwnerAuthentication   // biyometri + cihaz parolası fallback
        var policyError: NSError?
        guard context.canEvaluatePolicy(policy, error: &policyError) else {
            authenticating = false
            authError = "Kimlik doğrulama kullanılamıyor — Touch ID ya da cihaz parolası ayarlı değil."
            return
        }
        context.evaluatePolicy(policy, localizedReason: "Gelişim fotoğraflarını açmak için kimliğini doğrula") { ok, evalError in
            DispatchQueue.main.async {
                authenticating = false
                if ok {
                    unlocked = true
                    authError = nil
                } else {
                    let code = (evalError as NSError?)?.code
                    let cancelled = code == LAError.userCancel.rawValue
                        || code == LAError.appCancel.rawValue
                        || code == LAError.systemCancel.rawValue
                    authError = cancelled ? nil : "Doğrulama başarısız. Tekrar dene."
                }
            }
        }
    }

    // MARK: - Klasörler (ay ızgarası)

    private var foldersOverview: some View {
        // Üst şerit yok: sayfa adı sidebar'da, klasörler doğrudan başlar.
        VStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: .infinity), spacing: 12)],
                          spacing: 12) {
                    ForEach(months) { folderCard($0) }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func folderCard(_ info: MonthInfo) -> some View {
        let count = photos(in: info.key).count
        let isCurrent = info.key == currentMonthKey
        return Button {
            guard !info.locked else { return }
            selectedMonth = info.key
            showUpload = false
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Lucide(info.locked ? "lock" : "folder", size: 20)
                        .foregroundStyle(info.locked ? Palette.textTertiary : (isCurrent ? Palette.accent : Palette.textSecondary))
                    Spacer()
                    if isCurrent {
                        Text("BU AY").font(.system(size: 9.5, weight: .bold)).tracking(0.8)
                            .foregroundStyle(Palette.accent)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Palette.accentSoft))
                    }
                }
                Spacer(minLength: 26)
                Text(monthName(info.date))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(info.locked ? Palette.textTertiary : Palette.textPrimary)
                Text(info.locked ? "\(monthName(info.date, style: "MMMM")) ayında açılır"
                                 : (count == 0 ? "Boş" : "\(count) fotoğraf"))
                    .font(.system(size: 12.5))
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 3)
            }
            .padding(18)
            .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: Radius.md, style: .continuous).fill(Palette.surface))
            .overlay(RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .strokeBorder(isCurrent ? Palette.accent.opacity(0.30) : Palette.border.opacity(0.7), lineWidth: 1))
            .opacity(info.locked ? 0.55 : 1)
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(info.locked)
        .help(info.locked ? "Bu ay henüz açılmadı" : monthName(info.date))
    }

    // MARK: - Ay detayı (haftalar + ızgara)

    private func monthDetail(_ info: MonthInfo) -> some View {
        let monthPhotos = photos(in: info.key)
        let isCurrent = info.key == currentMonthKey
        return ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                // Üst bar: geri + başlık + yükle
                HStack(alignment: .center, spacing: 14) {
                    Button { selectedMonth = nil } label: {
                        HStack(spacing: 5) {
                            Lucide(sf: "chevron.left", size: 12)
                            Text("Aylar").font(.system(size: 13, weight: .medium))
                        }
                        .foregroundStyle(Palette.textSecondary)
                    }
                    .buttonStyle(.plain)

                    Text(monthName(info.date))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    Spacer()
                    if isCurrent {
                        Button { withAnimation(.easeInOut(duration: 0.18)) { showUpload.toggle() } } label: {
                            HStack(spacing: 7) {
                                Lucide(sf: showUpload ? "xmark" : "plus", size: 12)
                                Text(showUpload ? "Kapat" : "Yükle").font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(Palette.btnFg)
                            .padding(.horizontal, 15).frame(height: 38)
                            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.btnBg))
                        }
                        .buttonStyle(.plain)
                    }
                }

                if isCurrent && (showUpload || monthPhotos.isEmpty) {
                    uploadZone
                }

                if monthPhotos.isEmpty && !isCurrent {
                    Text("Bu ay fotoğraf eklenmemiş.")
                        .font(.system(size: 13)).foregroundStyle(Palette.textTertiary)
                        .padding(.vertical, 30)
                } else {
                    ForEach(weeks(in: monthPhotos), id: \.week) { group in
                        weekSection(group)
                    }
                }
            }
            .padding(.horizontal, 52)
            .padding(.top, 30)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var uploadZone: some View {
        VStack(spacing: 12) {
            Lucide(sf: "arrow.up.doc", size: 26).foregroundStyle(Palette.accent)
            Text("Fotoğrafları buraya sürükle")
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.textPrimary)
            Text("ya da Finder'dan seçmek için tıkla · bu haftanın karesi otomatik tarihlenir")
                .font(.system(size: 12)).foregroundStyle(Palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.fieldFill))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.6, dash: [7, 5]))
                .foregroundStyle(dropTargeted ? Palette.accent : Palette.borderStrong)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { browseFiles() }
        .onDrop(of: [.image, .fileURL], isTargeted: $dropTargeted) { providers in handleDrop(providers) }
        .animation(.easeInOut(duration: 0.12), value: dropTargeted)
    }

    private func weekSection(_ group: WeekGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("Hafta \(group.week)".uppercased())
                    .font(.system(size: 11, weight: .bold)).tracking(1.0)
                    .foregroundStyle(Palette.textSecondary)
                Text(dateLabel(group.photos.first?.capturedAt))
                    .font(.system(size: 11)).foregroundStyle(Palette.textTertiary)
                Rectangle().fill(Palette.border).frame(height: 1)
                Text("\(group.photos.count)")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.textTertiary)
                Button {
                    onSendToCoach(group.photos.map(\.imageData),
                                  "Hafta \(group.week) gelişim fotoğraflarım — karın/duruş açısından ne diyorsun?")
                } label: {
                    HStack(spacing: 5) {
                        Lucide(sf: "sparkles", size: 11)
                        Text("Koça gönder").font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Palette.accent)
                }
                .buttonStyle(.plain)
                .help("Bu haftanın fotoğraflarını koça gönder")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 12) {
                ForEach(group.photos) { photoCell($0) }
            }
        }
    }

    private func photoCell(_ photo: ProgressPhoto) -> some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let img = image(from: photo.imageData) {
                    img.resizable().scaledToFill()
                } else {
                    Lucide(sf: "photo", size: 20).foregroundStyle(Palette.textTertiary)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border, lineWidth: 1))
            .overlay(alignment: .topTrailing) {
                Button { deleteCandidate = photo } label: {
                    Lucide(sf: "xmark", size: 10)
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .padding(6)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onTapGesture { preview = photo }
    }

    // MARK: - Önizleme

    private func previewSheet(_ photo: ProgressPhoto) -> some View {
        ProgressPhotoPreview(
            photo: photo,
            image: image(from: photo.imageData),
            onSend: {
                onSendToCoach([photo.imageData],
                              "Bu gelişim fotoğrafımı (Hafta \(photo.week)) değerlendirir misin?")
                preview = nil
            },
            onDelete: { deleteCandidate = photo; preview = nil },
            onClose: { preview = nil }
        )
    }

    // MARK: - Header / eyebrow

    private func eyebrow(_ text: String) -> some View {
        Text(text).eyebrow()
    }

    // MARK: - İçe aktarma

    #if os(macOS)
    private func browseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.image]
        panel.prompt = "Ekle"
        guard panel.runModal() == .OK else { return }
        importDatas(panel.urls.compactMap { try? Data(contentsOf: $0) })
    }
    #else
    private func browseFiles() {}
    #endif

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers {
            #if canImport(AppKit)
            if provider.canLoadObject(ofClass: NSImage.self) {
                accepted = true
                _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                    guard let img = obj as? NSImage, let tiff = img.tiffRepresentation,
                          let rep = NSBitmapImageRep(data: tiff),
                          let data = rep.representation(using: .png, properties: [:]) else { return }
                    DispatchQueue.main.async { importDatas([data]) }
                }
                continue
            }
            #endif
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                accepted = true
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    guard let data else { return }
                    DispatchQueue.main.async { importDatas([data]) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    var url: URL?
                    if let u = item as? URL { url = u }
                    else if let d = item as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                    guard let url, let data = try? Data(contentsOf: url) else { return }
                    DispatchQueue.main.async { importDatas([data]) }
                }
            }
        }
        return accepted
    }

    /// Görselleri küçült (max 2000px, JPEG) ve bu haftanın karesi olarak kaydet.
    private func importDatas(_ datas: [Data]) {
        let now = Date()
        var inserted = false
        for data in datas {
            guard let small = Self.downsized(data) else { continue }
            ctx.insert(ProgressPhoto(imageData: small, capturedAt: now))
            inserted = true
        }
        if inserted {
            if ctx.saveOrReport("ilerleme fotoğrafı ekleme") {
                showUpload = false
            }
        }
    }

    /// ImageIO ile en uzun kenarı `maxPixel`'e indirgenmiş JPEG (oryantasyon korunur).
    private static func downsized(_ data: Data, maxPixel: CGFloat = 2000, quality: CGFloat = 0.82) -> Data? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, cg, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return out as Data
    }

    private func image(from data: Data) -> Image? {
        guard !data.isEmpty else { return nil }
        #if canImport(AppKit)
        return NSImage(data: data).map { Image(nsImage: $0) }
        #elseif canImport(UIKit)
        return UIImage(data: data).map { Image(uiImage: $0) }
        #else
        return nil
        #endif
    }

    // MARK: - Türetilen veri

    private struct MonthInfo: Identifiable {
        let key: String
        let date: Date
        let locked: Bool
        var id: String { key }
    }

    private struct WeekGroup: Identifiable {
        let week: Int
        let photos: [ProgressPhoto]
        var id: Int { week }
    }

    private var months: [MonthInfo] {
        let cal = Calendar.current
        guard let start = cal.date(from: Self.startComps), let end = cal.date(from: Self.endComps) else { return [] }
        let now = Date()
        let curStart = cal.date(from: cal.dateComponents([.year, .month], from: now)) ?? now
        var out: [MonthInfo] = []
        var d = start
        while d <= end {
            out.append(MonthInfo(key: ProgressPhoto.monthKey(for: d), date: d, locked: d > curStart))
            guard let next = cal.date(byAdding: .month, value: 1, to: d) else { break }
            d = next
        }
        return out
    }

    private var currentMonthKey: String { ProgressPhoto.monthKey(for: Date()) }

    private func photos(in key: String) -> [ProgressPhoto] {
        photos.filter { $0.monthKey == key }
    }

    /// Ay fotoğraflarını haftaya böl (yeni hafta üstte).
    private func weeks(in monthPhotos: [ProgressPhoto]) -> [WeekGroup] {
        let grouped = Dictionary(grouping: monthPhotos) { $0.week }
        return grouped.keys.sorted(by: >).map { w in
            WeekGroup(week: w, photos: grouped[w]?.sorted { $0.capturedAt > $1.capturedAt } ?? [])
        }
    }

    private func monthName(_ date: Date, style: String = "MMMM yyyy") -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = style
        return f.string(from: date)
    }

    private func dateLabel(_ date: Date?) -> String {
        guard let date else { return "" }
        let f = DateFormatter(); f.locale = Locale(identifier: "tr_TR"); f.dateFormat = "d MMM"
        return f.string(from: date)
    }

}

/// Fotoğraf önizleme penceresi — tasarım: tuval ▸ Pencereler · Veriler (az yazı). Başlıkta tarih ve
/// hafta, büyük fotoğraf (köşesinde o günün tartısı), altta Sil ve Koç'a gönder.
struct ProgressPhotoPreview: View {
    let photo: ProgressPhoto
    let image: Image?
    let onSend: () -> Void
    let onDelete: () -> Void
    let onClose: () -> Void

    @Query(sort: \Measurement.date, order: .reverse) private var measurements: [Measurement]

    /// Fotoğrafın çekildiği güne (±1 gün) en yakın tartı.
    private var weight: Double? {
        let cal = Calendar.current
        let day = cal.startOfDay(for: photo.capturedAt)
        return measurements
            .filter { abs(cal.dateComponents([.day], from: cal.startOfDay(for: $0.date), to: day).day ?? 99) <= 1 }
            .min { abs($0.date.timeIntervalSince(photo.capturedAt)) < abs($1.date.timeIntervalSince(photo.capturedAt)) }?
            .weight
    }

    var body: some View {
        SadeSheet(title: Fmt.dateLong.string(from: photo.capturedAt), subtitle: "Hafta \(photo.week)", onClose: onClose) {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.surfaceElevated, Palette.surface], startPoint: .topLeading, endPoint: .bottomTrailing))
                if let image {
                    image
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                } else {
                    Lucide(sf: "photo", size: 34)
                        .foregroundStyle(Palette.textQuaternary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let weight {
                    Text("\(SadeFormat.num(weight)) kg")
                        .font(.system(size: 12.5).monospacedDigit())
                        .foregroundStyle(Palette.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.45)))
                        .padding(14)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 16)
            .padding(.bottom, 22)
        } footerLeading: {
            SadeButton(title: "Sil", icon: "trash", role: .destructive, action: onDelete)
        } footerTrailing: {
            SadeButton(title: "Koç'a gönder", icon: "sparkles", role: .primary, bindsKey: false, action: onSend)
        }
        .frame(width: 640, height: 880)
    }
}
