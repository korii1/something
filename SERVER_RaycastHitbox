--!strict
-- Raycast Hitbox system meant for melee weapons
-- @ko5i on discord

-- dependencies
local Debris = game:GetService("Debris");
local TeamsService = game:GetService("Teams");
local PlayerModule = require(game.K0Engine.Player.PlayerManager);
local HookManager = require(game.K0Engine.Dependency.HookManager);
local ItemManager = require(game.K0Engine.Mechanic.Item);
local RemoteManager = require(game.K0Engine.Dependency.RemoteManager);
local ScreenMessage = require(game.K0Engine.Player.ScreenMessage);
local class = require(game.Utils.Class);
local assert = require(game.Utils.Logging).Assert;
local canHurtAlly = ItemManager.canHurtAlly;

-- types
export type Hitbox = {
	Owner : Player;
	Obj : Instance;
	CurrentHumanoid : Humanoid?;
	CustomData : {[any]:any};
	Casting : boolean;
	
	DistanceOffset : Vector3;
	MaxDistance : number;
	MaxYDistance : number;
	MaxHitsPerTarget : number;
	MaxHits : number;
	Params : RaycastParams;
	StopOnWallHit : boolean;

	Hit : HookManager.Hook;
	HitWall : HookManager.Hook;
	Cast : (self:Hitbox, duration:number?) -> ();
	Cancel : (self:Hitbox) -> ();
}

-- variables
--- 0: Cast
--- 1: Cancel
local mainRemote = RemoteManager.new("RaycastHitboxMain");
local hitRemote = RemoteManager.new("RaycastHitboxHit", nil, nil, {"Instance", "Instance", "Vector3", "Vector3"});
local hitboxes = {} :: {[Instance]:Hitbox};

local hitStr = '{type=right}[Server]: Hit \'<font color="#FFAAAA">%s</font>\' | Distance: <font color="#FFBB00">%s</font>;';
local farHitStr = '{type=right}[Server]: Hit \'<font color="#FFAAAA">%s</font>\' | Distance: <font color="#FF0000">%s</font>;';
local wallHitStr = '{type=right}[Server]: Hit a wall | Distance: <font color="#FFBB00">%s</font>;';

-- class definition
local Hitbox = class{
	ClassName = "RaycastHitbox";
	Obj = nil;
	Owner = nil;
	CurrentHumanoid = nil;
	CustomData = nil;
	Casting = false;
	
	DistanceOffset = Vector3.new(0, 0, -3);
	MaxDistance = 10;
	MaxYDistance = 3;
	MaxHitsPerTarget = 1;
	MaxHits = 4;
	StopOnWallHit = true;
	
	Hit = nil;
	HitWall = nil;
	
	_hit = function(self:Hitbox&any, target:Humanoid, pos:Vector3, dist:number, dir:Vector3, normal:Vector3)
		if target.Health <= 0 or (not target.Parent) then
			return;
		end
		
		local targetPlayer = PlayerModule.PlayersList[target.Parent.Name];
		if targetPlayer and targetPlayer.PlayerObj == self.Owner then
			return;
		end
		if targetPlayer and self.Owner and targetPlayer.Team == (self.Owner.Team::Team).Name and not canHurtAlly(targetPlayer.PlayerObj, self.Owner) then
			return;
		end
		
		local targetHits = self._targetHits[target] or 0;
		if targetHits >= self.MaxHitsPerTarget then
			return;
		end
		self._targetHits[target] = targetHits + 1;
		
		if self._hits == self.MaxHits then
			self:Cancel();
			return;
		end
		self._hits += 1;
		
		--------------------------------------------------
		
		self.Hit:Fire(self, target, pos, dist, dir, normal);
		
		ScreenMessage:Invoke(
			self.Owner,
			hitStr:format(
				(target.Parent::any).Name,
				tostring(math.round(dist*10)/10)
			),
			Color3.new(1, .4 ,.4)
		);
	end;
	
	_hitWall = function(self:Hitbox, part:BasePart, pos:Vector3, dist:number, dir:Vector3, normal:Vector3)
		warn("WALLHIT")
		self:Cancel();
		self.HitWall:Fire(self, part, pos, dist, dir, normal)
	end;
	
	Cast = function(self:Hitbox, duration:number?)
		assert(self.Owner, "Cannot cast a RaycastHitbox without a player owner");
		table.clear((self::any)._targetHits);
		(self::any)._hits = 0;
		self.Casting = true;
		local hum = self.Owner.Character and self.Owner.Character:FindFirstChildOfClass("Humanoid");
		if hum and hum.Health > 0 then
			mainRemote:Invoke(self.Owner, 0, self.Obj, duration, self.MaxHitsPerTarget, self.MaxHits, self.StopOnWallHit);
		end
		task.delay(duration, self.Cancel, self);
	end;
	
	Cancel = function(self:Hitbox)
		self.Casting = false;
		local hum = self.Owner and self.Owner.Character and self.Owner.Character:FindFirstChildOfClass("Humanoid");
		if hum and hum.Health > 0 then
			mainRemote:Invoke(self.Owner, 1, self.Obj);
		end
	end;
	
	new = function(self:Hitbox, obj:Instance, owner:Player) : Hitbox
		assert(owner, "Cannot create hitbox: owner is missing");
		self.Obj = obj;
		self.Owner = owner;
		self.CustomData = {};
		hitboxes[obj] = self;
		(self::any)._targetHits = {};
		self.Hit = HookManager.new();
		self.HitWall = HookManager.new();
		return self;
	end;
	
	_hits = 0;
} :: {
	new:(obj:Instance, owner:Player) -> Hitbox;
};

-- connect remotes
hitRemote:Connect(function(player, obj:Instance, part:BasePart, pos:Vector3, dir:Vector3, normal:Vector3)
	if not player.Character then
		return;
	end
	if not (part and part:IsA("BasePart")) then
		player:Kick();
		return;
	end
	--do
	--	for _, axis in pairs({dir.X, dir.Y, dir.Z}) do
	--		if math.abs(axis) > 1 then
	--			player:Kick();
	--			return;
	--		end
	--	end
	--end
	
	local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart;
	local humanoid = player.Character:FindFirstChildOfClass("Humanoid") :: Humanoid;
	if not (rootPart and humanoid) then
		return;
	end
	
	local hitbox = hitboxes[obj] :: Hitbox?;
	if not (hitbox and hitbox.Owner == player) then
		player:Kick();
		return;
	end
	if not hitbox.Casting then
		return;
	end
	
	local targetHum = part.Parent and part.Parent:FindFirstChildOfClass("Humanoid");
	local hitboxPos = rootPart.CFrame:PointToWorldSpace(hitbox.DistanceOffset);
	local dist = (pos - hitboxPos).Magnitude;
	if dist > hitbox.MaxDistance or (pos.Y - hitboxPos.Y) > hitbox.MaxYDistance then
		if targetHum then
			ScreenMessage:Invoke(
				hitbox.Owner,
				farHitStr:format(
					(targetHum.Parent::any).Name,
					tostring(math.round(dist*10)/10)
				),
				Color3.new(1, .4 ,.4)
			);
		end
		return;
	end
	
	if targetHum then
		(hitbox::any):_hit(targetHum, pos, dist, dir, normal);
	else
		(hitbox::any):_hitWall(part, pos, dist, dir, normal);
	end
end)

return Hitbox;
