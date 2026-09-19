--!strict
-- Remote Event manager using one RemoteEvent and one UnreliableRemoteEvent
-- Will make exploiters' life slightly harder to peek into the events
-- @ko5i on discord

-- dependencies
local Http = game:GetService("HttpService");
local ReplicatedStorage = game:GetService("ReplicatedStorage");
local Players = game:GetService("Players");
local this = {};

-- constants
local visualizeRemotesLol = false;

local remoteIds = {};
local remoteNames = {};
local events = {};
local connectedPlayers = {};
local waitingForPlayerConnections = {} :: {[Player]: {thread}};
local mainRemote = Instance.new("RemoteEvent");
mainRemote.Name = "MainRemote";
mainRemote.Parent = ReplicatedStorage;
local mainUnreliableRemote = Instance.new("UnreliableRemoteEvent");
mainUnreliableRemote.Name = "MainUnreliableRemote";
mainUnreliableRemote.Parent = ReplicatedStorage;

-- types
type Connection = {
	Disconnect : (self:Connection) -> ();
}
export type Signal = {
	Name : string;
	Id : string;
	Connect : (self:Signal, func:(Player, ...any)->()) -> Connection;
	Once : (self:Signal, func:(...any)->()) -> Connection;
	Invoke : (self:Signal, Targets:{Player}|Player?, ...any) -> ();
}


-- methods

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
local function receive(self:any, ...) : ()
	for i, c in ipairs(self.__onceconnections) do
		c(...);
		self.__onceconnections[i] = nil;
	end
	for _, c in ipairs(self.__connections) do
		c(...);
	end
end
-- No targets = fire all clients
local function _Fire(self:any, Targets:{Player}|Player?, ...) : ()
	if Targets then
		if typeof(Targets) == "Instance" and Targets:IsA("Player") then
			self.__remote:FireClient(Targets, self.Id, ...);
			return;
		end
		for _, player in ipairs(Targets) do
			self.__remote:FireClient(player, self.Id, ...);
		end
	else
		self.__remote:FireAllClients(self.Id, ...);
	end
end

-- ArgTypes follows this format:
-- {"arg1type", "arg2typeA|arg2typeB", ...};
-- Where "|" means "or".
-- In this example, argument 1 can only be arg1type, and argument 2 can be either arg2typeA or arg2typeB
-- This is used in strict typechecking for those stinky exploiters
function this.new(Name:string, Cooldown:number?, Unreliable:boolean?, ArgTypes:{string}?) : Signal
	assert(not remoteNames[Name], "Remote '"..Name.."' already exists");
	if visualizeRemotesLol then
		local v = Instance.new(Unreliable and "UnreliableRemoteEvent" or "RemoteEvent");
		v.Name = (Unreliable and "Unreliable__" or "Reliable__") .. Name
		v.Parent = ReplicatedStorage;
	end
	Name = ((Unreliable and "UN_") or "RE_") .. Name;

	local newId;
	repeat
		newId = Http:GenerateGUID();
	until not remoteIds[newId];
	remoteIds[newId] = Name;
	remoteNames[Name] = newId;

	mainRemote:FireAllClients(nil, newId, Name);

	local t = {
		__connections = {};
		__onceconnections = {};
		__cooldown = Cooldown;
		__invokeCooldowns = {};
		__argTypes = ArgTypes;
		__remote = (Unreliable and mainUnreliableRemote) or mainRemote;
		Name = Name;
		Id = newId;
		Connect = _Connect;
		Once = _Once;
		Invoke = _Fire;
	};
	events[newId] = t;
	return t;
end

function this.get(Name:string) : Signal?
	for _, event in pairs(events) do
		if event.Name == Name:sub(4) then
			return event;
		end
	end
	return nil;
end

function OnEvent(Player:Player, i:number, ...) : ()
	if not connectedPlayers[Player] then
		return;
	end
	if typeof(i) ~= "string" then
		Player:Kick();
		return;
	end

	local event = events[i];
	if not event then
		Player:Kick();
		return;
	end
	if event.__cooldown then
		local currentTick = os.clock();
		local cooldown = event.__invokeCooldowns[Player];
		if cooldown and cooldown > currentTick then
			return;
		end
		event.__invokeCooldowns[Player] = currentTick + event.__cooldown;
	end
	if event.__argTypes then
		local args = {...};
		for i, type in ipairs(event.__argTypes) do
			local nullable = false;
			if type:sub(-1) == "?" then
				nullable = true;
				type = type:sub(1, -2);
			end

			local arg = args[i];
			if typeof(arg) == type or (nullable and arg == nil) then
				continue;
			end

			warn("Invalid argument type ", event.__argTypes[i], typeof(arg), "\nCaller (likely an exploiter): ", Player.Name);
			Player:Kick();
			return;
		end
	end
	receive(event, Player, ...);
end

-- Yields the current thread until the client has synchronized with the server remotes
function this.WaitForPlayerReady(Player:Player) : ()
	if connectedPlayers[Player] then
		return;
	end
	if not waitingForPlayerConnections[Player] then
		waitingForPlayerConnections[Player] = {};
	end
	table.insert(waitingForPlayerConnections[Player], coroutine.running());
	return coroutine.yield();
end


-- setup
mainRemote.OnServerEvent:Connect(OnEvent);
mainUnreliableRemote.OnServerEvent:Connect(OnEvent);

local ClientConnectionRemote = Instance.new("RemoteEvent");
ClientConnectionRemote.Name = "connect";
ClientConnectionRemote.OnServerEvent:Connect(function(Player)
	local state = connectedPlayers[Player];
	if state == true then
		Player:Kick();
		return;
	elseif state == nil then
		print("⚡ Player connection has begun for ", Player);
		connectedPlayers[Player] = false;
		mainRemote:FireClient(Player, nil, remoteIds);
	elseif state == false then
		connectedPlayers[Player] = true;
		if waitingForPlayerConnections[Player] then
			for _, cnn in ipairs(waitingForPlayerConnections[Player]) do
				coroutine.resume(cnn);
			end
		end
		print("⚡ "..Player.Name.." has connected successfully and is listening for events");
	end
end);
ClientConnectionRemote.Parent = game:GetService("ReplicatedStorage");

--[[Players.PlayerAdded:Connect(function(Player:Player)
	task.wait(3);
	mainRemote:FireClient(Player, nil, remoteIds);
end)]]

table.freeze(this);
return this;
