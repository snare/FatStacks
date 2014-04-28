-------------------------------------------------------------------------------
-- FatStacks
-- The guild bank management add-on.
--
-- Add-on menu functions
-------------------------------------------------------------------------------

local SN_FS                         = SN_FS
local LAM                           = LibStub("LibAddonMenu-1.0")
local addonMenu                     = LAM:CreateControlPanel(SN_FS.name, SN_FS.name)

-------------------------------------------------------------------------------
-- LoadSettings()
-- Load the add-on's settings
-------------------------------------------------------------------------------
function SN_FS.LoadConfig()
    SN_FS.config = ZO_SavedVars:New(
        SN_FS.savedVariablesName,
        SN_FS.configVersion,
        SN_FS.configNamespace,
        SN_FS.configDefaults,
        profile
    )
end

-------------------------------------------------------------------------------
-- InitAddOnMenu()
-- Initialise the add-on menu
-------------------------------------------------------------------------------
function SN_FS.InitAddOnMenu()
    LAM:AddHeader(addonMenu, "SN_FS_Header", "FatStacks " .. SN_FS.version)
    LAM:AddDescription(addonMenu, "SN_FS_SettingsDescription", "Configuration options for FatStacks.", nil)
    LAM:AddCheckbox(addonMenu,
        "SN_FS_FatStacks_Enabled",
        "Enable FatStacks",
        "Enable or disable FatStacks globally.",
        function () return SN_FS.GetConfigValue("enabled") end,
        function (value) SN_FS.SetConfigValue("enabled", value) end
    )
    LAM:AddCheckbox(addonMenu,
        "SN_FS_FatStacks_Debug",
        "Enable debug logging",
        "Enable or disable debug logging.",
        function () return SN_FS.GetConfigValue("debug") end,
        function (value) SN_FS.SetConfigValue("debug", value) end
    )
    LAM:AddCheckbox(addonMenu,
        "SN_FS_FatStacks_AutoStack",
        "Enable auto-stacking",
        "Enable automatically re-stacking an item when after it is deposited into the guild bank.",
        function () return SN_FS.GetConfigValue("stack_on_insert") end,
        function (value) SN_FS.SetConfigValue("stack_on_insert", value) end
    )
end

-------------------------------------------------------------------------------
-- GetConfigValue()
-- Generic config getter
-------------------------------------------------------------------------------
function SN_FS.GetConfigValue(name)
    return SN_FS.config[name]
end

-------------------------------------------------------------------------------
-- SetConfigValue()
-- Generic config setter
-------------------------------------------------------------------------------
function SN_FS.SetConfigValue(name, value)
    SN_FS.config[name] = value
end
