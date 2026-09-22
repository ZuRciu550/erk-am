--[[
	VelocityHUB UI Library  |  v1.0.0

	VelocityHUB - a modern Rayfield-style script hub library.

	API OVERVIEW
	------------------------------------------------------------------
	local Window = VelocityHUB:CreateWindow({ Name = "My Hub", ToggleKey = Enum.KeyCode.RightShift })
	local Tab    = Window:CreateTab("Main", "rbxassetid://0000")   -- icon is optional

	Tab:CreateSection("Title")
	Tab:CreateLabel("Some text")
	Tab:CreateButton({ Name, Callback })
	Tab:CreateToggle({ Name, CurrentValue, Flag, Callback(bool) })
	Tab:CreateSlider({ Name, Range = {min,max}, Increment, Suffix, CurrentValue, Flag, Callback(number) })
	Tab:CreateColorPicker({ Name, Color, Flag, Callback(Color3) })
	Tab:CreateKeybind({ Name, CurrentKeybind, Flag, Callback(KeyCode), OnChange(KeyCode) })
	Tab:CreateDivider()
	Tab:CreateTextBox({ Name, CurrentValue, PlaceholderText, NumbersOnly, Min, Max, Flag, Callback(value, enterPressed) })
	Tab:CreateDropdown({ Name, Options = {"A","B"}, CurrentOption, Flag, Callback(option) })

	Window:Notify({ Title, Content, Duration, Type = "Info" | "Success" | "Error" })
	Window:Toggle() / Window:Destroy()
	Window:CreateButton / CreateSlider / ... also work (they go to the last tab created).
	VelocityHUB.Flags["MyFlag"].CurrentValue   -- read any element by its Flag
	------------------------------------------------------------------
]]

--==================================================================--
--  CONFIGURATION  (edit these)
--==================================================================--
local Config = {
	UseKeySystem = true,                        -- true = key screen first, false = skip it

	Key      = "VELOCITY_2026",                 -- the correct key (hardcoded)
	KeyLink  = "https://discord.gg/QVTsmm352y",-- copied to clipboard by the "Get Key" button
	KeyHint  = "Join our Discord server and open the #key channel to receive key.",

	Name        = "VelocityHUB",
	ToggleKey   = Enum.KeyCode.RightControl,    -- default key to open / close the GUI
	AccentColor = Color3.fromRGB(108, 92, 255), -- default theme color
	ShowBanner  = true,                         -- banner image used as the window background

	LogoId   = "rbxassetid://79065395294292",
	BannerId = "rbxassetid://86528416919779",
}

--==================================================================--
--  SERVICES
--==================================================================--
local Players          = game:GetService("Players")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local GuiService       = game:GetService("GuiService")
local Lighting         = game:GetService("Lighting")
local ContentProvider  = game:GetService("ContentProvider")
local CoreGui          = game:GetService("CoreGui")

--==================================================================--
--  THEME
--==================================================================--
local Theme = {
	Background = Color3.fromRGB(15, 15, 21),
	Sidebar    = Color3.fromRGB(19, 19, 27),
	Card       = Color3.fromRGB(27, 27, 38),
	CardHover  = Color3.fromRGB(36, 36, 50),
	Input      = Color3.fromRGB(20, 20, 29),
	Off        = Color3.fromRGB(58, 58, 78),
	Stroke     = Color3.fromRGB(46, 46, 64),
	Text       = Color3.fromRGB(240, 240, 250),
	SubText    = Color3.fromRGB(148, 148, 172),
	Success    = Color3.fromRGB(80, 220, 140),
	Danger     = Color3.fromRGB(255, 90, 105),
	Accent     = Config.AccentColor,
}

-- Typography: change these three lines to restyle every text in the library.
local Fonts = {
	Regular = Enum.Font.Gotham,
	Medium  = Enum.Font.GothamMedium,
	Bold    = Enum.Font.GothamBold,
}

-- Anything that uses the accent color registers here so the Settings color picker can recolor it live.
local accentBinds = {}
local function onAccent(fn)
	table.insert(accentBinds, fn)
	fn(Theme.Accent)
end
local function bindAccent(inst, prop)
	onAccent(function(c) inst[prop] = c end)
end
local function setAccent(c)
	Theme.Accent = c
	for _, fn in ipairs(accentBinds) do fn(c) end
end

-- Background transparency (Settings slider). base = minimum transparency of that surface.
local bgBinds = {}
local bgTransparency = 0
local function bindBG(inst, prop, base)
	local function apply() inst[prop] = base + (1 - base) * bgTransparency end
	table.insert(bgBinds, apply)
	apply()
end
local function setBGTransparency(t)
	bgTransparency = t
	for _, fn in ipairs(bgBinds) do fn() end
end
-- custom background-aware updater (used for the banner layers and the shadow)
local function bindBGFn(fn)
	table.insert(bgBinds, fn)
	fn()
end

--==================================================================--
--  UTILITIES
--==================================================================--
local function create(class, props, children)
	local inst = Instance.new(class)
	if inst:IsA("GuiObject") then
		inst.BorderSizePixel = 0
	end
	if inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox") then
		inst.BackgroundTransparency = 1
		inst.Font = Fonts.Medium
		inst.TextColor3 = Theme.Text
		inst.TextSize = 13
		inst.Text = ""
		inst.TextXAlignment = Enum.TextXAlignment.Left
	end
	if inst:IsA("TextButton") or inst:IsA("ImageButton") then
		inst.AutoButtonColor = false
	end
	if inst:IsA("ImageLabel") or inst:IsA("ImageButton") then
		inst.BackgroundTransparency = 1
	end
	local parent
	for k, v in pairs(props or {}) do
		if k == "Parent" then parent = v else inst[k] = v end
	end
	for _, child in ipairs(children or {}) do child.Parent = inst end
	if parent then inst.Parent = parent end
	return inst
end

local function newLabel(props) return create("TextLabel", props) end

local function tween(inst, props, duration, style, direction)
	local t = TweenService:Create(inst, TweenInfo.new(duration or 0.25, style or Enum.EasingStyle.Quint, direction or Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function corner(inst, radius)
	return create("UICorner", { CornerRadius = UDim.new(0, radius), Parent = inst })
end

local function stroke(inst, color, thickness, transparency)
	return create("UIStroke", { Color = color, Thickness = thickness or 1, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = inst })
end

local function lighten(c, a) return c:Lerp(Color3.new(1, 1, 1), a) end

-- Layered, ultra-soft drop shadow: four stacked 9-slice layers give a smooth falloff instead of one hard halo.
-- fade: 0 = fully visible, 1 = invisible.  minDim: approx. smallest side of the parent (keeps the 9-slice clean).
-- Must be a SIBLING placed behind the frame it decorates.
local SHADOW_IMAGE = "rbxassetid://6014261993"

local function setShadowFade(shadow, fade)
	for _, layer in ipairs(shadow:GetChildren()) do
		if layer:IsA("ImageLabel") then
			local base = layer:GetAttribute("Base") or 0.8
			layer.ImageTransparency = base + (1 - base) * fade
		end
	end
end

local function tweenShadow(shadow, fade, duration)
	for _, layer in ipairs(shadow:GetChildren()) do
		if layer:IsA("ImageLabel") then
			local base = layer:GetAttribute("Base") or 0.8
			tween(layer, { ImageTransparency = base + (1 - base) * fade }, duration or 0.3)
		end
	end
end

local function createShadow(parent, spread, fade, minDim)
	spread = spread or 30
	minDim = minDim or 200
	local holder = create("Frame", {
		Name = "Shadow", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, math.floor(spread * 0.25)), Size = UDim2.fromScale(1, 1), ZIndex = 0, Parent = parent,
	})
	local layers = { { 1.00, 0.93 }, { 0.72, 0.88 }, { 0.46, 0.82 }, { 0.22, 0.74 } } -- { spread multiplier, transparency }
	for _, l in ipairs(layers) do
		local sp = spread * l[1]
		local img = create("ImageLabel", {
			Image = SHADOW_IMAGE, ImageColor3 = Color3.new(0, 0, 0),
			ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(49, 49, 450, 450),
			SliceScale = math.clamp((minDim + sp * 2) / 110, 0.25, 1),
			AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, sp * 2, 1, sp * 2), ZIndex = 0, Parent = holder,
		})
		img:SetAttribute("Base", l[2])
	end
	setShadowFade(holder, fade or 0)
	return holder
end

local function safeCall(fn, ...)
	if type(fn) ~= "function" then return end
	local ok, err = pcall(fn, ...)
	if not ok then warn("[VelocityHUB] Callback error: " .. tostring(err)) end
end

-- Global (UserInputService) connections are tracked so Destroy() can clean them up.
local Connections = {}
local function connect(signal, fn)
	local c = signal:Connect(fn)
	table.insert(Connections, c)
	return c
end

local State = { Listening = false } -- true while any keybind element is capturing a key

local function isPress(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- Hover color tween
local function addHover(hit, target, getBase, getHover)
	hit.MouseEnter:Connect(function() tween(target, { BackgroundColor3 = getHover() }, 0.2) end)
	hit.MouseLeave:Connect(function() tween(target, { BackgroundColor3 = getBase() }, 0.25) end)
end

-- Press "squish" effect
local function addPress(hit, target, amount)
	local scale = create("UIScale", { Parent = target })
	hit.MouseButton1Down:Connect(function() tween(scale, { Scale = amount or 0.97 }, 0.1) end)
	local function release() tween(scale, { Scale = 1 }, 0.35, Enum.EasingStyle.Back) end
	hit.MouseButton1Up:Connect(release)
	hit.MouseLeave:Connect(release)
end

-- Material-style ripple, drawn inside `card`
local function ripple(card, x, y)
	local size = math.max(card.AbsoluteSize.X, card.AbsoluteSize.Y) * 2.4
	local r = create("Frame", {
		BackgroundColor3 = Theme.Accent,
		BackgroundTransparency = 0.72,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(x - card.AbsolutePosition.X, y - card.AbsolutePosition.Y),
		Size = UDim2.fromOffset(0, 0),
		ZIndex = 0,
		Parent = card,
	})
	corner(r, 999)
	tween(r, { Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, 0.65, Enum.EasingStyle.Quad)
	task.delay(0.7, function() r:Destroy() end)
end

-- Generic drag tracker for sliders / color areas. onUpdate receives x,y in 0..1 relative to `hit`.
local function trackDrag(hit, onUpdate, onStart, onEnd)
	local dragging = false
	local function update(pos)
		local abs, size = hit.AbsolutePosition, hit.AbsoluteSize
		onUpdate(
			math.clamp((pos.X - abs.X) / math.max(size.X, 1), 0, 1),
			math.clamp((pos.Y - abs.Y) / math.max(size.Y, 1), 0, 1)
		)
	end
	hit.InputBegan:Connect(function(input)
		if isPress(input) then
			dragging = true
			if onStart then onStart() end
			update(input.Position)
			local c
			c = input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
					if onEnd then onEnd() end
					c:Disconnect()
				end
			end)
		end
	end)
	connect(UserInputService.InputChanged, function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
			update(input.Position)
		end
	end)
end

local function decimalsOf(n)
	local frac = tostring(n):match("%.(%d+)")
	return frac and #frac or 0
end

--==================================================================--
--  ROOT GUI
--==================================================================--
local function resolveContainer()
	local getters = {
		function() return gethui() end,
		function() return CoreGui end,
		function() return Players.LocalPlayer:WaitForChild("PlayerGui") end,
	}
	for _, get in ipairs(getters) do
		local ok, container = pcall(get)
		if ok and container then
			local writable = pcall(function()
				local probe = Instance.new("Folder")
				probe.Parent = container
				probe:Destroy()
			end)
			if writable then return container end
		end
	end
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local Container = resolveContainer()
local previous = Container:FindFirstChild("VelocityHUB")
if previous then previous:Destroy() end

local ScreenGui = create("ScreenGui", {
	Name = "VelocityHUB",
	ResetOnSpawn = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	DisplayOrder = 999,
	Parent = Container,
})
pcall(function() if syn and syn.protect_gui then syn.protect_gui(ScreenGui) end end)

local VelocityHUB = { Config = Config, Theme = Theme, Flags = {} }

function VelocityHUB:Destroy()
	for _, c in ipairs(Connections) do pcall(function() c:Disconnect() end) end
	table.clear(Connections)
	for _, obj in ipairs(Lighting:GetChildren()) do
		if obj:IsA("BlurEffect") and obj.Name == "VelocityBlur" then obj:Destroy() end
	end
	ScreenGui:Destroy()
end

--==================================================================--
--  NOTIFICATIONS
--==================================================================--
local NotifyHolder = create("Frame", {
	Name = "Notifications",
	BackgroundTransparency = 1,
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, -20, 1, -20),
	Size = UDim2.new(0, 290, 1, -40),
	ZIndex = 50,
	Parent = ScreenGui,
}, {
	create("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 8) }),
})

function VelocityHUB:Notify(opts)
	opts = opts or {}
	local duration = opts.Duration or 4
	local color = Theme.Accent
	if opts.Type == "Success" then color = Theme.Success elseif opts.Type == "Error" then color = Theme.Danger end

	local wrapper = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 70), Parent = NotifyHolder })
	local mover = create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Position = UDim2.new(1, 330, 0, 0), Parent = wrapper })
	createShadow(mover, 24, 0, 70)
	local card = create("Frame", { BackgroundColor3 = Theme.Card, Size = UDim2.fromScale(1, 1), ClipsDescendants = true, Parent = mover })
	corner(card, 10)
	stroke(card, Theme.Stroke, 1, 0.3)
	local bar = create("Frame", { BackgroundColor3 = color, Position = UDim2.new(0, 8, 0, 12), Size = UDim2.new(0, 3, 1, -24), Parent = card })
	corner(bar, 2)
	newLabel({ Text = opts.Title or "VelocityHUB", Font = Fonts.Bold, TextSize = 14, Position = UDim2.new(0, 22, 0, 9), Size = UDim2.new(1, -34, 0, 18), Parent = card })
	newLabel({ Text = opts.Content or "", TextSize = 12, TextColor3 = Theme.SubText, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.new(0, 22, 0, 29), Size = UDim2.new(1, -34, 0, 34), Parent = card })
	local timer = create("Frame", { BackgroundColor3 = color, Position = UDim2.new(0, 0, 1, -2), Size = UDim2.new(1, 0, 0, 2), Parent = card })

	task.spawn(function()
		tween(mover, { Position = UDim2.new(0, 0, 0, 0) }, 0.55, Enum.EasingStyle.Back)
		tween(timer, { Size = UDim2.new(0, 0, 0, 2) }, duration, Enum.EasingStyle.Linear)
		task.wait(duration)
		tween(mover, { Position = UDim2.new(1, 330, 0, 0) }, 0.4, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		task.wait(0.4)
		tween(wrapper, { Size = UDim2.new(1, 0, 0, 0) }, 0.2)
		task.wait(0.2)
		wrapper:Destroy()
	end)
end

--==================================================================--
--  INTRO: BACKDROP  ->  KEY SYSTEM  ->  LOADING SCREEN
--==================================================================--
local function createBackdrop()
	local inset = GuiService:GetGuiInset()
	local frame = create("Frame", {
		Name = "Backdrop",
		BackgroundColor3 = Color3.fromRGB(8, 8, 12),
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, -inset.Y),
		Size = UDim2.new(1, 0, 1, inset.Y),
		Active = true,
		ZIndex = 10,
		Parent = ScreenGui,
	})
	tween(frame, { BackgroundTransparency = 0.3 }, 0.6)

	local blur
	pcall(function()
		blur = create("BlurEffect", { Name = "VelocityBlur", Size = 0, Parent = Lighting })
		tween(blur, { Size = 18 }, 0.7)
	end)

	local function close()
		tween(frame, { BackgroundTransparency = 1 }, 0.6)
		if blur then
			local t = tween(blur, { Size = 0 }, 0.6)
			t.Completed:Connect(function() blur:Destroy() end)
		end
		task.delay(0.65, function() frame:Destroy() end)
	end
	return frame, close
end

local function runKeySystem(backdrop)
	local result = Instance.new("BindableEvent")
	local verified = false

	local holder = create("Frame", {
		Name = "KeySystem", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(420, 384), Parent = backdrop,
	})
	local scale = create("UIScale", { Scale = 0.85, Parent = holder })
	local shadow = createShadow(holder, 44, 1, 384)
	local card = create("CanvasGroup", { BackgroundColor3 = Theme.Background, GroupTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = holder })
	corner(card, 16)
	stroke(card, Theme.Stroke, 1, 0.3)

	tween(scale, { Scale = 1 }, 0.6, Enum.EasingStyle.Back)
	tween(card, { GroupTransparency = 0 }, 0.5)
	tweenShadow(shadow, 0.15, 0.6)

	-- accent strip
	local strip = create("Frame", { Size = UDim2.new(1, 0, 0, 3), Parent = card })
	bindAccent(strip, "BackgroundColor3")
	create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 0.9) }), Parent = strip })

	-- logo (floating)
	local logo = create("ImageLabel", {
		Image = Config.LogoId, BackgroundColor3 = Theme.Card, BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 24), Size = UDim2.fromOffset(84, 84),
		ScaleType = Enum.ScaleType.Fit, Parent = card,
	})
	corner(logo, 20)
	bindAccent(stroke(logo, Theme.Accent, 2, 0.15), "Color")
	TweenService:Create(logo, TweenInfo.new(2.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Position = UDim2.new(0.5, 0, 0, 31) }):Play()

	newLabel({ Text = Config.Name, Font = Fonts.Bold, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 0, 122), Size = UDim2.new(1, 0, 0, 30), Parent = card })
	newLabel({ Text = "Enter your key to continue", TextSize = 13, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 0, 0, 152), Size = UDim2.new(1, 0, 0, 18), Parent = card })

	-- input
	local inputFrame = create("Frame", { BackgroundColor3 = Theme.Input, Position = UDim2.new(0, 24, 0, 184), Size = UDim2.new(1, -48, 0, 44), Parent = card })
	corner(inputFrame, 10)
	local inputStroke = stroke(inputFrame, Theme.Stroke, 1.5, 0)
	local box = create("TextBox", {
		PlaceholderText = "Enter your key here...", PlaceholderColor3 = Theme.SubText, ClearTextOnFocus = false,
		Font = Fonts.Medium, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -24, 1, 0), Parent = inputFrame,
	})
	local status = newLabel({ Text = "", TextSize = 12, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.new(0, 24, 0, 234), Size = UDim2.new(1, -48, 0, 16), Parent = card })

	box.Focused:Connect(function() if not verified then tween(inputStroke, { Color = Theme.Accent }, 0.2) end end)
	box.FocusLost:Connect(function() if not verified then tween(inputStroke, { Color = Theme.Stroke }, 0.25) end end)

	-- buttons
	local verifyBtn = create("TextButton", {
		Text = "Verify Key", Font = Fonts.Bold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundTransparency = 0, Position = UDim2.new(0, 24, 0, 258), Size = UDim2.new(0.58, -29, 0, 40), Parent = card,
	})
	corner(verifyBtn, 10)
	bindAccent(verifyBtn, "BackgroundColor3")
	addHover(verifyBtn, verifyBtn, function() return Theme.Accent end, function() return lighten(Theme.Accent, 0.18) end)
	addPress(verifyBtn, verifyBtn, 0.96)

	local getBtn = create("TextButton", {
		Text = "Get Key", Font = Fonts.Bold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = Theme.Card, BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 258), Size = UDim2.new(0.42, -29, 0, 40), Parent = card,
	})
	corner(getBtn, 10)
	stroke(getBtn, Theme.Stroke, 1, 0.2)
	addHover(getBtn, getBtn, function() return Theme.Card end, function() return Theme.CardHover end)
	addPress(getBtn, getBtn, 0.96)

	-- hint block
	local hint = create("Frame", { BackgroundColor3 = Theme.Card, Position = UDim2.new(0, 24, 0, 312), Size = UDim2.new(1, -48, 0, 56), Parent = card })
	corner(hint, 10)
	local hintBar = create("Frame", { Position = UDim2.new(0, 10, 0, 10), Size = UDim2.new(0, 3, 1, -20), Parent = hint })
	corner(hintBar, 2)
	bindAccent(hintBar, "BackgroundColor3")
	local hintText = newLabel({ RichText = true, TextSize = 12, TextWrapped = true, TextColor3 = Theme.SubText, TextYAlignment = Enum.TextYAlignment.Center, Position = UDim2.new(0, 24, 0, 0), Size = UDim2.new(1, -34, 1, 0), Parent = hint })
	onAccent(function(c)
		hintText.Text = string.format('<font color="#%s"><b>HINT</b></font>  %s', c:ToHex(), Config.KeyHint)
	end)

	local closeBtn = create("TextButton", {
		Text = "x", Font = Fonts.Bold, TextSize = 16, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.new(1, -38, 0, 10), Size = UDim2.fromOffset(28, 28), Parent = card,
	})
	closeBtn.MouseEnter:Connect(function() tween(closeBtn, { TextColor3 = Theme.Danger }, 0.2) end)
	closeBtn.MouseLeave:Connect(function() tween(closeBtn, { TextColor3 = Theme.SubText }, 0.2) end)

	local function setStatus(msg, color)
		status.Text = msg
		status.TextColor3 = color
	end

	local function shake()
		task.spawn(function()
			local base = holder.Position
			for _, off in ipairs({ -10, 10, -7, 7, -4, 4, 0 }) do
				tween(holder, { Position = UDim2.new(base.X.Scale, base.X.Offset + off, base.Y.Scale, base.Y.Offset) }, 0.05, Enum.EasingStyle.Sine)
				task.wait(0.05)
			end
		end)
	end

	local function fadeOut(callback)
		tween(card, { GroupTransparency = 1 }, 0.4)
		tween(scale, { Scale = 0.92 }, 0.4)
		tweenShadow(shadow, 1, 0.4)
		task.wait(0.45)
		holder:Destroy()
		result:Fire(callback)
	end

	local function verify()
		if verified then return end
		local input = string.match(box.Text, "^%s*(.-)%s*$")
		if input == "" then
			setStatus("Please enter your key.", Theme.Danger)
			shake()
		elseif input == Config.Key then
			verified = true
			setStatus("Key verified. Welcome!", Theme.Success)
			tween(inputStroke, { Color = Theme.Success }, 0.25)
			task.delay(0.7, function() fadeOut(true) end)
		else
			setStatus("Invalid key. Please try again.", Theme.Danger)
			tween(inputStroke, { Color = Theme.Danger }, 0.2)
			shake()
			task.delay(1.3, function()
				if not verified and not box:IsFocused() then tween(inputStroke, { Color = Theme.Stroke }, 0.3) end
			end)
		end
	end

	verifyBtn.MouseButton1Click:Connect(verify)
	box.FocusLost:Connect(function(enter) if enter then verify() end end)
	getBtn.MouseButton1Click:Connect(function()
		local copied = pcall(function() setclipboard(Config.KeyLink) end)
		if copied then
			setStatus("Link copied to clipboard!", Theme.Success)
		else
			setStatus(Config.KeyLink, Theme.Accent)
		end
	end)
	closeBtn.MouseButton1Click:Connect(function()
		if not verified then
			verified = true
			fadeOut(false)
		end
	end)

	return result.Event:Wait()
end

local function runLoader(backdrop)
	local group = create("CanvasGroup", { Name = "Loader", BackgroundTransparency = 1, GroupTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = backdrop })

	local ringHolder = create("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, -70), Size = UDim2.fromOffset(150, 150), Parent = group })

	local track = create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = ringHolder })
	corner(track, 46)
	stroke(track, Theme.Stroke, 3, 0.4)

	local ring = create("Frame", { BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), Parent = ringHolder })
	corner(ring, 46)
	local ringStroke = stroke(ring, Color3.new(1, 1, 1), 3, 0)
	local ringGrad = create("UIGradient", {
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.55, 1), NumberSequenceKeypoint.new(1, 0) }),
		Parent = ringStroke,
	})
	onAccent(function(c) ringGrad.Color = ColorSequence.new(c) end)
	TweenService:Create(ringGrad, TweenInfo.new(1.3, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, -1), { Rotation = 360 }):Play()

	local logo = create("ImageLabel", {
		Image = Config.LogoId, BackgroundColor3 = Theme.Card, BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(112, 112),
		ScaleType = Enum.ScaleType.Fit, Parent = ringHolder,
	})
	corner(logo, 28)
	local pulse = create("UIScale", { Parent = logo })
	TweenService:Create(pulse, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Scale = 1.06 }):Play()

	newLabel({ Text = string.upper(Config.Name), Font = Enum.Font.GothamBold, TextSize = 26, TextXAlignment = Enum.TextXAlignment.Center, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 26), Size = UDim2.fromOffset(400, 32), Parent = group })

	local status = newLabel({ Text = "Starting...", TextSize = 12, TextColor3 = Theme.SubText, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 68), Size = UDim2.fromOffset(300, 18), Parent = group })
	local percent = newLabel({ Text = "0%", TextSize = 12, Font = Enum.Font.GothamBold, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 68), Size = UDim2.fromOffset(300, 18), Parent = group })
	bindAccent(percent, "TextColor3")

	local bar = create("Frame", { BackgroundColor3 = Theme.Card, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 94), Size = UDim2.fromOffset(300, 6), Parent = group })
	corner(bar, 3)
	local fill = create("Frame", { Size = UDim2.new(0, 0, 1, 0), Parent = bar })
	corner(fill, 3)
	local fillGrad = create("UIGradient", { Parent = fill })
	onAccent(function(c) fillGrad.Color = ColorSequence.new(c, lighten(c, 0.45)) end)
	fill:GetPropertyChangedSignal("Size"):Connect(function()
		percent.Text = math.floor(fill.Size.X.Scale * 100 + 0.5) .. "%"
	end)

	-- real asset preloading
	local preloaded = false
	task.spawn(function()
		local bannerProbe = create("ImageLabel", { Image = Config.BannerId, Visible = false, Parent = group })
		pcall(function() ContentProvider:PreloadAsync({ logo, bannerProbe }) end)
		preloaded = true
	end)

	tween(group, { GroupTransparency = 0 }, 0.5)
	task.wait(0.5)

	local function goTo(alpha, duration, text)
		status.Text = text
		tween(fill, { Size = UDim2.new(alpha, 0, 1, 0) }, duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut).Completed:Wait()
	end

	goTo(0.25, 0.6, "Initializing core modules...")
	status.Text = "Preloading assets..."
	tween(fill, { Size = UDim2.new(0.6, 0, 1, 0) }, 0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut).Completed:Wait()
	local t0 = os.clock()
	while not preloaded and os.clock() - t0 < 3 do task.wait() end
	goTo(0.88, 0.7, "Building interface...")
	goTo(1, 0.5, "Ready!")
	task.wait(0.3)

	tween(group, { GroupTransparency = 1 }, 0.5)
	task.wait(0.5)
	group:Destroy()
end

--==================================================================--
--  WINDOW
--==================================================================--
function VelocityHUB:CreateWindow(settings)
	settings = settings or {}
	local Window = { Flags = VelocityHUB.Flags }
	local useKey = settings.UseKeySystem
	if useKey == nil then useKey = Config.UseKeySystem end
	local windowName = settings.Name or Config.Name
	Window.ToggleKey = settings.ToggleKey or Config.ToggleKey

	----------------------------------------------------------------
	-- Intro sequence (yields until finished)
	----------------------------------------------------------------
	local backdrop, closeBackdrop = createBackdrop()
	if useKey then
		local ok = runKeySystem(backdrop)
		if not ok then
			closeBackdrop()
			task.wait(0.7)
			VelocityHUB:Destroy()
			Instance.new("BindableEvent").Event:Wait() -- halt the calling script for good
		end
	end
	runLoader(backdrop)
	closeBackdrop()

	----------------------------------------------------------------
	-- Frame layout
	----------------------------------------------------------------
	local WIN_W, WIN_H, SIDEBAR_W = 680, 460, 184
	local TABS_TOP = 72
	local TABS_BOTTOM = 12

	local camera = workspace.CurrentCamera
	local baseScale = 1
	if camera then
		local vp = camera.ViewportSize
		baseScale = math.clamp(math.min(vp.X / (WIN_W + 60), vp.Y / (WIN_H + 60)), 0.5, 1)
	end

	local Holder = create("Frame", {
		Name = "Window", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(WIN_W, WIN_H), Parent = ScreenGui,
	})
	local Body = create("Frame", {
		Name = "Body", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromScale(1, 1), Parent = Holder,
	})
	local uiScale = create("UIScale", { Scale = baseScale * 0.85, Parent = Body })

	local shadow = createShadow(Body, 46, 0, WIN_H)
	bindBGFn(function() setShadowFade(shadow, bgTransparency) end)

	local Main = create("Frame", { Name = "Main", BackgroundColor3 = Theme.Background, Size = UDim2.fromScale(1, 1), Parent = Body })
	corner(Main, 14)
	stroke(Main, Color3.new(1, 1, 1), 1, 0.86)
	bindBG(Main, "BackgroundTransparency", 0)

	-- Banner as the window background ------------------------------
	-- A CanvasGroup lets the rounded corners clip the image and every shade layer cleanly.
	local Backdrop = create("CanvasGroup", { Name = "BannerBackdrop", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 0, Parent = Main })
	corner(Backdrop, 14)
	local BgImage = create("ImageLabel", { Name = "Banner", Image = Config.BannerId, ScaleType = Enum.ScaleType.Crop, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = Backdrop })

	local function shade(rotation, points)
		local keys = {}
		for _, p in ipairs(points) do table.insert(keys, NumberSequenceKeypoint.new(p[1], p[2])) end
		local f = create("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, 1), Parent = Backdrop })
		create("UIGradient", { Rotation = rotation, Transparency = NumberSequence.new(keys), Parent = f })
		return f
	end
	-- Dark overlays keep every label readable (lower number = darker). Tweak here to taste.
	local ShadeH = shade(0,  { { 0, 0.25 }, { 0.27, 0.35 }, { 1, 0.48 } }) -- darker on the sidebar side
	local ShadeV = shade(90, { { 0, 0.65 }, { 1, 0.30 } })                 -- vignette toward the bottom

	local Tint = create("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), Parent = Backdrop })
	local tintGrad = create("UIGradient", {
		Rotation = -35,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.6, 0.94), NumberSequenceKeypoint.new(1, 0.80) }),
		Parent = Tint,
	})
	onAccent(function(c) tintGrad.Color = ColorSequence.new(c) end) -- soft accent glow that follows the theme color

	local SidebarShade = create("Frame", { BackgroundColor3 = Theme.Sidebar, Size = UDim2.new(0, SIDEBAR_W, 1, 0), Parent = Backdrop })
	bindBG(SidebarShade, "BackgroundTransparency", 0.42) -- frosted-glass sidebar
	ShadeH.ZIndex, ShadeV.ZIndex, Tint.ZIndex, SidebarShade.ZIndex = 2, 3, 4, 5 -- explicit layer order

	local bgLayers = { ShadeH, ShadeV, Tint }
	local bannerShown = Config.ShowBanner
	local function applyBackground(animate)
		local t = bannerShown and bgTransparency or 1
		if animate then
			tween(BgImage, { ImageTransparency = t }, 0.5)
			for _, f in ipairs(bgLayers) do tween(f, { BackgroundTransparency = t }, 0.5) end
		else
			BgImage.ImageTransparency = t
			for _, f in ipairs(bgLayers) do f.BackgroundTransparency = t end
		end
	end
	bindBGFn(function() applyBackground(false) end)
	-- start hidden; the open animation fades the banner in
	BgImage.ImageTransparency = 1
	for _, f in ipairs(bgLayers) do f.BackgroundTransparency = 1 end

	-- Sidebar ------------------------------------------------------
	local Sidebar = create("Frame", { Name = "Sidebar", BackgroundTransparency = 1, Size = UDim2.new(0, SIDEBAR_W, 1, 0), Parent = Main })
	create("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.88, Position = UDim2.new(0, SIDEBAR_W, 0, 0), Size = UDim2.new(0, 1, 1, 0), Parent = Main })

	local Header = create("Frame", { Name = "Header", BackgroundTransparency = 1, Size = UDim2.new(0, SIDEBAR_W, 0, 68), Parent = Main })
	local headerLogo = create("ImageLabel", {
		Image = Config.LogoId, BackgroundColor3 = Theme.Card, BackgroundTransparency = 0, ScaleType = Enum.ScaleType.Fit,
		Position = UDim2.new(0, 16, 0, 15), Size = UDim2.fromOffset(38, 38), Parent = Header,
	})
	corner(headerLogo, 10)
	bindAccent(stroke(headerLogo, Theme.Accent, 1.5, 0.2), "Color")
	newLabel({ Text = windowName, Font = Fonts.Bold, TextSize = 15, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.new(0, 64, 0, 16), Size = UDim2.new(1, -72, 0, 18), Parent = Header })
	newLabel({ Text = "Please Like...", TextSize = 11, TextColor3 = Theme.SubText, Position = UDim2.new(0, 64, 0, 34), Size = UDim2.new(1, -72, 0, 14), Parent = Header })

	local TabList = create("ScrollingFrame", {
		Name = "Tabs", BackgroundTransparency = 1, ScrollBarThickness = 0, CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
		Position = UDim2.new(0, 8, 0, TABS_TOP), Size = UDim2.new(1, 0, 1, 0), Parent = Sidebar,
	})
	TabList.Size = UDim2.new(0, SIDEBAR_W - 16, 1, -(TABS_TOP + TABS_BOTTOM))
	create("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder, Parent = TabList })

	-- Content area -------------------------------------------------
	local Content = create("Frame", { Name = "Content", BackgroundTransparency = 1, Position = UDim2.new(0, SIDEBAR_W + 1, 0, 0), Size = UDim2.new(1, -(SIDEBAR_W + 1), 1, 0), Parent = Main })

	local glow = create("Frame", { Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -28, 0, 2), Parent = Content })
	bindAccent(glow, "BackgroundColor3")
	create("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }), Parent = glow })

	local Topbar = create("Frame", { Name = "Topbar", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 56), Parent = Content })
	local pageTitle = newLabel({ Text = "", Font = Fonts.Bold, TextSize = 18, Position = UDim2.new(0, 20, 0, 0), Size = UDim2.new(1, -80, 1, 0), Parent = Topbar })

	local closeBtn = create("TextButton", {
		Text = "x", Font = Fonts.Bold, TextSize = 14, TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Center,
		BackgroundColor3 = Theme.Card, BackgroundTransparency = 0,
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(30, 30), Parent = Topbar,
	})
	corner(closeBtn, 8)
	addHover(closeBtn, closeBtn, function() return Theme.Card end, function() return Theme.Danger end)
	closeBtn.MouseEnter:Connect(function() tween(closeBtn, { TextColor3 = Color3.new(1, 1, 1) }, 0.2) end)
	closeBtn.MouseLeave:Connect(function() tween(closeBtn, { TextColor3 = Theme.SubText }, 0.2) end)
	addPress(closeBtn, closeBtn, 0.9)

	local Pages = create("Frame", { Name = "Pages", BackgroundTransparency = 1, ClipsDescendants = true, Position = UDim2.new(0, 12, 0, 56), Size = UDim2.new(1, -24, 1, -68), Parent = Content })

	----------------------------------------------------------------
	-- Dragging
	----------------------------------------------------------------
	local function makeDraggable(handle, target)
		local dragging, dragStart, startPos = false, nil, nil
		handle.InputBegan:Connect(function(input)
			if isPress(input) then
				dragging = true
				dragStart = input.Position
				startPos = target.Position
				local c
				c = input.Changed:Connect(function()
					if input.UserInputState == Enum.UserInputState.End then
						dragging = false
						c:Disconnect()
					end
				end)
			end
		end)
		connect(UserInputService.InputChanged, function(input)
			if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
				local d = input.Position - dragStart
				tween(target, { Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y) }, 0.08, Enum.EasingStyle.Quad)
			end
		end)
	end
	makeDraggable(Header, Holder)
	makeDraggable(Topbar, Holder)

	----------------------------------------------------------------
	-- Open / close
	----------------------------------------------------------------
	local visible = true
	local function setVisible(v)
		if v == visible then return end
		visible = v
		if v then
			Holder.Visible = true
			uiScale.Scale = baseScale * 0.88
			tween(uiScale, { Scale = baseScale }, 0.45, Enum.EasingStyle.Back)
		else
			local t = tween(uiScale, { Scale = baseScale * 0.88 }, 0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			t.Completed:Connect(function() if not visible then Holder.Visible = false end end)
		end
	end

	function Window:Toggle() setVisible(not visible) end
	function Window:Show() setVisible(true) end
	function Window:Hide() setVisible(false) end
	function Window:Notify(opts) VelocityHUB:Notify(opts) end
	function Window:Destroy() VelocityHUB:Destroy() end
	function Window:SetAccent(c) setAccent(c) end
	function Window:SetTransparency(t) setBGTransparency(math.clamp(t, 0, 0.8)) end
	function Window:SetToggleKey(k) Window.ToggleKey = k end

	closeBtn.MouseButton1Click:Connect(function()
		setVisible(false)
		VelocityHUB:Notify({ Title = windowName, Content = "Hidden. Press " .. Window.ToggleKey.Name .. " to open it again.", Duration = 3 })
	end)

	connect(UserInputService.InputBegan, function(input, processed)
		if processed or State.Listening then return end
		if input.KeyCode == Window.ToggleKey then setVisible(not visible) end
	end)

	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		local fab = create("ImageButton", {
			Image = Config.LogoId, BackgroundColor3 = Theme.Card, BackgroundTransparency = 0,
			Position = UDim2.new(0, 14, 0.5, -23), Size = UDim2.fromOffset(46, 46), ZIndex = 5, Parent = ScreenGui,
		})
		corner(fab, 14)
		bindAccent(stroke(fab, Theme.Accent, 1.5, 0.2), "Color")
		fab.MouseButton1Click:Connect(function() setVisible(not visible) end)
	end

	----------------------------------------------------------------
	-- Banner toggle
	----------------------------------------------------------------
	function Window:SetBannerVisible(v)
		bannerShown = v
		applyBackground(true)
	end

	----------------------------------------------------------------
	-- Tabs & elements
	----------------------------------------------------------------
	local tabCounter = 0

	local function newTab(name, icon, order)
		local Tab = { Name = name }

		local btn = create("TextButton", { Name = name, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), LayoutOrder = order, Parent = TabList })
		corner(btn, 9)
		bindAccent(btn, "BackgroundColor3")
		local indicator = create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(3, 0), Parent = btn })
		corner(indicator, 2)
		bindAccent(indicator, "BackgroundColor3")

		local textX = 14
		local iconImg
		if icon then
			iconImg = create("ImageLabel", { Image = icon, ImageColor3 = Theme.SubText, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(18, 18), Parent = btn })
			textX = 40
		end
		local title = newLabel({ Text = name, TextColor3 = Theme.SubText, Position = UDim2.new(0, textX, 0, 0), Size = UDim2.new(1, -(textX + 8), 1, 0), Parent = btn })

		local page = create("ScrollingFrame", {
			Name = name, BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 3, ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false, Parent = Pages,
		})
		bindAccent(page, "ScrollBarImageColor3")
		create("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder, Parent = page })
		create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 12), PaddingRight = UDim.new(0, 8), Parent = page })

		local function setActive(active)
			tween(btn, { BackgroundTransparency = active and 0.85 or 1 }, 0.25)
			tween(indicator, { Size = UDim2.fromOffset(3, active and 18 or 0) }, 0.35, Enum.EasingStyle.Back)
			tween(title, { TextColor3 = active and Theme.Text or Theme.SubText }, 0.25)
			if iconImg then tween(iconImg, { ImageColor3 = active and Theme.Accent or Theme.SubText }, 0.25) end
		end

		function Tab:Select()
			if Window.CurrentTab == Tab then return end
			local prev = Window.CurrentTab
			if prev then
				prev._setActive(false)
				prev._page.Visible = false
			end
			Window.CurrentTab = Tab
			setActive(true)
			pageTitle.Text = name
			page.Position = UDim2.fromOffset(0, 18)
			page.Visible = true
			tween(page, { Position = UDim2.fromOffset(0, 0) }, 0.4)
		end
		Tab._setActive = setActive
		Tab._page = page

		btn.MouseEnter:Connect(function() if Window.CurrentTab ~= Tab then tween(btn, { BackgroundTransparency = 0.93 }, 0.2) end end)
		btn.MouseLeave:Connect(function() if Window.CurrentTab ~= Tab then tween(btn, { BackgroundTransparency = 1 }, 0.25) end end)
		btn.MouseButton1Click:Connect(function() Tab:Select() end)

		local order = 0
		local function nextOrder() order = order + 1 return order end

		local function createCard(height)
			local card = create("Frame", { BackgroundColor3 = Theme.Card, Size = UDim2.new(1, 0, 0, height), ClipsDescendants = true, LayoutOrder = nextOrder(), Parent = page })
			corner(card, 10)
			stroke(card, Color3.new(1, 1, 1), 1, 0.9)
			bindBG(card, "BackgroundTransparency", 0.22)
			return card
		end
		local function cardHover(hit, card)
			addHover(hit, card, function() return Theme.Card end, function() return Theme.CardHover end)
		end
		local function register(opts, element)
			if opts.Flag then VelocityHUB.Flags[opts.Flag] = element end
			return element
		end

		-- SECTION -----------------------------------------------------
		function Tab:CreateSection(text)
			local holder = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 24), LayoutOrder = nextOrder(), Parent = page })
			local bar = create("Frame", { Position = UDim2.new(0, 2, 0.5, -6), Size = UDim2.fromOffset(3, 12), Parent = holder })
			corner(bar, 2)
			bindAccent(bar, "BackgroundColor3")
			local lbl = newLabel({ Text = string.upper(text or "Section"), Font = Fonts.Bold, TextSize = 11, TextColor3 = Theme.SubText, Position = UDim2.new(0, 12, 0, 0), Size = UDim2.new(1, -12, 1, 0), Parent = holder })
			return { Set = function(_, t) lbl.Text = string.upper(t) end }
		end

		-- LABEL -------------------------------------------------------
		function Tab:CreateLabel(text)
			local lbl = newLabel({
				Text = text or "", TextSize = 12, TextColor3 = Theme.SubText, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top,
				AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(1, -8, 0, 0), LayoutOrder = nextOrder(), Parent = page,
			})
			create("UIPadding", { PaddingLeft = UDim.new(0, 4), Parent = lbl })
			return { Set = function(_, t) lbl.Text = t end }
		end

		-- BUTTON ------------------------------------------------------
		function Tab:CreateButton(opts)
			opts = opts or {}
			local card = createCard(40)
			local lbl = newLabel({ Text = opts.Name or "Button", Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -60, 1, 0), Parent = card })
			local diamond = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -24, 0.5, 0), Size = UDim2.fromOffset(8, 8), Rotation = 45, Parent = card })
			corner(diamond, 2)
			bindAccent(diamond, "BackgroundColor3")

			local hit = create("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = card })
			cardHover(hit, card)
			addPress(hit, card, 0.985)
			hit.InputBegan:Connect(function(input)
				if isPress(input) then ripple(card, input.Position.X, input.Position.Y) end
			end)
			hit.MouseButton1Click:Connect(function()
				diamond.Rotation = 45
				tween(diamond, { Rotation = 225 }, 0.45)
				safeCall(opts.Callback)
			end)
			return register(opts, { SetText = function(_, t) lbl.Text = t end })
		end

		-- TOGGLE ------------------------------------------------------
		function Tab:CreateToggle(opts)
			opts = opts or {}
			local state = opts.CurrentValue == true
			local card = createCard(40)
			newLabel({ Text = opts.Name or "Toggle", Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -80, 1, 0), Parent = card })

			local trackBg = create("Frame", { BackgroundColor3 = Theme.Off, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(42, 22), Parent = card })
			corner(trackBg, 11)
			local knob = create("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(16, 16), Parent = trackBg })
			corner(knob, 8)

			local Toggle = { CurrentValue = state }
			local function render()
				tween(trackBg, { BackgroundColor3 = state and Theme.Accent or Theme.Off }, 0.25)
				tween(knob, { Position = state and UDim2.new(1, -19, 0.5, 0) or UDim2.new(0, 3, 0.5, 0) }, 0.35, Enum.EasingStyle.Back)
			end
			onAccent(function(c) if state then trackBg.BackgroundColor3 = c end end)
			if state then
				trackBg.BackgroundColor3 = Theme.Accent
				knob.Position = UDim2.new(1, -19, 0.5, 0)
			end

			function Toggle:Set(v, silent)
				state = v == true
				Toggle.CurrentValue = state
				render()
				if not silent then safeCall(opts.Callback, state) end
			end

			local hit = create("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = card })
			cardHover(hit, card)
			hit.MouseButton1Down:Connect(function() tween(knob, { Size = UDim2.fromOffset(20, 16) }, 0.12) end)
			hit.MouseButton1Up:Connect(function() tween(knob, { Size = UDim2.fromOffset(16, 16) }, 0.2) end)
			hit.MouseLeave:Connect(function() tween(knob, { Size = UDim2.fromOffset(16, 16) }, 0.2) end)
			hit.MouseButton1Click:Connect(function() Toggle:Set(not state) end)
			return register(opts, Toggle)
		end

		-- SLIDER ------------------------------------------------------
		function Tab:CreateSlider(opts)
			opts = opts or {}
			local range = opts.Range or { 0, 100 }
			local min, max = range[1], range[2]
			local inc = opts.Increment or 1
			local suffix = opts.Suffix or ""
			local dec = decimalsOf(inc)
			local value = math.clamp(opts.CurrentValue or min, min, max)

			local card = createCard(56)
			newLabel({ Text = opts.Name or "Slider", Position = UDim2.new(0, 14, 0, 8), Size = UDim2.new(1, -120, 0, 18), Parent = card })
			local valueLbl = newLabel({ Text = "", TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 8), Size = UDim2.fromOffset(100, 18), Parent = card })

			local track = create("Frame", { BackgroundColor3 = Theme.Off, Position = UDim2.new(0, 14, 0, 37), Size = UDim2.new(1, -28, 0, 6), Parent = card })
			corner(track, 3)
			local fill = create("Frame", { Size = UDim2.new(0, 0, 1, 0), Parent = track })
			corner(fill, 3)
			bindAccent(fill, "BackgroundColor3")
			local knob = create("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(14, 14), ZIndex = 2, Parent = track })
			corner(knob, 7)
			bindAccent(stroke(knob, Theme.Accent, 2, 0), "Color")

			local Slider = { CurrentValue = value }
			local function fmt(v) return string.format("%." .. dec .. "f", v) end

			local function render(fast)
				local alpha = (max == min) and 0 or (value - min) / (max - min)
				local d = fast and 0.08 or 0.3
				tween(fill, { Size = UDim2.new(alpha, 0, 1, 0) }, d, Enum.EasingStyle.Quad)
				tween(knob, { Position = UDim2.new(alpha, 0, 0.5, 0) }, d, Enum.EasingStyle.Quad)
				valueLbl.Text = fmt(value) .. suffix
			end

			function Slider:Set(v, silent, fast)
				v = math.clamp(v, min, max)
				v = min + math.floor((v - min) / inc + 0.5) * inc
				v = math.clamp(tonumber(fmt(v)), min, max)
				local changed = v ~= value
				value = v
				Slider.CurrentValue = v
				render(fast)
				if changed and not silent then safeCall(opts.Callback, v) end
			end

			render(false)

			local hit = create("TextButton", { Position = UDim2.new(0, 14, 0, 26), Size = UDim2.new(1, -28, 0, 28), ZIndex = 3, Parent = card })
			trackDrag(hit,
				function(x) Slider:Set(min + (max - min) * x, false, true) end,
				function() tween(knob, { Size = UDim2.fromOffset(19, 19) }, 0.15, Enum.EasingStyle.Back) end,
				function() tween(knob, { Size = UDim2.fromOffset(14, 14) }, 0.2) end
			)
			card.MouseEnter:Connect(function() tween(card, { BackgroundColor3 = Theme.CardHover }, 0.2) end)
			card.MouseLeave:Connect(function() tween(card, { BackgroundColor3 = Theme.Card }, 0.25) end)
			return register(opts, Slider)
		end

		-- COLOR PICKER ------------------------------------------------
		function Tab:CreateColorPicker(opts)
			opts = opts or {}
			local color = opts.Color or Color3.fromRGB(255, 255, 255)
			local h, s, v = color:ToHSV()
			local expanded = false
			local COLLAPSED, EXPANDED = 40, 214

			local card = createCard(COLLAPSED)
			newLabel({ Text = opts.Name or "Color Picker", Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -70, 0, 40), Parent = card })
			local swatch = create("Frame", { BackgroundColor3 = color, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 10), Size = UDim2.fromOffset(34, 20), Parent = card })
			corner(swatch, 6)
			stroke(swatch, Color3.new(1, 1, 1), 1, 0.75)

			local headHit = create("TextButton", { Size = UDim2.new(1, 0, 0, 40), ZIndex = 3, Parent = card })
			cardHover(headHit, card)

			-- saturation / value square
			local svBox = create("Frame", { BackgroundColor3 = Color3.fromHSV(h, 1, 1), Position = UDim2.new(0, 14, 0, 50), Size = UDim2.new(1, -66, 0, 112), Parent = card })
			corner(svBox, 8)
			local whiteLayer = create("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.fromScale(1, 1), Parent = svBox })
			corner(whiteLayer, 8)
			create("UIGradient", { Transparency = NumberSequence.new(0, 1), Parent = whiteLayer })
			local blackLayer = create("Frame", { BackgroundColor3 = Color3.new(0, 0, 0), Size = UDim2.fromScale(1, 1), Parent = svBox })
			corner(blackLayer, 8)
			create("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(1, 0), Parent = blackLayer })
			local svCursor = create("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12), ZIndex = 3, Parent = svBox })
			corner(svCursor, 6)
			stroke(svCursor, Color3.new(0, 0, 0), 1.5, 0.2)

			-- hue bar
			local hueBar = create("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Position = UDim2.new(1, -40, 0, 50), Size = UDim2.fromOffset(26, 112), Parent = card })
			corner(hueBar, 8)
			create("UIGradient", {
				Rotation = 90,
				Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
					ColorSequenceKeypoint.new(1 / 6, Color3.fromRGB(255, 255, 0)),
					ColorSequenceKeypoint.new(2 / 6, Color3.fromRGB(0, 255, 0)),
					ColorSequenceKeypoint.new(3 / 6, Color3.fromRGB(0, 255, 255)),
					ColorSequenceKeypoint.new(4 / 6, Color3.fromRGB(0, 0, 255)),
					ColorSequenceKeypoint.new(5 / 6, Color3.fromRGB(255, 0, 255)),
					ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
				}),
				Parent = hueBar,
			})
			local hueCursor = create("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, h, 0), Size = UDim2.new(1, 6, 0, 6), ZIndex = 3, Parent = hueBar })
			corner(hueCursor, 3)
			stroke(hueCursor, Color3.new(0, 0, 0), 1.5, 0.2)

			-- hex + rgb readout
			local hexBox = create("TextBox", {
				Font = Fonts.Bold, TextSize = 12, PlaceholderText = "#FFFFFF", PlaceholderColor3 = Theme.SubText, ClearTextOnFocus = false,
				TextXAlignment = Enum.TextXAlignment.Center, BackgroundColor3 = Theme.Input, BackgroundTransparency = 0,
				Position = UDim2.new(0, 14, 0, 174), Size = UDim2.fromOffset(100, 28), Parent = card,
			})
			corner(hexBox, 6)
			local hexStroke = stroke(hexBox, Theme.Stroke, 1, 0)
			local rgbLbl = newLabel({ TextSize = 12, TextColor3 = Theme.SubText, Position = UDim2.new(0, 126, 0, 174), Size = UDim2.new(1, -140, 0, 28), Parent = card })

			local Picker = { CurrentValue = color }
			local function apply(fire)
				color = Color3.fromHSV(h, s, v)
				Picker.CurrentValue = color
				swatch.BackgroundColor3 = color
				svBox.BackgroundColor3 = Color3.fromHSV(h, 1, 1)
				svCursor.Position = UDim2.fromScale(s, 1 - v)
				hueCursor.Position = UDim2.new(0.5, 0, h, 0)
				hexBox.Text = "#" .. string.upper(color:ToHex())
				rgbLbl.Text = string.format("R %d   G %d   B %d", math.floor(color.R * 255 + 0.5), math.floor(color.G * 255 + 0.5), math.floor(color.B * 255 + 0.5))
				if fire then safeCall(opts.Callback, color) end
			end
			apply(false)

			function Picker:Set(c, silent)
				h, s, v = c:ToHSV()
				apply(not silent)
			end

			local svHit = create("TextButton", { Position = svBox.Position, Size = svBox.Size, ZIndex = 4, Parent = card })
			trackDrag(svHit, function(x, y)
				s = x
				v = 1 - y
				apply(true)
			end)
			local hueHit = create("TextButton", { Position = hueBar.Position, Size = hueBar.Size, ZIndex = 4, Parent = card })
			trackDrag(hueHit, function(_, y)
				h = math.clamp(y, 0, 0.999)
				apply(true)
			end)

			hexBox.Focused:Connect(function() tween(hexStroke, { Color = Theme.Accent }, 0.2) end)
			hexBox.FocusLost:Connect(function()
				tween(hexStroke, { Color = Theme.Stroke }, 0.2)
				local hex = string.gsub(hexBox.Text, "#", "")
				if #hex == 6 and string.match(hex, "^%x+$") then
					local r, g, b = tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)
					h, s, v = Color3.fromRGB(r, g, b):ToHSV()
				end
				apply(true)
			end)

			headHit.MouseButton1Click:Connect(function()
				expanded = not expanded
				tween(card, { Size = UDim2.new(1, 0, 0, expanded and EXPANDED or COLLAPSED) }, 0.45)
			end)
			return register(opts, Picker)
		end

		-- KEYBIND -----------------------------------------------------
		function Tab:CreateKeybind(opts)
			opts = opts or {}
			local key = opts.CurrentKeybind or Enum.KeyCode.E
			if type(key) == "string" then
				local ok, k = pcall(function() return Enum.KeyCode[key] end)
				key = ok and k or Enum.KeyCode.E
			end

			local card = createCard(40)
			newLabel({ Text = opts.Name or "Keybind", Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -130, 1, 0), Parent = card })
			local keyBtn = create("TextButton", {
				Text = key.Name, Font = Fonts.Bold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Center, TextTruncate = Enum.TextTruncate.AtEnd,
				BackgroundColor3 = Theme.Input, BackgroundTransparency = 0, AnchorPoint = Vector2.new(1, 0.5),
				Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(100, 26), ZIndex = 3, Parent = card,
			})
			corner(keyBtn, 6)
			local keyStroke = stroke(keyBtn, Theme.Stroke, 1, 0)
			addHover(keyBtn, keyBtn, function() return Theme.Input end, function() return Theme.CardHover end)
			addPress(keyBtn, keyBtn, 0.94)

			local Keybind = { CurrentKeybind = key }
			local listening = false

			function Keybind:Set(k, silent)
				key = k
				Keybind.CurrentKeybind = k
				keyBtn.Text = k.Name
				if not silent then safeCall(opts.OnChange, k) end
			end

			keyBtn.MouseButton1Click:Connect(function()
				listening = true
				State.Listening = true
				keyBtn.Text = "..."
				tween(keyStroke, { Color = Theme.Accent }, 0.2)
			end)

			connect(UserInputService.InputBegan, function(input, processed)
				if listening then
					if input.UserInputType == Enum.UserInputType.Keyboard then
						listening = false
						tween(keyStroke, { Color = Theme.Stroke }, 0.2)
						if input.KeyCode == Enum.KeyCode.Escape then
							keyBtn.Text = key.Name
						else
							Keybind:Set(input.KeyCode)
						end
						task.delay(0.15, function() State.Listening = false end)
					end
					return
				end
				if not processed and not State.Listening and input.KeyCode == key then
					safeCall(opts.Callback, key)
				end
			end)
			return register(opts, Keybind)
		end

		-- DIVIDER -----------------------------------------------------
		function Tab:CreateDivider()
			local holder = create("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = nextOrder(), Parent = page })
			local line = create("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, -8, 0, 1), Parent = holder })
			create("UIGradient", {
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.8), NumberSequenceKeypoint.new(1, 1) }),
				Parent = line,
			})
			local glint = create("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(46, 2), Parent = holder })
			corner(glint, 1)
			bindAccent(glint, "BackgroundColor3")
			create("UIGradient", {
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.15), NumberSequenceKeypoint.new(1, 1) }),
				Parent = glint,
			})
			return { Destroy = function() holder:Destroy() end }
		end

		-- TEXTBOX -----------------------------------------------------
		function Tab:CreateTextBox(opts)
			opts = opts or {}
			local numbersOnly = opts.NumbersOnly == true
			local card = createCard(46)
			newLabel({ Text = opts.Name or "TextBox", Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -200, 1, 0), Parent = card })

			-- accent glow that fades in while focused
			local glow = create("ImageLabel", {
				Image = SHADOW_IMAGE, ScaleType = Enum.ScaleType.Slice, SliceCenter = Rect.new(49, 49, 450, 450), SliceScale = 0.4,
				ImageTransparency = 1, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -4, 0.5, 0), Size = UDim2.fromOffset(186, 46), ZIndex = 1, Parent = card,
			})
			bindAccent(glow, "ImageColor3")

			local field = create("Frame", { BackgroundColor3 = Theme.Input, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.5, 0), Size = UDim2.fromOffset(170, 30), ZIndex = 2, Parent = card })
			corner(field, 8)
			local fieldStroke = stroke(field, Theme.Stroke, 1, 0)
			local box = create("TextBox", {
				Text = opts.CurrentValue ~= nil and tostring(opts.CurrentValue) or "",
				PlaceholderText = opts.PlaceholderText or (numbersOnly and "0" or "Type here..."), PlaceholderColor3 = Theme.SubText,
				ClearTextOnFocus = false, TextSize = 12, TextTruncate = Enum.TextTruncate.AtEnd,
				Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(1, -20, 1, 0), ZIndex = 3, Parent = field,
			})

			local Textbox = { CurrentValue = numbersOnly and tonumber(box.Text) or box.Text }
			local lastValid = box.Text
			local filtering = false

			if numbersOnly then
				box:GetPropertyChangedSignal("Text"):Connect(function()
					if filtering then return end
					local filtered = string.gsub(box.Text, "[^%d%.%-]", "")
					if filtered ~= box.Text then
						filtering = true
						box.Text = filtered
						filtering = false
					end
				end)
			end

			box.Focused:Connect(function()
				tween(fieldStroke, { Color = Theme.Accent, Thickness = 1.6 }, 0.25)
				tween(glow, { ImageTransparency = 0.5 }, 0.3)
			end)
			box.FocusLost:Connect(function(enterPressed)
				tween(fieldStroke, { Color = Theme.Stroke, Thickness = 1 }, 0.3)
				tween(glow, { ImageTransparency = 1 }, 0.35)
				local value = box.Text
				if numbersOnly then
					value = tonumber(box.Text)
					if value == nil then
						box.Text = lastValid -- reject junk such as "-" or "1.2.3"
						return
					end
					if opts.Min then value = math.max(value, opts.Min) end
					if opts.Max then value = math.min(value, opts.Max) end
					box.Text = tostring(value)
				end
				lastValid = box.Text
				Textbox.CurrentValue = value
				safeCall(opts.Callback, value, enterPressed)
				if opts.RemoveTextAfterFocusLost then box.Text = "" end
			end)

			function Textbox:Set(v, silent)
				box.Text = tostring(v)
				lastValid = box.Text
				Textbox.CurrentValue = numbersOnly and tonumber(v) or box.Text
				if not silent then safeCall(opts.Callback, Textbox.CurrentValue, false) end
			end

			local hit = create("TextButton", { Size = UDim2.new(1, -190, 1, 0), ZIndex = 3, Parent = card })
			cardHover(hit, card)
			hit.MouseButton1Click:Connect(function() box:CaptureFocus() end)
			return register(opts, Textbox)
		end

		-- DROPDOWN ----------------------------------------------------
		function Tab:CreateDropdown(opts)
			opts = opts or {}
			local options = opts.Options or {}
			local HEADER, ITEM_H, ITEM_GAP, MAX_LIST = 42, 30, 3, 160
			local expanded = false
			local items = {}

			local card = createCard(HEADER)
			newLabel({ Text = opts.Name or "Dropdown", Position = UDim2.new(0, 14, 0, 0), Size = UDim2.new(1, -200, 0, HEADER), Parent = card })
			local valueLbl = newLabel({
				Text = "Select...", TextColor3 = Theme.SubText, TextXAlignment = Enum.TextXAlignment.Right, TextTruncate = Enum.TextTruncate.AtEnd,
				AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -40, 0, 0), Size = UDim2.fromOffset(160, HEADER), Parent = card,
			})

			-- chevron drawn from two rotated bars (no external assets)
			local chevron = create("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -22, 0, HEADER / 2), Size = UDim2.fromOffset(16, 16), Parent = card })
			local arms = {}
			for _, def in ipairs({ { 5, 45 }, { 11, -45 } }) do
				local arm = create("Frame", { BackgroundColor3 = Theme.SubText, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(def[1], 8), Size = UDim2.fromOffset(9, 2), Rotation = def[2], Parent = chevron })
				corner(arm, 1)
				table.insert(arms, arm)
			end

			local headHit = create("TextButton", { Size = UDim2.new(1, 0, 0, HEADER), ZIndex = 3, Parent = card })
			cardHover(headHit, card)

			local list = create("ScrollingFrame", {
				BackgroundColor3 = Theme.Input, BackgroundTransparency = 0.15, Position = UDim2.new(0, 8, 0, HEADER + 2), Size = UDim2.new(1, -16, 0, 0),
				CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 2, ScrollingDirection = Enum.ScrollingDirection.Y, Parent = card,
			})
			corner(list, 8)
			bindAccent(list, "ScrollBarImageColor3")
			create("UIListLayout", { Padding = UDim.new(0, ITEM_GAP), SortOrder = Enum.SortOrder.LayoutOrder, Parent = list })
			create("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 6), Parent = list })

			local Dropdown = { Options = options }
			Dropdown.CurrentOption = type(opts.CurrentOption) == "table" and opts.CurrentOption[1] or opts.CurrentOption

			local function listHeight()
				return math.min(#options * (ITEM_H + ITEM_GAP) - ITEM_GAP + 8, MAX_LIST)
			end

			local function refreshVisuals()
				valueLbl.Text = Dropdown.CurrentOption ~= nil and tostring(Dropdown.CurrentOption) or "Select..."
				for _, it in ipairs(items) do
					local selected = it.opt == Dropdown.CurrentOption
					tween(it.btn, { BackgroundTransparency = selected and 0.8 or 1 }, 0.2)
					tween(it.lbl, { TextColor3 = selected and Theme.Text or Theme.SubText }, 0.2)
					tween(it.mark, { Size = UDim2.fromOffset(3, selected and 14 or 0) }, 0.3, Enum.EasingStyle.Back)
				end
			end

			local function setExpanded(v)
				expanded = v
				local open = v and (HEADER + 2 + listHeight() + 8) or HEADER
				tween(card, { Size = UDim2.new(1, 0, 0, open) }, 0.45)
				tween(list, { Size = UDim2.new(1, -16, 0, v and listHeight() or 0) }, 0.45)
				tween(chevron, { Rotation = v and 180 or 0 }, 0.4)
				for _, arm in ipairs(arms) do tween(arm, { BackgroundColor3 = v and Theme.Accent or Theme.SubText }, 0.3) end
			end

			local function build()
				for _, it in ipairs(items) do it.btn:Destroy() end
				table.clear(items)
				for i, opt in ipairs(options) do
					local btn = create("TextButton", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, ITEM_H), LayoutOrder = i, Parent = list })
					corner(btn, 7)
					bindAccent(btn, "BackgroundColor3")
					local mark = create("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(3, 0), Parent = btn })
					corner(mark, 2)
					bindAccent(mark, "BackgroundColor3")
					local lbl = newLabel({ Text = tostring(opt), TextColor3 = Theme.SubText, TextTruncate = Enum.TextTruncate.AtEnd, Position = UDim2.new(0, 16, 0, 0), Size = UDim2.new(1, -24, 1, 0), Parent = btn })
					btn.MouseEnter:Connect(function() if opt ~= Dropdown.CurrentOption then tween(btn, { BackgroundTransparency = 0.92 }, 0.15) end end)
					btn.MouseLeave:Connect(function() if opt ~= Dropdown.CurrentOption then tween(btn, { BackgroundTransparency = 1 }, 0.2) end end)
					btn.MouseButton1Click:Connect(function()
						Dropdown:Set(opt)
						setExpanded(false)
					end)
					table.insert(items, { opt = opt, btn = btn, lbl = lbl, mark = mark })
				end
				refreshVisuals()
			end

			function Dropdown:Set(opt, silent)
				Dropdown.CurrentOption = opt
				refreshVisuals()
				if not silent then safeCall(opts.Callback, opt) end
			end

			function Dropdown:Refresh(newOptions)
				options = newOptions or {}
				Dropdown.Options = options
				local stillThere = false
				for _, o in ipairs(options) do if o == Dropdown.CurrentOption then stillThere = true end end
				if not stillThere then Dropdown.CurrentOption = nil end
				build()
				if expanded then setExpanded(true) end
			end

			build()
			headHit.MouseButton1Click:Connect(function() setExpanded(not expanded) end)

			-- close when clicking anywhere outside the dropdown
			connect(UserInputService.InputBegan, function(input)
				if expanded and isPress(input) then
					local p, a, sz = input.Position, card.AbsolutePosition, card.AbsoluteSize
					if p.X < a.X or p.X > a.X + sz.X or p.Y < a.Y or p.Y > a.Y + sz.Y then setExpanded(false) end
				end
			end)
			return register(opts, Dropdown)
		end

		return Tab
	end

	-- Public tab creation --------------------------------------------
	function Window:CreateTab(name, icon)
		tabCounter = tabCounter + 1
		local Tab = newTab(name or ("Tab " .. tabCounter), icon, tabCounter)
		Window.LastTab = Tab
		if not Window.CurrentTab then Tab:Select() end
		return Tab
	end

	-- Window:CreateButton / CreateSlider / ... forward to the most recent tab
	for _, method in ipairs({ "CreateSection", "CreateLabel", "CreateButton", "CreateToggle", "CreateSlider", "CreateColorPicker", "CreateKeybind" }) do
		Window[method] = function(self, ...)
			local tab = self.LastTab or self:CreateTab("Main")
			return tab[method](tab, ...)
		end
	end

	----------------------------------------------------------------
	-- Built-in SETTINGS tab (always listed last)
	----------------------------------------------------------------
	local Settings = newTab("Settings", nil, 1000)
	Window.SettingsTab = Settings

	Settings:CreateSection("Appearance")
	Settings:CreateColorPicker({
		Name = "Theme Color",
		Color = Theme.Accent,
		Callback = function(c) setAccent(c) end,
	})
	Settings:CreateSlider({
		Name = "Background Transparency",
		Range = { 0, 80 },
		Increment = 1,
		Suffix = "%",
		CurrentValue = 0,
		Callback = function(val) setBGTransparency(val / 100) end,
	})
	Settings:CreateToggle({
		Name = "Show Banner Background",
		CurrentValue = Config.ShowBanner,
		Callback = function(val) Window:SetBannerVisible(val) end,
	})

	Settings:CreateDivider()
	Settings:CreateSection("Controls")
	Settings:CreateKeybind({
		Name = "Toggle GUI Keybind",
		CurrentKeybind = Window.ToggleKey,
		OnChange = function(k)
			Window.ToggleKey = k
			VelocityHUB:Notify({ Title = "Keybind updated", Content = "Press " .. k.Name .. " to open or close the GUI.", Type = "Success", Duration = 3 })
		end,
	})

	Settings:CreateDivider()
	Settings:CreateSection("Interface")
	Settings:CreateButton({ Name = "Unload " .. windowName, Callback = function() VelocityHUB:Destroy() end })
	Settings:CreateLabel(windowName .. " - built with VelocityHUB UI Library v1.0.0")

	----------------------------------------------------------------
	-- Open animation
	----------------------------------------------------------------
	tween(uiScale, { Scale = baseScale }, 0.65, Enum.EasingStyle.Back)
	task.delay(0.25, function() applyBackground(true) end)

	-- If the developer made no tabs, fall back to Settings
	task.defer(function()
		if not Window.CurrentTab then Settings:Select() end
	end)

	return Window
end

--==================================================================--
--  KULLANIM ALANI
--==================================================================--
local LocalPlayer = Players.LocalPlayer
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local Window = VelocityHUB:CreateWindow({
	Name = "VelocityHUB",
	ToggleKey = Enum.KeyCode.RightControl,
})

--==================================================================--
--  MAIN SEKME (FARM & CHEST SİSTEMİ)
--==================================================================--
local MainTab = Window:CreateTab("Main")

-- Farm Değişkenleri
local autoFarmEnabled = false
local npcFarmEnabled = false
local autoChestEnabled = false
local autoSealedEnabled = false

local isChestPriority = false
local isSealedPriority = false

local currentTarget = nil
local hitHeight = 5
local punchDelay = 0.6
local useSkills = false

local selectedNPCs = {} -- Çoklu NPC seçimi için tablo
local currentDropdownSelection = ""

local npcNamesList = {"NPC Bekleniyor..."}

local activeSkills = {
	F = false, Z = false, X = false, C = false, V = false,
	B = false, N = false, K = false, L = false, J = false
}
local skillOrder = {"F", "Z", "X", "C", "V", "B", "N", "K", "L", "J"}

local function refreshNpcList()
	local tempDict = {}
	npcNamesList = {}
	
	local humanoidsFolder = workspace:FindFirstChild("Humanoids")
	if humanoidsFolder then
		local regionsFolder = humanoidsFolder:FindFirstChild("Regions")
		if regionsFolder then
			for _, region in ipairs(regionsFolder:GetChildren()) do
				local activeNpcs = region:FindFirstChild("ActiveNpcs")
				if activeNpcs then
					for _, folder in ipairs(activeNpcs:GetChildren()) do
						if folder:IsA("Folder") then
							for _, npc in ipairs(folder:GetChildren()) do
								if npc:IsA("Model") and npc.Name ~= "" then
									if not tempDict[npc.Name] then
										tempDict[npc.Name] = true
										table.insert(npcNamesList, npc.Name)
									end
								end
							end
						end
					end
				end
			end
		end
	end
	
	if #npcNamesList == 0 then table.insert(npcNamesList, "Bulunamadı") end
	return npcNamesList
end
refreshNpcList()

-- Çoklu Seçilmiş NPC'leri Hedefleme
local function getSmartTarget(targetNamesTable)
	-- Eğer listede hiç NPC yoksa hedef arama
	if next(targetNamesTable) == nil then return nil end 

	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end

	local closest = nil
	local minDist = math.huge

	local humanoidsFolder = workspace:FindFirstChild("Humanoids")
	if humanoidsFolder then
		local regionsFolder = humanoidsFolder:FindFirstChild("Regions")
		if regionsFolder then
			for _, region in ipairs(regionsFolder:GetChildren()) do
				local activeNpcs = region:FindFirstChild("ActiveNpcs")
				if activeNpcs then
					for _, folder in ipairs(activeNpcs:GetChildren()) do
						for _, npc in ipairs(folder:GetChildren()) do
							-- Yalnızca tabloda (listede) seçili olan NPC'leri hedef al
							if npc:IsA("Model") and targetNamesTable[npc.Name] then
								local targetHrp = npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChildWhichIsA("BasePart")
								local hum = npc:FindFirstChildOfClass("Humanoid")
								if targetHrp and hum and hum.Health > 0 then
									local dist = (targetHrp.Position - hrp.Position).Magnitude
									if dist < minDist then 
										minDist = dist 
										closest = npc 
									end
								end
							end
						end
					end
				end
			end
		end
	end
	return closest
end

local function getNearestEnemy()
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return nil end
	
	local closest = nil
	local minDist = math.huge
	
	local humanoidsFolder = workspace:FindFirstChild("Humanoids")
	if humanoidsFolder then
		local regionsFolder = humanoidsFolder:FindFirstChild("Regions")
		if regionsFolder then
			for _, region in ipairs(regionsFolder:GetChildren()) do
				local activeNpcs = region:FindFirstChild("ActiveNpcs")
				if activeNpcs then
					for _, folder in ipairs(activeNpcs:GetChildren()) do
						if folder:IsA("Folder") and not string.find(folder.Name:lower(), "civilian") then
							for _, npc in ipairs(folder:GetChildren()) do
								if npc:IsA("Model") then
									local targetHrp = npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChildWhichIsA("BasePart")
									local hum = npc:FindFirstChildOfClass("Humanoid")
									if targetHrp and hum and hum.Health > 0 then
										local dist = (targetHrp.Position - hrp.Position).Magnitude
										if dist < minDist then minDist = dist closest = npc end
									end
								end
							end
						end
					end
				end
			end
		end
	end
	return closest
end

-- Raid Captain Bulma (Korunan Sandık İçin)
local function getRaidCaptainNear(centerPos, radius)
	local closest = nil
	local minDist = radius
	local humanoidsFolder = workspace:FindFirstChild("Humanoids")
	if humanoidsFolder then
		local regionsFolder = humanoidsFolder:FindFirstChild("Regions")
		if regionsFolder then
			for _, region in ipairs(regionsFolder:GetChildren()) do
				local activeNpcs = region:FindFirstChild("ActiveNpcs")
				if activeNpcs then
					for _, folder in ipairs(activeNpcs:GetChildren()) do
						if folder.Name == "Raid Captain" then
							for _, npc in ipairs(folder:GetChildren()) do
								if npc:IsA("Model") then
									local targetHrp = npc.PrimaryPart or npc:FindFirstChild("HumanoidRootPart") or npc:FindFirstChildWhichIsA("BasePart")
									local hum = npc:FindFirstChildOfClass("Humanoid")
									if targetHrp and hum and hum.Health > 0 then
										local dist = (targetHrp.Position - centerPos).Magnitude
										if dist <= minDist then
											minDist = dist
											closest = npc
										end
									end
								end
							end
						end
					end
				end
			end
		end
	end
	return closest
end

-- Farm Döngüsü
RunService.Heartbeat:Connect(function()
	if isChestPriority then return end
	local char = LocalPlayer.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return end

	if not isSealedPriority then
		if npcFarmEnabled then currentTarget = getSmartTarget(selectedNPCs)
		elseif autoFarmEnabled then currentTarget = getNearestEnemy()
		else currentTarget = nil end
	end

	if currentTarget then
		local targetPart = currentTarget.PrimaryPart or currentTarget:FindFirstChild("HumanoidRootPart") or currentTarget:FindFirstChildWhichIsA("BasePart")
		if targetPart then
			hrp.Velocity = Vector3.zero
			hrp.RotVelocity = Vector3.zero
			local topPosition = targetPart.Position + Vector3.new(0, hitHeight, 0)
			hrp.CFrame = CFrame.lookAt(topPosition, targetPart.Position)
		end
	end
end)

task.spawn(function()
	while true do
		task.wait(0.1)
		
		if isChestPriority or not currentTarget then continue end
		if not isSealedPriority and not npcFarmEnabled and not autoFarmEnabled then continue end
		
		for i = 1, 5 do
			if isChestPriority or not currentTarget then break end
			if not isSealedPriority and not npcFarmEnabled and not autoFarmEnabled then break end
			pcall(function()
				if mouse1click then mouse1click() else
					VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 0)
					task.wait(0.01)
					VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0)
				end
			end)
			task.wait(punchDelay)
		end

		if useSkills and not isChestPriority and currentTarget then
			for _, keyStr in ipairs(skillOrder) do
				if activeSkills[keyStr] and currentTarget and not isChestPriority then
					pcall(function()
						VirtualInputManager:SendKeyEvent(true, Enum.KeyCode[keyStr], false, game)
						task.wait(0.05)
						VirtualInputManager:SendKeyEvent(false, Enum.KeyCode[keyStr], false, game)
					end)
					task.wait(0.5)
				end
			end
		end
	end
end)

MainTab:CreateSection("Gelişmiş Farm Sistemi")
MainTab:CreateToggle({ Name = "Genel Auto Farm (En Yakın)", CurrentValue = false, Callback = function(val) autoFarmEnabled = val if val then npcFarmEnabled = false end end })
MainTab:CreateToggle({ Name = "Özel NPC Farm (Seçilenler)", CurrentValue = false, Callback = function(val) npcFarmEnabled = val if val then autoFarmEnabled = false end end })

local npcDropdown = MainTab:CreateDropdown({ Name = "Hedef NPC Seç (Aşağıdan Ekle)", Options = npcNamesList, CurrentOption = npcNamesList[1], Callback = function(val) currentDropdownSelection = val end })
local selectedListLabel = MainTab:CreateLabel("Seçili NPC'ler: Yok")

MainTab:CreateButton({
	Name = "Seçileni Listeye Ekle / Çıkar",
	Callback = function()
		if currentDropdownSelection ~= "" and currentDropdownSelection ~= "Bulunamadı" then
			if selectedNPCs[currentDropdownSelection] then
				selectedNPCs[currentDropdownSelection] = nil -- Listede varsa çıkar
			else
				selectedNPCs[currentDropdownSelection] = true -- Listede yoksa ekle
			end
			
			local listStr = ""
			for name, _ in pairs(selectedNPCs) do
				listStr = listStr .. name .. ", "
			end
			if listStr == "" then listStr = "Yok" else listStr = string.sub(listStr, 1, -3) end
			selectedListLabel:Set("Seçili NPC'ler: " .. listStr)
		end
	end,
})

MainTab:CreateButton({ Name = "NPC Listesini Yenile", Callback = function() npcDropdown:Refresh(refreshNpcList()) end })

MainTab:CreateDivider()
MainTab:CreateSlider({ Name = "Vurma Yüksekliği", Range = { 1, 10 }, Increment = 1, Suffix = " stud", CurrentValue = 5, Callback = function(v) hitHeight = v end })
MainTab:CreateSlider({ Name = "Yumruk Hızı", Range = { 0, 1.5 }, Increment = 0.1, Suffix = " sn", CurrentValue = 0.6, Callback = function(v) punchDelay = v end })
MainTab:CreateToggle({ Name = "Yetenek Kullanımı", CurrentValue = false, Callback = function(v) useSkills = v end })

MainTab:CreateDivider()
MainTab:CreateSection("Kullanılacak Yetenekler")
for _, key in ipairs(skillOrder) do
	MainTab:CreateToggle({ Name = "Yetenek: " .. key, CurrentValue = false, Callback = function(val) activeSkills[key] = val end })
end

MainTab:CreateDivider()
MainTab:CreateSection("Otomatik Sandık (Sıfır Bekleme & T Tuşu)")

MainTab:CreateToggle({
	Name = "Auto Collect Chest (Normal Sandıklar)",
	CurrentValue = false,
	Callback = function(val)
		autoChestEnabled = val
		if val then
			task.spawn(function()
				while autoChestEnabled do
					local char = LocalPlayer.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart")
					if not hrp then task.wait(0.5) continue end
					
					local foundSomething = false
					local targetPrompts = {}
					
					for _, obj in ipairs(workspace:GetDescendants()) do
						if obj:IsA("ProximityPrompt") and (obj.Name == "LootDropPrompt" or obj.Name == "ChestPrompt") and obj.Enabled then
							local model = obj:FindFirstAncestorWhichIsA("Model")
							-- Sadece isminde "Sealed " geçmeyenleri listeye al
							if model and string.find(model.Name, "Sealed ") == 1 then
								continue
							end
							table.insert(targetPrompts, obj)
						end
					end
					
					for _, prompt in ipairs(targetPrompts) do
						if not autoChestEnabled then break end
						if prompt and prompt.Parent and prompt.Enabled then
							foundSomething = true
							isChestPriority = true 
							
							local targetPart = prompt.Parent
							if not targetPart:IsA("BasePart") then
								targetPart = prompt:FindFirstAncestorWhichIsA("BasePart") or (prompt:FindFirstAncestorWhichIsA("Model") and prompt:FindFirstAncestorWhichIsA("Model").PrimaryPart)
							end
							
							if targetPart then
								hrp.Velocity = Vector3.zero
								hrp.CFrame = targetPart.CFrame * CFrame.new(0, 2, 0)
								task.wait(0.2)
								
								pcall(function() prompt.HoldDuration = 0 end)
								task.wait(0.1)
								
								VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.T, false, game)
								task.wait(0.05)
								VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.T, false, game)
								
								task.wait(0.6)
							end
						end
					end
					
					if not foundSomething then isChestPriority = false end
					task.wait(0.5)
				end
				isChestPriority = false
			end)
		else
			isChestPriority = false
		end
	end,
})

MainTab:CreateToggle({
	Name = "Korunan Sandık (Sealed Chest Farm)",
	CurrentValue = false,
	Callback = function(val)
		autoSealedEnabled = val
		if val then
			task.spawn(function()
				while autoSealedEnabled do
					local char = LocalPlayer.Character
					local hrp = char and char:FindFirstChild("HumanoidRootPart")
					if not hrp then task.wait(0.5) continue end
					
					local foundSealed = false
					-- Sandık klasörü "Chest" veya "Chests" olabilir
					local chestsFolder = workspace:FindFirstChild("Chest") or workspace:FindFirstChild("Chests")
					
					if chestsFolder then
						for _, chest in ipairs(chestsFolder:GetChildren()) do
							if not autoSealedEnabled then break end
							
							-- Sadece tam olarak "Sealed " (boşluklu) ile başlayanları filtrele
							if chest:IsA("Model") and string.find(chest.Name, "Sealed ") == 1 then
								local rootPart = chest:FindFirstChild("RootPart") or chest.PrimaryPart or chest:FindFirstChildWhichIsA("BasePart")
								if rootPart then
									local prompt = chest:FindFirstChild("ChestPrompt", true)
									if prompt and prompt:IsA("ProximityPrompt") and prompt.Enabled then
										foundSealed = true
										
										local raidBoss = getRaidCaptainNear(rootPart.Position, 100)
										
										if raidBoss then
											-- Korumalar hayatta, önce onları kes
											isSealedPriority = true
											currentTarget = raidBoss
										else
											-- Korumalar temizlendi, sandığı aç
											isSealedPriority = false
											isChestPriority = true 
											currentTarget = nil
											
											hrp.Velocity = Vector3.zero
											local targetPart = prompt.Parent:IsA("BasePart") and prompt.Parent or rootPart
											hrp.CFrame = targetPart.CFrame * CFrame.new(0, 2, 0)
											task.wait(0.3)
											
											pcall(function() prompt.HoldDuration = 0 end)
											task.wait(0.1)
											
											VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.T, false, game)
											task.wait(0.05)
											VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.T, false, game)
											
											task.wait(0.8)
											isChestPriority = false
										end
										break
									end
								end
							end
						end
					end
					
					if not foundSealed then
						isSealedPriority = false
					end
					
					task.wait(0.1)
				end
				isSealedPriority = false
			end)
		else
			isSealedPriority = false
		end
	end,
})

--==================================================================--
--  PLAYER SEKME (KARAKTER AYARLARI)
--==================================================================--
local PlayerTab = Window:CreateTab("Player")

local walkSpeed = 16
local wsConnection
PlayerTab:CreateSection("Karakter Fiziği")
PlayerTab:CreateToggle({
	Name = "Hız Hilesi (Speed)",
	CurrentValue = false,
	Callback = function(val)
		if val then
			wsConnection = RunService.Heartbeat:Connect(function()
				if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
					LocalPlayer.Character.Humanoid.WalkSpeed = walkSpeed
				end
			end)
		else
			if wsConnection then wsConnection:Disconnect() end
			if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
				LocalPlayer.Character.Humanoid.WalkSpeed = 16
			end
		end
	end
})
PlayerTab:CreateSlider({ Name = "Hız Miktarı", Range = { 16, 300 }, Increment = 1, Suffix = " sps", CurrentValue = 16, Callback = function(v) walkSpeed = v end })

local jumpPower = 50
local jpConnection
PlayerTab:CreateToggle({
	Name = "Zıplama Gücü Hilesi",
	CurrentValue = false,
	Callback = function(val)
		if val then
			jpConnection = RunService.Heartbeat:Connect(function()
				if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
					LocalPlayer.Character.Humanoid.UseJumpPower = true
					LocalPlayer.Character.Humanoid.JumpPower = jumpPower
				end
			end)
		else
			if jpConnection then jpConnection:Disconnect() end
			if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
				LocalPlayer.Character.Humanoid.JumpPower = 50
			end
		end
	end
})
PlayerTab:CreateSlider({ Name = "Zıplama Miktarı", Range = { 50, 500 }, Increment = 1, Suffix = " jp", CurrentValue = 50, Callback = function(v) jumpPower = v end })

local infJumpConnection
PlayerTab:CreateToggle({
	Name = "Sonsuz Zıplama (Infinite Jump)",
	CurrentValue = false,
	Callback = function(val)
		if val then
			infJumpConnection = UserInputService.JumpRequest:Connect(function()
				if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
					LocalPlayer.Character.Humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
				end
			end)
		else
			if infJumpConnection then infJumpConnection:Disconnect() infJumpConnection = nil end
		end
	end
})

local spiderConnection
PlayerTab:CreateToggle({
	Name = "Duvara Tırmanma (Spider)",
	CurrentValue = false,
	Callback = function(val)
		if val then
			spiderConnection = RunService.Stepped:Connect(function()
				local char = LocalPlayer.Character
				local hrp = char and char:FindFirstChild("HumanoidRootPart")
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				if not hrp or not hum then return end
				
				local params = RaycastParams.new()
				params.FilterDescendantsInstances = {char}
				params.FilterType = Enum.RaycastFilterType.Exclude
				
				local result = workspace:Raycast(hrp.Position, hrp.CFrame.LookVector * 2.5, params)
				if result and hum.MoveDirection.Magnitude > 0 then
					hrp.Velocity = Vector3.new(hrp.Velocity.X, 35, hrp.Velocity.Z)
				end
			end)
		else
			if spiderConnection then spiderConnection:Disconnect() spiderConnection = nil end
		end
	end
})

local noclipConnection
PlayerTab:CreateToggle({
	Name = "Duvarlardan Geçme (Noclip)",
	CurrentValue = false,
	Callback = function(val)
		if val then
			noclipConnection = RunService.Stepped:Connect(function()
				if LocalPlayer.Character then
					for _, p in ipairs(LocalPlayer.Character:GetDescendants()) do
						if p:IsA("BasePart") and p.CanCollide then
							p.CanCollide = false
						end
					end
				end
			end)
		else
			if noclipConnection then noclipConnection:Disconnect() noclipConnection = nil end
		end
	end
})

PlayerTab:CreateDivider()

local flySpeed = 50
local flyConnection
PlayerTab:CreateSection("Uçma (Fly)")
PlayerTab:CreateToggle({
	Name = "Fly Aktif",
	CurrentValue = false,
	Callback = function(val)
		local char = LocalPlayer.Character
		local hrp = char and char:FindFirstChild("HumanoidRootPart")
		if not hrp then return end
		
		if val then
			local bv = Instance.new("BodyVelocity")
			bv.Name = "VelocityFlyBV"
			bv.MaxForce = Vector3.new(math.huge, math.huge, math.huge)
			bv.Velocity = Vector3.new(0, 0, 0)
			bv.Parent = hrp

			local bg = Instance.new("BodyGyro")
			bg.Name = "VelocityFlyBG"
			bg.MaxTorque = Vector3.new(math.huge, math.huge, math.huge)
			bg.CFrame = hrp.CFrame
			bg.Parent = hrp

			flyConnection = RunService.RenderStepped:Connect(function()
				local camera = workspace.CurrentCamera
				local moveDir = Vector3.new(0,0,0)
				
				if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + camera.CFrame.LookVector end
				if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - camera.CFrame.LookVector end
				if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - camera.CFrame.RightVector end
				if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + camera.CFrame.RightVector end
				if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0,1,0) end
				if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then moveDir = moveDir - Vector3.new(0,1,0) end

				bv.Velocity = moveDir * flySpeed
				bg.CFrame = camera.CFrame
			end)
		else
			if flyConnection then flyConnection:Disconnect() flyConnection = nil end
			local bv = hrp:FindFirstChild("VelocityFlyBV")
			if bv then bv:Destroy() end
			local bg = hrp:FindFirstChild("VelocityFlyBG")
			if bg then bg:Destroy() end
		end
	end
})
PlayerTab:CreateSlider({ Name = "Fly Hızı", Range = { 10, 300 }, Increment = 5, Suffix = " vel", CurrentValue = 50, Callback = function(v) flySpeed = v end })

PlayerTab:CreateDivider()
PlayerTab:CreateSection("Clone & Kaçış Sistemi")

local currentClone = nil
local autoTpEnabled = false
local autoTpHealth = 25
local healthCheckConnection = nil

PlayerTab:CreateToggle({
	Name = "Canın Şu kadar kaldığında Clone a ışınlan",
	CurrentValue = false,
	Callback = function(val)
		autoTpEnabled = val
		if val then
			healthCheckConnection = RunService.Heartbeat:Connect(function()
				if autoTpEnabled and currentClone and currentClone.Parent then
					local char = LocalPlayer.Character
					if char then
						local hum = char:FindFirstChildOfClass("Humanoid")
						local hrp = char:FindFirstChild("HumanoidRootPart")
						local cloneHrp = currentClone:FindFirstChild("HumanoidRootPart")
						
						if hum and hrp and cloneHrp and hum.Health > 0 and hum.Health <= autoTpHealth then
							if (hrp.Position - cloneHrp.Position).Magnitude > 10 then
								hrp.CFrame = cloneHrp.CFrame
							end
						end
					end
				end
			end)
		else
			if healthCheckConnection then healthCheckConnection:Disconnect() healthCheckConnection = nil end
		end
	end,
})

PlayerTab:CreateSlider({ Name = "Işınlanma Can Sınırı", Range = { 1, 200 }, Increment = 1, Suffix = " HP", CurrentValue = 25, Callback = function(val) autoTpHealth = val end })

PlayerTab:CreateToggle({
	Name = "Clone oluştur",
	CurrentValue = false,
	Callback = function(val)
		if val then
			local char = LocalPlayer.Character
			if char then
				char.Archivable = true
				currentClone = char:Clone()
				currentClone.Name = LocalPlayer.Name .. "_Clone"
				char.Archivable = false
				
				local highlight = Instance.new("Highlight")
				highlight.FillColor = Color3.new(0, 0, 0)
				highlight.OutlineColor = Color3.new(0, 0, 0)
				highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				highlight.Parent = currentClone
				
				for _, part in ipairs(currentClone:GetDescendants()) do
					if part:IsA("BasePart") then part.Anchored = true part.CanCollide = false end
				end
				currentClone.Parent = workspace
			end
		else
			if currentClone then currentClone:Destroy() currentClone = nil end
		end
	end,
})

PlayerTab:CreateButton({
	Name = "TP Clone",
	Callback = function()
		if currentClone and currentClone:FindFirstChild("HumanoidRootPart") then
			local char = LocalPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then hrp.CFrame = currentClone.HumanoidRootPart.CFrame end
		end
	end,
})

PlayerTab:CreateKeybind({
	Name = "Tuş ile Clone'a Işınlan",
	CurrentKeybind = Enum.KeyCode.G,
	Callback = function(key)
		if currentClone and currentClone:FindFirstChild("HumanoidRootPart") then
			local char = LocalPlayer.Character
			local hrp = char and char:FindFirstChild("HumanoidRootPart")
			if hrp then hrp.CFrame = currentClone.HumanoidRootPart.CFrame end
		end
	end,
})
