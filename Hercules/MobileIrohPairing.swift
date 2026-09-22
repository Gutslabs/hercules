import SwiftUI
import AVFoundation
import LucideKit

// ---------------------------------------------------------------------------
// TELEFON BAĞLANTISI — Mac'in QR'ını okut, eşleşmeyi Mac'ten onayla.
//
// Akış: Mac ▸ Profil ▸ Telefon bağlantısı bir QR gösterir (Mac'in Iroh ticket'ı:
// public key + güncel adresler, secret YOK). Telefon okur, Mac'e bağlanmayı
// dener. İlk bağlantıda telefon "eşleşmemiş" olduğu için relay onu YALNIZ
// eşleştirme yoluna bırakır ve Mac'te "onayla" satırı belirir. Onaydan sonra
// tüm istekler Iroh üzerinden gider; Tailscale gerekmez.
// ---------------------------------------------------------------------------

@MainActor
@Observable
final class MobileIrohPairingModel {
    var macEndpoint: String? = HerculesIrohTransport.macEndpoint
    var localEndpoint: String?
    var status: String?
    var isPaired = false
    var isPending = false
    var busy = false

    func load() async {
        macEndpoint = HerculesIrohTransport.macEndpoint
        localEndpoint = await HerculesIrohTransport.localEndpointID()
        guard macEndpoint != nil else { return }
        await refreshStatus()
    }

    /// QR'dan gelen ticket. Geçersizse hiçbir şey yazılmaz.
    func apply(ticket: String) async {
        guard let id = HerculesIrohTransport.pair(ticket: ticket) else {
            status = "Bu QR bir Hercules bağlantı kodu değil."
            return
        }
        macEndpoint = id
        status = "Mac bulundu — şimdi Mac'ten onayla."
        await refreshStatus()
    }

    func refreshStatus() async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let result = try await RemoteAIClient().irohPairStatus()
            isPaired = result.paired
            isPending = result.pending
            localEndpoint = result.endpointId.isEmpty ? localEndpoint : result.endpointId
            status = result.paired
                ? "Bağlı — istekler Iroh üzerinden gidiyor."
                : (result.pending ? "Mac'te onay bekliyor." : "Mac bu telefonu henüz görmedi.")
        } catch {
            status = "Mac'e ulaşılamadı. Mac açık ve Hercules çalışıyor mu?"
        }
    }

    func unpair() {
        HerculesIrohTransport.unpair()
        macEndpoint = nil
        isPaired = false
        isPending = false
        status = nil
    }
}

struct MobileIrohPairingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var model = MobileIrohPairingModel()
    @State private var showScanner = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Mac'teki Hercules'te Profil ▸ Telefon bağlantısı'ndaki kodu okut. Tailscale ya da VPN profili gerekmez.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button { showScanner = true } label: {
                        HStack(spacing: 8) {
                            Lucide(sf: "camera", size: 13)
                            Text(model.macEndpoint == nil ? "QR kodu okut" : "Yeniden okut")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Palette.btnFg)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Palette.btnBg))
                    }
                    .buttonStyle(.plain)

                    if let status = model.status {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(model.isPaired ? Palette.positive : (model.isPending ? Palette.warning : Palette.textQuaternary))
                                .frame(width: 6, height: 6)
                            Text(status)
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if let mac = model.macEndpoint {
                        row("Mac kimliği", mac)
                    }
                    if let local = model.localEndpoint {
                        // Mac'teki onay satırında bu kimliğin baş harfleri görünür;
                        // doğru telefonu onayladığından emin olabilesin diye burada.
                        row("Bu telefon", local)
                    }

                    if model.macEndpoint != nil {
                        HStack(spacing: 14) {
                            Button("Durumu yenile") { Task { await model.refreshStatus() } }
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Palette.accent)
                                .buttonStyle(.plain)
                            Button("Bağlantıyı kaldır") { model.unpair() }
                                .font(.system(size: 12))
                                .foregroundStyle(Palette.negative)
                                .buttonStyle(.plain)
                        }
                    }
                }
                .padding(20)
            }
            .background(Palette.background.ignoresSafeArea())
            .navigationTitle("Telefon bağlantısı")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }
                }
            }
        }
        .task { await model.load() }
        .sheet(isPresented: $showScanner) {
            MobileQRScannerView { code in
                showScanner = false
                Task { await model.apply(ticket: code) }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased(with: Locale(identifier: "tr_TR")))
                .font(.system(size: 10, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Palette.textTertiary)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

// MARK: - QR okuyucu

struct MobileQRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var delivered = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.videoGravity = .resizeAspectFill
            preview.frame = view.bounds
            view.layer.addSublayer(preview)
            // Oturumu başlatmak ana thread'i kilitleyebiliyor.
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            view.layer.sublayers?.first?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            session.stopRunning()
        }

        func metadataOutput(
            _ output: AVCaptureMetadataOutput,
            didOutput objects: [AVMetadataObject],
            from connection: AVCaptureConnection
        ) {
            guard !delivered,
                  let object = objects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue else { return }
            delivered = true
            session.stopRunning()
            onCode?(value)
        }
    }
}
