import AppKit
import SwiftUI

/// Кэш картинок: память + диск. Иконки станций не меняются, обложки треков — редко,
/// так что после первого прогона сеть почти не используется.
actor ImageStore {
    static let shared = ImageStore()

    private var memory = NSCache<NSString, NSImage>()
    private var inFlight: [InFlightKey: Task<NSImage?, Never>] = [:]

    private let directory: URL = {
        let dir = DiskCache.directory.appendingPathComponent("images", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {
        memory.countLimit = 400
    }

    /// - Parameter maxPixel: до какого размера ужимать при декодировании.
    ///   Иконки станций приходят в 600 px, а показываются в 72 — держать в памяти
    ///   полный размер значило бы ~1,4 МБ на карточку и сотни мегабайт на весь список.
    func image(for url: URL, maxPixel: Int = 512) async -> NSImage? {
        let key = "\(url.absoluteString)|\(maxPixel)" as NSString
        if let cached = memory.object(forKey: key) { return cached }

        let requestKey = InFlightKey(url: url, maxPixel: maxPixel)
        if let existing = inFlight[requestKey] { return await existing.value }

        let task = Task<NSImage?, Never> { [directory] in
            let fileURL = directory.appendingPathComponent(Self.filename(for: url))

            if let data = try? Data(contentsOf: fileURL) {
                if let image = Self.decode(data, maxPixel: maxPixel) { return image }
                // Файл на диске оказался нечитаемым — выкидываем и качаем заново,
                // иначе однажды сохранённый мусор навсегда ломает эту обложку.
                try? FileManager.default.removeItem(at: fileURL)
            }

            guard let (data, response) = try? await URLSession.shared.data(from: url) else { return nil }
            // Без этой проверки страница ошибки от CDN легла бы в кэш как «картинка».
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                return nil
            }
            guard !data.isEmpty, let image = Self.decode(data, maxPixel: maxPixel) else { return nil }
            try? data.write(to: fileURL, options: .atomic)
            return image
        }
        inFlight[requestKey] = task
        let result = await task.value
        inFlight[requestKey] = nil
        if let result { memory.setObject(result, forKey: key) }
        return result
    }

    /// Декодирование сразу в нужный размер: ImageIO разворачивает уменьшенную копию,
    /// не поднимая в память полноразмерный битмап.
    private static func decode(_ data: Data, maxPixel: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            return NSImage(data: data)
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return NSImage(data: data)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    private struct InFlightKey: Hashable {
        let url: URL
        let maxPixel: Int
    }

    private static func filename(for url: URL) -> String {
        var hash: UInt64 = 5381
        for byte in url.absoluteString.utf8 {
            hash = (hash &* 33) &+ UInt64(byte)
        }
        let ext = url.pathExtension.isEmpty ? "img" : url.pathExtension
        return "\(String(hash, radix: 36)).\(ext)"
    }
}

/// SwiftUI-обёртка вокруг ImageStore с плавным появлением.
struct CachedImage<Placeholder: View>: View {
    let url: URL?
    var contentMode: ContentMode = .fit
    var maxPixel: Int = 512
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var image: NSImage?
    @State private var loadedURL: URL?

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                placeholder()
            }
        }
        .task(id: url) {
            guard let url else {
                image = nil
                return
            }
            guard loadedURL != url else { return }
            let loaded = await ImageStore.shared.image(for: url, maxPixel: maxPixel)
            guard !Task.isCancelled else { return }
            // Если загрузка не удалась — оставляем то, что уже показано, и не
            // помечаем адрес загруженным: при следующем появлении попробуем снова.
            // Иначе одна сетевая осечка гасила обложку навсегда.
            guard let loaded else { return }
            withAnimation(.easeOut(duration: 0.18)) {
                image = loaded
                loadedURL = url
            }
        }
    }
}

extension CachedImage where Placeholder == Color {
    init(url: URL?, contentMode: ContentMode = .fit, maxPixel: Int = 512) {
        self.init(url: url, contentMode: contentMode, maxPixel: maxPixel) { Color.clear }
    }
}
