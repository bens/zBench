const std = @import("std");
const expectEq = std.testing.expectEqual;
const expectEqSlices = std.testing.expectEqualSlices;

pub const Error = @import("./runner/types.zig").Error;
pub const Step = @import("./runner/types.zig").Step;
const Runner = @This();

const State = union(enum) {
    preparing: Preparing,
    running: Running,

    const Preparing = struct {
        /// Number of iterations to be performed in the benchmark.
        N: usize = 1,

        /// Maximum number of iterations the benchmark can run. This limit helps
        /// to avoid excessively long benchmark runs.
        max_iterations: u16,

        /// Time budget for the benchmark in nanoseconds. This value is used to
        /// determine how long a single benchmark should be allowed to run
        /// before concluding. Helps in avoiding long-running benchmarks.
        time_budget_ns: u64,

        /// How many more test runs to do before doubling N.
        iterations_remaining: usize = 1,

        /// Time spent measuring the test's running time while calibrating,
        /// calibration stops if it reaches time_budget_ns.
        elapsed_ns: u64 = 0,

        /// Number of countdowns done from increasing values of N, calibration
        /// stops if it reaches max_iterations.
        iteration_loops: usize = 0,
    };

    const Running = struct {
        /// Number of timings still to be performed in the benchmark.
        iterations_remaining: usize,

        /// Array of timings collected.
        timings_ns: []u64,
    };
};

allocator: std.mem.Allocator,
state: State,

pub fn init(
    allocator: std.mem.Allocator,
    iterations: u16,
    max_iterations: u16,
    time_budget_ns: u64,
) !Runner {
    return if (iterations == 0) .{
        .allocator = allocator,
        .state = .{ .preparing = .{
            .max_iterations = max_iterations,
            .time_budget_ns = time_budget_ns,
        } },
    } else .{
        .allocator = allocator,
        .state = .{ .running = .{
            .iterations_remaining = iterations,
            .timings_ns = try allocator.alloc(u64, iterations),
        } },
    };
}

pub fn next(self: *Runner, ns: u64) Runner.Error!?Runner.Step {
    const MAX_N = 65536;
    switch (self.state) {
        .preparing => |*st| {
            if (st.elapsed_ns < st.time_budget_ns and st.iteration_loops < st.max_iterations) {
                st.elapsed_ns += ns;
                if (st.iterations_remaining == 0) {
                    // double N for next iteration
                    st.N = @min(st.N * 2, MAX_N);
                    st.iterations_remaining = st.N - 1;
                    st.iteration_loops += 1;
                } else {
                    st.iterations_remaining -= 1;
                }
            } else {
                // Safety first: make sure the recorded durations aren't all-zero
                if (st.elapsed_ns == 0) st.elapsed_ns = 1;
                // Adjust N based on the actual duration achieved
                var N: usize = @intCast((st.N * st.time_budget_ns) / st.elapsed_ns);
                // check that N doesn't go out of bounds
                if (N == 0) N = 1;
                if (N > MAX_N) N = MAX_N;
                // Now run the benchmark with the adjusted N value
                self.state = .{ .running = .{
                    .iterations_remaining = N,
                    .timings_ns = try self.allocator.alloc(u64, N),
                } };
            }
            return .more;
        },
        .running => |*st| {
            if (0 < st.iterations_remaining) {
                st.timings_ns[st.timings_ns.len - st.iterations_remaining] = ns;
                st.iterations_remaining -= 1;
            }
            return if (st.iterations_remaining == 0) null else .more;
        },
    }
}

/// The next() function has returned null and there are no more steps to
/// complete, so get the timing results.
pub fn finish(self: *Runner) Runner.Error![]u64 {
    return switch (self.state) {
        .preparing => &.{},
        .running => |st| st.timings_ns,
    };
}

/// Clean up after an error.
pub fn abort(self: *Runner) void {
    return switch (self.state) {
        .preparing => {},
        .running => |st| self.allocator.free(st.timings_ns),
    };
}

test "Runner" {
    var r = try Runner.init(std.testing.allocator, 0, 16384, 2e9);
    {
        errdefer r.abort();
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(Runner.Step.more, try r.next(200_000_000));
        try expectEq(@as(?Runner.Step, null), try r.next(200_000_000));
    }
    const timings_ns = try r.finish();
    defer std.testing.allocator.free(timings_ns);
    try expectEqSlices(u64, &.{
        200_000_000, 200_000_000, 200_000_000, 200_000_000,
        200_000_000, 200_000_000, 200_000_000, 200_000_000,
    }, timings_ns);
}
