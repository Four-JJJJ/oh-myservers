import SwiftUI
import OhMyServersCore
import AppKit

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
        HSplitView {
            serverList
                .frame(minWidth: 180, idealWidth: 200)
            editor
                .frame(minWidth: 300)
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var serverList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Servers")
                .font(.headline)
            List(selection: Binding(
                get: { editingID },
                set: { id in
                    editingID = id
                    if let id, let server = model.servers.first(where: { $0.id == id }) {
                        draft = server
                        password = ""
                        keyPassphrase = ""
                    }
                }
            )) {
                ForEach(model.servers) { server in
                    Text("\(server.label) · \(server.name)")
                        .tag(Optional(server.id))
                }
            }
            .listStyle(.sidebar)

            HStack {
                Button("Add") {
                    let fresh = ServerConfig(
                        name: "New Server",
                        host: "",
                        username: "",
                        label: "NEW",
                        authMethod: .password
                    )
                    draft = fresh
                    editingID = fresh.id
                    password = ""
                    keyPassphrase = ""
                }
                Button("Delete", role: .destructive) {
                    if let id = editingID {
                        try? model.delete(serverID: id)
                        editingID = nil
                        draft = ServerConfig(name: "", host: "", username: "", label: "", authMethod: .password)
                    }
                }
                .disabled(editingID == nil)
            }
        }
    }

    private var editor: some View {
        Form {
            Section("Server") {
                TextField("Name", text: $draft.name)
                TextField("Label (menu bar)", text: $draft.label)
                TextField("Host", text: $draft.host)
                TextField("Port", text: Binding(
                    get: { String(draft.port) },
                    set: { draft.port = UInt16($0) ?? 22 }
                ))
                TextField("Username", text: $draft.username)
                Toggle("Enabled", isOn: $draft.isEnabled)
            }
            Section("Authentication") {
                Picker("Method", selection: $draft.authMethod) {
                    Text("Password").tag(AuthMethod.password)
                    Text("Private Key").tag(AuthMethod.privateKey)
                }
                if draft.authMethod == .password {
                    SecureField("Password", text: $password)
                    Text("Leave blank when editing to keep existing password.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        TextField("Private key path", text: Binding(
                            get: { draft.privateKeyPath ?? "" },
                            set: { draft.privateKeyPath = $0.isEmpty ? nil : $0 }
                        ))
                        Button("Browse…") { browseKey() }
                    }
                    SecureField("Key passphrase (optional)", text: $keyPassphrase)
                }
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(draft.name.isEmpty || draft.host.isEmpty)
        }
        .padding(8)
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
        guard !draft.name.isEmpty, !draft.host.isEmpty, !draft.username.isEmpty, !draft.label.isEmpty else {
            errorMessage = "Name, label, host and username are required."
            return
        }
        if draft.authMethod == .password, password.isEmpty,
           (try? CredentialStore().load(serverID: draft.id, kind: .password)) == nil {
            // New server without password
            if model.servers.contains(where: { $0.id == draft.id }) == false {
                errorMessage = "Password is required for new servers."
                return
            }
        }
        if draft.authMethod == .privateKey, (draft.privateKeyPath ?? "").isEmpty {
            errorMessage = "Private key path is required."
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
