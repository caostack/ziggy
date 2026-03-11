//! Transaction-based editing with undo/redo support
//! Operations can be composed into transactions and inverted for undo
const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

/// Single edit operation
pub const Operation = union(enum) {
    /// Insert text at position
    insert: struct {
        pos: usize,
        text: []const u8,
    },

    /// Delete text range, stores deleted content for undo
    delete: struct {
        start: usize,
        end: usize,
        deleted_text: []const u8,
    },

    const Self = @This();

    /// Create the inverse operation (for undo)
    pub fn invert(self: Self, allocator: Allocator) !Self {
        return switch (self) {
            .insert => |ins| Self{
                .delete = .{
                    .start = ins.pos,
                    .end = ins.pos + ins.text.len,
                    .deleted_text = try allocator.dupe(u8, ins.text),
                },
            },
            .delete => |del| Self{
                .insert = .{
                    .pos = del.start,
                    .text = try allocator.dupe(u8, del.deleted_text),
                },
            },
        };
    }

    /// Free owned memory
    pub fn deinit(self: *Self, allocator: Allocator) void {
        switch (self.*) {
            .insert => |*ins| {
                allocator.free(ins.text);
            },
            .delete => |*del| {
                allocator.free(del.deleted_text);
            },
        }
    }

    /// Get the position affected by this operation
    pub fn getPosition(self: Self) usize {
        return switch (self) {
            .insert => |ins| ins.pos,
            .delete => |del| del.start,
        };
    }

    /// Get the length of text affected
    pub fn getLength(self: Self) usize {
        return switch (self) {
            .insert => |ins| ins.text.len,
            .delete => |del| del.end - del.start,
        };
    }
};

/// Transaction - a group of operations that can be undone together
pub const Transaction = struct {
    operations: ArrayList(Operation),
    description: ?[]const u8,

    const Self = @This();

    /// Create empty transaction
    pub fn init(allocator: Allocator) Self {
        return .{
            .operations = ArrayList(Operation).init(allocator),
            .description = null,
        };
    }

    /// Free all resources
    pub fn deinit(self: *Self) void {
        for (self.operations.items) |*op| {
            op.deinit(self.operations.allocator);
        }
        self.operations.deinit();
        if (self.description) |desc| {
            self.operations.allocator.free(desc);
        }
    }

    /// Set description for this transaction
    pub fn setDescription(self: *Self, desc: []const u8) !void {
        if (self.description) |d| {
            self.operations.allocator.free(d);
        }
        self.description = try self.operations.allocator.dupe(u8, desc);
    }

    /// Add an insert operation (takes ownership of text)
    pub fn addInsert(self: *Self, pos: usize, text: []const u8) !void {
        const owned = try self.operations.allocator.dupe(u8, text);
        try self.operations.append(.{
            .insert = .{
                .pos = pos,
                .text = owned,
            },
        });
    }

    /// Add a delete operation (takes ownership of deleted_text)
    pub fn addDelete(self: *Self, start: usize, end: usize, deleted_text: []const u8) !void {
        const owned = try self.operations.allocator.dupe(u8, deleted_text);
        try self.operations.append(.{
            .delete = .{
                .start = start,
                .end = end,
                .deleted_text = owned,
            },
        });
    }

    /// Add an operation (takes ownership)
    pub fn addOperation(self: *Self, op: Operation) !void {
        try self.operations.append(op);
    }

    /// Check if transaction is empty
    pub fn isEmpty(self: Self) bool {
        return self.operations.items.len == 0;
    }

    /// Get operation count
    pub fn count(self: Self) usize {
        return self.operations.items.len;
    }

    /// Build the inverse transaction (for undo)
    /// Operations are inverted in reverse order
    pub fn buildInverse(self: Self) !Self {
        var inverse = Self.init(self.operations.allocator);
        errdefer inverse.deinit();

        // Process operations in reverse order
        var i = self.operations.items.len;
        while (i > 0) {
            i -= 1;
            const op = self.operations.items[i];
            const inverted = try op.invert(self.operations.allocator);
            try inverse.operations.append(inverted);
        }

        if (self.description) |desc| {
            try inverse.setDescription(desc);
        }

        return inverse;
    }
};

/// Undo/Redo stack
pub const UndoStack = struct {
    undo_stack: ArrayList(Transaction),
    redo_stack: ArrayList(Transaction),
    max_depth: usize,

    const Self = @This();

    /// Create new undo stack
    pub fn init(allocator: Allocator) Self {
        return .{
            .undo_stack = ArrayList(Transaction).init(allocator),
            .redo_stack = ArrayList(Transaction).init(allocator),
            .max_depth = 100, // Default max undo history
        };
    }

    /// Free all resources
    pub fn deinit(self: *Self) void {
        // Free undo stack
        for (self.undo_stack.items) |*tx| {
            tx.deinit();
        }
        self.undo_stack.deinit();

        // Free redo stack
        for (self.redo_stack.items) |*tx| {
            tx.deinit();
        }
        self.redo_stack.deinit();
    }

    /// Push a transaction onto the undo stack
    /// This clears the redo stack
    pub fn push(self: *Self, tx: Transaction) !void {
        // Clear redo stack when new edit is made
        self.clearRedoStack();

        // Enforce max depth
        while (self.undo_stack.items.len >= self.max_depth) {
            var old = self.undo_stack.orderedRemove(0);
            old.deinit();
        }

        try self.undo_stack.append(tx);
    }

    /// Pop from undo stack and push inverse to redo stack
    /// Returns the transaction to apply (the inverse)
    pub fn undo(self: *Self) ?Transaction {
        if (self.undo_stack.items.len == 0) return null;

        var tx = self.undo_stack.pop();
        const inverse = tx.buildInverse() catch {
            // Failed to build inverse, push back
            self.undo_stack.append(tx) catch {};
            return null;
        };

        // Move original to redo stack
        self.redo_stack.append(tx) catch {
            tx.deinit();
        };

        return inverse;
    }

    /// Pop from redo stack and push inverse back to undo stack
    /// Returns the transaction to apply (the inverse of redo)
    pub fn redo(self: *Self) ?Transaction {
        if (self.redo_stack.items.len == 0) return null;

        var tx = self.redo_stack.pop();
        const inverse = tx.buildInverse() catch {
            // Failed to build inverse, push back
            self.redo_stack.append(tx) catch {};
            return null;
        };

        // Move original back to undo stack
        self.undo_stack.append(tx) catch {
            tx.deinit();
        };

        return inverse;
    }

    /// Check if undo is available
    pub fn canUndo(self: Self) bool {
        return self.undo_stack.items.len > 0;
    }

    /// Check if redo is available
    pub fn canRedo(self: Self) bool {
        return self.redo_stack.items.len > 0;
    }

    /// Get undo history depth
    pub fn undoDepth(self: Self) usize {
        return self.undo_stack.items.len;
    }

    /// Get redo history depth
    pub fn redoDepth(self: Self) usize {
        return self.redo_stack.items.len;
    }

    /// Clear all history
    pub fn clear(self: *Self) void {
        self.clearUndoStack();
        self.clearRedoStack();
    }

    fn clearUndoStack(self: *Self) void {
        for (self.undo_stack.items) |*tx| {
            tx.deinit();
        }
        self.undo_stack.clearRetainingCapacity();
    }

    fn clearRedoStack(self: *Self) void {
        for (self.redo_stack.items) |*tx| {
            tx.deinit();
        }
        self.redo_stack.clearRetainingCapacity();
    }
};

// ============================================================================
// Tests
// ============================================================================

test "Operation - insert invert" {
    const allocator = std.testing.allocator;

    var op = Operation{
        .insert = .{
            .pos = 10,
            .text = try allocator.dupe(u8, "Hello"),
        },
    };

    const inverted = try op.invert(allocator);
    defer {
        op.deinit(allocator);
        var inv = inverted;
        inv.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 10), inverted.delete.start);
    try std.testing.expectEqual(@as(usize, 15), inverted.delete.end);
    try std.testing.expectEqualStrings("Hello", inverted.delete.deleted_text);
}

test "Operation - delete invert" {
    const allocator = std.testing.allocator;

    var op = Operation{
        .delete = .{
            .start = 5,
            .end = 10,
            .deleted_text = try allocator.dupe(u8, "World"),
        },
    };

    const inverted = try op.invert(allocator);
    defer {
        op.deinit(allocator);
        var inv = inverted;
        inv.deinit(allocator);
    }

    try std.testing.expectEqual(@as(usize, 5), inverted.insert.pos);
    try std.testing.expectEqualStrings("World", inverted.insert.text);
}

test "Transaction - add operations" {
    const allocator = std.testing.allocator;

    var tx = Transaction.init(allocator);
    defer tx.deinit();

    try tx.addInsert(0, "Hello");
    try tx.addInsert(5, " ");
    try tx.addInsert(6, "World");

    try std.testing.expectEqual(@as(usize, 3), tx.count());
    try std.testing.expect(!tx.isEmpty());
}

test "Transaction - build inverse" {
    const allocator = std.testing.allocator;

    var tx = Transaction.init(allocator);
    defer tx.deinit();

    try tx.addInsert(0, "AB");
    try tx.addInsert(2, "CD");

    var inverse = try tx.buildInverse();
    defer inverse.deinit();

    // Inverse should have operations in reverse order
    try std.testing.expectEqual(@as(usize, 2), inverse.count());

    // First inverse op should undo the second insert
    try std.testing.expectEqual(@as(usize, 2), inverse.operations.items[0].delete.start);
    try std.testing.expectEqual(@as(usize, 4), inverse.operations.items[0].delete.end);

    // Second inverse op should undo the first insert
    try std.testing.expectEqual(@as(usize, 0), inverse.operations.items[1].delete.start);
    try std.testing.expectEqual(@as(usize, 2), inverse.operations.items[1].delete.end);
}

test "Transaction - description" {
    const allocator = std.testing.allocator;

    var tx = Transaction.init(allocator);
    defer tx.deinit();

    try tx.setDescription("Type 'Hello'");
    try std.testing.expectEqualStrings("Type 'Hello'", tx.description.?);
}

test "UndoStack - push and undo" {
    const allocator = std.testing.allocator;

    var stack = UndoStack.init(allocator);
    defer stack.deinit();

    var tx = Transaction.init(allocator);
    try tx.addInsert(0, "Hello");
    try stack.push(tx);

    try std.testing.expect(stack.canUndo());
    try std.testing.expect(!stack.canRedo());
    try std.testing.expectEqual(@as(usize, 1), stack.undoDepth());

    const undo_tx = stack.undo();
    try std.testing.expect(undo_tx != null);
    if (undo_tx) |utx| {
        defer {
            var t = utx;
            t.deinit();
        }
        try std.testing.expectEqual(@as(usize, 1), utx.count());
    }

    try std.testing.expect(!stack.canUndo());
    try std.testing.expect(stack.canRedo());
}

test "UndoStack - redo" {
    const allocator = std.testing.allocator;

    var stack = UndoStack.init(allocator);
    defer stack.deinit();

    var tx = Transaction.init(allocator);
    try tx.addInsert(0, "Hello");
    try stack.push(tx);

    // Undo
    var undo_tx = stack.undo().?;
    undo_tx.deinit();

    // Redo
    const redo_tx = stack.redo();
    try std.testing.expect(redo_tx != null);
    if (redo_tx) |rtx| {
        defer {
            var t = rtx;
            t.deinit();
        }
    }

    try std.testing.expect(stack.canUndo());
    try std.testing.expect(!stack.canRedo());
}

test "UndoStack - push clears redo" {
    const allocator = std.testing.allocator;

    var stack = UndoStack.init(allocator);
    defer stack.deinit();

    // Push first transaction
    var tx1 = Transaction.init(allocator);
    try tx1.addInsert(0, "A");
    try stack.push(tx1);

    // Undo
    var undo_tx = stack.undo().?;
    undo_tx.deinit();

    try std.testing.expect(stack.canRedo());

    // Push new transaction - should clear redo
    var tx2 = Transaction.init(allocator);
    try tx2.addInsert(0, "B");
    try stack.push(tx2);

    try std.testing.expect(!stack.canRedo());
}

test "UndoStack - max depth" {
    const allocator = std.testing.allocator;

    var stack = UndoStack.init(allocator);
    stack.max_depth = 3;
    defer stack.deinit();

    // Push more than max depth
    for (0..5) |i| {
        var tx = Transaction.init(allocator);
        try tx.addInsert(i, "X");
        try stack.push(tx);
    }

    // Should have max_depth items
    try std.testing.expectEqual(@as(usize, 3), stack.undoDepth());
}

test "UndoStack - clear" {
    const allocator = std.testing.allocator;

    var stack = UndoStack.init(allocator);
    defer stack.deinit();

    var tx1 = Transaction.init(allocator);
    try tx1.addInsert(0, "A");
    try stack.push(tx1);

    var undo_tx = stack.undo().?;
    undo_tx.deinit();

    try std.testing.expect(stack.canRedo());

    stack.clear();
    try std.testing.expect(!stack.canUndo());
    try std.testing.expect(!stack.canRedo());
}
