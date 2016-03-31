import std.algorithm;
import std.array;
import std.conv;
import std.datetime;
import std.string;
import asynchronous;

class TestHelper
{
    private Appender!(string[]) actualEvents_;

    private Connection[] connections_;

    private Server server_;

    void putEvent(string event)
    {
        actualEvents_.put(event);
    }

    void addConnection(Connection connection)
    {
        connections_ ~= connection;
    }

    @property
    Server server()
    {
        return server_;
    }

    @property
    void server(Server server)
    in
    {
        assert(server !is null);
        assert(server_ is null);
    }
    body
    {
        server_ = server;
    }

    string[] actualEvents()
    {
       return actualEvents_.data;
    }

    Connection[] connections()
    {
        return connections_;
    }
}

class Connection : Protocol
{
    string name;
    Transport transport;
    TestHelper testHelper;

    this(string name, TestHelper testHelper)
    {
        this.name = name;
        this.testHelper = testHelper;
    }

    void connectionMade(BaseTransport transport)
    {
        this.transport = cast(Transport) transport;
        testHelper.addConnection(this);
        testHelper.putEvent(name ~ ": connectionMade");
    }

    void connectionLost(Exception exception)
    {
        testHelper.putEvent(name ~ ": connectionLost");
    }

    void pauseWriting()
    {
        testHelper.putEvent(name ~ ": pauseWriting");
    }

    void resumeWriting()
    {
        testHelper.putEvent(name ~ ": resumeWriting");
    }

    void dataReceived(const(void)[] data)
    {
        testHelper.putEvent(name ~ ": dataReceived '%s'".format(data.to!string));
    }

    bool eofReceived()
    {
        testHelper.putEvent(name ~ ": eofReceived");
        return false;
    }
}

@Coroutine
void tearDown(TestHelper testHelper)
{
    testHelper.server.close;
    testHelper.server.waitClosed;

    foreach (connection; testHelper.connections)
        connection.transport.close;
}

@Coroutine
void createConnection(TestHelper testHelper)
{
    auto loop = getEventLoop;
    testHelper.server = loop.createServer(() => new Connection("server", testHelper), "localhost", "8038");
    auto client = loop.createConnection(() => new Connection("client", testHelper), "localhost", "8038");
}

unittest
{
    // setup
    auto loop = getEventLoop;
    auto testHelper = new TestHelper();
    string[] expectedEvents = [
        "client: connectionMade",
        "server: connectionMade",
    ];

    // tear down
    scope (exit)
    {
        loop.runUntilComplete(loop.createTask(() => testHelper.tearDown));
    }

    // execute
    loop.runUntilComplete(loop.createTask(() => testHelper.createConnection));

    // verify
    assert(testHelper.actualEvents == expectedEvents);
}

@Coroutine
void sendToServer(TestHelper testHelper, string message)
{
    Connection clientConnection = testHelper.connections.find!(c => c.name == "client")[0];

    clientConnection.transport.write(message);

    getEventLoop.sleep(10.msecs);
}

unittest
{
    // setup
    auto loop = getEventLoop;
    auto testHelper = new TestHelper();
    string[] expectedEvents = [
        "client: connectionMade",
        "server: connectionMade",
        "server: dataReceived 'foo'",
    ];
    // tear down
    scope (exit)
    {
        loop.runUntilComplete(loop.createTask(() => testHelper.tearDown));
    }

    // execute
    loop.runUntilComplete(loop.createTask(() => testHelper.createConnection));
    loop.runUntilComplete(loop.createTask(() => testHelper.sendToServer("foo")));

    // verify
    assert(testHelper.actualEvents == expectedEvents);
}

@Coroutine
void sendToClient(TestHelper testHelper, string message)
{
    Connection serverConnection = testHelper.connections.find!(c => c.name == "server")[0];

    serverConnection.transport.write(message);

    getEventLoop.sleep(10.msecs);
}

unittest
{
    // setup
    auto loop = getEventLoop;
    auto testHelper = new TestHelper();
    string[] expectedEvents = [
        "client: connectionMade",
        "server: connectionMade",
        "client: dataReceived 'foo'",
    ];

    // tear down
    scope (exit)
    {
        loop.runUntilComplete(loop.createTask(() => testHelper.tearDown));
    }

    // execute
    loop.runUntilComplete(loop.createTask(() => testHelper.createConnection));
    loop.runUntilComplete(loop.createTask(() => testHelper.sendToClient("foo")));

    // verify
    assert(testHelper.actualEvents == expectedEvents);
}

@Coroutine
void createUnixConnection(TestHelper testHelper)
{
    auto loop = getEventLoop;
    testHelper.server = loop.createUnixServer(() => new Connection("server", testHelper), "unix.socket");
    auto client = loop.createUnixConnection(() => new Connection("client", testHelper), "unix.socket");
}

version (Posix)
version (Libasync_supports_unix_sockets)
unittest
{
    // setup
    auto loop = getEventLoop;
    auto testHelper = new TestHelper();
    string[] expectedEvents = [
        "client: connectionMade",
        "server: connectionMade",
    ];

    // tear down
    scope (exit)
    {
        loop.runUntilComplete(loop.createTask(() => testHelper.tearDown));
        import std.file : remove;
        remove("unix.socket");
    }

    // execute
    loop.runUntilComplete(loop.createTask(() => testHelper.createUnixConnection));

    // verify
    assert(testHelper.actualEvents == expectedEvents);
}

version (Posix)
version (Libasync_supports_unix_sockets)
unittest
{
    // setup
    auto loop = getEventLoop;
    auto testHelper = new TestHelper();
    string[] expectedEvents = [
        "client: connectionMade",
        "server: connectionMade",
        "server: dataReceived 'foo'",
    ];

    // tear down
    scope (exit)
    {
        loop.runUntilComplete(loop.createTask(() => testHelper.tearDown));
        import std.file : remove;
        remove("unix.socket");
    }

    // execute
    loop.runUntilComplete(loop.createTask(() => testHelper.createUnixConnection));
    loop.runUntilComplete(loop.createTask(() => testHelper.sendToServer("foo")));

    // verify
    assert(testHelper.actualEvents == expectedEvents);

    // tear down
    loop.runUntilComplete(loop.createTask(() => testHelper.tearDown));
}

version (Posix)
version (Libasync_supports_unix_sockets)
unittest
{
    // setup
    auto loop = getEventLoop;
    auto testHelper = new TestHelper();
    string[] expectedEvents = [
        "client: connectionMade",
        "server: connectionMade",
        "client: dataReceived 'foo'",
    ];

    // tear down
    scope (exit)
    {
        loop.runUntilComplete(loop.createTask(() => testHelper.tearDown));
        import std.file : remove;
        remove("unix.socket");
    }

    // execute
    loop.runUntilComplete(loop.createTask(() => testHelper.createUnixConnection));
    loop.runUntilComplete(loop.createTask(() => testHelper.sendToClient("foo")));

    // verify
    assert(testHelper.actualEvents == expectedEvents);
}
