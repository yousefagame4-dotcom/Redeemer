--// Yo Redeemer - Balanced UI Edition
--// Place this LocalScript in StarterPlayerScripts.
--// Reworked UI: responsive layout, real tabs, consistent spacing, animations,
--// Non-blocking startup/scanning: never anchors or freezes the player.
--// hover/press states, compact cards, scrolling, mobile-friendly sizing,
--// cleaner status/log presentation, and preserved core functionality.

--============================================================
-- SERVICES
--============================================================
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local MarketplaceService = game:GetService("MarketplaceService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

pcall(function()
    if script then
        script.Name = "Yo Redeemer"
    end
end)

--============================================================
-- CONFIG
--============================================================
local CONFIG = {
    GuiName = "YoRedeemer",
    StateKey = "YoRedeemerState_v4",
    ToggleKey = Enum.KeyCode.LeftControl, -- Left Ctrl and Right Ctrl both toggle the UI.

    WindowMin = Vector2.new(560, 520),
    WindowMax = Vector2.new(900, 680),

    Colors = {
        Background = Color3.fromRGB(10, 11, 14),
        Surface = Color3.fromRGB(17, 19, 24),
        Surface2 = Color3.fromRGB(22, 24, 30),
        Surface3 = Color3.fromRGB(27, 30, 37),
        Border = Color3.fromRGB(48, 52, 62),

        Text = Color3.fromRGB(242, 244, 248),
        TextDim = Color3.fromRGB(158, 164, 176),
        TextFaint = Color3.fromRGB(105, 111, 124),

        Accent = Color3.fromRGB(139, 92, 246),
        AccentSoft = Color3.fromRGB(111, 72, 205),

        Success = Color3.fromRGB(74, 222, 128),
        Warning = Color3.fromRGB(250, 204, 21),
        Error = Color3.fromRGB(248, 113, 113),
    },

    Animation = {
        Fast = 0.12,
        Normal = 0.18,
        Slow = 0.28,
    }
}

--============================================================
-- HELPERS
--============================================================
local function safeCall(fn, ...)
    local ok, result = pcall(fn, ...)
    return ok, result
end

local function new(className, props)
    local object = Instance.new(className)
    if props then
        for key, value in pairs(props) do
            if key ~= "Parent" then
                object[key] = value
            end
        end
        if props.Parent then
            object.Parent = props.Parent
        end
    end
    return object
end

local function addCorner(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
    return corner
end

local function addStroke(parent, color, thickness, transparency)
    local stroke = Instance.new("UIStroke")
    stroke.Color = color or CONFIG.Colors.Border
    stroke.Thickness = thickness or 1
    stroke.Transparency = transparency or 0
    stroke.Parent = parent
    return stroke
end

local function addPadding(parent, left, right, top, bottom)
    local padding = Instance.new("UIPadding")
    padding.PaddingLeft = UDim.new(0, left or 0)
    padding.PaddingRight = UDim.new(0, right or 0)
    padding.PaddingTop = UDim.new(0, top or 0)
    padding.PaddingBottom = UDim.new(0, bottom or 0)
    padding.Parent = parent
    return padding
end

local function tween(object, duration, properties, style, direction)
    if not object then return end
    local info = TweenInfo.new(
        duration or CONFIG.Animation.Normal,
        style or Enum.EasingStyle.Quart,
        direction or Enum.EasingDirection.Out
    )
    return TweenService:Create(object, info, properties)
end

local function playTween(object, duration, properties, style, direction)
    local t = tween(object, duration, properties, style, direction)
    if t then t:Play() end
    return t
end

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function cleanText(text)
    text = tostring(text or "")
    text = text:gsub("<.->", "")
    text = text:gsub("%s+", " ")
    text = text:gsub("^%s+", "")
    text = text:gsub("%s+$", "")
    return text
end

local function formatTime(timestamp)
    return os.date("%H:%M:%S", timestamp or os.time())
end

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do
        copy[deepCopy(k)] = deepCopy(v)
    end
    return copy
end

--============================================================
-- STATE
--============================================================
local State = {
    savedCodes = {},
    processedLabels = {},

    redeeming = false,
    redeemAfter = 1,

    listen = true,
    autoSubmit = true,
    spamRedeem = false,
    retypeInvalid = true,
    splitBuffer = false,
    riddleSolver = false,
    deleteAfterRedeem = true,

    autoInteract = true,
    interactRange = 10,
    holdingSpeed = "Normal", -- "Normal" or "Fast"

    uiVisible = true,
    uiScale = 1,

    launcherPosition = nil,

    logs = {},
    maxLogs = 300,
}

-- Runtime-only shutdown flag. This is intentionally NOT persisted.
local terminated = false

local function isAlive()
    return not terminated
end

--============================================================
-- REDEEM QUEUE
-- Declared before shutdown so killYoRedeemer can always clear it.
--============================================================
local RedeemQueue = {}
local RedeemWorkerRunning = false

local function loadState()
    local encoded = Player:GetAttribute(CONFIG.StateKey)
    if not encoded then return end

    local ok, decoded = pcall(function()
        return HttpService:JSONDecode(encoded)
    end)

    if ok and type(decoded) == "table" then
        for key, value in pairs(decoded) do
            if State[key] ~= nil and key ~= "savedCodes" and key ~= "processedLabels" and key ~= "logs" then
                State[key] = value
            end
        end
    end
end

local function persist()
    local saveData = {}

    for key, value in pairs(State) do
        if key ~= "savedCodes" and key ~= "processedLabels" and key ~= "logs" then
            saveData[key] = value
        end
    end

    pcall(function()
        Player:SetAttribute(CONFIG.StateKey, HttpService:JSONEncode(saveData))
    end)
end

loadState()

-- Guard persisted UI values in case an older/corrupted state contains bad types.
if type(State.uiVisible) ~= "boolean" then
    State.uiVisible = true
end
if type(State.uiScale) ~= "number" then
    State.uiScale = 1
end
State.uiScale = clamp(State.uiScale, 0.8, 1.15)

if type(State.launcherPosition) ~= "table"
    or type(State.launcherPosition.x) ~= "number"
    or type(State.launcherPosition.y) ~= "number" then
    State.launcherPosition = nil
end

local function addLog(message)
    if terminated then return end
    table.insert(State.logs, 1, {
        time = os.time(),
        text = tostring(message)
    })

    while #State.logs > State.maxLogs do
        table.remove(State.logs)
    end
end

--============================================================
-- CLEAN OLD UI
--============================================================
pcall(function()
    local old = PlayerGui:FindFirstChild(CONFIG.GuiName)
    if old then
        old:Destroy()
    end
end)

--============================================================
-- ROOT GUI
--============================================================
local Gui = new("ScreenGui", {
    Name = CONFIG.GuiName,
    ResetOnSpawn = false,
    IgnoreGuiInset = true,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    Parent = PlayerGui,
})

--======================== GUI PROTECTION BLOCK ========================--
pcall(function()
    if syn and syn.protect_gui then
        syn.protect_gui(Gui)
        Gui.Parent = game:GetService("CoreGui")
    elseif gethui then
        Gui.Parent = gethui()
    else
        Gui.Parent = game:GetService("CoreGui")
    end
end)

if not Gui.Parent then
    Gui.Parent = PlayerGui
end
--======================================================================--

--============================================================
-- MAIN WINDOW
--============================================================
local Main = new("Frame", {
    Name = "Main",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(760, 600),
    BackgroundColor3 = CONFIG.Colors.Background,
    BorderSizePixel = 0,
    ClipsDescendants = true,
    Parent = Gui,
})
addCorner(Main, 16)
addStroke(Main, CONFIG.Colors.Border, 1)

-- Subtle procedural texture / sheen: no external asset required.
local MainSheen = new("Frame", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 0.95,
    BackgroundColor3 = CONFIG.Colors.Accent,
    BorderSizePixel = 0,
    ZIndex = 0,
    Parent = Main,
})
addCorner(MainSheen, 16)

new("UIGradient", {
    Rotation = 135,
    Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.15),
        NumberSequenceKeypoint.new(0.30, 0.90),
        NumberSequenceKeypoint.new(0.58, 1),
        NumberSequenceKeypoint.new(1, 0.35),
    }),
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, CONFIG.Colors.Accent),
        ColorSequenceKeypoint.new(1, CONFIG.Colors.Background),
    }),
    Parent = MainSheen,
})

local CornerGlow = new("Frame", {
    Size = UDim2.fromOffset(240, 240),
    Position = UDim2.new(1, -155, 0, -150),
    BackgroundColor3 = CONFIG.Colors.Accent,
    BackgroundTransparency = 0.94,
    BorderSizePixel = 0,
    ZIndex = 0,
    Parent = Main,
})
addCorner(CornerGlow, 120)

local MainScale = new("UIScale", {
    Scale = State.uiScale,
    Parent = Main,
})

--============================================================
-- FLOATING OPEN / LAUNCHER BUTTON
--============================================================
local Launcher = new("TextButton", {
    Name = "OpenLauncher",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromOffset(0, 0),
    Size = UDim2.fromOffset(58, 58),
    BackgroundColor3 = CONFIG.Colors.Accent,
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "D",
    Font = Enum.Font.GothamBold,
    TextSize = 20,
    TextColor3 = Color3.new(1, 1, 1),
    ZIndex = 50,
    Visible = false,
    Active = true,
    Selectable = true,
    Parent = Gui,
})
addCorner(Launcher, 17)
addStroke(Launcher, CONFIG.Colors.Border, 1)

new("UIGradient", {
    Rotation = 125,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, Color3.fromRGB(178, 136, 255)),
        ColorSequenceKeypoint.new(0.45, CONFIG.Colors.Accent),
        ColorSequenceKeypoint.new(1, CONFIG.Colors.AccentSoft),
    }),
    Parent = Launcher,
})

local LauncherScale = new("UIScale", {
    Scale = 1,
    Parent = Launcher,
})

local LauncherGradient = new("UIGradient", {
    Rotation = 135,
    Color = ColorSequence.new({
        ColorSequenceKeypoint.new(0, CONFIG.Colors.Accent),
        ColorSequenceKeypoint.new(1, CONFIG.Colors.AccentSoft),
    }),
    Parent = Launcher,
})

local LauncherHint = new("TextLabel", {
    Size = UDim2.new(1, -8, 0, 12),
    Position = UDim2.new(0, 4, 1, -16),
    BackgroundTransparency = 1,
    Text = "OPEN",
    Font = Enum.Font.GothamBold,
    TextSize = 7,
    TextColor3 = Color3.fromRGB(235, 232, 255),
    TextTransparency = 0.08,
    ZIndex = 51,
    Parent = Launcher,
})

--============================================================
-- TOP ACCENT
--============================================================
local AccentBar = new("Frame", {
    Name = "AccentBar",
    Size = UDim2.new(1, 0, 0, 2),
    BackgroundColor3 = CONFIG.Colors.Accent,
    BorderSizePixel = 0,
    Parent = Main,
})

--============================================================
-- HEADER
--============================================================
local Header = new("Frame", {
    Name = "Header",
    Size = UDim2.new(1, 0, 0, 76),
    Position = UDim2.fromOffset(0, 2),
    BackgroundColor3 = CONFIG.Colors.Surface,
    BorderSizePixel = 0,
    Parent = Main,
})

addPadding(Header, 18, 14, 12, 10)

local Logo = new("Frame", {
    Size = UDim2.fromOffset(44, 44),
    BackgroundColor3 = CONFIG.Colors.Accent,
    BorderSizePixel = 0,
    Parent = Header,
})
addCorner(Logo, 12)

new("TextLabel", {
    Size = UDim2.fromScale(1, 1),
    BackgroundTransparency = 1,
    Text = "D",
    Font = Enum.Font.GothamBold,
    TextSize = 21,
    TextColor3 = Color3.new(1, 1, 1),
    Parent = Logo,
})

local TitleBlock = new("Frame", {
    Size = UDim2.new(1, -165, 1, 0),
    Position = UDim2.fromOffset(56, 0),
    BackgroundTransparency = 1,
    Parent = Header,
})

new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 25),
    Position = UDim2.fromOffset(0, 0),
    BackgroundTransparency = 1,
    Text = "Yo Redeemer",
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    TextColor3 = CONFIG.Colors.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = TitleBlock,
})

new("TextLabel", {
    Size = UDim2.new(1, 0, 0, 19),
    Position = UDim2.fromOffset(0, 27),
    BackgroundTransparency = 1,
    Text = "Code collection • redemption • interaction",
    Font = Enum.Font.Gotham,
    TextSize = 11,
    TextColor3 = CONFIG.Colors.TextDim,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = TitleBlock,
})

local GameNameLabel = new("TextLabel", {
    Name = "GameNameLabel",
    Size = UDim2.new(1, -6, 0, 15),
    Position = UDim2.fromOffset(0, 46),
    BackgroundTransparency = 1,
    Text = "GAME • " .. tostring(game.Name),
    Font = Enum.Font.GothamMedium,
    TextSize = 9,
    TextColor3 = CONFIG.Colors.TextFaint,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextTruncate = Enum.TextTruncate.AtEnd,
    Parent = TitleBlock,
})

local HeaderStatus = new("TextLabel", {
    Size = UDim2.fromOffset(110, 22),
    Position = UDim2.new(1, -152, 0, 3),
    BackgroundTransparency = 1,
    Text = "● READY",
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    TextColor3 = CONFIG.Colors.Success,
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent = Header,
})

local CloseButton = new("TextButton", {
    Size = UDim2.fromOffset(32, 32),
    Position = UDim2.new(1, -38, 0, 1),
    BackgroundColor3 = CONFIG.Colors.Surface3,
    BorderSizePixel = 0,
    Text = "×",
    Font = Enum.Font.GothamMedium,
    TextSize = 20,
    TextColor3 = CONFIG.Colors.TextDim,
    AutoButtonColor = false,
    Parent = Header,
})
addCorner(CloseButton, 9)
addStroke(CloseButton, CONFIG.Colors.Border, 1)

--============================================================
-- TAB BAR
--============================================================
local TabBar = new("Frame", {
    Name = "TabBar",
    Size = UDim2.new(1, -28, 0, 46),
    Position = UDim2.fromOffset(14, 86),
    BackgroundColor3 = CONFIG.Colors.Surface,
    BorderSizePixel = 0,
    Parent = Main,
})
addCorner(TabBar, 11)
addStroke(TabBar, CONFIG.Colors.Border, 1)
addPadding(TabBar, 5, 5, 5, 5)

local TabLayout = new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    Padding = UDim.new(0, 5),
    Parent = TabBar,
})

--============================================================
-- CONTENT HOLDER
--============================================================
local ContentHolder = new("Frame", {
    Name = "ContentHolder",
    Size = UDim2.new(1, -28, 1, -150),
    Position = UDim2.fromOffset(14, 140),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
    Parent = Main,
})

local Pages = {}
local CurrentPage = nil

local function makePage(name)
    local page = new("ScrollingFrame", {
        Name = name,
        Size = UDim2.fromScale(1, 1),
        CanvasSize = UDim2.new(0, 0, 0, 0),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = CONFIG.Colors.Border,
        ScrollingDirection = Enum.ScrollingDirection.Y,
        Visible = false,
        Parent = ContentHolder,
    })

    addPadding(page, 2, 5, 4, 12)

    local layout = new("UIListLayout", {
        Padding = UDim.new(0, 10),
        SortOrder = Enum.SortOrder.LayoutOrder,
        Parent = page,
    })

    Pages[name] = page
    return page
end

--============================================================
-- UI STYLE HELPERS
--============================================================
local function addHover(button, normalColor, hoverColor, pressedColor)
    button.AutoButtonColor = false

    button.MouseEnter:Connect(function()
        playTween(button, CONFIG.Animation.Fast, {
            BackgroundColor3 = hoverColor or CONFIG.Colors.Surface3
        })
    end)

    button.MouseLeave:Connect(function()
        playTween(button, CONFIG.Animation.Fast, {
            BackgroundColor3 = normalColor
        })
    end)

    button.MouseButton1Down:Connect(function()
        playTween(button, 0.06, {
            BackgroundColor3 = pressedColor or CONFIG.Colors.AccentSoft
        })
    end)

    button.MouseButton1Up:Connect(function()
        playTween(button, CONFIG.Animation.Fast, {
            BackgroundColor3 = hoverColor or CONFIG.Colors.Surface3
        })
    end)
end

local function makeTab(text)
    local button = new("TextButton", {
        Size = UDim2.new(0.333, -4, 1, 0),
        BackgroundColor3 = CONFIG.Colors.Surface2,
        BorderSizePixel = 0,
        Text = text,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = CONFIG.Colors.TextDim,
        AutoButtonColor = false,
        Parent = TabBar,
    })
    addCorner(button, 8)
    return button
end

local function makeCard(parent, title, subtitle, height)
    local card = new("Frame", {
        Size = UDim2.new(1, -4, 0, height or 100),
        BackgroundColor3 = CONFIG.Colors.Surface,
        BorderSizePixel = 0,
        Parent = parent,
    })
    addCorner(card, 12)
    addStroke(card, CONFIG.Colors.Border, 1)

    local headerHeight = subtitle and 46 or 34

    new("TextLabel", {
        Size = UDim2.new(1, -24, 0, 20),
        Position = UDim2.fromOffset(12, 9),
        BackgroundTransparency = 1,
        Text = title,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = CONFIG.Colors.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = card,
    })

    if subtitle then
        new("TextLabel", {
            Size = UDim2.new(1, -24, 0, 16),
            Position = UDim2.fromOffset(12, 28),
            BackgroundTransparency = 1,
            Text = subtitle,
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextColor3 = CONFIG.Colors.TextDim,
            TextXAlignment = Enum.TextXAlignment.Left,
            Parent = card,
        })
    end

    return card, headerHeight
end

local function makeButton(parent, text, width, accent)
    local button = new("TextButton", {
        Size = UDim2.fromOffset(width or 100, 38),
        BackgroundColor3 = accent and CONFIG.Colors.Accent or CONFIG.Colors.Surface3,
        BorderSizePixel = 0,
        Text = text,
        Font = Enum.Font.GothamBold,
        TextSize = 11,
        TextColor3 = CONFIG.Colors.Text,
        AutoButtonColor = false,
        Parent = parent,
    })
    addCorner(button, 9)
    addStroke(button, accent and CONFIG.Colors.AccentSoft or CONFIG.Colors.Border, 1)

    addHover(
        button,
        accent and CONFIG.Colors.Accent or CONFIG.Colors.Surface3,
        accent and Color3.fromRGB(157, 112, 255) or Color3.fromRGB(34, 37, 45),
        accent and CONFIG.Colors.AccentSoft or Color3.fromRGB(29, 32, 39)
    )

    return button
end

local function makeDivider(parent)
    return new("Frame", {
        Size = UDim2.new(1, 0, 0, 1),
        BackgroundColor3 = CONFIG.Colors.Border,
        BorderSizePixel = 0,
        Parent = parent,
    })
end

--============================================================
-- CODES PAGE
--============================================================
local CodesPage = makePage("Codes")

local CodeCard = makeCard(
    CodesPage,
    "CODE QUEUE",
    "Captured codes appear here before redemption.",
    176
)

local CodePreview = new("TextLabel", {
    Size = UDim2.new(1, -24, 0, 56),
    Position = UDim2.fromOffset(12, 54),
    BackgroundColor3 = CONFIG.Colors.Background,
    BorderSizePixel = 0,
    Text = "No codes collected",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = CONFIG.Colors.TextDim,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Center,
    TextWrapped = true,
    Parent = CodeCard,
})
addCorner(CodePreview, 9)
addStroke(CodePreview, CONFIG.Colors.Border, 1)
addPadding(CodePreview, 12, 12, 6, 6)

local CodeActions = new("Frame", {
    Size = UDim2.new(1, -24, 0, 42),
    Position = UDim2.fromOffset(12, 122),
    BackgroundTransparency = 1,
    Parent = CodeCard,
})

local CodeActionLayout = new("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    HorizontalAlignment = Enum.HorizontalAlignment.Left,
    VerticalAlignment = Enum.VerticalAlignment.Center,
    Padding = UDim.new(0, 8),
    Parent = CodeActions,
})

local CopyButton = makeButton(CodeActions, "COPY", 88, false)
local ClearButton = makeButton(CodeActions, "CLEAR", 88, false)
local RedeemButton = makeButton(CodeActions, "REDEEM", 112, true)

local StatusCard = makeCard(
    CodesPage,
    "STATUS",
    nil,
    76
)

local StatusText = new("TextLabel", {
    Size = UDim2.new(1, -24, 0, 24),
    Position = UDim2.fromOffset(12, 38),
    BackgroundTransparency = 1,
    Text = "Ready",
    Font = Enum.Font.GothamMedium,
    TextSize = 12,
    TextColor3 = CONFIG.Colors.TextDim,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = StatusCard,
})

local CollectedText = new("TextLabel", {
    Size = UDim2.fromOffset(160, 24),
    Position = UDim2.new(1, -172, 0, 38),
    BackgroundTransparency = 1,
    Text = "0 / 1",
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = CONFIG.Colors.Accent,
    TextXAlignment = Enum.TextXAlignment.Right,
    Parent = StatusCard,
})

--============================================================
-- CODE OPTIONS CARD
--============================================================
local OptionsCard = makeCard(
    CodesPage,
    "AUTOMATION",
    "Only enable the behavior you actually need.",
    300
)

local OptionsGrid = new("Frame", {
    Size = UDim2.new(1, -24, 0, 200),
    Position = UDim2.fromOffset(12, 54),
    BackgroundTransparency = 1,
    Parent = OptionsCard,
})

local GridLayout = new("UIGridLayout", {
    CellPadding = UDim2.fromOffset(8, 8),
    CellSize = UDim2.new(0.5, -4, 0, 46),
    FillDirection = Enum.FillDirection.Horizontal,
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = OptionsGrid,
})

local function makeToggle(parent, label, initial, callback)
    local state = initial

    local button = new("TextButton", {
        BackgroundColor3 = state and CONFIG.Colors.Accent or CONFIG.Colors.Surface3,
        BorderSizePixel = 0,
        Text = "",
        AutoButtonColor = false,
        Parent = parent,
    })
    addCorner(button, 9)
    addStroke(button, state and CONFIG.Colors.AccentSoft or CONFIG.Colors.Border, 1)

    local nameLabel = new("TextLabel", {
        Size = UDim2.new(1, -54, 1, 0),
        Position = UDim2.fromOffset(12, 0),
        BackgroundTransparency = 1,
        Text = label,
        Font = Enum.Font.GothamMedium,
        TextSize = 10,
        TextColor3 = CONFIG.Colors.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
        Parent = button,
    })

    local pill = new("Frame", {
        Size = UDim2.fromOffset(31, 17),
        Position = UDim2.new(1, -42, 0.5, -8),
        BackgroundColor3 = state and Color3.fromRGB(235, 231, 255) or CONFIG.Colors.Background,
        BorderSizePixel = 0,
        Parent = button,
    })
    addCorner(pill, 10)

    local dot = new("Frame", {
        Size = UDim2.fromOffset(11, 11),
        Position = state and UDim2.new(1, -14, 0.5, -5) or UDim2.fromOffset(3, 3),
        BackgroundColor3 = state and CONFIG.Colors.Accent or CONFIG.Colors.TextFaint,
        BorderSizePixel = 0,
        Parent = pill,
    })
    addCorner(dot, 6)

    local function render()
        local base = state and CONFIG.Colors.Accent or CONFIG.Colors.Surface3
        local border = state and CONFIG.Colors.AccentSoft or CONFIG.Colors.Border

        playTween(button, CONFIG.Animation.Normal, {BackgroundColor3 = base})
        playTween(pill, CONFIG.Animation.Normal, {
            BackgroundColor3 = state and Color3.fromRGB(235, 231, 255) or CONFIG.Colors.Background
        })
        playTween(dot, CONFIG.Animation.Normal, {
            Position = state and UDim2.new(1, -14, 0.5, -5) or UDim2.fromOffset(3, 3),
            BackgroundColor3 = state and CONFIG.Colors.Accent or CONFIG.Colors.TextFaint
        })

        local stroke = button:FindFirstChildOfClass("UIStroke")
        if stroke then
            stroke.Color = border
        end
    end

    button.MouseEnter:Connect(function()
        playTween(button, CONFIG.Animation.Fast, {
            BackgroundColor3 = state and Color3.fromRGB(151, 105, 250) or Color3.fromRGB(34, 37, 45)
        })
    end)

    button.MouseLeave:Connect(render)

    button.MouseButton1Click:Connect(function()
        state = not state
        render()
        if callback then callback(state) end
    end)

    return button, function()
        return state
    end, function(value)
        state = value
        render()
    end
end

local ListenToggle, GetListen, SetListen = makeToggle(
    OptionsGrid, "Listen for codes", State.listen,
    function(v) State.listen = v; persist() end
)

local AutoSubmitToggle, GetAutoSubmit, SetAutoSubmit = makeToggle(
    OptionsGrid, "Auto submit", State.autoSubmit,
    function(v) State.autoSubmit = v; persist() end
)

local SpamToggle, GetSpamRedeem, SetSpamRedeem = makeToggle(
    OptionsGrid, "Repeat redeem", State.spamRedeem,
    function(v) State.spamRedeem = v; persist() end
)

local RetypeToggle, GetRetype, SetRetype = makeToggle(
    OptionsGrid, "Retype invalid", State.retypeInvalid,
    function(v) State.retypeInvalid = v; persist() end
)

local SplitToggle, GetSplit, SetSplit = makeToggle(
    OptionsGrid, "Split buffer", State.splitBuffer,
    function(v) State.splitBuffer = v; persist() end
)

local RiddleToggle, GetRiddle, SetRiddle = makeToggle(
    OptionsGrid, "Riddle solver", State.riddleSolver,
    function(v) State.riddleSolver = v; persist() end
)

local DeleteAfterRedeemToggle, GetDeleteAfterRedeem, SetDeleteAfterRedeem = makeToggle(
    OptionsGrid, "Delete after redeem", State.deleteAfterRedeem,
    function(v) State.deleteAfterRedeem = v; persist() end
)

--============================================================
-- REDEEM THRESHOLD
--============================================================
local ThresholdRow = new("Frame", {
    Size = UDim2.new(1, -24, 0, 46),
    Position = UDim2.fromOffset(12, 246),
    BackgroundTransparency = 1,
    Parent = OptionsCard,
})

new("TextLabel", {
    Size = UDim2.new(1, -160, 1, 0),
    BackgroundTransparency = 1,
    Text = "Redeem after",
    Font = Enum.Font.GothamMedium,
    TextSize = 11,
    TextColor3 = CONFIG.Colors.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = ThresholdRow,
})

local Stepper = new("Frame", {
    Size = UDim2.fromOffset(145, 38),
    Position = UDim2.new(1, -145, 0.5, -19),
    BackgroundColor3 = CONFIG.Colors.Surface3,
    BorderSizePixel = 0,
    Parent = ThresholdRow,
})
addCorner(Stepper, 9)
addStroke(Stepper, CONFIG.Colors.Border, 1)

local MinusButton = new("TextButton", {
    Size = UDim2.fromOffset(38, 38),
    BackgroundTransparency = 1,
    Text = "−",
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    TextColor3 = CONFIG.Colors.TextDim,
    AutoButtonColor = false,
    Parent = Stepper,
})

local ThresholdValue = new("TextLabel", {
    Size = UDim2.new(1, -76, 1, 0),
    Position = UDim2.fromOffset(38, 0),
    BackgroundTransparency = 1,
    Text = tostring(State.redeemAfter),
    Font = Enum.Font.GothamBold,
    TextSize = 12,
    TextColor3 = CONFIG.Colors.Text,
    TextXAlignment = Enum.TextXAlignment.Center,
    Parent = Stepper,
})

local PlusButton = new("TextButton", {
    Size = UDim2.fromOffset(38, 38),
    Position = UDim2.new(1, -38, 0, 0),
    BackgroundTransparency = 1,
    Text = "+",
    Font = Enum.Font.GothamBold,
    TextSize = 18,
    TextColor3 = CONFIG.Colors.TextDim,
    AutoButtonColor = false,
    Parent = Stepper,
})

--============================================================
-- INTERACT PAGE
--============================================================
local InteractPage = makePage("Interact")

local InteractCard = makeCard(
    InteractPage,
    "AUTO INTERACT",
    "Automatically look for nearby ProximityPrompts.",
    112
)

local InteractToggle = new("TextButton", {
    Size = UDim2.new(1, -24, 0, 42),
    Position = UDim2.fromOffset(12, 54),
    BackgroundColor3 = State.autoInteract and CONFIG.Colors.Accent or CONFIG.Colors.Surface3,
    BorderSizePixel = 0,
    Text = State.autoInteract and "AUTO INTERACT  •  ON" or "AUTO INTERACT  •  OFF",
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextColor3 = CONFIG.Colors.Text,
    AutoButtonColor = false,
    Parent = InteractCard,
})
addCorner(InteractToggle, 9)
addStroke(InteractToggle, State.autoInteract and CONFIG.Colors.AccentSoft or CONFIG.Colors.Border, 1)

--============================================================
-- HOLDING SPEED
--============================================================
-- Kept as its own card so the control is always visible and cannot
-- overlap the Auto Interact toggle or the interaction-range card.
local HoldingSpeedCard = makeCard(
    InteractPage,
    "HOLDING SPEED",
    "Choose how quickly ProximityPrompts are held.",
    112
)

local HoldingSpeedButton = new("TextButton", {
    Size = UDim2.new(1, -24, 0, 42),
    Position = UDim2.fromOffset(12, 54),
    BackgroundColor3 = State.holdingSpeed == "Fast" and CONFIG.Colors.Accent or CONFIG.Colors.Surface3,
    BorderSizePixel = 0,
    Text = State.holdingSpeed == "Fast" and "FAST  •  0.05s" or "NORMAL  •  1×",
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextColor3 = CONFIG.Colors.Text,
    AutoButtonColor = false,
    Parent = HoldingSpeedCard,
})
addCorner(HoldingSpeedButton, 9)
addStroke(HoldingSpeedButton, State.holdingSpeed == "Fast" and CONFIG.Colors.AccentSoft or CONFIG.Colors.Border, 1)

local renderLogs

local function setHoldingSpeedVisual()
    local fast = State.holdingSpeed == "Fast"
    HoldingSpeedButton.Text = fast and "FAST  •  0.05s" or "NORMAL  •  1×"
    playTween(HoldingSpeedButton, CONFIG.Animation.Normal, {
        BackgroundColor3 = fast and CONFIG.Colors.Accent or CONFIG.Colors.Surface3
    })
    local stroke = HoldingSpeedButton:FindFirstChildOfClass("UIStroke")
    if stroke then
        stroke.Color = fast and CONFIG.Colors.AccentSoft or CONFIG.Colors.Border
    end
end

HoldingSpeedButton.MouseEnter:Connect(function()
    playTween(HoldingSpeedButton, CONFIG.Animation.Fast, {
        BackgroundColor3 = State.holdingSpeed == "Fast" and Color3.fromRGB(157, 112, 255) or Color3.fromRGB(34, 37, 45)
    })
end)

HoldingSpeedButton.MouseLeave:Connect(setHoldingSpeedVisual)

HoldingSpeedButton.MouseButton1Click:Connect(function()
    State.holdingSpeed = State.holdingSpeed == "Fast" and "Normal" or "Fast"
    setHoldingSpeedVisual()
    persist()
    addLog("Holding speed: " .. string.upper(State.holdingSpeed))
    renderLogs()
end)

local RangeCard = makeCard(
    InteractPage,
    "INTERACTION RANGE",
    "Choose the maximum distance used by the scanner.",
    120
)

local RangeRow = new("Frame", {
    Size = UDim2.new(1, -24, 0, 42),
    Position = UDim2.fromOffset(12, 54),
    BackgroundTransparency = 1,
    Parent = RangeCard,
})

local RangeMinus = makeButton(RangeRow, "−", 42, false)
local RangeValue = new("TextLabel", {
    Size = UDim2.new(1, -108, 0, 38),
    Position = UDim2.fromOffset(50, 0),
    BackgroundColor3 = CONFIG.Colors.Surface3,
    BorderSizePixel = 0,
    Text = tostring(State.interactRange) .. " studs",
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextColor3 = CONFIG.Colors.Text,
    Parent = RangeRow,
})
addCorner(RangeValue, 9)
addStroke(RangeValue, CONFIG.Colors.Border, 1)

local RangePlus = makeButton(RangeRow, "+", 42, false)
RangePlus.Position = UDim2.new(1, -42, 0, 0)

local PromptStatus = new("TextLabel", {
    Size = UDim2.new(1, -24, 0, 20),
    Position = UDim2.fromOffset(12, 99),
    BackgroundTransparency = 1,
    Text = "Scanning...",
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextColor3 = CONFIG.Colors.TextDim,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = RangeCard,
})

--============================================================
-- LOG PAGE / ACTIVITY
--============================================================
local ActivityCard = makeCard(
    InteractPage,
    "ACTIVITY",
    "Recent events and automation feedback.",
    280
)

local LogList = new("ScrollingFrame", {
    Size = UDim2.new(1, -24, 0, 210),
    Position = UDim2.fromOffset(12, 58),
    BackgroundColor3 = CONFIG.Colors.Background,
    BorderSizePixel = 0,
    ScrollBarThickness = 3,
    ScrollBarImageColor3 = CONFIG.Colors.Border,
    AutomaticCanvasSize = Enum.AutomaticSize.Y,
    CanvasSize = UDim2.new(0, 0, 0, 0),
    Parent = ActivityCard,
})
addCorner(LogList, 9)
addStroke(LogList, CONFIG.Colors.Border, 1)
addPadding(LogList, 9, 9, 8, 8)

local LogLayout = new("UIListLayout", {
    Padding = UDim.new(0, 5),
    SortOrder = Enum.SortOrder.LayoutOrder,
    Parent = LogList,
})

--============================================================
-- SETTINGS PAGE
--============================================================
local SettingsPage = makePage("Settings")

local AppearanceCard = makeCard(
    SettingsPage,
    "APPEARANCE",
    "Small controls that affect the interface itself.",
    156
)

local UIScaleRow = new("Frame", {
    Size = UDim2.new(1, -24, 0, 42),
    Position = UDim2.fromOffset(12, 55),
    BackgroundTransparency = 1,
    Parent = AppearanceCard,
})

new("TextLabel", {
    Size = UDim2.new(1, -180, 1, 0),
    BackgroundTransparency = 1,
    Text = "Interface scale",
    Font = Enum.Font.GothamMedium,
    TextSize = 11,
    TextColor3 = CONFIG.Colors.Text,
    TextXAlignment = Enum.TextXAlignment.Left,
    Parent = UIScaleRow,
})

local ScaleMinus = makeButton(UIScaleRow, "−", 38, false)
ScaleMinus.Position = UDim2.new(1, -130, 0, 2)

local ScaleValue = new("TextLabel", {
    Size = UDim2.fromOffset(48, 38),
    Position = UDim2.new(1, -86, 0, 2),
    BackgroundColor3 = CONFIG.Colors.Surface3,
    BorderSizePixel = 0,
    Text = tostring(math.floor(State.uiScale * 100)) .. "%",
    Font = Enum.Font.GothamBold,
    TextSize = 10,
    TextColor3 = CONFIG.Colors.Text,
    Parent = UIScaleRow,
})
addCorner(ScaleValue, 8)

local ScalePlus = makeButton(UIScaleRow, "+", 38, false)
ScalePlus.Position = UDim2.new(1, -38, 0, 2)

local KeybindCard = makeCard(
    SettingsPage,
    "HOTKEY",
    "Toggle the interface without closing it.",
    110
)

local KeybindText = new("TextLabel", {
    Size = UDim2.new(1, -24, 0, 38),
    Position = UDim2.fromOffset(12, 54),
    BackgroundColor3 = CONFIG.Colors.Surface3,
    BorderSizePixel = 0,
    Text = "Right Control",
    Font = Enum.Font.GothamBold,
    TextSize = 11,
    TextColor3 = CONFIG.Colors.Text,
    TextXAlignment = Enum.TextXAlignment.Center,
    TextYAlignment = Enum.TextYAlignment.Center,
    Parent = KeybindCard,
})
addCorner(KeybindText, 9)
addStroke(KeybindText, CONFIG.Colors.Border, 1)

--============================================================
-- YO REDEEMER SELF-DESTRUCT / KILL CONTROL
--============================================================
local KillCard = makeCard(
    SettingsPage,
    "SYSTEM SHUTDOWN",
    "Permanently stop Yo Redeemer and remove its interface.",
    196
)

local KillWarning = new("TextLabel", {
    Size = UDim2.new(1, -24, 0, 34),
    Position = UDim2.fromOffset(12, 52),
    BackgroundTransparency = 1,
    Text = "This stops the redeemer, clears its queue, removes saved state, and destroys the UI.",
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextColor3 = CONFIG.Colors.TextDim,
    TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    Parent = KillCard,
})

local KillButton = new("TextButton", {
    Size = UDim2.new(1, -24, 0, 58),
    Position = UDim2.fromOffset(12, 102),
    BackgroundColor3 = Color3.fromRGB(88, 26, 36),
    BorderSizePixel = 0,
    AutoButtonColor = false,
    Text = "KILL YO REDEEMER",
    Font = Enum.Font.GothamBold,
    TextSize = 13,
    TextColor3 = CONFIG.Colors.Text,
    Parent = KillCard,
})
addCorner(KillButton, 12)
local KillStroke = addStroke(KillButton, CONFIG.Colors.Error, 1)

local KillButtonScale = new("UIScale", {
    Scale = 1,
    Parent = KillButton,
})

local KillShine = new("Frame", {
    Size = UDim2.new(0, 90, 1, 0),
    Position = UDim2.fromOffset(-110, 0),
    BackgroundColor3 = Color3.fromRGB(255, 255, 255),
    BackgroundTransparency = 0.82,
    BorderSizePixel = 0,
    Rotation = 12,
    ClipsDescendants = true,
    Parent = KillButton,
})
addCorner(KillShine, 12)

-- Full-screen shutdown FX is created only when the user actually presses Kill.
local function makeShutdownFx()
    local fx = new("Frame", {
        Size = UDim2.fromScale(1, 1),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(255, 42, 78),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 9999,
        Parent = Gui,
    })

    local flash = new("Frame", {
        Size = UDim2.fromScale(0, 0),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = Color3.fromRGB(255, 245, 248),
        BackgroundTransparency = 0,
        BorderSizePixel = 0,
        ZIndex = 10001,
        Parent = fx,
    })
    addCorner(flash, 999)

    local ring = new("Frame", {
        Size = UDim2.fromScale(0.08, 0.08),
        Position = UDim2.fromScale(0.5, 0.5),
        AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ZIndex = 10000,
        Parent = fx,
    })
    addCorner(ring, 999)
    addStroke(ring, CONFIG.Colors.Error, 5)

    local shards = {}
    for i = 1, 18 do
        local shard = new("Frame", {
            Size = UDim2.fromOffset(math.random(4, 11), math.random(18, 48)),
            Position = UDim2.fromScale(0.5, 0.5),
            AnchorPoint = Vector2.new(0.5, 0.5),
            BackgroundColor3 = i % 2 == 0 and CONFIG.Colors.Error or Color3.fromRGB(255, 255, 255),
            BackgroundTransparency = 0.08,
            BorderSizePixel = 0,
            Rotation = math.random(0, 360),
            ZIndex = 10002,
            Parent = fx,
        })
        addCorner(shard, 6)
        table.insert(shards, shard)
    end

    return fx, flash, ring, shards
end

local function killYoRedeemer()
    if terminated then return end
    terminated = true

    -- Stop every internal activity immediately.
    State.listen = false
    State.autoSubmit = false
    State.spamRedeem = false
    State.autoInteract = false
    State.redeeming = false
    holding = false
    if type(RedeemQueue) == "table" then
        table.clear(RedeemQueue)
    end

    -- Remove the persisted footprint so the next run starts clean.
    pcall(function()
        Player:SetAttribute(CONFIG.StateKey, nil)
    end)

    local fx, flash, ring, shards = makeShutdownFx()

    -- Lock the button visually before the main window collapses.
    KillButton.Active = false
    KillButton.AutoButtonColor = false
    KillButton.Text = "SHUTTING DOWN..."
    KillWarning.Text = "Yo Redeemer is shutting down..."

    -- Big cinematic collapse: overshoot, spin, flash, then vanish.
    playTween(KillButtonScale, 0.12, {Scale = 1.06}, Enum.EasingStyle.Quad)
    playTween(KillButton, 0.12, {BackgroundColor3 = CONFIG.Colors.Error}, Enum.EasingStyle.Quad)
    playTween(KillShine, 0.18, {Position = UDim2.new(1, 20, 0, 0)}, Enum.EasingStyle.Quart)

    task.spawn(function()
        playTween(flash, 0.10, {Size = UDim2.fromScale(0.35, 0.35), BackgroundTransparency = 0.05}, Enum.EasingStyle.Quad)
        playTween(ring, 0.42, {Size = UDim2.fromScale(2.4, 2.4)}, Enum.EasingStyle.Quint)
        playTween(ring, 0.42, {BackgroundTransparency = 1}, Enum.EasingStyle.Quint)

        for i, shard in ipairs(shards) do
            local angle = math.rad((i / #shards) * 360)
            local distance = math.random(260, 520)
            local target = UDim2.new(0.5, math.cos(angle) * distance, 0.5, math.sin(angle) * distance)
            playTween(shard, 0.48, {Position = target, Rotation = shard.Rotation + math.random(-160, 160), BackgroundTransparency = 1}, Enum.EasingStyle.Quint)
        end

        task.wait(0.08)
        playTween(flash, 0.22, {Size = UDim2.fromScale(2.2, 2.2), BackgroundTransparency = 1}, Enum.EasingStyle.Quint)

        playTween(MainScale, 0.36, {Scale = 0.78}, Enum.EasingStyle.Back)
        playTween(Main, 0.34, {Rotation = 7}, Enum.EasingStyle.Quint)

        for _, child in ipairs(Main:GetDescendants()) do
            if child:IsA("TextLabel") or child:IsA("TextButton") or child:IsA("TextBox") or child:IsA("ImageLabel") then
                pcall(function()
                    playTween(child, 0.26, {TextTransparency = 1}, Enum.EasingStyle.Quad)
                end)
            elseif child:IsA("Frame") and child ~= Main then
                pcall(function()
                    playTween(child, 0.26, {BackgroundTransparency = 1}, Enum.EasingStyle.Quad)
                end)
            elseif child:IsA("UIStroke") then
                pcall(function()
                    playTween(child, 0.22, {Transparency = 1}, Enum.EasingStyle.Quad)
                end)
            end
        end

        task.wait(0.34)
        pcall(function() Gui:Destroy() end)
        pcall(function()
            if script then
                script:Destroy()
            end
        end)
    end)
end

KillButton.MouseEnter:Connect(function()
    if terminated then return end
    playTween(KillButtonScale, 0.16, {Scale = 1.025}, Enum.EasingStyle.Quart)
    playTween(KillButton, 0.16, {BackgroundColor3 = Color3.fromRGB(116, 30, 44)}, Enum.EasingStyle.Quart)
    playTween(KillStroke, 0.16, {Thickness = 2}, Enum.EasingStyle.Quart)
end)

KillButton.MouseLeave:Connect(function()
    if terminated then return end
    playTween(KillButtonScale, 0.16, {Scale = 1}, Enum.EasingStyle.Quart)
    playTween(KillButton, 0.16, {BackgroundColor3 = Color3.fromRGB(88, 26, 36)}, Enum.EasingStyle.Quart)
    playTween(KillStroke, 0.16, {Thickness = 1}, Enum.EasingStyle.Quart)
end)

KillButton.MouseButton1Down:Connect(function()
    if terminated then return end
    playTween(KillButtonScale, 0.07, {Scale = 0.97}, Enum.EasingStyle.Quad)
end)

KillButton.MouseButton1Up:Connect(function()
    if terminated then return end
    playTween(KillButtonScale, 0.10, {Scale = 1.025}, Enum.EasingStyle.Back)
end)

KillButton.MouseButton1Click:Connect(killYoRedeemer)

local InfoCard = makeCard(
    SettingsPage,
    "ABOUT",
    nil,
    126
)

new("TextLabel", {
    Size = UDim2.new(1, -24, 0, 62),
    Position = UDim2.fromOffset(12, 42),
    BackgroundTransparency = 1,
    Text = "Yo Redeemer\nBalanced UI Edition\nBuilt with responsive Roblox UI primitives.",
    Font = Enum.Font.Gotham,
    TextSize = 10,
    TextColor3 = CONFIG.Colors.TextDim,
    TextXAlignment = Enum.TextXAlignment.Left,
    TextYAlignment = Enum.TextYAlignment.Top,
    Parent = InfoCard,
})

--============================================================
-- TAB BUTTONS / PAGE SWITCHING
--============================================================
local CodesTab = makeTab("CODES")
local InteractTab = makeTab("INTERACT")
local SettingsTab = makeTab("SETTINGS")

local TabButtons = {
    Codes = CodesTab,
    Interact = InteractTab,
    Settings = SettingsTab,
}

local function setTabVisual(button, active)
    playTween(button, CONFIG.Animation.Normal, {
        BackgroundColor3 = active and CONFIG.Colors.Accent or CONFIG.Colors.Surface2,
        TextColor3 = active and CONFIG.Colors.Text or CONFIG.Colors.TextDim,
    })
end

local function selectTab(name)
    local target = Pages[name]
    if not target then return end

    for pageName, page in pairs(Pages) do
        page.Visible = pageName == name
    end

    for tabName, button in pairs(TabButtons) do
        setTabVisual(button, tabName == name)
    end

    CurrentPage = name
end

CodesTab.MouseButton1Click:Connect(function()
    selectTab("Codes")
end)

InteractTab.MouseButton1Click:Connect(function()
    selectTab("Interact")
end)

SettingsTab.MouseButton1Click:Connect(function()
    selectTab("Settings")
end)

selectTab("Codes")

--============================================================
-- LOG RENDERING
--============================================================
renderLogs = function()
    for _, child in ipairs(LogList:GetChildren()) do
        if child:IsA("TextLabel") then
            child:Destroy()
        end
    end

    if #State.logs == 0 then
        new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 30),
            BackgroundTransparency = 1,
            Text = "No activity yet.",
            Font = Enum.Font.Gotham,
            TextSize = 10,
            TextColor3 = CONFIG.Colors.TextFaint,
            TextXAlignment = Enum.TextXAlignment.Center,
            Parent = LogList,
        })
        return
    end

    for index = 1, math.min(#State.logs, 100) do
        local entry = State.logs[index]

        local label = new("TextLabel", {
            Size = UDim2.new(1, 0, 0, 27),
            BackgroundColor3 = index % 2 == 0 and CONFIG.Colors.Surface2 or CONFIG.Colors.Surface,
            BorderSizePixel = 0,
            Text = "  " .. formatTime(entry.time) .. "   " .. entry.text,
            Font = Enum.Font.Gotham,
            TextSize = 9,
            TextColor3 = CONFIG.Colors.TextDim,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextTruncate = Enum.TextTruncate.AtEnd,
            Parent = LogList,
        })
        addCorner(label, 6)
    end
end

--============================================================
-- DISPLAY HELPERS
--============================================================
local function updateCodeDisplay()
    if #State.savedCodes == 0 then
        CodePreview.Text = "No codes collected"
        CodePreview.TextColor3 = CONFIG.Colors.TextDim
    else
        CodePreview.Text = table.concat(State.savedCodes, " ")
        CodePreview.TextColor3 = CONFIG.Colors.Text
    end

    CollectedText.Text = tostring(#State.savedCodes) .. " / " .. tostring(State.redeemAfter) .. " words"
    ThresholdValue.Text = tostring(State.redeemAfter)
end

local function setStatus(text, kind)
    StatusText.Text = tostring(text)

    if kind == "success" then
        StatusText.TextColor3 = CONFIG.Colors.Success
        HeaderStatus.Text = "● READY"
        HeaderStatus.TextColor3 = CONFIG.Colors.Success
    elseif kind == "warning" then
        StatusText.TextColor3 = CONFIG.Colors.Warning
        HeaderStatus.Text = "● WAITING"
        HeaderStatus.TextColor3 = CONFIG.Colors.Warning
    elseif kind == "error" then
        StatusText.TextColor3 = CONFIG.Colors.Error
        HeaderStatus.Text = "● ERROR"
        HeaderStatus.TextColor3 = CONFIG.Colors.Error
    else
        StatusText.TextColor3 = CONFIG.Colors.TextDim
        HeaderStatus.Text = "● READY"
        HeaderStatus.TextColor3 = CONFIG.Colors.Success
    end
end

local function setInteractVisual()
    InteractToggle.Text = State.autoInteract and "AUTO INTERACT  •  ON" or "AUTO INTERACT  •  OFF"
    playTween(InteractToggle, CONFIG.Animation.Normal, {
        BackgroundColor3 = State.autoInteract and CONFIG.Colors.Accent or CONFIG.Colors.Surface3
    })

    local stroke = InteractToggle:FindFirstChildOfClass("UIStroke")
    if stroke then
        stroke.Color = State.autoInteract and CONFIG.Colors.AccentSoft or CONFIG.Colors.Border
    end
end

local function updateRange()
    RangeValue.Text = tostring(State.interactRange) .. " studs"
end

--============================================================
-- CODE / REDEEM LOGIC
--============================================================
local ConfirmButton = nil
local CodeTextBox = nil
local NotificationHolder = nil

local function solveRiddleCandidate(text)
    if not text or text == "" then return text end

    local cleaned = cleanText(text)
    local reversed = cleaned:reverse()

    if #reversed:gsub("%W", "") > #cleaned:gsub("%W", "") then
        cleaned = reversed
    end

    return cleaned:gsub("[^%w%s_-]", "")
end

local function pressConfirmSafe()
    if not ConfirmButton or not ConfirmButton.Parent then
        return false
    end

    local fired = false

    -- Try the direct button signal first. This is the fastest path for
    -- executor environments that expose firesignal.
    if typeof(firesignal) == "function" then
        pcall(function()
            if ConfirmButton.MouseButton1Click then
                firesignal(ConfirmButton.MouseButton1Click)
                fired = true
            end
        end)

        if not fired then
            pcall(function()
                if ConfirmButton.Activated then
                    firesignal(ConfirmButton.Activated)
                    fired = true
                end
            end)
        end
    end

    -- Normal Roblox path / fallback.
    if not fired then
        pcall(function()
            ConfirmButton:Activate()
            fired = true
        end)
    end

    return fired
end

local function fastSetRedeemText(text)
    if not CodeTextBox or not CodeTextBox.Parent then
        return false
    end

    text = tostring(text or "")

    -- Some games listen for FocusLost instead of merely watching .Text.
    -- Capture/Release happens in the same frame here: no character-by-
    -- character typing, no artificial delay, and no prolonged movement lock.
    if GetRetype() then
        pcall(function()
            CodeTextBox:CaptureFocus()
            CodeTextBox.Text = text
            CodeTextBox:ReleaseFocus(true)
        end)
    else
        CodeTextBox.Text = text
    end

    return CodeTextBox.Text == text
end

local function processRedeemTask(taskItem)
    if not isAlive() or not taskItem then return false end

    local codes = taskItem.codes or {}
    local combined = table.concat(codes, " ")

    if GetSplit() then
        local pieces = {}
        for word in combined:gmatch("%S+") do
            table.insert(pieces, word)
        end
        combined = table.concat(pieces, " ")
    end

    if GetRiddle() then
        combined = solveRiddleCandidate(combined)
    end

    if combined == "" then
        setStatus("Nothing to redeem.", "warning")
        return false
    end

    if not fastSetRedeemText(combined) then
        setStatus("Redeem box could not be filled.", "error")
        addLog("Redeem failed: code box unavailable")
        renderLogs()
        return false
    end

    -- Give Roblox one scheduler slice to process the TextBox assignment,
    -- then submit immediately. This is intentionally tiny (not 0.08s+).
    task.wait()

    local submitted = false

    if GetSpamRedeem() then
        for i = 1, 3 do
            if not isAlive() then return false end
            submitted = pressConfirmSafe() or submitted
            if i < 3 then
                task.wait(0.025)
            end
        end
    else
        submitted = pressConfirmSafe()
    end

    if not submitted then
        setStatus("Confirm button could not be triggered.", "error")
        addLog("Redeem failed: confirm button unavailable")
        renderLogs()
        return false
    end

    addLog("Redeemed instantly: " .. combined)
    renderLogs()
    setStatus("Redeemed: " .. combined, "success")

    -- Clear only AFTER the submit signal has been sent.
    if GetDeleteAfterRedeem() then
        State.savedCodes = {}
        State.processedLabels = {}

        if CodeTextBox and CodeTextBox.Parent then
            CodeTextBox.Text = ""
        end

        updateCodeDisplay()
        setStatus("Redeemed + captured words cleared.", "success")
        addLog("Deleted captured words after redeem")
        renderLogs()
    end

    return true
end

local function redeemWorker()
    if not isAlive() or RedeemWorkerRunning then return end

    RedeemWorkerRunning = true

    while isAlive() and #RedeemQueue > 0 do
        local item = table.remove(RedeemQueue, 1)
        processRedeemTask(item)
        if not isAlive() then break end
        -- No artificial 0.12s queue delay. The next item can submit
        -- immediately after the previous one finishes.
        task.wait()
    end

    RedeemWorkerRunning = false
    if not isAlive() then
        table.clear(RedeemQueue)
    end
end

local function enqueueRedeem(codes)
    if not isAlive() then return end

    table.insert(RedeemQueue, {
        codes = deepCopy(codes)
    })

    if not RedeemWorkerRunning then
        task.spawn(redeemWorker)
    end
end

local function doRedeem(manual)
    if not isAlive() or State.redeeming then return end

    if #State.savedCodes < State.redeemAfter then
        setStatus("Need more codes before redeeming.", "warning")
        return
    end

    State.redeeming = true

    local codes = deepCopy(State.savedCodes)
    enqueueRedeem(codes)

    setStatus(manual and "Manual redeem queued." or "Automatic redeem queued.", "success")

    State.redeeming = false
end

--============================================================
-- CAPTURE / NOTIFICATION WATCHER
--============================================================
local function addCapturedCode(text, labelObject)
    if not isAlive() or not GetListen() then return end

    -- The Amount value is the exact number of WORDS we are allowed to capture.
    -- Once the amount is reached, every other word is ignored until the
    -- captured queue is redeemed and cleared.
    if #State.savedCodes >= State.redeemAfter then
        return
    end

    if not text or cleanText(text) == "" then return end

    if labelObject and State.processedLabels[labelObject] then
        return
    end

    if labelObject then
        State.processedLabels[labelObject] = true
    end

    local cleaned = cleanText(text)
    local words = {}

    -- Extract individual words instead of storing the entire notification.
    for word in cleaned:gmatch("%S+") do
        word = word:gsub("[^%w_%-]", "")
        if word ~= "" then
            table.insert(words, word)
        end
    end

    -- Take only the number of words still needed.
    for _, word in ipairs(words) do
        if #State.savedCodes >= State.redeemAfter then
            break
        end

        table.insert(State.savedCodes, word)
        addLog("Captured: " .. word)
    end

    if #words == 0 then
        return
    end

    if CodeTextBox then
        CodeTextBox.Text = table.concat(State.savedCodes, " ")
    end

    updateCodeDisplay()
    renderLogs()

    if #State.savedCodes >= State.redeemAfter then
        setStatus(
            "Captured " .. tostring(State.redeemAfter) .. " word(s).",
            "success"
        )

        -- Auto-submit only after the exact requested amount is present.
        if GetAutoSubmit() then
            doRedeem(false)
        end
    else
        setStatus(
            "Captured " .. tostring(#State.savedCodes) .. " / " ..
            tostring(State.redeemAfter) .. " words.",
            "warning"
        )
    end
end

local function watchNotificationHolder(holder)
    if not isAlive() or not holder then return end

    for _, object in ipairs(holder:GetDescendants()) do
        if object:IsA("TextLabel") then
            object:GetPropertyChangedSignal("Text"):Connect(function()
                addCapturedCode(object.Text, object)
            end)

            addCapturedCode(object.Text, object)
        end
    end

    holder.DescendantAdded:Connect(function(object)
        if object:IsA("TextLabel") then
            object:GetPropertyChangedSignal("Text"):Connect(function()
                addCapturedCode(object.Text, object)
            end)

            addCapturedCode(object.Text, object)
        end
    end)
end

--============================================================
-- GAME GUI RESOLUTION
--============================================================
task.spawn(function()
    if not isAlive() then return end
    local top = PlayerGui:FindFirstChild("TopNotification")

    if top then
        NotificationHolder = top:FindFirstChild("TopNotification") or top
    end

    local codesRoot = PlayerGui:FindFirstChild("Codes")

    if codesRoot then
        local codesInner = codesRoot:FindFirstChild("Codes")

        if codesInner then
            local codeRedeem = codesInner:FindFirstChild("CodeRedeem")

            if codeRedeem then
                CodeTextBox = codeRedeem:FindFirstChild("TextBox")
            end

            ConfirmButton = codesInner:FindFirstChild("Confirm")
                if ConfirmButton and not ConfirmButton:IsA("GuiButton") then
                    ConfirmButton = nil
                end
        end
    end

    -- Batched GUI lookup: never scan a huge PlayerGui tree in one frame.
    if not CodeTextBox or not ConfirmButton then
        local descendants = PlayerGui:GetDescendants()
        for index, object in ipairs(descendants) do
            if not CodeTextBox and object:IsA("TextBox") and object.Name:lower():find("code") then
                CodeTextBox = object
            end

            if not ConfirmButton and object:IsA("GuiButton") and object.Name:lower():find("confirm") then
                ConfirmButton = object
            end

            if CodeTextBox and ConfirmButton then
                break
            end

            if index % 50 == 0 then
                task.wait()
            end
        end
    end

    if NotificationHolder then
        setStatus("Ready — listening for codes.", "success")
        PromptStatus.Text = "Notification listener connected."
        watchNotificationHolder(NotificationHolder)
    else
        setStatus("Waiting for notifications...", "warning")
        PromptStatus.Text = "Waiting for notification GUI..."

        for _ = 1, 6 do
            task.wait(1)

            local current = PlayerGui:FindFirstChild("TopNotification")

            if current then
                NotificationHolder = current:FindFirstChild("TopNotification") or current

                if NotificationHolder then
                    setStatus("Ready — listening for codes.", "success")
                    PromptStatus.Text = "Notification listener connected."
                    watchNotificationHolder(NotificationHolder)
                    break
                end
            end
        end

        if not NotificationHolder then
            setStatus("Notification GUI not found.", "error")
            PromptStatus.Text = "Notification GUI not found."
            addLog("Notification GUI not found")
            renderLogs()
        end
    end
end)

--============================================================
-- BUTTON BINDINGS
--============================================================
ClearButton.MouseButton1Click:Connect(function()
    State.savedCodes = {}
    State.processedLabels = {}

    if CodeTextBox then
        CodeTextBox.Text = ""
    end

    updateCodeDisplay()
    setStatus("Code queue cleared.", "success")
    addLog("Cleared saved codes")
    renderLogs()
end)

RedeemButton.MouseButton1Click:Connect(function()
    if #State.savedCodes > 0 then
        doRedeem(true)
    else
        setStatus("There are no codes to redeem.", "warning")
    end
end)

CopyButton.MouseButton1Click:Connect(function()
    local text = CodeTextBox and CodeTextBox.Text or table.concat(State.savedCodes, " ")

    if typeof(setclipboard) == "function" then
        pcall(function()
            setclipboard(text)
        end)
        setStatus("Copied to clipboard.", "success")
    else
        setStatus("Clipboard is unavailable here.", "warning")
    end

    addLog("Copied code queue")
    renderLogs()
end)

MinusButton.MouseButton1Click:Connect(function()
    State.redeemAfter = clamp(State.redeemAfter - 1, 1, 99)
    updateCodeDisplay()
    persist()
end)

PlusButton.MouseButton1Click:Connect(function()
    State.redeemAfter = clamp(State.redeemAfter + 1, 1, 99)
    updateCodeDisplay()
    persist()
end)

--============================================================
-- INTERACT BINDINGS
--============================================================
InteractToggle.MouseButton1Click:Connect(function()
    State.autoInteract = not State.autoInteract
    setInteractVisual()
    persist()

    addLog(State.autoInteract and "Auto interact enabled" or "Auto interact disabled")
    renderLogs()
end)

RangeMinus.MouseButton1Click:Connect(function()
    State.interactRange = clamp(State.interactRange - 2, 4, 50)
    updateRange()
    persist()
end)

RangePlus.MouseButton1Click:Connect(function()
    State.interactRange = clamp(State.interactRange + 2, 4, 50)
    updateRange()
    persist()
end)

--============================================================
-- SCALE CONTROLS
--============================================================
local function applyScale()
    State.uiScale = clamp(State.uiScale, 0.8, 1.15)

    MainScale.Scale = State.uiScale
    ScaleValue.Text = tostring(math.floor(State.uiScale * 100)) .. "%"

    persist()
end

ScaleMinus.MouseButton1Click:Connect(function()
    State.uiScale = State.uiScale - 0.05
    applyScale()
end)

ScalePlus.MouseButton1Click:Connect(function()
    State.uiScale = State.uiScale + 0.05
    applyScale()
end)

--============================================================
-- RESPONSIVE WINDOW SIZING
--============================================================
local function updateResponsiveSize()
    local camera = Workspace.CurrentCamera
    if not camera then return end

    local viewport = camera.ViewportSize
    local width = clamp(viewport.X - 28, CONFIG.WindowMin.X, CONFIG.WindowMax.X)
    local height = clamp(viewport.Y - 80, CONFIG.WindowMin.Y, CONFIG.WindowMax.Y)

    if viewport.X < 620 then
        width = math.max(320, viewport.X - 18)
    end

    if viewport.Y < 600 then
        height = math.max(430, viewport.Y - 36)
    end

    Main.Size = UDim2.fromOffset(width, height)
end

local cameraConnection
local function connectCamera()
    if cameraConnection then
        cameraConnection:Disconnect()
    end

    local camera = Workspace.CurrentCamera
    if not camera then return end

    updateResponsiveSize()

    cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsiveSize)
end

connectCamera()
Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(connectCamera)

--============================================================
-- WINDOW DRAGGING
--============================================================
local dragging = false
local dragStart
local startPosition
local dragInput

Header.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then

        dragging = true
        dragStart = Vector2.new(input.Position.X, input.Position.Y)
        startPosition = Main.Position

        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then
                dragging = false
            end
        end)
    end
end)

Header.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseMovement
        or input.UserInputType == Enum.UserInputType.Touch then
        dragInput = input
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if not isAlive() then return end
    if dragging and input == dragInput then
        local pointerPosition = Vector2.new(input.Position.X, input.Position.Y)
        local delta = pointerPosition - dragStart

        Main.Position = UDim2.new(
            startPosition.X.Scale,
            startPosition.X.Offset + delta.X,
            startPosition.Y.Scale,
            startPosition.Y.Offset + delta.Y
        )
    end
end)

--============================================================
-- SHOW / HIDE + DRAGGABLE LAUNCHER
--============================================================
local visibilityTween
local launcherTween
local launcherDragging = false
local launcherDragStart = nil
local launcherStartPosition = nil
local launcherDragMoved = false
local launcherTouchInput = nil
local launcherPressTime = 0
local DRAG_THRESHOLD = 7

local function cancelTween(animation)
    if animation then
        pcall(function()
            animation:Cancel()
        end)
    end
end

local function getViewport()
    local camera = Workspace.CurrentCamera
    if camera then
        return camera.ViewportSize
    end
    return Vector2.new(1280, 720)
end

local function clampLauncherPosition(position)
    local viewport = getViewport()
    local size = Launcher.AbsoluteSize
    local halfX = math.max(size.X * 0.5, 29)
    local halfY = math.max(size.Y * 0.5, 29)

    local x = clamp(position.X, halfX + 8, viewport.X - halfX - 8)
    local y = clamp(position.Y, halfY + 8, viewport.Y - halfY - 8)

    return Vector2.new(x, y)
end

local function setLauncherPosition(position, save)
    position = clampLauncherPosition(position)
    Launcher.AnchorPoint = Vector2.new(0.5, 0.5)
    Launcher.Position = UDim2.fromOffset(position.X, position.Y)

    if save then
        State.launcherPosition = {
            x = position.X,
            y = position.Y,
        }
        persist()
    end
end

local function getLauncherCenter()
    return Launcher.AbsolutePosition + (Launcher.AbsoluteSize * 0.5)
end

local function restoreLauncherPosition()
    local saved = State.launcherPosition

    if type(saved) == "table"
        and type(saved.x) == "number"
        and type(saved.y) == "number" then
        setLauncherPosition(Vector2.new(saved.x, saved.y), false)
    else
        local viewport = getViewport()
        setLauncherPosition(Vector2.new(viewport.X - 42, viewport.Y - 42), false)
    end
end

local function animateLauncher(visible)
    cancelTween(launcherTween)

    if visible then
        Launcher.Visible = true
        LauncherScale.Scale = 0.76
        Launcher.TextTransparency = 0.35
        LauncherHint.TextTransparency = 0.55

        launcherTween = playTween(
            LauncherScale,
            CONFIG.Animation.Slow,
            {Scale = 1},
            Enum.EasingStyle.Back
        )

        playTween(Launcher, CONFIG.Animation.Normal, {
            TextTransparency = 0,
        })

        playTween(LauncherHint, CONFIG.Animation.Normal, {
            TextTransparency = 0.08,
        })
    else
        launcherTween = playTween(
            LauncherScale,
            CONFIG.Animation.Fast,
            {Scale = 0.76},
            Enum.EasingStyle.Quart
        )

        playTween(Launcher, CONFIG.Animation.Fast, {
            TextTransparency = 1,
        })

        playTween(LauncherHint, CONFIG.Animation.Fast, {
            TextTransparency = 1,
        })

        if launcherTween then
            launcherTween.Completed:Once(function()
                if not State.uiVisible then
                    Launcher.Visible = false
                end
            end)
        end
    end
end

local function setVisible(visible)
    visible = visible == true

    if State.uiVisible == visible then
        if not visible then
            animateLauncher(true)
        end
        return
    end

    State.uiVisible = visible
    cancelTween(visibilityTween)

    if visible then
        Main.Visible = true
        Launcher.Visible = false
        MainScale.Scale = math.max(0.90, State.uiScale - 0.07)

        visibilityTween = playTween(
            MainScale,
            CONFIG.Animation.Slow,
            {Scale = State.uiScale},
            Enum.EasingStyle.Back
        )
    else
        visibilityTween = playTween(
            MainScale,
            CONFIG.Animation.Normal,
            {Scale = math.max(0.84, State.uiScale - 0.10)},
            Enum.EasingStyle.Quart
        )

        if visibilityTween then
            visibilityTween.Completed:Once(function()
                if not State.uiVisible then
                    Main.Visible = false
                    animateLauncher(true)
                end
            end)
        else
            Main.Visible = false
            animateLauncher(true)
        end
    end

    persist()
end

--============================================================
-- LAUNCHER DRAGGING
--============================================================
-- The old implementation chained InputChanged through the button.
-- This version tracks the global pointer, so the launcher can move
-- freely left/right/up/down and works much better on touch too.
Launcher.InputBegan:Connect(function(input)
    if not isAlive() then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then
        return
    end

    launcherDragging = true
    launcherDragMoved = false
    launcherDragStart = Vector2.new(input.Position.X, input.Position.Y)
    launcherStartPosition = getLauncherCenter()
    launcherTouchInput = input.UserInputType == Enum.UserInputType.Touch and input or nil
    launcherPressTime = os.clock()

    input.Changed:Connect(function()
        if input.UserInputState == Enum.UserInputState.End then
            local wasDragged = launcherDragMoved

            launcherDragging = false
            launcherTouchInput = nil

            -- A real drag never opens the menu accidentally.
            if not wasDragged and os.clock() - launcherPressTime < 0.55 then
                setVisible(true)
                addLog("UI opened from launcher")
                renderLogs()
            elseif wasDragged then
                setLauncherPosition(getLauncherCenter(), true)
            end
        end
    end)
end)

UserInputService.InputChanged:Connect(function(input)
    if not isAlive() or not launcherDragging then
        return
    end

    local validPointer

    if launcherTouchInput then
        validPointer = input == launcherTouchInput
    else
        validPointer = input.UserInputType == Enum.UserInputType.MouseMovement
    end

    if not validPointer then
        return
    end

    local pointerPosition = Vector2.new(input.Position.X, input.Position.Y)
    local delta = pointerPosition - launcherDragStart

    if not launcherDragMoved
        and (math.abs(delta.X) >= DRAG_THRESHOLD or math.abs(delta.Y) >= DRAG_THRESHOLD) then
        launcherDragMoved = true
    end

    if launcherDragMoved then
        setLauncherPosition(launcherStartPosition + delta, false)
    end
end)

local function keepLauncherOnScreen()
    task.defer(function()
        setLauncherPosition(getLauncherCenter(), false)
    end)
end

Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(keepLauncherOnScreen)

task.defer(function()
    restoreLauncherPosition()
end)

--============================================================
-- CLOSE BUTTON
--============================================================
CloseButton.MouseButton1Click:Connect(function()
    if not isAlive() then return end
    setVisible(false)
    addLog("UI hidden from close button")
    renderLogs()
end)

--============================================================
-- CTRL HOTKEY
--============================================================
-- Either Ctrl key toggles the UI. Press once = open, press again = close.
UserInputService.InputBegan:Connect(function(input)
    if not isAlive() then return end
    if input.KeyCode ~= Enum.KeyCode.LeftControl
        and input.KeyCode ~= Enum.KeyCode.RightControl then
        return
    end

    setVisible(not State.uiVisible)
    addLog(State.uiVisible and "UI opened with Ctrl" or "UI hidden with Ctrl")
    renderLogs()
end)

--============================================================
-- INTERACT PROMPT TRACKING
--============================================================
-- IMPORTANT: all world scanning is throttled/yielding so the LocalPlayer
-- never gets stuck during startup or while moving around. Nothing here
-- changes WalkSpeed, JumpPower, PlatformStand, AutoRotate, or Anchored.
local prompts = {}
local humanoidRootPart = nil
local holding = false
local promptScannerAlive = true
local PROMPT_SCAN_INTERVAL = 0.12
local PROMPT_BATCH_SIZE = 100

local function trackPrompt(object)
    if object and object:IsA("ProximityPrompt") then
        prompts[object] = true
    end
end

local function untrackPrompt(object)
    prompts[object] = nil
end

-- Register future prompts immediately; this is cheap and non-blocking.
Workspace.DescendantAdded:Connect(trackPrompt)
Workspace.DescendantRemoving:Connect(untrackPrompt)

-- Initial world scan is deliberately split into batches.
task.spawn(function()
    local descendants = Workspace:GetDescendants()

    for index, object in ipairs(descendants) do
        if not promptScannerAlive or terminated then
            break
        end

        trackPrompt(object)

        if index % PROMPT_BATCH_SIZE == 0 then
            task.wait()
        end
    end
end)

local function getPromptPosition(prompt)
    local parent = prompt.Parent
    if not parent then return nil end

    if parent:IsA("BasePart") then
        return parent.Position
    elseif parent:IsA("Attachment") then
        return parent.WorldPosition
    elseif parent:IsA("Model") then
        local ok, pivot = pcall(function()
            return parent:GetPivot()
        end)

        if ok and pivot then
            return pivot.Position
        end
    end

    return nil
end

local function findNearestPrompt()
    if not humanoidRootPart then return nil end

    local nearest
    local nearestDistance = State.interactRange
    local checked = 0

    for prompt in pairs(prompts) do
        checked += 1

        if prompt.Parent and prompt.Enabled then
            local position = getPromptPosition(prompt)

            if position then
                local distance = (position - humanoidRootPart.Position).Magnitude
                local allowed = math.min(State.interactRange, prompt.MaxActivationDistance)

                if distance <= allowed and distance < nearestDistance then
                    nearest = prompt
                    nearestDistance = distance
                end
            end
        else
            prompts[prompt] = nil
        end

        -- A large prompt table should never monopolize a render frame.
        if checked % PROMPT_BATCH_SIZE == 0 then
            task.wait()
            if terminated then
                return nil
            end
        end
    end

    return nearest
end

local function triggerInteract(prompt)
    if not isAlive() or not prompt then
        return false
    end

    if not prompt.Parent or not prompt.Enabled then
        return false
    end

    -- Start the real Roblox ProximityPrompt hold so the prompt UI
    -- visibly shows the hold progress just like pressing the key/button.
    local ok = pcall(function()
        prompt:InputHoldBegin()
    end)

    return ok
end

local function beginInteract(prompt)
    if not isAlive() or holding or not prompt then
        return
    end

    if not prompt.Parent or not prompt.Enabled then
        return
    end

    holding = true

    local actionName = prompt.ActionText ~= "" and prompt.ActionText or "Interact"
    local baseHoldDuration = math.max(prompt.HoldDuration or 0, 0)
    local fastMode = State.holdingSpeed == "Fast"
    local originalHoldDuration = prompt.HoldDuration
    local holdDuration = baseHoldDuration
    local changedHoldDuration = false

    PromptStatus.Text = (fastMode and "Fast holding " or "Holding ") .. actionName .. "..."

    -- A ProximityPrompt owns its own progress timer. Simply waiting for half
    -- of HoldDuration and releasing it causes the exact bug where the bar
    -- reaches the middle and starts over. In Fast mode, temporarily shorten
    -- the prompt's actual HoldDuration instead of releasing early.
    if fastMode and baseHoldDuration > 0 then
        local ok = pcall(function()
            prompt.HoldDuration = 0.05
            changedHoldDuration = math.abs(prompt.HoldDuration - 0.05) < 0.001
        end)

        if changedHoldDuration then
            holdDuration = 0.08
        else
            -- If the game prevents the property from being changed, use the
            -- real duration rather than performing a broken half-hold.
            holdDuration = baseHoldDuration
        end
    end

    local started = triggerInteract(prompt)

    if not started then
        if changedHoldDuration then
            pcall(function() prompt.HoldDuration = originalHoldDuration end)
        end
        holding = false
        PromptStatus.Text = "Unable to interact."
        return
    end

    if holdDuration > 0 then
        local startTime = os.clock()

        while isAlive()
            and prompt.Parent
            and prompt.Enabled
            and os.clock() - startTime < holdDuration do
            task.wait()
        end
    else
        task.wait()
    end

    -- Always release the hold cleanly.
    if prompt.Parent then
        pcall(function()
            prompt:InputHoldEnd()
        end)
    end

    -- Restore the game's original HoldDuration immediately after the prompt
    -- has completed, so we don't leave the prompt altered.
    if changedHoldDuration and prompt.Parent then
        pcall(function()
            prompt.HoldDuration = originalHoldDuration
        end)
    end

    if isAlive() then
        addLog("Interacted: " .. actionName)
        renderLogs()
        PromptStatus.Text = State.autoInteract and "Scanning..." or "Auto interact disabled."
    end

    holding = false
end

-- Throttled scanner instead of Heartbeat. This keeps movement/input responsive.
task.spawn(function()
    while isAlive() and Gui.Parent do
        task.wait(PROMPT_SCAN_INTERVAL)

        if isAlive() and State.autoInteract and not holding and humanoidRootPart then
            local nearest = findNearestPrompt()
            if nearest then
                task.spawn(beginInteract, nearest)
            end
        end
    end
end)

--============================================================
-- CHARACTER HANDLING
--============================================================
local function onCharacterAdded(character)
    humanoidRootPart = character:FindFirstChild("HumanoidRootPart")

    if humanoidRootPart then
        return
    end

    -- Never block script startup waiting for the character.
    task.spawn(function()
        local connection
        connection = character.ChildAdded:Connect(function(child)
            if child:IsA("BasePart") and child.Name == "HumanoidRootPart" then
                humanoidRootPart = child
                if connection then
                    connection:Disconnect()
                end
            end
        end)

        task.delay(10, function()
            if connection then
                connection:Disconnect()
            end
        end)
    end)
end

Player.CharacterAdded:Connect(onCharacterAdded)

if Player.Character then
    onCharacterAdded(Player.Character)
end

--============================================================
-- BUTTON MICRO-ANIMATIONS
--============================================================
local function addPressScale(button)
    local scale = Instance.new("UIScale")
    scale.Scale = 1
    scale.Parent = button

    button.MouseButton1Down:Connect(function()
        playTween(scale, 0.06, {Scale = 0.96})
    end)

    button.MouseButton1Up:Connect(function()
        playTween(scale, CONFIG.Animation.Fast, {Scale = 1})
    end)

    button.MouseLeave:Connect(function()
        playTween(scale, CONFIG.Animation.Fast, {Scale = 1})
    end)
end

for _, button in ipairs({
    CloseButton,
    Launcher,
    CopyButton,
    ClearButton,
    RedeemButton,
    MinusButton,
    PlusButton,
    InteractToggle,
    HoldingSpeedButton,
    RangeMinus,
    RangePlus,
    ScaleMinus,
    ScalePlus,
}) do
    addPressScale(button)
end

--============================================================
-- INITIALIZE
--============================================================
updateCodeDisplay()
updateRange()
setInteractVisual()
setHoldingSpeedVisual()
applyScale()

restoreLauncherPosition()

-- Respect the saved visibility state instead of always forcing the menu open.
if State.uiVisible then
    Main.Visible = true
    Launcher.Visible = false
    MainScale.Scale = State.uiScale
else
    Main.Visible = false
    Launcher.Visible = true
    LauncherScale.Scale = 1
    Launcher.TextTransparency = 0
    LauncherHint.TextTransparency = 0.08
end

--============================================================
-- AMBIENT UI MOTION
--============================================================
-- Subtle motion only: the UI feels alive without consuming a render
-- frame with heavy effects or touching the character/controller.
task.spawn(function()
    local gradient = MainSheen:FindFirstChildOfClass("UIGradient")
    local pulse = 0

    while isAlive() and Gui.Parent do
        task.wait(0.035)
        if not isAlive() then break end

        pulse += 0.035
        if gradient then
            gradient.Rotation = (135 + math.sin(pulse * 0.7) * 18) % 360
        end

        local glow = 0.935 + (math.sin(pulse * 1.25) + 1) * 0.012
        CornerGlow.BackgroundTransparency = clamp(glow, 0.92, 0.96)
    end
end)

addLog("Yo Redeemer initialized")
renderLogs()

setStatus("Ready.", "success")

-- Save periodically, but only the lightweight settings state.
task.spawn(function()
    while isAlive() and Gui.Parent do
        task.wait(8)
        if isAlive() and Gui.Parent then
            persist()
        end
    end
end)

--============================================================
-- YO REDEEMER END
--============================================================

