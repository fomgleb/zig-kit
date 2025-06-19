const std = @import("std");
const Mutex = std.Thread.Mutex;
const BoundedArray = std.BoundedArray;

/// A generic event system.
/// Conditionally thread-safe if `thread_safe` is set to true.
/// Synchronization is done using a `std.Thread.Mutex` only when enabled.
pub fn Event(
    comptime Args: type,
    comptime thread_safe: bool,
    max_callbacks: comptime_int,
) type {
    return struct {
        const MutexOrVoid = if (thread_safe) Mutex else void;
        const Self = @This();

        /// Subscriber callback signature.
        const Callback = struct {
            context: *anyopaque,
            function: *const fn (context: *anyopaque, data: Args) void,
        };

        /// Internal list of subscribers, fixed size.
        callbacks: BoundedArray(Callback, max_callbacks) = BoundedArray(Callback, max_callbacks).init(0) catch unreachable,
        mutex: MutexOrVoid = MutexOrVoid{},

        /// Registers a callback to be invoked when the event is triggered.
        /// If `thread_safe` is true, this function is thread-safe.
        /// Returns error if already subscribed or capacity is full.
        pub fn subscribe(
            self: *Self,
            context: anytype,
            comptime callback: fn (@TypeOf(context), Args) void,
        ) error{ Overflow, AlreadySubscribed }!void {
            const Wrapper = struct {
                fn invoke(ctx: *anyopaque, args: Args) void {
                    callback(@ptrCast(@alignCast(ctx)), args);
                }
            };

            if (thread_safe) self.mutex.lock();
            defer if (thread_safe) self.mutex.unlock();

            for (self.callbacks.constSlice()) |callback_info|
                if (callback_info.context == @as(*anyopaque, @ptrCast(context)))
                    return error.AlreadySubscribed;

            try self.callbacks.append(.{
                .context = @ptrCast(context),
                .function = Wrapper.invoke,
            });
        }

        /// Removes a previously subscribed callback.
        /// If `thread_safe` is true, this function is thread-safe.
        /// Returns error if the context was not found.
        pub fn unsubscribe(self: *Self, context: anytype) error{NoSuchSubscriber}!void {
            const ctx_ptr: *anyopaque = @ptrCast(context);

            if (thread_safe) self.mutex.lock();
            defer if (thread_safe) self.mutex.unlock();

            for (self.callbacks.constSlice(), 0..) |callback, i| {
                if (callback.context == ctx_ptr) {
                    _ = self.callbacks.swapRemove(i);
                    return;
                }
            }

            return error.NoSuchSubscriber;
        }

        /// Removes all subscribers.
        /// If `thread_safe` is true, this function is thread-safe.
        pub fn unsubscribeAll(self: *Self) void {
            if (thread_safe) self.mutex.lock();
            self.callbacks.clear();
            if (thread_safe) self.mutex.unlock();
        }

        /// Calls all registered callbacks with provided event data.
        /// If `thread_safe` is true, this function is thread-safe.
        /// Executes callbacks outside the mutex lock for efficiency and safety.
        pub fn notify(self: *Self, args: Args) void {
            if (thread_safe) self.mutex.lock();
            const callbacks_copy = self.callbacks;
            if (thread_safe) self.mutex.unlock();

            for (callbacks_copy.constSlice()) |callback| {
                callback.function(callback.context, args);
            }
        }
    };
}

const testing = std.testing;

test "subscribe and notify (non-thread-safe)" {
    var event = Event(i32, false, 2){};

    var called_value: i32 = 0;

    const Context = struct {
        called_value: *i32,

        fn on_event(self: *@This(), val: i32) void {
            self.called_value.* = val;
        }
    };
    var ctx = Context{ .called_value = &called_value };

    try event.subscribe(&ctx, Context.on_event);
    event.notify(123);

    try testing.expectEqual(@as(i32, 123), called_value);
}

test "double subscribe returns AlreadySubscribed" {
    var event = Event(u8, false, 2){};

    const Context = struct {
        fn on_event(_: *@This(), _: u8) void {}
    };
    var ctx = Context{};

    try event.subscribe(&ctx, Context.on_event);
    try testing.expectError(error.AlreadySubscribed, event.subscribe(&ctx, Context.on_event));
}

test "unsubscribe and unsubscribeAll" {
    var event = Event(void, false, 2){};

    var called = false;

    const Context = struct {
        called: *bool,

        fn on_event(self: *@This(), _: void) void {
            self.called.* = true;
        }
    };
    var ctx = Context{ .called = &called };

    try event.subscribe(&ctx, Context.on_event);
    try event.unsubscribe(&ctx);

    event.notify({});
    try testing.expectEqual(false, called);

    try event.subscribe(&ctx, Context.on_event);
    event.unsubscribeAll();
    event.notify({});
    try testing.expectEqual(false, called); // still false
}

test "subscribe overflow" {
    var event = Event(u8, false, 1){};

    const Ctx = struct {
        dummy: i32 = 0,

        fn cb(_: *@This(), _: u8) void {}
    };
    var ctx1 = Ctx{};
    var ctx2 = Ctx{};

    try event.subscribe(&ctx1, Ctx.cb);
    try testing.expectError(error.Overflow, event.subscribe(&ctx2, Ctx.cb));
}

test "unsubscribe returns NoSuchSubscriber" {
    var event = Event(u8, false, 1){};

    const Dummy = struct {
        fn cb(_: *@This(), _: u8) void {}
    };
    var ctx = Dummy{};
    try testing.expectError(error.NoSuchSubscriber, event.unsubscribe(&ctx));
}

test "basic thread-safe event" {
    var event = Event(i32, true, 1){};

    var got: i32 = 0;

    const Ctx = struct {
        got: *i32,

        fn cb(self: *@This(), val: i32) void {
            self.got.* = val;
        }
    };
    var ctx = Ctx{ .got = &got };

    try event.subscribe(&ctx, Ctx.cb);
    event.notify(42);
    try testing.expectEqual(42, got);
}
