import AppKit
import SwiftUI
import OhMyServersCore

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ServerConfig(
        name: "",
        host: "",
        username: "",
        label: "",
        authMethod: .password
    )
    @State private var password = ""
    @State private var keyPassphrase = ""
    @State private var editingID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 220)
            Rectangle()
                .fill(Graphite.divider)
                .frame(width: 1)
            editorPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Graphite.bg)
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .foregroundStyle(Graphite.accent)
                Text(L10n.servers)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Graphite.text)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 18)
            .padding(.bottom, 12)

            if model.servers.isEmpty {
                Text(L10n.noServers)
                    .font(.system(size: 12))
                    .foregroundStyle(Graphite.muted)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(model.servers) { server in
                            Button {
                                editingID = server.id
                                draft = server
                                password = ""
                                keyPassphrase = ""
                                errorMessage = nil
                            } label: {
                                HStack(spacing: 10) {
                                    Circle()
                                        .fill(model.snapshots[server.id]?.health.color ?? Graphite.muted)
                                        .frame(width: 7, height: 7)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(server.name)
                                            .font(.system(size: 12, weight: .semibold))
                                            .foregroundStyle(Graphite.text)
                                            .lineLimit(1)
                                        Text(server.label)
                                            .font(.system(size: 10, weight: .medium).monospacedDigit())
                                            .foregroundStyle(Graphite.muted)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 9)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(editingID == server.id ? Graphite.field : Color.clear)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    addServer()
                } label: {
                    labelChip(L10n.add, systemImage: "plus")
                }
                .buttonStyle(.plain)

                Button {
                    deleteSelected()
                } label: {
                    labelChip(L10n.delete, systemImage: "trash", destructive: true)
                }
                .buttonStyle(.plain)
                .disabled(editingID == nil)
                .opacity(editingID == nil ? 0.4 : 1)
            }
            .padding(12)
        }
        .background(Graphite.bgElevated)
    }

    private var editorPane: some View {
        Group {
            if editingID == nil && draft.host.isEmpty && draft.name.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 28, weight: .light))
                        .foregroundStyle(Graphite.muted)
                    Text(L10n.selectServer)
                        .font(.system(size: 13))
                        .foregroundStyle(Graphite.muted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        sectionTitle(L10n.basic)
                        VStack(spacing: 12) {
                            field(L10n.name, text: $draft.name)
                            field(L10n.label, text: $draft.label, hint: "如 HK / US")
                            HStack(spacing: 12) {
                                field(L10n.host, text: $draft.host)
                                field(L10n.port, text: Binding(
                                    get: { String(draft.port) },
                                    set: { draft.port = UInt16($0) ?? 22 }
                                ))
                                .frame(width: 96)
                            }
                            field(L10n.username, text: $draft.username)
                            Toggle(isOn: $draft.isEnabled) {
                                Text(L10n.enabled)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Graphite.text)
                            }
                            .toggleStyle(.switch)
                            .tint(Graphite.accent)
                        }

                        sectionTitle(L10n.auth)
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 8) {
                                authTab(L10n.authPassword, method: .password)
                                authTab(L10n.authKey, method: .privateKey)
                            }

                            if draft.authMethod == .password {
                                secureField(L10n.password, text: $password)
                                Text(L10n.keepPassword)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Graphite.muted)
                            } else {
                                HStack(spacing: 8) {
                                    field(L10n.keyPath, text: Binding(
                                        get: { draft.privateKeyPath ?? "" },
                                        set: { draft.privateKeyPath = $0.isEmpty ? nil : $0 }
                                    ))
                                    Button(L10n.browse) { browseKey() }
                                        .buttonStyle(.plain)
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(Graphite.accent)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 10)
                                        .background(Graphite.field)
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                secureField(L10n.passphrase, text: $keyPassphrase)
                                Text(L10n.passphraseOptional)
                                    .font(.system(size: 11))
                                    .foregroundStyle(Graphite.muted)
                            }
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(Graphite.offline)
                        }

                        HStack {
                            Spacer()
                            Button(action: save) {
                                Text(L10n.save)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Graphite.bg)
                                    .padding(.horizontal, 22)
                                    .padding(.vertical, 10)
                                    .background(canSave ? Graphite.accent : Graphite.muted.opacity(0.35))
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .disabled(!canSave)
                            .keyboardShortcut(.defaultAction)
                        }
                    }
                    .padding(24)
                }
            }
        }
    }

    private var canSave: Bool {
        !draft.name.isEmpty && !draft.host.isEmpty && !draft.username.isEmpty && !draft.label.isEmpty
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Graphite.muted)
            .textCase(.uppercase)
            .tracking(0.6)
    }

    private func field(_ title: String, text: Binding<String>, hint: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Graphite.muted)
            TextField(hint ?? title, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Graphite.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Graphite.field)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func secureField(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Graphite.muted)
            SecureField(title, text: text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(Graphite.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Graphite.field)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func authTab(_ title: String, method: AuthMethod) -> some View {
        let selected = draft.authMethod == method
        return Button {
            draft.authMethod = method
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? Graphite.text : Graphite.muted)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(selected ? Graphite.field : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Graphite.divider, lineWidth: selected ? 0 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private func labelChip(_ title: String, systemImage: String, destructive: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(destructive ? Graphite.offline : Graphite.text)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Graphite.field)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func addServer() {
        let fresh = ServerConfig(
            name: "新服务器",
            host: "",
            username: "root",
            label: "NEW",
            authMethod: .privateKey
        )
        draft = fresh
        editingID = fresh.id
        password = ""
        keyPassphrase = ""
        errorMessage = nil
    }

    private func deleteSelected() {
        guard let id = editingID else { return }
        try? model.delete(serverID: id)
        editingID = nil
        draft = ServerConfig(name: "", host: "", username: "", label: "", authMethod: .password)
        password = ""
        keyPassphrase = ""
    }

    private func browseKey() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.begin { response in
            if response == .OK, let url = panel.url {
                draft.privateKeyPath = url.path
            }
        }
    }

    private func save() {
        errorMessage = nil
        guard canSave else {
            errorMessage = L10n.requiredFields
            return
        }
        if draft.authMethod == .password, password.isEmpty {
            let exists = model.servers.contains(where: { $0.id == draft.id })
            let hasStored = (try? CredentialStore().load(serverID: draft.id, kind: .password)) != nil
            if !exists && !hasStored {
                errorMessage = L10n.passwordRequired
                return
            }
        }
        if draft.authMethod == .privateKey, (draft.privateKeyPath ?? "").isEmpty {
            errorMessage = L10n.keyRequired
            return
        }
        do {
            try model.save(
                server: draft,
                password: password.isEmpty ? nil : password,
                keyPassphrase: keyPassphrase.isEmpty ? nil : keyPassphrase
            )
            editingID = draft.id
            password = ""
            keyPassphrase = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension ServerHealth {
    var color: Color {
        switch self {
        case .online: return Graphite.online
        case .high: return Graphite.high
        case .offline: return Graphite.offline
        }
    }
}
