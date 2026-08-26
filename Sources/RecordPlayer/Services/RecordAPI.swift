import Foundation

/// Тонкий клиент публичного API radiorecord.ru: станции, эфир, чарты.
enum RecordAPI {
    static let stationsURL = URL(string: "https://www.radiorecord.ru/api/stations/")!
    static let nowURL = URL(string: "https://www.radiorecord.ru/api/stations/now/")!

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 20
        config.waitsForConnectivity = false
        config.httpAdditionalHeaders = [
            "User-Agent": "RecordPlayer/1.0 (macOS; personal use)",
            "Accept": "application/json",
            "Accept-Encoding": "gzip, deflate"
        ]
        return URLSession(configuration: config)
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()

    static func fetchStations() async throws -> [Station] {
        let (data, response) = try await session.data(from: stationsURL)
        try validate(response)
        let decoded = try decoder.decode(StationsResponse.self, from: data)
        // Сохраняем сырой JSON, чтобы приложение работало без сети при следующем запуске.
        DiskCache.write(data, to: "stations.json")
        return decoded.result.stations
    }

    /// Список станций из локального кэша (первый запуск без сети вернёт nil).
    static func cachedStations() -> [Station]? {
        guard let data = DiskCache.read("stations.json"),
              let decoded = try? decoder.decode(StationsResponse.self, from: data)
        else { return nil }
        return decoded.result.stations
    }

    /// Один запрос отдаёт текущий трек для всех 117 станций (~22 КБ).
    static func fetchNowPlaying() async throws -> [Int: Track] {
        let (data, response) = try await session.data(from: nowURL)
        try validate(response)
        let decoded = try decoder.decode(NowPlayingResponse.self, from: data)
        return decoded.result.reduce(into: [:]) { acc, entry in
            if let track = entry.track { acc[entry.id] = track }
        }
    }

    /// Плейлист станции: что играло в эфире до текущего трека.
    /// Отдаёт порядка 350 записей за последние сутки-двое.
    static func fetchStationHistory(id: Int) async throws -> [PlaylistTrack] {
        var components = URLComponents(string: "https://www.radiorecord.ru/api/station/history/")!
        components.queryItems = [URLQueryItem(name: "id", value: String(id))]
        let (data, response) = try await session.data(from: components.url!)
        try validate(response)
        return try decoder.decode(StationHistoryResponse.self, from: data).result.history
    }

    // MARK: - Чарты

    /// Суперчарт — недельный хит-парад, порядка 30 позиций.
    static func fetchSuperchart() async throws -> [ChartEntry] {
        try await fetchChart(path: "superchart")
    }

    /// Клаб чарт — недельный топ клубных треков.
    static func fetchClubchart() async throws -> [ChartEntry] {
        try await fetchChart(path: "clubchart")
    }

    private static func fetchChart(path: String) async throws -> [ChartEntry] {
        let url = URL(string: "https://www.radiorecord.ru/api/\(path)/")!
        let (data, response) = try await session.data(from: url)
        try validate(response)
        return try decoder.decode(ChartResponse.self, from: data).result
    }

    /// Record New — новинки радио.
    ///
    /// На сайте у этого раздела нет собственного эндпоинта, страница собирается
    /// на сервере. Но список новинок оказался обычным фидом: `/api/podcast/`
    /// с идентификатором 15762 отдаёт те же треки в том же порядке — сверил
    /// первые тридцать позиций со страницей, совпали один в один.
    ///
    /// Поэтому здесь честный JSON, а не разбор разметки. Идентификатор фида —
    /// единственное слабое место: если он сменится, раздел должен деградировать
    /// мягко, а не ронять соседние чарты.
    static func fetchNewest(limit: Int = 30) async throws -> [ChartEntry] {
        let tracks = try await fetchFeedTracks(id: recordNewFeedID)
        return tracks.prefix(limit).map { ChartEntry(name: nil, track: $0) }
    }

    /// Идентификатор фида новинок — взят из поля `podcastId` у треков на
    /// странице `/chart/newest`.
    static let recordNewFeedID = 15762

    /// Тот же эндпоинт отдаёт и выпуски подкаста, и треки новинок,
    /// поэтому разбор вынесен в общий метод.
    static func fetchFeedTracks(id: Int) async throws -> [Track] {
        var components = URLComponents(string: "https://www.radiorecord.ru/api/podcast/")!
        components.queryItems = [URLQueryItem(name: "id", value: String(id))]
        let (data, response) = try await session.data(from: components.url!)
        try validate(response)
        return try decoder.decode(PodcastFeedResponse<Track>.self, from: data).result.tracks
    }

    private static func validate(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "RecordAPI", code: http.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: L10n.format(
                        "Сервер ответил %@",
                        String(http.statusCode)
                    )
                ]
            )
        }
    }
}

// MARK: - Простой файловый кэш

enum DiskCache {
    static let directory: URL = {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("RecordPlayer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    static func url(for name: String) -> URL {
        directory.appendingPathComponent(name)
    }

    static func write(_ data: Data, to name: String) {
        try? data.write(to: url(for: name), options: .atomic)
    }

    static func read(_ name: String) -> Data? {
        try? Data(contentsOf: url(for: name))
    }
}
