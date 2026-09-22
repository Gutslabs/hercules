#if os(macOS)
import Foundation
import Observation
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Iroh relay yardımcı sürecinin sahibi.
///
/// Relay neden ayrı süreç: `Iroh.xcframework` ile hafıza aramasının kullandığı
/// `sentencepiece.xcframework` aynı `include/module.modulemap` yoluna yazıyor;
/// ikisini tek hedefte linklemek Xcode'da çakışıyor. Ayrı hedef bunu çözüyor ve
/// bonus olarak relay, bugün Tailscale Serve'ün yaptığı işi yapıyor — QUIC'i
/// loopback'teki RemoteAIServer'a taşıyor.
@MainActor
@Observable
final class IrohRelayHost {
    static let shared = IrohRelayHost()

    private(set) var endpointID: String?
    private(set) var ticket: String?
    private(set) var pending: [String] = []
    private(set) var paired: [String] = []
    private(set) var lastError: String?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var pollTimer: Timer?

    private init() {}

    var isRunning: Bool { process?.isRunning == true }

    /// Uygulama ile birlikte başlar. Binary app bundle'ının içinde durur
    /// (kurulum betiği kopyalar); yoksa sessizce atlanır ve Tailscale yolu kalır.
    func start() {
        guard process == nil else { return }
        let binary = Bundle.main.bundleURL
            .appendingPathComponent("Contents/MacOS/hercules-iroh-relay")
        guard FileManager.default.isExecutableFile(atPath: binary.path) else {
            lastError = "Relay binary'si bundle'da yok. ./scripts/mac-build-install.sh Release ile kur."
            return
        }
        let task = Process()
        task.executableURL = binary
        // Relay stderr'e log basar; uygulama günlüğüne karışmasın diye yutuyoruz.
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            process = task
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            return
        }
        refresh()
        // Relay kimliği bind + relay seçiminden sonra netleşiyor; kısa aralıkla
        // yoklayıp eşleşme bekleyenleri de aynı turda topluyoruz.
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        process?.terminate()
        process = nil
    }

    func refresh() {
        if let published = IrohPairedPeers.published() {
            endpointID = published.endpointId.isEmpty ? nil : published.endpointId
            ticket = published.ticket.isEmpty ? nil : published.ticket
        }
        let peers = IrohPairedPeers.load()
        pending = peers.pending
        paired = peers.paired
    }

    func approve(_ endpoint: String) {
        IrohPairedPeers.pair(endpoint)
        refresh()
    }

    func reject(_ endpoint: String) {
        IrohPairedPeers.reject(endpoint)
        refresh()
    }

    func revoke(_ endpoint: String) {
        IrohPairedPeers.revoke(endpoint)
        refresh()
    }

    /// Ticket'ın QR görüntüsü. Telefon bunu okuyunca Mac'i public key ile bulur.
    func qrImage(side: CGFloat) -> NSImage? {
        guard let ticket, !ticket.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(ticket.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = side / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let context = CIContext()
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: side, height: side))
    }
}
#endif
