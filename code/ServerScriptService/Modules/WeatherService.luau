-- WeatherService: server weather events (Toxic Rain, Glitch Storm, Void Rain...).
-- Used by GameServer (natural events + road mutations) and AdminService (admins can start/stop events).
-- The state lives in workspace attributes so every client can draw it (StarterPlayerScripts.WeatherClient):
--   Weather      = id of the active event ("" = clear sky)
--   WeatherStart = server time it started
--   WeatherEnds  = server time it ends
--   WeatherNext  = server time of the next natural event
-- Nothing here touches cash, chickens or saved data.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

local WeatherService = {}
local rng = Random.new()
local nextNatural = math.huge
local started = false

local function now()
	return workspace:GetServerTimeNow()
end

local function announce(text, style)
	local remotes = ReplicatedStorage:FindFirstChild("Remotes")
	local notifyRE = remotes and remotes:FindFirstChild("Notify")
	if notifyRE then
		notifyRE:FireAllClients(text, style)
	end
end

local function scheduleNext(after)
	local every = Config.Weather.Every
	nextNatural = after + rng:NextNumber(every[1], every[2])
	workspace:SetAttribute("WeatherNext", nextNatural)
end

-- the active event (or nil)
function WeatherService.Current()
	local w = Config.WeatherById[workspace:GetAttribute("Weather") or ""]
	if w and (workspace:GetAttribute("WeatherEnds") or 0) > now() then
		return w
	end
	return nil
end

-- mutation a new road chicken gets from the weather (nil = none)
function WeatherService.RollMutation()
	local w = WeatherService.Current()
	if w and rng:NextNumber() < w.Chance then
		return w.Mutation
	end
	return nil
end

-- starts an event (replaces the current one). by = display name of the admin who summoned it
function WeatherService.Start(id, duration, by)
	local w = Config.WeatherById[id]
	if not w then
		return false
	end
	duration = math.clamp(tonumber(duration) or Config.Weather.Duration, 20, 600)
	local t = now()
	workspace:SetAttribute("WeatherStart", t)
	workspace:SetAttribute("WeatherEnds", t + duration)
	workspace:SetAttribute("Weather", w.Id)
	scheduleNext(t + duration)
	local mut = Config.MutationById[w.Mutation]
	local msg = string.upper(w.Name) .. "! More " .. string.upper(mut.Name) .. " chickens on the road!"
	if by then
		msg = by .. " summoned a " .. msg
	end
	announce(msg, "Rare")
	return true
end

function WeatherService.Stop(quiet)
	local w = WeatherService.Current()
	workspace:SetAttribute("Weather", "")
	workspace:SetAttribute("WeatherEnds", 0)
	scheduleNext(now())
	if w and not quiet then
		announce("The " .. w.Name .. " is over.", "Info")
	end
end

local function pickNatural()
	local total = 0
	for _, w in ipairs(Config.Weathers) do
		total += w.Weight
	end
	local r = rng:NextNumber() * total
	for _, w in ipairs(Config.Weathers) do
		r -= w.Weight
		if r <= 0 then
			return w
		end
	end
	return Config.Weathers[1]
end

-- starts the natural weather cycle (called once by GameServer)
function WeatherService.Init()
	if started then
		return
	end
	started = true
	workspace:SetAttribute("Weather", "")
	workspace:SetAttribute("WeatherEnds", 0)
	nextNatural = now() + Config.Weather.FirstDelay
	workspace:SetAttribute("WeatherNext", nextNatural)
	task.spawn(function()
		while true do
			task.wait(1)
			local t = now()
			local id = workspace:GetAttribute("Weather") or ""
			if id ~= "" then
				if t >= (workspace:GetAttribute("WeatherEnds") or 0) then
					WeatherService.Stop()
				end
			elseif t >= nextNatural then
				WeatherService.Start(pickNatural().Id)
			end
		end
	end)
end

return WeatherService
