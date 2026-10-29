-- Player save data (DataStore). In Studio, enable Game Settings > Security > "Enable Studio Access to API Services".
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage.Config)

local DataService = {}
local profiles = {}
local canSave = {}

local store
do
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore("StealAChicken_v1")
	end)
	if not ok then
		warn("[DataService] DataStore unavailable, progress will not be saved:", err)
	end
end

local function default()
	return {
		Cash = Config.StartingCash,
		TotalEarned = 0,
		Eggs = 0,
		Slots = {}, -- [tostring(slotIndex)] = chickenId
		Mutations = {}, -- [tostring(slotIndex)] = mutationId (Config.Mutations)
		Upgrades = {}, -- [upgradeId] = level
		Index = {}, -- [chickenId] = true
		EggIndex = {}, -- [eggId] = count
		BatSkin = "Classic", -- equipped bonk bat skin (Config.BatSkins)
		Bought = {}, -- [chickenId] = true: chickens bought on the road (they unlock bat skins)
		BoughtMuts = {}, -- [mutationId] = true: mutations bought on the road (they unlock bat skins)
	}
end

local function reconcile(data)
	local base = default()
	if type(data) ~= "table" then
		return base
	end
	for k, v in pairs(base) do
		if data[k] == nil then
			data[k] = v
		end
	end
	return data
end

-- SESSION LOCK --------------------------------------------------------------------
-- The save holds `_lock = { job = <server JobId>, t = os.time() }` while a server is using it.
--  * Load takes the lock with UpdateAsync. If another server still holds it (the player just left that server
--    and it is still saving), we wait for it to let go, so we never load an old save.
--  * Every save checks that THIS server still owns the lock, so an old server can never overwrite newer data
--    (no rollbacks, no duplicated chickens by hopping between servers).
--  * Leaving the game saves one last time and frees the lock (Save(player, true)).
--  * A lock older than LOCK_TIMEOUT belongs to a server that crashed: it is taken over.
local JOB = game.JobId ~= "" and game.JobId or "studio"
local LOCK_TIMEOUT = 240 -- autosave refreshes the lock every 2 min, so an older one is dead
local LOAD_WAIT = 30 -- seconds we wait for the previous server to free the lock before taking it
local released = {}

local function key(player)
	return "u_" .. player.UserId
end

function DataService.Load(player)
	local data
	canSave[player] = store ~= nil
	released[player] = nil
	if store then
		local ok, result
		local started = os.clock()
		local fails = 0
		while player.Parent do
			local lockedElsewhere = false
			local force = os.clock() - started >= LOAD_WAIT
			local loaded
			ok, result = pcall(store.UpdateAsync, store, key(player), function(old)
				local lock = type(old) == "table" and old._lock
				if type(lock) == "table" and lock.job ~= JOB and not force and os.time() - (tonumber(lock.t) or 0) < LOCK_TIMEOUT then
					lockedElsewhere = true
					return nil -- don't write: the other server is still saving
				end
				lockedElsewhere = false
				loaded = type(old) == "table" and old or {}
				loaded._lock = { job = JOB, t = os.time() }
				return loaded
			end)
			if ok and not lockedElsewhere then
				data = loaded
				break
			elseif ok then
				task.wait(2) -- wait for the other server to finish saving
			else
				fails += 1
				if fails >= 3 then
					break
				end
				task.wait(1)
			end
		end
		if not data then
			-- Never overwrite real data after a failed load.
			canSave[player] = false
			warn("[DataService] Load failed for", player.Name, result)
		end
	end
	profiles[player] = reconcile(data)
	return profiles[player]
end

function DataService.Get(player)
	return profiles[player]
end

-- release = true on the last save (player leaving / server closing): frees the lock for the next server
function DataService.Save(player, release)
	local data = profiles[player]
	if not (data and store and canSave[player]) or released[player] then
		return
	end
	if release then
		released[player] = true -- no more saves for this player from this server
	end
	data.LastSeen = os.time() -- used for the offline income
	local income = player:GetAttribute("IncomePerSec")
	if type(income) == "number" then
		data.LastIncome = income
	end
	local ok, err = pcall(store.UpdateAsync, store, key(player), function(old)
		local lock = type(old) == "table" and old._lock
		if type(lock) == "table" and lock.job ~= JOB then
			return nil -- another server took this save over: never overwrite its newer data
		end
		data._lock = (not release) and { job = JOB, t = os.time() } or nil
		return data
	end)
	if not ok then
		warn("[DataService] Save failed for", player.Name, err)
	end
end

function DataService.Release(player)
	profiles[player] = nil
	canSave[player] = nil
	released[player] = nil
end

return DataService
