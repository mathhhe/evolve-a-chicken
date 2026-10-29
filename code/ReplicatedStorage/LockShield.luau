-- LockShield: the force field of a locked base. Only looks: the server does the locking and sets the plot
-- attributes ShieldMin / ShieldMax (the box of the base's DomeWalls), ShieldGate (the entrance), DomeOn and
-- LockEnd, and sends WorldFX("ShieldHit", plot, position) when it pushes an intruder out.
-- StarterPlayerScripts.LockShieldClient builds one per base and calls update() every frame while it shows:
--   lock     -> shield generators pop out of the ground, energy walls grow between them and a big golden
--               padlock drops onto the gate with the seconds left on it;
--   locked   -> the walls shimmer, a light scans up them, sparkles rise, the generators' crystals spin;
--   bump     -> a ripple where somebody ran into it;
--   last 5 s -> everything turns red, the walls flicker and the padlock shakes;
--   unlock   -> the padlock pops open and shrinks away, walls and generators sink back into the ground.
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")

local LockShield = {}
LockShield.__index = LockShield

local H = 14 -- wall height (studs)
local RISE_TIME = 1.05 -- build animation (seconds)
local FALL_TIME = 0.8 -- take-down animation
local WARN_TIME = 5 -- the last seconds are red
local FLICKER_TIME = 3 -- ...and flicker
local FAR = 450 -- farther than this from the camera: no per-frame animation
local LOCK_SIZE = 1.25 -- size of the padlock
local PATTERN = "rbxassetid://7447638591" -- the stud tile of the UI, scrolling up the walls
local PATTERN_TILE = 4 -- studs
local GLOW_BAND = 1.1 -- the foot of the walls glows: bands of this height, fading out going up
-- how see-through the walls are: strong for everybody else, light for the owner (they keep playing inside)
local LOOK = {
	others = { tint = 0.9, pattern = 0.35, glow = { 0.45, 0.7, 0.86 } },
	owner = { tint = 0.96, pattern = 0.8, glow = { 0.7, 0.86, 0.94 } },
}

local CYAN = Color3.fromRGB(70, 205, 255)
local CYAN_HI = Color3.fromRGB(195, 246, 255)
local RED = Color3.fromRGB(255, 70, 62)
local RED_HI = Color3.fromRGB(255, 150, 130)
local METAL = Color3.fromRGB(48, 52, 68)
local METAL_HI = Color3.fromRGB(92, 100, 124)
local GOLD = Color3.fromRGB(255, 196, 40)
local GOLD_HI = Color3.fromRGB(255, 228, 112)
local GOLD_LO = Color3.fromRGB(212, 142, 22)
local STEEL = Color3.fromRGB(168, 176, 192)
local DARK = Color3.fromRGB(50, 36, 24)
local WHITE = Color3.new(1, 1, 1)
local TEXT_RED = Color3.fromRGB(255, 95, 85)

local SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local PING = "rbxasset://sounds/electronicpingshort.wav"
local CLICK = "rbxasset://sounds/clickfast.wav"

-- a cube standing on one corner (the generators' crystals)
local TILT = CFrame.Angles(math.rad(45), 0, math.rad(35.26))

-- easing: 0..1 -> 0..1 ----------------------------------------------------------------------------------
local function easeOut(x)
	x = math.clamp(x, 0, 1)
	return 1 - (1 - x) ^ 3
end

local function easeIn(x)
	x = math.clamp(x, 0, 1)
	return x * x * x
end

local function easeBack(x) -- goes a little past 1, then settles
	x = math.clamp(x, 0, 1)
	local c1 = 1.9
	return 1 + (c1 + 1) * (x - 1) ^ 3 + c1 * (x - 1) ^ 2
end

local function bounce(x) -- falls and bounces on the ground
	x = math.clamp(x, 0, 1)
	local n1, d1 = 7.5625, 2.75
	if x < 1 / d1 then
		return n1 * x * x
	elseif x < 2 / d1 then
		x -= 1.5 / d1
		return n1 * x * x + 0.75
	elseif x < 2.5 / d1 then
		x -= 2.25 / d1
		return n1 * x * x + 0.9375
	end
	x -= 2.625 / d1
	return n1 * x * x + 0.984375
end

-- building blocks -----------------------------------------------------------------------------------------
local function newPart(parent, name, size, color, material, shape)
	local p = Instance.new("Part")
	p.Name = name
	if shape then
		p.Shape = shape
	end
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Locked = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = material or Enum.Material.SmoothPlastic
	p.Color = color
	p.Size = size
	p.Parent = parent
	return p
end

local function playAt(parent, id, volume, speed)
	if not parent or not parent:IsDescendantOf(workspace) then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.PlaybackSpeed = speed
	s.RollOffMinDistance = 14
	s.RollOffMaxDistance = 180
	s.Parent = parent
	s:Play()
	Debris:AddItem(s, 3)
end

local function sparkles(parent, rate, speed, life, size)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = SPARKLE
	pe.Color = ColorSequence.new(CYAN_HI, CYAN)
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	pe.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	pe.Lifetime = NumberRange.new(life * 0.6, life)
	pe.Speed = NumberRange.new(speed * 0.5, speed)
	pe.Rate = rate
	pe.EmissionDirection = Enum.NormalId.Top
	pe.SpreadAngle = Vector2.new(12, 12)
	pe.Parent = parent
	return pe
end

-- the shield of one base ---------------------------------------------------------------------------------
function LockShield.new(plot, holder)
	local lo, hi = plot:GetAttribute("ShieldMin"), plot:GetAttribute("ShieldMax")
	if typeof(lo) ~= "Vector3" or typeof(hi) ~= "Vector3" then
		return nil
	end
	local self = setmetatable({}, LockShield)
	self.plot = plot
	self.holder = holder
	self.on = false
	self.visible = false
	self.state = "off" -- "off" | "rising" | "on" | "falling"
	self.stateAt = 0
	self.lockEnd = 0
	self.flashUntil = 0
	self.bulkParts, self.bulkCFs = {}, {}

	local model = Instance.new("Model")
	model.Name = "LockShield_" .. plot.Name
	self.model = model

	-- the walls stand on the grass around the base (the DomeWalls start on top of the base floor)
	local ground = lo.Y - 1
	self.ground = ground
	local center = Vector3.new((lo.X + hi.X) / 2, ground, (lo.Z + hi.Z) / 2)
	self.center = center
	local corners = {
		Vector3.new(lo.X, ground, lo.Z),
		Vector3.new(hi.X, ground, lo.Z),
		Vector3.new(hi.X, ground, hi.Z),
		Vector3.new(lo.X, ground, hi.Z),
	}
	-- the 4 sides; the gate side is the one closest to the base entrance
	local gatePos = plot:GetAttribute("ShieldGate")
	self.sides = {}
	local gate, best = nil, math.huge
	for i = 1, 4 do
		local a, b = corners[i], corners[i % 4 + 1]
		local mid = (a + b) / 2
		local s = { a = a, b = b, mid = mid, len = (b - a).Magnitude, dir = (b - a).Unit, out = ((mid - center) * Vector3.new(1, 0, 1)).Unit }
		table.insert(self.sides, s)
		if typeof(gatePos) == "Vector3" then
			local d = math.abs((gatePos - mid):Dot(s.out))
			if d < best then
				gate, best = s, d
			end
		end
	end
	gate = gate or self.sides[2]
	self.gateSide = gate
	local along = typeof(gatePos) == "Vector3" and math.clamp((gatePos - gate.a):Dot(gate.dir), 0, gate.len) or gate.len / 2
	self.gatePoint = gate.a + gate.dir * along

	self:buildWalls()
	self:buildPylons(corners)
	self:buildPadlock()
	return self
end

function LockShield:buildWalls()
	self.walls = {}
	for i, s in ipairs(self.sides) do
		local w = { side = s, phase = (i - 1) * 0.27 }
		-- X along the wall, Z across it
		w.base = CFrame.fromMatrix(s.mid, s.dir, Vector3.yAxis)
		w.wall = newPart(self.model, "Wall", Vector3.new(s.len, H, 0.3), CYAN, Enum.Material.ForceField)
		w.tint = newPart(self.model, "WallTint", Vector3.new(s.len, H, 0.1), CYAN, Enum.Material.Neon)
		-- a stud pattern on both faces (it scrolls up)
		w.patterns = {}
		for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
			local tx = Instance.new("Texture")
			tx.Texture = PATTERN
			tx.Face = face
			tx.StudsPerTileU = PATTERN_TILE
			tx.StudsPerTileV = PATTERN_TILE
			tx.Color3 = CYAN_HI
			tx.Parent = w.tint
			table.insert(w.patterns, tx)
		end
		-- the foot of the wall glows (bands that fade out going up)
		w.glow = {}
		for k = 1, 3 do
			w.glow[k] = newPart(self.model, "WallGlow", Vector3.new(s.len, GLOW_BAND, 0.16), CYAN, Enum.Material.Neon)
		end
		w.rail = newPart(self.model, "Rail", Vector3.new(s.len + 0.6, 0.45, 0.45), CYAN, Enum.Material.Neon)
		w.line = newPart(self.model, "GroundLine", Vector3.new(s.len, 0.16, 1.1), CYAN, Enum.Material.Neon)
		w.scan = newPart(self.model, "Scan", Vector3.new(s.len, 0.22, 0.22), CYAN_HI, Enum.Material.Neon)
		w.sparkles = sparkles(w.wall, math.max(2, s.len / 9), 2.6, 2.2, 0.55)
		self.walls[i] = w
	end
end

function LockShield:buildPylons(corners)
	-- a generator on every corner and one halfway along the two sides that run back from the gate
	local spots = table.clone(corners)
	for _, s in ipairs(self.sides) do
		if s ~= self.gateSide and math.abs(s.dir:Dot(self.gateSide.out)) > 0.9 then
			table.insert(spots, s.mid)
		end
	end
	local far = 1
	for _, p in ipairs(spots) do
		far = math.max(far, (p - self.gatePoint).Magnitude)
	end
	self.pylons = {}
	for _, pos in ipairs(spots) do
		-- (the ones next to the gate come up first)
		local py = { pos = pos, items = {}, glow = {}, delay = 0.3 * (pos - self.gatePoint).Magnitude / far, seed = math.random() * 6.3 }
		local function add(name, size, color, material, rel)
			local part = newPart(self.model, name, size, color, material)
			table.insert(py.items, { part = part, rel = rel })
			return part
		end
		add("Base", Vector3.new(3.2, 1, 3.2), METAL, nil, CFrame.new(0, 0.5, 0))
		add("Collar", Vector3.new(2.4, 0.6, 2.4), METAL_HI, nil, CFrame.new(0, 1.3, 0))
		add("Column", Vector3.new(1.3, H - 1.6, 1.3), METAL, nil, CFrame.new(0, 1.6 + (H - 1.6) / 2, 0))
		for k = 1, 3 do
			table.insert(py.glow, add("Ring", Vector3.new(1.75, 0.38, 1.75), CYAN, Enum.Material.Neon, CFrame.new(0, 1.6 + (H - 1.6) * k / 4, 0)))
		end
		add("Cap", Vector3.new(2.4, 0.6, 2.4), METAL_HI, nil, CFrame.new(0, H + 0.3, 0))
		py.crystal = newPart(self.model, "Crystal", Vector3.new(1.7, 1.7, 1.7), CYAN, Enum.Material.Neon)
		table.insert(py.glow, py.crystal)
		py.light = Instance.new("PointLight")
		py.light.Range = 13
		py.light.Brightness = 1.8
		py.light.Color = CYAN
		py.light.Shadows = false
		py.light.Parent = py.crystal
		py.burst = sparkles(py.crystal, 0, 10, 0.9, 0.9)
		py.burst.SpreadAngle = Vector2.new(180, 180)
		table.insert(self.pylons, py)
	end
end

function LockShield:buildPadlock()
	local lock = { items = {}, shackle = {}, labels = {} }
	self.lock = lock
	-- the body's centre hangs in the middle of the gate, just outside the wall; its front (-Z) faces the road
	local out = self.gateSide.out
	local c = self.gatePoint + out * 1.9 + Vector3.new(0, 4, 0)
	lock.origin = CFrame.lookAt(c, c + out)
	local function add(list, name, size, color, rel, shape)
		size *= LOCK_SIZE
		rel = CFrame.new(rel.Position * LOCK_SIZE) * rel.Rotation
		local part = newPart(self.model, name, size, color, nil, shape)
		table.insert(list, { part = part, rel = rel, size = size })
		return part
	end
	lock.body = add(lock.items, "Body", Vector3.new(4.4, 3.4, 1.7), GOLD, CFrame.new())
	add(lock.items, "Rim", Vector3.new(4.7, 0.45, 2), GOLD_LO, CFrame.new(0, 1.55, 0))
	add(lock.items, "Rim", Vector3.new(4.7, 0.45, 2), GOLD_LO, CFrame.new(0, -1.55, 0))
	for _, side in ipairs({ -1, 1 }) do
		-- -1 = the face towards the road, 1 = towards the base; each plate's Front face looks outwards
		local turn = side == 1 and CFrame.Angles(0, math.pi, 0) or CFrame.new()
		local plate = add(lock.items, "Plate", Vector3.new(3.7, 2.5, 0.12), GOLD_HI, CFrame.new(0, 0, side * 0.88) * turn)
		add(lock.items, "Keyhole", Vector3.new(0.12, 0.72, 0.72), DARK, CFrame.new(0, -0.5, side * 0.96) * CFrame.Angles(0, math.pi / 2, 0), Enum.PartType.Cylinder)
		add(lock.items, "KeySlot", Vector3.new(0.34, 0.55, 0.12), DARK, CFrame.new(0, -0.92, side * 0.96))
		-- the seconds left, on the plate
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 60
		sg.LightInfluence = 0
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(0.92, 0.56)
		t.Position = UDim2.fromScale(0.04, 0.01)
		t.Font = Enum.Font.FredokaOne
		t.TextScaled = true
		t.Text = ""
		t.TextColor3 = WHITE
		local stroke = Instance.new("UIStroke")
		stroke.Thickness = 5
		stroke.Color = DARK
		stroke.Parent = t
		t.Parent = sg
		sg.Parent = plate
		table.insert(lock.labels, t)
	end
	-- the shackle: 2 legs and the top bar; it pops up and swings open around its left leg
	add(lock.shackle, "Shackle", Vector3.new(0.75, 2.5, 0.75), STEEL, CFrame.new(-1.5, 2.85, 0))
	add(lock.shackle, "Shackle", Vector3.new(0.75, 2.5, 0.75), STEEL, CFrame.new(1.5, 2.85, 0))
	add(lock.shackle, "Shackle", Vector3.new(3.75, 0.75, 0.75), STEEL, CFrame.new(0, 3.725, 0))
	lock.hinge = Vector3.new(-1.5 * LOCK_SIZE, 0, 0)
	-- (already in place: its sounds play from here before the first frame)
	for _, list in ipairs({ lock.items, lock.shackle }) do
		for _, it in ipairs(list) do
			it.part.CFrame = lock.origin * it.rel
		end
	end
end

-- turning it on / off ---------------------------------------------------------------------------------------
function LockShield:show()
	if not self.visible then
		self.visible = true
		self.model.Parent = self.holder
	end
end

function LockShield:hide()
	if self.visible then
		self.visible = false
		self.model.Parent = nil
	end
end

-- on: the base is locked until server time `lockEnd`; instant = no animation (e.g. joining a server)
function LockShield:setOn(on, lockEnd, instant)
	if tonumber(lockEnd) then
		self.lockEnd = lockEnd
	end
	if on == self.on then
		return
	end
	self.on = on
	local clock = os.clock()
	self.colorKey, self.wallT, self.sparkling, self.shownSecs, self.placed = nil, nil, nil, nil, false
	if on then
		-- (the owner sees their own shield lighter)
		local me = Players.LocalPlayer
		self.look = (me and self.plot:GetAttribute("OwnerUserId") == me.UserId) and LOOK.owner or LOOK.others
		self:show()
		if instant then
			self.state, self.stateAt = "on", clock - RISE_TIME
		else
			self.state, self.stateAt = "rising", clock
			self.landed = false
			for _, py in ipairs(self.pylons) do
				py.up = false
			end
			self:shockwave()
			playAt(self.lock.body, PING, 0.8, 0.7)
		end
		-- (place everything now, so the first frame on screen is already right)
		self:update(workspace:GetServerTimeNow(), clock, self.center)
	elseif instant or not self.visible then
		self.state = "off"
		self:hide()
	else
		self.state, self.stateAt = "falling", clock
		self.popped = false
	end
end

-- a flash that runs over the ground from the gate when the shield goes up
function LockShield:shockwave()
	local at = Vector3.new(self.gatePoint.X, self.ground + 0.12, self.gatePoint.Z)
	local p = newPart(self.holder, "ShieldWave", Vector3.new(0.2, 2, 2), CYAN_HI, Enum.Material.Neon, Enum.PartType.Cylinder)
	p.Transparency = 0.45
	p.CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.pi / 2) -- flat on the ground
	TweenService:Create(p, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.2, 70, 70), Transparency = 1 }):Play()
	Debris:AddItem(p, 0.8)
end

-- somebody ran into it: a ripple on the closest wall
function LockShield:hit(position)
	if not self.visible or self.state == "falling" then
		return
	end
	local best, bestD, bestP
	for _, w in ipairs(self.walls) do
		local s = w.side
		local p = s.a + s.dir * math.clamp((position - s.a):Dot(s.dir), 0, s.len)
		local d = ((position - p) * Vector3.new(1, 0, 1)).Magnitude
		if not bestD or d < bestD then
			best, bestD, bestP = w, d, p
		end
	end
	if not best then
		return
	end
	local at = Vector3.new(bestP.X, math.clamp(position.Y, self.ground + 2, self.ground + H - 2), bestP.Z)
	local ring = newPart(self.holder, "ShieldRipple", Vector3.new(0.25, 1.5, 1.5), self.hiColor or CYAN_HI, Enum.Material.Neon, Enum.PartType.Cylinder)
	ring.Transparency = 0.15
	ring.CFrame = CFrame.lookAt(at, at + best.side.out) * CFrame.Angles(0, math.pi / 2, 0) -- facing out of the wall
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.25, 12, 12), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.5)
	self.flashUntil = os.clock() + 0.16
	playAt(ring, PING, 0.6, 0.5)
end

-- every frame while it shows (t = server time, clock = os.clock())
function LockShield:update(t, clock, camPos)
	if not self.visible then
		return
	end
	local e = clock - self.stateAt
	if self.state == "rising" and e >= RISE_TIME then
		self.state = "on"
	elseif self.state == "falling" and e >= FALL_TIME then
		self.state = "off"
		self:hide()
		return
	end
	local state = self.state
	local left = self.lockEnd - t
	local lock = self.lock

	-- seconds left on the padlock
	local secs = math.max(0, math.ceil(left))
	if secs ~= self.shownSecs then
		self.shownSecs = secs
		for _, l in ipairs(lock.labels) do
			l.Text = tostring(secs)
		end
	end
	if state == "on" and (self.center - camPos).Magnitude > FAR then
		return -- far away: it just stays as it is
	end

	-- colour: cyan; it turns red (quickly) in the last seconds; white for a moment when somebody bumps into it
	local k = math.clamp((WARN_TIME - left) / 0.8, 0, 1)
	local flash = clock < self.flashUntil
	local colorKey = math.floor(k * 20) + (flash and 100 or 0)
	if colorKey ~= self.colorKey then
		self.colorKey = colorKey
		local base = CYAN:Lerp(RED, k)
		local hi = CYAN_HI:Lerp(RED_HI, k)
		self.hiColor = hi
		if flash then
			base = hi
		end
		for _, w in ipairs(self.walls) do
			w.wall.Color = base
			w.tint.Color = base
			w.line.Color = base
			w.rail.Color = base
			w.scan.Color = hi
			for _, tx in ipairs(w.patterns) do
				tx.Color3 = hi
			end
			for _, g in ipairs(w.glow) do
				g.Color = base
			end
			w.sparkles.Color = ColorSequence.new(hi, base)
		end
		for _, py in ipairs(self.pylons) do
			for _, g in ipairs(py.glow) do
				g.Color = base
			end
			py.light.Color = base
			py.burst.Color = ColorSequence.new(hi, base)
		end
		for _, l in ipairs(lock.labels) do
			l.TextColor3 = WHITE:Lerp(TEXT_RED, k)
		end
	end

	local parts, cfs = self.bulkParts, self.bulkCFs
	table.clear(parts)
	table.clear(cfs)
	local n = 0
	-- while it just stands there only the crystals, the scan lines and the padlock move
	local moveAll = state ~= "on" or not self.placed
	self.placed = state == "on"

	-- generators: rise out of the ground one after the other (and sink back the same way)
	for _, py in ipairs(self.pylons) do
		local up = 1
		if state == "rising" then
			local kp = (e - py.delay) / 0.45
			up = easeBack(kp)
			if kp >= 1 and not py.up then
				py.up = true
				py.burst:Emit(16)
			end
		elseif state == "falling" then
			up = 1 - easeIn((e - 0.3 - py.delay * 0.4) / 0.35)
		end
		local dy = (up - 1) * (H + 3.5)
		if moveAll then
			local base = CFrame.new(py.pos.X, py.pos.Y + dy, py.pos.Z)
			for _, it in ipairs(py.items) do
				n += 1
				parts[n], cfs[n] = it.part, base * it.rel
			end
		end
		n += 1
		parts[n] = py.crystal
		cfs[n] = CFrame.new(py.pos.X, py.pos.Y + dy + H + 2.3 + math.sin(clock * 2 + py.seed) * 0.25, py.pos.Z)
			* CFrame.Angles(0, clock * 1.5 + py.seed, 0)
			* TILT
	end

	-- walls: grow up from the ground, shrink back into it
	local wh = H
	if state == "rising" then
		wh = H * easeOut((e - 0.18) / 0.55)
	elseif state == "falling" then
		wh = H * (1 - easeIn((e - 0.12) / 0.4))
	end
	local shown = wh > 0.15
	if wh ~= self.wallH then
		self.wallH = wh
		local hh = math.max(wh, 0.05)
		local band = GLOW_BAND * hh / H
		for _, w in ipairs(self.walls) do
			w.wall.Size = Vector3.new(w.side.len, hh, 0.3)
			w.tint.Size = Vector3.new(w.side.len, hh, 0.1)
			for _, g in ipairs(w.glow) do
				g.Size = Vector3.new(w.side.len, band, 0.16)
			end
		end
	end
	-- last seconds: the walls flicker
	local flicker = state == "on" and left < FLICKER_TIME and math.floor(clock * 9) % 2 == 0
	local wallT = (not shown) and 1 or (flicker and 0.6 or 0)
	if wallT ~= self.wallT then
		self.wallT = wallT
		local look = self.look or LOOK.others
		local function fade(x) -- transparency x while showing; more see-through when flickering; 1 when hidden
			return wallT >= 1 and 1 or (flicker and x + (1 - x) * 0.65 or x)
		end
		for _, w in ipairs(self.walls) do
			w.wall.Transparency = wallT
			w.tint.Transparency = fade(look.tint)
			w.rail.Transparency = wallT >= 1 and 1 or wallT * 0.5
			for _, tx in ipairs(w.patterns) do
				tx.Transparency = fade(look.pattern)
			end
			for k, g in ipairs(w.glow) do
				g.Transparency = fade(look.glow[k])
			end
		end
	end
	local sparkling = state == "on"
	if sparkling ~= self.sparkling then
		self.sparkling = sparkling
		for _, w in ipairs(self.walls) do
			w.sparkles.Enabled = sparkling
		end
	end
	for _, w in ipairs(self.walls) do
		if moveAll then
			local mid = w.base * CFrame.new(0, wh / 2, 0)
			n += 1
			parts[n], cfs[n] = w.wall, mid
			n += 1
			parts[n], cfs[n] = w.tint, mid
			n += 1
			parts[n], cfs[n] = w.rail, w.base * CFrame.new(0, wh, 0)
			n += 1
			parts[n], cfs[n] = w.line, w.base * CFrame.new(0, 0.1, 0)
			local band = GLOW_BAND * wh / H
			for k, g in ipairs(w.glow) do
				n += 1
				parts[n], cfs[n] = g, w.base * CFrame.new(0, (k - 0.5) * band, 0)
			end
		end
		-- the pattern scrolls up
		local offset = (clock * 1.1) % PATTERN_TILE
		for _, tx in ipairs(w.patterns) do
			tx.OffsetStudsV = offset
		end
		-- a light scans up the wall again and again
		local f = (clock * 0.42 + w.phase) % 1
		n += 1
		parts[n], cfs[n] = w.scan, w.base * CFrame.new(0, wh * f, 0)
		w.scan.Transparency = shown and (0.15 + 0.85 * f * f) or 1
	end

	-- the padlock: drops onto the gate and snaps shut; at the end it pops open and shrinks away
	local scale, drop, open, swing = 1, 0, 0, 0
	if state == "rising" then
		drop = (1 - bounce((e - 0.32) / 0.5)) * 11
		open = 1 - math.clamp((e - 0.86) / 0.1, 0, 1)
		if e >= 0.86 and not self.landed then
			self.landed = true
			playAt(lock.body, CLICK, 0.9, 0.8)
		end
	elseif state == "falling" then
		open = math.clamp(e / 0.12, 0, 1)
		swing = math.clamp((e - 0.06) / 0.14, 0, 1)
		if not self.popped then
			self.popped = true
			playAt(lock.body, CLICK, 0.9, 1.15)
			playAt(lock.body, PING, 0.5, 0.55)
		end
		scale = 1 - easeIn((e - 0.28) / 0.38)
	end
	scale = math.max(scale, 0.02)
	local shake = Vector3.zero
	if state == "on" and left < WARN_TIME then
		local m = 0.06 + 0.22 * math.clamp(1 - left / WARN_TIME, 0, 1)
		shake = Vector3.new((math.random() - 0.5) * m, (math.random() - 0.5) * m, 0)
	end
	local cf = lock.origin
		* CFrame.new(Vector3.new(0, drop + math.sin(clock * 2.3) * 0.18, 0) + shake)
		* CFrame.Angles(0, math.sin(clock * 1.4) * 0.07, 0)
	local resize = scale ~= self.lockScale
	self.lockScale = scale
	for _, it in ipairs(lock.items) do
		if resize then
			it.part.Size = it.size * scale
		end
		n += 1
		parts[n], cfs[n] = it.part, cf * CFrame.new(it.rel.Position * scale) * it.rel.Rotation
	end
	local hinge = lock.hinge * scale
	local sh = cf * CFrame.new(0, open * 1.2 * LOCK_SIZE * scale, 0) * CFrame.new(hinge) * CFrame.Angles(0, -swing * 0.9, 0) * CFrame.new(-hinge)
	for _, it in ipairs(lock.shackle) do
		if resize then
			it.part.Size = it.size * scale
		end
		n += 1
		parts[n], cfs[n] = it.part, sh * CFrame.new(it.rel.Position * scale) * it.rel.Rotation
	end

	workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

function LockShield:destroy()
	self:hide()
	self.model:Destroy()
end

return LockShield
