
local MockSocket = {}
MockSocket.__index = MockSocket

function MockSocket.new(bytes, ty)
    return setmetatable({
        bytes = bytes,
        offset = 1,
        send_space = -1,
        calls = {},
        closed = false,
        accept_queue = {},
        accept_idx = 1,
        ty = ty or "unconnected",
        connect_error = nil,
        peername = { "127.0.0.1", 80 },
        birthday = os.time(),
    }, MockSocket)
end

--#region Internals

function MockSocket:record_call(name, args, rets)
    table.insert(self.calls, {
        name = name,
        args = args,
        rets = rets,
    })
end
local function inner_accept(self)
    if self.closed then
        return nil, "closed"
    end
    local ret = self.accept_queue[self.accept_idx]
    local err = nil
    if not ret then
        return nil, "timeout"
    end
    self.accept_idx = self.accept_idx + 1
    return ret, err
end

local function inner_bind(self)
    if self.closed then
        return nil, "closed"
    end
    if self.error_on_bind then
        return nil, self.error_on_bind
    end
    return 1
end

local function inner_connect(self)
    if self.closed then
        return nil, "closed"
    end
    if self.connect_error then
        return nil, self.connect_error
    end
    self.ty = "client"
    return 1
end

local function inner_getpeername(self)
    if self.closed then
        return nil, "closed"
    end
    if self.ty ~= "client" then
        return nil, "getpeername called on bad self: " .. tostring(self.ty)
    end
    if self.peername then
        return table.unpack(self.peername)
    end
    return nil, "timeout"
end

local function inner_getsockname(self)
    if self.closed then
        return nil, "closed"
    end
    if self.sockname then
        return table.unpack(self.sockname)
    end
    return "0.0.0.0", 0, "inet"
end

local function inner_getstats(self)
    if self.closed then
        return nil, "closed"
    end
    if self.ty == "unconnected" then
        return nil, "calling getstats on bad self: " .. tostring(self.ty)
    end
    if self.stats then
        return table.unpack(self.stats)
    end
    local recv, sent, birthday = 0, 0, self.birthday
    for _, call in ipairs(self.calls) do
        if call.name == "receive" then
            recv = recv + #(call.rets[1] or call.rets[3] or "")
        end
        if call.name == "send" then
            sent = sent + call.rets[1] or call.rets[3] or 0
        end
    end
    local birthday = os.difftime(os.time(), self.birthday or os.time())
    return recv, sent, birthday
end

local function inner_setoption(self, name, value)
    if self.closed then
        return nil, "closed"
    end
    if self.ty == "unconnected" then
        return nil, "setoption called on bad self: "..tostring(self.ty)
    end
    if self.options_errors[name] then
        return nil, self.options_errors[name]
    end
    return 1
end

local function inner_listen(self, backlog)
    if self.closed then
        return nil, "closed"
    end
    if self.ty ~= "unconnected" then
        return nil, "listen called on bad self: "..tostring(self.ty)
    end
    if self.listen_error then
        return nil, self.listen_error
    end
    self.ty = "server"
    return 1
end

local function inner_setstats(self, recv, send, birthday)
    if self.closed then
        return nil, "closed"
    end
    self.stats = table.pack(recv, send, birthday)
end

local function inner_settimeout(self, timeout)
    if self.closed then
        return nil, "closed"
    end
    self.timeout = timeout
end

local function inner_shutdown(self, mode)
    self.closed = true
    return 1
end

local function inner_recv(self, pattern)
    if self.closed then
        return nil, "closed"
    end
    if self.ty ~= "client" then
        return nil, "receive on bad self: " .. tostring(self.ty)
    end
    if self.offset > #self.bytes then
        return nil, "timeout"
    end
    pattern = pattern or "*l"
    local s = string.sub(self.bytes, self.offset)
    if pattern == "*l" then
        local chunk, crlf = string.match(s, "([^\r\n]*)(\r?\n)")
        if not chunk then
            chunk = string.sub(s, 1)
            self.offset = #self.bytes
            return nil, "timeout", chunk
        end
        self.offset = self.offset + #chunk + #crlf
        return chunk
    elseif pattern == "*a" then
        self.closed = true
        return s
    elseif type(pattern) == "number" then
        local chunk = string.sub(s, 1, pattern)
        self.offset = self.offset + #(chunk or "")
        if not chunk or #chunk < pattern then
            return nil, "timeout", chunk
        end
        return chunk
    end
    return nil, "invalid pattern must be '*l', '*a' or a number found "..type(pattern)
end

local function inner_send(self, bytes, i, j)
    if self.closed then
        return nil, "closed"
    end
    if self.ty ~= "client" then
        return nil, "send on bad self: " .. tostring(self.ty)
    end
    if self.send_space == 0 then
        return nil, "timeout"
    end
    local tosend = bytes
    if i then
        tosend = string.sub(tosend, i, j)
    end
    if self.send_space < 0 then
        table.insert(self.sent, tosend)
        return 1
    end
    if #tosend > self.send_space then
        tosend = string.sub(tosend, 1, self.send_space)
    end
    self.send_space = math.max(self.send_space - #tosend, 0)
    table.insert(self.sent, tosend)
    return #tosend
end

--#endregion
--#region MockMethods

function MockSocket:accept(...)
    local rets = table.pack(inner_accept(self))
    self:record_call("accept", table.pack(...), rets)
    return table.unpack(rets)
end

function MockSocket:bind(...)
    local rets = table.pack(inner_bind(self, ...))
    self:record_call("bind", table.pack(...), rets)
    return table.unpack(rets)
end

function MockSocket:close(...)
    self:record_call("close", table.pack(...), { 1 })
    return 1
end

function MockSocket:connect(...)
    local rets = table.pack(inner_connect(self))
    self:record_call("connect", table.pack(...), rets)
    return table.unpack(rets)
end

function MockSocket:getpeername(...)
    local rets = table.pack(inner_getpeername(self, ...))
    self:record_call("getpeername", table.pack(...), rets)
    return table.unpack(rets)
end

function MockSocket:getsockname(...)
    local rets = table.pack(inner_getsockname(self, ...))
    self:record_call("getsockname", table.pack(...), rets)
    return table.unpack(rets)
end

function MockSocket:getstats(...)
    local rets = table.pack(inner_getstats(self, ...))
    self:record_call("getstats", table.pack(...), rets)
    return table.unpack(rets)
end

function MockSocket:listen(...)
    local rets = table.pack(inner_listen(self, ...))
    self:record_call("listen", table.pack(...), rets)
    return table.unpack(rets)
end

function MockSocket:setoption(...)
    local rets = table.pack(inner_setoption(self, ...))
    self:record_call("setoption", table.pack(...), rets)
    return table.unpack(rets)
end

function MockSocket:setstats(...)
    local rets = table.pack(inner_setstats(self, ...))
    self:record_call("setstats", table.pack(...), rets)
    return table.unpack(rets)
end

function MockSocket:settimeout(...)
    local rets = table.pack(inner_settimeout(self, ...))
    self:record_call("settimeout", table.pack(...), rets)
    return table.unpack(rets)
end

function MockSocket:receive(...)
    local rets = table.pack(inner_recv(self, ...))
    self:record_call("receive", table.pack(...), rets)
    return table.unpack(rets)
end

function MockSocket:send(...)
    local rets = table.pack(inner_send(self, ...))
    self:record_call("send", table.pack(...), rets)
    return table.unpack(rets)
end

function MockSocket:shutdown(...)
    local rets = table.pack(inner_shutdown(self, ...))
    self:record_call("shutdown", table.pack(...), {})
    return table.unpack(rets)
end

--#endregion
--#region MockControls

function MockSocket:remote_close()
    self.close = true
end

function MockSocket:push_recv_bytes(bytes)
    self.bytes = self.bytes .. (bytes or "")
end

function MockSocket:push_accept_sock(bytes)
    table.insert(self.accept_queue, MockSocket.new(bytes, "client"))
    return self
end

function MockSocket:push_accepted_bytes(bytes, idx)
    local accepted = self.accept_queue[idx]
    if accepted then
        accepted:push_recv_bytes(bytes)
    end
end

function MockSocket:remote_close_accepted(idx)
    local accepted = self.accept_queue[idx]
    if accepted then
        accepted:remote_close()
    end
end

function MockSocket:limit_send(by)
    self.send_space = by
    return self
end

function MockSocket:connect_should_error(error)
    self.connect_error = error or "timeout"
    return self
end

function MockSocket:set_peer(ip, port)
    if ip or port then
        self.peer = table.pack(ip, port)
    end
    self.peer = nil
    return self
end

function MockSocket:error_for_option(name, err)
    self.options_errors[name] = err
    return self
end

--#endregion

return {
    MockSocket = MockSocket,
}
