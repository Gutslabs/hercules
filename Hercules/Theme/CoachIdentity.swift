import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Platform görsel köprüsü

#if os(macOS)
typealias PlatformImage = NSImage
#else
typealias PlatformImage = UIImage
#endif

extension Image {
    /// Paylaşılan bileşenler tek çağrı kullansın: Mac'te NSImage, iOS'ta UIImage.
    init(platform image: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: image)
        #else
        self.init(uiImage: image)
        #endif
    }
}

// MARK: - Avatar deposu (profil + koç)

/// Tek dosyalık avatar deposu. Avatarlar SwiftData'ya DEĞİL diske yazılır:
/// CloudKit production şemasına alan eklemek riskli (şema kilitli) ve avatar
/// zaten cihaza özel kalabilir. İki örneği var — profil ve koç.
final class AvatarFileStore: @unchecked Sendable {
    private let fileName: String
    let changed: Notification.Name
    private let lock = NSLock()
    private var cached: PlatformImage?
    private var loaded = false

    init(fileName: String, changed: Notification.Name) {
        self.fileName = fileName
        self.changed = changed
    }

    private var url: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return base.appendingPathComponent("Hercules/\(fileName)")
    }

    /// Diskteki ham PNG. Avatarı ağdan göndermek için (decode/encode gerekmez).
    func data() -> Data? {
        guard let url else { return nil }
        return try? Data(contentsOf: url)
    }

    func image() -> PlatformImage? {
        lock.lock(); defer { lock.unlock() }
        if loaded { return cached }
        loaded = true
        if let url, let data = try? Data(contentsOf: url), let img = PlatformImage(data: data) {
            cached = img
        }
        return cached
    }

    func set(imageAt sourceURL: URL) {
        guard let data = try? Data(contentsOf: sourceURL), let img = PlatformImage(data: data) else { return }
        set(img)
    }

    func set(_ img: PlatformImage) {
        guard let url, let png = Self.pngData(img) else { return }
        try? png.write(to: url)
        lock.lock(); cached = img; loaded = true; lock.unlock()
        NotificationCenter.default.post(name: changed, object: nil)
    }

    func clear() {
        if let url { try? FileManager.default.removeItem(at: url) }
        lock.lock(); cached = nil; loaded = true; lock.unlock()
        NotificationCenter.default.post(name: changed, object: nil)
    }

    private static func pngData(_ img: PlatformImage) -> Data? {
        #if os(macOS)
        guard let tiff = img.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
        #else
        return img.pngData()
        #endif
    }

    #if os(macOS)
    /// NSOpenPanel ile görsel seçtir (sandbox yok — direkt dosya erişimi).
    @MainActor
    func pickImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let picked = panel.url {
            set(imageAt: picked)
        }
    }
    #endif
}

/// ~/Library/Application Support/Hercules/avatar.png
enum ProfileAvatarStore {
    static let changed = Notification.Name("hercules.profile.avatar.changed")
    static let store = AvatarFileStore(fileName: "avatar.png", changed: Self.changed)
    static func image() -> PlatformImage? { store.image() }
    static func data() -> Data? { store.data() }
    static func set(imageAt url: URL) { store.set(imageAt: url) }
    static func set(_ img: PlatformImage) { store.set(img) }
    static func clear() { store.clear() }
    #if os(macOS)
    @MainActor static func pickImage() { store.pickImage() }
    #endif
}

/// ~/Library/Application Support/Hercules/coach-avatar.png
/// Fotoğraf yoksa koç sohbette kendi orb'uyla görünmeye devam eder.
enum CoachAvatarStore {
    static let changed = Notification.Name("hercules.coach.avatar.changed")
    static let store = AvatarFileStore(fileName: "coach-avatar.png", changed: Self.changed)
    static func image() -> PlatformImage? { store.image() }
    static func data() -> Data? { store.data() }
    static func set(imageAt url: URL) { store.set(imageAt: url) }
    static func set(_ img: PlatformImage) { store.set(img) }
    static func clear() { store.clear() }
    #if os(macOS)
    @MainActor static func pickImage() { store.pickImage() }
    #endif
}

// MARK: - Koç kimliği

/// Koç'un kullanıcı tarafından değiştirilebilen adı. Cihaza özel bir tercih
/// (UserDefaults) — CloudKit şemasına dokunmaz.
enum CoachIdentity {
    static let changed = Notification.Name("hercules.coach.identity.changed")
    static let defaultName = "Koç"
    private static let key = "hercules.coach.name"

    static var name: String {
        let raw = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        return raw.isEmpty ? defaultName : raw
    }

    /// Ham tercih — ayarlardaki alan boşken varsayılanı placeholder gösterebilsin.
    static var customName: String { UserDefaults.standard.string(forKey: key) ?? "" }

    static func setName(_ newName: String) {
        let trimmed = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(24))
        if trimmed.isEmpty || trimmed == defaultName {
            UserDefaults.standard.removeObject(forKey: key)
        } else {
            UserDefaults.standard.set(trimmed, forKey: key)
        }
        NotificationCenter.default.post(name: changed, object: nil)
    }

    /// Yönelme hâli: "Koç'a", "Herkül'e", "Ayşe'ye". Özel ad olduğu için kesme
    /// işaretiyle yazılır; son sessiz harf yumuşamaz ("Koç'a", "Koc'a" değil).
    static var dative: String { dative(name) }

    static func dative(_ raw: String) -> String {
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "" }
        // Ek son ÜNLÜYE göre uyumlanır: kalın → 'a, ince → 'e.
        let back: Set<Character> = ["a", "ı", "o", "u", "A", "I", "O", "U"]
        let front: Set<Character> = ["e", "i", "ö", "ü", "E", "İ", "Ö", "Ü"]
        let isVowel: (Character) -> Bool = { back.contains($0) || front.contains($0) }
        let suffix = name.last(where: isVowel).map { back.contains($0) ? "a" : "e" } ?? "e"
        // Ünlüyle biten adlarda kaynaştırma y'si: "Ayşe'ye".
        let buffer = name.last.map(isVowel) == true ? "y" : ""
        return "\(name)'\(buffer)\(suffix)"
    }
}

/// Ada göre renkli daire + baş harf — fotoğraf yokken avatarın yerini tutar.
struct InitialFace: View {
    let name: String
    var fallbackInitial: String = "h"
    /// Baş harf punto (sohbet/kenar çubuğu yüzleri 12; mobil Profil'in 48'lik avatarı 20).
    var fontSize: CGFloat = 12

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.first.map { String($0).lowercased(with: Locale(identifier: "tr_TR")) }
            ?? fallbackInitial
    }

    var body: some View {
        let colors = AvatarPalette.color(for: name.isEmpty ? "Hercules" : name)
        ZStack {
            Circle().fill(Color(hex: colors.bg))
            Text(initial)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(colors.fg)
        }
    }
}

// MARK: - Avatar büyütme

/// Avatara tıklayınca açılan kart: fotoğrafın büyük hâli + ad. Sidebar ve
/// sohbetteki yüzlerin ortak popover içeriği.
struct AvatarZoomCard<Face: View>: View {
    let name: String
    var subtitle: String? = nil
    var onPickPhoto: (() -> Void)? = nil
    @ViewBuilder var face: () -> Face

    var body: some View {
        VStack(spacing: 13) {
            face()
                .frame(width: 168, height: 168)
                .clipShape(Circle())

            VStack(spacing: 2) {
                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let onPickPhoto {
                Button("Fotoğrafı değiştir", action: onPickPhoto)
                    .controlSize(.small)
            }
        }
        .padding(18)
        .frame(width: 212)
    }
}

// MARK: - Avatar fallback paleti

/// Buzz avatar fallback'i: ada göre deterministik renk (hash*31+codePoint mod 7)
/// üstünde yarı-kalın baş harf — UserAvatar.tsx ile aynı 7'li palet.
enum AvatarPalette {
    static let colors: [(bg: UInt32, fg: Color)] = [
        (0x3B82F6, .white), (0x10B981, .white), (0xFBBF24, Color(hex: 0x451A03)),
        (0xF43F5E, .white), (0x22D3EE, Color(hex: 0x083344)), (0x8B5CF6, .white),
        (0xF97316, .white),
    ]

    static func color(for name: String) -> (bg: UInt32, fg: Color) {
        var hash = 0
        for scalar in name.lowercased().unicodeScalars { hash = hash &* 31 &+ Int(scalar.value) }
        let count = colors.count
        return colors[((hash % count) + count) % count]
    }
}
