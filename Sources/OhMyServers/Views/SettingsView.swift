import AppKit
import SwiftUI
import OhMyServersCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var launchAtLoginEnabled = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?
    @State private var newName = ""
    @State private var newURL = ""
    @State private var addError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    sectionTitle(L10n.komariSites)

                    if model.sites.isEmpty {
                        Text(L10n.noSites)
                            .font(.system(size: 12))
                            .foregroundStyle(Graphite.muted)
                            .padding(.vertical, 4)
                    } else {
                        ForEach(model.sites) { site in
                            SiteRowView(site: site)
                        }
                    }

                    addSiteForm

                    menuBarSection
                        .padding(.top, 8)
                }
                .padding(16)
            }

            Rectangle()
                .fill(Graphite.divider)
                .frame(height: 1)

            monitorSection
                .padding(16)
        }
        .background(Graphite.bg)
        .preferredColorScheme(.dark)
    }

    // MARK: - Add site

    private var addSiteForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField(L10n.nameOptional, text: $newName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Graphite.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Graphite.field)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(width: 140)

                TextField(L10n.siteURLHint, text: $newURL)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Graphite.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Graphite.field)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .onSubmit(addSite)

                Button(action: addSite) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Graphite.bg)
                        .frame(width: 34, height: 34)
                        .background(canAdd ? Graphite.accent : Graphite.muted.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }

            if let addError {
                Text(addError)
                    .font(.system(size: 11))
                    .foregroundStyle(Graphite.offline)
            }
        }
    }

    private var canAdd: Bool {
        !newURL.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func addSite() {
        addError = nil
        do {
            try model.addSite(name: newName, urlString: newURL)
            newName = ""
            newURL = ""
        } catch {
            addError = L10n.invalidURL
        }
    }

    // MARK: - Menu bar display section

    private var menuBarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(L10n.menuBarDisplay)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 4),
                spacing: 8
            ) {
                ForEach(MenuBarMetric.allCases) { metric in
                    Toggle(isOn: metricBinding(metric)) {
                        Text(L10n.menuBarMetricName(metric))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Graphite.text)
                    }
                    .toggleStyle(.switch)
                    .tint(Graphite.accent)
                    .controlSize(.small)
                }
            }

            if model.nodeStatuses.isEmpty {
                Text(L10n.menuBarNoNodes)
                    .font(.system(size: 12))
                    .foregroundStyle(Graphite.muted)
            } else {
                Toggle(isOn: allServersBinding) {
                    Text(L10n.allServers)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Graphite.text)
                }
                .toggleStyle(.switch)
                .tint(Graphite.accent)
                .controlSize(.small)

                if model.menuBarSettings.selectedNodeUUIDs != nil {
                    ForEach(model.nodeStatuses) { node in
                        Toggle(isOn: nodeBinding(node.info.uuid)) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(node.isOnline ? Graphite.online : Graphite.offline)
                                    .frame(width: 6, height: 6)
                                Text(node.info.name)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Graphite.text)
                            }
                        }
                        .toggleStyle(.switch)
                        .tint(Graphite.accent)
                        .controlSize(.small)
                        .padding(.leading, 12)
                    }
                }
            }

            HStack(spacing: 6) {
                Text(L10n.preview)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Graphite.muted)
                Text(model.menuBarTitle)
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Graphite.text)
                    .textSelection(.enabled)
            }
            .padding(.top, 2)
        }
    }

    private func metricBinding(_ metric: MenuBarMetric) -> Binding<Bool> {
        Binding(
            get: { model.menuBarSettings.metrics.contains(metric) },
            set: { on in
                var settings = model.menuBarSettings
                if on {
                    settings.metrics.append(metric)
                } else {
                    settings.metrics.removeAll { $0 == metric }
                }
                model.updateMenuBarSettings(settings)
            }
        )
    }

    private var allServersBinding: Binding<Bool> {
        Binding(
            get: { model.menuBarSettings.selectedNodeUUIDs == nil },
            set: { showAll in
                var settings = model.menuBarSettings
                // Switching off "all" starts from every current node so the
                // user can then uncheck individual ones.
                settings.selectedNodeUUIDs = showAll ? nil : Set(model.nodeStatuses.map(\.info.uuid))
                model.updateMenuBarSettings(settings)
            }
        )
    }

    private func nodeBinding(_ uuid: String) -> Binding<Bool> {
        Binding(
            get: {
                guard let selected = model.menuBarSettings.selectedNodeUUIDs else { return true }
                return selected.contains(uuid)
            },
            set: { on in
                var settings = model.menuBarSettings
                var selected = settings.selectedNodeUUIDs ?? Set(model.nodeStatuses.map(\.info.uuid))
                if on {
                    selected.insert(uuid)
                } else {
                    selected.remove(uuid)
                }
                settings.selectedNodeUUIDs = selected
                model.updateMenuBarSettings(settings)
            }
        )
    }

    // MARK: - Monitor section

    private var monitorSection: some View {
        HStack(alignment: .center, spacing: 20) {
            HStack(spacing: 8) {
                Text(L10n.pollInterval)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Graphite.muted)
                Picker(L10n.pollInterval, selection: Binding(
                    get: { model.pollIntervalSeconds },
                    set: { model.updatePollInterval($0) }
                )) {
                    ForEach(AppModel.allowedPollIntervals, id: \.self) { seconds in
                        Text(L10n.pollIntervalOption(Int(seconds))).tag(seconds)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .tint(Graphite.text)
                .fixedSize()
            }

            Toggle(isOn: Binding(
                get: { launchAtLoginEnabled },
                set: { applyLaunchAtLogin($0) }
            )) {
                Text(L10n.launchAtLogin)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Graphite.text)
            }
            .toggleStyle(.switch)
            .tint(Graphite.accent)
            .controlSize(.small)

            Spacer(minLength: 0)
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.setEnabled(enabled)
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
            launchAtLoginError = enabled && !launchAtLoginEnabled ? L10n.launchAtLoginFailed : nil
        } catch {
            launchAtLoginEnabled = LaunchAtLogin.isEnabled
            launchAtLoginError = L10n.launchAtLoginFailed
        }
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Graphite.muted)
            .textCase(.uppercase)
            .tracking(0.6)
    }
}

/// One editable site row. Edits save when a field loses focus or Return is pressed;
/// invalid URLs show an inline error and are not persisted.
private struct SiteRowView: View {
    @EnvironmentObject private var model: AppModel
    let site: KomariSite

    @State private var nameDraft: String
    @State private var urlDraft: String
    @State private var error: String?
    @FocusState private var focusedField: Field?

    private enum Field { case name, url }

    init(site: KomariSite) {
        self.site = site
        _nameDraft = State(initialValue: site.name)
        _urlDraft = State(initialValue: site.urlString)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField(L10n.nameOptional, text: $nameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Graphite.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Graphite.field)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .frame(width: 140)
                    .focused($focusedField, equals: .name)
                    .onSubmit(save)

                TextField(L10n.siteURLHint, text: $urlDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Graphite.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Graphite.field)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .focused($focusedField, equals: .url)
                    .onSubmit(save)

                Toggle(isOn: Binding(
                    get: { site.isEnabled },
                    set: { enabled in
                        var updated = site
                        updated.isEnabled = enabled
                        try? model.updateSite(updated)
                    }
                )) {
                    EmptyView()
                }
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Graphite.accent)
                .controlSize(.small)

                Button {
                    model.deleteSite(id: site.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(Graphite.offline)
                }
                .buttonStyle(.plain)
            }

            if let error {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundStyle(Graphite.offline)
            }
        }
        .onChange(of: focusedField) { _, newValue in
            // Save when the user tabs/clicks away from a field.
            if newValue == nil { save() }
        }
        .onChange(of: site) { _, newSite in
            // External change (e.g. reload) — refresh drafts if the user isn't editing.
            guard focusedField == nil else { return }
            nameDraft = newSite.name
            urlDraft = newSite.urlString
        }
    }

    private func save() {
        guard let normalized = AppModel.normalizedURLString(urlDraft) else {
            error = L10n.invalidURL
            return
        }
        error = nil
        var updated = site
        updated.name = nameDraft.trimmingCharacters(in: .whitespaces)
        updated.urlString = normalized
        guard updated != site else { return }
        try? model.updateSite(updated)
    }
}
