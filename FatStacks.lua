-------------------------------------------------------------------------------
-- FatStacks by snare
-- The guild bank management add-on.
--
-- Props to Zolan for the advice and borrowed code.
-------------------------------------------------------------------------------

-------------------------------------------------------------------------------
-- Add-on properties
-------------------------------------------------------------------------------
SN_FS                               = {}
local SN_FS                         = SN_FS
SN_FS.name                          = "FatStacks"
SN_FS.description                   = "The guild bank management add-on"
SN_FS.version                       = "0.1.3"
SN_FS.savedVariablesName            = 'SN_FS_SavedVariables'
SN_FS.configVersion                 = 1
SN_FS.configNamespace               = 'SN_FS'
SN_FS.configDefaults = {
    ["configVersion"]               = SN_FS.configVersion,
    ["debug"]                       = false,
    ["stack_on_insert"]             = false
}

-------------------------------------------------------------------------------
-- File-scoped locals
-------------------------------------------------------------------------------

-- Data collection processing
local data                          = {}
local ids                           = {}
local id_index                      = 1

-- Withdrawal queue processing
local withdraw_slots                = {}
local ws_index                      = 1
local wait_slot_id                  = nil

-- Deposit queue processing
local deposit_slots                 = {}
local deposit_slot_id               = 0
local ds_index                      = 1

-- Guild bank is open flag
local gb_open                       = false

-- Debug logging function
local dbg                           = d
local log                           = d

-------------------------------------------------------------------------------
-- Local instances of globals
-- Allegedly this is good for performance or something (avoids repeated global lookups)
-------------------------------------------------------------------------------
local table                         = table
local pairs                         = pairs
local ipairs                        = ipairs

local BAG_BACKPACK                  = BAG_BACKPACK
local BAG_GUILDBANK                 = BAG_GUILDBANK

local EVENT_GUILD_BANK_ITEM_REMOVED = EVENT_GUILD_BANK_ITEM_REMOVED
local EVENT_GUILD_BANK_ITEM_ADDED   = EVENT_GUILD_BANK_ITEM_ADDED
local EVENT_OPEN_GUILD_BANK         = EVENT_OPEN_GUILD_BANK
local EVENT_CLOSE_GUILD_BANK        = EVENT_CLOSE_GUILD_BANK
local EVENT_MANAGER                 = EVENT_MANAGER

-------------------------------------------------------------------------------
-- Main()
-- Main function called by the /fs command
-------------------------------------------------------------------------------
function SN_FS.Main(arg)
    if arg == "" or arg == "help" then
        d("----- FatStacks help -----")
        d("/fs - this help")
        d("/fs info - just get info about the state of the guild bank")
        d("/fs restack - restack the guild bank")
        d("/fs reset - reset FatStacks (use this if you get an error or if FS hangs mid-restack)")
    elseif arg == "restack" then
        SN_FS.RestackGuildBank()
    elseif arg == "reset" then
        d("[FatStacks] Resetting")
        EVENT_MANAGER:UnregisterForEvent(SN_FS.name, EVENT_GUILD_BANK_ITEM_REMOVED, SN_FS.OnGuildBankItemRemoved)
        EVENT_MANAGER:UnregisterForEvent(SN_FS.name, EVENT_GUILD_BANK_ITEM_ADDED,   SN_FS.OnGuildBankItemAdded)
        data = {}
    elseif arg == "info" then
        SN_FS.InspectGuildBank()
    elseif arg == "debug" then
        SN_FS.ToggleDebugLogging()
    else
        d("[FatStacks] No such command: " .. arg)
    end
end

-------------------------------------------------------------------------------
-- Debug()
-- Perform debug logging
-------------------------------------------------------------------------------
function SN_FS.Debug(msg)
    if SN_FS.config["debug"] then
        d(msg)
    end
end

-------------------------------------------------------------------------------
-- Log()
-- Log a message to chat
-------------------------------------------------------------------------------
function SN_FS.Log(msg)
    d(msg)
end

-------------------------------------------------------------------------------
-- OnOpenGuildBank()
-- EVENT_OPEN_GUILD_BANK handler
-------------------------------------------------------------------------------
function SN_FS.OnOpenGuildBank()
    dbg("Opening guild bank")
    gb_open = true
end

-------------------------------------------------------------------------------
-- OnCloseGuildBank()
-- EVENT_CLOSE_GUILD_BANK handler
-------------------------------------------------------------------------------
function SN_FS.OnCloseGuildBank()
    dbg("Closing guild bank")
    gb_open = false
end

-------------------------------------------------------------------------------
-- ToggleDebugLogging()
-- Toggle debug logging
-------------------------------------------------------------------------------
function SN_FS.ToggleDebugLogging()
    -- Toggle the debug enable flag
    SN_FS.config["debug"] = SN_FS.config["debug"] and false or true
end

-------------------------------------------------------------------------------
-- OnGuildBankItemRemoved()
-- EVENT_GUILD_BANK_ITEM_REMOVED handler
-------------------------------------------------------------------------------
function SN_FS.OnGuildBankItemRemoved(bagId, slotId, isNewItem, itemSoundCategory, updateReason)
    local slots

    -- If this is the ID we were waiting for
    if wait_slot_id == slotId then
        if ws_index <= #withdraw_slots then
            -- Haven't finished withdrawing all the slots for this item yet
            SN_FS.NextWithdrawal()
        else
            -- Finished withdrawing all the slots for this item, find the item slot(s) in backpack
            slots = SN_FS.FindItemInBag(ids[id_index], BAG_BACKPACK)

            -- Stack the items we found
            deposit_slots = SN_FS.StackItems(BAG_BACKPACK, slots)

            -- Deposit the first stack in the GB
            ds_index = 1
            SN_FS.NextDeposit()

            -- Wait for notification to call OnGuildBankItemAdded() before depositing the next one
        end
    end
end

-------------------------------------------------------------------------------
-- OnGuildBankItemAdded()
-- EVENT_GUILD_BANK_ITEM_ADDED handler
-------------------------------------------------------------------------------
function SN_FS.OnGuildBankItemAdded(bagId, slotId, isNewItem, itemSoundCategory, updateReason)
    if ds_index <= #deposit_slots then
        -- Haven't finished depositing all the slots for this item yet
        SN_FS.NextDeposit()
    else
        -- Finished depositing all the slots for this item
        -- Increment the index into the IDs array
        id_index = id_index + 1

        -- Do the next restack
        if id_index <= #ids then
            SN_FS.NextRestack()
        else
            log("Finished restacking guild bank")
            EVENT_MANAGER:UnregisterForEvent(SN_FS.name, EVENT_GUILD_BANK_ITEM_REMOVED,  SN_FS.OnGuildBankItemRemoved)
            EVENT_MANAGER:UnregisterForEvent(SN_FS.name, EVENT_GUILD_BANK_ITEM_ADDED,    SN_FS.OnGuildBankItemAdded)
        end
    end
end

-------------------------------------------------------------------------------
-- StackItems()
-- Stack items within the specified bag and slot IDs
-------------------------------------------------------------------------------
function SN_FS.StackItems(bagId, slotIds)
    local move
    local done = false
    local targetIndex = 1
    local sourceIndex = 0
    local target, stack, maxStack, room, slotId

    -- Make sure they're all the same item type
    local id = nil
    for i,slotId in ipairs(slotIds) do
        if id == nil then
            id = GetItemInstanceId(bagId, slotId)
        elseif id ~= GetItemInstanceId(bagId, slotId) then
            return slotIds
        end
    end

    -- Stack
    sourceIndex = #slotIds
    dbg("targetIndex: " .. targetIndex .. " sourceIndex: " .. sourceIndex)
    while targetIndex < sourceIndex do
        target = slotIds[targetIndex]

        -- Check how much room the target slot has
        stack, maxStack = GetSlotStackSize(bagId, target)
        room = maxStack - stack
        dbg("target stack: " .. stack .. " room: " .. room)

        -- While there's still room
        while room > 0 and targetIndex < sourceIndex do
            local source = slotIds[sourceIndex]

            -- Calculate how many to move
            stack, maxStack = GetSlotStackSize(bagId, source)
            if stack <= room then
                dbg("moving remaining")
                -- Enough room for the remaining stack, move it all
                move = stack
                room = room - move

                -- Move back from the end of the array one slot
                sourceIndex = sourceIndex - 1
            else
                -- Not enough room for the remaining stack, fill the remainder
                move = room
                room = 0
            end

            -- Move it
            dbg("moving " .. move .. " from slot " .. source .. " to " .. target .. " - room: " .. room)
            ClearCursor()
            local res = CallSecureProtected("PickupInventoryItem", bagId, source, move)
            if (res) then
                res = CallSecureProtected("PlaceInInventory", bagId, target)
            end
            ClearCursor()
        end

        -- Out of room in this slot, move to the next one
        targetIndex = targetIndex + 1
        dbg("out of room. target index now " .. targetIndex)
    end

    -- Work out which slots still have items
    local newSlotIds = {}
    for i=1,sourceIndex,1 do
        table.insert(newSlotIds, slotIds[i])
    end

    return newSlotIds
end

-------------------------------------------------------------------------------
-- NextRestack()
-- Perform the next item re-stack
-------------------------------------------------------------------------------
function SN_FS.NextRestack()
    local id = ids[id_index]
    local v = data[id]

    -- Set the global with the slot IDs we're withdrawing (only the partial stacks for efficiency)
    withdraw_slots = v["partials"]
    ws_index = 1

    -- Withdraw the first instance of this item in the GB
    dbg("Restacking " .. v["name"] .. " (" .. id .. ")")
    SN_FS.NextWithdrawal()

    -- Now we wait for a OnGuildBankItemRemoved() callback to tell us that the withdrawal has finished
end

-------------------------------------------------------------------------------
-- NextWithdrawal()
-- Perform the next item withdrawal
-------------------------------------------------------------------------------
function SN_FS.NextWithdrawal()
    wait_slot_id = withdraw_slots[ws_index]

    if wait_slot_id == nil then
        dbg("Found a nil wait slot id - this is a bug, tell snare if you see this :(")
    else
        dbg("Withdrawing from slot ID " .. wait_slot_id)
        TransferFromGuildBank(wait_slot_id)
    end

    ws_index = ws_index + 1
end

-------------------------------------------------------------------------------
-- NextDeposit()
-- Perform the next item deposit
-------------------------------------------------------------------------------
function SN_FS.NextDeposit()
    deposit_slot_id = deposit_slots[ds_index]

    if deposit_slot_id == nil then
        dbg("Found a nil deposit slot id - this is a bug, tell snare if you see this :(")
        dbg("Deposit slot index is " .. ds_index)
    else
        dbg("Depositing backpack slot ID " .. deposit_slot_id)
        TransferToGuildBank(BAG_BACKPACK, deposit_slot_id)
    end

    ds_index = ds_index + 1
end

-------------------------------------------------------------------------------
-- RestackGuildBank()
-- Restack the guild bank
-------------------------------------------------------------------------------
function SN_FS.RestackGuildBank()
    if not gb_open then
        log("Guild bank is not open")
        return
    end

    -- Inspect the items in the GB
    data, ids = SN_FS.InspectGuildBank()

    -- Start restacking
    id_index = 1
    if #ids > 0 then
        log("Restacking...")

        -- Register for item notifications
        EVENT_MANAGER:RegisterForEvent(SN_FS.name, EVENT_GUILD_BANK_ITEM_REMOVED,   SN_FS.OnGuildBankItemRemoved)
        EVENT_MANAGER:RegisterForEvent(SN_FS.name, EVENT_GUILD_BANK_ITEM_ADDED,     SN_FS.OnGuildBankItemAdded)

        -- Do the first restack
        SN_FS.NextRestack()
    end
end

-------------------------------------------------------------------------------
-- InspectGuildBank()
-- Finds inefficiently stacked items in the guild bank
-------------------------------------------------------------------------------
function SN_FS.InspectGuildBank()
    local i = nil
    local count = 0
    local data = {}
    local restack = {}
    local data_count = 0
    local slot_count = 0
    local name, maxStack, stack
    local v = {}

    if not gb_open then
        log("Guild bank is not open")
        return data, restack
    end

    local icon, slots = GetBagInfo(BAG_GUILDBANK)

    -- Iterate through slots in GB
    while(GetNextGuildBankSlotId(i)) do
        -- Get the next slot ID
        i = GetNextGuildBankSlotId(i)        
        slot_count = slot_count + 1

        -- Get info about what's in that slot
        name = GetItemName(BAG_GUILDBANK, i)
        local id = GetItemInstanceId(BAG_GUILDBANK, i)
        local stack, maxStack = GetSlotStackSize(BAG_GUILDBANK, i)

        -- Initialise a new entry if necessary
        if data[id] == nil then
            data[id] = {["name"] = name, ["slots"] = 0, ["count"] = 0, ["maxStack"] = maxStack, ["restack"] = 0,
                        ["slotIds"] = {}, ["partials"] = {}}
            data_count = data_count + 1
        end

        -- Add this slot
        data[id]["slots"] = data[id]["slots"] + 1
        data[id]["count"] = data[id]["count"] + stack
        table.insert(data[id]["slotIds"], i)

        -- Keep track of partial stacks
        if stack < maxStack then
            table.insert(data[id]["partials"], i)
        end
    end

    log("There are " .. data_count .. " unique items in " .. slot_count .. "/" .. slots .. " slots")
    if data_count == 0 then return data, restack end

    -- Find items taking up too much room
    for k,v in pairs(data) do
        data[k]["req"] = math.ceil(v["count"] / v["maxStack"])
        if v["slots"] > data[k]["req"] then
            data[k]["restack"] = 1
            table.insert(restack, k)
        end
    end

    -- Report on poorly stacked items
    if #restack > 0 then
        log("There are " .. #restack .. " items taking up too many slots")
        for i,id in ipairs(restack) do
            v = data[id]
            dbg(v["name"] .. " - " .. v["count"] .. " using " .. v["slots"] .. " slots instead of " .. v["req"])
        end
    else
        log("Guild bank is stacked OK")
    end

    return data, restack
end

-------------------------------------------------------------------------------
-- FindItemInBag()
-- Locates all instances of a specified item ID in the specified bag
-------------------------------------------------------------------------------
function SN_FS.FindItemInBag(itemId, bagId)
    local icon, slots = GetBagInfo(bagId)
    local found = {}

    for slot=0,slots,1 do
        if itemId == GetItemInstanceId(bagId, slot) then
            table.insert(found, slot)
        end
    end

    return found
end

-------------------------------------------------------------------------------
-- OnAddOnLoaded()
-- Initialise the add-on
-------------------------------------------------------------------------------
function SN_FS.OnAddOnLoaded(eventCode, addOnName)
    -- Only initialize our own addon
    if (addOnName ~= SN_FS.name) then return end

    -- Unregister for loaded event
    EVENT_MANAGER:UnregisterForEvent(SN_FS.name, EVENT_ADD_ON_LOADED)

    -- Init logging
    log = SN_FS.Log
    dbg = SN_FS.Debug

    -- Load settings
    SN_FS.LoadConfig()

    -- Configure control panel
    SN_FS.InitAddOnMenu()

    -- Register for guild bank open and close events
    EVENT_MANAGER:RegisterForEvent(SN_FS.name, EVENT_OPEN_GUILD_BANK,    SN_FS.OnOpenGuildBank)
    EVENT_MANAGER:RegisterForEvent(SN_FS.name, EVENT_CLOSE_GUILD_BANK,   SN_FS.OnCloseGuildBank)

    -- Register slash command
    SLASH_COMMANDS["/fs"] = SN_FS.Main
end

-- Register for the initialisation event
EVENT_MANAGER:RegisterForEvent(SN_FS.name, EVENT_ADD_ON_LOADED, SN_FS.OnAddOnLoaded)
