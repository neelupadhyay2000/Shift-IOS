import Foundation

/// Errors produced by the SHIFT engine.
public enum SHIFTError: Error, Sendable, Equatable {
    case circularDependency(blockID: UUID)
    case blockNotFound(UUID)
}
