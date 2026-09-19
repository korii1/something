--!strict
--optimize 2
-- Custom Signal module designed to function just like bindable events
-- Along with a workaround for autocomplete in studio :D
-- @k05i on discord

-- CONSTANT
local Connection;
local Event;
local Signal;
type _Connection = typeof(Connection);
type _Event = typeof(Event);
type _Signal = typeof(Signal);
const any = nil :: any;
type anyFunc = (...any)->();
type exFunc = ((self:any)->()) & any;
type exWaitFunc = ((self:any)->...any) & any;

-- VARIABLE
local freeThread : thread?;


-- MAIN

const function runCallback(fn: anyFunc, ...) : ()
	local thread = freeThread;
	freeThread = nil;
	
	const success:boolean, err:string? = xpcall(fn, debug.traceback, ...);
	if not success then
		task.spawn(error, "Signal connection callback error: "..(err or "?"));
	end
	
	freeThread = freeThread or thread;
end

const function runCallbackInFreeThread(...) : ()
	runCallback(...);
	while true do
		runCallback(coroutine.yield());
	end
end


-- Connection Class
Connection = {};
Connection._connected	= false	:: boolean;
Connection._next		= nil	:: _Connection?;
Connection._signal		= any	:: _Signal;
Connection._fn			= any	:: (...any)->();

function Connection.Disconnect(self: _Connection) : ()
	assert(self._connected, "Cannot disconnect a connection twice");
	self._connected	= false;
	
	if self._signal._connectionHead == self then
		self._signal._connectionHead = self._next;
		return;
	end
	
	local current = self._signal._connectionHead;
	while current do
		if current._next == self then
			current._next = self._next;
			return;
		end
		current = current._next;
	end
end

(Connection::any).__index = Connection;


-- Event Class
Event = {};
Event._signal	= any :: _Signal;

function Event.Connect(self: _Event, func: anyFunc) : (_Connection)
	assert(typeof(func)=="function", "Signal.Event:Connect() expects an argument of type function, given '"..typeof(func).."'");
	
	const connection = setmetatable({
		_connected	= true;
		_signal		= self._signal;
		_fn			= func;
		_next		= self._signal._connectionHead;
	}, Connection);
	self._signal._connectionHead = connection :: any;
	
	return connection :: any;
end

function Event.Once(self: _Event, func: anyFunc) : (_Connection)
	assert(typeof(func)=="function", "Signal.Event:Once() expects an argument of type function, given '"..typeof(func).."'");
	
	local cn;
	cn = self:Connect(function(...)
		cn:Disconnect();
		func(...);
	end)
	
	return cn;
end

function Event.Wait(self: _Event) : (...any)
	const t = coroutine.running();
	
	self:Once(function(...)
		task.spawn(t, ...);
	end)
	
	return coroutine.yield();
end

(Event::any).__index = Event;


-- Signal Class
Signal = {};
Signal._connectionHead	= nil :: _Connection?;

function Signal.DisconnectAll(self: _Signal) : ()
	self._connectionHead = nil;
end

function Signal.Fire(self: _Signal, ...) : ()
	local i = self._connectionHead;
	while i do
		if i._connected then
			if not freeThread then
				freeThread = coroutine.create(runCallbackInFreeThread);
			end
			task.spawn(freeThread::thread, i._fn, ...);
		end
		i = i._next;
	end
end

(Signal::any).__index = Signal;


-- SETUP

const Content = {};

function Content.new() : (Signal<anyFunc, exFunc, exWaitFunc>)
	const signal = {
		_connectionHead = nil;
	};
	
	signal.Event = setmetatable({
		_signal = signal;
	}, Event);
	
	return setmetatable(signal, Signal) :: any;
end

export type Connection = { Disconnect : (self:any) -> (); };
export type Event<fnc, wait> = {
	Connect : (self:any, func:fnc) -> Connection;
	Once : (self:any, func:fnc) -> Connection;
	Wait : wait;
};
export type Signal<fnc, fire, wait> = {
	Fire : fire;
	DisconnectAll : (self:any) -> ();
	Event : Event<fnc, wait>;
}

if false then -- THIS IS AN EXAMPLE ↓↓↓
	local test = Content.new()
	:: Signal<
		(var:number)->(), -- Used in :Connect(your:vars), :Once(your:vars), etc.
		(self:any, var:number)->(), -- Used in :Fire(self:any, your:vars)
		(self:any) -> (number, ...any) -- Used in :Wait()
	>;
	
	test:Fire("this is an invalid argument");
	test.Event:Connect(function() end):Disconnect();
	test.Event:Wait(); -- This will yield infinitely lol
end

return Content;
