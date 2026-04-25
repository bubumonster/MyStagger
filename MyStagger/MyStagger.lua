local ADDON_NAME = ...

local BREWMASTER_SPEC_INDEX = 1
local UPDATE_INTERVAL = 0.15

local STAGGER_DURATION = 10

local BOB_AND_WEAVE_SPELL_ID = 280515

local function HasBobAndWeave()
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        return C_SpellBook.IsSpellKnown(BOB_AND_WEAVE_SPELL_ID)
    end

    if IsPlayerSpell then
        return IsPlayerSpell(BOB_AND_WEAVE_SPELL_ID)
    end

    return false
end

local function UpdateTalentState()
    STAGGER_DURATION = HasBobAndWeave() and 15 or 10
end

local f = CreateFrame("Frame", ADDON_NAME .. "Frame", UIParent)
f:SetSize(260, 32)
f:SetPoint("CENTER", UIParent, "CENTER", 0, -200)
f:Hide()

local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
text:SetAllPoints()
text:SetJustifyH("CENTER")
text:SetJustifyV("MIDDLE")
text:SetTextColor(0.95, 0.82, 0.25)

local elapsed = 0

local function IsBrewmaster()
    local _, class = UnitClass("player")
    if class ~= "MONK" then
        return false
    end

    return GetSpecialization() == BREWMASTER_SPEC_INDEX
end

local function Update()
    if not IsBrewmaster() then
        f:Hide()
        return
    end

    local stagger = UnitStagger("player") or 0
    local maxHP = UnitHealthMax("player") or 0

    if stagger <= 0 or maxHP <= 0 then
        f:Hide()
        return
    end

    local totalPercent = stagger / maxHP * 100
    local perSecondPercent = totalPercent / STAGGER_DURATION

    text:SetText(string.format("%.2f%%/s", perSecondPercent))
    f:Show()
end

f:SetScript("OnUpdate", function(_, delta)
    elapsed = elapsed + delta
    if elapsed >= UPDATE_INTERVAL then
        elapsed = 0
        Update()
    end
end)

f:SetScript("OnEvent", function(_, event, unit)
    if event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED"
        or event == "PLAYER_ENTERING_WORLD" then

        UpdateTalentState()
    end

    if unit and unit ~= "player" then
        return
    end

    Update()
end)

f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("PLAYER_TALENT_UPDATE")
f:RegisterEvent("TRAIT_CONFIG_UPDATED")
f:RegisterEvent("UNIT_HEALTH")
f:RegisterEvent("UNIT_MAXHEALTH")
