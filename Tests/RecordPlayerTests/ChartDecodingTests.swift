import Foundation
import Testing
@testable import RecordPlayer

@Suite("Chart decoding")
struct ChartDecodingTests {
    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    /// Главная защита модели: в клаб чарте поле `like` приходит то строкой,
    /// то числом в одном и том же ответе. Пока оно не объявлено в `ChartEntry`,
    /// такая позиция разбирается наравне с остальными. Стоит кому-то добавить
    /// `like` с жёстким типом — этот тест упадёт раньше пользователя.
    @Test func mixedTypesInIgnoredFieldsDoNotBreakDecoding() throws {
        let json = """
        {"result":[
          {"name":"A - One","sort":"1995","like":"18","status":"(не установлено)",
           "track":{"id":1,"artist":"A","song":"One"}},
          {"name":"B - Two","sort":2,"like":7,"status":"(не установлено)",
           "track":{"id":2,"artist":"B","song":"Two"}}
        ]}
        """
        let entries = try decoder.decode(ChartResponse.self, from: Data(json.utf8)).result
        #expect(entries.count == 2)
        #expect(entries[1].track?.displayArtist == "B")
    }

    /// Место в чарте задаётся порядком в ответе, а не полем `sort`:
    /// в суперчарте там лежит внутренний счётчик, начинающийся с 1995.
    @Test func rankComesFromOrderNotFromSortField() throws {
        let json = """
        {"result":[
          {"name":"First","sort":"1995","track":{"id":1,"artist":"A","song":"One"}},
          {"name":"Second","sort":"1996","track":{"id":2,"artist":"B","song":"Two"}}
        ]}
        """
        let ranked = try decoder.decode(ChartResponse.self, from: Data(json.utf8)).result.ranked
        #expect(ranked.map(\.rank) == [1, 2])
        #expect(ranked.first?.entry.track?.displaySong == "One")
    }

    /// У части позиций `itunesUrl` пустой — строка обязана остаться рабочей.
    @Test func entryWithoutAppleMusicLinkStillDecodes() throws {
        let json = """
        {"result":[{"name":"C - Three","track":
          {"id":3,"artist":"C","song":"Three","itunesUrl":null,"listenUrl":"https://example.com/p.m4a"}}]}
        """
        let entry = try decoder.decode(ChartResponse.self, from: Data(json.utf8)).result[0]
        #expect(entry.appleMusicURL == nil)
        #expect(entry.previewURL != nil)
    }

    /// Новинки приходят тем же фидом, что и выпуски подкаста.
    @Test func newestFeedDecodesAsTracks() throws {
        let json = """
        {"result":{"tracks":[
          {"id":328760,"artist":"ROBIN SCHULZ","song":"Take It Slow","image600":"https://example.com/a.jpg"}
        ]}}
        """
        let tracks = try decoder.decode(PodcastFeedResponse<Track>.self, from: Data(json.utf8)).result.tracks
        #expect(tracks.count == 1)
        #expect(tracks[0].displayTitle == "ROBIN SCHULZ — Take It Slow")
    }
}
