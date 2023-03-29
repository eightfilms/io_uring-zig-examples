const std = @import("std");

const process = std.process;
const IO_Uring = std.os.linux.IO_Uring;
const fs = std.fs;
const File = fs.File;
const os = std.os;
const iovec = std.os.iovec;

const QUEUE_DEPTH = 64;
const BUFFER_SIZE = 32 * 1024;

// for userdata input
const EVENT_R = 0;
const EVENT_W = 1;

fn copy_file(ring: *IO_Uring, infile: File, outfile: File) !void {
    var insize = (try infile.stat()).size;
    var offset: u64 = 0;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var iovecs = try allocator.alloc(os.iovec, 1);
    defer allocator.free(iovecs);

    var inflight: usize = 0;
    while (insize > 0) {
        var has_inflight = inflight;
        var depth: usize = 0;

        var buf = try allocator.alloc(u8, insize);
        defer allocator.free(buf);
        while (insize > 0 and inflight < QUEUE_DEPTH) {
            var this_size = if (BUFFER_SIZE > insize) insize else BUFFER_SIZE;

            iovecs[0].iov_base = buf.ptr;
            iovecs[0].iov_len = this_size;
            // io_uring_get_sqe, io_uring_prep_readv, io_uring_sqe_set_data is all condensed into 1 call here
            var sqe = try ring.read(EVENT_R, infile.handle, .{ .iovecs = iovecs[0..] }, offset);
            // Link SQEs!
            sqe.flags |= os.linux.IOSQE_IO_LINK;
            _ = try ring.write(EVENT_W, outfile.handle, iovecs[0].iov_base[0..iovecs[0].iov_len], 0);

            offset += this_size;
            insize -= this_size;
            inflight += 2;
        }

        if (has_inflight != inflight) {
            _ = try ring.submit();
        }

        depth = if (insize > 0) QUEUE_DEPTH else 1;

        while (inflight >= depth) {
            _ = try ring.copy_cqe();

            inflight -= 1;
        }
    }
}

/// This is almost the same as io_uring-cp, but with linked SQEs.
///
/// Does the same thing as link-cp but again in fewer LoCs.
/// https://github.com/axboe/liburing/blob/master/examples/link-cp.c
pub fn main() !void {
    var args = std.process.args();
    // Read args
    _ = args.next(); // ignore self, then read file paths
    var infile_path = args.next() orelse {
        std.debug.print("expected usage: link-cp [infile] [outfile]\n", .{});
        return error.NoInfile;
    };
    var outfile_path = args.next() orelse {
        std.debug.print("expected usage: link-cp [infile] [outfile]\n", .{});
        return error.NoOutfile;
    };

    const infile = try fs.openFileAbsolute(infile_path, .{});
    defer infile.close();

    const outfile = try fs.createFileAbsolute(outfile_path, .{});
    defer outfile.close();

    var ring = try IO_Uring.init(QUEUE_DEPTH, 0);
    defer ring.deinit();

    try copy_file(&ring, infile, outfile);
}
