local _, NS = ...

NS.Logic = {}

local requestedItems = {}

local function PlainNumber(value)
    return NS.Data.PlainNumber(value)
end

local function DB()
    return NS.Data.DB()
end

local function CharacterRecord()
    return NS.Data.CharacterRecord()
end

local function FormatMoney(copper, unverified)
    if type(copper) ~= "number" then
        return "Unknown price"
    end

    local text
    if C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString then
        text = C_CurrencyInfo.GetCoinTextureString(math.floor(copper))
    elseif GetCoinTextureString then
        text = GetCoinTextureString(math.floor(copper))
    else
        local gold = math.floor(copper / 10000)
        local silver = math.floor((copper % 10000) / 100)
        local coppers = copper % 100
        text = string.format("%dg %ds %dc", gold, silver, coppers)
    end

    if unverified then
        return "~" .. text
    end
    return text
end

local function ItemAppearance(itemID, itemLink)
    local name, link, icon
    link = itemLink

    if C_Item.GetItemNameByID then
        name = C_Item.GetItemNameByID(itemID)
    end
    if C_Item.GetItemIconByID then
        icon = C_Item.GetItemIconByID(itemID)
    end
    if GetItemInfo and (not name or not link) then
        local infoName, infoLink, _, _, _, _, _, _, _, infoIcon = GetItemInfo(link or itemID)
        name = name or infoName
        link = link or infoLink
        icon = icon or infoIcon
    end
    if not name and itemID and not requestedItems[itemID] and C_Item.RequestLoadItemDataByID then
        requestedItems[itemID] = true
        C_Item.RequestLoadItemDataByID(itemID)
    end

    return name, link, icon
end

local function ChangeColor(delta)
    if not delta or delta == 0 then
        return 0.85, 0.85, 0.85
    end
    if delta > 0 then
        return 0.30, 0.86, 0.40
    end
    return 0.95, 0.38, 0.32
end

local function FormatSignedMoney(copper)
    if type(copper) ~= "number" then
        return "—", 0.65, 0.65, 0.65
    end
    local sign = copper > 0 and "+" or (copper < 0 and "-" or "")
    local red, green, blue = ChangeColor(copper)
    return sign .. FormatMoney(math.abs(copper)), red, green, blue
end

local function FormatSignedPercent(percent)
    if type(percent) ~= "number" then
        return "—", 0.65, 0.65, 0.65
    end
    local sign = percent > 0 and "+" or ""
    local red, green, blue = ChangeColor(percent)
    return string.format("%s%.1f%%", sign, percent), red, green, blue
end

local MARKET_SOURCE_TSM = "tsm"
local MARKET_SOURCE_AUCTIONATOR = "auctionator"
local TSM_PRICE_SOURCES = {
    { key = "DBMinBuyout", label = "Min Buyout" },
    { key = "DBMarket", label = "Market Value" },
    { key = "DBHistorical", label = "Historical" },
    { key = "DBRegionMarketAvg", label = "Region Market Avg" },
    { key = "DBRegionMinBuyoutAvg", label = "Region Min Buyout Avg" },
    { key = "DBRegionSaleAvg", label = "Region Sale Avg" },
}
local auctionatorWatching = false

local function AddonIsInstalled(name)
    local info
    if C_AddOns and C_AddOns.GetAddOnInfo then
        info = C_AddOns.GetAddOnInfo(name)
    elseif GetAddOnInfo then
        info = GetAddOnInfo(name)
    end
    return type(info) == "string" and info ~= ""
end

local function TSMAvailable()
    return type(TSM_API) == "table" and TSM_API.GetCustomPriceValue ~= nil and TSM_API.ToItemString ~= nil
end

local function AuctionatorAvailable()
    return type(Auctionator) == "table"
        and type(Auctionator.API) == "table"
        and type(Auctionator.API.v1) == "table"
        and Auctionator.API.v1.GetAuctionPriceByItemID ~= nil
end

local function EffectiveMarketSource()
    local saved = DB().marketSource
    if saved == MARKET_SOURCE_TSM or saved == MARKET_SOURCE_AUCTIONATOR then
        return saved
    end
    if TSMAvailable() then
        return MARKET_SOURCE_TSM
    end
    if AuctionatorAvailable() then
        return MARKET_SOURCE_AUCTIONATOR
    end
    return MARKET_SOURCE_TSM
end

local function EffectiveTSMPriceSource()
    local saved = DB().tsmPriceSource
    for _, option in ipairs(TSM_PRICE_SOURCES) do
        if option.key == saved then
            return saved
        end
    end
    return "DBMinBuyout"
end

local function TSMPriceLabel(key)
    for _, option in ipairs(TSM_PRICE_SOURCES) do
        if option.key == key then
            return option.label
        end
    end
    return "Min Buyout"
end

local function CopperPrice(value)
    local number = PlainNumber(value)
    if not number or number <= 0 then
        return nil
    end
    return math.floor(number + 0.5)
end

local function TSMItemString(itemID, itemLink)
    local itemString
    if itemLink then
        local ok, value = pcall(TSM_API.ToItemString, itemLink)
        if ok and type(value) == "string" and value ~= "" then
            itemString = value
        end
    end
    if not itemString and itemID then
        local ok, value = pcall(TSM_API.ToItemString, "i:" .. itemID)
        if ok and type(value) == "string" and value ~= "" then
            itemString = value
        else
            itemString = "i:" .. tostring(itemID)
        end
    end
    return itemString
end

local function TSMMarketPrice(itemID, itemLink)
    if not TSMAvailable() then
        return nil
    end
    local itemString = TSMItemString(itemID, itemLink)
    if not itemString then
        return nil
    end
    local ok, value = pcall(TSM_API.GetCustomPriceValue, EffectiveTSMPriceSource(), itemString)
    if not ok then
        return nil
    end
    return CopperPrice(value)
end

local function AuctionatorMarketPrice(itemID, itemLink)
    if not AuctionatorAvailable() then
        return nil
    end
    local api = Auctionator.API.v1
    if itemLink and api.GetAuctionPriceByItemLink then
        local ok, value = pcall(api.GetAuctionPriceByItemLink, "WorldOfWallStreet", itemLink)
        local price = ok and CopperPrice(value) or nil
        if price then
            return price
        end
    end
    if not itemID then
        return nil
    end
    local ok, value = pcall(api.GetAuctionPriceByItemID, "WorldOfWallStreet", itemID)
    if not ok then
        return nil
    end
    return CopperPrice(value)
end

local function MarketUnitPrice(itemID, itemLink)
    if EffectiveMarketSource() == MARKET_SOURCE_AUCTIONATOR then
        return AuctionatorMarketPrice(itemID, itemLink)
    end
    return TSMMarketPrice(itemID, itemLink)
end

local function PositionMarketUnit(position)
    if not position then
        return nil
    end
    return MarketUnitPrice(position.itemID, position.itemLink)
end

local sparkCache = {}
local lastAuctionatorUpdate = 0
local auctionatorQuietWait = false
local AUCTIONATOR_QUIET_SECONDS = 1.5

local function AuctionatorSettled()
    return (GetTime() - lastAuctionatorUpdate) >= AUCTIONATOR_QUIET_SECONDS
end

local function OnAuctionatorQuiet()
    if not AuctionatorSettled() then
        C_Timer.After(AUCTIONATOR_QUIET_SECONDS, OnAuctionatorQuiet)
        return
    end
    auctionatorQuietWait = false
    sparkCache = {}
    if NS.UI and NS.UI.RefreshPortfolio then
        NS.UI.RefreshPortfolio()
    end
end

local function WatchAuctionator()
    if auctionatorWatching or not AuctionatorAvailable() or not Auctionator.API.v1.RegisterForDBUpdate then
        return
    end
    local ok = pcall(Auctionator.API.v1.RegisterForDBUpdate, "WorldOfWallStreet", function()
        lastAuctionatorUpdate = GetTime()
        if auctionatorQuietWait then
            return
        end
        auctionatorQuietWait = true
        C_Timer.After(AUCTIONATOR_QUIET_SECONDS, OnAuctionatorQuiet)
    end)
    if ok then
        auctionatorWatching = true
    end
end

local function BuildPositions()
    local groups = {}
    local order = {}
    for _, purchase in ipairs(DB().purchases) do
        if purchase.investment and purchase.itemID then
            local position = groups[purchase.itemID]
            if not position then
                position = {
                    itemID = purchase.itemID,
                    itemLink = purchase.itemLink,
                    quantity = 0,
                    costQuantity = 0,
                    baseCost = 0,
                    knownCost = true,
                    lots = {},
                }
                groups[purchase.itemID] = position
                order[#order + 1] = position
            end
            if purchase.itemLink then
                position.itemLink = purchase.itemLink
            end
            local quantity = purchase.quantity or 1
            position.quantity = position.quantity + quantity
            if type(purchase.totalCost) == "number" then
                position.baseCost = position.baseCost + purchase.totalCost
                position.costQuantity = position.costQuantity + quantity
            else
                position.knownCost = false
            end
            position.lots[#position.lots + 1] = purchase
        end
    end

    for _, position in ipairs(order) do
        if position.costQuantity > 0 then
            position.avgCost = math.floor(position.baseCost / position.costQuantity)
        end
        table.sort(position.lots, function(a, b)
            return (a.boughtAt or 0) > (b.boughtAt or 0)
        end)

        local unitMarket = MarketUnitPrice(position.itemID, position.itemLink)
        local marketValue = unitMarket and position.quantity and (unitMarket * position.quantity) or nil
        local basis = position.costQuantity > 0 and position.baseCost or nil
        local unrealized = nil
        local percent = nil
        if position.knownCost and basis and marketValue then
            unrealized = marketValue - basis
            if basis ~= 0 then
                percent = (unrealized / basis) * 100
            else
                percent = 0
            end
        end
        position.sort = {
            item = ItemAppearance(position.itemID, position.itemLink) or "",
            qty = position.quantity or 0,
            avg = basis and position.avgCost or nil,
            market = unitMarket,
            basis = basis,
            mktValue = marketValue,
            unrealized = unrealized,
            percent = percent,
        }
    end

    local sortKey = DB().portfolioSortKey
    if sortKey ~= "item" and sortKey ~= "qty" and sortKey ~= "avg" and sortKey ~= "market"
        and sortKey ~= "basis" and sortKey ~= "mktValue" and sortKey ~= "unrealized" and sortKey ~= "percent" then
        sortKey = "item"
    end
    local ascending = DB().portfolioSortAscending
    if type(ascending) ~= "boolean" then
        ascending = true
    end

    local function NameBefore(a, b)
        local nameA = a.sort.item
        local nameB = b.sort.item
        if nameA ~= nameB then
            if strcmputf8i then
                return strcmputf8i(nameA, nameB) < 0
            end
            return nameA < nameB
        end
        return a.itemID < b.itemID
    end

    table.sort(order, function(a, b)
        if sortKey == "item" then
            if ascending then
                return NameBefore(a, b)
            end
            return NameBefore(b, a)
        end
        local valueA = a.sort[sortKey]
        local valueB = b.sort[sortKey]
        if valueA == valueB then
            return NameBefore(a, b)
        end
        if valueA == nil then
            return false
        end
        if valueB == nil then
            return true
        end
        if ascending then
            return valueA < valueB
        end
        return valueA > valueB
    end)

    return order
end

local function PortfolioOverview(positions)
    local currentValue = 0
    local priced = 0
    local missingPrice = 0
    local unrealized = 0
    local unrealizedBasis = 0
    local haveUnrealized = false
    local ranked = {}

    for _, position in ipairs(positions or {}) do
        local value = position.sort and position.sort.mktValue or nil
        if type(value) == "number" and value > 0 then
            currentValue = currentValue + value
            priced = priced + 1
            local name = position.sort.item
            if type(name) ~= "string" or name == "" then
                name = "Item " .. tostring(position.itemID)
            end
            ranked[#ranked + 1] = {
                itemID = position.itemID,
                itemLink = position.itemLink,
                name = name,
                value = value,
            }
        else
            missingPrice = missingPrice + 1
        end
        if position.sort and type(position.sort.unrealized) == "number" then
            haveUnrealized = true
            unrealized = unrealized + position.sort.unrealized
            unrealizedBasis = unrealizedBasis + (position.sort.basis or 0)
        end
    end

    table.sort(ranked, function(a, b)
        if a.value ~= b.value then
            return a.value > b.value
        end
        return a.name < b.name
    end)

    local slices = {}
    local otherValue = 0
    for index, entry in ipairs(ranked) do
        if index <= 10 then
            slices[#slices + 1] = entry
        else
            otherValue = otherValue + entry.value
        end
    end
    if otherValue > 0 then
        slices[#slices + 1] = { name = "Other", value = otherValue, isOther = true }
    end
    for _, slice in ipairs(slices) do
        slice.weight = currentValue > 0 and (slice.value / currentValue) or 0
    end

    local percent = nil
    if haveUnrealized then
        if unrealizedBasis ~= 0 then
            percent = (unrealized / unrealizedBasis) * 100
        else
            percent = 0
        end
    end

    return {
        currentValue = priced > 0 and currentValue or nil,
        missingPrice = missingPrice,
        unrealized = haveUnrealized and unrealized or nil,
        unrealizedPercent = percent,
        slices = slices,
    }
end

local function QuantityInList(list, itemID)
    local total = 0
    if type(list) == "table" then
        for _, entry in ipairs(list) do
            if entry.itemID == itemID then
                total = total + (entry.quantity or 0)
            end
        end
    end
    return total
end

local function OwnedQuantity(itemID)
    local record = CharacterRecord()
    if not record or not itemID then
        return 0
    end
    return QuantityInList(record.bags, itemID) + QuantityInList(record.bank, itemID)
end

local function PortfolioQuantity(itemID)
    local total = 0
    if not itemID then
        return 0
    end
    for _, purchase in ipairs(DB().purchases) do
        if purchase.investment and purchase.itemID == itemID then
            total = total + (purchase.quantity or 0)
        end
    end
    return total
end

local function RegistrableQuantity(item)
    if not item or not item.itemID then
        return 0
    end
    local remaining = OwnedQuantity(item.itemID) - PortfolioQuantity(item.itemID)
    if remaining < 0 then
        remaining = 0
    end
    local here = item.quantity or 0
    if remaining > here then
        remaining = here
    end
    return remaining
end

local SPARK_DAYS = 30
local DAY_SECONDS = 86400

local function AuctionatorDBKeys(itemID, itemLink)
    local keys = {}
    local seen = {}
    local function add(key)
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            keys[#keys + 1] = key
        end
    end
    if itemLink and Auctionator and Auctionator.Utilities and Auctionator.Utilities.BasicDBKeyFromLink then
        local ok, key = pcall(Auctionator.Utilities.BasicDBKeyFromLink, itemLink)
        if ok then
            add(key)
        end
    end
    if itemID then
        add("i:" .. tostring(itemID))
    end
    return keys
end

local function PricesFromHistory(history)
    local prices = {}
    if type(history) ~= "table" then
        return prices
    end
    if type(history.l) == "table" then
        local days = {}
        for day, price in pairs(history.l) do
            days[#days + 1] = { day = tonumber(day) or 0, price = price }
        end
        table.sort(days, function(a, b)
            return a.day < b.day
        end)
        local startAt = math.max(1, #days - (SPARK_DAYS - 1))
        for index = startAt, #days do
            local price = CopperPrice(days[index].price)
            if price then
                prices[#prices + 1] = price
            end
        end
        return prices
    end
    if #history < 1 then
        return prices
    end
    local startAt = math.max(1, #history - (SPARK_DAYS - 1))
    for index = startAt, #history do
        local entry = history[index]
        local raw = entry
        if type(entry) == "table" then
            raw = entry.minSeen or entry.price or entry.min
        end
        local price = CopperPrice(raw)
        if price then
            prices[#prices + 1] = price
        end
    end
    return prices
end

local function AuctionatorHistory(itemID, itemLink)
    if not Auctionator or not Auctionator.Database or not Auctionator.Database.GetPriceHistory then
        return {}
    end
    for _, key in ipairs(AuctionatorDBKeys(itemID, itemLink)) do
        local ok, history = pcall(Auctionator.Database.GetPriceHistory, Auctionator.Database, key)
        if ok then
            local prices = PricesFromHistory(history)
            if #prices >= 2 then
                return prices
            end
        end
    end
    return {}
end

local function SavedSparkline(itemID, price)
    local db = DB()
    if type(db.marketHistory) ~= "table" then
        db.marketHistory = {}
    end
    local key = tostring(itemID)
    local series = db.marketHistory[key]
    if type(series) ~= "table" then
        series = {}
        db.marketHistory[key] = series
    end
    local day = math.floor((GetServerTime() or 0) / DAY_SECONDS)
    local cutoff = day - (SPARK_DAYS - 1)
    local writeIndex = 1
    for readIndex = 1, #series do
        local sample = series[readIndex]
        if type(sample) == "table" and type(sample.day) == "number" and sample.day >= cutoff and type(sample.price) == "number" then
            series[writeIndex] = sample
            writeIndex = writeIndex + 1
        end
    end
    for index = writeIndex, #series do
        series[index] = nil
    end
    if price and price > 0 then
        local last = series[#series]
        if last and last.day == day then
            if last.price ~= price then
                last.price = price
            end
        else
            series[#series + 1] = { day = day, price = price }
            if last and last.day > day then
                table.sort(series, function(a, b)
                    return a.day < b.day
                end)
            end
        end
    end
    local prices = {}
    for index = 1, #series do
        prices[index] = series[index].price
    end
    return prices
end

local function MarketSparkline(itemID, itemLink)
    if not itemID then
        return {}
    end
    local source = EffectiveMarketSource()
    local day = math.floor((GetServerTime() or 0) / DAY_SECONDS)
    local cacheKey = tostring(itemID) .. ":" .. source .. ":" .. tostring(day)
    if source == MARKET_SOURCE_TSM then
        cacheKey = cacheKey .. ":" .. tostring(EffectiveTSMPriceSource())
    end
    local cached = sparkCache[cacheKey]
    if cached then
        return cached
    end

    local settled = AuctionatorSettled()
    local price = settled and MarketUnitPrice(itemID, itemLink) or nil
    local saved = SavedSparkline(itemID, price)
    local prices = saved
    if settled and source == MARKET_SOURCE_AUCTIONATOR then
        local history = AuctionatorHistory(itemID, itemLink)
        if #history >= 2 then
            prices = history
        end
    end
    if settled then
        sparkCache[cacheKey] = prices
    end
    return prices
end

local function ClearItemRequest(itemID, success)
    if not success then
        requestedItems[itemID] = nil
    end
end

NS.Logic.FormatMoney = FormatMoney
NS.Logic.ItemAppearance = ItemAppearance
NS.Logic.FormatSignedMoney = FormatSignedMoney
NS.Logic.FormatSignedPercent = FormatSignedPercent
NS.Logic.BuildPositions = BuildPositions
NS.Logic.PortfolioOverview = PortfolioOverview
NS.Logic.MarketUnitPrice = MarketUnitPrice
NS.Logic.PositionMarketUnit = PositionMarketUnit
NS.Logic.MarketSparkline = MarketSparkline
NS.Logic.EffectiveMarketSource = EffectiveMarketSource
NS.Logic.EffectiveTSMPriceSource = EffectiveTSMPriceSource
NS.Logic.TSMPriceLabel = TSMPriceLabel
NS.Logic.TSM_PRICE_SOURCES = TSM_PRICE_SOURCES
NS.Logic.MARKET_SOURCE_TSM = MARKET_SOURCE_TSM
NS.Logic.MARKET_SOURCE_AUCTIONATOR = MARKET_SOURCE_AUCTIONATOR
NS.Logic.AddonIsInstalled = AddonIsInstalled
NS.Logic.TSMAvailable = TSMAvailable
NS.Logic.AuctionatorAvailable = AuctionatorAvailable
NS.Logic.WatchAuctionator = WatchAuctionator
NS.Logic.OwnedQuantity = OwnedQuantity
NS.Logic.PortfolioQuantity = PortfolioQuantity
NS.Logic.RegistrableQuantity = RegistrableQuantity
NS.Logic.ClearItemRequest = ClearItemRequest
