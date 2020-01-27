local _, helpers = ...

Aptechka = CreateFrame("Frame","Aptechka",UIParent)
local Aptechka = Aptechka

Aptechka:SetScript("OnEvent", function(self, event, ...)
    self[event](self, event, ...)
end)

--- Compatibility with Classic
local isClassic = WOW_PROJECT_ID == WOW_PROJECT_CLASSIC

local UnitHasVehicleUI = UnitHasVehicleUI
local UnitInVehicle = UnitInVehicle
local UnitUsingVehicle = UnitUsingVehicle
local UnitGetIncomingHeals = UnitGetIncomingHeals
local UnitGetTotalAbsorbs = UnitGetTotalAbsorbs
local UnitGetTotalHealAbsorbs = UnitGetTotalHealAbsorbs
local UnitThreatSituation = UnitThreatSituation
local UnitGroupRolesAssigned = UnitGroupRolesAssigned
local UnitIsWarModePhased = UnitIsWarModePhased
local GetSpecialization = GetSpecialization
local GetSpecializationInfo = GetSpecializationInfo
local HasIncomingSummon = C_IncomingSummon and C_IncomingSummon.HasIncomingSummon

if isClassic then
    local dummyFalse = function() return false end
    local dummy0 = function() return 0 end
    local dummyNil = function() return nil end
    UnitHasVehicleUI = dummyFalse
    UnitInVehicle = dummyFalse
    UnitUsingVehicle = dummyFalse
    UnitGetIncomingHeals = dummy0
    UnitGetTotalAbsorbs = dummy0
    UnitGetTotalHealAbsorbs = dummy0
    UnitThreatSituation = dummyNil
    UnitIsWarModePhased = dummyFalse
    UnitGroupRolesAssigned = function(unit) if GetPartyAssignment("MAINTANK", unit) then return "TANK" end end
    GetSpecialization = function() return 1 end
    GetSpecializationInfo = function() return "DAMAGER" end
    HasIncomingSummon = dummyNil
end

-- AptechkaUserConfig = setmetatable({},{ __index = function(t,k) return AptechkaDefaultConfig[k] end })
-- When AptechkaUserConfig __empty__ field is accessed, it will return AptechkaDefaultConfig field

local AptechkaUnitInRange
local uir -- current range check function
local auras
local traceheals
local colors
local threshold = 0 --incoming heals
local ignoreplayer
local fgShowMissing

local config = AptechkaDefaultConfig
Aptechka.loadedAuras = {}
local loadedAuras = Aptechka.loadedAuras
local customBossAuras = helpers.customBossAuras
local default_blacklist = helpers.auraBlacklist
local blacklist
local importantTargetedCasts = helpers.importantTargetedCasts
local inCL = setmetatable({},{__index = function (t,k) return 0 end})
local buffer = {}
local loaded = {}
local auraUpdateEvents
local Roster = {}
local guidMap = {}
local group_headers = {}
local missingFlagSpells = {}
local anchors = {}
local skinAnchorsName
local BITMASK_DISPELLABLE = 0
local RosterUpdateOccured
local LastCastSentTime = 0
local LastCastTargetName

local AptechkaString = "|cffff7777Aptechka: |r"
local GetTime = GetTime
local UnitHealth = UnitHealth
local UnitHealthMax = UnitHealthMax
local UnitIsDeadOrGhost = UnitIsDeadOrGhost
local UnitPower = UnitPower
local UnitPowerMax = UnitPowerMax
local CombatLogGetCurrentEventInfo = CombatLogGetCurrentEventInfo
local UnitAura = UnitAura
local ForEachAura = helpers.ForEachAura
local UnitAffectingCombat = UnitAffectingCombat
local CUSTOM_CLASS_COLORS = CUSTOM_CLASS_COLORS
local RAID_CLASS_COLORS = RAID_CLASS_COLORS
local customColors
local table_wipe = table.wipe
local SetJob
local FrameSetJob
local DispelFilter

local pixelperfect = helpers.pixelperfect

local spellNameToID = helpers.spellNameToID
Aptechka.spellNameToID = spellNameToID
local bit_band = bit.band
local bit_bor = bit.bor
local IsInGroup = IsInGroup
local IsInRaid = IsInRaid
local pairs = pairs
local next = next
Aptechka.helpers = helpers
local utf8sub = helpers.utf8sub
local reverse = helpers.Reverse
local AptechkaDB
local LibSpellLocks
local LibAuraTypes
local LibTargetedCasts
local LibClassicDurations = LibStub("LibClassicDurations")
local tinsert = table.insert
local tsort = table.sort
local HealComm
local BuffProc
local DebuffProc, DebuffPostUpdate
local DispelTypeProc, DispelTypePostUpdate
local debuffLimit

Aptechka.L = setmetatable({}, {
    __index = function(t, k)
        -- print(string.format('L["%s"] = ""',k:gsub("\n","\\n")));
        return k
    end,
    __call = function(t,k) return t[k] end,
})

local defaultFont = "ClearFont"
do
    local locale = GetLocale()
    if locale == "zhTW" or locale == "zhCN" or locale == "koKR" then
        defaultFont = LibStub("LibSharedMedia-3.0").DefaultMedia["font"]
        -- "預設" - zhTW
        -- "默认" - zhCN
        -- "기본 글꼴" - koKR
    end
end

local defaults = {
    global = {
        disableBlizzardParty = true,
        hideBlizzardRaid = true,
        RMBClickthrough = false,
        sortUnitsByRole = false,
        showAFK = false,
        customBlacklist = {},
        useCombatLogHealthUpdates = false,
        disableTooltip = false,
        useDebuffOrdering = true, -- On always?

        profileSelection = {
            HEALER = {
                solo = "Default",
                party = "Default",
                smallRaid = "Default",
                mediumRaid = "Default",
                bigRaid = "Default",
            },
            DAMAGER = {
                solo = "Default",
                party = "Default",
                smallRaid = "Default",
                mediumRaid = "Default",
                bigRaid = "Default",
            },
        },
    },
    profile = {
        point = "CENTER",
        x = 0,
        y = 0,
        width = 55,
        height = 55,
        healthOrientation = "VERTICAL",
        unitGrowth = "RIGHT",
        groupGrowth = "TOP",
        unitGap = 7,
        groupGap = 7,
        showSolo = true,
        showParty = true,
        cropNamesLen = 7,
        showCasts = true,
        showAggro = true,
        petGroup = false,
        showRaidIcons = true,
        showDispels = false,
        healthTexture = "Gradient",
        powerTexture = "Gradient",

        scale = 1, --> into
        debuffSize = 13,
        debuffLimit = 4,
        debuffBossScale = 1.3,
        stackFontName = "ClearFont",
        stackFontSize = 12,
        nameFontName = defaultFont,
        nameFontSize = 12,
        nameFontOutline = "SHADOW",
        nameColorMultiplier = 1,
        fgShowMissing = true,
        fgColorMultiplier = 1,
        bgColorMultiplier = 0.2,
    },
}

local function SetupDefaults(t, defaults)
    if not defaults then return end
    for k,v in pairs(defaults) do
        if type(v) == "table" then
            if t[k] == nil then
                t[k] = CopyTable(v)
            elseif t[k] == false then
                t[k] = false --pass
            else
                SetupDefaults(t[k], v)
            end
        else
            if type(t) == "table" and t[k] == nil then t[k] = v end
            if t[k] == "__REMOVED__" then t[k] = nil end
        end
    end
end
Aptechka.SetupDefaults = SetupDefaults

local function RemoveDefaults(t, defaults)
    if not defaults then return end
    for k, v in pairs(defaults) do
        if type(t[k]) == 'table' and type(v) == 'table' then
            RemoveDefaults(t[k], v)
            if next(t[k]) == nil then
                t[k] = nil
            end
        elseif t[k] == v then
            t[k] = nil
        end
    end
    return t
end
Aptechka.RemoveDefaults = RemoveDefaults

local function RemoveDefaultsPreserve(t, defaults)
    if not defaults then return end
    for k, v in pairs(defaults) do
        if type(t[k]) == 'table' and type(v) == 'table' then
            RemoveDefaultsPreserve(t[k], v)
            if next(t[k]) == nil then
                t[k] = nil
            end
        elseif t[k] == nil and v ~= nil then
            t[k] = "__REMOVED__"
        elseif t[k] == v then
            t[k] = nil
        end
    end
    return t
end
Aptechka.RemoveDefaultsPreserve = RemoveDefaultsPreserve

local function MergeTable(t1, t2)
    if not t2 then return false end
    for k,v in pairs(t2) do
        if type(v) == "table" then
            if t1[k] == nil then
                t1[k] = CopyTable(v)
            else
                MergeTable(t1[k], v)
            end
        elseif v == "__REMOVED__" then
            t1[k] = nil
        else
            t1[k] = v
        end
    end
    return t1
end
Aptechka.MergeTable = MergeTable

Aptechka:RegisterEvent("PLAYER_LOGIN")
function Aptechka.PLAYER_LOGIN(self,event,arg1)
    Aptechka:UpdateRangeChecker()
    Aptechka:UpdateDispelBitmask()

    local uir2 = function(unit)
        if UnitIsDeadOrGhost(unit) or UnitIsEnemy(unit, "player") then --IsSpellInRange doesn't work with dead people
            return UnitInRange(unit)
        else
            return uir(unit)
        end
    end

    AptechkaUnitInRange = uir2

    AptechkaDB_Global = AptechkaDB_Global or {}
    AptechkaDB_Char = AptechkaDB_Char or {}
    self:DoMigrations(AptechkaDB_Global)
    self.db = LibStub("AceDB-3.0"):New("AptechkaDB_Global", defaults, "Default") -- Create a DB using defaults and using a shared default profile
    AptechkaDB = self.db

    self.db.RegisterCallback(self, "OnProfileChanged", "Reconfigure")
    self.db.RegisterCallback(self, "OnProfileCopied", "Reconfigure")
    self.db.RegisterCallback(self, "OnProfileReset", "Reconfigure")

    if AptechkaDB.forceShamanColor and not CUSTOM_CLASS_COLORS then
        customColors = {
            SHAMAN = {
                b=0.86666476726532,
                g=0.4392147064209,
                r=0,
            }
        }
    end

    Aptechka:UpdateUnprotectedUpvalues()

    -- CUSTOM_CLASS_COLORS is from phanx's ClassColors addons
    colors = setmetatable(customColors or {},{ __index = function(t,k) return (CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS)[k] end })

    blacklist = setmetatable({}, {
        __index = function(t,k)
            return AptechkaDB.global.customBlacklist[k] or default_blacklist[k]
        end,
    })

    AptechkaConfigCustom = AptechkaConfigCustom or {}
    AptechkaConfigMerged = CopyTable(AptechkaDefaultConfig)
    config = AptechkaConfigMerged
    config.DebuffTypes = config.DebuffTypes or {}
    config.DebuffDisplay = config.DebuffDisplay or {}
    config.auras = config.auras or {}
    config.traces = config.traces or {}
    auras = config.auras
    traceheals = config.traces

    local _, class = UnitClass("player")
    local categories = {"auras", "traces"}
    if not AptechkaConfigCustom[class] then AptechkaConfigCustom[class] = {} end

    local fixOldAuraFormat = function(customConfigPart)
        if not customConfigPart then return end
        for id, opts in pairs(customConfigPart) do
            if opts.id == nil then
                opts.id = id
            end
        end
    end

    local globalConfig = AptechkaConfigCustom["GLOBAL"]
    if globalConfig then
        fixOldAuraFormat(globalConfig.auras)
        fixOldAuraFormat(globalConfig.traces)
    end
    MergeTable(AptechkaConfigMerged, globalConfig)
    local classConfig = AptechkaConfigCustom[class]
    if classConfig then
        fixOldAuraFormat(classConfig.auras)
        fixOldAuraFormat(classConfig.traces)
    end
    MergeTable(AptechkaConfigMerged, classConfig)

    Aptechka.spellNameToID = helpers.spellNameToID

    Aptechka:UpdateSpellNameToIDTable()

    -- compiling a list of spells that should activate indicator when missing
    self:UpdateMissingAuraList()

    -- filling up ranks for auras
    local cloneIDs = {}
    local rankCategories = { "auras", "traces" }
    local tempTable = {}
    for _, category in ipairs(rankCategories) do
        table_wipe(tempTable)
        for spellID, opts in pairs(config[category]) do
            if not cloneIDs[spellID] and opts.clones then
                for i, additionalSpellID in ipairs(opts.clones) do
                    tempTable[additionalSpellID] = opts
                    cloneIDs[additionalSpellID] = true
                end
            end
        end
        for spellID, opts in pairs(tempTable) do
            config[category][spellID] = opts
        end
    end
    config.spellClones = cloneIDs

    for spellID, originalSpell in pairs(traceheals) do
        if not cloneIDs[spellID] and originalSpell.clones then
            for i, additionalSpellID in ipairs(originalSpell.clones) do
                traceheals[additionalSpellID] = originalSpell
                cloneIDs[additionalSpellID] = true
            end
        end
    end



    Aptechka.Roster = Roster

    if AptechkaDB.global.disableBlizzardParty then
        helpers.DisableBlizzParty()
    end
    if AptechkaDB.global.hideBlizzardRaid then
        -- disable Blizzard party & raid frame if our Raid Frames are loaded
        -- InterfaceOptionsFrameCategoriesButton11:SetScale(0.00001)
        -- InterfaceOptionsFrameCategoriesButton11:SetAlpha(0)
        -- raid
        local hider = CreateFrame("Frame")
        hider:Hide()
        if CompactRaidFrameManager and CompactUnitFrameProfiles then
            CompactRaidFrameManager:SetParent(hider)
            -- CompactRaidFrameManager:UnregisterAllEvents()
            CompactUnitFrameProfiles:UnregisterAllEvents()

            local disableCompactRaidFrameUnitButton = function(self)
                if not CanAccessObject(self) then return end
                -- for some reason CompactUnitFrame_OnLoad also gets called for nameplates, so ignoring that
                local frameName = self:GetName()
                if string.sub(frameName, 1, 16) == "CompactRaidFrame" then
                    -- print(frameName)
                    self:UnregisterAllEvents()
                end
            end

            for i=1,60 do
                local crf = _G["CompactRaidFrame"..i]
                if not crf then break end
                disableCompactRaidFrameUnitButton(crf)
            end
            hooksecurefunc("CompactUnitFrame_OnLoad", disableCompactRaidFrameUnitButton)
            hooksecurefunc("CompactUnitFrame_UpdateUnitEvents", disableCompactRaidFrameUnitButton)
        end
    end

    if config.enableIncomingHeals then
        HealComm = LibStub:GetLibrary("LibHealComm-4.0",true);
        local incomingHealIgnoreHots = true
        if HealComm then
            if incomingHealIgnoreHots then
                HealComm.AptechkaHealType = HealComm.CASTED_HEALS
            else
                HealComm.AptechkaHealType = HealComm.ALL_HEALS
                HealComm.RegisterCallback(self, "HealComm_HealUpdated", "HealUpdated");     -- hots
            end
            HealComm.RegisterCallback(self, "HealComm_HealStarted", "HealUpdated");
            HealComm.RegisterCallback(self, "HealComm_HealStopped", "HealUpdated");
        end
    end

    -- local tbind
    -- if config.TargetBinding == nil then tbind = "*type1"
    -- elseif config.TargetBinding == false then tbind = "__none__"
    -- else tbind = config.TargetBinding end

    -- local ccmacro = config.ClickCastingMacro or "__none__"

    -- local width = pixelperfect(AptechkaDB.profile.width or config.width)
    -- local height = pixelperfect(AptechkaDB.profile.height or config.height)
    -- local scale = AptechkaDB.profile.scale or config.scale
    -- local strata = config.frameStrata or "LOW"
    self.initConfSnippet = [=[
            RegisterUnitWatch(self)

            local header = self:GetParent()
            local width = header:GetAttribute("frameWidth")
            local height = header:GetAttribute("frameHeight")
            local scale = header:GetAttribute("frameScale")
            self:SetWidth(width)
            self:SetHeight(height)
            self:SetScale(scale)
            self:SetFrameStrata("LOW")
            self:SetFrameLevel(3)

            self:SetAttribute("toggleForVehicle", true)
            self:SetAttribute("allowVehicleTarget", false)

            self:SetAttribute("*type1","target")
            self:SetAttribute("shift-type2","togglemenu")


            local ccheader = header:GetFrameRef("clickcast_header")
            if ccheader then
                ccheader:SetAttribute("clickcast_button", self)
                ccheader:RunAttribute("clickcast_register")
            end
            header:CallMethod("initialConfigFunction", self:GetName())
    ]=]

    self:LayoutUpdate()
    self:UpdateDebuffScanningMethod()

    self:RegisterEvent("UNIT_HEALTH")
    self:RegisterEvent("UNIT_HEALTH_FREQUENT")
    self:RegisterEvent("UNIT_MAXHEALTH")
    Aptechka.UNIT_HEALTH_FREQUENT = Aptechka.UNIT_HEALTH
    self:RegisterEvent("UNIT_CONNECTION")
    if AptechkaDB.global.showAFK then
        self:RegisterEvent("PLAYER_FLAGS_CHANGED") -- UNIT_AFK_CHANGED
    end

    self:RegisterEvent("UNIT_FACTION")
    self:RegisterEvent("UNIT_FLAGS")
    self.UNIT_FLAGS = self.UNIT_FACTION

    self:RegisterEvent("UNIT_PHASE")

    if not config.disableManaBar then
        self:RegisterEvent("UNIT_POWER_UPDATE")
        self:RegisterEvent("UNIT_MAXPOWER")
        self:RegisterEvent("UNIT_DISPLAYPOWER")
        Aptechka.UNIT_MAXPOWER = Aptechka.UNIT_POWER_UPDATE
    end

    Aptechka:UpdateAggroConfig()

    if config.ReadyCheck then
        self:RegisterEvent("READY_CHECK")
        self:RegisterEvent("READY_CHECK_CONFIRM")
        self:RegisterEvent("READY_CHECK_FINISHED")
    end
    if config.TargetStatus then
        self.previousTarget = "player"
        self:RegisterEvent("PLAYER_TARGET_CHANGED")
    end

    if config.VoiceChatStatus then
        self:RegisterEvent("VOICE_CHAT_CHANNEL_ACTIVATED")
        self:RegisterEvent("VOICE_CHAT_CHANNEL_DEACTIVATED")
        if (C_VoiceChat.GetActiveChannelType()) then
            self:VOICE_CHAT_CHANNEL_ACTIVATED()
        end
    end

    self:RegisterEvent("INCOMING_RESURRECT_CHANGED")
    self.INCOMING_RESURRECT_CHANGED = self.UNIT_PHASE

    if LibClassicDurations then
        LibClassicDurations:RegisterFrame(self)
        UnitAura = LibClassicDurations.UnitAuraWrapper
    end

    LibAuraTypes = LibStub("LibAuraTypes")
    if AptechkaDB.global.useDebuffOrdering then
        LibSpellLocks = LibStub("LibSpellLocks")

        LibSpellLocks.RegisterCallback("Aptechka", "UPDATE_INTERRUPT", function(event, guid)
            local unit = guidMap[guid]
            if unit then
                Aptechka.ScanAuras(unit)
            end
        end)

        DebuffProc = Aptechka.OrderedDebuffProc
        DebuffPostUpdate = Aptechka.OrderedDebuffPostUpdate
    else
        DebuffProc = Aptechka.SimpleDebuffProc
        DebuffPostUpdate = Aptechka.SimpleDebuffPostUpdate
    end

    if config.enableAbsorbBar then
        self:RegisterEvent("UNIT_ABSORB_AMOUNT_CHANGED")
        self:RegisterEvent("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
    end

    self:UpdateCastsConfig()


    -- AptechkaDB.global.useCombatLogHealthUpdates = false
    if AptechkaDB.global.useCombatLogHealthUpdates then
        local CLH = LibStub("LibCombatLogHealth-1.0")
        UnitHealth = CLH.UnitHealth
        self:UnregisterEvent("UNIT_HEALTH")
        self:UnregisterEvent("UNIT_HEALTH_FREQUENT")
        -- table.insert(config.HealthBarColor.assignto, "health2")
        CLH.RegisterCallback(self, "COMBAT_LOG_HEALTH", function(event, unit, eventType)
            return Aptechka:UNIT_HEALTH(eventType, unit)
            -- return Aptechka:COMBAT_LOG_HEALTH(nil, unit, health)
        end)
    end

    self:RegisterEvent("UNIT_AURA")
    self:RegisterEvent("SPELLS_CHANGED")
    self:RegisterEvent("GROUP_ROSTER_UPDATE")

    if AptechkaDB.profile.showRaidIcons then
        self:RegisterEvent("RAID_TARGET_UPDATE")
    end
    if config.enableVehicleSwap then
        self:RegisterEvent("UNIT_ENTERED_VEHICLE")
    end

    if not config.anchorpoint then
        config.anchorpoint = Aptechka:SetAnchorpoint()
    end

    skinAnchorsName = "GridSkin"
    local i = 1
    while (i <= config.maxgroups) do
        local f  = Aptechka:CreateHeader(i) -- if second arg is true then it's petgroup
        group_headers[i] = f
        i = i + 1
    end
    self:UpdatePetGroupConfig()

    if config.unlocked then anchors[1]:Show() end
    local unitGrowth = AptechkaDB.profile.unitGrowth or config.unitGrowth
    local groupGrowth = AptechkaDB.profile.groupGrowth or config.groupGrowth
    Aptechka:SetGrowth(unitGrowth, groupGrowth)

    -- if config.DispelFilterAll
    --     then DispelFilter = "HARMFUL"
    --     else DispelFilter = "HARMFUL|RAID"
    -- end

    Aptechka:SetScript("OnUpdate",Aptechka.OnRangeUpdate)
    Aptechka:Show()

    SLASH_APTECHKA1= "/aptechka"
    SLASH_APTECHKA2= "/apt"
    SLASH_APTECHKA3= "/inj"
    SLASH_APTECHKA4= "/injector"
    SlashCmdList["APTECHKA"] = Aptechka.SlashCmd

    SLASH_APTROLEPOLL1= "/rolepoll"
    SLASH_APTROLEPOLL2= "/rolecheck"
    SlashCmdList["APTROLEPOLL"] = InitiateRolePoll

    if config.LOSStatus then
        self:RegisterEvent("UNIT_SPELLCAST_SENT")
        self:RegisterEvent("UI_ERROR_MESSAGE")
    end

    if config.enableTraceHeals and next(traceheals) then
        self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
        self.COMBAT_LOG_EVENT_UNFILTERED = function( self, event)
            local timestamp, eventType, hideCaster,
            srcGUID, srcName, srcFlags, srcFlags2,
            dstGUID, dstName, dstFlags, dstFlags2,
            spellID, spellName, spellSchool, amount, overhealing, absorbed, critical = CombatLogGetCurrentEventInfo()
            if bit_band(srcFlags, COMBATLOG_OBJECT_AFFILIATION_MINE) == COMBATLOG_OBJECT_AFFILIATION_MINE then
                if spellID == 0 then
                    spellID = spellNameToID[spellName]
                end
                local opts = traceheals[spellID]
                if opts and eventType == opts.type then
                    if guidMap[dstGUID] then
                        local minamount = opts.minamount
                        if not minamount or amount > minamount then
                            SetJob(guidMap[dstGUID],opts,true)
                        end
                    end
                end
            end
        end

    end

    -- --autoloading
    for _,spell_group in pairs(config.autoload) do
        config.LoadableDebuffs[spell_group]()
        loaded[spell_group] = true
    end
    --raid/pvp debuffs loading
    local loader = CreateFrame("Frame")
    loader:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    loader:RegisterEvent("PLAYER_ENTERING_WORLD")
    local mapIDs = config.MapIDs

    local CheckCurrentMap = function()
        local instance
        local _, instanceType = GetInstanceInfo()
        if instanceType == "arena" or instanceType == "pvp" then
            instance = "PvP"
        else
            local uiMapID = C_Map.GetBestMapForUnit("player")
            instance = mapIDs[uiMapID]
        end
        if not instance then return end
        local add = config.LoadableDebuffs[instance]
        if add and not loaded[instance] then
            add()
            print (AptechkaString..instance.." debuffs loaded.")
            loaded[instance] = true
        end
    end

    loader:SetScript("OnEvent",function (self,event)
        C_Timer.After(2, CheckCurrentMap)
    end)


    local f = CreateFrame('Frame', nil, InterfaceOptionsFrame)
    f:SetScript('OnShow', function(self)
        self:SetScript('OnShow', nil)
        LoadAddOn('AptechkaOptions')
    end)

    self.isInitialized = true
end  -- END PLAYER_LOGIN


function Aptechka:ToggleCompactRaidFrames()
    local v = IsAddOnLoaded("Blizzard_CompactRaidFrames")
    local f = v and DisableAddOn or EnableAddOn
    f("Blizzard_CompactRaidFrames")
    f("Blizzard_CUFProfiles")
    ReloadUI()
end

function Aptechka:PostSpellListUpdate()
    self:UpdateMissingAuraList()
    for unit, frames in pairs(Roster) do
        self:UNIT_AURA(nil, unit)
    end
end

function Aptechka:UpdateMissingAuraList()
    table_wipe(missingFlagSpells)
    for spellID, opts in pairs(auras) do
        if opts.isMissing and not opts.disabled then
            missingFlagSpells[opts] = true
        end
    end
end


function Aptechka:CreatePetGroup()
    if group_headers[9] then return end -- already exists
    local pets  = Aptechka:CreateHeader(9,true)
    group_headers[9] = pets
    pets:Show()
end
function Aptechka:UpdatePetGroupConfig()
    if AptechkaDB.profile.petGroup then
        Aptechka:CreatePetGroup()
    else
        if group_headers[9] then
            group_headers[9]:Hide()
        end
    end
end

function Aptechka:UpdateName(frame)
    local name = frame.nameFull
    frame.name = name and utf8sub(name,1, AptechkaDB.profile.cropNamesLen) or "Unknown"
    FrameSetJob(frame, config.UnitNameStatus, true)
end

function Aptechka:Reconfigure()
    if not self.isInitialized then return end
    if InCombatLockdown() then self:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
    self:ReconfigureProtected()
    self:ReconfigureUnprotected()

    self:UpdateDebuffScanningMethod()
    self:UpdateRaidIconsConfig()
    self:UpdateAggroConfig()
    self:UpdateCastsConfig()
end
function Aptechka:RefreshAllUnitsHealth()
    for unit, frames in pairs(Roster) do
        Aptechka:UNIT_HEALTH("UNIT_HEALTH", unit)
        Aptechka:UNIT_POWER_UPDATE("UNIT_HEALTH", unit)
    end
end
function Aptechka:RefreshAllUnitsColors()
    for unit, frames in pairs(Roster) do
        for frame in pairs(frames) do
            FrameSetJob(frame, config.UnitNameStatus, true)
            FrameSetJob(frame, config.HealthBarColor, true)
            FrameSetJob(frame, config.PowerBarColor, true)
        end
    end
end
function Aptechka:ReconfigureUnprotected()
    self:UpdateUnprotectedUpvalues()
    for group, header in ipairs(group_headers) do
        for _, f in ipairs({ header:GetChildren() }) do
            self:UpdateName(f)
            f:ReconfigureUnitFrame()
            if Aptechka.PostFrameUpdate then
                Aptechka.PostFrameUpdate(f)
            end
        end
    end
end
function Aptechka:UpdateUnprotectedUpvalues()
    ignoreplayer = config.incomingHealIgnorePlayer or false
    fgShowMissing = Aptechka.db.profile.fgShowMissing
    debuffLimit = AptechkaDB.profile.debuffLimit
end
function Aptechka:ReconfigureProtected()
    if InCombatLockdown() then self:RegisterEvent("PLAYER_REGEN_ENABLED"); return end

    self:RepositionAnchor()
    self:UpdatePetGroupConfig()

    local width = pixelperfect(AptechkaDB.profile.width or config.width)
    local height = pixelperfect(AptechkaDB.profile.height or config.height)
    local scale = AptechkaDB.profile.scale or config.scale
    -- local strata = config.frameStrata or "LOW"
    -- self.initConfSnippet = self.makeConfSnippet(width, height, strata)
    for group, header in ipairs(group_headers) do
        if header:CanChangeAttribute() then
            header:SetAttribute("frameWidth", width)
            header:SetAttribute("frameHeight", height)
            header:SetAttribute("frameScale", scale)
        end
        for _, f in ipairs({ header:GetChildren() }) do
            f:SetWidth(width)
            f:SetHeight(height)
            f:SetScale(scale)
            if f:CanChangeAttribute() then
                -- this is only for classic, because its SGH doesn't have _initialAttributeNames
                f:SetAttribute("_onenter",[[
                    local snippet = self:GetAttribute('clickcast_onenter'); if snippet then self:Run(snippet) end
                    self:CallMethod("onenter")
                ]])

                f:SetAttribute("_onleave",[[
                    local snippet = self:GetAttribute('clickcast_onleave'); if snippet then self:Run(snippet) end
                    self:CallMethod("onleave")
                ]])
            end
        end

        local showSolo = AptechkaDB.profile.showSolo
        header:SetAttribute("showSolo", showSolo)

        header:SetAttribute("showParty", AptechkaDB.profile.showParty)
    end

    local unitGrowth = AptechkaDB.profile.unitGrowth or config.unitGrowth
    local groupGrowth = AptechkaDB.profile.groupGrowth or config.groupGrowth
    Aptechka:SetGrowth(unitGrowth, groupGrowth)
end



do
    local spellNameBasedCategories = { "traces" }
    function Aptechka:UpdateSpellNameToIDTable()
        local mergedConfig = AptechkaConfigMerged
        local visited = {}

        for _, catName in ipairs(spellNameBasedCategories) do
            local category = mergedConfig[catName]
            if category then
                for spellID, opts in pairs(category) do
                    if not visited[opts] then
                        local lastRankID
                        local clones = opts.clones
                        if clones then
                            lastRankID = clones[#clones]
                        else
                            lastRankID = spellID
                        end
                        helpers.AddSpellNameRecognition(lastRankID)

                        visited[opts] = true
                    end
                end
            end
        end
    end
end

function Aptechka:HealUpdated(event, casterGUID, spellID, healType, endTime, ...)
    for i=1,select('#', ...) do
        local targetGUID = select(i, ...)
        local unit = guidMap[targetGUID]
        if unit then
            Aptechka:UNIT_HEAL_PREDICTION(nil, unit, targetGUID)
        end
    end
end

local incomingHealTimeframe = 3

local function GetIncomingHealsCustom(unit, excludePlayer)
    local guid = UnitGUID(unit)
    local heal = HealComm:GetHealAmount(guid, HealComm.AptechkaHealType, GetTime()+incomingHealTimeframe)
    return heal or 0
end

function Aptechka.UNIT_HEAL_PREDICTION(self,event,unit, guid)
    self:UNIT_HEALTH(event, unit)

    local heal = HealComm:GetHealAmount(guid, HealComm.AptechkaHealType, GetTime()+incomingHealTimeframe)
    local showHeal = (heal and heal > threshold)

    if not Roster[unit] then return end
    for self in pairs(Roster[unit]) do
        if config.IncomingHealStatus then
            if showHeal then
                self.vIncomingHeal = heal
                SetJob(unit, config.IncomingHealStatus, true)
            else
                self.vIncomingHeal = 0
                SetJob(unit, config.IncomingHealStatus, false)
            end
        end
    end
end

function Aptechka.UNIT_ABSORB_AMOUNT_CHANGED(self, event, unit)
    local rosterunit = Roster[unit]
    if not rosterunit then return end
    for self in pairs(rosterunit) do
        local a,hm = UnitGetTotalAbsorbs(unit), UnitHealthMax(unit)
        local h = UnitHealth(unit)
        local ch, p = 0, 0
        if hm ~= 0 then
            p = a/hm
            ch = h/hm
        end
        self.absorb:SetValue(p, ch)
        self.absorb2:SetValue(p, ch)
    end
end

function Aptechka.UNIT_HEAL_ABSORB_AMOUNT_CHANGED(self, event, unit)
    local rosterunit = Roster[unit]
    if not rosterunit then return end
    for self in pairs(rosterunit) do
        local a = UnitGetTotalHealAbsorbs(unit)
        local hm = UnitHealthMax(unit)
        local h = UnitHealth(unit)
        local ch, p = 0, 0
        if hm ~= 0 then
            ch = (h/hm)
            p = a/hm
        end
        self.healabsorb:SetValue(p, ch)
    end
end

local function GetForegroundSeparation(health, healthMax, showMissing)
    if showMissing then
        return (healthMax - health)/healthMax, health/healthMax
    else
        return health/healthMax, health/healthMax
    end
end

function Aptechka:UNIT_MAXHEALTH(event, unit)
    if unit == "player" then
        threshold = UnitHealthMax("player")*0.04 -- 4% of player max health
    end
    return Aptechka:UNIT_HEALTH(event, unit)
end

function Aptechka.UNIT_HEALTH(self, event, unit)
    -- local beginTime1 = debugprofilestop();

    local rosterunit = Roster[unit]
    if not rosterunit then return end
    for self in pairs(rosterunit) do
        local h,hm = UnitHealth(unit), UnitHealthMax(unit)
        local shields = UnitGetTotalAbsorbs(unit)
        local healabsorb = UnitGetTotalHealAbsorbs(unit)
        local incomingHeal = GetIncomingHealsCustom(unit, ignoreplayer)
        if hm == 0 then return end
        local healthPercent, fgSep = GetForegroundSeparation(h, hm, fgShowMissing)
        self.vHealth = h
        self.vHealthMax = hm
        self.health:SetValue(healthPercent*100)
        self.healabsorb:SetValue(healabsorb/hm, fgSep)
        self.absorb2:SetValue(shields/hm, fgSep)
        self.absorb:SetValue(shields/hm, fgSep)
        self.health.incoming:SetValue(incomingHeal/hm, fgSep)
        FrameSetJob(self, config.HealthDeficitStatus, ((hm-h) > hm*0.05) )

        if event then
            if UnitIsDeadOrGhost(unit) then
                SetJob(unit, config.AggroStatus, false)
                local isGhost = UnitIsGhost(unit)
                local deadorghost = isGhost and config.GhostStatus or config.DeadStatus
                SetJob(unit, deadorghost, true)
                SetJob(unit,config.HealthDeficitStatus, false )
                self.isDead = true
                Aptechka:UNIT_DISPLAYPOWER(event, unit, true)
                if self.OnDead then self:OnDead() end
            elseif self.isDead then
                self.isDead = false
                Aptechka.ScanAuras(unit)
                SetJob(unit, config.GhostStatus, false)
                SetJob(unit, config.DeadStatus, false)
                SetJob(unit, config.ResPendingStatus, false)
                SetJob(unit, config.ResIncomingStatus, false)
                Aptechka:UNIT_DISPLAYPOWER(event, unit, false)
                if self.OnAlive then self:OnAlive() end
            end
        end

    end

    -- local timeUsed1 = debugprofilestop();
    -- print("UNIT_HEALTH", timeUsed1 - beginTime1)
end


function Aptechka:CheckPhase(frame, unit)
    if UnitHasIncomingResurrection(unit) then
        frame.centericon.texture:SetTexture("Interface\\RaidFrame\\Raid-Icon-Rez");
        frame.centericon.texture:SetTexCoord(0,1,0,1);
        frame.centericon:Show()
    elseif (not UnitInPhase(unit) or UnitIsWarModePhased(unit)) and not frame.InVehicle then
        frame.centericon.texture:SetTexture("Interface\\TargetingFrame\\UI-PhasingIcon");
        frame.centericon.texture:SetTexCoord(0.15625, 0.84375, 0.15625, 0.84375);
        frame.centericon:Show()
    else
        frame.centericon:Hide()
    end
end

function Aptechka.UNIT_PHASE(self, event, unit)
    local frames = Roster[unit]
    if frames then
        for frame in pairs(frames) do
            Aptechka:CheckPhase(frame,unit)
        end
    end
end

function Aptechka:UpdateMindControl(unit)
    local frames = Roster[unit]
    if frames then
        for frame in pairs(frames) do
            -- local currentUnit = SecureButton_GetModifiedUnit(frame)
            local ownerUnit = SecureButton_GetUnit(frame)
            -- if a button is currently overridden by pet(vehicle) unit, it'll report as charmed
            -- so always using owner unit to check
            local isMindControlled = UnitIsCharmed(ownerUnit)

            FrameSetJob(frame, config.MindControlStatus, isMindControlled)
        end
    end
end

function Aptechka:UpdateUnhealable(unit)
    --[[
    local frames = Roster[unit]
    if frames then
        for frame in pairs(frames) do
            local isUnhealable = SecureCmdOptionParse(string.format("[target=%s,help] 1; 2", unit)) == "2"
            FrameSetJob(frame, config.UnhealableStatus, isUnhealable)
        end
    end
    ]]
end

function Aptechka.UNIT_FACTION(self, event, unit)
    self:UpdateMindControl(unit)
    self:UpdateUnhealable(unit)
end

local afkPlayerTable = {}
function Aptechka.UNIT_AFK_CHANGED(self, event, unit)
    if not Roster[unit] then return end
    for self in pairs(Roster[unit]) do
        local name = UnitGUID(unit)
        if UnitIsAFK(unit) then
            if name then
                local startTime = afkPlayerTable[name]
                if not startTime then
                    startTime = GetTime()
                    afkPlayerTable[name] = startTime
                end

                local job = config.AwayStatus
                job.startTime = startTime
            end
            SetJob(unit, config.AwayStatus, true)
        else
            if name then
                afkPlayerTable[name] = nil
            end
            SetJob(unit, config.AwayStatus, false)
        end
    end
end
Aptechka.PLAYER_FLAGS_CHANGED = Aptechka.UNIT_AFK_CHANGED


local offlinePlayerTable = {}
function Aptechka.UNIT_CONNECTION(self, event, unit)
    if not Roster[unit] then return end
    for frame in pairs(Roster[unit]) do
        -- if self.unitOwner then unit = self.unitOwner end
        local name = UnitGUID(unit)
        if not UnitIsConnected(unit) then
            if name then
                local startTime = offlinePlayerTable[name]
                if not startTime then
                    startTime = GetTime()
                    offlinePlayerTable[name] = startTime
                end

                local job = config.OfflineStatus
                job.startTime = startTime
            end
            FrameSetJob(frame, config.OfflineStatus, true)
        else
            if name then
                offlinePlayerTable[name] = nil
            end
            FrameSetJob(frame, config.OfflineStatus, false)
        end
    end
end

function Aptechka.UNIT_POWER_UPDATE(self, event, unit, ptype)
    local rosterunit = Roster[unit]
    if not rosterunit then return end
    for self in pairs(rosterunit) do
        if self.power and not self.power.disabled then
            local powerMax = UnitPowerMax(unit)
            local power = UnitPower(unit)
            if powerMax == 0 then
                power = 1
                powerMax = 1
            end
            local manaPercent = GetForegroundSeparation(power, powerMax, fgShowMissing)
            -- print(manaPercent, power, powerMax, fgShowMissing)
            self.power:SetValue(manaPercent*100)
        end
    end
end
function Aptechka.UNIT_DISPLAYPOWER(self, event, unit, isDead)
    if not Roster[unit] then return end
    for self in pairs(Roster[unit]) do
        if self.power and self.power.OnPowerTypeChange then
            local tnum, tname = UnitPowerType(unit)
            self.power:OnPowerTypeChange(tname, isDead)
        end
    end
end

-- STAY AWAY FROM DA VOODOO
local vehicleHack = function (self, time)
    self.OnUpdateCounter = self.OnUpdateCounter + time
    if self.OnUpdateCounter < 1 then return end
    self.OnUpdateCounter = 0
    local owner = self.parent.unitOwner
    if not ( UnitHasVehicleUI(owner) or UnitInVehicle(owner) or UnitUsingVehicle(owner) ) then
        if Roster[self.parent.unit] then
            -- Restore owner unit in the roster, delete vehicle unit
            Roster[owner] = Roster[self.parent.unit]
            Roster[self.parent.unit] = nil
            self.parent.unit = owner
            self.parent.unitOwner = nil
            self.parent.guid = UnitGUID(owner)
            self.parent.InVehicle = nil

            -- print(string.format("L1>>Unit: %-s",original_unit))
            -- print(string.format("D4>[%s]>Dumping- Roster",NAME))
            -- d87add.dump("ROSTER")-

            -- Remove vehicle status
            SetJob(owner,config.InVehicleStatus,false)
            -- Update unitframe back to owner's unit health, etc.
            Aptechka:UNIT_HEALTH("VEHICLE",owner)
            if self.parent.power then
                Aptechka:UNIT_DISPLAYPOWER(nil, owner)
                Aptechka:UNIT_POWER_UPDATE(nil,owner)
            end
            if self.parent.absorb then
                Aptechka:UNIT_ABSORB_AMOUNT_CHANGED(nil, owner)
            end
            Aptechka.ScanAuras(owner)

            Aptechka:UpdateMindControl(owner)
            Aptechka:UpdateUnhealable(owner)

            -- Stop periodic checks
            self:SetScript("OnUpdate",nil)
        end
    end
end
function Aptechka.UNIT_ENTERED_VEHICLE(self, event, unit)
    if not Roster[unit] then return end
    for self in pairs(Roster[unit]) do
        if not self.InVehicle then --print("Already in vehicle")
            local vehicleUnit = SecureButton_GetModifiedUnit(self)
            -- local vehicleOwner = SecureButton_GetUnit(self)
            if unit ~= vehicleUnit then
                self.InVehicle = true
                self.unitOwner = unit --original unit
                self.unit = vehicleUnit

                self.guid = UnitGUID(vehicleUnit)
                if self.guid then guidMap[self.guid] = vehicleUnit end

                -- Delete owner unit from Roster and add point vehicle unit to this button instead
                Roster[self.unit] = Roster[self.unitOwner]
                Roster[self.unitOwner] = nil

                -- A small frame is crated to start 1s periodic OnUpdate checks when unit has left the vehicle
                if not self.vehicleFrame then self.vehicleFrame = CreateFrame("Frame"); self.vehicleFrame.parent = self end
                self.vehicleFrame.OnUpdateCounter = -1.5
                self.vehicleFrame:SetScript("OnUpdate",vehicleHack)

                -- Set in vehicle status
                SetJob(self.unit,config.InVehicleStatus,true)
                -- Update unitframe for the new vehicle unit
                Aptechka:UNIT_HEALTH("VEHICLE",self.unit)
                if self.power then Aptechka:UNIT_POWER_UPDATE(nil,self.unit) end
                if self.absorb then Aptechka:UNIT_ABSORB_AMOUNT_CHANGED(nil,self.unit) end
                Aptechka:CheckPhase(self, self.unit)
                Aptechka.ScanAuras(self.unit)

                Aptechka:UpdateMindControl(self.unit) -- pet unit will be marked as 'charmed'
                Aptechka:UpdateUnhealable(self.unit)

                -- Except class color, it's still tied to owner
                Aptechka:Colorize(nil, self.unitOwner)
            end
        end
    end
end
-- VOODOO ENDS HERE


--Range check
Aptechka.OnRangeUpdate = function (self, time)
    self.OnUpdateCounter = (self.OnUpdateCounter or 0) + time
    if self.OnUpdateCounter < 0.3 then return end
    self.OnUpdateCounter = 0

    if not IsInGroup() then --UnitInRange returns false when not grouped
        for unit, frames in pairs(Roster) do
            for frame in pairs(frames) do
                frame:SetAlpha(1)
            end
        end
        return
    end

    if (RosterUpdateOccured) then
        if RosterUpdateOccured + 3 < GetTime() then
            if not InCombatLockdown() then
                RosterUpdateOccured = nil

                for i,hdr in pairs(group_headers) do
                    local showSolo = AptechkaDB.profile.showSolo
                    hdr:SetAttribute("showSolo", not showSolo)
                    hdr:SetAttribute("showSolo", showSolo)
                end
            end
        end
    end

    for unit, frames in pairs(Roster) do
        for frame in pairs(frames) do
            if AptechkaUnitInRange(unit) then
                frame:SetAlpha(1)
            else
                frame:SetAlpha(0.45)
            end
        end
    end
end

--Aggro
function Aptechka:UpdateAggroConfig()
    if not config.AggroStatus then return end
    if AptechkaDB.profile.showAggro then
        if isClassic then
            local LB = LibStub("LibBanzai-2.0", true)
            if LB then
                UnitThreatSituation = function(unit)
                    local gotAggro = LB:GetUnitAggroByUnitId(unit)
                    return gotAggro and 3 or 0
                end
                LB:RegisterCallback(function(aggroInt, name, unit)
                    if not AptechkaDB.profile.showAggro then return end
                    return Aptechka:UNIT_THREAT_SITUATION_UPDATE(nil, unit)
                end)
            end
        else
            self:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
        end
    else
        if isClassic then
            -- local LB = LibStub("LibBanzai-2.0", true)
            -- if LB then
            --     LB:UnregisterCallback(LibBanzaiCallback) -- It can't fail silently
            -- end
        else
            self:UnregisterEvent("UNIT_THREAT_SITUATION_UPDATE")
        end

        if self.isInitialized then
            self:ForEachFrame(function(frame)
                FrameSetJob(frame, config.AggroStatus, false)
            end)
        end
    end
end
function Aptechka.UNIT_THREAT_SITUATION_UPDATE(self, event, unit)
    if not Roster[unit] then return end
    for self in pairs(Roster[unit]) do
        local sit = UnitThreatSituation(unit)
        if sit and sit > 1 then
            SetJob(unit, config.AggroStatus, true)
        else
            SetJob(unit, config.AggroStatus, false)
        end
    end
end

function Aptechka.UNIT_SPELLCAST_SENT(self, event, unit, targetName, lineID, spellID)
    if unit ~= "player" or not targetName then return end
    LastCastTargetName = string.match(targetName, "(.+)-") or targetName
    LastCastSentTime = GetTime()
end
function Aptechka.UI_ERROR_MESSAGE(self, event, errcode, errtext)
    if errcode == 50 or errcode == 51 then -- Out of Range code
        if LastCastSentTime > GetTime() - 0.5 then
            for unit in pairs(Roster) do
                if UnitName(unit) == LastCastTargetName then
                    SetJob(unit, config.LOSStatus, true)
                    return
                end
            end
        end
    end
end

function Aptechka.CheckRoles(apt, self, unit )

    local isRaidMaintank = GetPartyAssignment("MAINTANK", unit) -- gets updated on GROUP_ROSTER_UPDATE and PLAYER_ROLES_ASSIGNED
    local isTankRoleAssigned = UnitGroupRolesAssigned(unit) == "TANK"
    local isAnyTank = isRaidMaintank or isTankRoleAssigned

    if config.MainTankStatus then
        FrameSetJob(self, config.MainTankStatus, isAnyTank)
    end

    if config.displayRoles then
        local isLeader = UnitIsGroupLeader(unit)
        local role = UnitGroupRolesAssigned(unit)

        FrameSetJob(self, config.LeaderStatus, isLeader)
        if config.AssistStatus then
            local isAssistant = UnitIsGroupAssistant(unit)
            FrameSetJob(self, config.AssistStatus, isAssistant)
        end

        local icon = self.roleicon.texture
        if icon then
            if UnitGroupRolesAssigned(unit) == "HEALER" then
                -- GetTexCoordsForRoleSmallCircle("HEALER") -- Classic doesn't have this function
                icon:SetTexCoord(20/64, 39/64, 1/64, 20/64); icon:Show()
            elseif isTankRoleAssigned then
                icon:SetTexCoord(0, 19/64, 22/64, 41/64); icon:Show()
            else
                icon:Hide()
            end
        end
    end
end

function Aptechka.PLAYER_REGEN_ENABLED(self,event)
    self:Reconfigure()
    self:UnregisterEvent("PLAYER_REGEN_ENABLED")
end

function Aptechka:UpdateRangeChecker()
    local spec = GetSpecialization() or 1
    if config.UnitInRangeFunctions and config.UnitInRangeFunctions[spec] then
        uir = config.UnitInRangeFunctions[spec]
    else
        uir = UnitInRange
    end
end

function Aptechka:UpdateDispelBitmask()
    local spec = GetSpecialization() or 1
    if config.DispelBitmasks and config.DispelBitmasks[spec] then
        BITMASK_DISPELLABLE = config.DispelBitmasks[spec]
    else
        BITMASK_DISPELLABLE = 0
    end
end

function Aptechka.GROUP_ROSTER_UPDATE(self,event,arg1)
    RosterUpdateOccured = GetTime()

    --raid autoscaling
    if not InCombatLockdown() then
        Aptechka:LayoutUpdate()
    else
        self:RegisterEvent("PLAYER_REGEN_ENABLED")
    end

    for unit, frames in pairs(Roster) do
        for frame in pairs(frames) do
            Aptechka:CheckRoles(frame, unit)
        end
    end
end


function Aptechka:OnRoleChanged()
    if not InCombatLockdown() then Aptechka:LayoutUpdate() end
    Aptechka:ReconfigureProtected() -- Schedules update on combat exit, that also includes layout update
end
do
    local currentRole
    function Aptechka:SPELLS_CHANGED()
        Aptechka:UpdateRangeChecker()
        Aptechka:UpdateDispelBitmask()

        local role = self:GetSpecRole()
        if role ~= currentRole then
            self:OnRoleChanged()
            currentRole = role
        end
    end
end

function Aptechka:GetCurrentGroupType()
    if IsInRaid() then
        local numMembers = GetNumGroupMembers()
        if numMembers > 30 then
            return "bigRaid"
        elseif numMembers > 15 then
            return "mediumRaid"
        elseif numMembers > 5 then
            return "smallRaid"
        else
            return "party"
        end
    elseif IsInGroup() then
        local numMembers = GetNumGroupMembers()
        if numMembers > 1 then
            return "party"
        else
            return "solo"
        end
    else
        return "solo"
    end
end

function Aptechka.LayoutUpdate(self)
    local numMembers = GetNumGroupMembers()
    local spec = GetSpecialization()
    local role = self:GetSpecRole()
    local groupType = self:GetCurrentGroupType()

    local newProfileName = self.db.global.profileSelection[role][groupType]

    self.db:SetProfile(newProfileName)
end

--raid icons
function Aptechka:UpdateRaidIconsConfig()
    if not Aptechka.db.profile.showRaidIcons then
        Aptechka:ForEachFrame(function(self) self.raidicon:Hide() end)
        Aptechka:UnregisterEvent("RAID_TARGET_UPDATE")
    else
        Aptechka:RAID_TARGET_UPDATE()
        Aptechka:RegisterEvent("RAID_TARGET_UPDATE")
    end
end
function Aptechka.RAID_TARGET_UPDATE(self, event)
    if not AptechkaDB.profile.showRaidIcons then return end
    for unit, frames in pairs(Roster) do
        for self in pairs(frames) do
            local index = GetRaidTargetIndex(unit)
            local icon = self.raidicon
            if icon then
            if index then
                SetRaidTargetIconTexture(icon.texture, index)
                icon:Show()
            else
                icon:Hide()
            end
            end
        end
    end
end

function Aptechka:ForEachFrame(func)
    for unit, frames in pairs(Roster) do
        for frame in pairs(frames) do
            func(frame)
        end
    end
end


-- function Aptechka.INCOMING_RESURRECT_CHANGED(self, event, unit)
    -- if not Roster[unit] then return end
    -- for self in pairs(Roster[unit]) do
        -- SetJob(unit, config.ResurrectStatus, UnitHasIncomingResurrection(unit))
    -- end
-- end

--Target Indicator
function Aptechka.PLAYER_TARGET_CHANGED(self, event)
    local newTargetUnit = guidMap[UnitGUID("target")]
    if newTargetUnit and Roster[newTargetUnit] then
        SetJob(Aptechka.previousTarget, config.TargetStatus, false)
        SetJob(newTargetUnit, config.TargetStatus, true)
        Aptechka.previousTarget = newTargetUnit
    else
        SetJob(Aptechka.previousTarget, config.TargetStatus, false)
    end
end

-- Readycheck
function Aptechka.READY_CHECK(self, event)
    for unit in pairs(Roster) do
        self:READY_CHECK_CONFIRM(event, unit)
    end
end
function Aptechka.READY_CHECK_CONFIRM(self, event, unit)
    local rci = config.ReadyCheck
    if not Roster[unit] then return end
    for self in pairs(Roster[unit]) do
        local status = GetReadyCheckStatus(unit)
        if not status or not rci.stackcolor[status] then return end
        rci.color = rci.stackcolor[status]
        SetJob(unit, rci, true)
    end
end
function Aptechka.READY_CHECK_FINISHED(self, event)
    for unit in pairs(Roster) do
        SetJob(unit, config.ReadyCheck, false)
    end
end

--applying UnitButton color
function Aptechka.Colorize(self, event, unit)
    if not Roster[unit] then return end
    for self in pairs(Roster[unit]) do
        local hdr = self:GetParent()
        --if hdr.isPetGroup then   -- use owner color
        --    unit = string.gsub(unit,"pet","")
        --    if unit == "" then unit = "player" end
        --end
        if hdr.isPetGroup then
            self.classcolor = config.petcolor
        else
            local _,class = UnitClass(unit)
            if class then
                local color = colors[class] -- or { r = 1, g = 1, b = 0}
                self.classcolor = {color.r,color.g,color.b}
            end
        end
    end
end


local has_unknowns = true
local UNKNOWNOBJECT = UNKNOWNOBJECT

local function updateUnitButton(self, unit)
    local owner = unit
    -- print("InVehicle:", self.InVehicle, "  unitOwner:", self.unitOwner, "  unit:", unit)
    if self.InVehicle and unit and unit == self.unitOwner then
        unit = self.unit
        owner = self.unitOwner
        --if for some reason game will decide to update unit whose frame is mapped to vehicleunit in roster
    elseif self.InVehicle and unit then
        owner = self.unitOwner
    else
        if self.vehicleFrame then
            self.vehicleFrame:SetScript("OnUpdate",nil)
            self.vehicleFrame = nil
            self.InVehicle = nil
            FrameSetJob(self,config.InVehicleStatus,false)
            -- print ("Killing orphan vehicle frame")
        end
    end

    -- Removing frames that no longer associated with this unit from Roster
    for roster_unit, frames in pairs(Roster) do
        if frames[self] and (  self:GetAttribute("unit") ~= roster_unit   ) then -- or (self.InVehicle and self.unitOwner ~= roster_unit)
            -- print ("Removing frame", self:GetName(), roster_unit, "=>", self:GetAttribute("unit"))
            frames[self] = nil
        end
    end

    if self.OnUnitChanged then self:OnUnitChanged(owner) end
    if not unit then return end

    local name, realm = UnitName(owner)
    if name == UNKNOWNOBJECT or name == nil then
        has_unknowns = true
    end
    self.nameFull = name
    Aptechka:UpdateName(self)

    self.unit = unit
    Roster[unit] = Roster[unit] or {}
    Roster[unit][self] = true
    self.guid = UnitGUID(unit) -- is it even needed?
    if self.guid then guidMap[self.guid] = unit end
    for guid, gunit in pairs(guidMap) do
        if not Roster[gunit] or guid ~= UnitGUID(gunit) then guidMap[guid] = nil end
    end

    Aptechka:Colorize(nil, owner)
    FrameSetJob(self,config.HealthBarColor,true)
    FrameSetJob(self,config.PowerBarColor,true)
    Aptechka.ScanAuras(unit)
    Aptechka:UNIT_HEALTH("UNIT_HEALTH", unit)
    if config.enableAbsorbBar then
        Aptechka:UNIT_ABSORB_AMOUNT_CHANGED(nil, unit)
    end
    Aptechka:UNIT_CONNECTION("ONATTR", owner)

    if AptechkaDB.global.showAFK then
        Aptechka:UNIT_AFK_CHANGED(nil, owner)
    end
    Aptechka:CheckPhase(self, unit)
    SetJob(unit, config.ReadyCheck, false)
    if not config.disableManaBar then
        Aptechka:UNIT_DISPLAYPOWER(nil, unit)
        Aptechka:UNIT_POWER_UPDATE(nil, unit)
    end
    Aptechka:UNIT_THREAT_SITUATION_UPDATE(nil, unit)
    Aptechka:UpdateMindControl(unit)
    Aptechka:UpdateUnhealable(unit)
    Aptechka:RAID_TARGET_UPDATE()
    if config.enableVehicleSwap and UnitHasVehicleUI(owner) then
        Aptechka:UNIT_ENTERED_VEHICLE(nil,owner) -- scary
    end
    Aptechka:CheckRoles(self, unit)
    if HealComm and config.enableIncomingHeals then Aptechka:UNIT_HEAL_PREDICTION(nil,unit, UnitGUID(unit)) end
end

local delayedUpdateTimer = C_Timer.NewTicker(5, function()
    if has_unknowns then
        has_unknowns = false
        for unit, frames in pairs(Roster) do
            for frame in pairs(frames) do
                -- updateUnitButton may change has_unknowns back to true
                updateUnitButton(frame, unit)
            end
        end
    end
end)

--UnitButton initialization
local OnAttributeChanged = function(self, attrname, unit)
    if attrname == "unit" then
        updateUnitButton(self, unit)
    end
end



local arrangeHeaders = function(prv_group, notreverse, unitGrowth, groupGrowth)
        local p1, p2
        local xgap = 0
        local ygap = AptechkaDB.profile.groupGap or config.groupGap
        local point, direction = reverse(unitGrowth or config.unitGrowth)
        local grgrowth = groupGrowth or (notreverse and reverse(config.groupGrowth) or config.groupGrowth)
        -- print(point, direction, grgrowth)
        if grgrowth == "TOP" then
            if direction == "VERTICAL" then point = "" end
            p1 = "BOTTOM"..point; p2 = "TOP"..point;
        elseif grgrowth == "BOTTOM" then
            if direction == "VERTICAL" then point = "" end
            p2 = "BOTTOM"..point; p1 = "TOP"..point
            ygap = -ygap
        elseif grgrowth == "RIGHT" then
            if direction == "HORIZONTAL" then point = "" end
            p1 = point.."LEFT"; p2 = point.."RIGHT"
            xgap, ygap = ygap, xgap
        elseif grgrowth == "LEFT" then
            if direction == "HORIZONTAL" then point = "" end
            p2 = point.."LEFT"; p1 = point.."RIGHT"
            xgap, ygap = -ygap, xgap
        end
        return p1, prv_group, p2, xgap, ygap
end
function Aptechka.CreateHeader(self,group,petgroup)
    local frameName = "NugRaid"..group

    local HeaderTemplate = petgroup and "SecureGroupPetHeaderTemplate" or "SecureGroupHeaderTemplate"
    local f = CreateFrame("Button",frameName, UIParent, HeaderTemplate)

    f:SetFrameStrata("BACKGROUND")

    f:SetAttribute("template", "SecureUnitButtonTemplate, SecureHandlerStateTemplate, SecureHandlerEnterLeaveTemplate")
    if(Clique) then
        SecureHandlerSetFrameRef(f, 'clickcast_header', Clique.header)
    end


    local xgap = AptechkaDB.profile.unitGap or config.unitGap
    local ygap = AptechkaDB.profile.unitGap or config.unitGap
    local unitgr = reverse(AptechkaDB.profile.unitGrowth or config.unitGrowth)
    if unitgr == "RIGHT" then
        xgap = -xgap
    elseif unitgr == "TOP" then
        ygap = -ygap
    end
    f:SetAttribute("point", unitgr)
    f:SetAttribute("xOffset", xgap)
    f:SetAttribute("yOffset", ygap)

    if not petgroup
    then
        f:SetAttribute("groupFilter", group)
        if AptechkaDB.global.sortUnitsByRole then
            f:SetAttribute("groupBy", "ROLE")
            f:SetAttribute("groupingOrder", "MAINTANK,MAINASSIST")
        end
    else
        f.isPetGroup = true
        f:SetAttribute("maxColumns", 1 )
        f:SetAttribute("unitsPerColumn", 5)
        --f:SetAttribute("startingIndex", 5*((group - config.maxgroups)-1))
    end
    --our group header doesn't really inherits SecureHandlerBaseTemplate

    local showSolo = AptechkaDB.profile.showSolo -- or config.showSolo
    f:SetAttribute("showRaid", true)
    f:SetAttribute("showParty", AptechkaDB.profile.showParty)
    f:SetAttribute("showSolo", showSolo)
    f:SetAttribute("showPlayer", true)
    f.initialConfigFunction = Aptechka.SetupFrame
    f:SetAttribute("initialConfigFunction", self.initConfSnippet)

    local width = pixelperfect(AptechkaDB.profile.width or config.width)
    local height = pixelperfect(AptechkaDB.profile.height or config.height)
    local scale = AptechkaDB.profile.scale or config.scale
    f:SetAttribute("frameWidth", width)
    f:SetAttribute("frameHeight", height)
    f:SetAttribute("frameScale", scale)

    f:SetAttribute('_initialAttributeNames', '_onenter,_onleave,refreshUnitChange,_onstate-vehicleui')
    f:SetAttribute('_initialAttribute-_onenter', [[
        local snippet = self:GetAttribute('clickcast_onenter')
        if(snippet) then self:Run(snippet) end
        self:CallMethod("onenter")
    ]])
    f:SetAttribute('_initialAttribute-_onleave', [[
        local snippet = self:GetAttribute('clickcast_onleave')
        if(snippet) then self:Run(snippet) end
        self:CallMethod("onleave")
    ]])

    --[[
    f:SetAttribute('_initialAttribute-_onmousedown', [==[
        print("OnMouseDown", self:GetName(), button)
        if (button == "RightButton") then
            self:SetAttribute("mouselook", "started")
        end
        --self:CallMethod("onMouseDown", button)
    ]==])
    f:SetAttribute('_initialAttribute-_onmouseup', [==[
        print("OnMouseUp", self:GetName(), button)
        if (button == "RightButton") then
            self:SetAttribute("mouselook", "stopped")
        end
        --self:CallMethod("onMouseUp")
    ]==])
    ]]
    -- f:SetAttribute('_initialAttribute-refreshUnitChange', [[
    --     local unit = self:GetAttribute('unit')
    --     if(unit) then
    --         RegisterStateDriver(self, 'vehicleui', '[@' .. unit .. ',unithasvehicleui]vehicle; novehicle')
    --     else
    --         UnregisterStateDriver(self, 'vehicleui')
    --     end
    -- ]])
    -- f:SetAttribute('_initialAttribute-_onstate-vehicleui', [[
    --     local unit = self:GetAttribute('unit')
    --     if(newstate == 'vehicle' and unit and UnitPlayerOrPetInRaid(unit) and not UnitTargetsVehicleInRaidUI(unit)) then
    --         self:SetAttribute('toggleForVehicle', false)
    --     else
    --         self:SetAttribute('toggleForVehicle', true)
    --     end
    -- ]])

    local unitGrowth = AptechkaDB.profile.unitGrowth or config.unitGrowth
    local groupGrowth = AptechkaDB.profile.groupGrowth or config.groupGrowth

    if group == 1 then
        Aptechka:CreateAnchor(f,group)
    elseif petgroup then
        f:SetPoint(arrangeHeaders(group_headers[1], nil, unitGrowth, reverse(groupGrowth)))
    else
        f:SetPoint(arrangeHeaders(group_headers[group-1]))
    end

    f:Show()

    return f
end

do -- this function supposed to be called from layout switchers
    function Aptechka:SetGrowth(unitGrowth, groupGrowth)
        if config.useGroupAnchors then return end

        local anchorpoint = self:SetAnchorpoint(unitGrowth, groupGrowth)

        local xgap = AptechkaDB.profile.unitGap or config.unitGap
        local ygap = AptechkaDB.profile.unitGap or config.unitGap
        local unitgr = reverse(unitGrowth)
        if unitgr == "RIGHT" then
            xgap = -xgap
        elseif unitgr == "TOP" then
            ygap = -ygap
        end

        for group,hdr in ipairs(group_headers) do
            for _,button in ipairs{ hdr:GetChildren() } do -- group header doesn't clear points when attribute value changes
                button:ClearAllPoints()
            end
            hdr:SetAttribute("point", unitgr)
            hdr:SetAttribute("xOffset", xgap)
            hdr:SetAttribute("yOffset", ygap)
            local petgroup = hdr.isPetGroup

            hdr:ClearAllPoints()
            if group == 1 then
                hdr:SetPoint(anchorpoint, anchors[group], reverse(anchorpoint),0,0)
            elseif petgroup then
                hdr:SetPoint(arrangeHeaders(group_headers[1], nil, unitGrowth, reverse(groupGrowth)))
            else
                hdr:SetPoint(arrangeHeaders(group_headers[group-1], nil, unitGrowth, groupGrowth))
            end
        end
    end
end

function Aptechka:SetAnchorpoint(unitGrowth, groupGrowth)
    local ug = unitGrowth or config.unitGrowth
    local gg = groupGrowth or config.groupGrowth
    local rug, ud = reverse(ug)
    local rgg, gd = reverse(gg)
    if config.useGroupAnchors then return rug
    elseif ud == gd then return rug
    elseif gd == "VERTICAL" and ud == "HORIZONTAL" then return rgg..rug
    elseif ud == "VERTICAL" and gd == "HORIZONTAL" then return rug..rgg
    end
end

function Aptechka:GetSpecRole()
    local role = AptechkaDB_Char.forcedClassicRole
    if role ~= "HEALER" then role = "DAMAGER" end
    return role
end

function Aptechka:RepositionAnchor()
    -- local role = self:GetSpecRole()
    local anchorTable = AptechkaDB.profile
    anchors[1].san = anchorTable
    local san = anchorTable
    anchors[1]:ClearAllPoints()
    anchors[1]:SetPoint(san.point,UIParent,san.point,san.x,san.y)
end

function Aptechka.CreateAnchor(self,hdr,num)
    local f = CreateFrame("Frame","NugRaidAnchor"..num,UIParent)

    f:SetHeight(20)
    f:SetWidth(20)

    local t = f:CreateTexture(nil,"BACKGROUND")
    t:SetTexture("Interface\\Buttons\\UI-RadioButton")
    t:SetTexCoord(0,0.25,0,1)
    t:SetAllPoints(f)

    t = f:CreateTexture(nil,"BACKGROUND")
    t:SetTexture("Interface\\Buttons\\UI-RadioButton")
    t:SetTexCoord(0.25,0.49,0,1)
    if num == 1 then t:SetVertexColor(1, 0, 0)
    elseif num == 9 then t:SetVertexColor(1, 0.6, 0)
    else t:SetVertexColor(0, 1, 0) end
    t:SetAllPoints(f)

    f:RegisterForDrag("LeftButton")
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetFrameStrata("HIGH")

    hdr:SetPoint(config.anchorpoint,f,reverse(config.anchorpoint),0,0)
    anchors[num] = f
    f:Hide()
    self:RepositionAnchor()

    f:SetScript("OnDragStart",function(self) self:StartMoving() end)
    f:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing();
        _,_, self.san.point, self.san.x, self.san.y = self:GetPoint(1)
    end)
end

local onenter = function(self)
    if self.OnMouseEnterFunc then self:OnMouseEnterFunc() end
    if AptechkaDB.global.disableTooltip or UnitAffectingCombat("player") then return end
    UnitFrame_OnEnter(self)
    self:SetScript("OnUpdate", UnitFrame_OnUpdate)
end
local onleave = function(self)
    if self.OnMouseLeaveFunc then self:OnMouseLeaveFunc() end
    UnitFrame_OnLeave(self)
    self:SetScript("OnUpdate", nil)
end

function Aptechka.SetupFrame(header, frameName)
    local f = _G[frameName]

    local width = pixelperfect(AptechkaDB.profile.width or config.width)
    local height = pixelperfect(AptechkaDB.profile.height or config.height)
    if not InCombatLockdown() then
        -- this is only for classic, because its SGH doesn't have _initialAttributeNames
        f:SetAttribute("_onenter",[[
            local snippet = self:GetAttribute('clickcast_onenter'); if snippet then self:Run(snippet) end
            self:CallMethod("onenter")
        ]])

        f:SetAttribute("_onleave",[[
            local snippet = self:GetAttribute('clickcast_onleave'); if snippet then self:Run(snippet) end
            self:CallMethod("onleave")
        ]])
    else
        Aptechka:ReconfigureProtected()
    end

    if not InCombatLockdown() then
        f:SetSize(width, height)
    end

    f.onenter = onenter
    f.onleave = onleave

    if AptechkaDB.global.RMBClickthrough then
        -- Another way of doing this:
        -- f:RegisterForClicks("AnyUp", "RightButtonDown")
        -- And then in button setup
        -- self:SetAttribute("type2","macro")
        -- self:SetAttribute("macrotext2", "/script MouselookStart()"
        -- But click on mouse down screws up unit's menu
        -- And using OnMouseDown allows it to still work with Clique, only breaking the nomodifier-RMB bind

        f:SetScript("OnMouseDown", function(self, button)
            if not IsModifierKeyDown() then
                if button == "RightButton" then
                    MouselookStart()
                -- elseif LMBClickThrough and button == "LeftButton" then
                --     MouselookStart()
                end
            end
        end)

        -- f:SetScript("OnMouseUp", function(self, button)
        --     print(GetTime(), "OnMouseUp", self:GetName(), button)
        --     if RMBClickthrough and button == "RightButton" then
        --         if (IsMouselooking()) then MouselookStop() end
        --     elseif LMBClickThrough and button == "LeftButton" then
        --         if (IsMouselooking()) then MouselookStop() end
        --     end
        -- end)
    end

    f:RegisterForClicks(unpack(config.registerForClicks))
    f.vHealthMax = 1
    f.vHealth = 1


    f.activeAuras = {}

    config.GridSkin(f)

    f:ReconfigureUnitFrame()
    if Aptechka.PostFrameCreate then
        Aptechka.PostFrameCreate(f)
    end
    if Aptechka.PostFrameUpdate then
        Aptechka.PostFrameUpdate(f)
    end

    f.self = f
    f.HideFunc = f.HideFunc or Aptechka.DummyFunction

    if config.disableManaBar or not f.power then
        Aptechka:UnregisterEvent("UNIT_POWER_UPDATE")
        Aptechka:UnregisterEvent("UNIT_MAXPOWER")
        Aptechka:UnregisterEvent("UNIT_DISPLAYPOWER")
        if f.power and f.power.OnPowerTypeChange then f.power:OnPowerTypeChange("none") end
        f.power = nil
    end

    if f.raidicon then
        f.raidicon.texture:SetTexture[[Interface\TargetingFrame\UI-RaidTargetingIcons]]
    end

    f:HookScript("OnAttributeChanged", OnAttributeChanged)
end

local AssignToSlot = function(frame, opts, status, slot, ...)
    local self = frame[slot]
    if not self then
        if frame._optional_widgets[slot] then
            frame[slot] = frame._optional_widgets[slot](frame)
            self = frame[slot]
        end
    end
    if self then
            -- short exit if disabling auras on already empty widget
            if not self.currentJob and status == false then return end

            local jobs = self.jobs
            if not jobs then
                self.jobs = {}
                jobs = self.jobs
            end

            if status then
                jobs[opts.name] = opts
                if opts.realID and not opts.isMissing then
                    frame.activeAuras[opts.realID] = opts
                end
            else
                jobs[opts.name] = nil
            end

            if next(jobs) then
                local max
                if not self.rawAssignments then
                    local max_priority = 0
                    for name, opts in pairs(jobs) do
                        local opts_priority = opts.priority or 80
                        if max_priority < opts_priority then
                            max_priority = opts_priority
                            max = name
                        end
                    end
                    self.currentJob = jobs[max] -- important that it's before SetJob
                else
                    max = opts.name
                end
                if self ~= frame then self:Show() end   -- taint if we show protected unitbutton frame
                if self.SetJob  then self:SetJob(jobs[max], ...) end
            else
                if self.rawAssignments then self:SetJob(opts, ...) end
                if self.HideFunc then self:HideFunc() else self:Hide() end
                self.currentJob = nil
            end
    end
end

function Aptechka.FrameSetJob(frame, opts, status, ...)
    if opts and opts.assignto then
        if type(opts.assignto) == "string" then
            AssignToSlot(frame, opts, status, opts.assignto, ...)
        else
            for _, slot in ipairs(opts.assignto) do
                AssignToSlot(frame, opts, status, slot, ...)
            end
        end
    end
end
FrameSetJob = Aptechka.FrameSetJob

function Aptechka.SetJob(unit, opts, status, ...)
    if not Roster[unit] then return end
    for frame in pairs(Roster[unit]) do
        FrameSetJob(frame, opts, status, ...)
    end
end
SetJob = Aptechka.SetJob

local GetRealID = function(id) return type(id) == "table" and id[1] or id end
-----------------------
-- AURAS
-----------------------

local function SetDebuffIcon(unit, index, debuffType, expirationTime, duration, icon, count, isBossAura)
    local frames = Roster[unit]
    if not frames then return end

    for frame in pairs(frames) do
        local iconFrame = frame.debuffIcons[index]
        if debuffType == false then
            iconFrame:Hide()
        else
            iconFrame:SetJob(debuffType, expirationTime, duration, icon, count, isBossAura)
            iconFrame:Show()
        end
    end
end


local encountered = {}

local function IndicatorAurasProc(unit, index, slot, filter, name, icon, count, debuffType, duration, expirationTime, caster, isStealable, nameplateShowSelf, spellID )
    -- local name, icon, count, _, duration, expirationTime, caster, _,_, spellID = UnitAura(unit, i, auraType)

    local opts = auras[spellID] or loadedAuras[spellID]
    if opts and not opts.disabled then
        if caster == "player" or not opts.isMine then
            local realID = GetRealID(opts.id)
            opts.realID = realID

            encountered[realID] = opts

            local status = true
            if opts.isMissing then status = false end

            if opts.stackcolor then
                opts.color = opts.stackcolor[count]
            end
            if opts.foreigncolor then
                opts.isforeign = (caster ~= "player")
            end
            opts.expirationTime = expirationTime
            local minduration = opts.extend_below
            if minduration and opts.duration and duration < minduration then
                duration = opts.duration
            end
            opts.duration = duration
            opts.texture = opts.texture or icon
            opts.stacks = count
            SetJob(unit, opts, status)
        end
    end
end

local function IndicatorAurasPostUpdate(unit)
    local frames = Roster[unit]
    if frames then
        for frame in pairs(frames) do
            for realID, opts in pairs(frame.activeAuras) do
                if not encountered[realID] then
                    FrameSetJob(frame, opts, false)
                    frame.activeAuras[realID] = nil
                end
            end
            for optsMissing in pairs(missingFlagSpells) do
                local isPresent
                for spellID, opts in pairs(encountered) do
                    if optsMissing == opts then
                        isPresent = true
                        break
                    end
                end
                if not isPresent then
                    local isKnown = true
                    if optsMissing.isKnownCheck then
                        isKnown = optsMissing.isKnownCheck()
                    end
                    if isKnown then
                        FrameSetJob(frame, optsMissing, true)
                    end
                end
            end
        end
    end
end

-----------------------
-- Debuff Handling
-----------------------

local debuffList = {}
local sortfunc = function(a,b)
    return a[2] > b[2]
end
local visType = "RAID_OUTOFCOMBAT"

local function UtilShouldDisplayDebuff(spellId, unitCaster, visType)
    if spellId == 212183 then -- smoke bomb
        local reaction = unitCaster and UnitReaction("player", unitCaster) or 0
        return reaction <= 4 -- display enemy smoke bomb, hide friendly
    end
    local hasCustom, alwaysShowMine, showForMySpec = SpellGetVisibilityInfo(spellId, visType);
    if ( hasCustom ) then
        return showForMySpec or (alwaysShowMine and (unitCaster == "player" or unitCaster == "pet" or unitCaster == "vehicle") );	--Would only be "mine" in the case of something like forbearance.
    else
        return true;
    end
end

local function SpellLocksProc(unit)
    -- local spellLocked = LibSpellLocks:GetSpellLockInfo(unit)
    local spellID, name, icon, duration, expirationTime = LibSpellLocks:GetSpellLockInfo(unit)
    if spellID then
        tinsert(debuffList, { -1, LibAuraTypes.GetAuraTypePriority("SILENCE", "ALLY")})
    end
end

---------------------------
-- Ordered
---------------------------
local BITMASK_DISEASE = helpers.BITMASK_DISEASE
local BITMASK_POISON = helpers.BITMASK_POISON
local BITMASK_CURSE = helpers.BITMASK_CURSE
local BITMASK_MAGIC = helpers.BITMASK_MAGIC
local function GetDebuffTypeBitmask(debuffType)
    if debuffType == "Magic" then
        return BITMASK_MAGIC
    elseif debuffType == "Poison" then
        return BITMASK_POISON
    elseif debuffType == "Disease" then
        return BITMASK_DISEASE
    elseif debuffType == "Curse" then
        return BITMASK_CURSE
    end
    return 0
end

function Aptechka.OrderedDebuffProc(unit, index, slot, filter, name, icon, count, debuffType, duration, expirationTime, caster, isStealable, nameplateShowSelf, spellID, canApplyAura, isBossAura)
    if UtilShouldDisplayDebuff(spellID, caster, visType) and not blacklist[spellID] then
        local prio, spellType = LibAuraTypes.GetAuraInfo(spellID, "ALLY")
        if not prio then
            prio = (isBossAura and 60) or 0
        end
        if debuffType then
            local mask = GetDebuffTypeBitmask(debuffType)
            if bit_band( mask, BITMASK_DISPELLABLE ) > 0 then
                prio = prio + 15
            end
        end
        tinsert(debuffList, { slot or index, prio, filter })
        -- tinsert(debuffList, { index, prio, name, icon, count, debuffType, duration, expirationTime, caster, isStealable, nameplateShowSelf, spellID, canApplyAura, isBossAura })
        return 1
    end
    return 0
end

function Aptechka.OrderedBuffProc(unit, index, slot, filter, name, icon, count, debuffType, duration, expirationTime, caster, isStealable, nameplateShowSelf, spellID, canApplyAura, isBossAura)
    if isBossAura and not blacklist[spellID] then
        local prio = 60
        tinsert(debuffList, { slot or index, prio, filter })
        return 1
    end
    return 0
end

function Aptechka.OrderedDebuffPostUpdate(unit)
    local debuffLineLength = debuffLimit
    local shown = 0
    local fill = 0

    if LibSpellLocks then
        SpellLocksProc(unit)
    end

    tsort(debuffList, sortfunc)

    for i, debuffIndexCont in ipairs(debuffList) do
        local indexOrSlot, prio, auraFilter = unpack(debuffIndexCont)
        local name, icon, count, debuffType, duration, expirationTime, caster, _,_, spellID, canApplyAura, isBossAura
        if indexOrSlot >= 0 then
            name, icon, count, debuffType, duration, expirationTime, caster, _,_, spellID, canApplyAura, isBossAura = UnitAura(unit, indexOrSlot, auraFilter)
            if auraFilter == "HELPFUL" then
                debuffType = "Helpful"
            end
            -- name, icon, count, debuffType, duration, expirationTime, caster, _,_, spellID, canApplyAura, isBossAura = UnitAuraBySlot(unit, indexOrSlot)
            if prio >= 50 then -- 50 is roots
                isBossAura = true
            end
        else
            spellID, name, icon, duration, expirationTime = LibSpellLocks:GetSpellLockInfo(unit)
            count = 0
            isBossAura = true
        end

        fill = fill + (isBossAura and AptechkaDB.profile.debuffBossScale or 1)

        if fill <= debuffLineLength then
            shown = shown + 1
            SetDebuffIcon(unit, shown, debuffType, expirationTime, duration, icon, count, isBossAura)
        else
            break
        end
    end

    for i=shown+1, debuffLineLength do
        SetDebuffIcon(unit, i, false)
    end
end

---------------------------
-- Simple
---------------------------
function Aptechka.SimpleDebuffProc(unit, index, slot, filter, name, icon, count, debuffType, duration, expirationTime, caster, isStealable, nameplateShowSelf, spellID, canApplyAura, isBossAura)
    if UtilShouldDisplayDebuff(spellID, caster, visType) and not blacklist[spellID] then
        if isBossAura then
            tinsert(debuffList, 1, slot or index)
        else
            tinsert(debuffList, slot or index)
        end
    end
end

function Aptechka.SimpleBuffProc(unit, index, slot, filter, name, icon, count, debuffType, duration, expirationTime, caster, isStealable, nameplateShowSelf, spellID, canApplyAura, isBossAura)
    -- Uncommen when moving to Slot API
    -- if isBossAura and not blacklist[spellID] then
    --     tinsert(debuffList, 1, slot or index)
    -- end
end

function Aptechka.SimpleDebuffPostUpdate(unit)
    local shown = 0
    local fill = 0
    local debuffLineLength = debuffLimit

    for i, indexOrSlot in ipairs(debuffList) do
        local name, icon, count, debuffType, duration, expirationTime, caster, _,_, spellID, canApplyAura, isBossAura = UnitAura(unit, indexOrSlot, "HARMFUL")
        -- local name, icon, count, debuffType, duration, expirationTime, caster, _,_, spellID, canApplyAura, isBossAura = UnitAuraBySlot(unit, indexOrSlot)

        fill = fill + (isBossAura and AptechkaDB.profile.debuffBossScale or 1)

        if fill <= debuffLineLength then
            shown = shown + 1
            SetDebuffIcon(unit, shown, debuffType, expirationTime, duration, icon, count, isBossAura)
        else
            break
        end
    end

    for i=shown+1, debuffLineLength do
        SetDebuffIcon(unit, i, false)
    end
end

---------------------------
-- Dispel Type Indicator
---------------------------
local debuffTypeMask -- Resets to 0 at the start of every aura scan
function Aptechka.DispelTypeProc(unit, index, slot, filter, name, icon, count, debuffType)
    debuffTypeMask = bit_bor( debuffTypeMask,  GetDebuffTypeBitmask(debuffType))
end

local MagicColor = { 0.2, 0.6, 1}
local CurseColor = { 0.6, 0, 1}
local PoisonColor = { 0, 0.6, 0}
local DiseaseColor = { 0.6, 0.4, 0}
function Aptechka.DispelTypePostUpdate(unit)
    local debuffTypeMaskDispellable = bit_band( debuffTypeMask, BITMASK_DISPELLABLE )

    local frames = Roster[unit]
    if frames then
        for frame in pairs(frames) do
            if frame.debuffTypeMask ~= debuffTypeMaskDispellable then

                local color
                -- local debuffType
                if bit_band(debuffTypeMaskDispellable, BITMASK_MAGIC) > 0 then
                    color = MagicColor
                    -- debuffType = 1
                elseif bit_band(debuffTypeMaskDispellable, BITMASK_POISON) > 0 then
                    color = PoisonColor
                    -- debuffType = 2
                elseif bit_band(debuffTypeMaskDispellable, BITMASK_DISEASE) > 0 then
                    color = DiseaseColor
                    -- debuffType = 3
                elseif bit_band(debuffTypeMaskDispellable, BITMASK_CURSE) > 0 then
                    color = CurseColor
                    -- debuffType = 4
                end

                if color then
                    config.DispelStatus.color = color
                    -- config.DispelStatus.debuffType = debuffType
                    FrameSetJob(frame, config.DispelStatus, true) --, debuffType)
                else
                    FrameSetJob(frame, config.DispelStatus, false)
                end

                frame.debuffTypeMask = debuffTypeMaskDispellable
            end
        end
    end
end
function Aptechka.DummyFunction() end

local handleBuffs = function(unit, index, slot, filter, ...)
    IndicatorAurasProc(unit, index, slot, filter, ...)
    BuffProc(unit, index, slot, filter, ...)
end

local handleDebuffs = function(unit, index, slot, filter, ...)
    IndicatorAurasProc(unit, index, slot, filter, ...)
    DebuffProc(unit, index, slot, filter, ...)
    DispelTypeProc(unit, index, slot, filter, ...)
end

function Aptechka.ScanAuras(unit)
    -- indicator cleanup
    table_wipe(encountered)
    debuffTypeMask = 0
    -- debuffs cleanup
    table_wipe(debuffList)


    visType = UnitAffectingCombat("player") and "RAID_INCOMBAT" or "RAID_OUTOFCOMBAT"

    -- Old API
    local filter = "HELPFUL"
    for i=1,100 do
        local name, icon, count, debuffType, duration, expirationTime, caster, isStealable, nameplateShowSelf, spellID, canApplyAura, isBossAura = UnitAura(unit, i, filter)
        if not name then break end
        handleBuffs(unit, i, nil, filter, name, icon, count, debuffType, duration, expirationTime, caster, isStealable, nameplateShowSelf, spellID, canApplyAura, isBossAura)
    end

    filter = "HARMFUL"
    for numDebuffs=1,100 do
        local name, icon, count, debuffType, duration, expirationTime, caster, isStealable, nameplateShowSelf, spellID, canApplyAura, isBossAura = UnitAura(unit, numDebuffs, filter)
        if not name then
            -- numDebuffs = numDebuffs-1
            break
        end
        handleDebuffs(unit, numDebuffs, nil, filter, name, icon, count, debuffType, duration, expirationTime, caster, isStealable, nameplateShowSelf, spellID, canApplyAura, isBossAura)
    end

    -- New API
    -- ForEachAura(unit, "HELPFUL", 5, handleBuffs)
    -- ForEachAura(unit, "HARMFUL", 5, handleDebuffs)

    IndicatorAurasPostUpdate(unit)
    DebuffPostUpdate(unit)
    DispelTypePostUpdate(unit)
end
local debugprofilestop = debugprofilestop
function Aptechka.UNIT_AURA(self, event, unit)
    if not Roster[unit] then return end
    -- local beginTime1 = debugprofilestop();
    Aptechka.ScanAuras(unit)
    -- local timeUsed1 = debugprofilestop();
    -- print("ScanAuras", timeUsed1 - beginTime1)
end


function Aptechka:UpdateDebuffScanningMethod()
    local useOrdering = AptechkaDB.global.useDebuffOrdering
    --[[
    if AptechkaDB.global.useDebuffOrdering  then
        local numMembers = GetNumGroupMembers()
        local _, instanceType = GetInstanceInfo()
        local isBattleground = instanceType == "arena" or instanceType == "pvp"
        useOrdering = not IsInRaid() or (isBattleground and numMembers <= 15)
    end
    ]]
    if useOrdering then
        DebuffProc = Aptechka.OrderedDebuffProc
        BuffProc = Aptechka.OrderedBuffProc
        DebuffPostUpdate = Aptechka.OrderedDebuffPostUpdate
    else
        DebuffProc = Aptechka.SimpleDebuffProc
        BuffProc = Aptechka.SimpleBuffProc
        DebuffPostUpdate = Aptechka.SimpleDebuffPostUpdate
    end
    if AptechkaDB.profile.showDispels then
        DispelTypeProc = Aptechka.DispelTypeProc
        DispelTypePostUpdate = Aptechka.DispelTypePostUpdate
    else
        DispelTypeProc = Aptechka.DummyFunction
        DispelTypePostUpdate = Aptechka.DummyFunction
    end
end



function Aptechka.TestDebuffSlots()
    local debuffLineLength = debuffLimit
    local shown = 0
    local fill = 0
    local unit = "player"

    local numBossAuras = math.random(3)-1
    local now = GetTime()
    local debuffTypes = { "none", "Magic", "Poison", "Curse", "Disease" }
    local randomIDs = { 5211, 19577, 172, 408, 15286, 853, 980, 589, 118, 605 }
    for i=1,6 do
        local spellID = randomIDs[math.random(#randomIDs)]
        local _, _, icon = GetSpellInfo(spellID)
        local duration = math.random(20)+5
        local hasCount = math.random(3) == 1
        local count = hasCount and math.random(18) or 0
        local debuffType = debuffTypes[math.random(#debuffTypes)]
        local expirationTime = now + duration
        local isBossAura = shown < numBossAuras
        fill = fill + (isBossAura and AptechkaDB.profile.debuffBossScale or 1)

        -- print(fill, debuffLineLength, fill < debuffLineLength)

        if fill <= debuffLineLength then
            shown = shown + 1
            SetDebuffIcon(unit, shown, debuffType, expirationTime, duration, icon, count, isBossAura)
        else
            break
        end
    end

    -- if Roster[unit] then
    --     for frame in pairs(Roster[unit]) do
    --         local icon = frame.castIcon
    --         local spellID = randomIDs[math.random(#randomIDs)]
    --         local _, _, texture = GetSpellInfo(spellID)
    --         local startTime = now
    --         local duration = math.random(20)+5
    --         local endTime = startTime + duration
    --         local count = math.random(18)
    --         local castType = "CAST"
    --         icon.texture:SetTexture(texture)
    --         icon.cd:SetReverse(castType == "CAST")

    --         local r,g,b = 1, 0.65, 0

    --         icon.cd:SetSwipeColor(r,g,b);

    --         local duration = endTime - startTime
    --         icon.cd:SetCooldown(startTime, duration)
    --         icon.cd:Show()

    --         icon.stacktext:SetText(count > 1 and count)
    --         icon:Show()
    --     end
    -- end

    for i=shown+1, debuffLineLength do
        SetDebuffIcon(unit, i, false)
    end
end

local ParseOpts = function(str)
    local t = {}
    local capture = function(k,v)
        t[k:lower()] = tonumber(v) or v
        return ""
    end
    str:gsub("(%w+)%s*=%s*%[%[(.-)%]%]", capture):gsub("(%w+)%s*=%s*(%S+)", capture)
    return t
end
function Aptechka:PrintReloadUIWarning()
    print(Aptechka.L"Aptechka: Changes will effect after /reload")
    -- print("|cffffffff|Hgarrmission:APTECHKAReload:|h[/reload]|h|r")
end
-- hooksecurefunc("SetItemRef", function(link, text)
--     local _, linkType = strsplit(":", link)
--     if linkType == "APTECHKAReload" then
--         ReloadUI()
--     end
-- end)
Aptechka.Commands = {
    ["unlockall"] = function()
        for _,anchor in pairs(anchors) do
            anchor:Show()
        end
    end,
    ["unlock"] = function()
        anchors[1]:Show()
    end,
    ["lock"] = function()
        for _,anchor in pairs(anchors) do
            anchor:Hide()
        end
    end,
    ["gui"] = function(v)
        if not IsAddOnLoaded("AptechkaOptions") then
            LoadAddOn("AptechkaOptions")
        end
        InterfaceOptionsFrame_OpenToCategory("Aptechka")
        InterfaceOptionsFrame_OpenToCategory("Aptechka")
    end,
    ["reset"] = function()
        anchors[1].san.point = "CENTER"
        anchors[1].san.x = 0
        anchors[1].san.y = 0
        anchors[1]:ClearAllPoints()
        anchors[1]:SetPoint(anchors[1].san.point, UIParent, anchors[1].san.point, anchors[1].san.x, anchors[1].san.y)
    end,
    ["togglegroup"] = function(v)
        local group = tonumber(v)
        if group then
            local hdr = group_headers[group]
            if hdr:IsVisible() then
                hdr:Hide()
            else
                hdr:Show()
            end
        end
    end,
    ["setrole"] = function(v)
        v = string.upper(v)
        if v == "HEALER" then
            AptechkaDB_Char.forcedClassicRole = v
        else
            AptechkaDB_Char.forcedClassicRole = "DAMAGER"
        end
        print("Role changed to", AptechkaDB_Char.forcedClassicRole)
        Aptechka:OnRoleChanged()
    end,
    ["createpets"] = function()
        if not AptechkaDB.profile.petGroup then
            if not InCombatLockdown() then
                Aptechka:CreatePetGroup()
            else
                local f = CreateFrame('Frame')
                f:SetScript("OnEvent",function(self)
                    Aptechka:CreatePetGroup()
                    self:SetScript("OnEvent",nil)
                end)
                f:RegisterEvent("PLAYER_REGEN_ENABLED")
            end
        end
    end,
    ["show"] = function()
        for i,hdr in pairs(group_headers) do
            hdr:Show()
        end
    end,
    ["hide"] = function()
        for i,hdr in pairs(group_headers) do
            hdr:Hide()
        end
    end,
    ["spells"] = function()
        print("=== Spells ===")
        local spellset = AptechkaUserConfig.auras or AptechkaDefaultConfig.auras
        for spellName,opts in pairs(spellset) do
            local format = string.find(opts.type,"HARMFUL") and "|cffff7777%s|r" or "|cff77ff77%s|r"
            print(string.format(format,spellName))
        end
    end,
    ["load"] = function(v)
        local add = config.LoadableDebuffs[v]
        if v == "" then
            print("Spell sets:")
            for k,v in pairs(config.LoadableDebuffs) do
                print(k)
            end return
        end
        if add then
            if loaded[v] then return end
            add()
            print(AptechkaString..v.." loaded.")
            loaded[v] = true
        else
            print(AptechkaString..v.." doesn't exist")
        end
    end,
    ["setpos"] = function(v)
        local fields = ParseOpts(v)
        if not next(fields) then print("Usage: /apt setpos point=center x=0 y=0") return end
        local point,x,y = string.upper(fields['point'] or "CENTER"), fields['x'] or 0, fields['y'] or 0
        anchors[1].san.point = point
        anchors[1].san.x = x
        anchors[1].san.y = y
        anchors[1]:ClearAllPoints()
        anchors[1]:SetPoint(point, UIParent, point, x, y)
    end,
    -- ["charspec"] = function()
    --     local user = UnitName("player").."@"..GetRealmName()
    --     if AptechkaDB_Global.charspec[user] then AptechkaDB_Global.charspec[user] = nil
    --     else AptechkaDB_Global.charspec[user] = true
    --     end
    --     print (AptechkaString..(AptechkaDB_Global.charspec[user] and "Enabled" or "Disabled").." character specific options for this toon. Will take effect after ui reload",0.7,1,0.7)
    -- end,
    ["listauras"] = function(v)
        local unit = v
        local h = false
        for i=1, 100 do
            local name, _,_,_,duration,_,_,_,_, spellID = UnitAura(unit, i, "HELPFUL")
            if not name then break end
            if not h then print("BUFFS:"); h = true; end
            print(string.format("    %s (id: %d) Duration: %s", name, spellID, duration or "none" ))
        end
        h = false
        for i=1, 100 do
            local name, _,_,_,duration,_,_,_,_, spellID = UnitAura(unit, i, "HARMFUL")
            if not name then break end
            if not h then print("DEBUFFS:"); h = true; end
            print(string.format("    %s (id: %d) Duration: %s", name, spellID, duration or "none" ))
        end

    end,
    ["blacklist"] = function(v)
        local cmd,args = string.match(v, "([%w%-]+) ?(.*)")
        if cmd == "add" then
            local spellID = tonumber(args)
            if spellID then
                blacklist[spellID] = true
                local spellName = GetSpellInfo(spellID) or "<Unknown spell>"
                print(string.format("%s (%d) added to debuff blacklist", spellName, spellID))
            end
        elseif cmd == "del" then
            local spellID = tonumber(args)
            if spellID then
                local val = nil
                if default_blacklist[spellID] then val = false end -- if nil it'll fallback on __index
                blacklist[spellID] = val
                local spellName = GetSpellInfo(spellID) or "<Unknown spell>"
                print(string.format("%s (%d) removed from debuff blacklist", spellName, spellID))
            end
        else
            print("Default blacklist:")
            for spellID in pairs(default_blacklist) do
                local spellName = GetSpellInfo(spellID) or "<Unknown spell>"
                print(string.format("    %s (%d)", spellName, spellID))
            end
            print("Custom blacklist:")
            for spellID in pairs(blacklist) do
                local spellName = GetSpellInfo(spellID) or "<Unknown spell>"
                print(string.format("    %s (%d)", spellName, spellID))
            end
        end
    end,
}
function Aptechka.SlashCmd(msg)
    local k,v = string.match(msg, "([%w%+%-%=]+) ?(.*)")
    if not k or k == "help" then print([=[Usage:
      |cff00ff00/aptechka|r lock
      |cff00ff00/aptechka|r unlock
      |cff00ff00/aptechka|r gui
      |cff00ff00/aptechka|r reset|r
      |cff00ff00/aptechka|r createpets
      |cff00ff00/aptechka|r blacklist add <spellID>
      |cff00ff00/aptechka|r blacklist del <spellID>
      |cff00ff00/aptechka|r blacklist show
    ]=]
    )end

    if Aptechka.Commands[k] then
        Aptechka.Commands[k](v)
    end
end

local PARTY_CHAT = Enum.ChatChannelType.Private_Party
local INSTANCE_CHAT = Enum.ChatChannelType.Public_Party
function Aptechka:VOICE_CHAT_CHANNEL_ACTIVATED(event)
    local channelType = C_VoiceChat.GetActiveChannelType()
    if channelType == PARTY_CHAT or channelType == INSTANCE_CHAT then
        self:RegisterEvent("VOICE_CHAT_CHANNEL_MEMBER_SPEAKING_STATE_CHANGED")
    else
        self:UnregisterEvent("VOICE_CHAT_CHANNEL_MEMBER_SPEAKING_STATE_CHANGED")
    end
end

function Aptechka:VOICE_CHAT_CHANNEL_DEACTIVATED(event, channelID)
    self:UnregisterEvent("VOICE_CHAT_CHANNEL_MEMBER_SPEAKING_STATE_CHANGED")
end

function Aptechka:VOICE_CHAT_CHANNEL_MEMBER_SPEAKING_STATE_CHANGED(event, memberID, channelID, isSpeaking)
    local guid = C_VoiceChat.GetMemberGUID(memberID, channelID)
    local unit = guidMap[guid]
    if unit then
        SetJob(unit, config.VoiceChatStatus, isSpeaking)
    end
end


function Aptechka:UpdateCastsConfig()
    LibTargetedCasts = LibStub("LibTargetedCasts", true)
    if LibTargetedCasts then
        if AptechkaDB.profile.showCasts then
            LibTargetedCasts.RegisterCallback("Aptechka", "SPELLCAST_UPDATE", Aptechka.SPELLCAST_UPDATE)
        else
            LibTargetedCasts.UnregisterCallback("Aptechka", "SPELLCAST_UPDATE")

            if self.isInitialized then
                self:ForEachFrame(function(self)
                    self.castIcon:Hide()
                end)
            end
        end
    end
end
function Aptechka.SPELLCAST_UPDATE(event, GUID)
    local unit = guidMap[GUID]
    if unit and Roster[unit] then
        for frame in pairs(Roster[unit]) do
            local minSrcGUID
            local minTime
            local totalCasts = 0
            for i, castInfo in ipairs(LibTargetedCasts:GetUnitIncomingCastsTable(unit)) do
                local srcGUID, dstGUID, castType, name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible, spellID = unpack(castInfo)

                local isImportant = importantTargetedCasts[spellID]
                if not blacklist[spellID] then
                    totalCasts = totalCasts + 1
                    if castType == "CHANNEL" then endTime = endTime - 5 end -- prioritizing channels
                    if isImportant then endTime = endTime - 100 end

                    if not minTime or endTime < minTime then
                        minSrcGUID = srcGUID
                        minTime = endTime
                        -- print(i)
                    end
                end
            end

            local icon = frame.castIcon
            if minSrcGUID then
                local srcGUID, dstGUID, castType, name, text, texture, startTime, endTime, isTradeSkill, castID, notInterruptible, spellID = LibTargetedCasts:GetCastInfoBySourceGUID(minSrcGUID)

                icon.texture:SetTexture(texture)
                icon.cd:SetReverse(castType == "CAST")

                local r,g,b
                -- if notInterruptible then
                --     r,g,b = 0.7, 0.7, 0.7
                -- else
                if castType == "CHANNEL" then
                    r,g,b = 0.8, 1, 0.3
                else
                    r,g,b = 1, 0.65, 0
                end

                icon.cd:SetSwipeColor(r,g,b);

                local duration = endTime - startTime
                icon.cd:SetCooldown(startTime, duration)
                icon.cd:Show()

                icon.stacktext:SetText(totalCasts > 1 and totalCasts)

                icon:Show()
            else
                icon:Hide()
            end
        end
    end
end

do
    local CURRENT_DB_VERSION = 2
    function Aptechka:DoMigrations(db)
        if not next(db) or db.DB_VERSION == CURRENT_DB_VERSION then -- skip if db is empty or current
            db.DB_VERSION = CURRENT_DB_VERSION
            return
        end

        if db.DB_VERSION == nil then
            if not db.roleProfile then
                db.roleProfile = {}
            end
            if db["GridSkin"] then
                local oldAnchorData = db["GridSkin"][1]
                db.roleProfile.DAMAGER = oldAnchorData
                db.roleProfile.HEALER = oldAnchorData
                db.GridSkin = nil
            end
            if db.autoscale then
                db.roleProfile.DAMAGER.scaleMediumRaid = db.autoscale.damageMediumRaid
                db.roleProfile.DAMAGER.scaleBigRaid = db.autoscale.damageBigRaid
                db.roleProfile.HEALER.scaleMediumRaid = db.autoscale.healerMediumRaid
                db.roleProfile.HEALER.scaleBigRaid = db.autoscale.healerBigRaid
                db.autoscale = nil
            end

            db.DB_VERSION = 1
        end

        if db.DB_VERSION == 1 then
            db.global = {}
            db.global.disableBlizzardParty = db.disableBlizzardParty
            db.global.hideBlizzardRaid = db.hideBlizzardRaid
            db.global.RMBClickthrough = db.RMBClickthrough
            db.global.sortUnitsByRole = db.sortUnitsByRole
            db.global.showAFK = db.showAFK
            db.global.customBlacklist = db.customBlacklist
            db.global.useCombatLogHealthUpdates = db.useCombatLogHealthUpdates
            db.global.disableTooltip = db.disableTooltip
            db.global.useDebuffOrdering = db.useDebuffOrdering

            db.profiles = {
                Default = {}
            }
            local default_profile = db.profiles["Default"]
            default_profile.width = db.width
            default_profile.height = db.height
            default_profile.healthOrientation = db.healthOrientation
            default_profile.unitGrowth = db.unitGrowth
            default_profile.groupGrowth = db.groupGrowth
            default_profile.unitGap = db.unitGap
            default_profile.groupGap = db.groupGap
            default_profile.showSolo = db.showSolo
            default_profile.showParty = db.showParty
            default_profile.cropNamesLen = db.cropNamesLen
            default_profile.showCasts = db.showCasts
            default_profile.showAggro = db.showAggro
            default_profile.petGroup = db.petGroup
            default_profile.showRaidIcons = db.showRaidIcons
            default_profile.showDispels = db.showDispels
            default_profile.healthTexture = db.healthTexture
            default_profile.powerTexture = db.powerTexture

            default_profile.scale = db.scale
            default_profile.debuffSize = db.debuffSize
            default_profile.debuffLimit = db.debuffLimit
            default_profile.debuffBossScale = db.debuffBossScale
            default_profile.stackFontName = db.stackFontName
            default_profile.stackFontSize = db.stackFontSize
            default_profile.nameFontName = db.nameFontName
            default_profile.nameFontSize = db.nameFontSize
            default_profile.nameFontOutline = db.nameFontOutline
            default_profile.nameColorMultiplier = db.nameColorMultiplier
            default_profile.fgShowMissing = db.fgShowMissing
            default_profile.fgColorMultiplier = db.fgColorMultiplier
            default_profile.bgColorMultiplier = db.bgColorMultiplier

            if db.roleProfile then
                if db.roleProfile["HEALER"] then
                    local old_healer_profile = db.roleProfile["HEALER"]
                    default_profile.point = old_healer_profile.point
                    default_profile.x = old_healer_profile.x
                    default_profile.y = old_healer_profile.y
                end
                if db.useRoleProfiles and db.roleProfile["DAMAGER"] then
                    local old_damager_profile = db.roleProfile["DAMAGER"]
                    -- Create a second profile, copied from our new Default profile
                    db.profiles["DefaultNonHealer"] = CopyTable(default_profile)

                    local default_damager_profile = db.profiles["DefaultNonHealer"]

                    default_damager_profile.point = old_damager_profile.point
                    default_damager_profile.x = old_damager_profile.x
                    default_damager_profile.y = old_damager_profile.y

                    db.global.profileSelection = {
                        DAMAGER = {
                            solo = "DefaultNonHealer",
                            party = "DefaultNonHealer",
                            smallRaid = "DefaultNonHealer",
                            mediumRaid = "DefaultNonHealer",
                            bigRaid = "DefaultNonHealer",
                        },
                    }
                end
            end

            db.disableBlizzardParty = nil
            db.hideBlizzardRaid = nil
            db.RMBClickthrough = nil
            db.sortUnitsByRole = nil
            db.showAFK = nil
            db.customBlacklist = nil
            db.useCombatLogHealthUpdates = nil
            db.disableTooltip = nil
            db.useDebuffOrdering = nil

            db.width = nil
            db.height = nil
            db.healthOrientation = nil
            db.unitGrowth = nil
            db.groupGrowth = nil
            db.unitGap = nil
            db.groupGap = nil
            db.showSolo = nil
            db.showParty = nil
            db.cropNamesLen = nil
            db.showCasts = nil
            db.showAggro = nil
            db.petGroup = nil
            db.showRaidIcons = nil
            db.showDispels = nil
            db.healthTexture = nil
            db.powerTexture = nil
            db.scale = nil
            db.debuffSize = nil
            db.debuffLimit = nil
            db.debuffBossScale = nil
            db.stackFontName = nil
            db.stackFontSize = nil
            db.nameFontName = nil
            db.nameFontSize = nil
            db.nameFontOutline = nil
            db.nameColorMultiplier = nil
            db.fgShowMissing = nil
            db.fgColorMultiplier = nil
            db.bgColorMultiplier = nil

            db.roleProfile = nil
            db.useRoleProfiles = nil

            db.charspec = nil

            db.DB_VERSION = 2
        end
    end
end
