import SwiftUI
import AppKit

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.title = "FilmDown"
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert([.titled, .closable, .miniaturizable, .fullSizeContentView])
                window.isMovableByWindowBackground = true
                window.backgroundColor = .clear
                window.minSize = NSSize(width: 580, height: 500)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

class DownloaderModel: ObservableObject {
    @Published var urlText: String = ""
    @Published var destPath: String = ""
    @Published var separateFolders: Bool = true
    @Published var preventCollision: Bool = true
    @Published var isDownloading: Bool = false
    @Published var progressValue: Double = 0.0
    @Published var statusMessage: String = "İndirmeye hazır"
    @Published var currentSpeed: String = ""
    @Published var currentEta: String = ""

    private var process: Process?
    private var tempUrlsFile: URL?

    init() {
        let defaultDesktop = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Desktop/ALPTUĞ İÇERİK")
        if FileManager.default.fileExists(atPath: defaultDesktop) {
            destPath = defaultDesktop
        } else {
            destPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Downloads")
        }
    }

    var validUrlCount: Int {
        urlText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
            .count
    }

    func browseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Seç"
        panel.directoryURL = URL(fileURLWithPath: destPath)

        if panel.runModal() == .OK, let url = panel.url {
            destPath = url.path
        }
    }

    func openFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: destPath)
    }

    func clearInput() {
        guard !isDownloading else { return }
        urlText = ""
        progressValue = 0.0
        statusMessage = "İndirmeye hazır"
    }

    func toggleDownload() {
        if isDownloading {
            stopDownload()
        } else {
            startDownload()
        }
    }

    func stopDownload() {
        process?.terminate()
        process = nil
        isDownloading = false
        statusMessage = "İndirme işlemi kullanıcı tarafından durduruldu"
    }

    func startDownload() {
        let urls = urlText.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard !urls.isEmpty else {
            statusMessage = "Lütfen en az bir video bağlantısı girin"
            return
        }

        isDownloading = true
        progressValue = 0.0
        statusMessage = "İndirme başlatılıyor..."

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("filmdown_urls_\(UUID().uuidString).txt")
        self.tempUrlsFile = tempFile
        let fileContent = urls.joined(separator: "\n")
        do {
            try fileContent.write(to: tempFile, atomically: true, encoding: .utf8)
        } catch {
            statusMessage = "Geçici dosya oluşturulamadı: \(error.localizedDescription)"
            isDownloading = false
            return
        }

        let pythonPath = findPython()
        let enginePath = findEngine()

        guard let py = pythonPath, let eng = enginePath else {
            statusMessage = "Python veya indirme motoru bulunamadı"
            isDownloading = false
            return
        }

        var args = [eng, "--urls-file", tempFile.path, "--dest", destPath]
        if separateFolders { args.append("--separate-folders") }
        if preventCollision { args.append("--prevent-collision") }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: py)
        proc.arguments = args

        var env = ProcessInfo.processInfo.environment
        env["PYTHONWARNINGS"] = "ignore"
        let extraPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/Library/Frameworks/Python.framework/Versions/3.10/bin",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin").path
        ]
        let currentPath = env["PATH"] ?? ""
        env["PATH"] = extraPaths.joined(separator: ":") + ":" + currentPath
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        var buffer = ""
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            buffer += chunk
            while let newlineRange = buffer.range(of: "\n") {
                let line = String(buffer[..<newlineRange.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                buffer.removeSubrange(...newlineRange.lowerBound)
                if !line.isEmpty {
                    self?.handleEngineLine(line)
                }
            }
        }

        proc.terminationHandler = { [weak self] p in
            DispatchQueue.main.async {
                self?.isDownloading = false
                self?.process = nil
                pipe.fileHandleForReading.readabilityHandler = nil
                if let tmp = self?.tempUrlsFile {
                    try? FileManager.default.removeItem(at: tmp)
                }
            }
        }

        self.process = proc

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try proc.run()
            } catch {
                DispatchQueue.main.async {
                    self.statusMessage = "Başlatma hatası: \(error.localizedDescription)"
                    self.isDownloading = false
                }
            }
        }
    }

    private func handleEngineLine(_ line: String) {
        guard let data = line.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            return
        }

        DispatchQueue.main.async {
            switch type {
            case "batch_start":
                let total = json["total"] as? Int ?? 1
                self.statusMessage = "\(total) video taranıyor..."
            case "item_start":
                let idx = json["index"] as? Int ?? 1
                let total = json["total"] as? Int ?? 1
                self.statusMessage = "Video \(idx) / \(total) indiriliyor..."
            case "item_progress":
                let idx = json["index"] as? Int ?? 1
                let total = json["total"] as? Int ?? 1
                let percent = json["percent"] as? Double ?? 0.0
                let speed = json["speed"] as? String ?? ""
                let eta = json["eta"] as? String ?? ""

                let itemFraction = (Double(idx - 1) + (percent / 100.0)) / Double(total)
                self.progressValue = min(max(itemFraction, 0.0), 1.0)

                var status = "Video \(idx) / \(total) — %\(String(format: "%.1f", percent))"
                if !speed.isEmpty { status += " • \(speed)" }
                if !eta.isEmpty { status += " • Kalan: \(eta)" }
                self.statusMessage = status
            case "item_processing":
                let idx = json["index"] as? Int ?? 1
                let total = json["total"] as? Int ?? 1
                let msg = json["message"] as? String ?? "İşleniyor..."
                self.statusMessage = "Video \(idx) / \(total) — \(msg)"
            case "item_complete":
                let idx = json["index"] as? Int ?? 1
                let total = json["total"] as? Int ?? 1
                let title = json["title"] as? String ?? "Video"
                self.progressValue = Double(idx) / Double(total)
                self.statusMessage = "Video \(idx) / \(total) tamamlandı: \(title)"
            case "item_error":
                let idx = json["index"] as? Int ?? 1
                let total = json["total"] as? Int ?? 1
                let err = json["error"] as? String ?? "Hata"
                self.statusMessage = "Video \(idx) / \(total) indirilemedi: \(err)"
            case "all_done":
                let total = json["total"] as? Int ?? 0
                let success = json["success_count"] as? Int ?? 0
                self.progressValue = 1.0
                if total == 0 {
                    self.statusMessage = "İndirilecek video bulunamadı"
                } else if success == total {
                    self.statusMessage = "Tüm indirmeler tamamlandı (\(success) / \(total) video başarıyla kaydedildi)"
                } else {
                    self.statusMessage = "İşlem bitti (\(success) / \(total) video kaydedildi)"
                }
            default:
                break
            }
        }
    }

    private func findPython() -> String? {
        let candidates = [
            "/Library/Frameworks/Python.framework/Versions/3.10/bin/python3",
            "/usr/local/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/bin/python3"
        ]
        for c in candidates {
            if FileManager.default.isExecutableFile(atPath: c) {
                return c
            }
        }
        return "/usr/bin/python3"
    }

    private func findEngine() -> String? {
        if let bundleResource = Bundle.main.path(forResource: "engine", ofType: "py") {
            return bundleResource
        }
        let directApp = "/Users/alptug/Desktop/ALPTUĞ İÇERİK/FilmDown.app/Contents/Resources/engine.py"
        if FileManager.default.fileExists(atPath: directApp) {
            return directApp
        }
        let repoEngine = "/Users/alptug/.gemini/antigravity/scratch/FilmDown/src/engine.py"
        if FileManager.default.fileExists(atPath: repoEngine) {
            return repoEngine
        }
        return nil
    }
}

struct LiquidGlassCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    var body: some View {
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.28))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

struct FilmDownMainView: View {
    @StateObject private var model = DownloaderModel()

    var body: some View {
        ZStack {
            VisualEffectBackground()
            WindowConfigurator()

            VStack(spacing: 16) {
                // Header Bar
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("FilmDown")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                        Text("Yüksek Kaliteli Video ve Medya İndirici")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.55))
                    }
                    Spacer()
                    if model.validUrlCount > 0 {
                        Text("\(model.validUrlCount) Bağlantı")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(Color.cyan)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.cyan.opacity(0.15))
                                    .overlay(Capsule().stroke(Color.cyan.opacity(0.3), lineWidth: 1))
                            )
                    }
                }
                .padding(.top, 8)

                // URL Input Card
                LiquidGlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("BAĞLANTI LİSTESİ")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.5))
                            Spacer()
                            Text("Her satıra bir adres")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(Color.white.opacity(0.35))
                        }

                        ZStack(alignment: .topLeading) {
                            if model.urlText.isEmpty {
                                Text("Video veya akış bağlantılarını buraya yapıştırın...\nhttps://...\nhttps://...")
                                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                                    .foregroundColor(Color.white.opacity(0.25))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 10)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $model.urlText)
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundColor(.white)
                                .scrollContentBackground(.hidden)
                                .background(Color.black.opacity(0.25))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                )
                                .frame(height: 110)
                        }
                    }
                }

                // Options & Destination Card
                LiquidGlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        // Destination Path
                        VStack(alignment: .leading, spacing: 6) {
                            Text("HEDEF KLASÖR")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.5))

                            HStack(spacing: 8) {
                                Text(model.destPath)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundColor(Color.white.opacity(0.85))
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.black.opacity(0.3))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )

                                Button(action: { model.browseFolder() }) {
                                    Text("Gözat...")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(Color.white.opacity(0.1))
                                        .cornerRadius(6)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }

                        Divider()
                            .background(Color.white.opacity(0.1))

                        // Toggles
                        HStack(spacing: 24) {
                            Toggle("Her video için ayrı klasör", isOn: $model.separateFolders)
                                .toggleStyle(SwitchToggleStyle(tint: Color.cyan))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)

                            Toggle("Çakışma koruması (Üzerine yazma)", isOn: $model.preventCollision)
                                .toggleStyle(SwitchToggleStyle(tint: Color.cyan))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                        }
                    }
                }

                // Progress Card (Loading Bar)
                LiquidGlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("DURUM")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.5))
                            Spacer()
                            if model.isDownloading {
                                Text("%\(Int(model.progressValue * 100))")
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundColor(Color.cyan)
                            }
                        }

                        // Loading Bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.black.opacity(0.4))
                                    .frame(height: 8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 1)
                                    )

                                RoundedRectangle(cornerRadius: 4)
                                    .fill(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.blue, Color.cyan]),
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .frame(width: max(geo.size.width * CGFloat(model.progressValue), model.isDownloading ? 12 : 0), height: 8)
                                    .animation(.linear(duration: 0.2), value: model.progressValue)
                            }
                        }
                        .frame(height: 8)

                        Text(model.statusMessage)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.75))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Spacer()

                // Action Bar (Bottom)
                HStack(spacing: 12) {
                    Button(action: { model.openFolder() }) {
                        Text("Klasörü Aç")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()

                    Button(action: { model.clearInput() }) {
                        Text("Temizle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.6))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(model.isDownloading)

                    Button(action: { model.toggleDownload() }) {
                        HStack(spacing: 6) {
                            Text(model.isDownloading ? "Durdur" : "İndirmeyi Başlat")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(
                            Group {
                                if model.isDownloading {
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.red.opacity(0.8), Color.pink.opacity(0.8)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                } else {
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.blue, Color.cyan.opacity(0.9)]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                }
                            }
                        )
                        .cornerRadius(8)
                        .shadow(color: model.isDownloading ? Color.red.opacity(0.3) : Color.cyan.opacity(0.3), radius: 6, y: 2)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.bottom, 6)
            }
            .padding(18)
        }
        .frame(minWidth: 580, idealWidth: 620, maxWidth: 700, minHeight: 520, idealHeight: 540, maxHeight: 600)
    }
}

@main
struct FilmDownAppMain: App {
    var body: some Scene {
        WindowGroup {
            FilmDownMainView()
        }
        .windowStyle(HiddenTitleBarWindowStyle())
    }
}
