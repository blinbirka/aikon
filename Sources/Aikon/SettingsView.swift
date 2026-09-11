import SwiftUI
import AppKit

/// `path` is already the unique key `ConfigStore` uses to find a project,
/// so it doubles as the `Identifiable` id the `Table` below needs.
extension ProjectConfig: Identifiable {
    public var id: String { path }
}

/// The app's marketing version, read from the bundled Info.plist. Falls
/// back to the value `scripts/bundle.sh` stamps in, since a plain `swift
/// build`/`swift run` (no bundling step) has no Info.plist to read from.
enum AppVersion {
    static var current: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
}

// MARK: - Sections

/// The window opened from the menu bar's "Settings…" item (⌘,) — see
/// `SettingsWindowCoordinator` for why AppKit owns it, not a `Settings` scene.
/// A hand-built sidebar (not `List`) switches between three sections; the
/// system's list-selection tint can't be recolored away from the user's
/// system accent color, and the approved design calls for a neutral
/// "lighter surface" selection instead.
enum SettingsSection: String, CaseIterable, Identifiable {
    case projects, settings, about
    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .projects: return "settings.nav.projects"
        case .settings: return "settings.nav.settings"
        case .about: return "settings.nav.about"
        }
    }

    var systemImage: String {
        switch self {
        case .projects: return "folder"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var configStore: ConfigStore
    @State private var section: SettingsSection = .settings

    var body: some View {
        // Rebuild the whole window when the language changes. `L` is a plain
        // static, so SwiftUI has no idea it moved: the parts that happen to
        // observe `configStore` (the settings rows) would redraw in the new
        // language while the sidebar and the About page — which don't — kept
        // the old one. Half-translated window, exactly what was reported.
        content.id(configStore.config.language)
    }

    private var content: some View {
        HStack(spacing: 0) {
            Sidebar(section: $section)

            Group {
                switch section {
                case .projects:
                    // Built and styled by a different task — this is just
                    // the existing tab, wired into the new shell.
                    ProjectsSettingsTab(configStore: configStore)
                case .settings:
                    ScrollView {
                        SettingsSectionView(configStore: configStore)
                            .padding(Theme.Spacing.xl)
                    }
                case .about:
                    ScrollView {
                        AboutSectionView(configStore: configStore, goToSettings: { section = .settings })
                            .padding(Theme.Spacing.xl)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.contentBackground)
        }
        .frame(width: 700, height: 520)
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @Binding var section: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            mark
            ForEach(SettingsSection.allCases) { item in
                SidebarButton(section: item, isSelected: section == item) {
                    section = item
                }
            }
            Spacer(minLength: 0)
            Text(AppVersion.current)
                .font(.system(size: Theme.FontSize.caption))
                .foregroundStyle(Theme.textFaint)
                .monospacedDigit()
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.sm)
        }
        .padding(Theme.Spacing.sm)
        .frame(width: 176)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.sidebarBackground)
    }

    private var mark: some View {
        HStack(spacing: Theme.Spacing.sm) {
            BrandMark(size: 28, cornerRadius: Theme.Radius.md, markSize: 12)
            VStack(alignment: .leading, spacing: 0) {
                Text(L.string("settings.brand.name"))
                    .font(.system(size: Theme.FontSize.body, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L.string("settings.nav.tagline"))
                    .font(.system(size: Theme.FontSize.caption))
                    .foregroundStyle(Theme.textFaint)
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.top, Theme.Spacing.sm)
        .padding(.bottom, Theme.Spacing.lg)
    }
}

private struct SidebarButton: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 16))
                    .frame(width: 16, height: 16)
                    .opacity(isSelected ? 1 : 0.8)
                Text(L.string(section.titleKey))
                    .font(.system(size: Theme.FontSize.body, weight: isSelected ? .medium : .regular))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(height: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? Theme.textPrimary : Theme.textDim)
        .background(isSelected ? Theme.cardBackground : (hovering ? Theme.hover : Color.clear))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
        .onHover { hovering = $0 }
    }
}

// MARK: - Shared building blocks (group header, card, divider, chips, buttons)

private struct GroupHeader: View {
    let titleKey: String
    var body: some View {
        Text(L.string(titleKey))
            .font(.system(size: Theme.FontSize.caption))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(Theme.textFaint)
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing: 0) { content }
            .background(Theme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }
}

private struct CardDivider: View {
    var body: some View {
        Rectangle().fill(Theme.line).frame(height: 1)
    }
}

private struct Chip: View {
    let text: String
    let muted: Bool
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(muted ? Theme.textFaint : Theme.accent).frame(width: 5, height: 5)
            Text(text).font(.system(size: 11))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .foregroundStyle(Theme.textDim)
        .background(Theme.sunk)
        .clipShape(Capsule())
    }
}

private struct StatusChip: View {
    let installed: Bool
    var body: some View {
        Chip(text: installed ? L.string("settings.hook.status.installed")
                              : L.string("settings.hook.status.notInstalled"),
             muted: !installed)
    }
}

private struct PillButton: View {
    let title: String
    var accent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: Theme.FontSize.small, weight: accent ? .semibold : .regular))
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.xs + 2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(accent ? Theme.textOnAccent : Theme.textPrimary)
        .background(accent ? Theme.accent : Theme.hover)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm, style: .continuous))
    }
}

/// Takes its icon as a view builder rather than a fixed symbol name so both
/// SF Symbol stand-ins (site, email) and the drawn brand marks (GitHub,
/// LinkedIn — see `SVGGlyph`) can share the same button chrome.
private struct SocialButton<Icon: View>: View {
    let labelKey: String
    let url: URL
    @ViewBuilder let icon: () -> Icon

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            icon()
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.textDim)
        .background(Theme.hover)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .help(L.string(labelKey))
    }
}

// MARK: - "Settings" section (sidebar: settings.nav.settings)

struct SettingsSectionView: View {
    @ObservedObject var configStore: ConfigStore

    @State private var launchAtLoginEnabled = LoginItem.isEnabled
    @State private var launchAtLoginError: String?

    @State private var hookState = HookInstaller.state()
    @State private var hookError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            generalGroup
            statusesGroup
            filesGroup
        }
    }

    // MARK: General

    private var generalGroup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            GroupHeader(titleKey: "settings.group.general")
            Card {
                languageRow
                CardDivider()
                launchAtLoginRow
                CardDivider()
                checkForUpdatesRow
            }
        }
    }

    private var languageRow: some View {
        HStack {
            Text(L.string("settings.general.language.title"))
                .font(.system(size: Theme.FontSize.body))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Picker(selection: languageBinding) {
                Text(L.string("settings.general.language.system")).tag(AppLanguage.system)
                Text(L.string("settings.general.language.en")).tag(AppLanguage.en)
                Text(L.string("settings.general.language.ru")).tag(AppLanguage.ru)
            } label: {
                Text(L.string("settings.general.language.title"))
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    private var languageBinding: Binding<AppLanguage> {
        Binding(
            get: { configStore.config.language },
            set: { configStore.setLanguage($0) }
        )
    }

    private var launchAtLoginRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                Text(L.string("settings.general.launchAtLogin"))
                    .font(.system(size: Theme.FontSize.body))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Toggle("", isOn: launchAtLoginBinding)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.system(size: Theme.FontSize.small))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginEnabled },
            set: { setLaunchAtLogin($0) }
        )
    }

    private var checkForUpdatesRow: some View {
        HStack {
            Text(L.string("settings.general.checkForUpdates"))
                .font(.system(size: Theme.FontSize.body))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Toggle("", isOn: checkForUpdatesBinding)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    private var checkForUpdatesBinding: Binding<Bool> {
        Binding(
            get: { configStore.config.checkForUpdates },
            set: { configStore.setCheckForUpdates($0) }
        )
    }

    private func setLaunchAtLogin(_ newValue: Bool) {
        do {
            if newValue {
                try LoginItem.enable()
            } else {
                try LoginItem.disable()
            }
            launchAtLoginEnabled = newValue
            launchAtLoginError = nil
            configStore.setLaunchAtLogin(newValue)
        } catch {
            // Leave `launchAtLoginEnabled` untouched so the toggle snaps
            // back to what's actually true on the system.
            launchAtLoginError = error.localizedDescription
        }
    }

    // MARK: Statuses

    private var statusesGroup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            GroupHeader(titleKey: "settings.group.statuses")
            Card { hookRow }
        }
    }

    private var hookRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(L.string("settings.hook.title"))
                        .font(.system(size: Theme.FontSize.body))
                        .foregroundStyle(Theme.textPrimary)
                    StatusChip(installed: hookState == .installed)
                }
                hookDescription
                    .font(.system(size: Theme.FontSize.small))
                    .foregroundStyle(Theme.textDim)
                    .frame(maxWidth: 420, alignment: .leading)
                if let hookUnavailableReason {
                    Text(L.format("settings.hook.status.unavailable", hookUnavailableReason))
                        .font(.system(size: Theme.FontSize.small))
                        .foregroundStyle(Theme.textDim)
                }
                if let hookError {
                    Text(hookError)
                        .font(.system(size: Theme.FontSize.small))
                        .foregroundStyle(Theme.textDim)
                }
            }
            Spacer(minLength: Theme.Spacing.lg)
            PillButton(title: hookButtonTitle, accent: hookState != .installed, action: toggleHook)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    /// Composed with `+` so the file path in the middle can carry its own
    /// monospaced font while the rest of the sentence stays regular —
    /// matches the approved mockup, where the path sits in `<code>`.
    private var hookDescription: Text {
        Text(L.string("settings.hook.description.prefix"))
        + Text("~/.claude/settings.json").font(.system(size: Theme.FontSize.small, design: .monospaced))
        + Text(L.string("settings.hook.description.suffix"))
    }

    private var hookUnavailableReason: String? {
        if case .unavailable(let reason) = hookState { return reason }
        return nil
    }

    private var hookButtonTitle: String {
        hookState == .installed ? L.string("settings.hook.remove") : L.string("settings.hook.install")
    }

    private func toggleHook() {
        hookError = nil
        do {
            if hookState == .installed {
                try HookInstaller.uninstall()
            } else {
                try HookInstaller.install()
            }
        } catch {
            hookError = error.localizedDescription
        }
        hookState = HookInstaller.state()
    }

    // MARK: Files

    private var filesGroup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            GroupHeader(titleKey: "settings.group.files")
            Card {
                configPathRow
                CardDivider()
                sessionsPathRow
            }
        }
    }

    private var configPathRow: some View {
        HStack {
            Text(L.string("settings.files.config.title"))
                .font(.system(size: Theme.FontSize.body))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(ConfigStore.defaultURL.path)
                .font(.system(size: Theme.FontSize.small, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: 200, alignment: .trailing)
            PillButton(title: L.string("settings.files.config.open")) {
                NSWorkspace.shared.activateFileViewerSelecting([ConfigStore.defaultURL])
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    private var sessionsPathRow: some View {
        HStack {
            Text(L.string("settings.files.sessions.title"))
                .font(.system(size: Theme.FontSize.body))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(configStore.config.sessionsPath)
                .font(.system(size: Theme.FontSize.small, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: 200, alignment: .trailing)
            PillButton(title: L.string("settings.files.sessions.change"), action: changeSessionsPath)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    private func changeSessionsPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        configStore.setSessionsPath(url.path)
    }
}

// MARK: - "About" section (sidebar: settings.nav.about)

struct AboutSectionView: View {
    @ObservedObject var configStore: ConfigStore
    /// Lets the "why don't statuses differ" answer jump straight to the
    /// Statuses group in Settings instead of just describing where it is.
    let goToSettings: () -> Void

    /// The version row's chip: `nil` while up to date, the version string
    /// once a check has found something newer than what's running.
    private var updateVersion: String? {
        UpdateChecker.availableUpdate(latestKnown: configStore.config.latestKnownVersion,
                                       current: AppVersion.current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            hero
            questionsGroup
            authorGroup
        }
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "aikon-settings" else { return .systemAction }
            goToSettings()
            return .handled
        })
    }

    private var hero: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            BrandMark(size: 56, cornerRadius: Theme.Radius.lg, markSize: 24)
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(L.string("settings.brand.name"))
                    .font(.system(size: Theme.FontSize.hero, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L.string("settings.about.tagline"))
                    .font(.system(size: Theme.FontSize.body))
                    .foregroundStyle(Theme.textDim)
                    .frame(maxWidth: 420, alignment: .leading)
                HStack(spacing: Theme.Spacing.xs) {
                    Chip(text: AppVersion.current, muted: false)
                    Chip(text: L.string("settings.about.license"), muted: true)
                    Chip(text: L.string("settings.about.macosRequirement"), muted: true)
                    if let updateVersion {
                        Chip(text: L.format("settings.about.update.available", updateVersion), muted: false)
                        PillButton(title: L.string("settings.about.update.openRelease")) {
                            NSWorkspace.shared.open(UpdateChecker.releasePageURL)
                        }
                    } else {
                        Chip(text: L.string("settings.about.update.upToDate"), muted: true)
                    }
                }
            }
        }
    }

    private var questionsGroup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            GroupHeader(titleKey: "settings.about.qa.title")
            Card {
                qa(questionKey: "settings.about.qa1.question", answer: Text(L.string("settings.about.qa1.answer")))
                CardDivider()
                qa(questionKey: "settings.about.qa2.question", answer: Text(L.string("settings.about.qa2.answer")))
                CardDivider()
                qa(questionKey: "settings.about.qa3.question", answer: Text(L.string("settings.about.qa3.answer")))
                CardDivider()
                qa(questionKey: "settings.about.qa4.question", answer: qa4Answer)
            }
        }
    }

    private func qa(questionKey: String, answer: Text) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(L.string(questionKey))
                .font(.system(size: Theme.FontSize.body, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            answer
                .font(.system(size: Theme.FontSize.small))
                .foregroundStyle(Theme.textDim)
                .frame(maxWidth: 460, alignment: .leading)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    /// The trailing clause is a real tappable link (via `AttributedString`,
    /// intercepted through `openURL` above) rather than a separate button,
    /// so the sentence wraps as one paragraph instead of breaking into two
    /// disjointed pieces.
    private var qa4Answer: Text {
        var attributed = AttributedString(L.string("settings.about.qa4.prefix"))
        var link = AttributedString(L.string("settings.about.qa4.link"))
        link.link = URL(string: "aikon-settings:///statuses")
        link.foregroundColor = Theme.accent
        link.underlineStyle = .single
        attributed += link
        attributed += AttributedString(L.string("settings.about.qa4.suffix"))
        return Text(attributed)
    }

    private var authorGroup: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            GroupHeader(titleKey: "settings.group.author")
            Card {
                authorRow
                CardDivider()
                openSourceRow
            }
        }
    }

    private var authorRow: some View {
        HStack(spacing: Theme.Spacing.lg) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L.string("settings.about.author.name"))
                    .font(.system(size: Theme.FontSize.title, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(L.string("settings.about.author.role"))
                    .font(.system(size: Theme.FontSize.small))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            HStack(spacing: Theme.Spacing.xs) {
                SocialButton(labelKey: "settings.about.author.github",
                             url: URL(string: "https://github.com/blinbirka")!) {
                    SVGGlyph(pathData: BrandGlyphPaths.github)
                        .fill(Theme.textDim)
                        .frame(width: 16, height: 16)
                }
                SocialButton(labelKey: "settings.about.author.website",
                             url: URL(string: "https://adorogova.com")!) {
                    Image(systemName: "globe").font(.system(size: 14))
                }
                SocialButton(labelKey: "settings.about.author.linkedin",
                             url: URL(string: "https://www.linkedin.com/in/annadorogova/")!) {
                    SVGGlyph(pathData: BrandGlyphPaths.linkedIn)
                        .fill(Theme.textDim)
                        .frame(width: 16, height: 16)
                }
                SocialButton(labelKey: "settings.about.author.email",
                             url: URL(string: "mailto:dorogova.ann@gmail.com")!) {
                    Image(systemName: "envelope").font(.system(size: 14))
                }
            }
        }
        .padding(Theme.Spacing.lg)
    }

    private var openSourceRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(L.string("settings.about.opensource.title"))
                    .font(.system(size: Theme.FontSize.body))
                    .foregroundStyle(Theme.textPrimary)
                Text(L.string("settings.about.opensource.description"))
                    .font(.system(size: Theme.FontSize.small))
                    .foregroundStyle(Theme.textDim)
            }
            Spacer()
            PillButton(title: L.string("settings.about.opensource.repo")) {
                NSWorkspace.shared.open(URL(string: "https://github.com/blinbirka/aikon")!)
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }
}

// MARK: - "Projects" section (sidebar: settings.nav.projects)
// Built out in `ProjectsTab.swift` — see `ProjectsSettingsTab` there.
