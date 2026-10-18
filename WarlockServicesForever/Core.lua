local addon = CreateFrame("Frame")
local queue = WSFQueue.New()
local panel, status, queueText, summonButton, removeButton
local spellButtons = {}
local requestRows = {}
local completedRequests = {}
local selected = 1
local pendingRequests = {}
local healthstones = { 5512, 5511, 5509, 5510, 9421, 19004, 19005, 19006,
    19007, 19008, 19009, 19010, 19011, 19012, 19013, 22103, 22104, 22105 }
local spells = {
    { "Healthstone", 6201 }, { "Soulstone", 693 },
    { "Firestone", 6366 }, { "Spellstone", 2362 },
    { "Ritual of Souls", 29893 },
}
local function Say(message)
    DEFAULT_CHAT_FRAME:AddMessage("|cffb48affWSF:|r " .. message)
end
local function Locked()
    return InCombatLockdown and InCombatLockdown()
end
local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
    if GetSpellInfo then return GetSpellInfo(id) end
end
local function Count(id)
    if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id, false) end
    if GetItemCount then return GetItemCount(id) end
    return 0
end
local function OfferHealthstone()
    if Locked() then Say("Wait until combat ends."); return end
    if not TradeFrame or not TradeFrame:IsShown() then
        Say("Open a trade with the recipient first."); return
    end
    if GetCursorInfo and GetCursorInfo() then Say("Clear your cursor first."); return end
    if not GetTradePlayerItemInfo or not ClickTradeButton then
        Say("Place the healthstone in the trade window manually on this client."); return
    end
    local empty
    for slot = 1, 6 do
        if not GetTradePlayerItemInfo(slot) then empty = slot; break end
    end
    if not empty then Say("Your trade slots are full."); return end
    local api = C_Container
    local slots = api and api.GetContainerNumSlots or GetContainerNumSlots
    local itemID = api and api.GetContainerItemID or GetContainerItemID
    local pickup = api and api.PickupContainerItem or PickupContainerItem
    if not slots or not itemID or not pickup then
        Say("Place the healthstone in the trade window manually on this client."); return
    end
    for bag = 0, 4 do
        for slot = 1, slots(bag) do
            local id = itemID(bag, slot)
            for _, stone in ipairs(healthstones) do
                if id == stone then
                    pickup(bag, slot)
                    if GetCursorInfo and GetCursorInfo() == "item" then
                        ClickTradeButton(empty)
                        Say("Check the trade contents, then click Trade yourself.")
                    end
                    return
                end
            end
        end
    end
    Say("No healthstone found in your bags.")
end
local function Button(parent, label, x, y, width, secure)
    local b = CreateFrame("Button", nil, parent,
        secure and "SecureActionButtonTemplate,UIPanelButtonTemplate" or "UIPanelButtonTemplate")
    b:SetSize(width or 140, 24)
    b:SetPoint("TOPLEFT", x, y)
    b:SetText(label)
    if secure then b:RegisterForClicks("AnyUp", "AnyDown") end
    return b
end
local function SafeName(name)
    return name and not string.find(name, "[%s%c/;,%[%]\\]")
end
local function RemoveCompleted()
    local keep = queue.names[selected]
    for i = #queue.names, 1, -1 do
        if completedRequests[string.lower(queue.names[i])] then WSFQueue.Remove(queue, i) end
    end
    completedRequests = {}
    for i, name in ipairs(queue.names) do
        if name == keep then selected = i; break end
    end
end
local function RequestedName(name)
    if queue.lookup[string.lower(name)] then return name end
    -- Some clients omit the realm in combat logs. Resolve only an unambiguous
    -- short name so two players on different realms cannot remove each other.
    if string.find(name, "-", 1, true) then return end
    local match
    for _, candidate in ipairs(queue.names) do
        if string.lower(string.match(candidate, "^[^-]+")) == string.lower(name) then
            if match then return end
            match = candidate
        end
    end
    return match
end
local function Update()
    if not panel then return end
    local shards, stones = Count(6265), 0
    for _, id in ipairs(healthstones) do stones = stones + Count(id) end
    local color = shards < WarlockServicesForeverDB.shardTarget and "|cffff6666" or "|cff88ff88"
    status:SetText(color .. "Soul shards: " .. shards .. " / " .. WarlockServicesForeverDB.shardTarget ..
        "|r\nHealthstones: " .. stones)
    selected = math.max(1, math.min(selected, #queue.names))
    queueText:SetText("Summon requests: " .. #queue.names .. " (click a name to target)")
    if Locked() then return end
    local first = math.floor((selected - 1) / #requestRows) * #requestRows + 1
    for offset, row in ipairs(requestRows) do
        local index = first + offset - 1
        local name = queue.names[index]
        row.queueIndex = index
        row:SetAttribute("type", "macro")
        row:SetAttribute("macrotext", SafeName(name) and ("/targetexact " .. name) or "")
        row:SetText(name and ((index == selected and "> " or "") .. name) or "")
        row:SetEnabled(SafeName(name) and true or false)
        if name then row:Show() else row:Hide() end
    end
    local ritual = SpellName(698)
    local name = queue.names[selected]
    summonButton:SetAttribute("type", "macro")
    -- Names come from chat sender metadata, never from the message body.
    -- Restrict interpolation to player-name characters and optional realm suffix.
    local safe = SafeName(name)
    summonButton:SetAttribute("macrotext", safe and ritual and
        ("/targetexact " .. name .. "\n/cast " .. ritual) or "")
    summonButton:SetEnabled(safe and ritual ~= nil or false)
    for _, entry in ipairs(spellButtons) do
        local localized = SpellName(entry.id)
        entry.button:SetAttribute("type", "spell")
        entry.button:SetAttribute("spell", localized)
        entry.button:SetEnabled(localized ~= nil)
    end
end
local function CreatePanel()
    panel = CreateFrame("Frame", "WarlockServicesForeverPanel", UIParent,
        BackdropTemplateMixin and "BackdropTemplate" or nil)
    panel:SetSize(340, 615)
    panel:SetPoint("CENTER", UIParent, "CENTER", WarlockServicesForeverDB.x or 0,
        WarlockServicesForeverDB.y or 0)
    panel:SetClampedToScreen(true)
    panel:SetMovable(true)
    panel:EnableMouse(true)
    panel:RegisterForDrag("LeftButton")
    panel:SetScript("OnDragStart", function(self) if not Locked() then self:StartMoving() end end)
    panel:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local x, y = self:GetCenter()
        local px, py = UIParent:GetCenter()
        WarlockServicesForeverDB.x, WarlockServicesForeverDB.y = x - px, y - py
    end)
    if panel.SetBackdrop then
        panel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 16,
            insets = { left = 4, right = 4, top = 4, bottom = 4 } })
    end
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -14)
    title:SetText("Warlock Services Forever")
    status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("TOPLEFT", 16, -45)
    status:SetJustifyH("LEFT")
    for i, entry in ipairs(spells) do
        local b = Button(panel, entry[1], 16 + ((i - 1) % 2) * 155,
            -90 - math.floor((i - 1) / 2) * 29, 150, true)
        table.insert(spellButtons, { button = b, id = entry[2] })
    end
    Button(panel, "Offer healthstone", 171, -148, 150):SetScript("OnClick", OfferHealthstone)
    queueText = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    queueText:SetPoint("TOPLEFT", 16, -185)
    queueText:SetWidth(310)
    queueText:SetJustifyH("LEFT")
    for i = 1, 8 do
        local row = Button(panel, "", 16, -207 - (i - 1) * 28, 305, true)
        -- PostClick updates selection after the secure target action. Never invoke
        -- TargetUnit from an insecure handler or mutate protected attributes in combat.
        row:SetScript("PostClick", function(self)
            if Locked() then return end
            if queue.names[self.queueIndex] then selected = self.queueIndex; Update() end
        end)
        table.insert(requestRows, row)
    end
    summonButton = Button(panel, "Summon selected", 16, -448, 150, true)
    removeButton = Button(panel, "Remove selected", 171, -448, 150)
    removeButton:SetScript("OnClick", function()
        if Locked() then return end
        WSFQueue.Remove(queue, selected)
        Update()
    end)
    Button(panel, "Previous", 16, -478, 150):SetScript("OnClick", function()
        if Locked() then return end
        selected = math.max(1, selected - 1); Update()
    end)
    Button(panel, "Next", 171, -478, 150):SetScript("OnClick", function()
        if Locked() then return end
        selected = math.min(#queue.names, selected + 1); Update()
    end)
    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", 16, -520)
    hint:SetWidth(305)
    hint:SetJustifyH("LEFT")
    hint:SetText("Trade: open trade, offer stone, then accept.\nSummons need party members and a shard.\n/wsf toggles this panel. /wsf help lists options.")
    Update()
end
addon:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        if class ~= "WARLOCK" then return end
        if not GetSpellInfo and not C_Spell then
            Say("This client API is unsupported."); return
        end
        WarlockServicesForeverDB = WarlockServicesForeverDB or {}
        WarlockServicesForeverDB.shardTarget = WarlockServicesForeverDB.shardTarget or 10
        CreatePanel()
        for _, e in ipairs({ "BAG_UPDATE", "SPELLS_CHANGED", "PLAYER_REGEN_ENABLED",
            "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
            "CHAT_MSG_WHISPER", "COMBAT_LOG_EVENT_UNFILTERED" }) do self:RegisterEvent(e) end
        Say("Loaded. Type /wsf help for options.")
    elseif event == "COMBAT_LOG_EVENT_UNFILTERED" then
        -- Ritual of Summoning's initial cast/channel is not proof of a summon.
        -- Only the player's completed summon effect with an identified recipient
        -- may remove a request. 7720 is the vanilla Summon Player effect.
        local data
        if CombatLogGetCurrentEventInfo then data = { CombatLogGetCurrentEventInfo() }
        else data = { ... } end
        local subevent, sourceGUID, destName, spellID = data[2], data[4], data[9], data[12]
        if UnitGUID and sourceGUID == UnitGUID("player") and destName and
            ((subevent == "SPELL_SUMMON" and (spellID == 698 or spellID == 7720)) or
             (subevent == "SPELL_CAST_SUCCESS" and spellID == 7720)) then
            local name = RequestedName(destName)
            if name then
                completedRequests[string.lower(name)] = true
                if not Locked() then RemoveCompleted(); Update() end
            end
        end
    elseif string.sub(event, 1, 9) == "CHAT_MSG_" then
        local message, sender = ...
        -- Defer requests until combat ends to preserve the protected button target.
        if Locked() then
            table.insert(pendingRequests, { sender, message }); return
        end
        if WSFQueue.Add(queue, sender, message) then Update() end
    else
        if event == "PLAYER_REGEN_ENABLED" then
            RemoveCompleted()
            for _, request in ipairs(pendingRequests) do
                WSFQueue.Add(queue, request[1], request[2])
            end
            pendingRequests = {}
        end
        Update()
    end
end)
addon:RegisterEvent("PLAYER_LOGIN")
SLASH_WARLOCKSERVICESFOREVER1 = "/wsf"
SlashCmdList.WARLOCKSERVICESFOREVER = function(message)
    if not panel then Say("Log in on a warlock to use this addon."); return end
    local target = tonumber(string.match(message, "^shards%s+(%d+)$"))
    if target and target <= 100 then
        WarlockServicesForeverDB.shardTarget = target; Update()
    elseif message == "clear" then
        if Locked() then Say("Wait until combat ends."); return end
        queue = WSFQueue.New(); selected = 1; Update()
    elseif message == "version" then
        local v, b, _, interface = GetBuildInfo()
        Say("Client " .. tostring(v) .. " build " .. tostring(b) .. " interface " .. tostring(interface))
    elseif message == "help" then
        Say("/wsf: toggle; /wsf shards 10: shard target; /wsf clear: clear queue; /wsf version: client details.")
    elseif not Locked() then
        if panel:IsShown() then panel:Hide() else panel:Show() end
    end
end
