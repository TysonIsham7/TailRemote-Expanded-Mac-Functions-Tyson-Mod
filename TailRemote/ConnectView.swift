import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ConnectView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @EnvironmentObject private var session: VNCSession
    @AppStorage("remoteHost") private var host = ""
    @AppStorage("remoteUsername") private var username = ""
    @AppStorage("rememberPassword") private var rememberPassword = true
    @StateObject private var credentials: ConnectionCredentials
    @StateObject private var savedMacs: SavedMacs
    @State private var showsMacEditor = false
    @State private var showsMacChoices = false
    @State private var showsImporter = false
    @FocusState private var passwordFocused: Bool
    @State private var draftHost = ""
    @State private var draftName = ""
    @State private var draftUsername = ""
    @State private var importError: String?

    private let port: UInt16 = 5900

    private var usesPadLayout: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }

    init(passwordStore: any RemotePasswordStoring = KeychainPasswordStore(), defaults: UserDefaults = .standard) {
        let credentials = ConnectionCredentials(store: passwordStore)
        let host = defaults.string(forKey: "remoteHost") ?? ""
        let username = defaults.string(forKey: "remoteUsername") ?? ""
        let remember = (defaults.object(forKey: "rememberPassword") as? Bool) ?? true
        credentials.load(
            for: RemoteCredentialKey(hostname: host, port: 5900, username: username),
            rememberPassword: remember
        )
        _credentials = StateObject(wrappedValue: credentials)
        _savedMacs = StateObject(wrappedValue: SavedMacs(defaults: defaults))
    }

    var body: some View {
        ZStack {
            AppTheme.ink.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                header
                connectionCard
                controlsHint
            }
            .frame(maxWidth: usesPadLayout ? 640 : 540)
            .padding(.horizontal, 24)
            .padding(.vertical, usesPadLayout ? 48 : 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .onAppear {
            releasePasswordFocus()
            prepareMacs()
            // Returning from a session can restore focus and cover the form.
            DispatchQueue.main.async {
                releasePasswordFocus()
            }
        }
        .onChange(of: credentialKey) { _, _ in loadPassword() }
        .onChange(of: username) { _, value in
            savedMacs.remember(hostname: host, username: value)
        }
        .sheet(isPresented: $showsMacEditor) { macEditor }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.json]) { result in
            do {
                let url = try result.get()
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                try savedMacs.importMacs(handle.read(upToCount: 1_048_577) ?? Data())
                importError = nil
                restoreSelection()
            } catch {
                importError = "Couldn’t import that list. Choose a TailRemote Mac export."
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            TailSignalMark()

            Text("Your Mac,\nwithin reach.")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .tracking(-1.4)
                .foregroundStyle(AppTheme.text)

            Text("A direct Screen Sharing connection inside your private tailnet.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(AppTheme.muted)
        }
    }

    private var connectionCard: some View {
        VStack(spacing: 18) {
            HStack {
                Label("PRIVATE TAILNET", systemImage: "lock.fill")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(AppTheme.connected)
                Spacer()
                Text(":5900")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(AppTheme.muted)
            }

            VStack(spacing: 12) {
                fieldLabel("MAC")
                // Above the scrolling fields. A control inside the ScrollView has
                // no activation point, so a tap never opens the list.
                macPicker
            }

            ScrollView {
                credentialFields
            }
            .scrollDismissesKeyboard(.immediately)
            .frame(maxHeight: .infinity)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(AppTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        }
    }

    private var credentialFields: some View {
        VStack(spacing: 18) {
            VStack(spacing: 12) {
                fieldLabel("MAC USERNAME")
                TextField("Mac username", text: $username)
                    .accessibilityIdentifier("remote-username")
                    // An unset content type is inferred. "username" in the label
                    // makes iOS treat this as a login and offer to save the password.
                    .textContentType(.nickname)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .inputStyle()

                fieldLabel("PASSWORD")
                passwordField
            }

            if let importError {
                Text(importError)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.danger)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Remember password", isOn: Binding(
                    get: { rememberPassword },
                    set: setRememberPassword
                ))
                .accessibilityIdentifier("remember-password")
                .tint(AppTheme.tailBlue)
                .font(.subheadline)
                Text("Stored securely on this \(AppTheme.deviceName) after signing in. Turn off to forget it.")
                    .font(.caption)
                    .foregroundStyle(AppTheme.muted)
            }

            if let error = credentials.errorMessage ?? session.credentialStorageError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(AppTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let error = session.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(AppTheme.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: connect) {
                HStack {
                    Text("Connect to Mac")
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(.headline, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .frame(height: 54)
                .background(AppTheme.tailBlue)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .accessibilityIdentifier("connect-to-mac")
            .disabled(host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || credentials.password.isEmpty)
            .opacity(credentials.password.isEmpty ? 0.45 : 1)
        }
    }

    private var controlsHint: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.draw.fill")
                .foregroundStyle(AppTheme.tailBlue)
            Text("Hold, then drag to move sliders or windows.")
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(AppTheme.muted)
        }
    }

    private var macPicker: some View {
        VStack(spacing: 8) {
            Button {
                showsMacChoices.toggle()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "desktopcomputer")
                        .foregroundStyle(AppTheme.tailBlue)
                    Text(savedMacs.matching(host)?.name ?? "Choose a Mac")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: showsMacChoices ? "chevron.up" : "chevron.down")
                        .font(.caption)
                }
                .inputStyle()
                .contentShape(Rectangle())
            }
            // A system menu is a pop-up button. Inside the form's scroll view it
            // never activates, so the saved Macs are not reachable. These are
            // ordinary buttons with real hit targets.
            .buttonStyle(.plain)
            .accessibilityIdentifier("mac-picker")

            if showsMacChoices {
                VStack(spacing: 4) {
                    ForEach(savedMacs.macs) { mac in
                        macChoice(mac)
                    }
                    if !host.isEmpty {
                        macAction("Connection details", systemImage: "pencil") { editMac() }
                    }
                    macAction("Add a Mac", systemImage: "plus") { editMac(isNew: true) }
                    macAction("Import Tailscale Macs", systemImage: "square.and.arrow.down") { showsImporter = true }
                }
            }
        }
    }

    private func macChoice(_ mac: SavedMac) -> some View {
        Button {
            select(mac)
            showsMacChoices = false
        } label: {
            Label(mac.name, systemImage: savedMacs.matching(host)?.id == mac.id ? "checkmark" : "desktopcomputer")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(AppTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(AppTheme.ink.opacity(0.45))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("saved-mac-\(mac.id)")
    }

    private func macAction(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button {
            showsMacChoices = false
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(AppTheme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var macEditor: some View {
        NavigationStack {
            Form {
                Section("Mac") {
                    TextField("Name", text: $draftName)
                    TextField("Tailscale name or IP address", text: $draftHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("mac-address")
                    TextField("Mac username", text: $draftUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("In Tailscale, select your Mac and copy its address. Your username is the account you use to sign in to that Mac.")
                    Text("Import Tailscale Macs adds a saved device list exported from your Mac. It does not refresh automatically.")
                }
            }
            .navigationTitle("Mac details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showsMacEditor = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savedMacs.remember(hostname: draftHost, username: draftUsername, name: draftMac.name)
                        if let mac = savedMacs.matching(draftHost) { select(mac) }
                        showsMacEditor = false
                    }
                    .disabled(!SavedMacs.isValid(draftMac))
                }
            }
        }
    }

    private var draftMac: SavedMac {
        SavedMac(hostname: draftHost, name: draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? draftHost : draftName,
                 username: draftUsername)
    }

    private func editMac(isNew: Bool = false) {
        draftHost = isNew ? "" : host
        draftName = isNew ? "" : savedMacs.matching(host)?.name ?? host
        draftUsername = isNew ? "" : username
        showsMacEditor = true
    }

    private func select(_ mac: SavedMac) {
        credentials.password = ""
        // Keep a previously used alias as the credential key when selecting it.
        if !mac.addresses.contains(SavedMac.normalize(host)) { host = mac.hostname }
        username = mac.username
        loadPassword()
    }

    private func prepareMacs() {
        savedMacs.remember(hostname: host, username: username)
        if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            do {
                try savedMacs.importPendingFile(at: documents.appendingPathComponent("TailscaleMacs.json"))
            } catch {
                importError = "Couldn’t import the Mac list. You can try importing it again."
            }
        }
        restoreSelection()
    }

    private func restoreSelection() {
        if let current = savedMacs.matching(host) {
            select(current)
        } else if host.isEmpty, let first = savedMacs.macs.first {
            select(first)
        } else {
            loadPassword()
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .tracking(1.4)
            .foregroundStyle(AppTheme.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// UI tests launch with --test-credentials. Password AutoFill can take a secure
    /// field there and leave it without keyboard focus, so tests type into a plain
    /// field with the same identifier. Users always get the SecureField.
    private var suppressesPasswordAutofill: Bool {
        ProcessInfo.processInfo.arguments.contains("--test-credentials")
    }

    @ViewBuilder
    private var passwordField: some View {
        if suppressesPasswordAutofill {
            TextField("Mac login password", text: $credentials.password)
                .accessibilityIdentifier("remote-password")
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($passwordFocused)
                .submitLabel(.go)
                .inputStyle()
                .onSubmit {
                    releasePasswordFocus()
                    connect()
                }
        } else {
            SecureField("Mac login password", text: $credentials.password)
                .accessibilityIdentifier("remote-password")
                // Nil is inferred as a password, and iOS then covers the screen
                // with Save / Not Now. A one-time code is still masked entry,
                // and Remember password stores the login.
                .textContentType(.oneTimeCode)
                .submitLabel(.go)
                .focused($passwordFocused)
                .inputStyle()
                .onSubmit {
                    releasePasswordFocus()
                    connect()
                }
        }
    }

    private func releasePasswordFocus() {
        passwordFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private func connect() {
        releasePasswordFocus()
        let hostname = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let password = credentials.password
        let remember = rememberPassword
        let resolvedPort = port
        savedMacs.remember(hostname: hostname, username: account)
        let activeSession = session
        // Resign the password field before this view is removed. Otherwise the
        // keyboard stays up with no first responder and covers the session bar.
        DispatchQueue.main.async {
            activeSession.connect(
                hostname: hostname,
                port: resolvedPort,
                username: account,
                password: password,
                rememberPassword: remember
            )
        }
    }

    private var credentialKey: RemoteCredentialKey {
        RemoteCredentialKey(hostname: host, port: port, username: username)
    }

    private func loadPassword() {
        let returnedGracefully = session.takeGracefulClose()
        credentials.load(for: credentialKey, rememberPassword: rememberPassword)
        if returnedGracefully {
            credentials.clearPresentedError()
        }
    }

    private func setRememberPassword(_ enabled: Bool) {
        if !enabled {
            guard credentials.forget(for: credentialKey) else { return }
        }
        rememberPassword = enabled
        if enabled && credentials.password.isEmpty {
            loadPassword()
        }
    }
}

private struct TailSignalMark: View {
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { column in
                VStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { row in
                        Circle()
                            .fill(column == 2 && row == 0 ? AppTheme.connected : AppTheme.tailBlue.opacity(0.32 + Double(column + row) * 0.08))
                            .frame(width: 7, height: 7)
                    }
                }
            }
        }
        .padding(12)
        .background(AppTheme.panelRaised)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel("TailRemote")
    }
}

private extension View {
    func inputStyle() -> some View {
        self
            .foregroundStyle(AppTheme.text)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(AppTheme.ink.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(.white.opacity(0.07), lineWidth: 1)
            }
    }
}
