//
//  DownloadedMangaView.swift
//  Aidoku
//
//  Created by doomsboygaming on 6/25/25.
//

import AidokuRunner
import SwiftUI

struct DownloadedMangaView: View {
    @StateObject private var viewModel: ViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var path: NavigationCoordinator

    @State private var openChapter: DownloadedChapterInfo?
    @State private var editMode = EditMode.inactive
    @State private var selectedChapters = Set<String>()
    @State private var showingRemoveConfirmation = false

    @Namespace private var transitionNamespace

    init(manga: DownloadedMangaInfo) {
        self._viewModel = StateObject(wrappedValue: .init(manga: manga))
    }

    var body: some View {
        Group {
            if viewModel.chapters.isEmpty {
                if viewModel.isLoading {
                    ProgressView(NSLocalizedString("LOADING_ELLIPSIS"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    emptyStateView
                }
            } else {
                chaptersList
            }
        }
        .navigationTitle(viewModel.manga.displayTitle)
        .navigationBarBackButtonHidden(editMode == .active)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if editMode == .active {
                    let allSelected = !viewModel.chapters.isEmpty
                        && viewModel.chapters.allSatisfy { selectedChapters.contains($0.chapterId) }
                    Button {
                        if allSelected {
                            selectedChapters = Set()
                        } else {
                            selectedChapters = Set(viewModel.chapters.map { $0.chapterId })
                        }
                    } label: {
                        if allSelected {
                            Text(NSLocalizedString("DESELECT_ALL"))
                        } else {
                            Text(NSLocalizedString("SELECT_ALL"))
                        }
                    }
                    .disabled(viewModel.chapters.isEmpty)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if editMode == .active {
                    HStack {
                        Button(NSLocalizedString("REMOVE")) {
                            showingRemoveConfirmation = true
                        }
                        .disabled(selectedChapters.isEmpty)
                        DoneButton {
                            withAnimation {
                                editMode = .inactive
                            }
                        }
                    }
                } else {
                    Menu {
                        Section {
                            if viewModel.manga.isInLibrary, let source = SourceManager.shared.store.source(for: viewModel.manga.sourceId) {
                                Button {
                                    openMangaView(source: source)
                                } label: {
                                    Label(NSLocalizedString("VIEW_SERIES"), systemImage: "book")
                                }
                            }

                            Button {
                                if let url = DownloadManager.shared.getMangaDirectoryUrl(identifier: viewModel.manga.mangaIdentifier) {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                Label(NSLocalizedString("VIEW_FILES"), systemImage: "folder")
                            }
                        }

                        if !viewModel.chapters.isEmpty {
                            Section {
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
                            }
                        }
                    } label: {
                        MoreIcon()
                    }
                }
            }
        }
        .onChange(of: editMode) { mode in
            if mode == .inactive {
                selectedChapters = Set()
            }
            guard let navigationController = path.rootViewController?.navigationController
            else { return }
            navigationController.setDismissGesturesEnabled(mode != .active)
        }
        .task {
            await viewModel.loadChapters()
            await viewModel.loadHistory()
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
                viewModel.delete(chapters: selectedChapters)
                withAnimation {
                    editMode = .inactive
                }
            }
        } message: {
            Text(NSLocalizedString("REMOVE_DOWNLOADS_CONFIRM"))
        }
        .fullScreenCover(item: $openChapter) { chapter in
            SwiftUIReaderNavigationController(
                source: SourceManager.shared.store.source(for: viewModel.manga.sourceId),
                manga: viewModel.manga.toManga(),
                chapter: chapter.toChapter()
            )
            .ignoresSafeArea()
            .navigationTransitionZoom(sourceID: chapter, in: transitionNamespace)
        }
    }

    private var emptyStateView: some View {
        UnavailableView(
            NSLocalizedString("NO_DOWNLOADS"),
            systemImage: "arrow.down.circle",
            description: Text(NSLocalizedString("NO_DOWNLOADS_TEXT"))
        )
        .ignoresSafeArea()
    }

    private var chaptersList: some View {
        List(selection: $selectedChapters) {
            Section {
                mangaInfoHeader
                    .tag(0)
            }

            Section {
                ForEach(viewModel.chapters) { chapter in
                    if editMode == .inactive {
                        Button {
                            openChapter = chapter
                        } label: {
                            ChapterRow(chapter: chapter, history: viewModel.readingHistory[chapter.chapterId])
                        }
                        .foregroundStyle(.primary)
                        .disabled(chapter.failed)
                        .contextMenu {
                            if !chapter.failed {
                                Button {
                                    showShareSheet(chapter: chapter)
                                } label: {
                                    Label(NSLocalizedString("SHARE"), systemImage: "square.and.arrow.up")
                                }
                            }
                        }
                        .matchedTransitionSourcePlease(id: chapter, in: transitionNamespace)
                        .tag(chapter.chapterId)
                    } else {
                        ChapterRow(chapter: chapter, history: viewModel.readingHistory[chapter.chapterId])
                            .tag(chapter.chapterId)
                    }
                }
                .onDelete(perform: delete)
            } header: {
                HStack {
                    Text(NSLocalizedString("DOWNLOADED_CHAPTERS"))

                    Spacer()

                    if editMode == .inactive {
                        Button(action: viewModel.toggleSortOrder) {
                            Image(systemName: viewModel.sortAscending ? "arrow.up" : "arrow.down")
                                .imageScale(.small)
                        }
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .clearsStaleListSelection(selectedChapters)
        .restoresListSelectionOnAppear($selectedChapters)
    }

    private var mangaInfoHeader: some View {
        HStack(spacing: 12) {
            MangaCoverView(
                source: SourceManager.shared.store.source(for: viewModel.manga.sourceId),
                coverImage: viewModel.manga.coverUrl ?? "",
                width: 56,
                height: 56 * 3/2
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.manga.displayTitle)
                    .font(.callout)
                    .lineLimit(2)

                // Format like chapter subtitles: Date • Size
                Text(formatMangaSubtitle())
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if viewModel.manga.isInLibrary {
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
        .padding(.vertical, 4)
    }

    private func delete(at offsets: IndexSet) {
        guard editMode == .inactive else { return }
        let chapters = offsets.map { viewModel.chapters[$0] }
        for chapter in chapters {
            viewModel.deleteChapter(chapter)
        }
    }

    private func formatMangaSubtitle() -> String {
        var components: [String] = []

        // Add current date (when viewed)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        components.append(formatter.string(from: Date()))

        // Add size
        components.append(viewModel.manga.formattedSize)

        return components.joined(separator: " • ")
    }

    private func openMangaView(source: AidokuRunner.Source) {
        let viewController = MangaViewController(
            source: source,
            manga: viewModel.manga.toManga(),
            parent: path.rootViewController
        )
        path.push(viewController)
    }

    private func showShareSheet(chapter: DownloadedChapterInfo) {
        Task {
            let identifier = ChapterIdentifier(
                sourceKey: viewModel.manga.sourceId,
                mangaKey: viewModel.manga.mangaId,
                chapterKey: chapter.chapterId
            )
            if let url = await DownloadManager.shared.getCompressedFile(for: identifier) {
                let activityViewController = UIActivityViewController(
                    activityItems: [url],
                    applicationActivities: nil
                )
                guard let sourceView = path.rootViewController?.view else { return }
                activityViewController.popoverPresentationController?.sourceView = sourceView
                // manually positioned in top right of screen, near the right navigation bar button
                activityViewController.popoverPresentationController?.sourceRect = CGRect(
                    x: UIScreen.main.bounds.width - 30,
                    y: 60,
                    width: 0,
                    height: 0
                )
                path.present(activityViewController)
            }
        }
    }
}

private struct ChapterRow: View {
    let chapter: DownloadedChapterInfo
    let history: (page: Int, date: Int)?

    var isRead: Bool {
        history?.page == -1
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(chapter.displayTitle)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(isRead ? .secondary : .primary)

                // Format like chapter subtitles: Date • Size
                if let subtitle = formatChapterSubtitle() {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if chapter.failed {
                Image(systemName: "exclamationmark.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.orange)
            }
        }
        .contentShape(Rectangle())
    }

    private func formatChapterSubtitle() -> String? {
        var components: [String] = []

        if chapter.failed {
            components.append(NSLocalizedString("DOWNLOAD_INCOMPLETE"))
        }

        // download date
        if let downloadDate = chapter.downloadDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            components.append(formatter.string(from: downloadDate))
        }

        // file size
        components.append(ByteCountFormatter.string(fromByteCount: chapter.size, countStyle: .file))

        // pages read
        if let page = history?.page, page > 0 {
            components.append(String(format: NSLocalizedString("PAGE_X"), page))
        }

        return components.isEmpty ? nil : components.joined(separator: " • ")
    }
}

#Preview {
    DownloadedMangaView(
        manga: DownloadedMangaInfo(
            sourceId: "test",
            mangaId: "test-manga",
            title: "Test Manga",
            coverUrl: nil,
            totalSize: 52428800, // 50 MB
            chapterCount: 12,
            isInLibrary: true
        )
    )
}
