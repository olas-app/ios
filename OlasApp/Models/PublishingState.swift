import Foundation
import Observation

/// Observable state for tracking post publishing status across the app
@Observable
@MainActor
public final class PublishingState {
    public var isPublishing = false
    public var publishingStatus: String = ""
    public var publishingProgress: Double = 0
    public var error: Error?
    public var lastPublishedEventId: String?
    public var didPublish = false

    public init() {}

    public func dismissError() {
        error = nil
        isPublishing = false
        publishingStatus = ""
    }

    public func reset() {
        isPublishing = false
        publishingStatus = ""
        publishingProgress = 0
        error = nil
        didPublish = false
    }
}
