--!strict
-- Player data handler
-- @k05i on discord

const DISABLE_IN_STUDIO = true;

const SLOW_SAVE_LOAD_MSG = [[{type=announcement, duration=-1, color=#FF5555, typingAnim=true}Loading save is taking longer than usual. Saving is disabled until it loads.
<font color='#888888' size='20'>[click to dismiss]</font>
]];
const SLOW_SAVE_SUCCESS_MSG = [[{type=right, duration=-1, color=#44FF44}Your save has loaded successfully. Any progress made will be merged with the original save.
<font color='#888888' size='20'>[click to dismiss]</font>
]];
const SAVED_MSG = "{type=right, color=#44FF44}💾 Saved player data!";

const DISABLED = game:GetService("RunService"):IsStudio() and DISABLE_IN_STUDIO;


const PlayerService	= game:GetService("Players");
const DataService	= game:GetService("DataStoreService");
const Logging		= require(game.Utils.Logging);																												const print=Logging.Log; const warn=Logging.Warn; const error=Logging.Error; const assert=Logging.Assert;
const RemoteManager	= require("../Dependency/RemoteManager");
const ScreenMessage	= require("../Player/ScreenMessage");
const Content = {};

const Remote	= RemoteManager.new("PlayerSave");
const DataStore = DataService:GetDataStore("PlayerSave");
const cache		= {} :: {[number] : save};
const fetching	= {} :: {[number] : true};

const defaultSave = {
	IsLoaded = false;
	LastUpdate = 0;
	
	Currency = {
		Money = 0;
	};
	EquippedSkins = {
		Bat = "none";
	};
	ItemSkins = {
		Bat = {"Face Cooler", "Face Melter", "Choco Reign"};
		Knife = {};
	};
	KurxianSkins = {
		CrystalPup = {};
		CrystalPupDragon = {};
	};
}
type save = typeof(defaultSave);
type dict = {[string]: any};

--[[ MAIN ]]

const function cloneTable(target : any) : any
	if typeof(target) == "table" then
		const copy = {};
		for key, v in target do
			copy[key] = cloneTable(v);
		end
		return copy;
	end
	return target;
end

const function isArray(t): boolean
	local count = 0;
	for key in t do
		if typeof(key) ~= "number" then
			return false;
		end
		count += 1;
	end
	return count > 0;
end

const function mergeArray(a: {any}, b: {any})
	const result = cloneTable(a);
	const exists = {};

	for _, v in ipairs(result) do
		exists[v] = true
	end

	for _, v in ipairs(b) do
		if not exists[v] then
			table.insert(result, v);
			exists[v] = true;
		end
	end

	return result;
end

const function overrideData(data: dict, newData: dict?) : dict
	if not newData then
		return data;
	end
	for key, value in newData do
		if typeof(value) == "table" then
			if typeof(data[key]) ~= "table" then
				warn("Data type mismatch for key '"..key.."'. table expected, got "..typeof(data[key]));
				continue;
			end
			if isArray(value) then
				data[key] = mergeArray(data[key], value);
			else
				overrideData(data[key], value);
			end
		else
			data[key] = value;
		end
	end
	return data;
end

const function mergeData(data: dict, add: dict?) : dict
	if not add then
		return data;
	end
	
	const currency = data.Currency;
	if add.Currency then
		for type, amount in add.Currency do
			currency[type] = (currency[type] or 0) + amount;
		end
	end
	
	for key, value in add do
		if typeof(value) ~= "table" then
			continue;
		end
		if typeof(data[key]) ~= "table" then
			warn("Data type mismatch for key '"..key.."'. table expected, got "..typeof(data[key]));
			continue;
		end
		
		if isArray(value) then
			data[key] = mergeArray(data[key], value);
		else
			mergeData(data[key], value);
		end
	end
	return data;
end

const function sendDataToClient(player: Player, data: save) : ()
	RemoteManager.WaitForPlayerReady(player);
	print("📦 Sending player data to client", player);
	Remote:Invoke(player, data);
end

function Content.GetSaveAsync(playerOrId: number|Player, timeout: number?, mergeWithCache: boolean?) : save?
	const userId		= (typeof(playerOrId) == "Instance" and playerOrId.UserId) or playerOrId::number;
	const playerName	= (typeof(playerOrId) == "Instance" and playerOrId.Name) or nil;
	print("📦 Fetching player data for "..(playerName or userId));
	
	if playerName and DISABLED then
		const data = cloneTable(defaultSave);
		data.IsLoaded = true;
		cache[userId] = data;
		return data;
	end
	
	if fetching[userId] then
		repeat
			task.wait(.1);
		until not fetching[userId];
		return cache[userId];
	end
	
	const cachedData = cache[userId];
	if cachedData and not mergeWithCache then
		return cachedData;
	end
	
	const startTime			= os.clock();
	const quitTime			= (timeout and startTime + timeout) or math.huge;
	local sentSlowMessage	= false;
	
	fetching[userId]		= true;
	local success, data: save;
	while (not success) do
		const time = os.clock();
		success, data = pcall(DataStore.GetAsync, DataStore, userId);
		
		if success then
			if cachedData then
				const method : (dict, dict?) -> dict
					= (mergeWithCache and mergeData) or overrideData;
				data = (data and method(data, cachedData)) or cachedData;
			end
			
			data = data or cloneTable(defaultSave);
			data.IsLoaded = true;
			if playerName then
				cache[userId] = data;
				if sentSlowMessage then
					ScreenMessage:Invoke(playerOrId, SLOW_SAVE_SUCCESS_MSG);
				end
			end
			print("📦✅ Cached data for "..(playerName or userId)..":\n", Logging.Stringify(data));
			break;
		elseif time-startTime > quitTime then
			warn("📦❌ Could not fetch player data for '"..(playerName or userId).."'. DataStore outage suspected. Message:", data);
			if playerName then
				data = cloneTable(defaultSave);
				cache[userId] = data;
				task.defer(Content.GetSaveAsync, playerOrId, nil, true);
			end
			break;
		end
		
		if time-startTime > 10 then
			if playerName and not sentSlowMessage then
				sentSlowMessage = true;
				ScreenMessage:Invoke(playerOrId, SLOW_SAVE_LOAD_MSG);
			end
			warn("📦⏳ DataStore is taking a while to respond for '"..(playerName or userId).."'");
		end
		
		task.wait(5);
	end
	fetching[userId] = nil;
	
	if playerName then
		task.spawn(sendDataToClient, playerOrId::Player, data);
	end
	return data;
end

function Content.UpdateSaveAsync(playerOrId: number|Player, replacement: ({[string] : any} & save)?, timeout: number?) : boolean
	const userId		= (typeof(playerOrId) == "Instance" and playerOrId.UserId) or playerOrId::number;
	const playerName	= (typeof(playerOrId) == "Instance" and playerOrId.Name) or nil;
	const cachedData	= cache[userId];
	const getData		= cachedData or Content.GetSaveAsync(playerOrId, timeout, true);
	print("📦 Saving player data for "..(playerName or userId).."\n New data:", getData);
	
	if DISABLED then
		return true;
	end
	if not (getData and getData.IsLoaded) then
		return false;
	end
	
	const data = cloneTable(getData);
	data.LastUpdate = os.time();
	if replacement then
		overrideData(data, cloneTable(replacement));
	end
	
	const quitTime = (timeout and os.clock() + timeout) or math.huge;
	local success, err;
	while (not success) and (os.clock() < quitTime) do
		if playerName then
			success, err = pcall(DataStore.SetAsync, DataStore, userId, data);
		else
			success, err = pcall(DataStore.UpdateAsync, DataStore, userId,
				function(oldData:save?, _:DataStoreInfo)
					return (oldData and overrideData(oldData, data)) or data;
				end);
		end
		
		if success then
			print("📦✅ Saved data for "..(playerName or userId)..":\n", data);
		else
			warn("📦❌ Could not save player data for '"..(playerName or userId).."'. DataStore outage suspected. \nMessage:", err);
			task.wait(5);
		end
	end
	
	if playerName then
		RemoteManager.WaitForPlayerReady(playerOrId::Player);
		Remote:Invoke(playerOrId::Player, data);
		if success then
			ScreenMessage:Invoke(playerOrId, SAVED_MSG);
		end
	end
	return success;
end


--[[ SETUP ]]
local closing = false;

task.spawn(function()
	repeat
		task.wait(10 * 60);
		for _, p in ipairs(PlayerService:GetPlayers()) do
			if closing then
				break;
			end
			Content.UpdateSaveAsync(p);
		end
	until false;
end);

PlayerService.PlayerAdded:Connect(function(player:Player)
	Content.GetSaveAsync(player);
end)

PlayerService.PlayerRemoving:Connect(function(player:Player)
	Content.UpdateSaveAsync(player);
	cache[player.UserId] = nil;
end)

game:BindToClose(function(_: Enum.CloseReason)
	closing = true;
	for key, _ in cache do
		Content.UpdateSaveAsync(key);
	end
end);

Content.DataStore = DataStore;
return Content;
