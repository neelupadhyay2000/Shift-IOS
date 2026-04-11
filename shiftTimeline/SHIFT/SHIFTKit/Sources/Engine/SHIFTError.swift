import Foundation

/// Errors produced by the SHIFT engine.
public enum SHIFTError: Error, Sendable, Equatable {
    case circularDependency
    case blockNotFound(UUID)
}
