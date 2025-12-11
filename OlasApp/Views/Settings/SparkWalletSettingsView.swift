import SwiftUI

public struct SparkWalletSettingsView: View {
    var walletManager: SparkWalletManager

    @State private var showCreateWallet = false
    @State private var showImportWallet = false
    @State private var showDisconnectAlert = false
    @State private var showLightningAddressSetup = false
    @State private var showBackupWallet = false

    public init(walletManager: SparkWalletManager) {
        self.walletManager = walletManager
    }

    public var body: some View {
        List {
            statusSection

            if walletManager.connectionStatus == .connected {
                balanceSection
                currencySection
                addressSection
                actionsSection
            } else {
                setupSection
            }

            if let error = walletManager.error {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("Spark Wallet")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showCreateWallet) {
            CreateSparkWalletView(walletManager: walletManager)
        }
        .sheet(isPresented: $showImportWallet) {
            ImportSparkWalletView(walletManager: walletManager)
        }
        .sheet(isPresented: $showLightningAddressSetup) {
            LightningAddressSetupView(walletManager: walletManager)
        }
        .sheet(isPresented: $showBackupWallet) {
            BackupWalletView(walletManager: walletManager)
        }
        .alert("Disconnect Wallet", isPresented: $showDisconnectAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Disconnect", role: .destructive) {
                Task { await walletManager.disconnect(clearMnemonic: true) }
            }
        } message: {
            Text("This will disconnect your Spark wallet. You can reconnect later using your mnemonic.")
        }
    }

    // MARK: - Sections

    private var statusSection: some View {
        Section {
            HStack {
                Image(systemName: walletManager.connectionStatus.icon)
                    .foregroundStyle(walletManager.connectionStatus.color)
                Text(walletManager.connectionStatus.description)
                Spacer()
                if walletManager.isLoading {
                    ProgressView()
                }
            }
        } header: {
            Text("Connection Status")
        }
    }

    private var balanceSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Balance")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(formatSats(walletManager.balance))
                    .font(.title.bold())
                if let fiatAmount = walletManager.formatFiat(walletManager.balance) {
                    Text(fiatAmount)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var currencySection: some View {
        Section {
            Picker("Preferred Currency", selection: Bindable(walletManager).preferredCurrency) {
                ForEach(availableCurrencies, id: \.self) { currency in
                    Text(currency).tag(currency)
                }
            }
        } header: {
            Text("Display Settings")
        } footer: {
            Text("Choose the currency for displaying fiat equivalents")
        }
    }

    private var availableCurrencies: [String] {
        if walletManager.fiatRates.isEmpty {
            return ["USD"]
        }
        return walletManager.fiatRates.map { $0.coin }.sorted()
    }

    private var addressSection: some View {
        Section {
            if let address = walletManager.lightningAddress {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lightning Address")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(address)
                            .font(.body.monospaced())
                        Spacer()
                        Button {
                            #if os(iOS)
                            UIPasteboard.general.string = address
                            #endif
                        } label: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                }
            } else {
                Button("Setup Lightning Address") {
                    showLightningAddressSetup = true
                }
            }
        } header: {
            Text("Receiving")
        }
    }

    private var actionsSection: some View {
        Section {
            Button {
                Task { await walletManager.sync() }
            } label: {
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sync Wallet")
                }
            }

            Button {
                showBackupWallet = true
            } label: {
                HStack {
                    Image(systemName: "key.fill")
                    Text("Show Recovery Phrase")
                }
            }

            Button(role: .destructive) {
                showDisconnectAlert = true
            } label: {
                HStack {
                    Image(systemName: "xmark.circle")
                    Text("Disconnect Wallet")
                }
            }
        }
    }

    private var setupSection: some View {
        Section {
            Button {
                showCreateWallet = true
            } label: {
                HStack {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(OlasTheme.Colors.accent)
                    Text("Create New Wallet")
                }
            }

            Button {
                showImportWallet = true
            } label: {
                HStack {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.blue)
                    Text("Import Existing Wallet")
                }
            }
        } header: {
            Text("Get Started")
        } footer: {
            Text("Spark is a self-custodial Bitcoin wallet. Your keys, your coins. You'll need your mnemonic phrase to recover your wallet.")
        }
    }

    // MARK: - Helpers

    private func formatSats(_ amount: UInt64) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let formatted = formatter.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "\(formatted) sats"
    }
}

// MARK: - Create Wallet View

struct CreateSparkWalletView: View {
    var walletManager: SparkWalletManager

    @Environment(\.dismiss) private var dismiss
    @State private var isCreating = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    createPrompt
                }
                .padding()
            }
            .navigationTitle("Create Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var createPrompt: some View {
        VStack(spacing: 20) {
            Image(systemName: "key.fill")
                .font(.system(size: 60))
                .foregroundStyle(OlasTheme.Colors.accent)

            Text("Create Your Wallet")
                .font(.title2.bold())

            Text("Your wallet will be created and ready to use immediately. You can backup your recovery phrase anytime from wallet settings.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let error = error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await createWallet() }
            } label: {
                HStack {
                    if isCreating {
                        ProgressView()
                            .tint(Color(.systemBackground))
                    }
                    Text("Create Wallet")
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(OlasTheme.Colors.accent)
                .foregroundStyle(Color(.systemBackground))
                .cornerRadius(12)
            }
            .disabled(isCreating)
        }
    }

    private func createWallet() async {
        isCreating = true
        defer { isCreating = false }

        do {
            _ = try await walletManager.createWallet()
            // Wallet is created and saved to keychain - dismiss to return to main wallet view
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Import Wallet View

struct ImportSparkWalletView: View {
    var walletManager: SparkWalletManager

    @Environment(\.dismiss) private var dismiss
    @State private var mnemonic = ""
    @State private var isImporting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.blue)

                Text("Import Wallet")
                    .font(.title2.bold())

                Text("Enter your 12 or 24-word recovery phrase to restore your wallet.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextEditor(text: $mnemonic)
                    .font(.body.monospaced())
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    #endif

                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await importWallet() }
                } label: {
                    HStack {
                        if isImporting {
                            ProgressView()
                                .tint(Color(.systemBackground))
                        }
                        Text("Import Wallet")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValidMnemonic ? .blue : Color(.systemGray))
                    .foregroundStyle(Color(.systemBackground))
                    .cornerRadius(12)
                }
                .disabled(!isValidMnemonic || isImporting)

                Spacer()
            }
            .padding()
            .navigationTitle("Import Wallet")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var isValidMnemonic: Bool {
        let words = mnemonic.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: " ")
        return words.count == 12 || words.count == 24
    }

    private func importWallet() async {
        isImporting = true
        defer { isImporting = false }

        let cleanedMnemonic = mnemonic.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        do {
            try await walletManager.importWallet(mnemonic: cleanedMnemonic)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Lightning Address Setup View

struct LightningAddressSetupView: View {
    var walletManager: SparkWalletManager

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var isRegistering = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(OlasTheme.Colors.zapGold)

                Text("Setup Lightning Address")
                    .font(.title2.bold())

                Text("Choose a username for your Lightning address. After registration, you'll receive a full Lightning address for receiving payments.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Username")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextField("username", text: $username)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        #if os(iOS)
                        .textInputAutocapitalization(.never)
                        #endif
                }
                .padding(.horizontal)

                if let error = error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Button {
                    Task { await registerAddress() }
                } label: {
                    HStack {
                        if isRegistering {
                            ProgressView()
                                .tint(Color(.systemBackground))
                        }
                        Text("Register Address")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(isValidUsername ? OlasTheme.Colors.zapGold : Color(.systemGray))
                    .foregroundStyle(Color(.systemBackground))
                    .cornerRadius(12)
                }
                .disabled(!isValidUsername || isRegistering)

                Spacer()
            }
            .padding()
            .navigationTitle("Lightning Address")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var isValidUsername: Bool {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= 3 && trimmed.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    private func registerAddress() async {
        isRegistering = true
        defer { isRegistering = false }

        let cleanedUsername = username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        do {
            try await walletManager.registerLightningAddress(cleanedUsername)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Backup Wallet View

struct BackupWalletView: View {
    var walletManager: SparkWalletManager
    @Environment(\.dismiss) private var dismiss
    @State private var mnemonic: String?
    @State private var isRevealed = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                if !isRevealed {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 60))
                        .foregroundStyle(OlasTheme.Colors.accent)

                    Text("Show Recovery Phrase")
                        .font(.title2.bold())

                    Text("Your recovery phrase gives full access to your wallet and funds. Never share it with anyone. View it only in a private, secure location.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Spacer()

                    Button {
                        revealMnemonic()
                    } label: {
                        HStack {
                            Image(systemName: "eye.fill")
                            Text("Reveal Phrase")
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(OlasTheme.Colors.accent)
                        .foregroundStyle(Color(.systemBackground))
                        .cornerRadius(12)
                    }
                    .padding(.horizontal)
                } else if let mnemonic = mnemonic {
                    mnemonicDisplay(mnemonic)
                }
            }
            .padding()
            .navigationTitle("Backup Wallet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func revealMnemonic() {
        if let key = walletManager.retrieveMnemonic() {
            self.mnemonic = key
            withAnimation {
                isRevealed = true
            }
            // Mark wallet as backed up when user views the recovery phrase
            UserDefaults.standard.set(true, forKey: "hasBackedUpSparkWallet")
        }
    }

    private func mnemonicDisplay(_ mnemonic: String) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "shield.checkered")
                    .font(.system(size: 60))
                    .foregroundStyle(OlasTheme.Colors.zapGold)

                Text("Your Recovery Phrase")
                    .font(.title2.bold())

                Text("Write these words down in order. Store them safely.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    let words = mnemonic.split(separator: " ")
                    ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                        HStack {
                            Text("\(index + 1).")
                                .foregroundStyle(.secondary)
                                .frame(width: 24, alignment: .trailing)
                            Text(String(word))
                                .font(.body.monospaced())
                            Spacer()
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray6))
                        .cornerRadius(6)
                    }
                }
                .padding()

                Button {
                    #if os(iOS)
                    UIPasteboard.general.string = mnemonic
                    #endif
                } label: {
                    HStack {
                        Image(systemName: "doc.on.doc")
                        Text("Copy to Clipboard")
                    }
                    .font(.subheadline)
                }
                .padding(.bottom)

                Text("Warning: Copying your phrase to the clipboard can be risky if you have malicious apps installed.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }
}
