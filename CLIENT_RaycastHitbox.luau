--!strict
-- Raycast Hitbox system meant for melee weapons
-- @ko5i on discord

-- dependencies
local PlayersService = game:GetService("Players");
local Cacher = require(game.Utils.ObjectCaching);
local class = require(game.Utils.Class);
local RemoteManager = require("./RemoteManager");
local ItemManager = require("../Character/ItemManager");
local HookManager = require("./HookManager");
local Rainbow = require("../VFX/Rainbow");

-- types
export type Hitbox = {
	ClassName : "ClientRaycastHitbox";
	Obj : Instance;
	Params : RaycastParams?;
	CustomData : {[any]:any};
	MaxHits : number?;
	MaxHitsPerTarget : number?;
	StopOnWallHit : boolean;
	
	Cast : (self:Hitbox, Duration:number) -> ();
	Cancel : (self:Hitbox) -> ();
	Hit : HookManager.Hook;
};

-- variables

local this = {
	ChecksPerSecond = 60;
	RayLineColor = Color3.new(1, 0, .3);
	RayLineRainbow = false;
	RayLinesEnabled = true;
};
local cache = {} :: {[Instance]:Hitbox};

local localPlayer = PlayersService.LocalPlayer;
local HitboxAddedEvent = HookManager.new("RaycastHitboxCreated");
local mainRemote = RemoteManager.new("RaycastHitboxMain");
local hitRemote = RemoteManager.new("RaycastHitboxHit");
local linesPool : Cacher.ObjectCacher;
local rainbow = Rainbow.new({.1, .2, .3, .4, .5, .6, .7, .8, .9, 1}, .8, .7, 6);
local rainbowConnections = {};

local defaultParams = RaycastParams.new();
defaultParams.CollisionGroup = "CollideWithEverything";
local filterInst = {workspace.Terrain, workspace.Scripted, workspace.Map, workspace.temp};

local canHurtAlly = ItemManager.canHurtAlly;

-- class
local CastLoop;
local Hitbox = class{
	ClassName = "ClientRaycastHitbox";
	Obj = nil;
	Params = defaultParams;
	CustomData = nil;
	MaxHits = 4;
	MaxHitsPerTarget = 1;
	StopOnWallHit = true;
	
	Hit = nil;
	
	Cast = function(self:Hitbox & any, Duration:number)
		if self.castId then
			self:Cancel();
		end
		table.clear(self.hitTargets);
		--if not table.find(self.Params.FilterDescendantsInstances, localPlayer.Character) then
		--	table.insert(self.Params.FilterDescendantsInstances, localPlayer.Character);
		--end
		
		self._loopThread = task.spawn(CastLoop, self, Duration);
		task.delay(Duration, self.Cancel::any, self, tick);
	end;
	
	Cancel = function(self:Hitbox & any, castId:number?)
		if (not castId) or (self.castId == castId) then
			pcall(task.cancel, self._loopThread);
			self.castId = nil;
		end
	end,
	
	new = function(self:Hitbox & any, Obj:Instance, Params:RaycastParams?)
		self.Obj = Obj;
		self.Params = Params or defaultParams;
		if not Params then
			local filter = table.clone(filterInst);
			table.insert(filter, Obj);
			table.insert(filter, localPlayer.Character);
			self.Params.FilterDescendantsInstances = filter;
		end
		cache[Obj] = self;
		self.CustomData = {};
		self.hitTargets = {};
		self.Hit = HookManager.new();
		HitboxAddedEvent:Fire(self);
	end;
	
	hits = 0;
	_loopThread = nil;
} :: {new : (Obj:Instance, Params:RaycastParams?) -> Hitbox};

-- methods
function CastLoop(self:Hitbox & any, Duration:number) : ()
	local hitPoints = {} :: {Attachment};
	for _, v in ipairs(self.Obj:GetDescendants()) do
		if v:IsA("Attachment") and v.Name == "HitPoint" then
			table.insert(hitPoints, v);
		end
	end
	if not this.RayLineRainbow then
		for i, c in pairs(rainbowConnections) do
			c:Disconnect();
			rainbowConnections[i] = nil;
		end
	end
	
	local castId = time();
	local time = 1/this.ChecksPerSecond;
	local pointPos = {};
	for _, p in ipairs(hitPoints) do
		pointPos[p] = p.WorldPosition;
	end
	self.castId = castId;
	for i=0, Duration, time do
		task.wait(time);
		if castId ~= self.castId then
			break;
		end
		for p, pos in pairs(pointPos) do
			local dir = p.WorldPosition-pos;
			local cast = workspace:Raycast(pos, dir, self.Params);
			local hit : Humanoid?;
			
			local line;
			if this.RayLinesEnabled then
				line = linesPool:Pull() :: Part;
				if this.RayLineRainbow and not rainbowConnections[line] then
					rainbowConnections[line] = rainbow:Bind(line);
				end
				line.CFrame = CFrame.new(pos + (dir/2), p.WorldPosition);
				line.Size = Vector3.new(0.02, 0.02, dir.Magnitude);
				line.Color = this.RayLineColor;
				line.Parent = workspace.temp;
				task.defer(linesPool.Store, linesPool, line, 1);
			end
			pointPos[p] = p.WorldPosition;

			if cast then
				hitRemote:Invoke(
					self.Obj,
					cast.Instance,
					cast.Position, dir, cast.Normal
				);
				hit = cast.Instance.Parent:FindFirstChildOfClass("Humanoid");
				if hit then
					local target = PlayersService:GetPlayerFromCharacter(hit.Parent) or hit.Parent;
					
					if target:GetAttribute("Team") == localPlayer.Team and not canHurtAlly(localPlayer, target) then
						hit = nil;
					else
						local tgData = self.hitTargets[hit];
						if (tgData or 0) == self.MaxHitsPerTarget then
							continue;
						else
							self.hitTargets[hit] = (tgData or 0) + 1;
						end
					end
				end

				self.Hit:Fire(self, cast, hit);

				if hit then
					if line then
						if rainbowConnections[line] then
							rainbowConnections[line]:Disconnect();
						end
						line.Color = Color3.new(0, .7);
					end
					self.hits += 1;
					if self.hits == self.MaxHits then
						self.castId = nil;
						if line then
							if rainbowConnections[line] then
								rainbowConnections[line]:Disconnect();
							end
							line.Color = Color3.new(1, 0);
						end
						break;
					end
				elseif self.StopOnWallHit then
					if line then
						if rainbowConnections[line] then
							rainbowConnections[line]:Disconnect();
						end
						line.Color = Color3.new(.7, .7);
					end
					self.castId = nil;
					break;
				end
			end
		end
	end
end

-- 0: Cast
-- 1: Cancel
mainRemote:Connect(function(method, obj:Instance, b, c, d, e)
	if method == 0 then
		local hitbox = cache[obj] or Hitbox.new(obj) :: Hitbox;
		hitbox.MaxHitsPerTarget = c;
		hitbox.MaxHits = d;
		hitbox.StopOnWallHit = e;
		hitbox:Cast(b);
	elseif method == 1 then
		local hitbox = cache[obj];
		if hitbox then
			hitbox:Cancel();
		end
	end
end);

-- setup
defaultParams.FilterType = Enum.RaycastFilterType.Exclude;
defaultParams.IgnoreWater = true;

linesPool = Cacher.new(function()
	local p = Instance.new("Part");
	p.Material = Enum.Material.Neon;
	p.Anchored = true;
	p.CanCollide = false;
	p.CanQuery = false;
	p.Name = "Ray";
	return p;
end, nil, true);

this.HitboxAdded = HitboxAddedEvent;
this.Hitboxes = cache;
this.new = Hitbox.new;
--------------------------------------------------
return this;
