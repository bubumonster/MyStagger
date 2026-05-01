local ADDON_NAME = ...

local _, playerClass = UnitClass("player")
if playerClass ~= "MONK" then
    return
end

local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)

local BREWMASTER_SPEC_INDEX = 1
local BOB_AND_WEAVE_SPELL_ID = 280515

local UPDATE_INTERVAL_ACTIVE = 0.10
local UPDATE_INTERVAL_IDLE = 0.35

local active = false
local elapsed = 0
local updateInterval = UPDATE_INTERVAL_IDLE
local staggerDuration = 10

local wasAboveThreshold = false
local lastSoundTime = 0
local testDisplayActive = false

local currentStyle = nil
local lastDisplayedValue = nil

local options
local settingsCategory

local defaults = {
    dbVersion = 3,

    x = 0,
    y = -200,

    fontSize = 18,
    alertFontSize = 24,

    alertThreshold = 2.5,

    soundEnabled = true,
    soundCooldown = 3.0,

    sharedMediaSound = "MyStagger Pling",
}

local db

local function InitDB()
    MyStaggerData = MyStaggerData or {}

    if (MyStaggerData.dbVersion or 0) < 3 then
        MyStaggerData.soundMode = nil
        MyStaggerData.soundKit = nil
        MyStaggerData.soundFile = nil
        MyStaggerData.customSoundFile = nil
        MyStaggerData.dbVersion = 3
    end

    for k, v in pairs(defaults) do
        if MyStaggerData[k] == nil then
            MyStaggerData[k] = v
        end
    end

    db = MyStaggerData
end

local frame = CreateFrame("Frame", ADDON_NAME .. "Frame", UIParent)
frame:SetSize(260, 32)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:EnableMouse(false)
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
    displayText:SetFormattedText("%.2f%%/s", rounded)
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

local function GetSharedMediaSoundPath()
    if not LSM or not db.sharedMediaSound then
        return nil
    end

    return LSM:Fetch("sound", db.sharedMediaSound, true)
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

    local soundFile = GetSharedMediaSoundPath()

    if soundFile then
        local ok = PlaySoundFile(soundFile, "Master")

        if ok then
            return
        end
    end

    PlaySound(SOUNDKIT.RAID_WARNING, "Master")
end

local function IsBrewmaster()
    return GetSpecialization() == BREWMASTER_SPEC_INDEX
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
    updateInterval = UPDATE_INTERVAL_ACTIVE
    ShowValue(db.alertThreshold + 0.25)
end

local function Update()
    if testDisplayActive then
        ShowTestValue()
        return
    end

    local stagger = UnitStagger("player") or 0
    local maxHP = UnitHealthMax("player") or 0

    if stagger <= 0 or maxHP <= 0 then
        updateInterval = UPDATE_INTERVAL_IDLE
        HideDisplay()
        return
    end

    updateInterval = UPDATE_INTERVAL_ACTIVE

    local totalPercent = stagger / maxHP * 100
    local perSecondPercent = totalPercent / staggerDuration

    ShowValue(perSecondPercent)
end

local function OnUpdate(_, delta)
    elapsed = elapsed + delta

    if elapsed >= updateInterval then
        elapsed = 0
        Update()
    end
end

local function EnableBrewmasterMode()
    if active then
        return
    end

    active = true
    elapsed = 0
    updateInterval = UPDATE_INTERVAL_IDLE

    ResetAlertState()
    ResetTextCache()

    UpdateTalentState()
    frame:SetScript("OnUpdate", OnUpdate)
    Update()
end

local function DisableBrewmasterMode()
    if not active then
        return
    end

    active = false
    elapsed = 0
    updateInterval = UPDATE_INTERVAL_IDLE

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

local function SetSharedMediaSound(soundName)
    db.sharedMediaSound = soundName
    ResetAlertState()
end

local function SetTestDisplayEnabled(enabled)
    testDisplayActive = enabled and true or false
    frame:EnableMouse(testDisplayActive)

    ResetAlertState()
    ResetTextCache()

    if testDisplayActive then
        frame:SetScript("OnUpdate", OnUpdate)
        elapsed = 0
        updateInterval = UPDATE_INTERVAL_ACTIVE
        Update()
    else
        if not active then
            frame:SetScript("OnUpdate", nil)
            HideDisplay()
        else
            Update()
        end
    end
end

local function ToggleTestDisplay()
    SetTestDisplayEnabled(not testDisplayActive)
end

local function ResetPosition()
    SetPosition(defaults.x, defaults.y)
end

frame:SetScript("OnDragStart", function(self)
    if testDisplayActive then
        self:StartMoving()
    end
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

local function GetSharedMediaSoundList()
    if not LSM then
        return nil
    end

    local sounds = LSM:List("sound")
    if not sounds then
        return nil
    end

    table.sort(sounds)
    return sounds
end

local function CreateOptionsPanel()
    local panel = CreateFrame("Frame")
    panel.name = "MyStagger"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("MyStagger")

    local sizeEdit = MakeNumericEditBox(panel, "Normal Font Size", 16, -64, 80, 10, 36, function()
        return db.fontSize
    end, SetFontSize)

    local alertSizeEdit = MakeNumericEditBox(panel, "Alert Font Size", 140, -64, 80, 10, 48, function()
        return db.alertFontSize
    end, SetAlertFontSize)

    local xEdit = MakeNumericEditBox(panel, "X Position", 16, -130, 80, -2000, 2000, function()
        return db.x
    end, SetXPosition)

    local yEdit = MakeNumericEditBox(panel, "Y Position", 140, -130, 80, -2000, 2000, function()
        return db.y
    end, SetYPosition)

    local thresholdLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    thresholdLabel:SetPoint("TOPLEFT", 16, -200)
    thresholdLabel:SetText("Alert Threshold: HP% per second")

    local thresholdSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
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

        if rounded ~= db.alertThreshold then
            SetAlertThreshold(rounded)
        end

        thresholdSlider.Text:SetFormattedText("%.1f%%/s", db.alertThreshold)
    end)

    local soundBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    soundBtn:SetSize(140, 24)
    soundBtn:SetPoint("TOPLEFT", thresholdSlider, "BOTTOMLEFT", 0, -32)

    local soundTestBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    soundTestBtn:SetSize(120, 24)
    soundTestBtn:SetPoint("LEFT", soundBtn, "RIGHT", 12, 0)
    soundTestBtn:SetText("Test Sound")

    local soundLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    soundLabel:SetPoint("TOPLEFT", soundBtn, "BOTTOMLEFT", 0, -18)
    soundLabel:SetText("SharedMedia Sound")

    local soundDropdown = CreateFrame("Frame", nil, panel, "UIDropDownMenuTemplate")
    soundDropdown:SetPoint("TOPLEFT", soundLabel, "BOTTOMLEFT", -16, -6)

    local testBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    testBtn:SetSize(140, 24)
    testBtn:SetPoint("TOPLEFT", soundDropdown, "BOTTOMLEFT", 16, -16)

    local resetBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    resetBtn:SetSize(140, 24)
    resetBtn:SetPoint("LEFT", testBtn, "RIGHT", 12, 0)
    resetBtn:SetText("Reset Position")

    local helpText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    helpText:SetPoint("TOPLEFT", testBtn, "BOTTOMLEFT", 0, -24)
    helpText:SetText("<50% threshold = white, 50-100% = orange, above threshold = red")

    local function UpdateSoundButtonText()
        soundBtn:SetText(db.soundEnabled and "Sound: On" or "Sound: Off")
    end

    local function UpdateTestButtonText()
        testBtn:SetText(testDisplayActive and "Test: On" or "Test: Off")
    end

    local function UpdateSoundDropdownText()
        if LSM then
            UIDropDownMenu_SetText(soundDropdown, db.sharedMediaSound or "Select sound")
        else
            UIDropDownMenu_SetText(soundDropdown, "Raid Warning fallback")
        end
    end

    local function InitializeSoundDropdown(_, level)
        local sounds = GetSharedMediaSoundList()

        if not sounds or #sounds == 0 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "SharedMedia unavailable"
            info.disabled = true
            UIDropDownMenu_AddButton(info, level)
            return
        end

        for _, soundName in ipairs(sounds) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = soundName
            info.checked = soundName == db.sharedMediaSound
            info.func = function()
                SetSharedMediaSound(soundName)
                UpdateSoundDropdownText()
            end

            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_SetWidth(soundDropdown, 220)
    UIDropDownMenu_Initialize(soundDropdown, InitializeSoundDropdown)
    UpdateSoundDropdownText()

    soundBtn:SetScript("OnClick", function()
        SetSoundEnabled(not db.soundEnabled)
        UpdateSoundButtonText()
    end)

    soundTestBtn:SetScript("OnClick", function()
        lastSoundTime = 0
        PlayAlertSound()
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

    panel:SetScript("OnShow", function()
        sizeEdit.Refresh()
        alertSizeEdit.Refresh()
        xEdit.Refresh()
        yEdit.Refresh()

        thresholdSlider:SetValue(db.alertThreshold)
        thresholdSlider.Text:SetFormattedText("%.1f%%/s", db.alertThreshold)

        UpdateSoundButtonText()
        UpdateSoundDropdownText()
        UpdateTestButtonText()
    end)

    return panel
end

local function EnsureOptionsPanel()
    if options then
        return
    end

    options = CreateOptionsPanel()

    if Settings and Settings.RegisterCanvasLayoutCategory then
        settingsCategory = Settings.RegisterCanvasLayoutCategory(options, options.name)
        Settings.RegisterAddOnCategory(settingsCategory)
    else
        InterfaceOptions_AddCategory(options)
    end
end

local function OpenOptionsPanel()
    EnsureOptionsPanel()

    if Settings and Settings.OpenToCategory and settingsCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
    elseif Settings and Settings.OpenToCategory then
        Settings.OpenToCategory("MyStagger")
    else
        InterfaceOptionsFrame_OpenToCategory(options)
        InterfaceOptionsFrame_OpenToCategory(options)
    end
end

local function RegisterSlashCommand()
    SLASH_MYSTAGGER1 = "/mystagger"

    SlashCmdList.MYSTAGGER = function(msg)
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

        OpenOptionsPanel()
    end
end

frame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then
            return
        end

        InitDB()
        ApplySettings()
        RegisterSlashCommand()

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