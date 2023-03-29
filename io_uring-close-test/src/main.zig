const std = @import("std");

const process = std.process;
const IO_Uring = std.os.linux.IO_Uring;
const fs = std.fs;
const File = fs.File;
const os = std.os;
const iovec = std.os.iovec;

const QUEUE_DEPTH = 4;

pub fn main() !void {
    var args = std.process.args();

    var file_path: []const u8 = undefined;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Read args
    _ = args.next(); // ignore self, then read file path
    if (args.next()) |path| {
        file_path = path;
    } else {
        return error.NoFileInput;
    }

    // Initialize io_uring
    var ring = try IO_Uring.init(QUEUE_DEPTH, 0);
    defer ring.deinit();

    const file = try fs.openFileAbsolute(file_path, .{});
    var size = (try file.stat()).size;
    defer file.close();

    var fds = [_]os.fd_t{0} ** 1;
    fds[0] = file.handle;
    try ring.register_files(fds[0..]);

    var iovecs = try allocator.alloc(os.iovec, QUEUE_DEPTH);
    defer allocator.free(iovecs);

    var buf = try allocator.alloc(u8, 4096);
    defer allocator.free(buf);

    for (0..QUEUE_DEPTH) |i| {
        iovecs[i].iov_base = buf.ptr;
        iovecs[i].iov_len = 4096;
    }

    var offset: u64 = 0;
    var to_submit: usize = 0;

    while (offset < size) {
        // Zig's built-in IO_Uring library will use readv if you provide iovecs.
        // No need to explicitly use io_uring_prep_readv!
        _ = try ring.read(0, file.handle, .{ .iovecs = iovecs[0..] }, offset);

        offset += iovecs[to_submit].iov_len;
        to_submit += 1;
    }

    var submitted = try ring.submit();

    if (submitted != to_submit) {
        std.debug.print("Submitted less {d}\n", .{submitted});
    }

    var done: usize = 0;
    var pending = submitted;
    var fsize: i32 = 0;
    for (0..pending) |_| {
        var cqe = try ring.copy_cqe();

        done += 1;
        submitted = 0;
        if (cqe.res != 4096 and cqe.res + fsize != size) {
            std.debug.print("submitted={d}, wanted 4096\n", .{cqe.res});
        }

        fsize += cqe.res;
        ring.cqe_seen(&cqe);

        if (submitted > 0) break;
    }

    std.debug.print("Submitted={d}, completed={d} bytes={d}\n", .{ pending, done, fsize });
}
