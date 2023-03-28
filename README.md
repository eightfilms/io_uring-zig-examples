# io_uring examples in Zig

**Disclaimer: This is a work in progress**

Learning io_uring by porting over the [examples found in liburing](https://github.com/axboe/liburing), except in Zig!

## What is io_uring?

There are [plenty](https://unixism.net/loti/what_is_io_uring.html), [plenty](https://blogs.oracle.com/linux/post/an-introduction-to-the-io-uring-asynchronous-io-framework) of [resources](https://www.youtube.com/watch?v=EAlHd6-7P0w) talking about io_uring and its benefits in technical detail and they all probably do a better job than I will, so I'll give the TL;DR:

> io_uring makes processing async I/O go brrrr by batching reads/writes and therefore keeping syscalls to a minimum.

## Implementations

- [x] io_uring-close-test
- [ ] ~io_uring-test~ (not porting this - same as above except without file descriptor registration)
- [x] io_uring-cp
- [ ] io_uring-udp
- [ ] link-cp
- [ ] poll-bench
- [ ] send-zerocopy
- [ ] ucontext-cp

## Acknowledgements

These are the resources I learnt from:

- original [liburing repo](https://github.com/axboe/liburing)
- [Lord of the io_uring](https://unixism.net/loti/index.html)
- the [Zig stdlib io_uring tests](https://github.com/ziglang/zig/blob/master/lib/std/os/linux/io_uring.zig), and
- TigerBeetle's [io_uring demos](https://github.com/tigerbeetledb/tigerbeetle/tree/main/demos/io_uring).
