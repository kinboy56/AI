//
//  DownloadsView.swift
//  Aidoku
//
//  Created by doomsboygaming on 6/25/25.
//

import SwiftUI

struct DownloadsView: View {
    @StateObject private var viewModel = ViewModel()
    @EnvironmentObject private var path: NavigationCoordinator

    @State private var editMode = EditMode.inactive
    @State private var selectedManga: Set<MangaIdentifier> = []
    @State private var showingRemoveConfirmation = false

    var body: some View {
        let list = List(selection: $selectedManga) {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(NSLocalizedString("TOTAL_DOWNLOADS"))
                            .font(.headline)
                        Spacer()
                        if viewModel.isLoading {
                            ProgressView()
                        } else {
                            Text(viewModel.totalSize)
                                .font(.headline)
                                .foregroundStyle(.primary)
                        }
                    }

                    HStack {
                        Text(String(format: NSLocalizedString("%i_SERIES"), viewModel.totalCount))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        let totalChapters = viewModel.downloadedManga.reduce(0) { $0 + $1.chapterCount }
                        Text(
                            (
                                totalChapters == 1
                                    ? NSLocalizedString("1_CHAPTER")
                                    : String(format: NSLocalizedString("%i_CHAPTERS"), totalChapters)
                            )
                            .lowercased()
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }

            ForEach(Settings.downloadSettings, id: \.key) { setting in
                SettingView(setting: setting)
                    .disabled(editMode == .active)
                    .allowsHitTesting(editMode == .inactive)
            }

            if viewModel.downloadedManga.isEmpty && viewModel.isLoading {
                Section {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .transition(.opacity)
                        .listRowBackground(Color.clear)
                }
            } else {
                ForEach(viewModel.groupedManga, id: \.source) { group in
                    Section(header: Text(group.source)) {
                        ForEach(group.manga, id: \.mangaIdentifier) { manga in
                            if editMode == .inactive {
                                NavigationLink(destination: DownloadedMangaView(manga: manga).environmentObject(path)) {
                                    DownloadedMangaRow(manga: manga)
                                }
                                .swipeActions {
                                    Button(role: .destructive) {
                                        viewModel.delete(manga: manga)
                                    } label: {
                                        Label(NSLocalizedString("DELETE"), systemImage: "trash")
                                    }
                                }
                                .tag(manga.mangaIdentifier)
                            } else {
                                DownloadedMangaRow(manga: manga)
                                    .tag(manga.mangaIdentifier)
                            }
                        }
                    }
                }
            }
        }
        .refreshable {
            if editMode == .inactive {
                await viewModel.loadDownloadedManga()
            }
        }
        .onChange(of: editMode) { mode in
            if mode == .inactive {
                selectedManga = []
            }
            updateEditingChrome(isEditing: mode == .active, animated: true)
        }
        .onDisappear {
            guard editMode == .active else { return }
            editMode = .inactive
            selectedManga = []
            updateEditingChrome(isEditing: false, animated: false)
        }
        .onChange(of: viewModel.downloadedManga) { manga in
            let validIds = Set(manga.map(\.mangaIdentifier))
            selectedManga = selectedManga.intersection(validIds)
            if manga.isEmpty && editMode == .active {
                withAnimation {
                    editMode = .inactive
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.isLoading)
        .animation(.easeInOut(duration: 0.3), value: viewModel.downloadedManga.isEmpty)
        .navigationTitle(NSLocalizedString("DOWNLOADS"))
        .navigationBarBackButtonHidden(editMode == .active)
        .task {
            await viewModel.loadDownloadedManga()
        }
        .alert(NSLocalizedString("REMOVE_ALL_DOWNLOADS"), isPresented: $viewModel.showingDeleteAllConfirmation) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) { }
            Button(NSLocalizedString("REMOVE"), role: .destructive) {
                viewModel.deleteAllChapters()
            }
        } message: {
            Text(NSLocalizedString("REMOVE_ALL_DOWNLOADS_CONFIRM"))
        }
        .alert(NSLocalizedString("REMOVE_DOWNLOADS"), isPresented: $showingRemoveConfirmation) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) {}
            Button(NSLocalizedString("REMOVE"), role: .destructive) {
                viewModel.delete(mangaIds: selectedManga)
                withAnimation {
                    editMode = .inactive
                }
            }
        } message: {
            Text(NSLocalizedString("REMOVE_DOWNLOADS_CONFIRM"))
        }
        .alert(NSLocalizedString("METADATA_DETECTED"), isPresented: $viewModel.showingMigrateNotice) {
            Button(NSLocalizedString("OK"), role: .cancel) {
                viewModel.migrate()
            }
        } message: {
            Text(NSLocalizedString("METADATA_DETECTED_TEXT"))
        }
        .environment(\.editMode, $editMode)
        .clearsStaleListSelection(selectedManga)
        .restoresListSelectionOnAppear($selectedManga)

        if #available(iOS 26.0, *) {
            list
                .toolbar {
                    toolbarContentiOS26
                }
        } else {
            list
                .toolbar {
                    toolbarContentBase

                    ToolbarItemGroup(placement: .bottomBar) {
                        if editMode == .active {
                            HStack {
                                Spacer()
                                removeSelectedButton
                            }
                        }
                    }
                }
        }
    }

    @ContentBuilder
    private var toolbarContentBase: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if editMode == .active {
                let allSelected = !viewModel.downloadedManga.isEmpty
                    && viewModel.downloadedManga.allSatisfy { selectedManga.contains($0.mangaIdentifier) }
                Button {
                    if allSelected {
                        selectedManga = []
                    } else {
                        selectedManga = Set(viewModel.downloadedManga.map(\.mangaIdentifier))
                    }
                } label: {
                    if allSelected {
                        Text(NSLocalizedString("DESELECT_ALL"))
                    } else {
                        Text(NSLocalizedString("SELECT_ALL"))
                    }
                }
                .disabled(viewModel.downloadedManga.isEmpty)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if editMode == .active {
                DoneButton {
                    withAnimation {
                        editMode = .inactive
                    }
                }
            } else if !viewModel.downloadedManga.isEmpty {
                Menu {
                    Button {
                        withAnimation {
                            editMode = .active
                        }
                    } label: {
                        Label(NSLocalizedString("SELECT"), systemImage: "checkmark.circle")
                    }
                    Button(role: .destructive, action: viewModel.confirmDeleteAll) {
                        Label(NSLocalizedString("REMOVE_ALL_DOWNLOADS"), systemImage: "trash")
                    }
                } label: {
                    MoreIcon()
                }
            }
        }
    }

    @available(iOS 26.0, *)
    @ContentBuilder
    private var toolbarContentiOS26: some ToolbarContent {
        toolbarContentBase

        if editMode == .active {
            ToolbarSpacer(.flexible, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                removeSelectedButton
            }
        }
    }

    private var removeSelectedButton: some View {
        Button(NSLocalizedString("REMOVE")) {
            showingRemoveConfirmation = true
        }
        .disabled(selectedManga.isEmpty)
    }

    private func updateEditingChrome(isEditing: Bool, animated: Bool) {
        guard let navigationController = path.navigationController else { return }
        navigationController.setDismissGesturesEnabled(!isEditing)
        func apply() {
            if isEditing {
                navigationController.isToolbarHidden = false
            }
            navigationController.toolbar.alpha = isEditing ? 1 : 0
            if #available(iOS 26.0, *) {
                navigationController.tabBarController?.isTabBarHidden = isEditing
            }
        }
        if animated {
            UIView.animate(withDuration: 0.3, animations: apply) { _ in
                if !isEditing && editMode == .inactive {
                    navigationController.isToolbarHidden = true
                }
            }
        } else {
            apply()
            if !isEditing {
                navigationController.isToolbarHidden = true
            }
        }
    }
}

private struct DownloadedMangaRow: View {
    let manga: DownloadedMangaInfo

    var body: some View {
        HStack(spacing: 12) {
            // Manga cover or placeholder matching history page style
            MangaCoverView(
                source: SourceManager.shared.store.source(for: manga.sourceId),
                coverImage: manga.coverUrl ?? "",
                width: 56,
                height: 56 * 3/2
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(manga.displayTitle)
                    .font(.callout)
                    .lineLimit(2)

                // Format like chapter subtitles: chapters • size
                Text(formatMangaSubtitle())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if manga.isInLibrary {
                    HStack(spacing: 4) {
                        Image(systemName: "books.vertical.fill")
                            .imageScale(.small)
                        Text(NSLocalizedString("IN_LIBRARY"))
                            .font(.footnote)
                    }
                    .foregroundStyle(.tint)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
    }

    private func formatMangaSubtitle() -> String {
        var components: [String] = []

        // Add chapter count
        let chapterText = (
            manga.chapterCount == 1
                ? NSLocalizedString("1_CHAPTER")
                : String(format: NSLocalizedString("%i_CHAPTERS"), manga.chapterCount)
        )
        .lowercased()
        components.append(chapterText)

        // Add size
        components.append(manga.formattedSize)

        return components.joined(separator: " • ")
    }
}

#Preview {
    PlatformNavigationStack {
        DownloadsView()
    }
}
