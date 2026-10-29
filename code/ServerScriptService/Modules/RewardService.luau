-- RewardService: offline income, daily rewards (7-day streak) and playtime gifts.
-- Numbers live in ReplicatedStorage.Config (Offline, DailyRewards, PlaytimeGifts). The UI is StarterPlayerScripts.RewardsClient.
-- GameServer calls RewardService.Init(api) once and RewardService.OnPlayerReady(player) after a player's base is built.
--
-- What the client sees (player attributes):
--   OfflineReward = JSON { amount, seconds }   (set once when they come back, the client shows a welcome popup)
--   Daily         = JSON { canClaim, streak, day, reset }  (day = 1..7 of the cycle to claim / claimed today)
--   PlaytimeSec   = seconds played today        GiftsClaimed = JSON { ["1"] = true, ... }
--   CashBoostUntil = os.time() when the personal 2x Cash from rewards ends (GameServer multiplies eggs by CashBoost())
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local DataService = require(script.Parent:WaitForChild("DataService"))

local RewardService = {}
local api -- { addCash, notify, notifyAll, findFreeSlot, placeChicken }
local ready = {} -- [player] = true once their base is built

local function income(player)
	return tonumber(player:GetAttribute("IncomePerSec")) or 0
end

-- Daily ----------------------------------------------------------------------------------------------------
local function dailyInfo(d)
	d.Daily = d.Daily or { Streak = 0 }
	local today = Config.DayNumber()
	local last = d.Daily.LastDay
	local canClaim = last ~= today
	local streak
	if canClaim then
		streak = (last == today - 1) and (d.Daily.Streak or 0) + 1 or 1
	else
		streak = math.max(1, d.Daily.Streak or 1)
	end
	local day = ((streak - 1) % #Config.DailyRewards) + 1
	return canClaim, streak, day
end

local function syncDaily(player, d)
	local canClaim, streak, day = dailyInfo(d)
	player:SetAttribute("Daily", HttpService:JSONEncode({
		canClaim = canClaim,
		streak = streak,
		day = day,
		reset = (Config.DayNumber() + 1) * 86400, -- when the next day starts (os.time)
	}))
end

-- Playtime gifts -------------------------------------------------------------------------------------------
local function playtime(d)
	local today = Config.DayNumber()
	if type(d.Playtime) ~= "table" or d.Playtime.Day ~= today then
		d.Playtime = { Day = today, Sec = 0, Claimed = {} }
	end
	return d.Playtime
end

local function syncGifts(player, d)
	local pt = playtime(d)
	player:SetAttribute("PlaytimeSec", pt.Sec)
	player:SetAttribute("GiftsClaimed", HttpService:JSONEncode(pt.Claimed))
end

-- Reward chicken: the rarity of the best chicken in their base ("Best") or one below it ("Lower"),
-- with a lab mutation when `mutated`
local function giveRewardChicken(player, d, kind, mutated)
	local best = 1
	for _, id in pairs(d.Slots or {}) do
		local def = Config.ChickenById[id]
		if def then
			best = math.max(best, Config.RarityIndex[def.Rarity] or 1)
		end
	end
	local rarity = math.max(1, best + (kind == "Lower" and -1 or 0))
	local def = Config.PickInRarity(Config.Rarities[rarity].Name)
	local mut = mutated and Config.RollMutation(nil, nil, Config.LabMutation) or nil
	local name = (mut and Config.MutationById[mut] and (Config.MutationById[mut].Name .. " ") or "") .. def.Name
	local slot = api.findFreeSlot(player)
	if slot then
		api.placeChicken(player, slot, def.Id, mut)
		return "a " .. name
	end
	-- base full: its value in cash instead
	local value = math.floor(def.Price * Config.MutationMult(mut))
	api.addCash(player, value, true)
	return "$" .. Config.Format(value) .. " (base full, so the " .. name .. " was sold for you)"
end

-- personal 2x Cash (saved, so it survives a rejoin; it keeps counting down while away)
function RewardService.CashBoost(player)
	return (tonumber(player:GetAttribute("CashBoostUntil")) or 0) > os.time() and Config.RewardBoostMult or 1
end
local function startBoost(player, d, minutes)
	d.CashBoostUntil = math.max(os.time(), tonumber(d.CashBoostUntil) or 0) + minutes * 60
	player:SetAttribute("CashBoostUntil", d.CashBoostUntil)
end

-- Server Luck x2 for everyone (same as the LuckBoost product)
local function startServerLuck(player, minutes)
	local t = workspace:GetServerTimeNow()
	workspace:SetAttribute("ServerLuckUntil", math.max(t, workspace:GetAttribute("ServerLuckUntil") or 0) + minutes * 60)
	if api.notifyAll then
		api.notifyAll(player.DisplayName .. " got SERVER LUCK x2 from a reward! Rare chickens x2 for everyone!", "Rare")
	end
end

-- gives everything in a reward (Config.DailyRewards / PlaytimeGifts entry) and returns the toast text
local function grant(player, d, r, label)
	local parts = {}
	local cash = Config.RewardCash(income(player), r.Minutes, r.Min)
	if cash > 0 then
		api.addCash(player, cash, true)
		table.insert(parts, "+$" .. Config.Format(cash))
	end
	if r.Chicken then
		table.insert(parts, giveRewardChicken(player, d, r.Chicken, r.Mutated))
	end
	if r.Boost then
		startBoost(player, d, r.Boost)
		table.insert(parts, Config.RewardBoostMult .. "x Cash for " .. r.Boost .. " min")
	end
	if r.Luck then
		startServerLuck(player, r.Luck)
		table.insert(parts, "Server Luck x2 for " .. r.Luck .. " min")
	end
	local text = table.concat(parts, ", ", 1, math.max(1, #parts - 1))
	if #parts > 1 then
		text ..= " and " .. parts[#parts]
	end
	return label .. ": " .. text .. "!"
end

local function claimDaily(player, d)
	local canClaim, streak, day = dailyInfo(d)
	if not canClaim then
		return false, "Come back tomorrow for your next daily reward!"
	end
	local r = Config.DailyRewards[day]
	d.Daily.Streak = streak
	d.Daily.LastDay = Config.DayNumber()
	local msg = grant(player, d, r, "Day " .. day .. " reward")
	syncDaily(player, d)
	return true, msg
end

local function claimGift(player, d, i)
	local g = type(i) == "number" and Config.PlaytimeGifts[i]
	if not g then
		return false, "Unknown gift."
	end
	local pt = playtime(d)
	if pt.Claimed[tostring(i)] then
		return false, "You already opened this gift today!"
	end
	if pt.Sec < g.At * 60 then
		return false, "Keep playing to unlock this gift!"
	end
	pt.Claimed[tostring(i)] = true
	local msg = grant(player, d, g, "Gift opened")
	syncGifts(player, d)
	return true, msg
end

-- Offline income -------------------------------------------------------------------------------------------
local function offlineIncome(player, d)
	local last = tonumber(d.LastSeen)
	local rate = tonumber(d.LastIncome) or 0
	if not last or rate <= 0 then
		return
	end
	local away = os.time() - last
	if away < Config.Offline.MinSeconds then
		return
	end
	local counted = math.min(away, Config.Offline.MaxHours * 3600)
	local amount = math.floor(rate * counted * Config.Offline.Rate)
	if amount <= 0 then
		return
	end
	d.LastSeen = os.time() -- can't be collected twice
	api.addCash(player, amount, true)
	player:SetAttribute("OfflineReward", HttpService:JSONEncode({ amount = amount, seconds = away, counted = counted }))
end

-- API ------------------------------------------------------------------------------------------------------
function RewardService.Init(a)
	api = a
	local remotes = ReplicatedStorage:WaitForChild("Remotes")
	local rf = Instance.new("RemoteFunction")
	rf.Name = "Rewards" -- ("ClaimDaily") | ("ClaimGift", index) -> ok, message
	rf.Parent = remotes
	local lastAsk = {}
	rf.OnServerInvoke = function(player, action, arg)
		local d = DataService.Get(player)
		if not d or not ready[player] then
			return false, "Still loading..."
		end
		if os.clock() - (lastAsk[player] or 0) < 0.5 then
			return false, "Wait a moment..."
		end
		lastAsk[player] = os.clock()
		local ok, msg = false, "Unknown action."
		if action == "ClaimDaily" then
			ok, msg = claimDaily(player, d)
		elseif action == "ClaimGift" then
			ok, msg = claimGift(player, d, arg)
		end
		api.notify(player, msg, ok and "Success" or "Error")
		return ok, msg
	end
	Players.PlayerRemoving:Connect(function(player)
		ready[player] = nil
		lastAsk[player] = nil
	end)

	-- playtime counter (and the daily state flips at midnight UTC)
	task.spawn(function()
		local STEP = 5
		local lastDay = Config.DayNumber()
		while true do
			task.wait(STEP)
			local dayChanged = Config.DayNumber() ~= lastDay
			lastDay = Config.DayNumber()
			for player in pairs(ready) do
				local d = DataService.Get(player)
				if d and player.Parent then
					local pt = playtime(d)
					pt.Sec += STEP
					syncGifts(player, d)
					if dayChanged then
						syncDaily(player, d)
					end
				end
			end
		end
	end)
end

function RewardService.OnPlayerReady(player)
	local d = DataService.Get(player)
	if not d or not api then
		return
	end
	ready[player] = true
	if (tonumber(d.CashBoostUntil) or 0) > os.time() then
		player:SetAttribute("CashBoostUntil", d.CashBoostUntil)
	end
	offlineIncome(player, d)
	syncDaily(player, d)
	syncGifts(player, d)
end

return RewardService
