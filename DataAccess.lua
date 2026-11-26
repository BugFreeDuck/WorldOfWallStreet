local _, NS = ...

NS.Data = {}

local MAX_PURCHASES = 200
local DEDUPE_SECONDS = 0.75

local pendingQuote
local auctionCache = {}
local recordedAt = {}
local lastCommodityItemID
local characterBankOpen = false

local function PlainNumber(value)
    if value == nil then
        return nil
    end
    local ok, number = pcall(function()
        if issecretvalue and issecretvalue(value) then
            return nil
        end
        if type(value) ~= "number" then
            return nil
        end
        return value
    end)
    if ok and type(number) == "number" then
        return number
    end
end

local function PositiveQuantity(value)
    value = PlainNumber(value)
    if type(value) == "number" and value >= 1 then
        return math.floor(value)
    end
end

local function ResolveQuantity(quantity, totalCost, unitPrice)
    quantity = PositiveQuantity(quantity)
    if quantity then
        return quantity
    end
    totalCost = PlainNumber(totalCost)
    unitPrice = PlainNumber(unitPrice)
    if totalCost and unitPrice and unitPrice > 0 and totalCost > 0 then
        local inferred = math.floor((totalCost / unitPrice) + 0.5)
        if inferred >= 1 then
            return inferred
        end
    end
end

local function DB()
    local db = WorldOfWallStreetDB
    if type(db) ~= "table" then
        db = {}
        WorldOfWallStreetDB = db
    end
    if type(db.purchases) ~= "table" then
        db.purchases = {}
    end
    if type(db.nextID) ~= "number" then
        db.nextID = 1
    end
    if type(db.minimapAngle) ~= "number" then
        db.minimapAngle = 220
    end
    return db
end

local function FindPurchase(id)
    for _, purchase in ipairs(DB().purchases) do
        if purchase.id == id then
            return purchase
        end
    end
end

local function TrimPurchases(db)
    while #db.purchases > MAX_PURCHASES do
        local removed = false
        for index, purchase in ipairs(db.purchases) do
            if not purchase.investment then
                table.remove(db.purchases, index)
                removed = true
                break
            end
        end
        if not removed then
            return
        end
    end
end

local function RemoveRecentUnknown(itemID)
    local now = GetServerTime()
    local purchases = DB().purchases
    for index = #purchases, 1, -1 do
        local purchase = purchases[index]
        if purchase.itemID == itemID and purchase.totalCost == nil and (now - (purchase.boughtAt or 0)) <= 3 then
            table.remove(purchases, index)
        end
    end
end

local function RememberPurchase(itemID)
    recordedAt[itemID] = GetTime()
end

local function WasJustRecorded(itemID)
    local at = recordedAt[itemID]
    return at and (GetTime() - at) < DEDUPE_SECONDS
end

local function AddPurchase(fields)
    if fields.totalCost ~= nil and fields.kind ~= "bags" and fields.kind ~= "bank" then
        RemoveRecentUnknown(fields.itemID)
    end

    local db = DB()
    local totalCost = fields.totalCost
    local quantity = PositiveQuantity(fields.quantity) or 1
    local unitCost = nil
    if type(totalCost) == "number" and quantity > 0 then
        unitCost = math.floor(totalCost / quantity)
    end

    db.purchases[#db.purchases + 1] = {
        id = db.nextID,
        itemID = fields.itemID,
        itemLink = fields.itemLink,
        quantity = quantity,
        totalCost = totalCost,
        unitCost = unitCost,
        boughtAt = GetServerTime(),
        character = UnitName("player"),
        realm = GetRealmName(),
        kind = fields.kind,
        investment = fields.investment and true or false,
        unverified = fields.unverified and true or false,
    }
    db.nextID = db.nextID + 1
    TrimPurchases(db)
    RememberPurchase(fields.itemID)

    if NS.UI and NS.UI.Refresh then
        NS.UI.Refresh()
    end
end

local function CommodityBuyContext()
    local buyFrame = AuctionHouseFrame and AuctionHouseFrame.CommoditiesBuyFrame
    if not buyFrame then
        return
    end

    local itemID
    if buyFrame.GetItemID then
        local ok, value = pcall(buyFrame.GetItemID, buyFrame)
        if ok then
            itemID = PlainNumber(value)
        end
    end
    if not itemID then
        itemID = PlainNumber(buyFrame.itemID)
    end

    local quantity
    local display = buyFrame.BuyDisplay
    local inputs = display and { display.QuantityInput, display.QuantityBox, display.quantityInput }
    if inputs then
        for _, input in ipairs(inputs) do
            if input and not quantity then
                if input.GetQuantity then
                    local ok, value = pcall(input.GetQuantity, input)
                    quantity = ok and PositiveQuantity(value) or nil
                end
                if not quantity and input.GetNumber then
                    local ok, value = pcall(input.GetNumber, input)
                    quantity = ok and PositiveQuantity(value) or nil
                end
                if not quantity and input.GetText then
                    local ok, text = pcall(input.GetText, input)
                    quantity = ok and PositiveQuantity(tonumber(text)) or nil
                end
            end
        end
    end

    return itemID, quantity
end

local function QuoteCost(quote)
    if not quote then
        return nil
    end
    if quote.money then
        local now = PlainNumber(GetMoney())
        if now and quote.money > now then
            return quote.money - now
        end
    end
    return PlainNumber(quote.totalPrice)
end

local function CommitCommodityPurchase(itemID, quantity, totalCost, unverified, unitPrice)
    itemID = PlainNumber(itemID)
    totalCost = PlainNumber(totalCost)
    quantity = ResolveQuantity(quantity, totalCost, unitPrice)
    if not itemID or WasJustRecorded(itemID) then
        return false
    end
    if not quantity then
        return false
    end

    AddPurchase({
        itemID = itemID,
        quantity = quantity,
        totalCost = totalCost,
        kind = "commodity",
        unverified = unverified or totalCost == nil,
    })
    return true
end

local function CacheItemSearchResults(itemKey)
    if not itemKey or not C_AuctionHouse or not C_AuctionHouse.GetNumItemSearchResults then
        return
    end

    local ok, count = pcall(C_AuctionHouse.GetNumItemSearchResults, itemKey)
    if not ok or type(count) ~= "number" then
        return
    end

    for index = 1, count do
        local infoOk, info = pcall(C_AuctionHouse.GetItemSearchResultInfo, itemKey, index)
        if infoOk and type(info) == "table" and type(info.auctionID) == "number" then
            local itemID = itemKey.itemID
            if type(info.itemKey) == "table" and type(info.itemKey.itemID) == "number" then
                itemID = info.itemKey.itemID
            end
            auctionCache[info.auctionID] = {
                itemID = itemID,
                itemLink = info.itemLink,
                quantity = PositiveQuantity(info.quantity) or 1,
                buyout = info.buyoutAmount,
            }
        end
    end
end

local function CharacterRecord()
    local name = UnitName("player")
    if not name or name == "" or name == "Unknown" then
        return nil
    end
    local realm = GetRealmName() or ""
    local db = DB()
    if type(db.characters) ~= "table" then
        db.characters = {}
    end
    local key = realm .. "-" .. name
    local record = db.characters[key]
    if type(record) ~= "table" then
        record = {}
        db.characters[key] = record
    end
    if type(record.bags) ~= "table" then
        record.bags = {}
    end
    if type(record.bank) ~= "table" then
        record.bank = {}
    end
    record.name = name
    record.realm = realm
    return record
end

local function AppendBagRange(list, first, count)
    if type(first) ~= "number" then
        return
    end
    for offset = 0, (count or 1) - 1 do
        list[#list + 1] = first + offset
    end
end

local function EquippedBagIDs()
    local bags = {}
    local backpack = Enum and Enum.BagIndex and Enum.BagIndex.Backpack or 0
    bags[#bags + 1] = backpack
    local numBags = 4
    if Constants and Constants.InventoryConstants and Constants.InventoryConstants.NumBagSlots then
        numBags = Constants.InventoryConstants.NumBagSlots
    end
    local firstBag = Enum and Enum.BagIndex and Enum.BagIndex.Bag_1 or 1
    AppendBagRange(bags, firstBag, numBags)
    if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
        bags[#bags + 1] = Enum.BagIndex.ReagentBag
    end
    return bags
end

local function BankIsOpen()
    return characterBankOpen
end

local function CharacterBankBagIDs()
    if C_Bank and C_Bank.FetchPurchasedBankTabIDs and Enum and Enum.BankType then
        local ok, tabs = pcall(C_Bank.FetchPurchasedBankTabIDs, Enum.BankType.Character)
        if ok and type(tabs) == "table" and #tabs > 0 then
            return tabs
        end
    end
    local bags = {}
    if Enum and Enum.BagIndex then
        local index = 1
        while Enum.BagIndex["CharacterBankTab_" .. index] do
            bags[#bags + 1] = Enum.BagIndex["CharacterBankTab_" .. index]
            index = index + 1
        end
    end
    return bags
end

local function ReadContainer(bagID, totals)
    if not C_Container or not C_Container.GetContainerNumSlots then
        return false
    end
    local ok, slots = pcall(C_Container.GetContainerNumSlots, bagID)
    slots = ok and PlainNumber(slots) or nil
    if not slots or slots < 1 then
        return false
    end
    for slot = 1, slots do
        local infoOk, info = pcall(C_Container.GetContainerItemInfo, bagID, slot)
        if infoOk and type(info) == "table" then
            local itemID = PlainNumber(info.itemID)
            local count = PlainNumber(info.stackCount) or 1
            local link = type(info.hyperlink) == "string" and info.hyperlink or nil
            if itemID and count > 0 then
                local entry = totals[itemID]
                if not entry then
                    entry = { quantity = 0, itemLink = link }
                    totals[itemID] = entry
                end
                entry.quantity = entry.quantity + count
                if link then
                    entry.itemLink = link
                end
            end
        end
    end
    return true
end

local function ListFromTotals(totals)
    local list = {}
    for itemID, info in pairs(totals) do
        list[#list + 1] = {
            itemID = itemID,
            quantity = info.quantity,
            itemLink = info.itemLink,
        }
    end
    table.sort(list, function(a, b)
        local nameA = NS.Logic.ItemAppearance(a.itemID, a.itemLink) or ""
        local nameB = NS.Logic.ItemAppearance(b.itemID, b.itemLink) or ""
        if nameA ~= nameB then
            if strcmputf8i then
                return strcmputf8i(nameA, nameB) < 0
            end
            return nameA < nameB
        end
        return a.itemID < b.itemID
    end)
    return list
end

local function ScanBagList(bagIDs)
    local totals = {}
    local readable = false
    for _, bagID in ipairs(bagIDs) do
        if ReadContainer(bagID, totals) then
            readable = true
        end
    end
    return ListFromTotals(totals), readable
end

local function ScanBags()
    local record = CharacterRecord()
    if not record then
        return
    end
    record.bags = ScanBagList(EquippedBagIDs())
    record.bagsUpdated = GetServerTime()
end

local function ScanBank()
    if not BankIsOpen() then
        return
    end
    local record = CharacterRecord()
    if not record then
        return
    end
    local list, readable = ScanBagList(CharacterBankBagIDs())
    if not readable then
        return
    end
    record.bank = list
    record.bankUpdated = GetServerTime()
    record.bankSeen = true
end


local function RefreshHoldingsIfVisible()
    if NS.UI and NS.UI.HoldingsVisible and NS.UI.HoldingsVisible() then
        NS.UI.RefreshHoldings()
    end
end

local function OnCommoditySearchResultsUpdated(itemID)
    itemID = PlainNumber(itemID)
    if itemID then
        lastCommodityItemID = itemID
    end
end

local function OnCommodityPriceUpdated(unitPrice, totalPrice)
    local itemID, quantity = CommodityBuyContext()
    itemID = PlainNumber(itemID) or lastCommodityItemID
    quantity = PositiveQuantity(quantity)
    if not quantity and pendingQuote and pendingQuote.itemID == itemID then
        quantity = pendingQuote.quantity
    end
    pendingQuote = {
        unitPrice = PlainNumber(unitPrice),
        totalPrice = PlainNumber(totalPrice),
        itemID = itemID,
        quantity = quantity,
        money = PlainNumber(GetMoney()),
    }
end

local function OnCommodityPurchaseFailed()
    pendingQuote = nil
end

local function OnCommodityPurchaseSucceeded()
    local quote = pendingQuote
    if not quote then
        return
    end

    local itemID = quote.itemID or lastCommodityItemID
    local totalCost = QuoteCost(quote)
    local quantity = ResolveQuantity(quote.quantity, totalCost, quote.unitPrice)
    if not quantity then
        return
    end
    if CommitCommodityPurchase(itemID, quantity, totalCost, false, quote.unitPrice) then
        pendingQuote = nil
    end
end

local function CorrectRecentQuantity(itemID, quantity)
    quantity = PositiveQuantity(quantity)
    if not itemID or not quantity then
        return
    end
    local now = GetServerTime()
    local purchases = DB().purchases
    for index = #purchases, 1, -1 do
        local purchase = purchases[index]
        if purchase.itemID == itemID and (now - (purchase.boughtAt or 0)) <= 3 and (purchase.quantity or 0) < 1 then
            purchase.quantity = quantity
            if type(purchase.totalCost) == "number" and quantity > 0 then
                purchase.unitCost = math.floor(purchase.totalCost / quantity)
            end
            if NS.UI and NS.UI.Refresh then
                NS.UI.Refresh()
            end
            return
        end
    end
end

local function OnCommodityPurchased(itemID, quantity)
    itemID = PlainNumber(itemID)
    quantity = PlainNumber(quantity)
    local quote = pendingQuote
    pendingQuote = nil

    if not itemID then
        return
    end
    if WasJustRecorded(itemID) then
        CorrectRecentQuantity(itemID, quantity)
        return
    end

    local totalCost = QuoteCost(quote)
    local unverified = totalCost == nil
    if quote and quote.itemID and quote.itemID ~= itemID then
        totalCost = nil
        unverified = true
    end
    quantity = ResolveQuantity(quantity, totalCost, quote and quote.unitPrice)
    if quote and quote.quantity and quantity and quote.quantity ~= quantity then
        unverified = true
    end

    CommitCommodityPurchase(itemID, quantity, totalCost, unverified, quote and quote.unitPrice)
end

local function OnItemSearchResultsUpdated(itemKey)
    CacheItemSearchResults(itemKey)
end

local function OnAuctionHousePurchaseCompleted(auctionID)
    local info = auctionCache[auctionID]
    auctionCache[auctionID] = nil
    if not info or not info.itemID or WasJustRecorded(info.itemID) then
        return
    end

    AddPurchase({
        itemID = info.itemID,
        itemLink = info.itemLink,
        quantity = PositiveQuantity(info.quantity) or 1,
        totalCost = info.buyout,
        kind = "item",
        unverified = type(info.buyout) ~= "number",
    })
end

local function OnItemPurchased(itemID)
    itemID = PlainNumber(itemID)
    if not itemID then
        return
    end
    C_Timer.After(0.2, function()
        if WasJustRecorded(itemID) then
            return
        end
        AddPurchase({
            itemID = itemID,
            quantity = 1,
            kind = "item",
            unverified = true,
        })
    end)
end

local function OnAuctionHouseClosed()
    pendingQuote = nil
    auctionCache = {}
end

local function OnEnteringWorld()
    ScanBags()
    ScanBank()
    RefreshHoldingsIfVisible()
end

local function OnBagsChanged()
    ScanBags()
    ScanBank()
    RefreshHoldingsIfVisible()
end

local function OnBankOpened()
    characterBankOpen = true
    ScanBank()
    RefreshHoldingsIfVisible()
end

local function OnBankClosed()
    characterBankOpen = false
end

local function OnBankSlotsChanged()
    ScanBank()
    RefreshHoldingsIfVisible()
end

NS.Data.PlainNumber = PlainNumber
NS.Data.DB = DB
NS.Data.AddPurchase = AddPurchase
NS.Data.FindPurchase = FindPurchase
NS.Data.CharacterRecord = CharacterRecord
NS.Data.ScanBags = ScanBags
NS.Data.ScanBank = ScanBank
NS.Data.OnCommoditySearchResultsUpdated = OnCommoditySearchResultsUpdated
NS.Data.OnCommodityPriceUpdated = OnCommodityPriceUpdated
NS.Data.OnCommodityPurchaseFailed = OnCommodityPurchaseFailed
NS.Data.OnCommodityPurchaseSucceeded = OnCommodityPurchaseSucceeded
NS.Data.OnCommodityPurchased = OnCommodityPurchased
NS.Data.OnItemSearchResultsUpdated = OnItemSearchResultsUpdated
NS.Data.OnAuctionHousePurchaseCompleted = OnAuctionHousePurchaseCompleted
NS.Data.OnItemPurchased = OnItemPurchased
NS.Data.OnAuctionHouseClosed = OnAuctionHouseClosed
NS.Data.OnEnteringWorld = OnEnteringWorld
NS.Data.OnBagsChanged = OnBagsChanged
NS.Data.OnBankOpened = OnBankOpened
NS.Data.OnBankClosed = OnBankClosed
NS.Data.OnBankSlotsChanged = OnBankSlotsChanged
