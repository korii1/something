--!strict
-- Remote Event manager using one RemoteEvent and one UnreliableRemoteEvent
-- Will make exploiters' life slightly harder to peek into the events
-- @ko5i on discord

local ReplicatedStorage = game:GetService("ReplicatedStorage");
local LocalPlayer = game:GetService("Players").LocalPlayer;
local this = {};

local dat;
local events = {};
local waitingForLoad = {} :: {thread};
local waitingForLoadP = {} :: {thread};

local connect = ReplicatedStorage:WaitForChild("connect") :: RemoteEvent;
local expectedRemotes = 0;
local createdRemotes = 0;
local readySent = false;
local loaded = false;

local mainRemote = ReplicatedStorage:WaitForChild("MainRemote") :: RemoteEvent;
mainRemote.Name = tostring(math.random()):sub(3);
local mainUnreliableRemote = ReplicatedStorage:WaitForChild("MainUnreliableRemote") :: UnreliableRemoteEvent;
mainUnreliableRemote.Name = tostring(math.random()):sub(3);

mainRemote.OnClientEvent:Connect(function(i, a, b)
	if not i then
		if typeof(a) == "table" then
			dat = a;
			for _, thread in ipairs(waitingForLoadP) do
				coroutine.resume(thread);
			end
			for _, thread in ipairs(waitingForLoad) do
				coroutine.resume(thread);
			end
			print("⚡ Received remote data!");
		else
			if not readySent then
				table.insert(waitingForLoadP, coroutine.running());
				coroutine.yield();
			end
			dat[a] = b;
		end
	end
end)

type Connection = {
	Disconnect : (self:Connection) -> ();
}
type Signal = {
	Connect : (self:Signal, func:(...any)->()) -> Connection;
	Wait : (self:Signal) -> ...any;
	Once : (self:Signal, func:(...any)->()) -> Connection;
	Invoke : (self:Signal, ...any) -> ();
}

local function _Disconnect(self:any) : ()
	if self.__once then
		self.__signal.__onceconnections[self.__i] = nil;
		return;
	end
	self.__signal.__connections[self.__i] = nil;
end
local function _Connect(self:any, func:(...any)->()) : Connection
	local i = table.maxn(self.__connections) + 1;
	self.__connections[i] = func;
	return {
		__signal = self;
		__i = i;
		Disconnect = _Disconnect;
	};
end
local function _Once(self:any, func:(...any)->()) : Connection
	local i = table.maxn(self.__onceconnections) + 1;
	self.__onceconnections[i] = func;
	return {
		__signal = self;
		__i = i;
		Disconnect = _Disconnect;
	};
end
local function _Wait(self:any) : ...any
	local t = {hasFired = false} :: any;
	table.insert(self.__onceconnections, t);
	repeat
		task.wait(1);
	until t.hasFired;
	return (t.r and table.unpack(t.r)) or nil;
end
local function receive(self:any, ...) : ()
	for i, c in ipairs(self.__waitconnections) do
		c.r = {...};
		c.hasFired = true;
		self.__waitconnections[i] = nil;
	end
	for i, c in ipairs(self.__onceconnections) do
		c(...);
		self.__onceconnections[i] = nil;
	end
	for _, c in ipairs(self.__connections) do
		c(...);
	end
end
local function _Fire(self:any, ...) : ()
	if not loaded then
		table.insert(waitingForLoad, coroutine.running());
		coroutine.yield();
	end
	self.__remote:FireServer(self.__n, ...);
end

function this.new(n:string) : Signal
	if not loaded then
		table.insert(waitingForLoad, coroutine.running());
		coroutine.yield();
	end
	expectedRemotes += 1;

	local i;
	local un;
	for si, v in pairs(dat) do
		if v:sub(4) == n then
			i = si;
			un = v:sub(1, 3) == "UN_";
		end
	end
	assert(i, "Failed to create event '"..n.."'");

	local t = {
		__n = i;
		__connections = {};
		__onceconnections = {};
		__waitconnections = {};
		__remote = (un and mainUnreliableRemote) or mainRemote;
		Connect = _Connect;
		Once = _Once;
		Wait = _Wait;
		Invoke = _Fire;
	};
	table.insert(events, t);

	createdRemotes += 1;
	if not readySent and createdRemotes == expectedRemotes then
		readySent = true;
		connect:FireServer();
		task.wait(1 + LocalPlayer:GetNetworkPing() * 10);
		loaded = true;
		print("⚡ I am ready to listen for events!");
	end
	return t;
end

function OnReceive(i, ...) : ()
	if not i then
		return;
	end
	for _, event in ipairs(events) do
		if event.__n == i then
			receive(event, ...);
		end
	end
end
mainRemote.OnClientEvent:Connect(OnReceive);
mainUnreliableRemote.OnClientEvent:Connect(OnReceive);
connect:FireServer();

return this;
