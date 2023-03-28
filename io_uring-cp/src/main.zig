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
    var write_left = insize;
    var reads: usize = 0;
    var writes: usize = 0;
    var offset: u64 = 0;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var iovecs = try allocator.alloc(os.iovec, 1);
    defer allocator.free(iovecs);

    while (insize > 0 or write_left > 0) {
        // Queue up as many reads as we can
        var had_reads = reads;

        var buf = try allocator.alloc(u8, insize);
        defer allocator.free(buf);
        read_loop: while (insize > 0) {
            var this_size = std.math.max(insize, BUFFER_SIZE);

            if (reads + writes >= QUEUE_DEPTH or
                this_size < 0)
            {
                break :read_loop;
            }

            iovecs[0].iov_base = buf.ptr;
            iovecs[0].iov_len = this_size;
            _ = ring.read(EVENT_R, infile.handle, .{ .iovecs = iovecs[0..] }, offset) catch {
                // On SubmissionQueueFull error we want to break and start writing
                break :read_loop;
            };

            insize -= this_size;
            offset += this_size;
            reads += 1;
        }

        if (had_reads != reads) {
            var ret = try ring.submit();
            if (ret < 0) {
                std.log.err("io_uring_submit: {s}\n", .{ret});
                return error.IOUringSubmitError;
            }
        }

        // Queue is full at this point, find at least 1 completion
        write_loop: while (write_left > 0) {
            var cqe = ring.copy_cqe() catch {
                break :write_loop;
            };

            _ = try ring.write(EVENT_W, outfile.handle, iovecs[0].iov_base[0..iovecs[0].iov_len], 0);
            _ = try ring.submit();
            write_left -= iovecs[0].iov_len;

            cqe = ring.copy_cqe() catch {
                break :write_loop;
            };
            ring.cqe_seen(&cqe);
        }
    }
}

/// Basically the cp command, except using IO_Uring.
///
/// Mostly a port of liburing's io_uring-cp, but Zigish!
/// This code also accomplishes the same thing but in less than half the LoC.
/// Not a good metric for comparison but still...
/// https://github.com/axboe/liburing/blob/master/examples/io_uring-cp.c
pub fn main() !void {
    var args = std.process.args();
    // Read args
    _ = args.next(); // ignore self, then read file paths
    var infile_path = args.next() orelse {
        std.debug.print("expected usage: io_uring-cp [infile] [outfile]\n", .{});
        return error.NoInfile;
    };
    var outfile_path = args.next() orelse {
        std.debug.print("expected usage: io_uring-cp [infile] [outfile]\n", .{});
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
