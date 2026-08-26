import AppKit
import SwiftUI

/// Каталог подкастов: сетка вертикальных обложек, как на сайте.
struct PodcastsView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.appAccent) private var accent

    private let columns = [GridItem(.adaptive(minimum: 168, maximum: 220), spacing: 14)]

    var body: some View {
        Group {
            if let error = state.podcastsError, state.podcasts.isEmpty {
                emptyState(
                    icon: "wifi.exclamationmark",
                    title: L10n.string("Не удалось загрузить подкасты"),
                    subtitle: error,
                    action: (L10n.string("Повторить"), { Task { await state.loadPodcasts(force: true) } })
                )
            } else if state.podcasts.isEmpty && state.isLoadingPodcasts {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if state.podcasts.isEmpty {
                emptyState(
                    icon: "mic",
                    title: L10n.string("Подкастов пока нет"),
                    subtitle: L10n.string("Сервер не вернул ни одного подкаста."),
                    action: nil
                )
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(state.podcasts) { podcast in
                            PodcastCard(
                                podcast: podcast,
                                accent: accent,
                                onOpen: { state.showPodcast(podcast) }
                            )
                            .equatable()
                        }
                    }
                    .padding(16)
                    .padding(.bottom, PlayerBar.reservedHeight)
                }
                .scrollIndicators(.automatic)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task { await state.loadPodcasts() }
    }

    private func emptyState(
        icon: String, title: String, subtitle: String, action: (String, () -> Void)?
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.tertiaryText)
            Text(title).font(.headline)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Карточка подкаста

/// Как и карточка станции, не подписана на состояние и сравнивается по данным.
struct PodcastCard: View, Equatable {
    let podcast: Podcast
    let accent: Color
    let onOpen: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered = false

    private static let coverRadius: CGFloat = 14

    static func == (lhs: PodcastCard, rhs: PodcastCard) -> Bool {
        lhs.podcast.id == rhs.podcast.id && lhs.accent == rhs.accent
    }

    var body: some View {
        cover
            .modifier(CardInteraction(
                hovered: $hovered,
                reduceMotion: reduceMotion,
                isCurrent: false,
                accent: accent,
                helpText: helpText,
                radius: Self.coverRadius,
                action: onOpen
            ))
            .modifier(CardAccessibility(
                label: podcast.title,
                value: podcast.summary,
                hint: L10n.string("Двойное нажатие открывает подкаст"),
                action: onOpen
            ))
            .contextMenu {
                Button("Открыть подкаст", action: onOpen)
                if let url = podcast.shareURL {
                    Button("Открыть на сайте") { NSWorkspace.shared.open(url) }
                }
            }
    }

    /// Обложка вертикальная, 750×1042 — поэтому и пропорция такая.
    private var cover: some View {
        ZStack(alignment: .bottomLeading) {
            CachedImage(url: podcast.coverURL, contentMode: .fill, maxPixel: 520) {
                LinearGradient(
                    colors: [accent.opacity(0.28), .black.opacity(0.4)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.15), .black.opacity(0.82)],
                startPoint: .center, endPoint: .bottom
            )

            Text(podcast.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)
                .shadow(color: .black.opacity(0.7), radius: 3, y: 1)
                .padding(10)
        }
        .aspectRatio(750.0 / 1042.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Self.coverRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Self.coverRadius, style: .continuous)
                .strokeBorder(.white.opacity(hovered ? 0.30 : 0.14), lineWidth: 1)
        }
        .overlay(alignment: .topLeading) {
            if podcast.isFresh {
                Text("NEW")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(accent, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .padding(8)
            }
        }
    }

    private var helpText: String {
        podcast.summary.isEmpty ? podcast.title : "\(podcast.title)\n\(podcast.summary)"
    }
}
