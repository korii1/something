--!strict
-- Custom held items to avoid using Roblox's Tool instance
-- @ko5i on discord

const any			= nil :: any;
const TOOL_OBJECT	= Instance.new("IntValue");
const ACT_EQUIP		= true;
const ACT_UNEQUIP	= false;
const ACT_USE		= nil;

export type ItemConfig = {
	DisplayName			: string?;
	Description			: string?;
	ImageID				: string?;
	ImageScale			: number?;

	DurablityEnabled	: boolean?;
	DropOnDeath			: boolean;
	Droppable			: boolean;
	UseCooldown			: number;
	AnimationIDs		: {[string] : {string}};
	EquipVisualDelay	: number?;
	UnequipVisualDelay	: number?;
	PlayRandomAnimations: boolean?;

	CastDelay			: number;
	CastDuration		: number;
	Hitbox				: any;
}
export type ItemModule = {
	Configurate		: (skin:string?) -> ItemConfig;
	Used			: (self:Item) -> ()?;
	Equipped		: (self:Item) -> ()?;
	Unequipped		: (self:Item) -> ()?;
	Dropped			: (self:Item) -> ()?;
	Destroyed		: (self:Item) -> ()?;
	Create			: (self:Item, skin:string?, ...any) -> ();
}
export type ItemObj = typeof(TOOL_OBJECT);

-- DEPENDENCY
const PlayersService	= game:GetService("Players");
const RunService		= game:GetService("RunService");
const UIS				= game:GetService("UserInputService");
const ContextAction		= game:GetService("ContextActionService");
const Logging			= require(game.Utils.Logging);	const assert=Logging.Assert;
const Signal			= require(game.Utils.Signal);
const WaitForClass		= require(game.Utils.WaitForClass).WaitForChildOfClass;
const RemoteManager		= require("../Dependency/RemoteManager");
const SoundManager		= require("../Dependency/SoundManager");
const ScreenMessage		= require("../UI/ScreenMessage");
const Animate			= require("./Animate");

-- CONSTANT
type ITEM_SIGNAL = Signal.Signal<
	(item:Item)->(), -- Used in :Connect(your:vars), :Once(your:vars), etc.
	(self:any, item:Item)->(), -- Used in :Fire(self:any, your:vars)
	(self:any) -> (Item) -- Used in :Wait()
>
const ItemRemote	= RemoteManager.new("ItemRemote");
const SoundRemote	= RemoteManager.new("PlayItemSound");
const ItemAddedSignal = (Signal.new() :: any) :: ITEM_SIGNAL;
const ItemRemovedSignal = (Signal.new() :: any) :: ITEM_SIGNAL;
const ItemEquippedSignal = (Signal.new() :: any) :: ITEM_SIGNAL;
const ItemUnequippedSignal = (Signal.new() :: any) :: ITEM_SIGNAL;

const registry	= {} :: {[ItemObj] : Item};
const Content	= {
	Registry		= registry;
	ToolModule		= {}	:: {[string] : ItemModule};
	CurrentItem		= nil	:: Item?;
	ItemAdded		= ItemAddedSignal.Event;
	ItemRemoved		= ItemRemovedSignal.Event;
	ItemEquipped	= ItemEquippedSignal.Event;
	ItemUnequipped	= ItemUnequippedSignal.Event;
};

const localPlayer	= PlayersService.LocalPlayer;
const mouse			= localPlayer:GetMouse();

const Item = {
	Skin		= "default"	:: string;
	Tool		= any		:: ItemObj;
	Model		= any		:: typeof(script.ToolModelTemplate);
	Handle		= any		:: typeof(script.ToolModelTemplate.Handle);
	Module		= any		:: ItemModule;
	Settings	= any		:: ItemConfig;
	Animations	= any		:: {[string] : {AnimationTrack}};
};

-- VARIABLE
local equipCooldown		= 0;
local currentIdleAnim	: AnimationTrack?;
local prevIdleAnim		: AnimationTrack?;
local character			: Model?;
local humanoid			: Humanoid?;


--[[ TYPES ]]

export type Item = typeof(Item);
type _Item = Item & {
	cooldown		: number;
};

type signalFunc = (item:Item) -> ();


--[[ CLASS ]]

-- Use the item
-- <strong>> force:</strong> Determines wether the cooldown is bypassed
function Item.Use(self:Item, force:boolean?) : ()
	if (not force) and not (character and humanoid) then
		return false;
	end
	
	const time = os.clock();
	if (not force) and ((not humanoid) or humanoid.PlatformStand or time < (self::any).cooldown or time < equipCooldown-.5) then
		return;
	end
	self.cooldown = time + (self.Tool:GetAttribute("UseCooldown") or self.Settings.UseCooldown);

	ItemRemote:Invoke(self.Tool, ACT_USE);
	
	const animations = self.Animations.Use;
	if animations then
		if #animations > 1 then
			animations[0] = animations[math.random(1, #animations)];
		end
		animations[0]:Play();
	end
	
	if self.Module.Used then
		self.Module.Used(self);
	end
end

-- Equip the item
-- <strong>> force:</strong> Determines wether the cooldown is bypassed
-- <strong>> RETURNS:</strong> (Success)
function Item.Equip(self:Item, force:boolean?) : (boolean)
	if not (character and humanoid and not force) then
		return false;
	end
	
	const time = os.clock();
	if (not force) and (humanoid.PlatformStand or time < equipCooldown) then
		return false;
	end
	equipCooldown = time + 1;
	
	
	if Content.CurrentItem == self then
		return self:Unequip();
	elseif Content.CurrentItem then
		Content.CurrentItem:Unequip(true);
	end
	
	-- ANIMATIONS
	const equipAnimations = self.Animations.Equip;
	if equipAnimations then
		if #equipAnimations > 1 then
			equipAnimations[0] = equipAnimations[math.random(1, #equipAnimations)];
		end
		equipAnimations[0]:Play();
	end
	
	const idleAnimations = self.Animations.Idle;
	if idleAnimations then
		currentIdleAnim = idleAnimations[0];
	end
	
	-- FINALIZE
	Content.CurrentItem = self;
	self.Tool.Parent = localPlayer.Character;
	ItemRemote:Invoke(self.Tool, ACT_EQUIP);
	
	if self.Module.Equipped then
		self.Module.Equipped(self);
	end
	ItemEquippedSignal:Fire(self);
	return true;
end

-- Unequip the player's current item
-- <strong>> force:</strong> Determines wether the cooldown is bypassed
-- <strong>> RETURNS:</strong> (Success)
function Item.Unequip(self:Item, force:boolean?, removing:boolean?) : (boolean)
	if (not force) and not (character and humanoid) then
		return false;
	end
	
	if Content.CurrentItem ~= self then
		return false;
	end
	
	const time = os.clock();
	if (not force) and (humanoid.PlatformStand or time < equipCooldown) then
		return false;
	end
	equipCooldown = time + 1;
	
	-- ANIMATIONS
	const unequipAnim2 = self.Animations.Unequip;
	if unequipAnim2 then
		if #unequipAnim2 > 1 then
			unequipAnim2[0] = unequipAnim2[math.random(1, #unequipAnim2)];
		end
		unequipAnim2[0]:Play();
	end
	
	const useAnim = self.Animations.Use;
	if useAnim and useAnim[0].IsPlaying then
		useAnim[0]:Stop(.5);
	end
	
	currentIdleAnim = nil;
	
	-- FINALIZE
	Content.CurrentItem = nil;
	if not force then
		ItemRemote:Invoke(self.Tool, ACT_UNEQUIP);
	end
	
	if not removing then
		local th : thread;
		const cnn = self.Tool:GetPropertyChangedSignal("Parent"):Once(function()
			task.cancel(th);
		end)
		th = task.delay(self.Settings.UnequipVisualDelay, function()
			cnn:Disconnect();
			self.Tool.Parent = localPlayer.Backpack;
		end)
	end
	
	if self.Module.Unequipped then
		self.Module.Unequipped(self);
	end
	ItemUnequippedSignal:Fire(self);
	return true;
end

-- Drops the item
-- <strong>> force:</strong> Determines wether the item should be dropped even if it isn't droppable
-- <strong>> RETURNS:</strong> (Success)
function Item.Drop(self:Item, force:boolean?) : (boolean)
	if (not force) and not (character and humanoid) then
		return false;
	end
	if not (self.Settings.Droppable or force) then
		return false;
	end
	
	self:Unequip(true, true);
	if not force then
		ItemRemote:Invoke(self.Tool, ACT_UNEQUIP, true);
	end
	
	if self.Module.Dropped then
		self.Module.Dropped(self);
	end
	ItemRemovedSignal:Fire(self);
	return true;
end

-- Deletes the item
function Item.Destroy(self:Item) : ()
	registry[self.Tool] = nil;
	if self.Module.Destroyed then
		self.Module.Destroyed(self);
	end
	ItemRemovedSignal:Fire(self);
	self.Model:Destroy();
	self.Tool:Destroy();
end


--[[ MAIN ]]

-- Creates a new item
-- <strong>> name:	</strong>	Internal name of the item
-- <strong>> player:</strong>	Owner of the item
-- <strong>> skin:	</strong>	Optional skin applied to the item
function Content.new(tool:ItemObj) : (Item)
	const ERR	= "Could not create tool '"..tool.Name.."': ";
	const skin	= tool:GetAttribute("Skin") :: string?;
	
	const character	= assert(localPlayer.Character,							ERR.."Character is missing")	:: Model;
	const humanoid	= assert(character:FindFirstChildOfClass("Humanoid"),	ERR.."Humanoid is missing")	:: Humanoid;
	const model		= assert(tool:WaitForChild("ToolModel", 5),				ERR.."ToolModel is missing")	:: typeof(script.ToolModelTemplate);
	const handle	= assert(model:WaitForChild("Handle", 5),				ERR.."Handle is missing")		:: typeof(script.ToolModelTemplate.Handle);
	
	local module	: ItemModule?;
	do
		const timeout	= os.clock() + 10;
		while task.wait(1) and not (module or os.clock() > timeout) do
			module = Content.ToolModule[tool.Name];
		end
	end
	if not module then
		ScreenMessage.ShowMessage("{color=#FF5555}"..ERR.."No tool module found");
		print(Content.ToolModule);
		error(ERR.."No tool module found");
	end
	
	const settings	 = module.Configurate(skin);
	const animations = {};
	
	const self = {
		Skin	 = skin;
		Tool	 = tool;
		Handle	 = handle;
		Model	 = model;
		Module	 = module;
		Settings = settings;
		Animations = animations;
		
		cooldown = 0;
	} :: _Item;
	setmetatable(self, Item);
	
	local destroyCnn;
	destroyCnn = tool:GetPropertyChangedSignal("Parent"):Connect(function()
		if tool.Parent ~= localPlayer.Backpack and tool.Parent ~= character then
			self:Drop(true);
			self:Destroy();
			destroyCnn:Disconnect();
			if (not tool.Parent) and self.Module.Destroyed then
				self.Module.Destroyed(self);
			end
		end
	end)
	
	registry[self.Tool] = self;
	if self.Module.Create then
		self.Module.Create(self, skin);
	end
	ItemAddedSignal:Fire(self);
	
	-- LOAD ANIMATIONS
	const animator = humanoid:WaitForChild("Animator", 5) :: Animator;
	if animator then
		for cat, v in settings.AnimationIDs do
			local anims = {};
			local total = #v;
			local animPriority =
				(cat == "Idle" and Enum.AnimationPriority.Action) or
				(cat == "Use" and Enum.AnimationPriority.Action2) or
				(cat == "Equip" and Enum.AnimationPriority.Action2) or
				(cat == "Unequip" and Enum.AnimationPriority.Action2) or
				nil;

			for i, animId in ipairs(v) do
				local anim = Instance.new("Animation");
				anim.AnimationId = animId;
				anim.Name = cat;
				anim.Parent = script;
				local loadedAnim = animator:LoadAnimation(anim);
				if animPriority then
					loadedAnim.Priority = animPriority;
				end
				table.insert(anims, loadedAnim);
			end
			anims[0] = anims[1];
			animations[cat] = anims;
		end
	else
		ScreenMessage.ShowMessage("{color=#FF5555}Failed to load "..tool.Name.." animations: No animator found");
	end

	return self;
end

function Content.PlaySoundOfCategory(item: Item & any, category: string, cloneAndDestroy: boolean?) : ()
	const folder	= item.Handle:FindFirstChild("Sounds");
	const cat		= folder and folder:FindFirstChild(category);
	const sounds	= cat and cat:GetChildren() :: {Sound & any};

	if not (sounds and #sounds > 0) then
		return;
	end
	
	SoundManager.playLocal(sounds[math.random(1, #sounds)], "SFX", cloneAndDestroy);
end

function Content.canHurtAlly(attacker:Player|Model, target:Player|Model?) : boolean
	return (target and target:HasTag("Hostile")) or attacker:HasTag("CanHurtAlly") or attacker:HasTag("Hostile");
end



const function ON_ItemRemote(player:Player, tool:ItemObj&any, action:boolean?, delay:number?)
	if player == localPlayer then
		return;
	end

	if delay then
		task.wait(delay);
	end
	if		action == true	then
		--tool.Parent = player.Character;
	elseif 	action == false	then
		--tool.Parent = player.Backpack;
	elseif	action == nil	then
		const item = registry[tool];
		if item then
			item:Use(true);
		end
	end
end

const function ON_SoundRemote(sound:Sound&any, cloneAndDestroy:boolean?) : ()
	if character and sound:IsDescendantOf(character) and sound.Parent.Name ~= "Hit" then
		return;
	end
	SoundManager.playLocal(sound, "SFX", cloneAndDestroy);
end

const function ON_AddedToBackpack(tool:ItemObj)
	if not tool:HasTag("Tool") then
		return;
	end
	if registry[tool] then
		return;
	end
	Content.new(tool);
end

const function ON_CharacterAdded(c:Model)
	const hum = WaitForClass(c, "Humanoid", 5) :: Humanoid;
	if hum then
		character = c;
		humanoid = hum;
		local humcnn;
		local charcnn;
		humcnn = hum.Died:Once(function()
			charcnn:Disconnect();
			character = nil;
			humanoid = nil;
		end)
		charcnn = c.Destroying:Once(function()
			humcnn:Disconnect();
			character = nil;
			humanoid = nil;
		end)
	end
end

const function render()
	if prevIdleAnim ~= currentIdleAnim then
		if prevIdleAnim then
			prevIdleAnim:Stop(.5);
		end
		prevIdleAnim = currentIdleAnim;
	end

	if currentIdleAnim then
		if humanoid and Animate.getPose() == "idle" and not Animate.DISABLED_HUMANOID_STATES[humanoid:GetState()] then
			if not currentIdleAnim.IsPlaying then
				currentIdleAnim:Play();
			end
		else
			if currentIdleAnim.IsPlaying then
				currentIdleAnim:Stop(.5);
			end
		end
	end
end


--[[ SETUP ]]

(Item::any).__index = Item;

RunService.PreRender:Connect(render);
ItemRemote:Connect(ON_ItemRemote);
SoundRemote:Connect(ON_SoundRemote);

ContextAction:BindAction("UseItem", function()
	if Content.CurrentItem then
		Content.CurrentItem:Use();
	end
	return Enum.ContextActionResult.Pass;
end, false, Enum.UserInputType.Touch, Enum.UserInputType.MouseButton1);

UIS.TouchTap:Connect(function(input, processed)
	if processed then
		return;
	end
	if Content.CurrentItem then
		Content.CurrentItem:Use();
	end
end)

if localPlayer.Backpack then
	for _, item in ipairs(localPlayer.Backpack:GetChildren()) do
		task.defer(ON_AddedToBackpack, item);
	end
end
localPlayer.ChildAdded:Connect(function(backpack)
	if backpack:IsA("Backpack") then
		for _, tool in ipairs(backpack:GetChildren()) do
			task.defer(ON_AddedToBackpack, tool);
		end
		backpack.ChildAdded:Connect(ON_AddedToBackpack);
	end
end);

if localPlayer.Character then
	ON_CharacterAdded(localPlayer.Character);
end
localPlayer.CharacterAdded:Connect(ON_CharacterAdded);

return Content;
