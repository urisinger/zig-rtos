const root = @import("root");
const std = @import("std");
const arch = root.arch;
const trap = arch.trap;

const TaskState = enum { Running, Sleeping, Dead };
pub const Task = struct {
    tcb: TaskControl,
    state: TaskState,
    next: *Task,
    prev: *Task,

    allocator: ?*std.mem.Allocator,

    // base must be alligned to the aligment of Task
    pub fn init(mem: []align(16) u8, entry: *const fn () void) *Task {
        const task: *Task = @ptrCast(mem.ptr);
        task.state = .Running;
        task.next = task;
        task.prev = task;

        task.tcb.sp = (@intFromPtr(mem.ptr) + @sizeOf(Task) + mem.len);

        const tf = task.tcb.trapFrame();
        tf.init(@intFromPtr(entry));

        return task;
    }
};

const TaskControl = struct {
    sp: usize,

    pub inline fn trapFrame(self: *TaskControl) *trap.TrapFrame {
        return @ptrFromInt(self.sp);
    }
};

pub const Sched = struct {
    running: *Task,
    idle_task: *Task,
    dead_list: ?*Task = null,

    pub fn init(idle_task: *Task) Sched {
        return Sched{
            .running = idle_task,
            .idle_task = idle_task,
        };
    }

    pub fn addTask(self: *Sched, task: *Task) void {
        const head = self.running;
        task.next = head.next;
        task.prev = head;
        head.next.prev = task;
        head.next = task;
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
        self.running.tcb.sp = @intFromPtr(tf);
        self.running = self.running.next;

        root.timer.armMs(5);
        return self.running.tcb.trapFrame();
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
