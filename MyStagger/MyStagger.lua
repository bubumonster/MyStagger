local ADDON_NAME = ...

local BREWMASTER_SPEC_INDEX = 1
local BOB_AND_WEAVE_SPELL_ID = 280515
local UPDATE_INTERVAL = 0.15

local active = false
local elapsed = 0
local STAGGER_DURATION = 10

local wasAboveThreshold = false
local lastSoundTime = 0
local testDisplayActive = false

local currentStyle = nil
local lastDisplayedValue = nil

local defaults = {
    dbVersion = 2,

    x = 0,
    y = -200,

    fontSize = 18,
    alertFontSize = 24,

    alertThreshold = 2.5,

    soundEnabled = true,
    soundCooldown = 3.0,

    soundMode = "custom",

    soundKit = SOUNDKIT.RAID_WARNING,
    customSoundFile = "Interface\\AddOns\\MyStagger\\Media\\Pling1.ogg",
}

local db

local function InitDB()
    MyStaggerData = MyStaggerData or {}

    for k, v in pairs(defaults) do
        if MyStaggerData[k] == nil then
            MyStaggerData[k] = v
        end
    end

    if (MyStaggerData.dbVersion or 0) < 2 then
        if type(MyStaggerData.soundFile) == "string" then
            MyStaggerData.soundMode = "custom"
            MyStaggerData.customSoundFile = MyStaggerData.soundFile
        elseif type(MyStaggerData.soundFile) == "number" then
            MyStaggerData.soundMode = "soundkit"
            MyStaggerData.soundKit = MyStaggerData.soundFile
        end

        MyStaggerData.soundFile = nil
        MyStaggerData.dbVersion = 2
    end

    db = MyStaggerData
end

local f = CreateFrame("Frame", ADDON_NAME .. "Frame", UIParent)
f:SetSize(260, 32)
f:SetMovable(true)
f:EnableMouse(true)
f:RegisterForDrag("LeftButton")
f:Hide()

local text = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
text:SetAllPoints()
text:SetJustifyH("CENTER")
text:SetJustifyV("MIDDLE")

local function ResetStyleCache()
    currentStyle = nil
end

local function ResetTextCache()
    lastDisplayedValue = nil
end

local function SetTextStyle(perSecondPercent)
    local newStyle

    if perSecondPercent >= db.alertThreshold then
        newStyle = "alert"
    elseif perSecondPercent >= db.alertThreshold * 0.5 then
        newStyle = "warning"
    else
        newStyle = "normal"
    end

    if newStyle == currentStyle then
        return
    end

    currentStyle = newStyle

    if newStyle == "alert" then
        text:SetFont(STANDARD_TEXT_FONT, db.alertFontSize, "OUTLINE")
        text:SetTextColor(1.0, 0.15, 0.15)
    elseif newStyle == "warning" then
        text:SetFont(STANDARD_TEXT_FONT, db.fontSize, "OUTLINE")
        text:SetTextColor(1.0, 0.55, 0.10)
    else
        text:SetFont(STANDARD_TEXT_FONT, db.fontSize, "OUTLINE")
        text:SetTextColor(1.0, 1.0, 1.0)
    end
end

local function SetDisplayText(perSecondPercent)
    local rounded = math.floor(perSecondPercent * 100 + 0.5) / 100

    if rounded == lastDisplayedValue then
        return
    end

    lastDisplayedValue = rounded
    text:SetText(string.format("%.2f%%/s", rounded))
end

local function ShowDisplay()
    if not f:IsShown() then
        f:Show()
    end
end

local function HideDisplay()
    if f:IsShown() then
        f:Hide()
    end

    wasAboveThreshold = false
    ResetTextCache()
end

local function ApplySettings()
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)

    ResetStyleCache()
    ResetTextCache()
    SetTextStyle(0)
end

local function PlayAlertSound()
    if not db.soundEnabled then
        return
    end

    local now = GetTime()
    if now - lastSoundTime < db.soundCooldown then
        return
    end

    lastSoundTime = now

    if db.soundMode == "soundkit" then
        PlaySound(db.soundKit or SOUNDKIT.RAID_WARNING, "Master")
        return
    end

    local ok = PlaySoundFile(db.customSoundFile, "Master")

    if not ok then
        print("MyStagger: Could not play custom sound:", db.customSoundFile)
    end
end

local function ResetAlertState()
    wasAboveThreshold = false
    lastSoundTime = 0
end

f:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)

f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()

    local centerX = self:GetLeft() + self:GetWidth() / 2
    local centerY = self:GetBottom() + self:GetHeight() / 2

    local uiCenterX = UIParent:GetWidth() / 2
    local uiCenterY = UIParent:GetHeight() / 2

    db.x = math.floor(centerX - uiCenterX + 0.5)
    db.y = math.floor(centerY - uiCenterY + 0.5)

    ApplySettings()
end)

local function IsBrewmaster()
    local _, class = UnitClass("player")
    return class == "MONK" and GetSpecialization() == BREWMASTER_SPEC_INDEX
end

local function HasBobAndWeave()
    if C_SpellBook and C_SpellBook.IsSpellKnown and Enum and Enum.SpellBookSpellBank then
        return C_SpellBook.IsSpellKnown(BOB_AND_WEAVE_SPELL_ID, Enum.SpellBookSpellBank.Player)
    end

    return false
end

local function UpdateTalentState()
    STAGGER_DURATION = HasBobAndWeave() and 15 or 10
end

local function ShowValue(perSecondPercent)
    local isAboveThreshold = perSecondPercent >= db.alertThreshold

    SetTextStyle(perSecondPercent)
    SetDisplayText(perSecondPercent)

    if isAboveThreshold and not wasAboveThreshold then
        PlayAlertSound()
    end

    wasAboveThreshold = isAboveThreshold
    ShowDisplay()
end

local function ShowTestValue()
    ShowValue(db.alertThreshold + 0.25)
end

local function Update()
    if not db then
        return
    end

    if testDisplayActive then
        ShowTestValue()
        return
    end

    if not active then
        HideDisplay()
        return
    end

    local stagger = UnitStagger("player") or 0
    local maxHP = UnitHealthMax("player") or 0

    if stagger <= 0 or maxHP <= 0 then
        HideDisplay()
        return
    end

    local totalPercent = stagger / maxHP * 100
    local perSecondPercent = totalPercent / STAGGER_DURATION

    ShowValue(perSecondPercent)
end

local function OnUpdate(_, delta)
    elapsed = elapsed + delta

    if elapsed >= UPDATE_INTERVAL then
        elapsed = elapsed - UPDATE_INTERVAL
        Update()
    end
end

local function EnableBrewmasterMode()
    if active then
        return
    end

    active = true
    elapsed = 0

    ResetAlertState()
    ResetTextCache()

    f:SetScript("OnUpdate", OnUpdate)

    UpdateTalentState()
    Update()
end

local function DisableBrewmasterMode()
    if not active then
        return
    end

    active = false
    elapsed = 0

    ResetAlertState()
    ResetTextCache()

    f:SetScript("OnUpdate", nil)

    if not testDisplayActive then
        HideDisplay()
    end
end

local function RefreshBrewmasterState()
    if IsBrewmaster() then
        EnableBrewmasterMode()
    else
        DisableBrewmasterMode()
    end
end

local options = CreateFrame("Frame")
options.name = "MyStagger"

local title = options:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("MyStagger")

local function MakeNumericEditBox(parent, labelText, x, y, width, minValue, maxValue, getValue, setValue)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    label:SetPoint("TOPLEFT", x, y)
    label:SetText(labelText)

    local editBox = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
    editBox:SetSize(width, 24)
    editBox:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
    editBox:SetAutoFocus(false)
    editBox:SetNumeric(false)

    local function Commit()
        local value = tonumber(editBox:GetText())

        if not value then
            editBox:SetText(tostring(getValue()))
            editBox:ClearFocus()
            return
        end

        value = math.floor(value + 0.5)

        if minValue and value < minValue then
            value = minValue
        end

        if maxValue and value > maxValue then
            value = maxValue
        end

        setValue(value)
        editBox:SetText(tostring(value))
        editBox:ClearFocus()
    end

    editBox:SetScript("OnEnterPressed", Commit)
    editBox:SetScript("OnEditFocusLost", Commit)

    editBox:SetScript("OnEscapePressed", function(self)
        self:SetText(tostring(getValue()))
        self:ClearFocus()
    end)

    editBox.Refresh = function()
        editBox:SetText(tostring(getValue()))
    end

    return editBox
end

local sizeEdit = MakeNumericEditBox(
    options,
    "Normal Font Size",
    16,
    -64,
    80,
    10,
    36,
    function()
        return db.fontSize
    end,
    function(value)
        db.fontSize = value
        ResetStyleCache()
        ResetTextCache()
        Update()
    end
)

local alertSizeEdit = MakeNumericEditBox(
    options,
    "Alert Font Size",
    140,
    -64,
    80,
    10,
    48,
    function()
        return db.alertFontSize
    end,
    function(value)
        db.alertFontSize = value
        ResetStyleCache()
        ResetTextCache()
        Update()
    end
)

local xEdit = MakeNumericEditBox(
    options,
    "X Position",
    16,
    -130,
    80,
    -2000,
    2000,
    function()
        return db.x
    end,
    function(value)
        db.x = value
        ApplySettings()
        Update()
    end
)

local yEdit = MakeNumericEditBox(
    options,
    "Y Position",
    140,
    -130,
    80,
    -2000,
    2000,
    function()
        return db.y
    end,
    function(value)
        db.y = value
        ApplySettings()
        Update()
    end
)

local thresholdLabel = options:CreateFontString(nil, "ARTWORK", "GameFontNormal")
thresholdLabel:SetPoint("TOPLEFT", 16, -200)
thresholdLabel:SetText("Alert Threshold: HP% per second")

local thresholdSlider = CreateFrame("Slider", nil, options, "OptionsSliderTemplate")
thresholdSlider:SetPoint("TOPLEFT", thresholdLabel, "BOTTOMLEFT", 0, -12)
thresholdSlider:SetMinMaxValues(0.5, 20)
thresholdSlider:SetValueStep(0.1)
thresholdSlider:SetObeyStepOnDrag(true)
thresholdSlider:SetWidth(220)
thresholdSlider.Low:SetText("0.5")
thresholdSlider.High:SetText("20")
thresholdSlider.Text:SetText("")

thresholdSlider:SetScript("OnValueChanged", function(_, value)
    db.alertThreshold = math.floor(value * 10 + 0.5) / 10
    thresholdSlider.Text:SetText(string.format("%.1f%%/s", db.alertThreshold))

    ResetAlertState()
    ResetStyleCache()
    ResetTextCache()
    Update()
end)

local soundBtn = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
soundBtn:SetSize(140, 24)
soundBtn:SetPoint("TOPLEFT", thresholdSlider, "BOTTOMLEFT", 0, -32)

local function UpdateSoundButtonText()
    soundBtn:SetText(db.soundEnabled and "Sound: On" or "Sound: Off")
end

soundBtn:SetScript("OnClick", function()
    db.soundEnabled = not db.soundEnabled
    ResetAlertState()
    UpdateSoundButtonText()
end)

local soundTestBtn = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
soundTestBtn:SetSize(120, 24)
soundTestBtn:SetPoint("LEFT", soundBtn, "RIGHT", 12, 0)
soundTestBtn:SetText("Test Sound")

soundTestBtn:SetScript("OnClick", function()
    lastSoundTime = 0
    PlayAlertSound()
end)

local soundModeBtn = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
soundModeBtn:SetSize(180, 24)
soundModeBtn:SetPoint("TOPLEFT", soundBtn, "BOTTOMLEFT", 0, -12)

local function UpdateSoundModeButtonText()
    if db.soundMode == "soundkit" then
        soundModeBtn:SetText("Sound Type: Raid Warning")
    else
        soundModeBtn:SetText("Sound Type: Custom")
    end
end

soundModeBtn:SetScript("OnClick", function()
    if db.soundMode == "soundkit" then
        db.soundMode = "custom"
    else
        db.soundMode = "soundkit"
    end

    ResetAlertState()
    UpdateSoundModeButtonText()
end)

local testBtn = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
testBtn:SetSize(140, 24)
testBtn:SetPoint("TOPLEFT", soundModeBtn, "BOTTOMLEFT", 0, -16)

local function UpdateTestButtonText()
    testBtn:SetText(testDisplayActive and "Test: On" or "Test: Off")
end

testBtn:SetScript("OnClick", function()
    testDisplayActive = not testDisplayActive

    ResetAlertState()
    ResetTextCache()
    UpdateTestButtonText()
    Update()
end)

local resetBtn = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
resetBtn:SetSize(140, 24)
resetBtn:SetPoint("LEFT", testBtn, "RIGHT", 12, 0)
resetBtn:SetText("Reset Position")

resetBtn:SetScript("OnClick", function()
    db.x = defaults.x
    db.y = defaults.y

    xEdit.Refresh()
    yEdit.Refresh()

    ApplySettings()
    Update()
end)

local helpText = options:CreateFontString(nil, "ARTWORK", "GameFontNormal")
helpText:SetPoint("TOPLEFT", testBtn, "BOTTOMLEFT", 0, -24)
helpText:SetText("<50% threshold = white, 50-100% = orange, above threshold = red")

options:SetScript("OnShow", function()
    if not db then
        return
    end

    sizeEdit.Refresh()
    alertSizeEdit.Refresh()
    xEdit.Refresh()
    yEdit.Refresh()

    thresholdSlider:SetValue(db.alertThreshold)
    thresholdSlider.Text:SetText(string.format("%.1f%%/s", db.alertThreshold))

    UpdateSoundButtonText()
    UpdateSoundModeButtonText()
    UpdateTestButtonText()
end)

if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(options, options.name)
    Settings.RegisterAddOnCategory(category)
else
    InterfaceOptions_AddCategory(options)
end

SLASH_MYSTAGGER1 = "/mystagger"

SlashCmdList.MYSTAGGER = function(msg)
    if not db then
        return
    end

    msg = msg and msg:lower() or ""

    if msg == "test" then
        testDisplayActive = not testDisplayActive

        ResetAlertState()
        ResetTextCache()

        print("MyStagger test display: " .. (testDisplayActive and "on" or "off"))
        Update()
        return
    end

    if msg == "sound" then
        lastSoundTime = 0
        PlayAlertSound()
        return
    end

    if msg == "reset" then
        db.x = defaults.x
        db.y = defaults.y

        ApplySettings()
        Update()
        return
    end

    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory("MyStagger")
    else
        InterfaceOptionsFrame_OpenToCategory(options)
        InterfaceOptionsFrame_OpenToCategory(options)
    end
end

f:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then
            return
        end

        InitDB()
        ApplySettings()

        f:UnregisterEvent("ADDON_LOADED")
        return
    end

    if not db then
        return
    end

    if event == "PLAYER_ENTERING_WORLD" then
        ApplySettings()
        RefreshBrewmasterState()
        return
    end

    if event == "PLAYER_SPECIALIZATION_CHANGED"
        or event == "PLAYER_TALENT_UPDATE"
        or event == "TRAIT_CONFIG_UPDATED" then

        RefreshBrewmasterState()

        if active then
            UpdateTalentState()
            Update()
        end
    end
end)

f:RegisterEvent("ADDON_LOADED")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
f:RegisterEvent("PLAYER_TALENT_UPDATE")
f:RegisterEvent("TRAIT_CONFIG_UPDATED")