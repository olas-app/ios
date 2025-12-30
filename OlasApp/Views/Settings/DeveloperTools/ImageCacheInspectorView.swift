import Kingfisher
import SwiftUI

struct ImageCacheInspectorView: View {
    @State private var memoryCount: Int = 0
    @State private var diskSize: UInt = 0
    @State private var isCalculating = false
    @State private var isClearing = false

    private let cache = ImageCache.default

    var body: some View {
        List {
            Section("Memory Cache") {
                LabeledContent("Cached Images") {
                    Text("\(memoryCount)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Memory Limit") {
                    Text(formatBytes(cache.memoryStorage.config.totalCostLimit))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Expiration") {
                    Text(formatExpiration(cache.memoryStorage.config.expiration))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Disk Cache") {
                LabeledContent("Disk Usage") {
                    if isCalculating {
                        ProgressView()
                    } else {
                        Text(formatBytes(Int(diskSize)))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Disk Limit") {
                    Text(formatBytes(Int(cache.diskStorage.config.sizeLimit)))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Expiration") {
                    Text(formatExpiration(cache.diskStorage.config.expiration))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Cache Path") {
                    Text(cache.diskStorage.directoryURL.path)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Section("Actions") {
                Button {
                    clearMemoryCache()
                } label: {
                    Label("Clear Memory Cache", systemImage: "memorychip")
                }
                .disabled(isClearing)

                Button {
                    clearDiskCache()
                } label: {
                    Label("Clear Disk Cache", systemImage: "externaldrive")
                }
                .disabled(isClearing)

                Button {
                    clearAllCache()
                } label: {
                    Label("Clear All Cache", systemImage: "trash")
                }
                .disabled(isClearing)

                Button {
                    cleanExpiredCache()
                } label: {
                    Label("Clean Expired Only", systemImage: "clock.badge.xmark")
                }
                .disabled(isClearing)
            }

            Section("Info") {
                LabeledContent("Downloader Timeout") {
                    Text("\(Int(ImageDownloader.default.downloadTimeout))s")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Image Cache")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await refreshStats() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isCalculating)
                }
            }
            .task {
                await refreshStats()
            }
            .refreshable {
                await refreshStats()
            }
    }

    private func refreshStats() async {
        isCalculating = true
        // Memory count not directly accessible in newer Kingfisher versions
        memoryCount = 0

        diskSize = await withCheckedContinuation { continuation in
            cache.calculateDiskStorageSize { result in
                switch result {
                case .success(let size):
                    continuation.resume(returning: size)
                case .failure:
                    continuation.resume(returning: 0)
                }
            }
        }

        isCalculating = false
    }

    private func clearMemoryCache() {
        isClearing = true
        cache.clearMemoryCache()
        memoryCount = 0
        isClearing = false
    }

    private func clearDiskCache() {
        isClearing = true
        cache.clearDiskCache {
            Task { @MainActor in
                await refreshStats()
                isClearing = false
            }
        }
    }

    private func clearAllCache() {
        isClearing = true
        cache.clearCache {
            Task { @MainActor in
                await refreshStats()
                isClearing = false
            }
        }
    }

    private func cleanExpiredCache() {
        isClearing = true
        cache.cleanExpiredMemoryCache()
        cache.cleanExpiredDiskCache {
            Task { @MainActor in
                await refreshStats()
                isClearing = false
            }
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formatExpiration(_ expiration: StorageExpiration) -> String {
        switch expiration {
        case .never:
            return "Never"
        case .seconds(let seconds):
            return formatDuration(seconds)
        case .days(let days):
            return "\(days) days"
        case .date(let date):
            return date.formatted()
        case .expired:
            return "Expired"
        }
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds >= 86400 {
            return String(format: "%.1f days", seconds / 86400)
        } else if seconds >= 3600 {
            return String(format: "%.1f hours", seconds / 3600)
        } else if seconds >= 60 {
            return String(format: "%.0f minutes", seconds / 60)
        } else {
            return String(format: "%.0f seconds", seconds)
        }
    }
}
