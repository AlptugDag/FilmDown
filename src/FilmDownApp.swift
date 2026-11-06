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
                // Non-resizable fixed window size
                window.styleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
                window.isMovableByWindowBackground = true
                window.backgroundColor = .clear
                let fixedSize = NSSize(width: 660, height: 610)
                window.setContentSize(fixedSize)
                window.minSize = fixedSize
                window.maxSize = fixedSize
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct DownloadItem: Identifiable, Equatable {
    let id = UUID()
    var url: String
    var destPath: String
    var statusText: String = "Bekliyor"
    var percent: Double = 0.0
    var isDownloading: Bool = false
    var isDone: Bool = false
    var isError: Bool = false
}

class DownloaderModel: ObservableObject {
    @Published var queue: [DownloadItem] = []
    @Published var inputUrl: String = ""
    @Published var defaultDestPath: String = ""
    @Published var separateFolders: Bool = true
    @Published var isDownloading: Bool = false
    @Published var progressValue: Double = 0.0
    @Published var statusMessage: String = "İndirmeye hazır"

    private var process: Process?
    private var tempQueueFile: URL?

    init() {
        let defaultDesktop = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Desktop/ALPTUĞ İÇERİK")
        if FileManager.default.fileExists(atPath: defaultDesktop) {
            defaultDestPath = defaultDesktop
        } else {
            defaultDestPath = (FileManager.default.homeDirectoryForCurrentUser.path as NSString).appendingPathComponent("Downloads")
        }
    }

    func browseDefaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Varsayılan Yap"
        panel.directoryURL = URL(fileURLWithPath: defaultDestPath)

        if panel.runModal() == .OK, let url = panel.url {
            defaultDestPath = url.path
        }
    }

    func browseItemFolder(id: UUID) {
        guard !isDownloading else { return }
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Bu Video İçin Seç"
        panel.directoryURL = URL(fileURLWithPath: queue[idx].destPath)

        if panel.runModal() == .OK, let url = panel.url {
            queue[idx].destPath = url.path
        }
    }

    func addUrlsFromInput() {
        addUrls(inputUrl)
        inputUrl = ""
    }

    func pasteFromClipboard() {
        if let clip = NSPasteboard.general.string(forType: .string) {
            addUrls(clip)
        }
    }

    func addUrls(_ raw: String) {
        guard !isDownloading else { return }
        let lines = raw.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        for u in lines {
            // Avoid adding identical pending URLs
            if !queue.contains(where: { $0.url == u }) {
                queue.append(DownloadItem(url: u, destPath: defaultDestPath))
            }
        }
        if !queue.isEmpty {
            statusMessage = "\(queue.count) video indirilmeye hazır"
        }
    }

    func removeItem(id: UUID) {
        guard !isDownloading else { return }
        queue.removeAll(where: { $0.id == id })
        if queue.isEmpty {
            statusMessage = "İndirmeye hazır"
            progressValue = 0.0
        } else {
            statusMessage = "\(queue.count) video kuyrukta"
        }
    }

    func clearQueue() {
        guard !isDownloading else { return }
        queue.removeAll()
        progressValue = 0.0
        statusMessage = "İndirmeye hazır"
    }

    func openFolder() {
        let path = queue.first?.destPath ?? defaultDestPath
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
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
        guard !queue.isEmpty else {
            statusMessage = "Lütfen önce en az bir video bağlantısı ekleyin"
            return
        }

        isDownloading = true
        progressValue = 0.0
        statusMessage = "İndirme başlatılıyor..."

        for i in 0..<queue.count {
            queue[i].statusText = "Bekliyor"
            queue[i].percent = 0.0
            queue[i].isDownloading = false
            queue[i].isDone = false
            queue[i].isError = false
        }

        // Save queue as JSON file
        let queuePayload = queue.map { ["url": $0.url, "dest": $0.destPath] }
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent("filmdown_queue_\(UUID().uuidString).json")
        self.tempQueueFile = tempFile

        do {
            let data = try JSONSerialization.data(withJSONObject: queuePayload, options: .prettyPrinted)
            try data.write(to: tempFile)
        } catch {
            statusMessage = "Kuyruk dosyası oluşturulamadı: \(error.localizedDescription)"
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

        var args = [eng, "--queue-file", tempFile.path, "--dest", defaultDestPath]
        if separateFolders { args.append("--separate-folders") }
        // prevent_collision is permanently active in engine

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
                if let tmp = self?.tempQueueFile {
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
                let itemIdx = idx - 1
                if itemIdx >= 0 && itemIdx < self.queue.count {
                    for i in 0..<self.queue.count {
                        if i < itemIdx { self.queue[i].isDownloading = false }
                    }
                    self.queue[itemIdx].isDownloading = true
                    self.queue[itemIdx].statusText = "İndiriliyor..."
                }
                self.statusMessage = "Video \(idx) / \(total) indiriliyor..."
            case "item_progress":
                let idx = json["index"] as? Int ?? 1
                let total = json["total"] as? Int ?? 1
                let percent = json["percent"] as? Double ?? 0.0
                let speed = json["speed"] as? String ?? ""
                let eta = json["eta"] as? String ?? ""

                let itemIdx = idx - 1
                if itemIdx >= 0 && itemIdx < self.queue.count {
                    self.queue[itemIdx].percent = percent
                    var sub = "%\(String(format: "%.1f", percent))"
                    if !speed.isEmpty { sub += " • \(speed)" }
                    self.queue[itemIdx].statusText = sub
                }

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
                let itemIdx = idx - 1
                if itemIdx >= 0 && itemIdx < self.queue.count {
                    self.queue[itemIdx].statusText = msg
                }
                self.statusMessage = "Video \(idx) / \(total) — \(msg)"
            case "item_complete":
                let idx = json["index"] as? Int ?? 1
                let total = json["total"] as? Int ?? 1
                let title = json["title"] as? String ?? "Video"
                let itemIdx = idx - 1
                if itemIdx >= 0 && itemIdx < self.queue.count {
                    self.queue[itemIdx].isDownloading = false
                    self.queue[itemIdx].isDone = true
                    self.queue[itemIdx].percent = 100.0
                    self.queue[itemIdx].statusText = "Tamamlandı"
                }
                self.progressValue = Double(idx) / Double(total)
                self.statusMessage = "Video \(idx) / \(total) tamamlandı: \(title)"
            case "item_error":
                let idx = json["index"] as? Int ?? 1
                let total = json["total"] as? Int ?? 1
                let err = json["error"] as? String ?? "Hata"
                let itemIdx = idx - 1
                if itemIdx >= 0 && itemIdx < self.queue.count {
                    self.queue[itemIdx].isDownloading = false
                    self.queue[itemIdx].isError = true
                    self.queue[itemIdx].statusText = "Hata"
                }
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
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.30))
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

            VStack(spacing: 12) {
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
                    if !model.queue.isEmpty {
                        Text("\(model.queue.count) Video")
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
                .padding(.top, 4)

                // Default Destination Card
                LiquidGlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Text("VARSAYILAN HEDEF:")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.5))

                            Text(model.defaultDestPath)
                                .font(.system(size: 11, weight: .regular))
                                .foregroundColor(Color.white.opacity(0.85))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Button(action: { model.browseDefaultFolder() }) {
                                Text("Gözat...")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(Color.white.opacity(0.1))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }

                        Divider()
                            .background(Color.white.opacity(0.1))

                        HStack {
                            Toggle("Her video için ayrı alt klasör oluştur", isOn: $model.separateFolders)
                                .toggleStyle(SwitchToggleStyle(tint: Color.cyan))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.white)
                            Spacer()
                            Text("Çakışma koruması devrede")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(Color.white.opacity(0.4))
                        }
                    }
                }

                // Add URL Input Bar
                HStack(spacing: 8) {
                    TextField("Video veya akış bağlantısını girin...", text: $model.inputUrl, onCommit: {
                        model.addUrlsFromInput()
                    })
                    .textFieldStyle(PlainTextFieldStyle())
                    .font(.system(size: 12, weight: .regular, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.12), lineWidth: 1)
                    )
                    .disabled(model.isDownloading)

                    Button(action: { model.addUrlsFromInput() }) {
                        Text("Ekle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(model.isDownloading || model.inputUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(action: { model.pasteFromClipboard() }) {
                        Text("Panodan Ekle")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color.cyan)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color.cyan.opacity(0.12))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(model.isDownloading)
                }

                // Queue List Card
                LiquidGlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("İNDİRME LİSTESİ")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundColor(Color.white.opacity(0.5))
                            Spacer()
                            Text("Her video için ayrı hedef klasör seçebilirsiniz")
                                .font(.system(size: 10, weight: .regular))
                                .foregroundColor(Color.white.opacity(0.35))
                        }

                        if model.queue.isEmpty {
                            VStack(spacing: 6) {
                                Spacer()
                                Text("Kuyrukta video bulunmuyor.")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(Color.white.opacity(0.45))
                                Text("Yukarıdaki kutudan bağlantı ekleyebilir veya 'Panodan Ekle'yi kullanabilirsiniz.")
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundColor(Color.white.opacity(0.3))
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 185)
                        } else {
                            ScrollView(.vertical, showsIndicators: true) {
                                LazyVStack(spacing: 8) {
                                    ForEach(Array(model.queue.enumerated()), id: \.element.id) { index, item in
                                        HStack(alignment: .center, spacing: 8) {
                                            Text("\(index + 1).")
                                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                                .foregroundColor(item.isDownloading ? Color.cyan : Color.white.opacity(0.5))
                                                .frame(width: 22, alignment: .trailing)

                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(item.url)
                                                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                                                    .foregroundColor(.white)
                                                    .lineLimit(1)
                                                    .truncationMode(.middle)

                                                HStack(spacing: 6) {
                                                    Text("Hedef: \(item.destPath)")
                                                        .font(.system(size: 10, weight: .regular))
                                                        .foregroundColor(Color.white.opacity(0.55))
                                                        .lineLimit(1)
                                                        .truncationMode(.middle)

                                                    if item.isDownloading || item.isDone || item.isError {
                                                        Text("• \(item.statusText)")
                                                            .font(.system(size: 10, weight: .medium))
                                                            .foregroundColor(item.isDone ? Color.green : (item.isError ? Color.red : Color.cyan))
                                                    }
                                                }
                                            }
                                            .frame(maxWidth: .infinity, alignment: .leading)

                                            Button(action: { model.browseItemFolder(id: item.id) }) {
                                                Text("Klasör Seç")
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(Color.cyan)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.cyan.opacity(0.12))
                                                    .cornerRadius(6)
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 6)
                                                            .stroke(Color.cyan.opacity(0.25), lineWidth: 1)
                                                    )
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .disabled(model.isDownloading)

                                            Button(action: { model.removeItem(id: item.id) }) {
                                                Text("Sil")
                                                    .font(.system(size: 10, weight: .medium))
                                                    .foregroundColor(Color.white.opacity(0.45))
                                                    .padding(.horizontal, 6)
                                                    .padding(.vertical, 4)
                                            }
                                            .buttonStyle(PlainButtonStyle())
                                            .disabled(model.isDownloading)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 6)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(item.isDownloading ? Color.cyan.opacity(0.1) : Color.black.opacity(0.2))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(item.isDownloading ? Color.cyan.opacity(0.3) : Color.white.opacity(0.06), lineWidth: 1)
                                        )
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .frame(height: 185)
                        }
                    }
                }

                // Progress Loading Bar Card
                LiquidGlassCard {
                    VStack(alignment: .leading, spacing: 6) {
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
                                    .frame(height: 7)
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
                                    .frame(width: max(geo.size.width * CGFloat(model.progressValue), model.isDownloading ? 12 : 0), height: 7)
                                    .animation(.linear(duration: 0.2), value: model.progressValue)
                            }
                        }
                        .frame(height: 7)

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
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .buttonStyle(PlainButtonStyle())

                    Spacer()

                    Button(action: { model.clearQueue() }) {
                        Text("Tümünü Temizle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.6))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.white.opacity(0.05))
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .disabled(model.isDownloading || model.queue.isEmpty)

                    Button(action: { model.toggleDownload() }) {
                        HStack(spacing: 6) {
                            Text(model.isDownloading ? "Durdur" : "İndirmeyi Başlat")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 22)
                        .padding(.vertical, 7)
                        .background(
                            Group {
                                if model.isDownloading {
                                    LinearGradient(
                                        gradient: Gradient(colors: [Color.red.opacity(0.85), Color.pink.opacity(0.85)]),
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
                    .disabled(model.queue.isEmpty && !model.isDownloading)
                }
                .padding(.bottom, 4)
            }
            .padding(16)
        }
        .frame(width: 660, height: 610)
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
