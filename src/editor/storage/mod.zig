//! Storage layer module
pub const gap_buffer = @import("gap_buffer.zig");
pub const piece_table = @import("piece_table.zig");
pub const mock_document = @import("mock_document.zig");

pub const GapBuffer = gap_buffer.GapBuffer;
pub const PieceTable = piece_table.PieceTable;
pub const MockDocument = mock_document.MockDocument;

test {
    _ = @import("gap_buffer.zig");
    _ = @import("piece_table.zig");
    _ = @import("mock_document.zig");
}
