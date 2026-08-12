import AppKit
import SwiftUI

struct RootView: View {
    @Environment(\.appAccent) private var accent
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
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
        .background { windowSurface.ignoresSafeArea() }
        .windowContainerClearBackground()
        .background(WindowConfigurator { window in
            // Единая full-size поверхность даёт настоящие скругления по всему
            // периметру, включая нижние углы. Заголовок и контент теперь лежат
            // внутри одного непрерывного стеклянного контейнера.
            window.styleMask.insert(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.titlebarSeparatorStyle = .none

            // Без этого система не пропустит обои рабочего стола сквозь окно.
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = true

            // Скругление и кант окна рисует система: она клиппует содержимое
            // по форме окна сама, и радиус у неё свой в каждой версии macOS.
            // Свои cornerRadius и borderWidth поверх этого давали второй кант
            // и заметный уступ, если системный радиус не совпадал с нашим.
            if let contentView = window.contentView {
                contentView.wantsLayer = true
                contentView.layer?.backgroundColor = NSColor.clear.cgColor
            }
        })
        .sheet(item: $state.playlistStation) { station in
            StationPlaylistView(station: station)
                .environmentObject(state)
                .environment(\.appAccent, accent)
        }
        .tint(accent)
    }

    @ViewBuilder
    private var windowSurface: some View {
        if reduceTransparency {
            Theme.opaqueBackground
        } else {
            VisualEffectBackground()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                state.playRandom()
            } label: {
                Label("Случайная станция", systemImage: "shuffle")
            }
            .help("Случайная станция (⇧⌘R)")

            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "mini")
            } label: {
                Label("Мини-плеер", systemImage: "pip")
            }
            .help("Мини-плеер (⌥⌘M)")
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Сортировка", selection: $state.sortOrder) {
                ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(width: 165)

            AccentMenuButton(selection: $state.accent)
        }
    }
}

// MARK: - Боковая панель

struct SidebarView: View {
    @Environment(\.appAccent) private var accent
    @EnvironmentObject private var state: AppState
    @FocusState private var focusedSection: SidebarSection?

    var body: some View {
        List {
            Section {
                ForEach(SidebarSection.allCases) { item in
                    Button {
                        state.section = item
                    } label: {
                        sidebarRow(for: item)
                    }
                    .buttonStyle(.plain)
                    .focused($focusedSection, equals: item)
                    .focusEffectDisabled()
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .listRowBackground(Color.clear)
                    .accessibilityValue(item == state.section ? L10n.string("Выбрано") : "")
                }
            }

            if !state.genres.isEmpty {
                Section("Жанры") {
                    Button {
                        state.selectedGenre = nil
                        if state.section == .history { state.section = .all }
                    } label: {
                        genreRow(title: L10n.string("Все жанры"), active: state.selectedGenre == nil)
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

    private func sidebarRow(for item: SidebarSection) -> some View {
        let selected = item == state.section
        let focused = item == focusedSection

        return HStack(spacing: 9) {
            Image(systemName: item.icon)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(selected ? accent : Color.primary)
                .frame(width: 16)

            Text(item.title)
                .font(.system(size: 13, weight: selected ? .semibold : .medium))

            Spacer(minLength: 8)

            if item == .favorites, !state.favorites.isEmpty {
                Text("\(state.favorites.count)")
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(selected ? Color.primary.opacity(0.10) : .clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    focused ? accent.opacity(0.80) : Color.white.opacity(selected ? 0.10 : 0),
                    lineWidth: focused ? 1.5 : 1
                )
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
