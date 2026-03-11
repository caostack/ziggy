//! Core module - exports all core types
pub const types = @import("types.zig");
pub const document = @import("document.zig");
pub const selection = @import("selection.zig");
pub const transaction = @import("transaction.zig");
pub const viewport = @import("viewport.zig");

// Re-export commonly used types
pub const Position = types.Position;
pub const Range = types.Range;
pub const EditorError = types.EditorError;

pub const DocumentVTable = document.DocumentVTable;
pub const Document = document.Document;
pub const DocumentError = document.DocumentError;

pub const Selection = selection.Selection;
pub const SelectionManager = selection.SelectionManager;

pub const Operation = transaction.Operation;
pub const Transaction = transaction.Transaction;
pub const UndoStack = transaction.UndoStack;

pub const Viewport = viewport.Viewport;

// Re-export test helper
test {
    _ = @import("types.zig");
    _ = @import("document.zig");
    _ = @import("selection.zig");
    _ = @import("transaction.zig");
    _ = @import("viewport.zig");
}
