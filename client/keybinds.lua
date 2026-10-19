-- The keybind panel at the bottom of the screen at the power unit, while the arms are set and while an
-- admin places a lift, drawn by the NUI and taken from zyke_chopshop's. Besides the keys it carries a
-- title, a detail beside it and a warning under it. The panel is only sent when it changes, and the keys
-- are read every frame by the loop that shows it

---@class LiftKeybindItem
---@field label string
---@field key string | string[] @ Names of Z.keys, such as "LEFTMOUSE"
---@field hiddenKey? string | string[] @ Works without being shown, such as Backspace beside Escape
---@field func fun(key: string)

---@class LiftKeybindOptions
---@field title? string
---@field detail? string @ Shown beside the title, such as a heading
---@field warning? string @ Why what the panel is about can not be done

LiftKeybinds = {}

local keys = Z.keys.getAll()
-- Keys read from a control of their own: zyke_lib's S and D are the fly axes, which W and A move too
local controls = {S = 33, D = 35}
-- What a key is shown as on its cap, for those whose name is not it
local caps = {LEFTMOUSE = "LMB", RIGHTMOUSE = "RMB", SCROLLUP = "Scroll", SCROLLDOWN = "Scroll", LEFTSHIFT = "Shift", BACKSPACE = "Backspace", ESC = "Esc", SPACE = "Space"}
-- Items of the loop the panel belongs to, so another one hiding meanwhile leaves it up
---@type LiftKeybindItem[]?
local owner
---@type {items: {label: string, keys: string[]}[], title?: string, detail?: string, warning?: string}?
local panel
---@type string?
local panelJson
-- The panel the NUI shows now, nil while it is hidden
---@type string?
local shownJson
local watching = false
-- Milliseconds between checks of the pause menu while a panel is up
local pauseCheckMs = 100
-- Backspace and Escape, which open the pause menu too unless it is held back
local cancelControls = {[202] = true, [322] = true}
local pauseControls = {199, 200}

-- Sends the panel when what the NUI should show changed. The pause menu covers the game, so the panel
-- goes with it
local function sync()
    local wanted = owner and not IsPauseMenuActive() and panelJson or nil
    if (wanted == shownJson) then return end

    shownJson = wanted

    SendNUIMessage({event = "SetKeybinds", data = wanted and panel or {items = {}}})
end

local function watchPauseMenu()
    if (watching) then return end

    watching = true

    CreateThread(function()
        while (owner) do
            sync()

            Wait(pauseCheckMs)
        end

        watching = false
    end)
end

---@param key string | string[]
---@return string[] shown @ The caps of the keys, each once
local function getCaps(key)
    local shown, seen = {}, {}

    for _, name in ipairs(type(key) == "table" and key or {key}) do
        local cap = caps[name] or name

        if (not seen[cap]) then
            seen[cap] = true
            shown[#shown + 1] = cap
        end
    end

    return shown
end

-- Shows the panel with these items, or changes what it shows
---@param items LiftKeybindItem[]
---@param options? LiftKeybindOptions
function LiftKeybinds.show(items, options)
    local buttons = {}

    for i = 1, #items do
        buttons[i] = {label = items[i].label, keys = getCaps(items[i].key)}
    end

    owner = items
    panel = {items = buttons, title = options and options.title, detail = options and options.detail, warning = options and options.warning}
    panelJson = json.encode(panel)

    sync()
    watchPauseMenu()
end

-- Reads the keys of the items and keeps the game from acting on them. Run every frame the panel is up
---@param items LiftKeybindItem[]
function LiftKeybinds.handle(items)
    ---@param item LiftKeybindItem
    ---@param key string
    local function processKey(item, key)
        local control = controls[key] or (keys[key] and keys[key].keyCode)
        if (not control) then return end

        local isCancel = cancelControls[control]

        DisableControlAction(0, control, true)

        if (isCancel) then
            for i = 1, #pauseControls do
                DisableControlAction(0, pauseControls[i], true)
            end
        end

        if (not IsDisabledControlJustPressed(0, control)) then return end

        -- The cancel that just closed whatever showed the panel would open the pause menu a frame later
        if (isCancel) then LiftScene.holdPauseMenu() end

        item.func(key)
    end

    for i = 1, #items do
        local item = items[i]

        for _, path in ipairs({"key", "hiddenKey"}) do
            local value = item[path]

            for _, key in ipairs(type(value) == "table" and value or {value}) do
                processKey(item, key)
            end
        end
    end
end

-- Hides the panel while it still shows these items, so a loop that took over in the meantime keeps it
---@param items LiftKeybindItem[]
function LiftKeybinds.hide(items)
    if (owner ~= items) then return end

    owner = nil
    panel = nil
    panelJson = nil

    sync()
end

-- The page asks once it has loaded, so a panel shown before then, or across a restart of the page, is sent again
---@param cb fun(result: table)
RegisterNUICallback("KeybindsReady", function(_, cb)
    shownJson = nil

    sync()
    cb({})
end)