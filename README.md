# io_uring examples in Zig

**Disclaimer: This is a work in progress**

Learning [io_uring](https://unixism.net/loti/what_is_io_uring.html) by porting over the [examples found in liburing](https://github.com/axboe/liburing), except in Zig!

- [x] io_uring-close-test
- [ ] ~io_uring-test~ (not porting this - same as above except without file descriptor registration)
- [x] io_uring-cp
- [ ] io_uring-udp
- [ ] link-cp
- [ ] poll-bench
- [ ] send-zerocopy
- [ ] ucontext-cp
