UnfuckBank = {}
UnfuckBank.name = "UnfuckBank"

wait_slots = {}
done_slots = 0
data = {}
ids = {}
index = 1

function OnOpenGuildBank()
    d("Opening guild bank")
end

function OnOpenBank()
    d("Opening bank")
end

function Unfuck(arg)
    if arg == "" or arg == "gb" then
        UnfuckGuildBank()
    end
end

function Test(arg)
    d("test")
    found = FindItemInBag(1937545910, BAG_BACKPACK)
    d(found)
    d("done")
end

function OnGuildBankItemRemoved(bagId, slotId, isNewItem, itemSoundCategory, updateReason)
    local found

    -- Remove the slot that was emptied from the list of slots we're waiting for
    for i,v in ipairs(wait_slots) do
        if v == slotId then
            -- d("removing slot " .. slotId .. " from wait_slots")
            table.remove(wait_slots, i)
        end
    end

    -- If all the withdrawals are finished
    if #wait_slots == 0 then
        -- Find the item slot(s) in backpack
        found = FindItemInBag(ids[index], BAG_BACKPACK)

        -- Deposit the stack(s) in the GB
        for i,slotId in ipairs(found) do
            d("Depositing " .. v["name"] .. " from backpack slot ID " .. slotId)
            TransferToGuildBank(BAG_BACKPACK, slotId)
        end

        -- Increment the index into the IDs array
        index = index + 1

        -- Do the next restack
        if index < #ids then
            NextRestack()
        else
            d("Finished restacking guild bank")
            EVENT_MANAGER:UnregisterForEvent(UnfuckBank.name, EVENT_GUILD_BANK_ITEM_REMOVED, OnGuildBankItemRemoved)
        end
    end
end

function UnfuckGuildBank()
    d("Unfucking guild bank")

    -- Inspect the items in the GB
    data = InspectGuildBank()

    -- Get a list of ids that need restacking
    for k,v in pairs(data) do
        if v["restack"] == 1 then
            table.insert(ids, k)
        end
    end

    if #ids > 0 then
        -- Register for item notifications
        EVENT_MANAGER:RegisterForEvent(UnfuckBank.name, EVENT_GUILD_BANK_ITEM_REMOVED, OnGuildBankItemRemoved)

        -- Do the first restack
        NextRestack()
    else
        d("Guild bank seems to be stacked OK")
    end
end

function NextRestack()
    id = ids[index]
    v = data[id]
    -- d("restacking id " .. id)

    -- Set the global with the slot IDs we're waiting to empty
    wait_slots = v["slotIds"]

    -- Withdraw all the instances of this item in the GB
    for i,slotId in ipairs(v["slotIds"]) do
        d("Withdrawing " .. v["name"] .. " (" .. id .. ") in guild bank slot ID " .. slotId)
        TransferFromGuildBank(slotId)
    end

    -- Now we wait for callbacks to tell us that the withdrawals have finished
end

function InspectGuildBank()
    local i = nil
    local count = 0
    local data = {}
    local data_count = 0
    local slot_count = 0
    local name, maxStack, stack

    icon, slots = GetBagInfo(BAG_GUILDBANK)

    -- Iterate through slots in GB
    while(GetNextGuildBankSlotId(i)) do
        -- Get the next slot ID
        i = GetNextGuildBankSlotId(i)        
        slot_count = slot_count + 1

        -- Get info about what's in that slot
        name = GetItemName(BAG_GUILDBANK, i)
        id = GetItemInstanceId(BAG_GUILDBANK, i)
        stack, maxStack = GetSlotStackSize(BAG_GUILDBANK, i)

        -- Initialise a new entry if necessary
        if data[id] == nil then
            data[id] = {["name"] = name, ["slots"] = 0, ["count"] = 0, ["maxStack"] = maxStack, ["restack"] = 0,
                        ["slotIds"] = {}}
            data_count = data_count + 1
        end

        -- Add this slot
        data[id]["slots"] = data[id]["slots"] + 1
        data[id]["count"] = data[id]["count"] + stack
        table.insert(data[id]["slotIds"], i)
    end

    d("There are " .. data_count .. " unique items in " .. slot_count .. "/" .. slots .. " slots")

    -- Find items taking up too much room
    d("The following items are taking up too many slots:")
    for k,v in pairs(data) do
        local req = math.ceil(v["count"] / v["maxStack"])
        if v["slots"] > req then
            d(v["name"] .. " - " .. v["count"] .. " using " .. v["slots"] .. " slots instead of " .. req)
            data[k]["restack"] = 1
        end
    end

    return data
end

function FindItemInBag(itemId, bagId)
    local icon, slots = GetBagInfo(bagId)
    local found = {}

    for slot=0,slots,1 do
        if GetItemInstanceId(bagId, slot) and itemId then
            -- d("slot: " .. slot .. " searching for " .. itemId .. " found " .. GetItemInstanceId(bagId, slot) .. ": " .. GetItemName(bagId, slot))
        end
        if itemId == GetItemInstanceId(bagId, slot) then
            table.insert(found, slot)
        end
    end

    return found
end

function UnfuckBank.OnAddOnLoaded(eventCode, addOnName)
    d("loading " .. eventCode .. " " .. addOnName)

    -- Only initialize our own addon
    if (UnfuckBank.name ~= UnfuckBank.name) then return end

    -- Register slash command
    SLASH_COMMANDS["/unfuck"] = Unfuck
    SLASH_COMMANDS["/test"] = Test

    -- Use this to load in our saved variables
    UnfuckBank.vars = ZO_SavedVars:NewAccountWide("UnfuckBank_SavedVariables", 1, nil, UnfuckBank.defaults)

    -- Register for bank events
    EVENT_MANAGER:RegisterForEvent(UnfuckBank.name, EVENT_OPEN_GUILD_BANK, OnOpenGuildBank)
    EVENT_MANAGER:RegisterForEvent(UnfuckBank.name, EVENT_OPEN_BANK, OnOpenBank)
end


EVENT_MANAGER:RegisterForEvent(UnfuckBank.name, EVENT_ADD_ON_LOADED, UnfuckBank.OnAddOnLoaded)