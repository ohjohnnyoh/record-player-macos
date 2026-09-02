import Testing
@testable import RecordPlayer

/// Разбор обложки на цвета фона. Проверяем на синтетических пикселях:
/// настоящая обложка сделала бы тест зависимым от сети и от того, что
/// сегодня играет на радио.
@Suite("Artwork palette")
struct ArtworkPaletteTests {

    /// RGBA8, ряд за рядом — тот же формат, в котором приходит уменьшенная обложка.
    private func pixels(_ colors: [(UInt8, UInt8, UInt8, UInt8)], repeated: Int = 1) -> [UInt8] {
        var out: [UInt8] = []
        for _ in 0..<repeated {
            for c in colors { out.append(contentsOf: [c.0, c.1, c.2, c.3]) }
        }
        return out
    }

    private func hsb(_ swatch: ArtworkPalette.Swatch)
        -> (hue: Double, saturation: Double, brightness: Double) {
        ArtworkPaletteExtractor.rgbToHSB(swatch.red, swatch.green, swatch.blue)
    }

    @Test func dominantColourDrivesTheBackground() throws {
        let red = pixels([(220, 30, 40, 255)], repeated: 256)
        let palette = try #require(ArtworkPaletteExtractor.palette(fromPixels: red))

        let primary = hsb(palette.primary)
        #expect(ArtworkPaletteExtractor.hueDistance(primary.hue, 356) < 25)
        #expect(primary.saturation > 0.5)

        // Основа — тот же цвет, но глуше: на ней лежит текст.
        #expect(hsb(palette.base).brightness < primary.brightness)
    }

    /// Иначе чёрно-белая обложка получила бы выдуманный оттенок.
    @Test func greyscaleArtworkStaysGrey() throws {
        let grey = pixels([(128, 128, 128, 255), (60, 60, 60, 255)], repeated: 128)
        let palette = try #require(ArtworkPaletteExtractor.palette(fromPixels: grey))

        #expect(hsb(palette.base).saturation < 0.05)
        #expect(hsb(palette.primary).saturation < 0.05)
    }

    /// Два пятна должны быть разными: иначе градиент вырождается в заливку.
    @Test func twoDistinctHuesGiveTwoDistinctSwatches() throws {
        var data = pixels([(210, 20, 20, 255)], repeated: 200)
        data += pixels([(20, 40, 210, 255)], repeated: 160)
        let palette = try #require(ArtworkPaletteExtractor.palette(fromPixels: data))

        let distance = ArtworkPaletteExtractor.hueDistance(
            hsb(palette.primary).hue,
            hsb(palette.secondary).hue
        )
        #expect(distance >= 40)
    }

    /// У красного соседние оттенки лежат по разные стороны нуля: 359° и 1°.
    /// Обычное среднее дало бы бирюзу — усреднение идёт через вектор.
    @Test func hueWrapAroundDoesNotInvertRed() throws {
        var data = pixels([(220, 20, 30, 255)], repeated: 150)   // ~356°
        data += pixels([(220, 40, 20, 255)], repeated: 150)      // ~6°
        let palette = try #require(ArtworkPaletteExtractor.palette(fromPixels: data))

        let hue = hsb(palette.primary).hue
        #expect(ArtworkPaletteExtractor.hueDistance(hue, 0) < 30)
    }

    /// Логотипы станций приходят с прозрачным фоном; он не должен красить экран.
    @Test func transparentPixelsAreIgnored() {
        let empty = pixels([(0, 0, 0, 0)], repeated: 512)
        #expect(ArtworkPaletteExtractor.palette(fromPixels: empty) == nil)
    }

    /// На горстке уцелевших пикселей средний цвет — шум, а не обложка.
    @Test func tooFewOpaquePixelsGiveNoPalette() {
        var data = pixels([(200, 10, 10, 255)], repeated: 10)
        data += pixels([(0, 0, 0, 0)], repeated: 400)
        #expect(ArtworkPaletteExtractor.palette(fromPixels: data) == nil)
    }

    /// Приложение всегда тёмное: белая обложка не должна давать белый экран.
    @Test func brightArtworkIsDimmedForWhiteText() throws {
        let white = pixels([(255, 255, 255, 255)], repeated: 256)
        let palette = try #require(ArtworkPaletteExtractor.palette(fromPixels: white))

        #expect(hsb(palette.base).brightness <= 0.50)
        #expect(hsb(palette.primary).brightness <= 0.62)
    }

    /// И наоборот: у чёрной обложки экран не должен схлопываться в ноль.
    @Test func darkArtworkKeepsAFloor() throws {
        let black = pixels([(6, 6, 8, 255)], repeated: 256)
        let palette = try #require(ArtworkPaletteExtractor.palette(fromPixels: black))

        #expect(hsb(palette.base).brightness >= 0.08)
    }

    @Test func hueDistanceIsCircular() {
        #expect(ArtworkPaletteExtractor.hueDistance(350, 10) == 20)
        #expect(ArtworkPaletteExtractor.hueDistance(10, 350) == 20)
        #expect(ArtworkPaletteExtractor.hueDistance(0, 180) == 180)
    }

    @Test func colourModelRoundTrips() {
        for (r, g, b) in [(0.8, 0.2, 0.3), (0.1, 0.6, 0.4), (0.5, 0.5, 0.5), (0.0, 0.0, 0.0)] {
            let hsb = ArtworkPaletteExtractor.rgbToHSB(r, g, b)
            let rgb = ArtworkPaletteExtractor.hsbToRGB(hsb.hue, hsb.saturation, hsb.brightness)
            #expect(abs(rgb.red - r) < 0.001)
            #expect(abs(rgb.green - g) < 0.001)
            #expect(abs(rgb.blue - b) < 0.001)
        }
    }
}
