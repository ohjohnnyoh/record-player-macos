import AppKit
import SwiftUI

struct RootView: View {
    @Environment(\.appAccent) private var accent
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            Group {
                switch state.section {
                case .all, .favorites:
                    StationGridView()
                case .history:
                    HistoryView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Плеер не в раскладке, а поверх неё — карточки проезжают под пилюлей.
            .overlay(alignment: .bottom) { PlayerBar() }
        }
        .navigationTitle("")
        .toolbar { toolbarContent }
        .searchable(
            text: $state.searchText,
            placement: .toolbar,
            prompt: "Поиск станции или жанра"
        )
        // Один слой прозрачности на всё окно, а не на правую колонку.
        //
        // Раньше он висел на колонке с сеткой, да ещё и с `.ignoresSafeArea()` —
        // то есть вылезал за её границы под сайдбар, и в зоне перекрытия
        // складывались два размытия. Вдобавок колонка меняет размер каждый кадр
        // при выезде сайдбара, и система пересчитывала размытие обоев на каждом.
        // Здесь размер backdrop равен окну и во время анимации не меняется.
        .background(VisualEffectBackground().ignoresSafeArea())
        .windowContainerClearBackground()
        .background(WindowConfigurator { window in
            // Без этого система не пропустит обои рабочего стола сквозь окно.
            window.isOpaque = false
            window.backgroundColor = .clear
        })
        .tint(accent)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                state.playRandom()
            } label: {
                Label("Случайная станция", systemImage: "shuffle")
            }
            .help("Случайная станция (⇧⌘R)")
        }

        ToolbarItem(placement: .navigation) {
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "mini")
            } label: {
                Label("Мини-плеер", systemImage: "pip")
            }
            .help("Мини-плеер (⌥⌘M)")
        }

        ToolbarItem(placement: .primaryAction) {
            Picker("Сортировка", selection: $state.sortOrder) {
                ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 165)
        }

        ToolbarItem(placement: .primaryAction) {
            AccentMenuButton(selection: $state.accent)
        }
    }
}

// MARK: - Боковая панель

struct SidebarView: View {
    @Environment(\.appAccent) private var accent
    @EnvironmentObject private var state: AppState

    var body: some View {
        List(selection: Binding(
            get: { state.section },
            set: { newValue in
                if let newValue { state.section = newValue }
            }
        )) {
            Section {
                ForEach(SidebarSection.allCases) { item in
                    Label {
                        HStack {
                            Text(item.title)
                            Spacer()
                            if item == .favorites, !state.favorites.isEmpty {
                                Text("\(state.favorites.count)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.tertiaryText)
                            }
                        }
                    } icon: {
                        Image(systemName: item.icon)
                    }
                    .tag(item)
                }
            }

            if !state.genres.isEmpty {
                Section("Жанры") {
                    Button {
                        state.selectedGenre = nil
                        if state.section == .history { state.section = .all }
                    } label: {
                        genreRow(title: "Все жанры", active: state.selectedGenre == nil)
                    }
                    .buttonStyle(.plain)

                    ForEach(state.genres, id: \.self) { genre in
                        Button {
                            state.selectedGenre = (state.selectedGenre == genre) ? nil : genre
                            if state.section == .history { state.section = .all }
                        } label: {
                            genreRow(title: genre, active: state.selectedGenre == genre)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            if state.stations.isEmpty && state.isLoadingStations {
                ProgressView().controlSize(.small).padding(.bottom, 10)
            }
        }
    }

    private func genreRow(title: String, active: Bool) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(active ? accent : Color.white.opacity(0.18))
                .frame(width: 6, height: 6)
            Text(title)
                .foregroundStyle(active ? Color.primary : Theme.secondaryText)
            Spacer()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 1)
    }
}
