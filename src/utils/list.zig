const std = @import("std");

// Doubly linked circular linked list, require that T has fields next and prev with type ?*T
pub fn CircularList(comptime T: type) type {
    return struct {
        const Self = @This();

        head: ?*T,

        pub fn init(first: *T) Self {
            first.next = first;
            first.prev = first;
            return .{ .head = first };
        }

        pub fn printAll(self: *Self) void {
            const head = self.head orelse return; // Handle empty list

            var cur = head;
            while (true) {
                std.log.info("Node: {any}", .{cur.*});

                cur = cur.next orelse break; // Safety check

                // Circular termination condition: back at the start
                if (cur == head) break;
            }
        }

        pub inline fn insertFirst(self: *Self, node: *T) void {
            if (self.head) |head| {
                self.insert(head, node);
            } else {
                node.next = node;
                node.prev = node;
                self.head = node;
            }
        }

        pub inline fn insert(self: *Self, after: *T, node: *T) void {
            _ = self;
            node.next = after.next;
            node.prev = after;
            after.next.?.prev = node;
            after.next = node;
        }

        pub inline fn remove(self: *Self, node: *T) void {
            if (node.next == node) {
                self.head = null;
            } else {
                node.next.?.prev = node.prev;
                node.prev.?.next = node.next;
                if (self.head == node) self.head = node.next;
            }
            node.next = null;
            node.prev = null;
        }

        pub inline fn advance(self: *Self) ?*T {
            if (self.head) |head| {
                self.head = head.next;
            }
            return self.head;
        }

        pub inline fn current(self: *Self) ?*T {
            return self.head;
        }
    };
}

// Requires T to have field next with type ?*T
pub fn List(comptime T: type) type {
    return struct {
        const Self = @This();

        top: ?*T = null,

        pub fn push(self: *Self, node: *T) void {
            node.next = self.top;
            self.top = node;
        }

        pub fn pop(self: *Self) ?*T {
            if (self.top) |top| {
                top = top.next;
                return top;
            }
            return null;
        }
    };
}
