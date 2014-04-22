FatStacks = {}
FatStacks.name = "FatStacks"

data = {}
ids = {}
id_index = 1

withdraw_slots = {}
ws_index = 1
wait_slot_id = nil

deposit_slots = {}
ds_index = 1

gb_open = false

function OnOpenGuildBank()
    -- d("Opening guild bank")
    gb_open = true
end

function OnCloseGuildBank()
    -- d("Closing guild bank")
    gb_open = false
end

function Main(arg)
    if arg == "" or arg == "help" then
        d("----- FatStacks help -----")
        d("/fs - this help")
        -- d("/fs show - show main output window")
        -- d("/fs hide - hide main output window")
        d("/fs info - just get info about the state of the guild bank")
        d("/fs restack - restack the guild bank")
        d("/fs reset - reset FatStacks (use this if you get an error or if FS hangs mid-restack)")
    elseif arg == "restack" then
        RestackGuildBank()
    elseif arg == "reset" then
        d("Resetting")
        EVENT_MANAGER:UnregisterForEvent(FatStacks.name, EVENT_GUILD_BANK_ITEM_REMOVED, OnGuildBankItemRemoved)
        EVENT_MANAGER:UnregisterForEvent(FatStacks.name, EVENT_GUILD_BANK_ITEM_ADDED, OnGuildBankItemAdded)
        data = {}
    elseif arg == "info" then
        InspectGuildBank()
    else
        d("[FatStacks] No such command: " .. arg)
    end
end

function OnGuildBankItemRemoved(bagId, slotId, isNewItem, itemSoundCategory, updateReason)
    local found

    -- If this is the ID we were waiting for
    if wait_slot_id == slotId then
        if ws_index <= #withdraw_slots then
            -- Haven't finished withdrawing all the slots for this item yet
            NextWithdrawal()
        else
            -- Finished withdrawing all the slots for this item, find the item slot(s) in backpack
            slots = FindItemInBag(ids[id_index], BAG_BACKPACK)

            -- Stack the items we found
            deposit_slots = StackItems(BAG_BACKPACK, slots)

            -- Deposit the first stack in the GB
            NextDeposit()

            -- Wait for notification to call OnGuildBankItemAdded() before depositing the next one
        end
    end
end

function OnGuildBankItemAdded(bagId, slotId, isNewItem, itemSoundCategory, updateReason)
    local found

    if ds_index <= #deposit_slots then
        -- Haven't finished depositing all the slots for this item yet
        NextDeposit()
    else
        -- Finished depositing all the slots for this item
        deposit_slots = FindItemInBag(ids[id_index], BAG_BACKPACK)
        ds_index = 1

        -- Increment the index into the IDs array
        id_index = id_index + 1

        -- Do the next restack
        if id_index <= #ids then
            NextRestack()
        else
            d("Finished restacking guild bank")
            EVENT_MANAGER:UnregisterForEvent(FatStacks.name, EVENT_GUILD_BANK_ITEM_REMOVED, OnGuildBankItemRemoved)
            EVENT_MANAGER:UnregisterForEvent(FatStacks.name, EVENT_GUILD_BANK_ITEM_ADDED, OnGuildBankItemAdded)
        end
    end
end

function StackItems(bagId, slotIds)
    -- Make sure they're all the same item type
    id = nil
    for i,slotId in ipairs(slotIds) do
        if id == nil then
            id = GetItemInstanceId(bagId, slotId)
        elseif id ~= GetItemInstanceId(bagId, slotId) then
            return slotIds
        end
    end

    -- Stack
    done = false
    targetIndex = 1
    sourceIndex = #slotIds
    -- d("targetIndex: " .. targetIndex .. " sourceIndex: " .. sourceIndex)
    while targetIndex < sourceIndex do
        target = slotIds[targetIndex]

        -- Check how much room the target slot has
        stack, maxStack = GetSlotStackSize(bagId, target)
        room = maxStack - stack
        -- d("target stack: " .. stack .. " room: " .. room)

        -- While there's still room
        while room > 0 and targetIndex < sourceIndex do
            source = slotIds[sourceIndex]

            -- Calculate how many to move
            stack, maxStack = GetSlotStackSize(bagId, source)
            if stack <= room then
                -- d("moving remaining")
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
            -- d("moving " .. move .. " from slot " .. source .. " to " .. target .. " - room: " .. room)
            ClearCursor()
            res = CallSecureProtected("PickupInventoryItem", bagId, source, move)
            if (res) then
                res = CallSecureProtected("PlaceInInventory", bagId, target)
            end
            ClearCursor()
        end

        -- Out of room in this slot, move to the next one
        targetIndex = targetIndex + 1
        -- d("out of room. target index now " .. targetIndex)
    end

    -- Work out which slots still have items
    newSlotIds = {}
    for i=1,sourceIndex,1 do
        table.insert(newSlotIds, slotIds[i])
    end

    return newSlotIds
end

function NextRestack()
    id = ids[id_index]
    v = data[id]
    -- d("restacking id " .. id)

    -- Set the global with the slot IDs we're withdrawing
    withdraw_slots = v["slotIds"]
    ws_index = 1

    -- Withdraw the first instance of this item in the GB
    d("Withdrawing " .. v["name"] .. " (" .. id .. ")")
    NextWithdrawal()

    -- Now we wait for a OnGuildBankItemRemoved() callback to tell us that the withdrawal has finished
end

function NextWithdrawal()
    wait_slot_id = withdraw_slots[ws_index]

    d("Withdrawing from slot ID " .. wait_slot_id)
    TransferFromGuildBank(wait_slot_id)

    ws_index = ws_index + 1
end

function NextDeposit()
    deposit_slot_id = deposit_slots[ds_index]

    d("Depositing backpack slot ID " .. deposit_slot_id)
    TransferToGuildBank(BAG_BACKPACK, deposit_slot_id)

    ds_index = ds_index + 1
end

function RestackGuildBank()
    if not gb_open then
        d("Guild bank is not open")
        return
    end

    -- Inspect the items in the GB
    data, ids = InspectGuildBank()

    -- Start restacking
    id_index = 1
    if #ids > 0 then
        -- Register for item notifications
        EVENT_MANAGER:RegisterForEvent(FatStacks.name, EVENT_GUILD_BANK_ITEM_REMOVED, OnGuildBankItemRemoved)
        EVENT_MANAGER:RegisterForEvent(FatStacks.name, EVENT_GUILD_BANK_ITEM_ADDED, OnGuildBankItemAdded)

        -- Do the first restack
        NextRestack()
    end
end

function InspectGuildBank()
    local i = nil
    local count = 0
    local data = {}
    local restack = {}
    local data_count = 0
    local slot_count = 0
    local name, maxStack, stack

    if not gb_open then
        d("Guild bank is not open")
        return data, restack
    end

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
        d("There are " .. #restack .. " items taking up too many slots:")
        for i,id in ipairs(restack) do
            v = data[id]
            d(v["name"] .. " - " .. v["count"] .. " using " .. v["slots"] .. " slots instead of " .. v["req"])
        end
    else
        d("Guild bank is stacked OK")
    end

    return data, restack
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

function FatStacks.OnAddOnLoaded(eventCode, addOnName)
    d("loading " .. eventCode .. " " .. addOnName)

    -- Register for guild bank open and close events
    EVENT_MANAGER:RegisterForEvent(FatStacks.name, EVENT_OPEN_GUILD_BANK, OnOpenGuildBank)
    EVENT_MANAGER:RegisterForEvent(FatStacks.name, EVENT_CLOSE_GUILD_BANK, OnCloseGuildBank)

    -- Only initialize our own addon
    if (FatStacks.name ~= FatStacks.name) then return end

    -- Register slash command
    SLASH_COMMANDS["/fs"] = Main
end


EVENT_MANAGER:RegisterForEvent(FatStacks.name, EVENT_ADD_ON_LOADED, FatStacks.OnAddOnLoaded)