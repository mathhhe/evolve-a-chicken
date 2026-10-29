-- ReplicatedStorage.CashModels
-- Blocky 3D money for the shop's cash packs (shown in ViewportFrames, like the chicken previews).
--   CashModels.Build(tier) -> Model   tier 1 = small stack ... 5 = treasure chest
--   CashModels.View(parent, tier) -> ViewportFrame   (camera looks at the model from the front)
--   CashModels.Spin(vp, t)   slowly swings the camera around the money
local CashModels = {}

local GREEN = Color3.fromRGB(86, 178, 80)
local GREEN_DARK = Color3.fromRGB(58, 132, 56)
local BAND = Color3.fromRGB(238, 242, 214)
local GOLD = Color3.fromRGB(255, 192, 36)
local GOLD_LIGHT = Color3.fromRGB(255, 228, 110)
local WOOD = Color3.fromRGB(150, 94, 52)
local WOOD_DARK = Color3.fromRGB(108, 64, 34)
local SACK = Color3.fromRGB(218, 180, 116)
local SACK_DARK = Color3.fromRGB(176, 136, 80)

local function part(model, size, cf, color, shape)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Parent = model
	return p
end

-- one bundle of bills (2 x 0.34 x 0.95), cf = its centre
local BUNDLE = Vector3.new(2, 0.34, 0.95)
local function bundle(model, cf)
	part(model, BUNDLE, cf, GREEN)
	-- edge lines so it reads as a stack of notes
	for _, y in ipairs({ -0.085, 0.085 }) do
		part(model, Vector3.new(2.02, 0.035, 0.97), cf * CFrame.new(0, y, 0), GREEN_DARK)
	end
	-- paper band
	part(model, Vector3.new(0.42, 0.37, 0.98), cf, BAND)
end
-- gold bar (1.1 x 0.42 x 0.55)
local function goldBar(model, cf)
	part(model, Vector3.new(1.1, 0.42, 0.55), cf, GOLD)
	part(model, Vector3.new(0.86, 0.06, 0.38), cf * CFrame.new(0, 0.23, 0), GOLD_LIGHT)
end
-- coin lying flat
local function coin(model, cf)
	local r = CFrame.Angles(0, 0, math.rad(90))
	part(model, Vector3.new(0.14, 0.66, 0.66), cf * r, GOLD, Enum.PartType.Cylinder)
	part(model, Vector3.new(0.16, 0.46, 0.46), cf * r, GOLD_LIGHT, Enum.PartType.Cylinder)
end
-- stack of n bundles starting at cf (bottom bundle centre)
local function stack(model, cf, n, twist)
	for i = 0, n - 1 do
		local wobble = CFrame.Angles(0, math.rad(((i % 2 == 0) and 1 or -1) * (twist or 4)), 0)
		bundle(model, cf * CFrame.new(0, i * 0.36, 0) * wobble)
	end
end

-- "$" made of little blocks on the front of something (cf = centre of the sign, facing -Z)
local DOLLAR = {
	"..X..",
	".XXXX",
	"X.X..",
	".XXX.",
	"..X.X",
	"XXXX.",
	"..X..",
}
local function dollar(model, cf, px, color)
	for row, line in ipairs(DOLLAR) do
		for col = 1, #line do
			if line:sub(col, col) == "X" then
				local x = (col - 3) * px
				local y = (4 - row) * px
				part(model, Vector3.new(px, px, px * 0.6), cf * CFrame.new(x, y, 0), color)
			end
		end
	end
end

local builders = {}
-- 1: a small stack of cash + a coin
builders[1] = function(m)
	stack(m, CFrame.new(0, 0.17, 0), 3, 5)
	coin(m, CFrame.new(1.25, 0.07, -0.55))
end
-- 2: two stacks + coins
builders[2] = function(m)
	stack(m, CFrame.new(-0.62, 0.17, 0.25) * CFrame.Angles(0, math.rad(-8), 0), 4, 4)
	stack(m, CFrame.new(0.7, 0.17, -0.35) * CFrame.Angles(0, math.rad(10), 0), 3, 5)
	coin(m, CFrame.new(1.7, 0.07, -1.05))
	coin(m, CFrame.new(-1.75, 0.07, -0.85))
end
-- 3: a pyramid of bundles
builders[3] = function(m)
	local layers = { { 3, 0 }, { 2, 1 }, { 1, 2 } }
	for _, l in ipairs(layers) do
		local count, level = l[1], l[2]
		for i = 1, count do
			local x = (i - (count + 1) / 2) * 2.06
			for _, z in ipairs({ -0.5, 0.5 }) do
				bundle(m, CFrame.new(x, 0.17 + level * 0.36, z) * CFrame.Angles(0, math.rad((i + level) % 2 == 0 and 3 or -3), 0))
			end
		end
	end
	coin(m, CFrame.new(2.6, 0.07, -1.2))
	coin(m, CFrame.new(-2.7, 0.07, -1.0))
	goldBar(m, CFrame.new(0, 0.21, -1.55) * CFrame.Angles(0, math.rad(8), 0))
end
-- 4: a money bag with cash around it
builders[4] = function(m)
	part(m, Vector3.new(2.4, 1.5, 2.1), CFrame.new(0, 0.75, 0), SACK)
	part(m, Vector3.new(2.0, 0.5, 1.75), CFrame.new(0, 1.7, 0), SACK)
	part(m, Vector3.new(1.0, 0.36, 0.9), CFrame.new(0, 2.1, 0), SACK_DARK)
	part(m, Vector3.new(1.14, 0.2, 1.04), CFrame.new(0, 2.25, 0), WOOD_DARK)
	part(m, Vector3.new(1.5, 0.42, 1.3), CFrame.new(0, 2.5, 0), SACK)
	part(m, Vector3.new(2.42, 0.12, 2.12), CFrame.new(0, 0.06, 0), SACK_DARK)
	dollar(m, CFrame.new(0, 0.95, -1.08), 0.2, Color3.fromRGB(46, 128, 52))
	stack(m, CFrame.new(-2.05, 0.17, -0.45) * CFrame.Angles(0, math.rad(78), 0), 3, 4)
	stack(m, CFrame.new(2.0, 0.17, -0.3) * CFrame.Angles(0, math.rad(-75), 0), 2, 5)
	goldBar(m, CFrame.new(-0.85, 0.21, -1.6) * CFrame.Angles(0, math.rad(-12), 0))
	goldBar(m, CFrame.new(0.75, 0.21, -1.65) * CFrame.Angles(0, math.rad(10), 0))
	coin(m, CFrame.new(1.55, 0.07, -1.55))
end
-- 5: an open treasure chest full of money
builders[5] = function(m)
	local W, H, D = 3.4, 1.4, 1.9
	part(m, Vector3.new(W, H, D), CFrame.new(0, H / 2, 0), WOOD)
	-- gold trims
	for _, x in ipairs({ -W / 2 + 0.12, W / 2 - 0.12 }) do
		part(m, Vector3.new(0.3, H + 0.04, D + 0.06), CFrame.new(x, H / 2, 0), GOLD)
	end
	part(m, Vector3.new(W + 0.04, 0.22, D + 0.06), CFrame.new(0, H - 0.11, 0), GOLD)
	part(m, Vector3.new(W + 0.04, 0.16, D + 0.06), CFrame.new(0, 0.08, 0), WOOD_DARK)
	-- lock plate
	part(m, Vector3.new(0.5, 0.56, 0.12), CFrame.new(0, H - 0.4, -D / 2 - 0.05), GOLD)
	part(m, Vector3.new(0.16, 0.22, 0.14), CFrame.new(0, H - 0.46, -D / 2 - 0.08), WOOD_DARK)
	-- open lid, tilted back on the hinge
	local hinge = CFrame.new(0, H, D / 2) * CFrame.Angles(math.rad(105), 0, 0)
	part(m, Vector3.new(W, 0.42, D), hinge * CFrame.new(0, 0.21, -D / 2), WOOD)
	part(m, Vector3.new(W + 0.04, 0.46, 0.22), hinge * CFrame.new(0, 0.21, -D + 0.11), GOLD)
	part(m, Vector3.new(0.3, 0.46, D + 0.04), hinge * CFrame.new(-W / 2 + 0.12, 0.21, -D / 2), GOLD)
	part(m, Vector3.new(0.3, 0.46, D + 0.04), hinge * CFrame.new(W / 2 - 0.12, 0.21, -D / 2), GOLD)
	-- treasure poking out of the top
	local top = H + 0.02
	bundle(m, CFrame.new(-0.75, top + 0.1, -0.25) * CFrame.Angles(0, math.rad(8), math.rad(10)))
	bundle(m, CFrame.new(0.8, top + 0.12, 0.2) * CFrame.Angles(0, math.rad(-10), math.rad(-12)))
	bundle(m, CFrame.new(0.1, top + 0.38, -0.05) * CFrame.Angles(0, math.rad(20), 0))
	goldBar(m, CFrame.new(-0.95, top + 0.32, 0.45) * CFrame.Angles(0, math.rad(25), math.rad(8)))
	goldBar(m, CFrame.new(1.0, top + 0.42, -0.45) * CFrame.Angles(0, math.rad(-20), 0))
	goldBar(m, CFrame.new(0.15, top + 0.65, 0.35) * CFrame.Angles(math.rad(12), math.rad(60), 0))
	coin(m, CFrame.new(-0.2, top + 0.7, -0.5) * CFrame.Angles(math.rad(15), 0, math.rad(20)))
	coin(m, CFrame.new(1.35, top + 0.3, 0.55))
	-- spilled coins and a bar in front
	coin(m, CFrame.new(-2.1, 0.07, -1.25))
	coin(m, CFrame.new(1.9, 0.07, -1.35))
	coin(m, CFrame.new(2.35, 0.07, -0.7))
	goldBar(m, CFrame.new(-1.1, 0.21, -1.55) * CFrame.Angles(0, math.rad(-18), 0))
	bundle(m, CFrame.new(0.9, 0.17, -1.65) * CFrame.Angles(0, math.rad(12), 0))
end

-- Blocks that share a face plane flicker (z-fighting). For every such pair the smaller block's face is
-- pushed GAP studs in front of the bigger one's. Blocks are handled from biggest to smallest and each one only
-- moves against the bigger ones (already final), so pushes can't undo each other.
local GAP = 0.03
local AXES = { Vector3.xAxis, Vector3.yAxis, Vector3.zAxis }
local function faceList(p)
	local list = {}
	for a = 1, 3 do
		for _, sign in ipairs({ 1, -1 }) do
			local ln = AXES[a] * sign
			local u, v = AXES[a % 3 + 1], AXES[(a + 1) % 3 + 1]
			table.insert(list, {
				ln = ln,
				n = p.CFrame:VectorToWorldSpace(ln),
				c = p.CFrame:PointToWorldSpace(ln * p.Size / 2),
				u = p.CFrame:VectorToWorldSpace(u), hu = (u * p.Size).Magnitude / 2,
				v = p.CFrame:VectorToWorldSpace(v), hv = (v * p.Size).Magnitude / 2,
			})
		end
	end
	return list
end
local function reach(f, axis)
	return math.abs(f.u:Dot(axis)) * f.hu + math.abs(f.v:Dot(axis)) * f.hv
end
local function volume(p)
	return p.Size.X * p.Size.Y * p.Size.Z
end
local function deconflict(model)
	local parts = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			table.insert(parts, p)
		end
	end
	local order = {}
	for i, p in ipairs(parts) do
		order[p] = i
	end
	table.sort(parts, function(x, y)
		local vx, vy = volume(x), volume(y)
		if vx ~= vy then
			return vx > vy
		end
		return order[x] < order[y]
	end)
	for j = 2, #parts do
		local b = parts[j] -- the smaller one: it moves
		for _ = 1, 12 do
			local moved = false
			for i = 1, j - 1 do
				local a = parts[i]
				if (a.Position - b.Position).Magnitude < (a.Size.Magnitude + b.Size.Magnitude) / 2 then
					for _, fa in ipairs(faceList(a)) do
						for _, fb in ipairs(faceList(b)) do
							local d = (fb.c - fa.c):Dot(fa.n) -- how far b's face is in front of a's
							if fa.n:Dot(fb.n) > 0.9999 and math.abs(d) < GAP * 0.9 then
								local du, dv = (fb.c - fa.c):Dot(fa.u), (fb.c - fa.c):Dot(fa.v)
								local ou = math.min(fa.hu, du + reach(fb, fa.u)) - math.max(-fa.hu, du - reach(fb, fa.u))
								local ov = math.min(fa.hv, dv + reach(fb, fa.v)) - math.max(-fa.hv, dv - reach(fb, fa.v))
								if ou > 0.01 and ov > 0.01 then
									local grow = GAP - d
									local cf = b.CFrame
									b.Size += Vector3.new(math.abs(fb.ln.X), math.abs(fb.ln.Y), math.abs(fb.ln.Z)) * grow
									b.CFrame = cf * CFrame.new(fb.ln * (grow / 2))
									moved = true
								end
							end
						end
					end
				end
			end
			if not moved then
				break
			end
		end
	end
end

function CashModels.Build(tier)
	local m = Instance.new("Model")
	m.Name = "Cash" .. tostring(tier)
	local b = builders[math.clamp(tier or 1, 1, #builders)]
	b(m)
	deconflict(m)
	return m
end

local VIEW = Vector3.new(-0.35, 0.55, -1).Unit -- from the money towards the camera (front is -Z)
local SWING = 0.32 -- how far Spin turns the camera (radians)

-- camera distance so every block of the model fits the view (also while the camera swings)
local function fitDistance(model, fov, aspect)
	local corners = {}
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			local h = p.Size / 2
			for _, sx in ipairs({ -1, 1 }) do
				for _, sy in ipairs({ -1, 1 }) do
					for _, sz in ipairs({ -1, 1 }) do
						table.insert(corners, p.CFrame * Vector3.new(h.X * sx, h.Y * sy, h.Z * sz))
					end
				end
			end
		end
	end
	local cf = model:GetBoundingBox()
	local center = cf.Position
	local t = math.tan(math.rad(fov / 2)) * 0.92
	local best = 0
	for _, a in ipairs({ -SWING, 0, SWING }) do
		local dir = CFrame.Angles(0, a, 0) * VIEW
		local look = CFrame.lookAt(center + dir, center)
		for _, corner in ipairs(corners) do
			local rel = corner - center
			local s = rel:Dot(dir)
			local x = math.abs(rel:Dot(look.RightVector))
			local y = math.abs(rel:Dot(look.UpVector))
			best = math.max(best, s + y / t, s + x / (t * aspect))
		end
	end
	return center, best
end

-- aspect = width / height of the viewport
function CashModels.View(parent, tier, aspect)
	local old = parent:FindFirstChild("Cash3D")
	if old and old:GetAttribute("Tier") == tier then
		return old
	end
	if old then
		old:Destroy()
	end
	local ok, model = pcall(CashModels.Build, tier)
	if not ok or not model then
		return nil
	end
	local vp = Instance.new("ViewportFrame")
	vp.Name = "Cash3D"
	vp.BackgroundTransparency = 1
	vp.AnchorPoint = Vector2.new(0.5, 0.5)
	vp.Position = UDim2.fromScale(0.5, 0.5)
	vp.Size = UDim2.fromScale(1, 1)
	vp.ZIndex = parent.ZIndex
	vp.Ambient = Color3.fromRGB(180, 178, 186)
	vp.LightColor = Color3.fromRGB(255, 250, 238)
	vp.LightDirection = Vector3.new(-0.4, -1, 0.55)
	model.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	local center, dist = fitDistance(model, cam.FieldOfView, aspect or 1.6)
	dist *= 0.8 -- the fit is a bit loose (block corners), this fills the frame without clipping
	cam.CFrame = CFrame.lookAt(center + VIEW * dist, center)
	vp:SetAttribute("Tier", tier)
	vp:SetAttribute("Center", center)
	vp:SetAttribute("Dist", dist)
	vp.Parent = parent
	return vp
end

function CashModels.Spin(vp, t)
	local cam = vp and vp.CurrentCamera
	if not cam then
		return
	end
	local center, dist = vp:GetAttribute("Center"), vp:GetAttribute("Dist")
	if not center or not dist then
		return
	end
	local dir = CFrame.Angles(0, math.sin(t * 0.7 + (vp:GetAttribute("Tier") or 0)) * SWING, 0) * VIEW
	cam.CFrame = CFrame.lookAt(center + dir * dist, center)
end

return CashModels
