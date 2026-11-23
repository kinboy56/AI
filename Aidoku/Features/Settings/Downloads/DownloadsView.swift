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
    @State private var selectedManga = Set<String>()
    @State private var showingRemoveConfirmation = false

    var body: some View {
        List(selection: $selectedManga) {
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
                        ForEach(group.manga) { manga in
                            NavigationLink(destination: DownloadedMangaView(manga: manga).environmentObject(path)) {
                                DownloadedMangaRow(manga: manga)
                            }
                            .swipeActions {
                                if editMode == .inactive {
                                    Button(role: .destructive) {
                                        viewModel.delete(manga: manga)
                                    } label: {
                                        Label(NSLocalizedString("DELETE"), systemImage: "trash")
                                    }
                                }
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
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if editMode == .active {
                    let allSelected = selectedManga.count == viewModel.downloadedManga.count
                    Button {
                        if allSelected {
                            selectedManga = Set()
                        } else {
                            selectedManga = Set(viewModel.downloadedManga.map { $0.id })
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
                    HStack {
                        Button(NSLocalizedString("REMOVE")) {
                            showingRemoveConfirmation = true
                        }
                        .disabled(selectedManga.isEmpty)
                        DoneButton {
                            withAnimation {
                                editMode = .inactive
                            }
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
        .onChange(of: editMode) { mode in
            guard let navigationController = path.rootViewController?.navigationController
            else { return }
            navigationController.setDismissGesturesEnabled(mode != .active)
            if mode == .inactive {
                selectedManga = Set()
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
            Button(NSLocalizedString("CANCEL"), role: .cancel) { }
            Button(NSLocalizedString("REMOVE"), role: .destructive) {
                viewModel.delete(ids: selectedManga)
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
