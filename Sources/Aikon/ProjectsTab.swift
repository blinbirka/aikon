import SwiftUI
import AppKit

/// The "Projects" section of the settings window (sidebar: `settings.nav.projects`).
/// Full width, no outer page padding — the hook banner and the bottom bar are
/// meant to run edge to edge, unlike every other section's padded cards.
struct ProjectsSettingsTab: View {
    @ObservedObject var configStore: ConfigStore

    @State private var hookState = HookInstaller.state()
    /// Mirrors `Self.bannerDismissedForSession`, which is what actually
    /// survives the settings window being closed and reopened — a plain
    /// `@State` here would reset every time SwiftUI recreates this view.
    @State private var bannerDismissed = ProjectsSettingsTab.bannerDismissedForSession

    @State private var selectedPath: String?
    @State private var iconMenuPath: String?

    /// "Until the app restarts" for the hook banner's dismiss button — a
    /// static survives the settings window closing and reopening, which
    /// recreates this view, but not an app relaunch.
    private static var bannerDismissedForSession = false

    var body: some View {
        Group {
            if configStore.loadFailed {
                ProjectsErrorState()
            } else if configStore.config.projects.isEmpty {
                ProjectsEmptyState()
            } else {
                content
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if !bannerDismissed && hookState != .installed {
                ProjectsHookBanner(onEnable: enableHook, onDismiss: dismissBanner)
            }
            ProjectsModeBlock(configStore: configStore)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(configStore.config.projects) { project in
                        ProjectRowView(
                            project: project,
                            showsPin: configStore.config.menuMode == .pinned,
                            isSelected: selectedPath == project.path,
                            iconMenuOpen: iconMenuPath == project.path,
                            recentEmojis: configStore.config.recentEmojis,
                            onSelect: { selectedPath = project.path },
                            onTogglePin: { configStore.setPinned(path: project.path, !project.pinned) },
                            onToggleIconMenu: {
                                iconMenuPath = (iconMenuPath == project.path) ? nil : project.path
                            },
                            onCloseIconMenu: { iconMenuPath = nil },
                            onSelectEmoji: { emoji in
                                applyEmoji(emoji, to: project.path)
                                configStore.recordRecentEmoji(emoji)
                                iconMenuPath = nil
                            },
                            onChoosePicture: { choosePicture(for: project.path) },
                            onRemovePicture: { removePicture(for: project.path) },
                            onImageChange: { image in handleImageChange(image, for: project.path) }
                        )
                    }
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.sm)
            }
            ProjectsBottomBar(canRemove: selectedPath != nil, onAdd: addProject, onRemove: removeSelected)
        }
    }

    // MARK: - Hook banner

    private func enableHook() {
        try? HookInstaller.install()
        hookState = HookInstaller.state()
    }

    private func dismissBanner() {
        Self.bannerDismissedForSession = true
        bannerDismissed = true
    }

    // MARK: - Icon actions

    private func applyEmoji(_ emoji: String, to path: String) {
        guard var project = configStore.config.projects.first(where: { $0.path == path }) else { return }
        project.emoji = emoji
        configStore.upsertProject(project)
    }

    private func choosePicture(for path: String) {
        iconMenuPath = nil
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        panel.beginOnSettingsWindow { url in
            guard let url,
                  var project = configStore.config.projects.first(where: { $0.path == path }) else { return }
            project.iconPath = url.path
            configStore.upsertProject(project)
        }
    }

    private func removePicture(for path: String) {
        iconMenuPath = nil
        guard var project = configStore.config.projects.first(where: { $0.path == path }) else { return }
        project.iconPath = nil
        configStore.upsertProject(project)
    }

    private func handleImageChange(_ image: NSImage?, for path: String) {
        guard var project = configStore.config.projects.first(where: { $0.path == path }) else { return }
        if let image {
            project.iconPath = ProjectIcon.save(image) ?? project.iconPath
        } else {
            project.iconPath = nil
        }
        configStore.upsertProject(project)
    }

    // MARK: - Add / remove

    private func addProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let path = url.path
        if configStore.config.projects.contains(where: { $0.path == path }) {
            selectedPath = path
            return
        }
        configStore.upsertProject(ProjectConfig(path: path, name: url.lastPathComponent))
        selectedPath = path
    }

    private func removeSelected() {
        guard let selectedPath else { return }
        configStore.removeProject(path: selectedPath)
        self.selectedPath = nil
    }
}

// MARK: - Hook banner

private struct ProjectsHookBanner: View {
    let onEnable: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            Circle()
                .fill(Theme.accent)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "exclamationmark")
                        .font(.system(size: Theme.FontSize.small, weight: .bold))
                        .foregroundStyle(Theme.textOnAccent)
                )
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(L.string("settings.projects.hookBanner.title"))
                    .font(.system(size: Theme.FontSize.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L.string("settings.projects.hookBanner.description"))
                    .font(.system(size: Theme.FontSize.small))
                    .foregroundStyle(Theme.textDim)
                    .frame(maxWidth: 420, alignment: .leading)
            }
            Spacer(minLength: Theme.Spacing.md)
            Button(action: onEnable) {
                Text(L.string("settings.projects.hookBanner.enable"))
                    .font(.system(size: Theme.FontSize.small, weight: .semibold))
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textOnAccent)
            .background(Theme.accent)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: Theme.FontSize.caption, weight: .semibold))
                    .frame(width: 20, height: 20)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textFaint)
            .accessibilityLabel(L.string("settings.projects.hookBanner.dismiss"))
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.bannerTint)
    }
}

// MARK: - Mode block

private struct ProjectsModeBlock: View {
    @ObservedObject var configStore: ConfigStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Text(L.string("settings.projects.mode.title"))
                    .font(.system(size: Theme.FontSize.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                ModeSwitch(mode: modeBinding)
            }
            Text(descriptionText)
                .font(.system(size: Theme.FontSize.small))
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.Spacing.lg)
    }

    private var modeBinding: Binding<MenuMode> {
        Binding(get: { configStore.config.menuMode }, set: { configStore.setMenuMode($0) })
    }

    private var descriptionText: String {
        configStore.config.menuMode == .pinned
            ? L.string("settings.projects.mode.pinned.description")
            : L.string("settings.projects.mode.running.description")
    }
}

private struct ModeSwitch: View {
    @Binding var mode: MenuMode

    var body: some View {
        HStack(spacing: 2) {
            segment(.pinned, label: L.string("settings.projects.mode.pinned"))
            segment(.running, label: L.string("settings.projects.mode.running"))
        }
        .padding(Theme.Spacing.xs - 1)
        .background(Theme.segmentTrack)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    private func segment(_ value: MenuMode, label: String) -> some View {
        let selected = mode == value
        return Button {
            mode = value
        } label: {
            Text(label)
                .font(.system(size: Theme.FontSize.small, weight: selected ? .semibold : .regular))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs)
        }
        .buttonStyle(.plain)
        .foregroundStyle(selected ? Theme.textPrimary : Theme.textFaint)
        .background(selected ? Theme.segmentSelected : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .shadow(color: .black.opacity(selected ? 0.35 : 0), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Project row

private struct ProjectRowView: View {
    let project: ProjectConfig
    let showsPin: Bool
    let isSelected: Bool
    let iconMenuOpen: Bool
    let recentEmojis: [String]
    let onSelect: () -> Void
    let onTogglePin: () -> Void
    let onToggleIconMenu: () -> Void
    let onCloseIconMenu: () -> Void
    let onSelectEmoji: (String) -> Void
    let onChoosePicture: () -> Void
    let onRemovePicture: () -> Void
    let onImageChange: (NSImage?) -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            glyphButton
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.system(size: Theme.FontSize.body))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(project.path)
                    .font(.system(size: Theme.FontSize.caption, design: .monospaced))
                    .foregroundStyle(Theme.textFaint)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: Theme.Spacing.sm)
            if showsPin {
                pinButton
            }
        }
        .padding(Theme.Spacing.sm)
        .frame(height: 48)
        .background(isSelected || hovering ? Theme.hover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onSelect)
    }

    private var glyphButton: some View {
        ZStack {
            ProjectImageWell(imagePath: project.iconPath, cornerRadius: Theme.Radius.md,
                              onImageChange: onImageChange, onClick: onToggleIconMenu)
            if project.iconPath == nil {
                Text(project.emoji ?? ProjectMatching.defaultEmoji)
                    .font(.system(size: Theme.FontSize.title))
                    .allowsHitTesting(false)
            }
        }
        .frame(width: 28, height: 28)
        .background(Theme.sunk)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .accessibilityLabel(L.string("settings.projects.chooseIcon"))
        .popover(isPresented: Binding(get: { iconMenuOpen }, set: { if !$0 { onCloseIconMenu() } }),
                 arrowEdge: .bottom) {
            EmojiPickerView(currentEmoji: project.emoji ?? ProjectMatching.defaultEmoji,
                             hasImage: project.iconPath != nil,
                             recentEmojis: recentEmojis,
                             onSelectEmoji: onSelectEmoji,
                             onChoosePicture: onChoosePicture,
                             onRemovePicture: onRemovePicture)
        }
    }

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: "pin.fill")
                .font(.system(size: Theme.FontSize.small))
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .foregroundStyle(project.pinned ? Theme.textOnAccent : Theme.textFaint)
        .background(project.pinned ? Theme.accent : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .accessibilityLabel(L.string(project.pinned ? "settings.projects.pin.remove" : "settings.projects.pin.add"))
    }
}

// MARK: - Emoji picker

/// The whole contents of a project's icon popover: search, a "Recent" row,
/// the emoji grid itself, and — below a divider — the picture actions that
/// used to need their own separate menu step. One flat view instead of a
/// menu that led into a second screen, since there's no longer a system
/// palette detour to keep separate from the grid.
private struct EmojiPickerView: View {
    let currentEmoji: String
    let hasImage: Bool
    let recentEmojis: [String]
    let onSelectEmoji: (String) -> Void
    let onChoosePicture: () -> Void
    let onRemovePicture: () -> Void

    @State private var query = ""

    private var results: [String] { EmojiCatalog.search(query) }

    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: Theme.Spacing.xs), count: 8)

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                TextField(L.string("settings.projects.icon.searchPlaceholder"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: Theme.FontSize.small))
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Theme.sunk)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))

                if !recentEmojis.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(L.string("settings.projects.icon.recent"))
                            .font(.system(size: Theme.FontSize.caption))
                            .foregroundStyle(Theme.textFaint)
                        emojiRow(recentEmojis)
                    }
                }
            }
            .padding(Theme.Spacing.md)

            if results.isEmpty {
                Spacer(minLength: 0)
                Text(L.string("settings.projects.icon.noMatches"))
                    .font(.system(size: Theme.FontSize.small))
                    .foregroundStyle(Theme.textFaint)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVGrid(columns: Self.columns, spacing: Theme.Spacing.xs) {
                        ForEach(results, id: \.self) { emoji in
                            cell(emoji)
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.sm)
                }
            }

            HStack(spacing: Theme.Spacing.sm) {
                footerButton(L.string("settings.projects.icon.choosePicture"), action: onChoosePicture)
                if hasImage {
                    footerButton(L.string("settings.projects.icon.removePicture"), action: onRemovePicture)
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
        }
        .frame(width: 300, height: 330)
    }

    private func emojiRow(_ emojis: [String]) -> some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(emojis, id: \.self) { emoji in
                cell(emoji)
            }
        }
    }

    private func cell(_ emoji: String) -> some View {
        EmojiCell(emoji: emoji, isSelected: emoji == currentEmoji) { onSelectEmoji(emoji) }
    }

    private func footerButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.FontSize.small))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textDim)
    }
}

/// One 30×30 cell in the emoji grid or the "Recent" row — hover highlight,
/// and an accent fill for whichever emoji the project currently has.
private struct EmojiCell: View {
    let emoji: String
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(emoji)
                .font(.system(size: Theme.FontSize.title))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Theme.accent : (hovering ? Theme.hover : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .onHover { hovering = $0 }
    }
}

// MARK: - Bottom bar

private struct ProjectsBottomBar: View {
    let canRemove: Bool
    let onAdd: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Button(action: onAdd) {
                Image(systemName: "plus").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textDim)
            .accessibilityLabel(L.string("settings.projects.addButton"))

            Button(action: onRemove) {
                Image(systemName: "minus").frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .foregroundStyle(canRemove ? Theme.textDim : Theme.textFaint)
            .disabled(!canRemove)
            .accessibilityLabel(L.string("settings.projects.removeButton"))

            Spacer()

            Text(L.string("settings.projects.iconHint"))
                .font(.system(size: Theme.FontSize.caption))
                .foregroundStyle(Theme.textFaint)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .top)
    }
}

// MARK: - Empty / error states

private struct ProjectsPlaceholder<Extra: View>: View {
    let systemImage: String
    let titleKey: String
    let descriptionKey: String
    @ViewBuilder var extra: Extra

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            ZStack {
                Circle().fill(Theme.sunk).frame(width: 48, height: 48)
                Image(systemName: systemImage)
                    .font(.system(size: Theme.FontSize.title))
                    .foregroundStyle(Theme.textFaint)
            }
            VStack(spacing: Theme.Spacing.sm) {
                Text(L.string(titleKey))
                    .font(.system(size: Theme.FontSize.title, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L.string(descriptionKey))
                    .font(.system(size: Theme.FontSize.small))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            extra
        }
        .padding(Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ProjectsEmptyState: View {
    var body: some View {
        ProjectsPlaceholder(systemImage: "folder",
                            titleKey: "settings.projects.empty.title",
                            descriptionKey: "settings.projects.empty.description") {
            EmptyView()
        }
    }
}

private struct ProjectsErrorState: View {
    var body: some View {
        ProjectsPlaceholder(systemImage: "exclamationmark.triangle",
                            titleKey: "settings.projects.error.title",
                            descriptionKey: "settings.projects.error.description") {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.defaultURL])
            } label: {
                Text(L.string("settings.projects.error.showInFinder"))
                    .font(.system(size: Theme.FontSize.small, weight: .semibold))
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .background(Theme.hover)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        }
    }
}
