// Custom error types for Antler
// Provides detailed, actionable error messages

use std::fmt;
use std::io;
use std::error::Error;

/// Main error type for Antler operations
#[derive(Debug)]
pub enum AntlerError {
    /// I/O operation failed
    Io {
        context: String,
        source: io::Error,
    },
    
    /// Tree structure violation (scalar parent)
    TreeStructureViolation {
        path: String,
        parent: String,
        reason: String,
    },
    
    /// WAL corruption detected
    WalCorruption {
        position: u64,
        expected: String,
        found: String,
    },
    
    /// Segment corruption detected
    SegmentCorruption {
        path: String,
        offset: u64,
        reason: String,
    },
    
    /// Compaction failed
    CompactionFailed {
        level: usize,
        segment_count: usize,
        reason: String,
    },
    
    /// Cache overflow
    CacheOverflow {
        current_size: usize,
        max_size: usize,
    },
    
    /// Invalid path format
    InvalidPath {
        path: String,
        reason: String,
    },
    
    /// Invalid pattern
    InvalidPattern {
        pattern: String,
        reason: String,
    },
    
    /// Transaction aborted
    TransactionAborted {
        reason: String,
        operations_rolled_back: usize,
    },
    
    /// Concurrent modification
    ConcurrentModification {
        key: String,
        expected_seq: u64,
        actual_seq: u64,
    },
    
    /// Resource exhausted
    ResourceExhausted {
        resource: String,
        limit: String,
    },
    
    /// Operation timeout
    Timeout {
        operation: String,
        duration_ms: u64,
    },
}

impl fmt::Display for AntlerError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            AntlerError::Io { context, source } => {
                write!(f, "I/O error during {}: {}", context, source)
            }
            
            AntlerError::TreeStructureViolation { path, parent, reason } => {
                write!(f, "Cannot write '{}': parent '{}' is a scalar value. {}", 
                       path, parent, reason)
            }
            
            AntlerError::WalCorruption { position, expected, found } => {
                write!(f, "WAL corruption at position {}: expected {}, found {}", 
                       position, expected, found)
            }
            
            AntlerError::SegmentCorruption { path, offset, reason } => {
                write!(f, "Segment '{}' corrupted at offset {}: {}", 
                       path, offset, reason)
            }
            
            AntlerError::CompactionFailed { level, segment_count, reason } => {
                write!(f, "Compaction failed for L{} ({} segments): {}", 
                       level, segment_count, reason)
            }
            
            AntlerError::CacheOverflow { current_size, max_size } => {
                write!(f, "Cache overflow: {} bytes exceeds limit of {} bytes", 
                       current_size, max_size)
            }
            
            AntlerError::InvalidPath { path, reason } => {
                write!(f, "Invalid path '{}': {}", path, reason)
            }
            
            AntlerError::InvalidPattern { pattern, reason } => {
                write!(f, "Invalid pattern '{}': {}", pattern, reason)
            }
            
            AntlerError::TransactionAborted { reason, operations_rolled_back } => {
                write!(f, "Transaction aborted: {} ({} operations rolled back)", 
                       reason, operations_rolled_back)
            }
            
            AntlerError::ConcurrentModification { key, expected_seq, actual_seq } => {
                write!(f, "Concurrent modification of '{}': expected seq {}, found seq {}", 
                       key, expected_seq, actual_seq)
            }
            
            AntlerError::ResourceExhausted { resource, limit } => {
                write!(f, "Resource exhausted: {} (limit: {})", resource, limit)
            }
            
            AntlerError::Timeout { operation, duration_ms } => {
                write!(f, "Operation '{}' timed out after {}ms", operation, duration_ms)
            }
        }
    }
}

impl Error for AntlerError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            AntlerError::Io { source, .. } => Some(source),
            _ => None,
        }
    }
}

/// Result type alias for Antler operations
pub type Result<T> = std::result::Result<T, AntlerError>;

/// Helper trait for adding context to io::Errors
pub trait IoContext<T> {
    fn io_context(self, context: impl Into<String>) -> Result<T>;
}

impl<T> IoContext<T> for io::Result<T> {
    fn io_context(self, context: impl Into<String>) -> Result<T> {
        self.map_err(|e| AntlerError::Io {
            context: context.into(),
            source: e,
        })
    }
}

/// Builder for detailed error messages
pub struct ErrorBuilder {
    error: AntlerError,
}

impl ErrorBuilder {
    pub fn tree_violation(path: impl Into<String>) -> Self {
        ErrorBuilder {
            error: AntlerError::TreeStructureViolation {
                path: path.into(),
                parent: String::new(),
                reason: String::new(),
            }
        }
    }
    
    pub fn parent(mut self, parent: impl Into<String>) -> Self {
        if let AntlerError::TreeStructureViolation { parent: p, .. } = &mut self.error {
            *p = parent.into();
        }
        self
    }
    
    pub fn reason(mut self, reason: impl Into<String>) -> Self {
        match &mut self.error {
            AntlerError::TreeStructureViolation { reason: r, .. } |
            AntlerError::SegmentCorruption { reason: r, .. } |
            AntlerError::CompactionFailed { reason: r, .. } |
            AntlerError::InvalidPath { reason: r, .. } |
            AntlerError::InvalidPattern { reason: r, .. } => {
                *r = reason.into();
            }
            _ => {}
        }
        self
    }
    
    pub fn build(self) -> AntlerError {
        self.error
    }
}

/// Extension trait for better error handling in async code
#[cfg(feature = "async")]
pub trait AsyncErrorContext {
    type Output;
    
    fn context(self, msg: &str) -> Self::Output;
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_error_display() {
        let err = AntlerError::TreeStructureViolation {
            path: "users/alice/profile".to_string(),
            parent: "users/alice".to_string(),
            reason: "Parent is a scalar value, not a tree node".to_string(),
        };
        
        let msg = format!("{}", err);
        assert!(msg.contains("users/alice/profile"));
        assert!(msg.contains("users/alice"));
        assert!(msg.contains("scalar value"));
    }
    
    #[test]
    fn test_io_context() {
        let io_err = io::Error::new(io::ErrorKind::PermissionDenied, "access denied");
        let result: io::Result<()> = Err(io_err);
        
        let antler_result = result.io_context("opening WAL file");
        assert!(antler_result.is_err());
        
        let err = antler_result.unwrap_err();
        let msg = format!("{}", err);
        assert!(msg.contains("opening WAL file"));
        assert!(msg.contains("access denied"));
    }
    
    #[test]
    fn test_error_builder() {
        let err = ErrorBuilder::tree_violation("users/bob/settings")
            .parent("users/bob")
            .reason("Cannot add children to scalar values")
            .build();
            
        let msg = format!("{}", err);
        assert!(msg.contains("users/bob/settings"));
        assert!(msg.contains("users/bob"));
        assert!(msg.contains("Cannot add children"));
    }
}