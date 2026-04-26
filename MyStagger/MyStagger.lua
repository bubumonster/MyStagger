local ADDON_NAME = ...

local BREWMASTER_SPEC_INDEX = 1
local BOB_AND_WEAVE_SPELL_ID = 280515
local UPDATE_INTERVAL = 0.15

local active = false
local elapsed = 0
local staggerDuration = 10

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

local frame = CreateFrame("Frame", ADDON_NAME .. "Frame", UIParent)
frame:SetSize(260, 32)
frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:Hide()

local displayText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
displayText:SetAllPoints()
displayText:SetJustifyH("CENTER")
displayText:SetJustifyV("MIDDLE")

local function ResetStyleCache()
    currentStyle = nil
end

local function ResetTextCache()
    lastDisplayedValue = nil
end

local function ResetAlertState()
    wasAboveThreshold = false
    lastSoundTime = 0
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
        displayText:SetFont(STANDARD_TEXT_FONT, db.alertFontSize, "OUTLINE")
        displayText:SetTextColor(1.0, 0.15, 0.15)
    elseif newStyle == "warning" then
        displayText:SetFont(STANDARD_TEXT_FONT, db.fontSize, "OUTLINE")
        displayText:SetTextColor(1.0, 0.55, 0.10)
    else
        displayText:SetFont(STANDARD_TEXT_FONT, db.fontSize, "OUTLINE")
        displayText:SetTextColor(1.0, 1.0, 1.0)
    end
end

local function SetDisplayText(perSecondPercent)
    local rounded = math.floor(perSecondPercent * 100 + 0.5) / 100

    if rounded == lastDisplayedValue then
        return
    end

    lastDisplayedValue = rounded
    displayText:SetText(string.format("%.2f%%/s", rounded))
end

local function ShowDisplay()
    if not frame:IsShown() then
        frame:Show()
    end
end

local function HideDisplay()
    if frame:IsShown() then
        frame:Hide()
    end

    wasAboveThreshold = false
    ResetTextCache()
end

local function ApplySettings()
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", db.x, db.y)

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
    staggerDuration = HasBobAndWeave() and 15 or 10
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
    local perSecondPercent = totalPercent / staggerDuration

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

    frame:SetScript("OnUpdate", OnUpdate)

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

    frame:SetScript("OnUpdate", nil)

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

local function SetFontSize(value)
    db.fontSize = value
    ResetStyleCache()
    ResetTextCache()
    Update()
end

local function SetAlertFontSize(value)
    db.alertFontSize = value
    ResetStyleCache()
    ResetTextCache()
    Update()
end

local function SetPosition(x, y)
    db.x = x
    db.y = y

    ApplySettings()
    Update()
end

local function SetXPosition(value)
    SetPosition(value, db.y)
end

local function SetYPosition(value)
    SetPosition(db.x, value)
end

local function SetAlertThreshold(value)
    db.alertThreshold = value

    ResetAlertState()
    ResetStyleCache()
    ResetTextCache()
    Update()
end

local function SetSoundEnabled(value)
    db.soundEnabled = value
    ResetAlertState()
end

local function ToggleSoundMode()
    if db.soundMode == "soundkit" then
        db.soundMode = "custom"
    else
        db.soundMode = "soundkit"
    end

    ResetAlertState()
end

local function ToggleTestDisplay()
    testDisplayActive = not testDisplayActive

    ResetAlertState()
    ResetTextCache()
    Update()
end

local function ResetPosition()
    SetPosition(defaults.x, defaults.y)
end

-- Dragging
frame:SetScript("OnDragStart", function(self)
    self:StartMoving()
end)

frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()

    local centerX = self:GetLeft() + self:GetWidth() / 2
    local centerY = self:GetBottom() + self:GetHeight() / 2

    local uiCenterX = UIParent:GetWidth() / 2
    local uiCenterY = UIParent:GetHeight() / 2

    SetPosition(
        math.floor(centerX - uiCenterX + 0.5),
        math.floor(centerY - uiCenterY + 0.5)
    )
end)

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

local function CreateOptionsPanel()
    local options = CreateFrame("Frame")
    options.name = "MyStagger"

    local title = options:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("MyStagger")

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
        SetFontSize
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
        SetAlertFontSize
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
        SetXPosition
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
        SetYPosition
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
        local rounded = math.floor(value * 10 + 0.5) / 10

        SetAlertThreshold(rounded)
        thresholdSlider.Text:SetText(string.format("%.1f%%/s", db.alertThreshold))
    end)

    local soundBtn = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
    soundBtn:SetSize(140, 24)
    soundBtn:SetPoint("TOPLEFT", thresholdSlider, "BOTTOMLEFT", 0, -32)

    local soundTestBtn = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
    soundTestBtn:SetSize(120, 24)
    soundTestBtn:SetPoint("LEFT", soundBtn, "RIGHT", 12, 0)
    soundTestBtn:SetText("Test Sound")

    local soundModeBtn = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
    soundModeBtn:SetSize(180, 24)
    soundModeBtn:SetPoint("TOPLEFT", soundBtn, "BOTTOMLEFT", 0, -12)

    local testBtn = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
    testBtn:SetSize(140, 24)
    testBtn:SetPoint("TOPLEFT", soundModeBtn, "BOTTOMLEFT", 0, -16)

    local resetBtn = CreateFrame("Button", nil, options, "UIPanelButtonTemplate")
    resetBtn:SetSize(140, 24)
    resetBtn:SetPoint("LEFT", testBtn, "RIGHT", 12, 0)
    resetBtn:SetText("Reset Position")

    local helpText = options:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    helpText:SetPoint("TOPLEFT", testBtn, "BOTTOMLEFT", 0, -24)
    helpText:SetText("<50% threshold = white, 50-100% = orange, above threshold = red")

    local function UpdateSoundButtonText()
        soundBtn:SetText(db.soundEnabled and "Sound: On" or "Sound: Off")
    end

    local function UpdateSoundModeButtonText()
        if db.soundMode == "soundkit" then
            soundModeBtn:SetText("Sound Type: Raid Warning")
        else
            soundModeBtn:SetText("Sound Type: Custom")
        end
    end

    local function UpdateTestButtonText()
        testBtn:SetText(testDisplayActive and "Test: On" or "Test: Off")
    end

    soundBtn:SetScript("OnClick", function()
        SetSoundEnabled(not db.soundEnabled)
        UpdateSoundButtonText()
    end)

    soundTestBtn:SetScript("OnClick", function()
        lastSoundTime = 0
        PlayAlertSound()
    end)

    soundModeBtn:SetScript("OnClick", function()
        ToggleSoundMode()
        UpdateSoundModeButtonText()
    end)

    testBtn:SetScript("OnClick", function()
        ToggleTestDisplay()
        UpdateTestButtonText()
    end)

    resetBtn:SetScript("OnClick", function()
        ResetPosition()

        xEdit.Refresh()
        yEdit.Refresh()
    end)

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

    return options
end

local options = CreateOptionsPanel()

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
        ToggleTestDisplay()
        print("MyStagger test display: " .. (testDisplayActive and "on" or "off"))
        return
    end

    if msg == "sound" then
        lastSoundTime = 0
        PlayAlertSound()
        return
    end

    if msg == "reset" then
        ResetPosition()
        return
    end

    if Settings and Settings.OpenToCategory then
        Settings.OpenToCategory("MyStagger")
    else
        InterfaceOptionsFrame_OpenToCategory(options)
        InterfaceOptionsFrame_OpenToCategory(options)
    end
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then
            return
        end

        InitDB()
        ApplySettings()

        frame:UnregisterEvent("ADDON_LOADED")
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

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_ENTERING_WORLD")
frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
frame:RegisterEvent("PLAYER_TALENT_UPDATE")
frame:RegisterEvent("TRAIT_CONFIG_UPDATED")