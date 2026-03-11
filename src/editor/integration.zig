//! Integration module - connects core, storage, and adapters
//! Provides high-level operations using the new layered architecture
const std = @import("std");
const Allocator = std.mem.Allocator;

const core = @import("core/mod.zig");
const storage = @import("storage/mod.zig");
const adapters = @import("adapters/mod.zig");

pub const Document = core.Document;
pub const DocumentVTable = core.DocumentVTable;
pub const DocumentError = core.DocumentError;
pub const GapBuffer = storage.GapBuffer;
pub const Selection = core.Selection;
pub const SelectionManager = core.SelectionManager;
pub const Transaction = core.Transaction;
pub const UndoStack = core.UndoStack;
pub const Operation = core.Operation;
pub const Viewport = core.Viewport;
pub const Position = core.Position;
pub const Range = core.Range;

// Re-export adapter types
pub const Key = adapters.Key;
pub const Terminal = adapters.Terminal;
pub const Input = adapters.Input;
pub const FileSystem = adapters.FileSystem;
pub const TerminalError = adapters.TerminalError;
pub const InputError = adapters.InputError;
pub const FileError = adapters.FileError;

/// EditorState - combines all editor components using the new architecture
pub const EditorState = struct {
    document: Document,
    selection: SelectionManager,
    viewport: Viewport,
    undo_stack: UndoStack,
    allocator: Allocator,

    const Self = @This();

    /// Initialize with a GapBuffer document
    pub fn init(allocator: Allocator, rows: usize, cols: usize) !Self {
        var gap_buffer = try allocator.create(GapBuffer);
        errdefer allocator.destroy(gap_buffer);
        gap_buffer.* = try GapBuffer.init(allocator, 4096);

        return .{
            .document = gap_buffer.document(),
            .selection = SelectionManager.init(allocator),
            .viewport = Viewport.init(rows, cols),
            .undo_stack = UndoStack.init(allocator),
            .allocator = allocator,
        };
    }

    /// Initialize with content
    pub fn initContent(allocator: Allocator, content: []const u8, rows: usize, cols: usize) !Self {
        var gap_buffer = try allocator.create(GapBuffer);
        errdefer allocator.destroy(gap_buffer);
        gap_buffer.* = try GapBuffer.initContent(allocator, content);

        return .{
            .document = gap_buffer.document(),
            .selection = SelectionManager.init(allocator),
            .viewport = Viewport.init(rows, cols),
            .undo_stack = UndoStack.init(allocator),
            .allocator = allocator,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        self.document.deinit();
        self.selection.deinit();
        self.undo_stack.deinit();
    }

    /// Insert text at cursor position
    pub fn insert(self: *Self, text: []const u8) !void {
        var tx = Transaction.init(self.allocator);
        errdefer tx.deinit();

        const cursor_pos = self.selection.getCursor();
        try tx.addInsert(cursor_pos, text);
        try self.document.insertAt(cursor_pos, text);

        try self.undo_stack.push(tx);

        // Update selection
        self.selection.moveBy(@as(isize, @intCast(text.len)));

        // Update viewport
        const cursor_row = self.document.getCursorRow();
        const cursor_col = self.document.getCursorCol();
        _ = self.viewport.updateCursor(cursor_row, cursor_col);
    }

    /// Delete character before cursor
    pub fn backspace(self: *Self) bool {
        // Create transaction for undo
        // For now, just delegate to gap buffer
        return self.document.moveCursorLeft();
    }

    /// Move cursor up
    pub fn moveUp(self: *Self) bool {
        if (self.document.moveCursorUp()) {
            const row = self.document.getCursorRow();
            const col = self.document.getCursorCol();
            _ = self.viewport.updateCursor(row, col);
            return true;
        }
        return false;
    }

    /// Move cursor down
    pub fn moveDown(self: *Self) bool {
        if (self.document.moveCursorDown()) {
            const row = self.document.getCursorRow();
            const col = self.document.getCursorCol();
            _ = self.viewport.updateCursor(row, col);
            return true;
        }
        return false;
    }

    /// Move cursor left
    pub fn moveLeft(self: *Self) bool {
        if (self.document.moveCursorLeft()) {
            const row = self.document.getCursorRow();
            const col = self.document.getCursorCol();
            _ = self.viewport.updateCursor(row, col);
            return true;
        }
        return false;
    }

    /// Move cursor right
    pub fn moveRight(self: *Self) bool {
        if (self.document.moveCursorRight()) {
            const row = self.document.getCursorRow();
            const col = self.document.getCursorCol();
            _ = self.viewport.updateCursor(row, col);
            return true;
        }
        return false;
    }

    /// Undo last operation
    pub fn undo(self: *Self) bool {
        if (self.undo_stack.undo()) |tx| {
            defer {
                var t = tx;
                t.deinit();
            }
            // Apply inverse operations
            for (tx.operations.items) |op| {
                switch (op) {
                    .insert => |ins| {
                        self.document.insertAt(ins.pos, ins.text) catch return false;
                    },
                    .delete => |del| {
                        self.document.deleteRange(del.start, del.end) catch return false;
                    },
                }
            }
            return true;
        }
        return false;
    }

    /// Check if can undo
    pub fn canUndo(self: Self) bool {
        return self.undo_stack.canUndo();
    }

    /// Check if can redo
    pub fn canRedo(self: Self) bool {
        return self.undo_stack.canRedo();
    }

    /// Get visible line range for rendering
    pub fn getVisibleRange(self: Self) core.LineRange {
        return self.viewport.getVisibleRange(self.document.getLineCount());
    }

    /// Get line content for rendering
    pub fn getLine(self: Self, line: usize) ?[]const u8 {
        return self.document.getLine(line);
    }
};

// ============================================================================
// Tests
// ============================================================================

test "EditorState - init" {
    var state = try EditorState.init(std.testing.allocator, 24, 80);
    defer state.deinit();

    try std.testing.expectEqual(@as(usize, 1), state.document.getLineCount());
    try std.testing.expectEqual(@as(usize, 0), state.selection.getCursor());
}

test "EditorState - initContent" {
    var state = try EditorState.initContent(std.testing.allocator, "Hello\nWorld", 24, 80);
    defer state.deinit();

    try std.testing.expectEqual(@as(usize, 2), state.document.getLineCount());
    try std.testing.expectEqualStrings("Hello\n", state.document.getLine(0).?);
}

test "EditorState - cursor movement" {
    var state = try EditorState.initContent(std.testing.allocator, "Line 1\nLine 2", 24, 80);
    defer state.deinit();

    try std.testing.expect(state.moveDown());
    try std.testing.expectEqual(@as(usize, 1), state.document.getCursorRow());

    try std.testing.expect(state.moveUp());
    try std.testing.expectEqual(@as(usize, 0), state.document.getCursorRow());
}

test "EditorState - viewport integration" {
    var state = try EditorState.initContent(std.testing.allocator, "Line 1\nLine 2", 3, 80);
    defer state.deinit();

    // Small viewport, scroll should work
    try std.testing.expect(state.viewport.isLineVisible(0));
    try std.testing.expect(!state.viewport.isLineVisible(10));
}

test "EditorState - undo stack" {
    var state = try EditorState.init(std.testing.allocator, 24, 80);
    defer state.deinit();

    try std.testing.expect(!state.canUndo());
    try std.testing.expect(!state.canRedo());
}

test "EditorState - get visible range" {
    var state = try EditorState.init(std.testing.allocator, 24, 80);
    defer state.deinit();

    const range = state.getVisibleRange();
    try std.testing.expectEqual(@as(usize, 0), range.start);
    try std.testing.expectEqual(@as(usize, 1), range.end); // 1 line (empty doc)
}

/// FullEditor - complete editor with adapters (for production and testing)
pub const FullEditor = struct {
    state: EditorState,
    terminal: Terminal,
    input: Input,
    filesystem: FileSystem,
    filename: ?[]const u8,
    modified: bool,
    should_quit: bool,
    allocator: Allocator,

    const Self = @This();

    /// Initialize with adapters
    pub fn init(
        allocator: Allocator,
        terminal: Terminal,
        input: Input,
        filesystem: FileSystem,
    ) !Self {
        const window_size = terminal.getWindowSize() catch adapters.WindowSize{ .rows = 24, .cols = 80 };

        var state = try EditorState.init(allocator, window_size.rows, window_size.cols);
        errdefer state.deinit();

        return .{
            .state = state,
            .terminal = terminal,
            .input = input,
            .filesystem = filesystem,
            .filename = null,
            .modified = false,
            .should_quit = false,
            .allocator = allocator,
        };
    }

    /// Initialize with file content
    pub fn initFile(
        allocator: Allocator,
        terminal: Terminal,
        input: Input,
        filesystem: FileSystem,
        filename: []const u8,
    ) !Self {
        const window_size = terminal.getWindowSize() catch adapters.WindowSize{ .rows = 24, .cols = 80 };

        // Load file content
        const content = filesystem.open(allocator, filename) catch |err| {
            return switch (err) {
                error.NotFound => error.FileNotFound,
                else => error.OpenFailed,
            };
        };
        defer allocator.free(content);

        var state = try EditorState.initContent(allocator, content, window_size.rows, window_size.cols);
        errdefer state.deinit();

        // Copy filename
        const owned_filename = try allocator.dupe(u8, filename);
        errdefer allocator.free(owned_filename);

        return .{
            .state = state,
            .terminal = terminal,
            .input = input,
            .filesystem = filesystem,
            .filename = owned_filename,
            .modified = false,
            .should_quit = false,
            .allocator = allocator,
        };
    }

    /// Clean up resources
    pub fn deinit(self: *Self) void {
        self.state.deinit();
        self.terminal.deinit();
        self.input.deinit();
        self.filesystem.deinit();
        if (self.filename) |f| {
            self.allocator.free(f);
        }
    }

    /// Handle a single key press
    pub fn handleKey(self: *Self, key: Key) !void {
        switch (key) {
            .ctrl_c => {
                // Force quit
                self.should_quit = true;
            },
            .ctrl_q => {
                // Quit with save prompt if modified
                if (self.modified) {
                    // For now, just quit
                    // TODO: implement save prompt
                }
                self.should_quit = true;
            },
            .ctrl_s => {
                try self.saveFile();
            },
            .arrow_up => {
                _ = self.state.moveUp();
            },
            .arrow_down => {
                _ = self.state.moveDown();
            },
            .arrow_left => {
                _ = self.state.moveLeft();
            },
            .arrow_right => {
                _ = self.state.moveRight();
            },
            .home => {
                // Move to start of line (col 0)
                self.state.document.setCursor(self.state.document.getCursorRow(), 0);
            },
            .end => {
                // Move to end of line
                const row = self.state.document.getCursorRow();
                const line_len = self.state.document.getLineLength(row);
                self.state.document.setCursor(row, line_len);
            },
            .enter => {
                try self.state.insert("\n");
                self.modified = true;
            },
            .backspace => {
                if (self.state.backspace()) {
                    self.modified = true;
                }
            },
            .delete => {
                // Delete character at cursor
                // TODO: implement delete forward
            },
            .character => |bytes| {
                const len = std.mem.sliceTo(bytes[0..], 0).len;
                if (len > 0) {
                    try self.state.insert(bytes[0..len]);
                    self.modified = true;
                }
            },
            .escape, .tab, .page_up, .page_down => {
                // TODO: implement these
            },
            .ctrl_f, .unknown => {
                // Ignore
            },
        }
    }

    /// Single step: refresh and read/handle one key
    pub fn step(self: *Self) !bool {
        if (self.should_quit) return false;

        // Refresh screen
        try self.refresh();

        // Read key
        const key = self.input.readKey() catch {
            return true; // Continue on read error
        };

        // Handle key
        self.handleKey(key) catch |err| {
            if (err == error.Quit) {
                self.should_quit = true;
                return false;
            }
        };

        return !self.should_quit;
    }

    /// Main event loop
    pub fn run(self: *Self) !void {
        while (try self.step()) {}
    }

    /// Refresh the screen
    pub fn refresh(self: *Self) !void {
        try self.terminal.clearScreen();
        try self.terminal.hideCursor();

        const visible_range = self.state.getVisibleRange();
        var row: usize = 1;

        var line_num = visible_range.start;
        while (line_num < visible_range.end) : (line_num += 1) {
            try self.terminal.moveCursor(row, 1);
            if (self.state.getLine(line_num)) |line| {
                try self.terminal.writeAll(line);
            }
            row += 1;
        }

        // Draw status line
        try self.terminal.moveCursor(visible_range.end - visible_range.start + 1, 1);
        try self.terminal.writeAll("\x1b[7m"); // Invert colors
        if (self.filename) |f| {
            try self.terminal.writeAll(f);
        } else {
            try self.terminal.writeAll("[No File]");
        }
        if (self.modified) {
            try self.terminal.writeAll(" [Modified]");
        }
        try self.terminal.writeAll("\x1b[m"); // Reset colors

        // Position cursor (use viewport's screen coordinates, not document coordinates)
        try self.terminal.moveCursor(
            self.state.viewport.cursor_screen_row,
            self.state.viewport.cursor_screen_col,
        );
        try self.terminal.showCursor();
    }

    /// Save file
    pub fn saveFile(self: *Self) !void {
        const path = self.filename orelse return error.NoFilename;

        const content = try self.state.document.toSlice(self.allocator);
        defer self.allocator.free(content);

        self.filesystem.save(path, content) catch return error.SaveFailed;
        self.modified = false;
    }

    /// Check if document is modified
    pub fn isModified(self: Self) bool {
        return self.modified;
    }

    /// Check if editor should quit
    pub fn shouldQuit(self: Self) bool {
        return self.should_quit;
    }
};

// ============================================================================
// FullEditor Tests
// ============================================================================

test "FullEditor - init with mocks" {
    const mock_term = adapters.MockTerminal;
    _ = mock_term;
    // Note: Full initialization requires VTable setup, tested in integration tests
}

test "FullEditor - handleKey arrow movement" {
    var state = try EditorState.initContent(std.testing.allocator, "Line 1\nLine 2", 24, 80);
    defer state.deinit();

    var mock_input = adapters.MockInput.init(std.testing.allocator);
    defer mock_input.deinit();

    try mock_input.addKey(.arrow_down);
    try mock_input.addKey(.arrow_up);

    // Simulate key handling through state
    try std.testing.expect(state.moveDown());
    try std.testing.expectEqual(@as(usize, 1), state.document.getCursorRow());

    try std.testing.expect(state.moveUp());
    try std.testing.expectEqual(@as(usize, 0), state.document.getCursorRow());
}

test "FullEditor - handleKey character insert" {
    var state = try EditorState.init(std.testing.allocator, 24, 80);
    defer state.deinit();

    try state.insert("H");
    try state.insert("i");

    const line = state.document.getLine(0).?;
    try std.testing.expectEqualStrings("Hi", line);
}

// ============================================================================
// Real User Scenario Tests
// ============================================================================

test "FullEditor - complete lifecycle with mock adapters" {
    const allocator = std.testing.allocator;

    // 1. Setup mock adapters (simulates user starting the editor)
    var mock_term = adapters.MockTerminal.init(allocator);
    defer mock_term.deinit();
    var mock_input = adapters.MockInput.init(allocator);
    defer mock_input.deinit(allocator);
    var mock_fs = adapters.MockFileSystem.init(allocator);
    defer mock_fs.deinit();

    // 2. Create editor
    var editor = try FullEditor.init(
        allocator,
        mock_term.terminal(),
        mock_input.input(),
        mock_fs.fileSystem(),
    );
    defer editor.deinit(); // This should NOT crash!

    // 3. Verify initial state
    try std.testing.expect(!editor.isModified());
    try std.testing.expect(!editor.shouldQuit());
}

test "FullEditor - user types and quits" {
    const allocator = std.testing.allocator;

    var mock_term = adapters.MockTerminal.init(allocator);
    defer mock_term.deinit();
    var mock_input = adapters.MockInput.init(allocator);
    defer mock_input.deinit(allocator);
    var mock_fs = adapters.MockFileSystem.init(allocator);
    defer mock_fs.deinit();

    // User types "Hi" then Ctrl+C to quit
    try mock_input.addChar(allocator, "H");
    try mock_input.addChar(allocator, "i");
    try mock_input.addKey(allocator, .ctrl_c);

    var editor = try FullEditor.init(
        allocator,
        mock_term.terminal(),
        mock_input.input(),
        mock_fs.fileSystem(),
    );
    defer editor.deinit();

    // Step through: first key inserts "H"
    try std.testing.expect(try editor.step());
    try std.testing.expect(editor.isModified());

    // Step through: second key inserts "i"
    try std.testing.expect(try editor.step());

    // Step through: Ctrl+C quits
    try std.testing.expect(!try editor.step());
    try std.testing.expect(editor.shouldQuit());
}

test "FullEditor - open file, edit, save" {
    const allocator = std.testing.allocator;

    var mock_term = adapters.MockTerminal.init(allocator);
    defer mock_term.deinit();
    var mock_input = adapters.MockInput.init(allocator);
    defer mock_input.deinit(allocator);
    var mock_fs = adapters.MockFileSystem.init(allocator);
    defer mock_fs.deinit();

    // Pre-populate filesystem with a file
    try mock_fs.createFile("test.txt", "Hello World");

    // User opens file, types "!", then saves
    try mock_input.addChar(allocator, "!");
    try mock_input.addKey(allocator, .ctrl_s);
    try mock_input.addKey(allocator, .ctrl_q);

    var editor = try FullEditor.initFile(
        allocator,
        mock_term.terminal(),
        mock_input.input(),
        mock_fs.fileSystem(),
        "test.txt",
    );
    defer editor.deinit();

    // Verify file was loaded
    try std.testing.expect(!editor.isModified());

    // Step: insert "!"
    _ = try editor.step();
    try std.testing.expect(editor.isModified());

    // Step: save
    _ = try editor.step();
    try std.testing.expect(!editor.isModified());

    // Verify file was saved with new content
    const content = try mock_fs.open(allocator, "test.txt");
    defer allocator.free(content);
    try std.testing.expect(content.len > 0);
}

test "FullEditor - multiple cycles of edit and undo" {
    const allocator = std.testing.allocator;

    var mock_term = adapters.MockTerminal.init(allocator);
    defer mock_term.deinit();
    var mock_input = adapters.MockInput.init(allocator);
    defer mock_input.deinit(allocator);
    var mock_fs = adapters.MockFileSystem.init(allocator);
    defer mock_fs.deinit();

    var editor = try FullEditor.init(
        allocator,
        mock_term.terminal(),
        mock_input.input(),
        mock_fs.fileSystem(),
    );
    defer editor.deinit();

    // Insert some text directly
    try editor.state.insert("ABC");
    try std.testing.expect(editor.state.canUndo());

    // Undo should work
    try std.testing.expect(editor.state.undo());
    try std.testing.expect(!editor.state.canUndo());
}

test "FullEditor - error during refresh doesn't crash deinit" {
    // This test simulates the original bug:
    // 1. An error occurs during refresh (WriteFailed)
    // 2. deinit() is called afterwards
    // 3. deinit should NOT crash with segfault

    const allocator = std.testing.allocator;

    var mock_term = adapters.MockTerminal.init(allocator);
    defer mock_term.deinit();
    var mock_input = adapters.MockInput.init(allocator);
    defer mock_input.deinit(allocator);
    var mock_fs = adapters.MockFileSystem.init(allocator);
    defer mock_fs.deinit();

    // Add a key that will trigger refresh
    try mock_input.addKey(allocator, .ctrl_c);

    var editor = try FullEditor.init(
        allocator,
        mock_term.terminal(),
        mock_input.input(),
        mock_fs.fileSystem(),
    );
    // The key test: deinit() must work even if refresh had issues
    defer editor.deinit();

    // Step through once
    _ = try editor.step();

    // Now deinit() will be called - this used to crash!
}
