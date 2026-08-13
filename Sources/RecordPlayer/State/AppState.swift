import AppKit
import Combine
import Foundation
import SwiftUI

enum SidebarSection: String, Hashable, CaseIterable, Identifiable {
    case all
    case favorites
    case history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: L10n.string("Все станции")
        case .favorites: L10n.string("Избранное")
        case .history: L10n.string("История")
        }
    }

    var icon: String {
        switch self {
        case .all: "square.grid.2x2"
        case .favorites: "heart"
        case .history: "clock.arrow.circlepath"
        }
    }
}

enum SortOrder: String, CaseIterable, Identifiable, Codable {
    case popularity
    case alphabet

    var id: String { rawValue }
    var title: String {
        switch self {
        case .popularity: L10n.string("По популярности")
        case .alphabet: L10n.string("По алфавиту")
        }
    }
}

@MainActor
final class AppState: ObservableObject {

    // MARK: - Данные

    @Published private(set) var stations: [Station] = []
    @Published private(set) var nowPlaying: [Int: Track] = [:]
    @Published private(set) var isLoadingStations = false
    @Published private(set) var loadError: String?
    @Published private(set) var history: [HistoryEntry] = []
    @Published private(set) var stationStats: [Int: StationStat] = [:]

    // MARK: - Готовые списки для интерфейса
    //
    // Раньше это были вычисляемые свойства: сортировка 117 станций и сборка
    // списка жанров выполнялись заново при каждой перерисовке — то есть на каждое
    // нажатие клавиши в поиске и на каждую смену состояния плеера. Теперь считаются
    // только когда действительно меняются входные данные.

    @Published private(set) var visibleStations: [Station] = []
    @Published private(set) var genres: [String] = []
    @Published private(set) var favoriteStations: [Station] = []

    // MARK: - Выбор и фильтры

    @Published var section: SidebarSection = .all {
        didSet { if oldValue != section { scheduleRecompute() } }
    }
    @Published var searchText: String = "" {
        didSet { searchSubject.send(searchText) }
    }
    @Published var selectedGenre: String? = nil {
        didSet { if oldValue != selectedGenre { scheduleRecompute() } }
    }
    @Published var sortOrder: SortOrder = .popularity {
        didSet {
            Defaults.sortOrder = sortOrder
            if oldValue != sortOrder { scheduleRecompute() }
        }
    }

    // MARK: - Воспроизведение

    @Published private(set) var currentStation: Station?
    @Published var quality: StreamQuality = .auto {
        didSet {
            Defaults.quality = quality
            // Пере-подключаемся на новом качестве, не прерывая прослушивание.
            if let currentStation, player.state.isActive {
                startPlayback(currentStation)
            }
        }
    }
    @Published var favorites: Set<Int> = [] {
        didSet {
            Defaults.favorites = favorites
            if oldValue != favorites { scheduleRecompute() }
        }
    }

    @Published var accent: AccentPalette = .red {
        didSet { Defaults.accent = accent }
    }

    /// Таймер сна: момент, когда воспроизведение остановится.
    @Published private(set) var sleepDeadline: Date?

    // MARK: - Плейлист станции

    /// Станция, открытая в полноразмерном режиме. nil — показан каталог.
    @Published var playlistStation: Station?
    @Published private(set) var playlist: [PlaylistTrack] = []
    @Published private(set) var isLoadingPlaylist = false
    @Published private(set) var playlistError: String?

    let player = AudioPlayer()

    // MARK: - Внутреннее

    /// Предсобранная строка для поиска по каждой станции: название + подпись + жанры.
    /// Собирать её на лету значило бы 117 склеек и приведений к нижнему регистру
    /// на каждое нажатие клавиши.
    private var searchIndex: [Int: String] = [:]

    private let searchSubject = PassthroughSubject<String, Never>()
    private var appliedSearch = ""
    private var recomputeScheduled = false

    /// Начало текущего отрезка прослушивания — из него набегает статистика.
    private var listenStart: Date?
    private var listenStationID: Int?

    private var nowTimer: Task<Void, Never>?
    private var sleepTimer: Task<Void, Never>?
    private var spaceMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var lastLoggedTrackKey: String?

    // MARK: - Инициализация

    init() {
        favorites = Defaults.favorites
        sortOrder = Defaults.sortOrder
        quality = Defaults.quality
        accent = Defaults.accent
        history = Defaults.history
        stationStats = StatsStore.load()
        player.volume = Defaults.volume
        player.isMuted = Defaults.isMuted

        if let cached = RecordAPI.cachedStations(), !cached.isEmpty {
            stations = cached
            rebuildIndexes()
            recomputeVisible()
            restoreLastStation()
        }

        // Фильтрация по поиску идёт с небольшой задержкой: поле остаётся
        // мгновенно отзывчивым, а список пересобирается один раз после паузы в наборе.
        searchSubject
            .removeDuplicates()
            .debounce(for: .milliseconds(110), scheduler: RunLoop.main)
            .sink { [weak self] text in
                guard let self else { return }
                let normalized = text.trimmed.lowercased()
                guard normalized != self.appliedSearch else { return }
                self.appliedSearch = normalized
                self.recomputeVisible()
            }
            .store(in: &cancellables)

        // Сохраняем громкость без спама в UserDefaults.
        player.$volume
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { Defaults.volume = $0 }
            .store(in: &cancellables)
        player.$isMuted
            .sink { Defaults.isMuted = $0 }
            .store(in: &cancellables)

        // Пробрасываем только смену состояния воспроизведения — от неё зависят
        // иконки play/pause по всему интерфейсу. Громкость сюда намеренно не входит:
        // иначе каждое движение ползунка перерисовывало бы всю сетку станций.
        // Её слушает отдельный `VolumeSlider` напрямую у плеера.
        player.$state
            .removeDuplicates()
            .sink { [weak self] state in
                guard let self else { return }
                self.updateListeningClock(for: state)
                self.objectWillChange.send()
                RemoteControl.shared.update(
                    station: self.currentStation,
                    track: self.currentStation.flatMap { self.nowPlaying[$0.id] },
                    isPlaying: state == .playing
                )
            }
            .store(in: &cancellables)

        configureRemoteControl()
        installSpaceShortcut()

        // При выходе закрываем текущий отрезок, иначе последние минуты пропадут.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushListening() }
        }
    }

    /// Пробел = play/pause, но только когда фокус не в текстовом поле.
    /// Через меню это не сделать: пункт меню перехватывает клавишу раньше поля поиска.
    private func installSpaceShortcut() {
        spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 49 else { return event }
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty else { return event }

            let responder = NSApp.keyWindow?.firstResponder
            if responder is NSTextView || responder is NSTextField { return event }

            self?.togglePlayPause()
            return nil
        }
    }

    // MARK: - Пересчёт списков

    /// Тяжёлая часть: выполняется только при смене набора станций.
    private func rebuildIndexes() {
        searchIndex = stations.reduce(into: [:]) { index, station in
            index[station.id] = station.searchHaystack
        }
        genres = Array(Set(stations.flatMap(\.genreNames))).sorted()
    }

    /// Откладываем пересчёт на следующий проход цикла событий.
    /// Иначе изменение опубликованного свойства прямо во время отрисовки
    /// вызывает предупреждение SwiftUI и лишний проход раскладки.
    private func scheduleRecompute() {
        guard !recomputeScheduled else { return }
        recomputeScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.recomputeScheduled = false
            self?.recomputeVisible()
        }
    }

    private func recomputeVisible() {
        var list = stations

        if section == .favorites {
            list = list.filter { favorites.contains($0.id) }
        }
        if let selectedGenre {
            list = list.filter { $0.genreNames.contains(selectedGenre) }
        }
        if !appliedSearch.isEmpty {
            list = list.filter { searchIndex[$0.id]?.contains(appliedSearch) ?? false }
        }

        switch sortOrder {
        case .popularity:
            list.sort { ($0.sort ?? Int.max) < ($1.sort ?? Int.max) }
        case .alphabet:
            list.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        }

        visibleStations = list
        favoriteStations = stations
            .filter { favorites.contains($0.id) }
            .sorted { ($0.sort ?? .max) < ($1.sort ?? .max) }
    }

    // MARK: - Загрузка

    func bootstrap() async {
        await loadStations()
        startNowPlayingUpdates()
    }

    func loadStations() async {
        isLoadingStations = stations.isEmpty
        loadError = nil
        do {
            let fetched = try await RecordAPI.fetchStations()
            stations = fetched
            rebuildIndexes()
            recomputeVisible()
            if currentStation == nil { restoreLastStation() }
            // Если станция уже играет — обновляем её данные из свежего списка.
            if let current = currentStation,
               let refreshed = fetched.first(where: { $0.id == current.id }) {
                currentStation = refreshed
            }
        } catch {
            if stations.isEmpty {
                loadError = error.localizedDescription
            }
        }
        isLoadingStations = false
    }

    private func startNowPlayingUpdates() {
        nowTimer?.cancel()
        nowTimer = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNowPlaying()
                try? await Task.sleep(for: .seconds(12))
            }
        }
    }

    func refreshNowPlaying() async {
        checkpointListening()
        guard let tracks = try? await RecordAPI.fetchNowPlaying() else { return }
        // Дополняем, а не заменяем: если в очередном ответе станции не оказалось,
        // это не повод стирать её трек — иначе обложка пропадает на ровном месте
        // и возвращается только через опрос-другой.
        nowPlaying.merge(tracks) { _, new in new }

        guard let station = currentStation, let track = tracks[station.id] else { return }

        RemoteControl.shared.update(
            station: station,
            track: track,
            isPlaying: player.state == .playing
        )

        // В историю пишем только то, что реально слушали.
        guard player.state == .playing else { return }
        let key = track.identityKey
        guard key != lastLoggedTrackKey, !track.displayTitle.isEmpty else { return }
        lastLoggedTrackKey = key
        appendHistory(station: station, track: track)
    }

    // MARK: - Управление воспроизведением

    func play(_ station: Station) {
        if currentStation?.id == station.id, player.state.isActive {
            player.pause()
            return
        }
        startPlayback(station)
    }

    func startPlayback(_ station: Station) {
        guard let url = station.streamURL(for: quality) else { return }
        let shouldFollowPlayback = playlistStation != nil && playlistStation?.id != station.id
        flushListening()
        countPlay(of: station)
        currentStation = station
        lastLoggedTrackKey = nil
        Defaults.lastStationID = station.id
        player.play(url: url)
        RemoteControl.shared.update(station: station, track: nowPlaying[station.id], isPlaying: true)

        // Полноразмерный режим всегда следует за фактически играющей станцией.
        // Иначе случайный выбор, горячие клавиши и медиакоманды меняли звук,
        // но оставляли на экране обложку и историю предыдущей станции.
        if shouldFollowPlayback {
            showStation(station)
        }
    }

    func togglePlayPause() {
        guard let currentStation else {
            if let first = visibleStations.first { startPlayback(first) }
            return
        }
        if player.state.isActive {
            player.pause()
        } else {
            startPlayback(currentStation)
        }
    }

    /// Следующая/предыдущая станция в текущем видимом списке (или во всём списке).
    func step(by offset: Int) {
        let pool = visibleStations.isEmpty ? stations : visibleStations
        guard !pool.isEmpty else { return }
        guard let current = currentStation,
              let index = pool.firstIndex(where: { $0.id == current.id })
        else {
            startPlayback(pool[0])
            return
        }
        let next = (index + offset + pool.count) % pool.count
        startPlayback(pool[next])
    }

    func playRandom() {
        // Выбираем из того, что сейчас на экране — так кнопка учитывает фильтр
        // по жанру и раздел. Раньше пул брался из избранного, и с одной
        // избранной станцией «случайная» всегда попадала в неё же.
        var pool = visibleStations.isEmpty ? stations : visibleStations

        // И не выпадаем на станцию, которая уже играет.
        if pool.count > 1, let current = currentStation {
            pool.removeAll { $0.id == current.id }
        }

        guard let station = pool.randomElement() else { return }
        startPlayback(station)
    }

    // MARK: - Избранное

    func toggleFavorite(_ station: Station) {
        if favorites.contains(station.id) {
            favorites.remove(station.id)
        } else {
            favorites.insert(station.id)
        }
    }

    func isFavorite(_ station: Station) -> Bool { favorites.contains(station.id) }

    // MARK: - Таймер сна

    func setSleepTimer(minutes: Int?) {
        sleepTimer?.cancel()
        guard let minutes else {
            sleepDeadline = nil
            return
        }
        let deadline = Date().addingTimeInterval(TimeInterval(minutes * 60))
        sleepDeadline = deadline
        sleepTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Double(minutes * 60)))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.player.pause()
                self?.sleepDeadline = nil
            }
        }
    }

    // MARK: - Плейлист станции

    func showStation(_ station: Station) {
        playlistStation = station
        playlist = []
        playlistError = nil
        Task { await loadPlaylist(for: station) }
    }

    func showPlaylist(for station: Station) {
        showStation(station)
    }

    func closeStation() {
        playlistStation = nil
        playlist = []
        playlistError = nil
        isLoadingPlaylist = false
    }

    func loadPlaylist(for station: Station) async {
        isLoadingPlaylist = true
        playlistError = nil
        do {
            let tracks = try await RecordAPI.fetchStationHistory(id: station.id)
            // Панель могли закрыть или переключить, пока ответ шёл.
            guard playlistStation?.id == station.id else { return }
            playlist = tracks
        } catch {
            guard playlistStation?.id == station.id else { return }
            playlistError = error.localizedDescription
        }
        isLoadingPlaylist = false
    }

    // MARK: - Статистика прослушивания

    /// Считает время по станциям. Отрезок открывается, когда звук реально пошёл,
    /// и закрывается на паузе, смене станции или выходе.
    private func updateListeningClock(for state: PlaybackState) {
        guard state == .playing else {
            flushListening()
            return
        }
        if listenStationID != currentStation?.id { flushListening() }
        if listenStart == nil {
            listenStart = Date()
            listenStationID = currentStation?.id
        }
    }

    private func flushListening() {
        defer {
            listenStart = nil
            listenStationID = nil
        }
        guard let start = listenStart,
              let id = listenStationID,
              let station = stations.first(where: { $0.id == id })
        else { return }

        let seconds = Date().timeIntervalSince(start)
        // Пролистывание станций одну за другой статистику засорять не должно.
        guard seconds >= 5 else { return }

        var stat = stationStats[id] ?? StationStat(
            stationID: id, title: station.title,
            totalSeconds: 0, lastPlayed: Date(), plays: 0
        )
        stat.title = station.title
        stat.totalSeconds += seconds
        stat.lastPlayed = Date()
        stationStats[id] = stat
        StatsStore.save(stationStats)
    }

    /// Закрывает отрезок и сразу открывает новый — чтобы долгое прослушивание
    /// не потерялось целиком, если приложение завершится неожиданно.
    private func checkpointListening() {
        guard listenStart != nil, player.state == .playing else { return }
        flushListening()
        listenStart = Date()
        listenStationID = currentStation?.id
    }

    private func countPlay(of station: Station) {
        var stat = stationStats[station.id] ?? StationStat(
            stationID: station.id, title: station.title,
            totalSeconds: 0, lastPlayed: Date(), plays: 0
        )
        stat.title = station.title
        stat.plays += 1
        stat.lastPlayed = Date()
        stationStats[station.id] = stat
        StatsStore.save(stationStats)
    }

    /// Станции по времени прослушивания, самые слушаемые сверху.
    var statsByTime: [StationStat] {
        stationStats.values
            .filter { $0.totalSeconds >= 5 || $0.plays > 0 }
            .sorted { ($0.totalSeconds, $0.lastPlayed) > ($1.totalSeconds, $1.lastPlayed) }
    }

    /// Недавно включённые станции.
    var recentStations: [Station] {
        stationStats.values
            .sorted { $0.lastPlayed > $1.lastPlayed }
            .compactMap { stat in stations.first { $0.id == stat.stationID } }
    }

    func clearStats() {
        stationStats = [:]
        listenStart = nil
        listenStationID = nil
        StatsStore.save([:])
    }

    // MARK: - История

    private func appendHistory(station: Station, track: Track) {
        let entry = HistoryEntry(
            stationID: station.id,
            stationTitle: station.title,
            artist: track.displayArtist,
            song: track.displaySong,
            artwork: track.smallArtworkURL?.absoluteString,
            itunesUrl: track.itunesUrl,
            date: Date()
        )
        // Не дублируем подряд один и тот же трек.
        if history.first?.trackKey == entry.trackKey && history.first?.stationID == entry.stationID {
            return
        }
        history.insert(entry, at: 0)
        if history.count > 300 { history.removeLast(history.count - 300) }
        Defaults.history = history
    }

    func clearHistory() {
        history = []
        Defaults.history = []
    }

    // MARK: - Прочее

    var currentTrack: Track? {
        currentStation.flatMap { nowPlaying[$0.id] }
    }

    private func restoreLastStation() {
        guard let id = Defaults.lastStationID,
              let station = stations.first(where: { $0.id == id })
        else { return }
        currentStation = station
    }

    private func configureRemoteControl() {
        let remote = RemoteControl.shared
        remote.onPlay = { [weak self] in
            guard let self, let station = self.currentStation else { return }
            if self.player.state != .playing { self.startPlayback(station) }
        }
        remote.onPause = { [weak self] in self?.player.pause() }
        remote.onToggle = { [weak self] in self?.togglePlayPause() }
        remote.onNextStation = { [weak self] in self?.step(by: 1) }
        remote.onPreviousStation = { [weak self] in self?.step(by: -1) }
        remote.activate()
    }
}

// MARK: - Настройки

enum Defaults {
    private static let d = UserDefaults.standard

    static var favorites: Set<Int> {
        get { Set(d.array(forKey: "favorites") as? [Int] ?? []) }
        set { d.set(Array(newValue), forKey: "favorites") }
    }

    static var lastStationID: Int? {
        get { d.object(forKey: "lastStationID") as? Int }
        set { d.set(newValue, forKey: "lastStationID") }
    }

    static var volume: Double {
        get { d.object(forKey: "volume") as? Double ?? 0.8 }
        set { d.set(newValue, forKey: "volume") }
    }

    static var isMuted: Bool {
        get { d.bool(forKey: "isMuted") }
        set { d.set(newValue, forKey: "isMuted") }
    }

    static var quality: StreamQuality {
        get { StreamQuality(rawValue: d.string(forKey: "quality") ?? "") ?? .auto }
        set { d.set(newValue.rawValue, forKey: "quality") }
    }

    static var accent: AccentPalette {
        get { AccentPalette(rawValue: d.string(forKey: "accent") ?? "") ?? .red }
        set { d.set(newValue.rawValue, forKey: "accent") }
    }

    static var sortOrder: SortOrder {
        get { SortOrder(rawValue: d.string(forKey: "sortOrder") ?? "") ?? .popularity }
        set { d.set(newValue.rawValue, forKey: "sortOrder") }
    }

    static var history: [HistoryEntry] {
        get {
            guard let data = d.data(forKey: "history") else { return [] }
            return (try? JSONDecoder().decode([HistoryEntry].self, from: data)) ?? []
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            d.set(data, forKey: "history")
        }
    }
}
