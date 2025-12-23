import SwiftUI

struct TelemetrySettingsView: View {
    @State private var telemetry = TelemetryService.shared
    @State private var testResult: (success: Bool, message: String)?
    @State private var isTesting = false

    var body: some View {
        Form {
            Section {
                Toggle("Enable Telemetry", isOn: $telemetry.isEnabled)

                Toggle("Console Logging", isOn: $telemetry.consoleLoggingEnabled)
                    .foregroundStyle(telemetry.consoleLoggingEnabled ? .primary : .secondary)
            } header: {
                Text("Logging")
            } footer: {
                Text("Console logging outputs to Xcode/Console.app. Telemetry sends logs to your configured endpoint.")
            }

            Section {
                TextField("https://your-server.com/logs", text: $telemetry.endpoint)
                    .textContentType(.URL)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()

                Picker("Minimum Level", selection: $telemetry.minimumLevel) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Text(level.rawValue).tag(level)
                    }
                }

                Button {
                    testConnection()
                } label: {
                    HStack {
                        Text("Test Connection")
                        Spacer()
                        if isTesting {
                            ProgressView()
                                .controlSize(.small)
                        } else if let result = testResult {
                            Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(result.success ? .green : .red)
                        }
                    }
                }
                .disabled(telemetry.endpoint.isEmpty || isTesting)
            } header: {
                Text("Remote Endpoint")
            } footer: {
                if let result = testResult {
                    Text(result.message)
                        .foregroundStyle(result.success ? .green : .red)
                } else {
                    Text("Logs are sent as JSON POST requests with an array of log entries.")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Expected Format")
                        .font(.headline)

                    Text(sampleJSON)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .padding(.vertical, 8)
            } header: {
                Text("API Documentation")
            }

            Section {
                Button("Send Test Log") {
                    sendTestLog()
                }
                .disabled(!telemetry.isEnabled || telemetry.endpoint.isEmpty)

                Button("Flush Log Queue") {
                    telemetry.flush()
                }
                .disabled(!telemetry.isEnabled || telemetry.endpoint.isEmpty)
            } header: {
                Text("Actions")
            }
        }
        .navigationTitle("Telemetry")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var sampleJSON: String {
        """
        [
          {
            "timestamp": "2025-01-01T12:00:00Z",
            "level": "INFO",
            "category": "Wallet",
            "message": "Payment sent",
            "metadata": {
              "amount": "1000",
              "destination": "lnbc..."
            }
          }
        ]
        """
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        Task {
            let result = await telemetry.testConnection()
            await MainActor.run {
                testResult = result
                isTesting = false
            }
        }
    }

    private func sendTestLog() {
        Log.info("Test log from settings", category: "Telemetry", metadata: ["source": "TelemetrySettingsView"])
        telemetry.flush()
    }
}
