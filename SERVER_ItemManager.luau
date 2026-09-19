--!strict
-- Custom held items to avoid using Roblox's Tool instance
-- @ko5i on discord

const any			= nil :: any;
const TOOL_OBJECT	= Instance.new("IntValue");

const Logging		= require(game.Utils.Logging) const warn=Logging.Warn; const print=Logging.Log; const assert = Logging.Assert;
const RemoteManager	= require("../Dependency/RemoteManager");

const ItemRemote = RemoteManager.new("ItemRemote", .1, nil, {"Instance"});
const SoundRemote = RemoteManager.new("PlayItemSound");

const raw		= {} :: {[string]: {
	Module	: ItemModule;
	Models	: {[string] : typeof(script.ToolModelTemplate)};
}};
const registry		= {} :: {[ItemObj] : Item};
const plrInventory	= {} :: {[Model] : {_Item}};
const plrCooldowns	= {} :: {[Model] : number};

const Content = {};
const Item = {
	Skin		= "default"	:: string;
	Tool		= any		:: ItemObj;
	Handle		= any		:: BasePart;
	Model		= any		:: typeof(script.ToolModelTemplate);
	Module		= any		:: ItemModule;
	Settings	= any		:: ItemConfig;
	Player		= any		:: Player?;
	Character 	= any		:: Model;
};


--[[ TYPES ]]

export type ItemConfig = {
	DisplayName			: string?;
	Description			: string?;
	ImageID				: string?;
	ImageScale			: number?;
	
	DurabilityEnabled	: boolean?;
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
	Dropped			: (self:Item, destroyed:boolean?) -> ()?;
	Create			: (self:Item, Player:Player, skin:string?, ...any) -> ();
}
type ItemObj = typeof(TOOL_OBJECT);

export type Item = typeof(Item) & {[string] : any};
type _Item = Item & {
	cooldown		: number;
};

const function newInventory(character:Model) : typeof(plrInventory[any])
	const new = {};
	plrInventory[character] = new;
	return new;
end


--[[ CLASS ]]

-- Use the item
-- <strong>> force:</strong> Determines wether the cooldown is bypassed
function Item.Use(self:_Item, force:boolean?) : ()
	assert(self.Player, "Cannot use an item that has no owner");

	const time = os.clock();
	if time < self.cooldown and not force then
		return;
	end
	self.cooldown = time + self.Settings.UseCooldown;

	ItemRemote:Invoke(nil, self.Player, self.Tool, nil);

	if self.Module.Used then
		self.Module.Used(self);
	end
end

-- Equip the item
-- <strong>> force:</strong> Determines wether the cooldown is bypassed
-- <strong>> RETURNS:</strong> (Success)
function Item.Equip(self:_Item, force:boolean?) : (boolean)
	const player	= assert(self.Player, "Cannot equip an item that has no owner");
	const character	= assert(player.Character, "Cannot equip an item without a character");
	const inventory	= plrInventory[character] or newInventory(character);
	const equipped	= inventory[0];
	
	const time = os.clock();
	if (not force) and time < plrCooldowns[character] then
		return false;
	end
	plrCooldowns[character] = time + 1;
	
	if equipped == self then
		return self:Unequip(force);
	elseif equipped then
		equipped:Unequip(true);
	end
	
	inventory[0] = self;
	self.Tool.Parent = character;
	ItemRemote:Invoke(nil, self.Player, self.Tool, true, self.Settings.EquipVisualDelay);
	
	if self.Module.Equipped then
		self.Module.Equipped(self);
	end
	return true;
end

-- Unequip the player's current item
-- <strong>> force:</strong> Determines wether the cooldown is bypassed
-- <strong>> RETURNS:</strong> (Success)
function Item.Unequip(self:_Item, force:boolean?) : (boolean)
	const player	= assert(self.Player, "Cannot unequip an item that has no owner");
	const character	= assert(player.Character, "Cannot unequip an item without a character");
	const inventory	= plrInventory[character] or newInventory(character);
	const self		= inventory[0];
	
	if not self then
		return false;
	end
	
	const time = os.clock();
	if time < plrCooldowns[character] and not force then
		return false;
	end
	plrCooldowns[character] = time + 1;
	
	inventory[0] = nil;
	self.Tool.Parent = player.Backpack;
	ItemRemote:Invoke(nil, self.Player, self.Tool, false, self.Settings.UnequipVisualDelay);
	return true;
end

-- Drops the item
-- <strong>> force:</strong> Determines wether the item should be dropped even if it isn't droppable
-- <strong>> RETURNS:</strong> (Success)
function Item.Drop(self:_Item, force:boolean?) : (boolean)
	const player	= assert(self.Player, "Cannot drop an item that has no owner");
	const character	= assert(player.Character, "Cannot drop an item without a character");
	const inventory	= plrInventory[character] or newInventory(character);
	
	if not (self.Settings.DropOnDeath or force) then
		return false;
	end
	
	if inventory[0] == self then
		inventory[0] = nil;
	end
	self:Unequip(true);
	table.remove(inventory, table.find(inventory, self));
	
	for _, joint:Motor6D in ipairs(self.Model.Welds:GetChildren()) do
		joint.Part0 = nil;
	end
	self.Tool.Parent = workspace;
	self.Model:PivotTo(character:GetPivot());
	self.Handle.CanCollide = true;
	
	if self.Module.Dropping then
		self.Module.Dropping(self);
	end
	return true;
end

-- Deletes the item
function Item.Destroy(self:_Item) : ()
	const player	= self.Player;
	const character	= player and player.Character;
	const inventory	= character and (plrInventory[character] or newInventory(character));
	if inventory then
		table.remove(inventory, table.find(inventory, self));
	end
	
	if self.Module.Destroying then
		self.Module.Destroying(self);
	end
	self.Model:Destroy();
	self.Tool:Destroy();
end


--[[ MAIN ]]

-- Creates a new item
-- <strong>> name:	</strong>	Internal name of the item
-- <strong>> player:</strong>	Owner of the item
-- <strong>> skin:	</strong>	Optional skin applied to the item
function Content.new(name:string, player:Player, skin:string?) : (Item)
				  assert(player, "Cannot create an item without a Player");
	const char	= assert(player.Character, "Cannot create an item without a Character");
	const raw	= assert(raw[name], "Invalid item '"..name.."'");
	const model	= (
		skin and assert(raw.Models[skin], "Invalid skin '"..skin::any.."' for item '"..name.."'")
			  or assert(raw.Models.default, "Item '"..name.."' has no default skin. Fix it.")
	):Clone();
	
	const handle	= assert(model:FindFirstChild("Handle"), "Item '"..name.."' has no handle. Fix it.") :: BasePart;
	const welds		= assert(model:FindFirstChild("Welds"), "Item '"..name.."' has no welds folder. Fix it.");
	const module 	= assert(raw.Module, "Item '"..name.."' has no module. Fix it.") :: ItemModule;
	const settings	= module.Configurate(skin);
	const tool		= Instance.new(TOOL_OBJECT.ClassName) :: ItemObj;
	const inventory	= plrInventory[char] or newInventory(char);
	
	const self = {
		Skin		= skin or "default";
		Tool		= tool;
		Handle		= handle;
		Model		= model;
		Module		= module;
		Settings 	= settings;
		Player		= player;
		Character	= char;
		
		cooldown	= 0;
	} :: _Item & any;
	setmetatable(self::any, Item);
	
	for _, weld:Motor6D in ipairs(welds:GetChildren()) do
		weld.Part0 = char:FindFirstChild(weld.Name) :: BasePart;
	end
	for _, v:BasePart in ipairs(self.Tool:QueryDescendants("BasePart")::any) do
		v.CanQuery = false;
	end
	
	const hum = char:FindFirstChildOfClass("Humanoid");
	if hum then
		hum.Died:Once(function()
			if self.Settings.DropOnDeath then
				self:Drop(true);
			end
		end)
	end
	char.Destroying:Once(function()
		plrCooldowns[char] = nil;
		plrInventory[char] = nil;
		if self.Tool.Parent then
			self:Destroy();
		end
	end)
	
	self.Tool.Destroying:Once(function()
		if self.Module.Destroying then
			self.Module.Destroying(self);
		end
	end)
	
	if settings.DurabilityEnabled then
		tool:SetAttribute("Durability", 1);
	end
	tool:AddTag("Tool");
	tool.Name				= name;
	model.Name				= "ToolModel";
	model.Parent			= self.Tool;
	self.Tool.Parent		= player.Backpack;
	registry[self.Tool]		= self :: any;
	plrCooldowns[char]		= 0;
	table.insert(inventory, self);
	
	self.Tool:SetAttribute("Skin", skin);
	
	if self.Module.Create then
		self.Module.Create(self, player);
	end
	
	return self :: any;
end

function Content.PlaySoundOfCategory(item: Item & any, category: string, cloneAndDestroy: boolean?, parent: Instance?) : ()
	const folder	= item.Handle:FindFirstChild("Sounds");
	const cat		= folder and folder:FindFirstChild(category);
	const sounds	= cat and cat:GetChildren() :: {Sound & any};

	if not (sounds and #sounds > 0) then
		return;
	end

	const sound = sounds[math.random(1, #sounds)];
	SoundRemote:Invoke(nil, sound, cloneAndDestroy, parent);
end

function Content.canHurtAlly(attacker:Player|Model, target:Player|Model?) : boolean
	return (target and target:HasTag("Hostile")) or attacker:HasTag("CanHurtAlly") or attacker:HasTag("Hostile");
end


--[[ SETUP ]]

-- > action: false=Unequip, true=Equip, nil=Use
const function ON_Remote(player:Player, item:ItemObj, action:boolean?, drop:boolean?) : ()
	const character = assert(player.Character, player.Name.." attempted to use an item without having a character");
	const self		= assert(registry[item], player.Name.." attempted to use an invalid item");
	const inventory	= plrInventory[character] or newInventory(character);
	
	if (not self) or self.Player ~= player then
		player:Kick();
		return;
	end
	
	if		action == true	then -- EQUIP
		self:Equip();
	elseif	action == false	then -- UNEQUIP
		self:Unequip();
		if drop and self.Settings.Droppable then
			self:Drop();
		end
	elseif	action == nil	then -- USE
		if inventory[0] == self then
			self:Use();
		end
	end
end
ItemRemote:Connect(ON_Remote);

(Item::any).__index = Item;
Content.raw = raw;
Content.registry = registry;
Content.plrInventory = plrInventory;
Content.ItemRemote = ItemRemote;
Content.SoundRemote = SoundRemote;
Content.TOOL_OBJECT = TOOL_OBJECT;

return Content;
