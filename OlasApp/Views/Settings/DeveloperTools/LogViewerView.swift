import NDKSwiftCore
import SwiftUI

struct LogViewerView: View {
    @State private var logs: [NDKLogEntry] = []
    @State private var isCapturing = false
    @State private var selectedLevel: NDKLogLevel? = nil
    @State private var selectedCategory: NDKLogCategory? = nil
    @State private var searchText = ""
    @State private var autoScroll = true

    private let maxLogEntries = 1000

    private var filteredLogs: [NDKLogEntry] {
        logs.filter { entry in
            let matchesLevel = selectedLevel == nil || entry.level == selectedLevel
            let matchesCategory = selectedCategory == nil || entry.category == selectedCategory
            let matchesSearch = searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText)
            return matchesLevel && matchesCategory && matchesSearch
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar

            if logs.isEmpty {
                emptyState
            } else {
                logList
            }

            toolbar
        }
        .navigationTitle("Logs")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            startCapturing()
        }
        .onDisappear {
            stopCapturing()
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Button("All Levels") { selectedLevel = nil }
                    Divider()
                    ForEach([NDKLogLevel.error, .warning, .info, .debug, .trace], id: \.self) { level in
                        Button(level.description) { selectedLevel = level }
                    }
                } label: {
                    Label(selectedLevel?.description ?? "Level", systemImage: "slider.horizontal.3")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedLevel != nil ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }

                Menu {
                    Button("All Categories") { selectedCategory = nil }
                    Divider()
                    ForEach(NDKLogCategory.allCases, id: \.self) { category in
                        Button(category.rawValue) { selectedCategory = category }
                    }
                } label: {
                    Label(selectedCategory?.rawValue ?? "Category", systemImage: "folder")
                        .font(.caption)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selectedCategory != nil ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.1))
                        .cornerRadius(8)
                }

                if selectedLevel != nil || selectedCategory != nil {
                    Button {
                        selectedLevel = nil
                        selectedCategory = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(Color(.systemBackground))
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(isCapturing ? "Waiting for Logs" : "Log Capture Paused", systemImage: "doc.plaintext")
        } description: {
            Text(isCapturing ? "Logs will appear here as they are generated" : "Tap Start to begin capturing logs")
        }
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(filteredLogs) { entry in
                    LogEntryRow(entry: entry)
                        .id(entry.id)
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                }
            }
            .listStyle(.plain)
            .onChange(of: logs.count) {
                if autoScroll, let last = filteredLogs.last {
                    withAnimation {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Button {
                isCapturing ? stopCapturing() : startCapturing()
            } label: {
                Label(isCapturing ? "Stop" : "Start", systemImage: isCapturing ? "stop.fill" : "play.fill")
            }
            .buttonStyle(.bordered)

            Spacer()

            Text("\(filteredLogs.count) logs")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.button)
                .font(.caption)

            Button {
                logs.removeAll()
            } label: {
                Image(systemName: "trash")
            }
            .disabled(logs.isEmpty)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    private func startCapturing() {
        isCapturing = true
        NDKLogger.setLogHandler { [self] message in
            Task { @MainActor in
                let entry = NDKLogEntry(rawMessage: message)
                logs.append(entry)
                if logs.count > maxLogEntries {
                    logs.removeFirst(logs.count - maxLogEntries)
                }
            }
        }
    }

    private func stopCapturing() {
        isCapturing = false
        NDKLogger.setLogHandler(nil)
    }
}

// MARK: - Log Entry Model

private struct NDKLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: NDKLogLevel
    let category: NDKLogCategory
    let message: String
    let rawMessage: String

    init(rawMessage: String) {
        self.rawMessage = rawMessage

        // Parse format: [timestamp] [CATEGORY] [LEVEL] emoji message
        // Example: [2025-01-03T12:00:00Z] [RELAY] [DEBUG] 📡 Connected to relay

        var parsedTimestamp = Date()
        var parsedLevel = NDKLogLevel.info
        var parsedCategory = NDKLogCategory.general
        var parsedMessage = rawMessage

        // Extract timestamp
        if let timestampRange = rawMessage.range(of: #"\[([^\]]+)\]"#, options: .regularExpression) {
            let timestampString = String(rawMessage[timestampRange]).dropFirst().dropLast()
            if let date = ISO8601DateFormatter().date(from: String(timestampString)) {
                parsedTimestamp = date
            }
        }

        // Extract category
        for cat in NDKLogCategory.allCases {
            if rawMessage.contains("[\(cat.rawValue)]") {
                parsedCategory = cat
                break
            }
        }

        // Extract level
        for level in [NDKLogLevel.error, .warning, .info, .debug, .trace] {
            if rawMessage.contains("[\(level)]") || rawMessage.contains("[\(level.description)]") {
                parsedLevel = level
                break
            }
        }

        // Extract message (everything after the last ] and emoji)
        if let lastBracket = rawMessage.lastIndex(of: "]") {
            let afterBracket = rawMessage[rawMessage.index(after: lastBracket)...]
            // Skip the emoji and space
            parsedMessage = String(afterBracket).trimmingCharacters(in: .whitespaces)
            // Remove leading emoji if present
            if let first = parsedMessage.unicodeScalars.first, first.value > 127 {
                parsedMessage = String(parsedMessage.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
        }

        self.timestamp = parsedTimestamp
        self.level = parsedLevel
        self.category = parsedCategory
        self.message = parsedMessage
    }
}

// MARK: - Log Entry Row

private struct LogEntryRow: View {
    let entry: NDKLogEntry
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                levelBadge
                categoryBadge
                Spacer()
                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(entry.message)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .lineLimit(isExpanded ? nil : 2)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }

    private var levelBadge: some View {
        Text(entry.level.description)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(levelColor.opacity(0.2))
            .foregroundStyle(levelColor)
            .cornerRadius(4)
    }

    private var categoryBadge: some View {
        Text(entry.category.rawValue)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.1))
            .foregroundStyle(.secondary)
            .cornerRadius(4)
    }

    private var levelColor: Color {
        switch entry.level {
        case .error: return .red
        case .warning: return .orange
        case .info: return .blue
        case .debug: return .green
        case .trace: return .purple
        case .off: return .gray
        }
    }
}

#Preview {
    NavigationStack {
        LogViewerView()
    }
}
