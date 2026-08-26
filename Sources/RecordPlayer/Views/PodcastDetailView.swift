import AppKit
import SwiftUI

/// Подкаст целиком: слева обложка и описание, справа выпуски.
/// Устроен как полноразмерный режим станции, чтобы разделы не разъезжались.
struct PodcastDetailView: View {
    @Environment(\.appAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var state: AppState

    let podcast: Podcast

    @State private var query = ""

    private var feedID: Int? { podcast.feedID }
    private var episodes: [PodcastEpisode] { feedID.flatMap { state.episodes[$0] } ?? [] }
    private var isLoading: Bool { feedID.map { state.loadingEpisodes.contains($0) } ?? false }
    private var error: String? { feedID.flatMap { state.episodesError[$0] } }

    var body: some View {
        VStack(spacing: 0) {
            navigationBar

            GeometryReader { geometry in
                let narrow = geometry.size.width < 980
                let coverWidth = narrow
                    ? min(280, max(220, geometry.size.width * 0.34))
                    : min(360, geometry.size.width * 0.30)

                HStack(alignment: .top, spacing: narrow ? 24 : 30) {
                    aboutColumn(width: coverWidth)

                    Divider().overlay(Theme.separator.opacity(0.65))

                    episodesColumn
                        .frame(minWidth: 320, maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 26)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(podcast.id)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.992)))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: podcast.id)
    }

    // MARK: - Шапка

    private var navigationBar: some View {
        HStack {
            Button {
                state.closePodcast()
            } label: {
                Label("К подкастам", systemImage: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.secondaryText)
            .help(L10n.string("Вернуться к списку подкастов"))

            Spacer()
        }
        .padding(.horizontal, 26)
        .frame(height: 44)
    }

    // MARK: - Левая колонка

    private func aboutColumn(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            CachedImage(url: podcast.coverURL, contentMode: .fill, maxPixel: 800) {
                LinearGradient(
                    colors: [accent.opacity(0.26), .black.opacity(0.36)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }
            .aspectRatio(750.0 / 1042.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(.white.opacity(0.13), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.34), radius: 24, y: 12)
            .accessibilityHidden(true)

            Text(podcast.title)
                .font(.system(size: 17, weight: .semibold))
                .lineLimit(3)

            if !podcast.summary.isEmpty {
                Text(podcast.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let url = podcast.shareURL {
                Button("Открыть на сайте") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.borderless)
                    .font(.system(size: 11))
            }

            Spacer(minLength: 0)
        }
        .frame(width: width, alignment: .leading)
        .padding(.top, 12)
    }

    // MARK: - Правая колонка

    private var episodesColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("Выпуски")
                    .font(.system(size: 13, weight: .semibold))

                if !episodes.isEmpty {
                    Text(L10n.episodeCount(filtered.count))
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                }

                Spacer()

                if isLoading {
                    ProgressView().controlSize(.small)
                } else if let feedID {
                    Button {
                        Task { await state.loadEpisodes(podcastID: feedID, force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help(L10n.string("Обновить"))
                    .accessibilityLabel(L10n.string("Обновить"))
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 8)

            if !episodes.isEmpty { searchField }

            content
        }
    }

    @ViewBuilder
    private var content: some View {
        if let error, episodes.isEmpty {
            message(icon: "wifi.exclamationmark", title: L10n.string("Не удалось загрузить выпуски"), subtitle: error) {
                if let feedID {
                    Button("Повторить") {
                        Task { await state.loadEpisodes(podcastID: feedID, force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                }
            }
        } else if episodes.isEmpty && isLoading {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if episodes.isEmpty {
            message(icon: "waveform", title: L10n.string("Выпусков пока нет"),
                    subtitle: L10n.string("Подкаст не вернул ни одного выпуска.")) { EmptyView() }
        } else if filtered.isEmpty {
            message(icon: "magnifyingglass", title: L10n.string("Ничего не найдено"),
                    subtitle: L10n.string("Попробуйте изменить поисковый запрос.")) { EmptyView() }
        } else {
            list
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
            TextField("Поиск по выпускам", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.string("Очистить поиск"))
            }
        }
        .padding(.bottom, 8)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(grouped, id: \.day) { group in
                    Section {
                        ForEach(group.episodes) { episode in
                            EpisodeRow(episode: episode).equatable()
                        }
                    } header: {
                        HStack {
                            Text(group.day)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.tertiaryText)
                            Spacer()
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 3)
                    }
                }
            }
            .padding(.bottom, PlayerBar.reservedHeight)
        }
    }

    // MARK: - Данные

    private var filtered: [PodcastEpisode] {
        let normalized = query.trimmed.lowercased()
        guard !normalized.isEmpty else { return episodes }
        return episodes.filter {
            $0.title.lowercased().contains(normalized)
                || ($0.playlist ?? "").lowercased().contains(normalized)
        }
    }

    /// Группировка по дням тем же приёмом, что и история эфира: порядок
    /// вставки сохраняется, поэтому выпуски не перемешиваются.
    private var grouped: [(day: String, episodes: [PodcastEpisode])] {
        var order: [String] = []
        var buckets: [String: [PodcastEpisode]] = [:]
        for episode in filtered {
            let day = Self.dayLabel(for: episode.date)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(episode)
        }
        return order.map { ($0, buckets[$0] ?? []) }
    }

    private static func dayLabel(for date: Date?) -> String {
        guard let date else { return L10n.string("Без даты") }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return L10n.string("Сегодня") }
        if calendar.isDateInYesterday(date) { return L10n.string("Вчера") }
        return date.formatted(.dateTime.day().month(.wide).year())
    }

    private func message<Action: View>(
        icon: String, title: String, subtitle: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.tertiaryText)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            action().padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Строка выпуска

private struct EpisodeRow: View, Equatable {
    let episode: PodcastEpisode

    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var hovered = false
    @State private var expanded = false

    static func == (lhs: EpisodeRow, rhs: EpisodeRow) -> Bool {
        lhs.episode.id == rhs.episode.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                CachedImage(url: episode.smallArtworkURL, contentMode: .fill, maxPixel: 96) {
                    RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.3))
                }
                .frame(width: 38, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 1) {
                    Text(episode.title)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        if let duration = episode.durationText {
                            Text(duration)
                        }
                        if let date = episode.date {
                            Text("·")
                            Text(date.formatted(date: .omitted, time: .shortened))
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.tertiaryText)
                }

                Spacer(minLength: 8)

                if !episode.playlistLines.isEmpty, hovered || voiceOverEnabled || expanded {
                    Button {
                        expanded.toggle()
                    } label: {
                        Image(systemName: expanded ? "chevron.up" : "list.bullet")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.secondaryText)
                    .help(L10n.string("Состав выпуска"))
                    .accessibilityLabel(L10n.string("Состав выпуска"))
                }
            }

            if expanded, !episode.playlistLines.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(episode.playlistLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 48)
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            if hovered {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.white.opacity(0.07))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .contextMenu {
            Button("Скопировать название") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(episode.title, forType: .string)
            }
            if !episode.playlistLines.isEmpty {
                Button("Скопировать состав") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(episode.playlistLines.joined(separator: "\n"), forType: .string)
                }
            }
            if let url = episode.shareURL {
                Button("Открыть на сайте") { NSWorkspace.shared.open(url) }
            }
        }
    }
}
