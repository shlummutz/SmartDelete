-- Global Strings for Keybinding UI
BINDING_HEADER_SMARTDELETE_HEADER = "SmartDelete"
BINDING_NAME_SMARTDELETE_MAIN = "Delete Item / Confirm"
BINDING_NAME_SMARTDELETE_IGNORE = "Ignore Item & Delete Grey"

-- Configuration: Chat Color
local CHAT_PREFIX = "|cffff2e89[SmartDelete]:|r "

-- State Variables
local waitingForConfirm = false
local pendingItem = {} -- The High Quality Item found
local backupItem = {}  -- The Grey Item (Fallback)

-- Initialize Saved Variables
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, arg1)
    if arg1 == "SmartDelete" then
        if not SmartDeleteIgnoreDB then SmartDeleteIgnoreDB = {} end
        -- Default Verbose to true if it doesn't exist
        if SmartDeleteVerbose == nil then SmartDeleteVerbose = true end
    end
end)

-- Helper: Extract ID from Link
local function GetItemID(link)
    if not link then return nil end
    return tonumber(string.match(link, "item:(%d+)"))
end

-- Helper: Perform Delete
-- Added 'silent' parameter to control chat output
local function DeleteItem(bag, slot, link, count, value, silent)
    if not bag or not slot then return end
    
    PickupContainerItem(bag, slot)
    if CursorHasItem() then
        DeleteCursorItem()
        if not silent then
            DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Deleted " .. link .. " x" .. count .. " (Value: " .. GetCoinTextureString(value) .. ")")
        end
    else
        if not silent then
            DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Error: Failed to pick up item.")
        end
    end
end

-- Helper: Reset State
local function ResetState()
    waitingForConfirm = false
    pendingItem = {}
    backupItem = {}
end

-- === MAIN LOGIC ===

function SmartDelete_MainButton()
    -- CASE 1: We are waiting for confirmation to delete the High Quality item
    if waitingForConfirm then
        -- Execute delete (Verbose mode handled inside DeleteItem normally, but if minimal we want the standard delete msg which is 1 line)
        DeleteItem(pendingItem.bag, pendingItem.slot, pendingItem.link, pendingItem.count, pendingItem.value, false)
        ResetState()
        return
    end

    -- CASE 2: Standard Scan
    local bestGrey = { value = nil }
    local bestNonGrey = { value = nil }

    for bag = 0, 4 do
        for slot = 1, GetContainerNumSlots(bag) do
            local link = GetContainerItemLink(bag, slot)
            if link then
                local _, count = GetContainerItemInfo(bag, slot)
                local _, _, quality, _, _, _, _, _, _, _, unitPrice = GetItemInfo(link)
                local id = GetItemID(link)
                
                -- Only calculate if it has a price and is NOT in ignore list
                if unitPrice and unitPrice > 0 and not SmartDeleteIgnoreDB[id] then
                    local totalValue = unitPrice * count
                    
                    if quality == 0 then
                        -- Logic for Grey Items
                        if (not bestGrey.value) or (totalValue < bestGrey.value) then
                            bestGrey = { bag=bag, slot=slot, link=link, count=count, value=totalValue }
                        end
                    else
                        -- Logic for Non-Grey Items (White/Green/etc)
                        if (not bestNonGrey.value) or (totalValue < bestNonGrey.value) then
                            bestNonGrey = { bag=bag, slot=slot, link=link, count=count, value=totalValue, id=id }
                        end
                    end
                end
            end
        end
    end

    -- === DECISION PHASE ===

    -- 1. No items found at all
    if not bestGrey.value and not bestNonGrey.value then
        DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "No sellable items found.")
        return
    end

    -- 2. We have a Non-Grey that is CHEAPER than the best Grey (or no grey exists)
    if bestNonGrey.value and ((not bestGrey.value) or (bestNonGrey.value < bestGrey.value)) then
        -- TRIGGER WARNING MODE
        waitingForConfirm = true
        pendingItem = bestNonGrey
        backupItem = bestGrey 
        
        PlaySound("RaidWarning")

        if SmartDeleteVerbose then
            -- MAX VERBOSITY (Full Details + Key Instructions)
            local mainKeyDisplay = GetBindingKey("SMARTDELETE_MAIN") or "Unbound"
            local ignoreKeyDisplay = GetBindingKey("SMARTDELETE_IGNORE") or "Unbound"

            DEFAULT_CHAT_FRAME:AddMessage("--------------------------------")
            DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "|cffff0000ATTENTION!|r")
            DEFAULT_CHAT_FRAME:AddMessage("Found better candidate than grey: " .. bestNonGrey.link .. " x" .. bestNonGrey.count)
            DEFAULT_CHAT_FRAME:AddMessage("Value: " .. GetCoinTextureString(bestNonGrey.value))
            
            if bestGrey.value then
                DEFAULT_CHAT_FRAME:AddMessage("(Your cheapest grey is " .. bestGrey.link .. " worth " .. GetCoinTextureString(bestGrey.value) .. ")")
                DEFAULT_CHAT_FRAME:AddMessage("--- ACTIONS ---")
                DEFAULT_CHAT_FRAME:AddMessage("1. Press |cff00ff00<" .. mainKeyDisplay .. ">|r again to DELETE " .. bestNonGrey.link)
                DEFAULT_CHAT_FRAME:AddMessage("2. Press |cff00ff00<" .. ignoreKeyDisplay .. ">|r to IGNORE " .. bestNonGrey.link .. " and delete the Grey instead.")
            else
                 DEFAULT_CHAT_FRAME:AddMessage("1. Press |cff00ff00<" .. mainKeyDisplay .. ">|r again to DELETE " .. bestNonGrey.link)
            end
            DEFAULT_CHAT_FRAME:AddMessage("--------------------------------")
        else
            -- MINIMAL VERBOSITY (Comparison Line Only)
            local msg = CHAT_PREFIX .. "|cffff0000WARN:|r " .. bestNonGrey.link .. " (" .. GetCoinTextureString(bestNonGrey.value) .. ")"
            
            if bestGrey.value then
                msg = msg .. " is cheaper than " .. bestGrey.link .. " (" .. GetCoinTextureString(bestGrey.value) .. ")."
            else
                msg = msg .. " found (No greys)."
            end
            
            DEFAULT_CHAT_FRAME:AddMessage(msg)
        end
        return
    end

    -- 3. Standard Behavior: Grey is the cheapest
    if bestGrey.value then
        DeleteItem(bestGrey.bag, bestGrey.slot, bestGrey.link, bestGrey.count, bestGrey.value, false)
    end
end

function SmartDelete_IgnoreButton()
    if waitingForConfirm then
        -- Add the High Quality item to ignore list
        SmartDeleteIgnoreDB[pendingItem.id] = true
        
        if SmartDeleteVerbose then
            -- VERBOSE: Detailed feedback
            DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Added " .. pendingItem.link .. " to ignore list.")
            if backupItem.value then
                DeleteItem(backupItem.bag, backupItem.slot, backupItem.link, backupItem.count, backupItem.value, false)
            else
                DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "No other grey items to delete.")
            end
        else
            -- MINIMAL: Single line summary
            local msg = CHAT_PREFIX .. "Ignored " .. pendingItem.link .. "."
            if backupItem.value then
                -- Delete silently, then append text manually to keep 1 line
                DeleteItem(backupItem.bag, backupItem.slot, backupItem.link, backupItem.count, backupItem.value, true)
                msg = msg .. " Deleted " .. backupItem.link .. " (" .. GetCoinTextureString(backupItem.value) .. ")."
            else
                msg = msg .. " No grey to delete."
            end
            DEFAULT_CHAT_FRAME:AddMessage(msg)
        end
        
        ResetState()
    else
        DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Nothing to ignore currently.")
    end
end

-- === SLASH COMMAND & SETUP CHECK ===

SLASH_SMARTDELETE1 = "/smartdelete"
SLASH_SMARTDELETE2 = "/sd"
SlashCmdList["SMARTDELETE"] = function(msg)
    -- Handle Clear Command
    if msg == "clear" then
        SmartDeleteIgnoreDB = {}
        DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Ignore list cleared.")
        return
    end

    -- Handle Verbose Command
    if msg == "verbose" then
        SmartDeleteVerbose = not SmartDeleteVerbose
        local state = SmartDeleteVerbose and "|cff00ff00ON|r" or "|cffff0000OFF|r"
        DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Verbosity: " .. state)
        return
    end

    -- Check if the Main Keybind is set
    local key1 = GetBindingKey("SMARTDELETE_MAIN")
    
    if not key1 then
        -- === WARNING: NO KEYBIND SET ===
        DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "|cffff0000WARNING: Keybinds not set!|r")
        DEFAULT_CHAT_FRAME:AddMessage("To use this addon, you must bind a key:")
        DEFAULT_CHAT_FRAME:AddMessage("1. Press |cffffffffEsc|r -> |cffffffffKey Bindings|r")
        DEFAULT_CHAT_FRAME:AddMessage("2. Scroll down to the |cffffffffSmartDelete|r header.")
        DEFAULT_CHAT_FRAME:AddMessage("3. Assign a key to '|cffffffffDelete Item / Confirm|r'.")
    else
        -- === SUCCESS: KEYBIND IS SET ===
        DEFAULT_CHAT_FRAME:AddMessage(CHAT_PREFIX .. "Addon ready. Bound to: |cff00ff00<" .. key1 .. ">|r")
        DEFAULT_CHAT_FRAME:AddMessage("commands: '/sd clear', '/sd verbose'")
    end
end