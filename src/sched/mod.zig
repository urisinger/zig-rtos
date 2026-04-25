const root = @import("root");
const std = @import("std");
const arch = root.arch;
const trap = arch.trap;
const utils = root.utils;
const CircularList = utils.list.CircularList;

const TaskState = enum { Running, Sleeping, Dead };
pub const Task = struct {
    tcb: TaskControl,
    next: ?*Task,
    prev: ?*Task,

    allocator: ?*std.mem.Allocator,

    // base must be alligned to the aligment of Task
    pub fn initStatic(mem: []align(16) u8, entry: fn () callconv(.c) void) *Task {
        const task: *Task = @ptrCast(mem.ptr);
        task.tcb.state = .Running;
        task.next = task;
        task.prev = task;
        const buffer_end = @intFromPtr(mem.ptr) + mem.len;
        const aligned_sp = buffer_end;

        task.tcb.sp = (aligned_sp - @sizeOf(trap.TrapFrame)) & ~(@as(usize, 15));

        std.log.debug("addr is: 0x{x}", .{@intFromPtr(&entry)});
        const tf = task.tcb.trapFrame();
        tf.init(@intFromPtr(&entry));

        return task;
    }

    pub fn init(alloc: *std.mem.Allocator, stack_size: usize, entry: *const fn () void) void {
        const mem = alloc.alignedAlloc(u8, .@"16", stack_size);
        Task.initStatic(mem, entry);
    }
};

const TaskControl = struct {
    sp: usize,
    state: TaskState,

    pub inline fn trapFrame(self: *TaskControl) *trap.TrapFrame {
        return @ptrFromInt(self.sp);
    }
};

pub const Sched = struct {
    running: CircularList(Task),
    idle_task: *Task,
    dead_list: ?*Task = null,

    pub fn init(idle_task: *Task) Sched {
        return Sched{
            .running = .init(idle_task),
            .idle_task = idle_task,
        };
    }

    pub fn start(self: *Sched) void {
        const first_task = self.running.current().?;
        const tf = first_task.tcb.trapFrame();
        utils.timer.armMs(500);

        arch.trap.restoreContext(tf);
    }

    pub fn addTask(self: *Sched, task: *Task) void {
        self.running.insertFirst(task);
    }

    pub fn signal(self: *Sched, task: *Task) void {
        const status = arch.enterCritical();

        if (task.state == .Running) {
            task.prev.next = task.next;
            task.next.prev = task.prev;
        }

        const head = self.running;
        task.next = head.next;
        task.prev = head;
        head.next.prev = task;
        head.next = task;

        task.state = .Running;

        arch.exitCritical(status);
    }

    pub fn schedule(self: *Sched, tf: *trap.TrapFrame) *trap.TrapFrame {
        std.log.debug("hi, 0x{x}", .{@intFromPtr(self.running.current())});
        self.running.current().?.tcb.sp = @intFromPtr(tf);

        const cur = self.running.advance();

        utils.timer.armMs(10);

        return cur.?.tcb.trapFrame();
    }

    pub export fn yeild(self: *Sched) void {
        const cur = self.running.current().?;
        const next = self.running.advance().?;

        arch.trap.yield(&cur.tcb.sp, next.tcb.sp);
    }

    pub fn removeTask(self: *Sched, task: *Task) void {
        task.prev.next = task.next;
        task.next.prev = task.prev;

        if (self.running == task) {
            self.running = task.next;
        }
    }

    pub fn kill(self: *Sched, task: *Task) void {
        const status = arch.enterCritical();
        defer arch.exitCritical(status);

        self.removeTask(task);
        task.state = .Dead;
        task.next = self.dead_list;
        self.dead_list = task;
    }

    pub fn performCleanup(self: *Sched) void {
        var current = self.dead_list;
        while (current) |task| {
            self.dead_list = task.next;
            if (task.allocator) |alloc| {
                alloc.free(task);
            }
            current = self.dead_list;
        }
    }
};
