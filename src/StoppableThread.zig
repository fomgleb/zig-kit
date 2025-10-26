const std = @import("std");
const Thread = std.Thread;
const atomic = std.atomic;
const Self = @This();

thread: ?Thread = null,
stop_flag: atomic.Value(bool) = atomic.Value(bool).init(false),

pub const StartError = error{AlreadyRunning} || std.Thread.SpawnError;

/// Starts the thread with the given function and context.
pub fn start(self: *Self, comptime func: anytype, args: anytype) StartError!void {
    if (self.thread != null) return error.AlreadyRunning;

    self.stop_flag.store(false, .release);
    self.thread = try Thread.spawn(.{}, func, args);
}

/// Signals the thread to stop.
pub fn stop(self: *Self) void {
    self.stop_flag.store(true, .release);
    if (self.thread) |t| {
        t.join();
        self.thread = null;
    }
}

/// Checks if stop was requested.
pub fn shouldStop(self: *const Self) bool {
    return self.stop_flag.load(.acquire);
}

const testing = std.testing;

test "thread lifecycle test" {
    var some_context = struct {
        stoppable_thread: Self = Self{},

        fn worker_fn(ctx: *@This()) void {
            while (!ctx.stoppable_thread.shouldStop()) {
                Thread.sleep(10_000);
            }
        }
    }{};

    try some_context.stoppable_thread.start(@TypeOf(some_context).worker_fn, .{&some_context});
    Thread.sleep(50_000);
    some_context.stoppable_thread.stop();

    try testing.expect(some_context.stoppable_thread.thread == null);
    try testing.expect(some_context.stoppable_thread.shouldStop() == true);
}

test "double start fails" {
    var some_context = struct {
        stoppable_thread: Self = Self{},

        pub fn worker_fn() void {
            Thread.sleep(100_000);
        }
    }{};

    try some_context.stoppable_thread.start(@TypeOf(some_context).worker_fn, .{});
    try testing.expectError(error.AlreadyRunning, some_context.stoppable_thread.start(@TypeOf(some_context).worker_fn, .{}));
    some_context.stoppable_thread.stop();
}
