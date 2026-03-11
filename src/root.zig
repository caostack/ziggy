//! Ziggy - UTF-8 Terminal Text Editor Library
//!
//! A nano-like text editor with full UTF-8 support, written in Zig.
//! Named after its friendly helper spirit that makes editing text a joy.
//!
//! Features:
//! - UTF-8 text editing with gap buffer
//! - Raw terminal mode with ANSI escape sequences
//! - Arrow key navigation
//! - File open/save operations
//! - Status bar display
//! - Undo/redo support
//! - Layered architecture with VTable abstractions
const std = @import("std");

// ============================================================================
// NEW ARCHITECTURE
// ============================================================================

// Core module - abstractions
pub const core = @import("editor/core/mod.zig");

pub const Position = core.Position;
pub const Range = core.Range;
pub const EditorError = core.EditorError;
pub const Document = core.Document;
pub const DocumentVTable = core.DocumentVTable;
pub const Selection = core.Selection;
pub const SelectionManager = core.SelectionManager;
pub const Operation = core.Operation;
pub const Transaction = core.Transaction;
pub const UndoStack = core.UndoStack;
pub const Viewport = core.Viewport;
pub const LineRange = core.LineRange;

// Storage module - implementations
pub const storage = @import("editor/storage/mod.zig");

pub const GapBuffer = storage.GapBuffer;
pub const PieceTable = storage.PieceTable;
pub const MockDocument = storage.MockDocument;

// Integration module - orchestrates all layers
pub const integration = @import("editor/integration.zig");

pub const EditorState = integration.EditorState;
pub const FullEditor = integration.FullEditor;

// Adapters module - I/O abstractions
pub const adapters = @import("editor/adapters/mod.zig");

pub const TerminalError = adapters.TerminalError;
pub const InputError = adapters.InputError;
pub const FileError = adapters.FileError;
pub const Key = adapters.Key;
pub const WindowSize = adapters.WindowSize;
pub const NativeTerminal = adapters.NativeTerminal;
pub const NativeInput = adapters.NativeInput;
pub const NativeFileSystem = adapters.NativeFileSystem;
pub const MockTerminal = adapters.MockTerminal;
pub const MockInput = adapters.MockInput;
pub const MockFileSystem = adapters.MockFileSystem;

test "root - imports work" {
    try std.testing.expect(true);
}
