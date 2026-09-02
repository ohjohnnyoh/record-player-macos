import AppKit
import SwiftUI

/// Цвета, снятые с обложки. Ими окрашивается фон полноразмерного экрана —
/// так же, как это делает Apple Music в развёрнутом плеере.
///
/// Храним компонентами, а не готовым `Color`: разбор идёт вне главного потока,
/// а значения должны спокойно пересекать границу актора.
struct ArtworkPalette: Equatable, Sendable {
    struct Swatch: Equatable, Sendable {
        var red: Double
        var green: Double
        var blue: Double

        var color: Color { Color(red: red, green: green, blue: blue) }
    }

    /// Основа, заливающая весь экран.
    var base: Swatch
    /// Главное цветное пятно — кладётся под обложку.
    var primary: Swatch
    /// Второе пятно с другой стороны, чтобы фон не был плоским.
    var secondary: Swatch
}

/// Разбор обложки на доминирующие цвета.
///
/// Намеренно без k-means и прочей кластеризации: обложка ужимается до 32×32,
/// и тысяча пикселей раскладывается по корзинам оттенка. Этого достаточно,
/// чтобы поймать крупные пятна, а стоит разбор доли миллисекунды — важно,
/// потому что на радио трек меняется каждые три минуты.
enum ArtworkPaletteExtractor {
    /// Сторона квадрата, в который ужимается обложка перед разбором.
    static let sampleSide = 32
    /// Ширина корзины оттенка в градусах. 15° — шестнадцать оттенков на круг:
    /// красный и оранжевый уже различаются, но шум не дробит крупное пятно.
    static let hueStep = 15.0
    /// Ниже этой насыщенности цвет считается серым и идёт в отдельную корзину:
    /// у почти чёрно-белой обложки оттенок — это шум сжатия, а не замысел.
    static let neutralSaturation = 0.12

    static func palette(from image: NSImage) -> ArtworkPalette? {
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        return palette(from: cgImage)
    }

    static func palette(from image: CGImage) -> ArtworkPalette? {
        guard let pixels = downsample(image) else { return nil }
        return palette(fromPixels: pixels)
    }

    // MARK: - Разбор

    /// - Parameter pixels: RGBA8, ряд за рядом.
    static func palette(fromPixels pixels: [UInt8]) -> ArtworkPalette? {
        var buckets: [Int: Bucket] = [:]
        var opaquePixels = 0

        for offset in stride(from: 0, to: pixels.count - 3, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            // Логотипы станций приходят с прозрачным фоном. Считать его чёрным
            // значило бы красить экран в чёрный у любой такой картинки.
            guard alpha > 0.35 else { continue }

            // Контекст отдаёт premultiplied-цвет: у полупрозрачного пикселя
            // компоненты уже умножены на альфу. Без деления сглаженный край
            // белого логотипа читался бы серым и утягивал палитру в темноту.
            let red = Double(pixels[offset]) / 255 / alpha
            let green = Double(pixels[offset + 1]) / 255 / alpha
            let blue = Double(pixels[offset + 2]) / 255 / alpha
            let hsb = rgbToHSB(min(red, 1), min(green, 1), min(blue, 1))

            let key = hsb.saturation < neutralSaturation
                ? neutralBucketKey
                : Int(hsb.hue / hueStep)
            buckets[key, default: Bucket()].add(min(red, 1), min(green, 1), min(blue, 1), hsb)
            opaquePixels += 1
        }

        // На десятке уцелевших пикселей средний цвет — это шум, а не обложка.
        guard opaquePixels >= 24 else { return nil }

        let ranked = buckets.values
            .filter { $0.count > 0 }
            .sorted { $0.score > $1.score }
        guard let top = ranked.first else { return nil }

        // Второе пятно ищем подальше по кругу: соседний оттенок дал бы
        // градиент из двух почти одинаковых цветов, то есть заливку.
        let alternative = ranked.dropFirst().first {
            hueDistance($0.averageHue, top.averageHue) >= 40 || $0.isNeutral != top.isNeutral
        } ?? ranked.dropFirst().first ?? top

        // Основа — тот же доминирующий цвет, только тусклее: усреднять всю
        // обложку нельзя, красное с зелёным дают бурую грязь, а не «цвет обложки».
        return ArtworkPalette(
            base: swatch(from: top, saturation: 0...0.70, brightness: 0.08...0.50, scale: 0.78),
            primary: swatch(from: top, saturation: 0...0.85, brightness: 0.18...0.62, scale: 1.05),
            secondary: swatch(from: alternative, saturation: 0...0.80, brightness: 0.12...0.50, scale: 0.85)
        )
    }

    /// Приводит средний цвет корзины к тому, чем можно залить тёмный экран.
    ///
    /// Приложение всегда в тёмной теме, поэтому слишком светлая обложка
    /// приглушается: белые подписи должны читаться и на кислотно-зелёном.
    /// Нижней границы у насыщенности нет намеренно — у чёрно-белой обложки
    /// экран честно останется серым, а не отдаст выдуманным оттенком.
    private static func swatch(
        from bucket: Bucket,
        saturation: ClosedRange<Double>,
        brightness: ClosedRange<Double>,
        scale: Double
    ) -> ArtworkPalette.Swatch {
        let hsb = rgbToHSB(bucket.averageRed, bucket.averageGreen, bucket.averageBlue)
        let s = min(max(hsb.saturation, saturation.lowerBound), saturation.upperBound)
        let v = min(max(hsb.brightness * scale, brightness.lowerBound), brightness.upperBound)
        let rgb = hsbToRGB(hsb.hue, s, v)
        return ArtworkPalette.Swatch(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }

    // MARK: - Пиксели

    private static func downsample(_ image: CGImage) -> [UInt8]? {
        let side = sampleSide
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        let drawn: Bool = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: side * 4,
                space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? pixels : nil
    }

    // MARK: - Корзина

    private static let neutralBucketKey = -1

    private struct Bucket {
        var count = 0
        var red = 0.0
        var green = 0.0
        var blue = 0.0
        var saturationSum = 0.0
        var hueX = 0.0
        var hueY = 0.0
        var isNeutral = true

        mutating func add(
            _ r: Double, _ g: Double, _ b: Double,
            _ hsb: (hue: Double, saturation: Double, brightness: Double)
        ) {
            count += 1
            red += r
            green += g
            blue += b
            saturationSum += hsb.saturation
            // Оттенок усредняем через единичный вектор: у красного соседние
            // значения 359° и 1°, и обычное среднее дало бы бирюзовый.
            let radians = hsb.hue * .pi / 180
            hueX += cos(radians) * hsb.saturation
            hueY += sin(radians) * hsb.saturation
            if hsb.saturation >= neutralSaturation { isNeutral = false }
        }

        var averageRed: Double { count == 0 ? 0 : red / Double(count) }
        var averageGreen: Double { count == 0 ? 0 : green / Double(count) }
        var averageBlue: Double { count == 0 ? 0 : blue / Double(count) }
        var averageSaturation: Double { count == 0 ? 0 : saturationSum / Double(count) }

        var averageHue: Double {
            let degrees = atan2(hueY, hueX) * 180 / .pi
            return degrees < 0 ? degrees + 360 : degrees
        }

        /// Площадь важнее всего, но насыщенное пятно выигрывает у такой же
        /// по размеру серой заливки: фон из чистого угля не читается как
        /// «цвет обложки», даже если угля на ней больше всего.
        var score: Double { Double(count) * (0.25 + averageSaturation) }
    }

    static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let raw = abs(a - b).truncatingRemainder(dividingBy: 360)
        return min(raw, 360 - raw)
    }

    // MARK: - Цветовые модели

    static func rgbToHSB(
        _ r: Double, _ g: Double, _ b: Double
    ) -> (hue: Double, saturation: Double, brightness: Double) {
        let maximum = max(r, g, b)
        let minimum = min(r, g, b)
        let delta = maximum - minimum

        var hue = 0.0
        if delta > 0 {
            if maximum == r {
                hue = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maximum == g {
                hue = 60 * ((b - r) / delta + 2)
            } else {
                hue = 60 * ((r - g) / delta + 4)
            }
        }
        if hue < 0 { hue += 360 }

        let saturation = maximum == 0 ? 0 : delta / maximum
        return (hue, saturation, maximum)
    }

    static func hsbToRGB(
        _ h: Double, _ s: Double, _ v: Double
    ) -> (red: Double, green: Double, blue: Double) {
        guard s > 0 else { return (v, v, v) }
        let sector = (h.truncatingRemainder(dividingBy: 360)) / 60
        let index = Int(floor(sector))
        let fraction = sector - Double(index)
        let p = v * (1 - s)
        let q = v * (1 - s * fraction)
        let t = v * (1 - s * (1 - fraction))

        switch index % 6 {
        case 0: return (v, t, p)
        case 1: return (q, v, p)
        case 2: return (p, v, t)
        case 3: return (p, q, v)
        case 4: return (t, p, v)
        default: return (v, p, q)
        }
    }
}
