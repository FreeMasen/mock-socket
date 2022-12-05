local mock_socket = require "mock-socket"
local http_empty_json = "HTTP/1.1 200 Ok\r\nContent-Type: application/json\r\n\r\n{}\n"
describe("MockSocket.tcp", function()
    it("recieve lines works #a", function()
        local mock = mock_socket.MockSocket.new(http_empty_json)
        mock:connect("192.168.1.1", 80)
        local first = assert(mock:receive())
        assert.are.equal("HTTP/1.1 200 Ok", first or nil)
        assert.are.equal("Content-Type: application/json", mock:receive("*l") or nil)
        assert.are.equal("", mock:receive() or nil)
        assert.are.equal("{}", mock:receive() or nil)
    end)
    it("recieve all works", function()
        local mock = mock_socket.MockSocket.new(http_empty_json)
        mock:connect("192.168.1.1", 80)
        local received = assert(mock:receive("*a"))
        assert.are.equal(http_empty_json, received)
        local _bytes, err = mock:receive("*a")
        assert.are.equal(nil, _bytes or nil)
        assert.are.equal("closed", err)
    end)
    it("recieve mixed works", function()
        local mock = mock_socket.MockSocket.new(http_empty_json)
        mock:connect("192.168.1.1", 80)
        local first = assert(mock:receive())
        assert.are.equal("HTTP/1.1 200 Ok", first or nil)
        local rest = assert(mock:receive("*a"))
        assert.are.equal(string.sub(http_empty_json, #first + 3), rest)
        local _bytes, err = mock:receive("*a")
        assert.are.equal(nil, _bytes or nil)
        assert.are.equal("closed", err)
    end)
    it("timeout when not enough bytes", function()
        local mock = mock_socket.MockSocket.new("12345")
        mock:connect("192.168.1.1", 80)
        local bytes, err, part = mock:receive(6)
        assert.are.equal(nil, bytes or nil)
        assert.are.equal("timeout", err or nil)
        assert.are.equal("12345", part)
        mock:push_recv_bytes("123456")
        bytes, err, part = mock:receive(6)
        assert.are.equal("123456", bytes)
        assert.is.falsy(err or nil)
        assert.is.falsy(part or nil)
    end)
    it("record calls works", function()
        local mock = mock_socket.MockSocket.new("12345\n123456\n00000")
        mock:connect("192.168.1.1", 80)
        assert(mock:receive())
        assert(mock:receive("*l"))
        assert(mock:receive(5))
        mock:receive(1)
        mock:push_recv_bytes("0000")
        assert(mock:receive("*a"))
        mock:receive()
        local expectations = {
            { args = table.pack(), rets = table.pack("12345"), name = "receive" },
            { args = table.pack("*l"), rets = table.pack("123456"), name = "receive" },
            { args = table.pack(5), rets = table.pack("00000"), name = "receive" },
            { args = table.pack(1), rets = table.pack(nil, "timeout"), name = "receive" },
            { args = table.pack("*a"), rets = table.pack("0000"), name = "receive" },
            { args = table.pack(), rets = table.pack(nil, "closed"), name = "receive" },
        }
        for i = 1, #expectations do
            -- +1 to skip the connect call
            local call = mock.calls[i+1]
            assert.are.same(expectations[i], call)
        end
    end)
end)
