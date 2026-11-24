//
//  BackupsView.swift
//  Aidoku
//
//  Created by Skitty on 9/19/25.
//

import SwiftUI

struct BackupsView: View {
    @State private var backupUrls: [URL] = []
    @State private var backups: [URL: BackupInfo] = [:]
    @State private var invalidBackups: Set<URL> = []

    @State private var loadedInitialBackupInfo = false
    @State private var targetRestoreBackup: BackupInfo?
    @State private var targetExportBackup: BackupInfo?
    @State private var showCreateSheet = false
    @State private var showImportSheet = false
    @State private var showAutoBackupsSheet = false
    @State private var showImportFailAlert = false
    @State private var editMode = EditMode.inactive
    @State private var selectedBackups: Set<URL> = []
    @State private var showingDeleteConfirmation = false

    @EnvironmentObject private var path: NavigationCoordinator

    @Namespace private var transitionNamespace

    private enum SheetID: String {
        case autoBackup
    }

    init() {
        self._backupUrls = State(initialValue: BackupManager.backupUrls)
    }

    var body: some View {
        let list = List(selection: $selectedBackups) {
            Section {
                ForEach(backupUrls, id: \.self) { url in
                    let backup = backups[url]

                    if let backup {
                        backupCell(backup: backup)
                            .tag(url)
                    } else if invalidBackups.contains(url) {
                        corruptedBackupCell(url: url)
                            .tag(url)
                    } else {
                        loadingBackupCell(url: url)
                            .tag(url)
                    }
                }
            } footer: {
                if !backupUrls.isEmpty {
                    Text(NSLocalizedString("BACKUP_INFO"))
                }
            }
        }
        .animation(.default, value: backupUrls)
        .animation(.default, value: backups)
        .navigationTitle(NSLocalizedString("BACKUPS"))
        .navigationBarBackButtonHidden(editMode == .active)
        .sheet(isPresented: $showCreateSheet) {
            BackupCreateView()
        }
        .sheet(isPresented: $showImportSheet) {
            DocumentPickerView(
                allowedContentTypes: [
                    .init(filenameExtension: "aib")!,
                    .json
                ],
                onDocumentsPicked: { urls in
                    guard let url = urls.first else {
                        return
                    }
                    Task {
                        let result = await BackupManager.shared.importBackup(from: url)
                        if !result {
                            showImportFailAlert = true
                        }
                    }
                }
            )
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showAutoBackupsSheet) {
            AutomaticBackupsView()
                .navigationTransitionZoom(sourceID: SheetID.autoBackup, in: transitionNamespace)
        }
        .sheet(item: $targetRestoreBackup) { backup in
            BackupContentView(backup: backup)
        }
        .alert(NSLocalizedString("IMPORT_FAIL"), isPresented: $showImportFailAlert) {
            Button(NSLocalizedString("OK"), role: .cancel) {}
        } message: {
            Text(NSLocalizedString("BACKUP_IMPORT_FAIL_TEXT"))
        }
        .alert(NSLocalizedString("DELETE_BACKUPS"), isPresented: $showingDeleteConfirmation) {
            Button(NSLocalizedString("CANCEL"), role: .cancel) {}
            Button(NSLocalizedString("DELETE"), role: .destructive) {
                deleteBackups(urls: selectedBackups)
                withAnimation {
                    editMode = .inactive
                }
            }
        } message: {
            Text(NSLocalizedString("DELETE_BACKUPS_CONFIRM"))
        }
        .onChange(of: editMode) { mode in
            if mode == .inactive {
                selectedBackups = []
            }
            updateEditingChrome(isEditing: mode == .active, animated: true)
        }
        .onDisappear {
            guard editMode == .active else { return }
            editMode = .inactive
            selectedBackups = []
            updateEditingChrome(isEditing: false, animated: false)
        }
        .onChange(of: backupUrls) { urls in
            selectedBackups = selectedBackups.intersection(urls)
            if urls.isEmpty && editMode == .active {
                withAnimation {
                    editMode = .inactive
                }
            }
        }
        .onAppear {
            guard !loadedInitialBackupInfo else { return }
            loadedInitialBackupInfo = true
            loadBackupInfo()
        }
        .onReceive(NotificationCenter.default.publisher(for: .updateBackupList)) { _ in
            backupUrls = BackupManager.backupUrls
            loadBackupInfo()
        }
        .environment(\.editMode, $editMode)
        .clearsStaleListSelection(selectedBackups)
        .restoresListSelectionOnAppear($selectedBackups)

        if #available(iOS 26.0, *) {
            list
                .toolbar {
                    toolbarContentiOS26
                }
        } else {
            list
                .toolbar {
                    toolbarContentLegacy
                }
        }
    }
}

extension BackupsView {
    var autoBackupButton: some View {
        Button {
            showAutoBackupsSheet = true
        } label: {
            let imageName = if #available(iOS 18.0, *) {
                "clock.arrow.trianglehead.counterclockwise.rotate.90"
            } else {
                "clock.arrow.circlepath"
            }
            Image(systemName: imageName)
        }
        .matchedTransitionSourcePlease(id: SheetID.autoBackup, in: transitionNamespace)
    }

    var selectButton: some View {
        Button {
            withAnimation {
                editMode = .active
            }
        } label: {
            Image(systemName: "checkmark.circle")
        }
        .accessibilityLabel(NSLocalizedString("SELECT"))
    }

    @ContentBuilder
    var selectAllButton: some View {
        let allSelected = !backupUrls.isEmpty
            && backupUrls.allSatisfy { selectedBackups.contains($0) }
        Button {
            if allSelected {
                selectedBackups = []
            } else {
                selectedBackups = Set(backupUrls)
            }
        } label: {
            if allSelected {
                Text(NSLocalizedString("DESELECT_ALL"))
            } else {
                Text(NSLocalizedString("SELECT_ALL"))
            }
        }
        .disabled(backupUrls.isEmpty)
    }

    var deleteSelectedButton: some View {
        Button(NSLocalizedString("DELETE")) {
            showingDeleteConfirmation = true
        }
        .disabled(selectedBackups.isEmpty)
    }

    var createBackupButton: some View {
        Menu {
            Button {
                showCreateSheet = true
            } label: {
                Label(NSLocalizedString("CREATE_BACKUP"), systemImage: "plus")
            }
            Button {
                showImportSheet = true
            } label: {
                Label(NSLocalizedString("IMPORT_BACKUP"), systemImage: "square.and.arrow.down")
            }
        } label: {
            Image(systemName: "plus")
        }
    }

    @available(iOS 26.0, *)
    @ContentBuilder
    var toolbarContentiOS26: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if editMode == .active {
                selectAllButton
            }
        }

        if editMode == .active {
            ToolbarItem(placement: .topBarTrailing) {
                DoneButton {
                    withAnimation {
                        editMode = .inactive
                    }
                }
            }

            ToolbarSpacer(.flexible, placement: .bottomBar)

            ToolbarItem(placement: .bottomBar) {
                deleteSelectedButton
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) {
                autoBackupButton
            }

            ToolbarSpacer(placement: .topBarTrailing)

            ToolbarItemGroup(placement: .topBarTrailing) {
                if !backupUrls.isEmpty {
                    selectButton
                }
                createBackupButton
            }
        }
    }

    @ContentBuilder
    var toolbarContentLegacy: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if editMode == .active {
                selectAllButton
            }
        }

        if editMode == .active {
            ToolbarItem(placement: .topBarTrailing) {
                DoneButton {
                    withAnimation {
                        editMode = .inactive
                    }
                }
            }
        } else {
            ToolbarItemGroup(placement: .topBarTrailing) {
                autoBackupButton
                if !backupUrls.isEmpty {
                    selectButton
                }
                createBackupButton
            }
        }

        ToolbarItemGroup(placement: .bottomBar) {
            if editMode == .active {
                HStack {
                    Spacer()
                    deleteSelectedButton
                }
            }
        }
    }

    @ContentBuilder
    func backupCell(backup: BackupInfo) -> some View {
        let url = backup.url
        if editMode == .inactive {
            Button {
                targetRestoreBackup = backup
            } label: {
                backupRowContent(backup: backup)
            }
            .foregroundStyle(.primary)
            .swipeActions {
                Button(role: .destructive) {
                    deleteBackup(url: url)
                } label: {
                    Label(NSLocalizedString("DELETE"), systemImage: "trash")
                }
                Button {
                    showRenamePrompt(targetRenameBackupUrl: url, initialName: backup.name)
                } label: {
                    Label(NSLocalizedString("RENAME"), systemImage: "pencil")
                }
                .tint(.indigo)
            }
            .contextMenu {
                Button {
                    targetExportBackup = backup
                } label: {
                    Label(NSLocalizedString("EXPORT"), systemImage: "square.and.arrow.up")
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onChange(of: targetExportBackup) { newValue in
                            if newValue == backup {
                                export(url: url, sourceRect: geo.frame(in: .global))
                                targetExportBackup = nil
                            }
                        }
                }
            )
        } else {
            backupRowContent(backup: backup)
        }
    }

    func backupRowContent(backup: BackupInfo) -> some View {
        HStack {
            let date = DateFormatter.localizedString(from: backup.date, dateStyle: .short, timeStyle: .short)
            if let name = backup.name {
                VStack(alignment: .leading) {
                    HStack {
                        Text(name)
                            .lineLimit(1)
                        if backup.automatic {
                            automaticBadge
                        }
                    }
                    Text(date)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    Text(String(format: NSLocalizedString("BACKUP_%@"), date))
                        .lineLimit(1)
                    if backup.automatic {
                        automaticBadge
                    }
                }
            }
            Spacer()
            if let size = backup.size {
                Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
        }
        .contentShape(Rectangle())
    }

    @ContentBuilder
    func corruptedBackupCell(url: URL) -> some View {
        if editMode == .inactive {
            Text(NSLocalizedString("CORRUPTED_BACKUP"))
                .swipeActions {
                    Button(role: .destructive) {
                        deleteBackup(url: url)
                    } label: {
                        Label(NSLocalizedString("DELETE"), systemImage: "trash")
                    }
                }
        } else {
            Text(NSLocalizedString("CORRUPTED_BACKUP"))
        }
    }

    @ContentBuilder
    func loadingBackupCell(url: URL) -> some View {
        if editMode == .inactive {
            ProgressView()
                .progressViewStyle(.circular)
                .swipeActions {
                    Button(role: .destructive) {
                        deleteBackup(url: url)
                    } label: {
                        Label(NSLocalizedString("DELETE"), systemImage: "trash")
                    }
                }
        } else {
            ProgressView()
                .progressViewStyle(.circular)
        }
    }

    var automaticBadge: some View {
        Text(NSLocalizedString("AUTO"))
            .lineLimit(1)
            .foregroundStyle(.primary)
            .font(.caption)
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(.blue.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    func deleteBackup(url: URL) {
        deleteBackups(urls: [url])
    }

    func deleteBackups(urls: Set<URL>) {
        let urlsToRemove = backupUrls.filter { urls.contains($0) }
        guard !urlsToRemove.isEmpty else { return }
        backupUrls.removeAll { urls.contains($0) }
        for url in urlsToRemove {
            backups.removeValue(forKey: url)
            invalidBackups.remove(url)
        }
        Task {
            for url in urlsToRemove {
                await BackupManager.shared.removeBackup(url: url)
            }
        }
    }

    func updateEditingChrome(isEditing: Bool, animated: Bool) {
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

    func showRenamePrompt(targetRenameBackupUrl: URL, initialName: String?) {
        var alertTextField: UITextField?
        UIApplication.shared.appDelegate?.presentAlert(
            title: NSLocalizedString("RENAME_BACKUP"),
            message: NSLocalizedString("RENAME_BACKUP_TEXT"),
            actions: [
                UIAlertAction(title: NSLocalizedString("CANCEL"), style: .cancel),
                UIAlertAction(title: NSLocalizedString("OK"), style: .default) { _ in
                    guard let text = alertTextField?.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
                    renameBackup(url: targetRenameBackupUrl, name: text)
                }
            ],
            textFieldHandlers: [
                { textField in
                    textField.placeholder = NSLocalizedString("BACKUP_NAME")
                    textField.text = initialName
                    textField.autocorrectionType = .no
                    textField.returnKeyType = .done
                    alertTextField = textField
                }
            ],
            textFieldDisablesLastActionWhenEmpty: true
        )
    }
}

extension BackupsView {
    func loadBackupInfo() {
        Task.detached { [backupUrls] in
            for backupUrl in backupUrls {
                let backup = BackupInfo.load(from: backupUrl)
                await MainActor.run {
                    if let backup {
                        self.backups[backupUrl] = backup
                        self.invalidBackups.remove(backupUrl)
                    } else {
                        self.invalidBackups.insert(backupUrl)
                    }
                }
            }
        }
    }

    func renameBackup(url: URL, name: String) {
        Task {
            // renaming requires re-encoding the backup, so it can fail even though the info loaded fine
            let renamed = await BackupManager.shared.renameBackup(url: url, name: name)
            if !renamed {
                UIApplication.shared.appDelegate?.presentAlert(
                    title: NSLocalizedString("CORRUPTED_BACKUP"),
                    message: NSLocalizedString("CORRUPTED_BACKUP_TEXT")
                )
            }
        }
    }

    func export(url: URL, sourceRect: CGRect) {
        let vc = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        guard let sourceView = path.rootViewController?.view else { return }
        vc.popoverPresentationController?.sourceView = sourceView
        vc.popoverPresentationController?.sourceRect = sourceRect
        path.present(vc)
    }
}
