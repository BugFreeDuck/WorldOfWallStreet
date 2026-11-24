local ADDON_NAME = ...

local MAX_PURCHASES = 200
local ROW_HEIGHT = 44
local ROW_GAP = 4
local ROW_STRIDE = ROW_HEIGHT + ROW_GAP
local POSITION_HEIGHT = 36
local LOT_HEIGHT = 24
local DEDUPE_SECONDS = 0.75

local mainFrame
local scrollFrame
local scrollContent
local emptyText
local rowPool = {}
local minimapButton

local pendingQuote
local auctionCache = {}
local recordedAt = {}
local requestedItems = {}
local refreshing = false
local lastCommodityItemID
local headerText
local purchasesPanel
local portfolioPanel
local purchasesTab
local portfolioTab
local portfolioScroll
local portfolioContent
local portfolioEmpty
local portfolioTitle
local portfolioHeader
local positionPool = {}
local lotPool = {}
local expandedPositions = {}
local refreshingPortfolio = false
local activeTab = "portfolio"
local holdingsPanel
local holdingsTab
local holdingsScroll
local holdingsContent
local holdingsEmpty
local holdingsTitle
local holdingsNote
local holdingsQuantity
local holdingsCost
local holdingsAddButton
local holdingPool = {}
local holdingItems = {}
local selectedHoldingID
local formItemID
local holdingsLocation = "bags"
local refreshingHoldings = false
local RefreshHoldings
local characterBankOpen = false

local COLUMN_PERCENT = { offset = 8, width = 52 }
local COLUMN_UNREALIZED = { offset = 64, width = 112 }
local COLUMN_MKT_VALUE = { offset = 180, width = 112 }
local COLUMN_BASIS = { offset = 296, width = 112 }
local COLUMN_MARKET = { offset = 412, width = 100 }
local COLUMN_AVG = { offset = 516, width = 100 }
local COLUMN_QTY = { offset = 620, width = 44 }

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
    local quantity = fields.quantity or 1
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

    if mainFrame and mainFrame:IsShown() then
        mainFrame:Refresh()
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
                    quantity = ok and PlainNumber(value) or nil
                end
                if not quantity and input.GetNumber then
                    local ok, value = pcall(input.GetNumber, input)
                    quantity = ok and PlainNumber(value) or nil
                end
                if not quantity and input.GetText then
                    local ok, text = pcall(input.GetText, input)
                    quantity = ok and tonumber(text) or nil
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

local function CommitCommodityPurchase(itemID, quantity, totalCost, unverified)
    itemID = PlainNumber(itemID)
    quantity = PlainNumber(quantity)
    totalCost = PlainNumber(totalCost)
    if not itemID or WasJustRecorded(itemID) then
        return false
    end

    AddPurchase({
        itemID = itemID,
        quantity = quantity or 1,
        totalCost = totalCost,
        kind = "commodity",
        unverified = unverified or totalCost == nil or quantity == nil,
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
                quantity = info.quantity or 1,
                buyout = info.buyoutAmount,
            }
        end
    end
end

local function ToggleWindow()
    if not mainFrame then
        return
    end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        mainFrame:Show()
    end
end

local function PlaceMinimapButton(angle)
    if not minimapButton then
        return
    end
    local rad = math.rad(angle)
    local radius = (Minimap:GetWidth() / 2) + 8
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

local function CreateMinimapButton()
    local button = CreateFrame("Button", "WorldOfWallStreetMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(19, 19)
    icon:SetPoint("CENTER", 0, 1)
    icon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    button:SetScript("OnClick", ToggleWindow)
    button:SetScript("OnDragStart", function(self)
        self:SetScript("OnUpdate", function()
            local centerX, centerY = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cursorX, cursorY = GetCursorPosition()
            cursorX, cursorY = cursorX / scale, cursorY / scale
            local angle = math.deg(math.atan2(cursorY - centerY, cursorX - centerX))
            DB().minimapAngle = angle
            PlaceMinimapButton(angle)
        end)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("World of Wall Street")
        GameTooltip:AddLine("Recent auction purchases", 1, 1, 1)
        GameTooltip:AddLine("Drag to move", 0.75, 0.75, 0.75)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    minimapButton = button
end

local function CreateRow(parent)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(ROW_HEIGHT)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    local iconButton = CreateFrame("Button", nil, row)
    iconButton:SetSize(32, 32)
    iconButton:SetPoint("LEFT", 6, 0)
    local icon = iconButton:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    row.icon = icon
    row.iconButton = iconButton

    local markButton = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    markButton:SetSize(76, 22)
    markButton:SetPoint("RIGHT", -6, 0)
    markButton:SetScript("OnClick", function(self)
        local purchase = FindPurchase(self:GetParent().purchaseID)
        if not purchase then
            return
        end
        purchase.investment = not purchase.investment
        if mainFrame then
            mainFrame:Refresh()
        end
    end)
    row.markButton = markButton

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("TOPLEFT", iconButton, "TOPRIGHT", 8, -2)
    name:SetPoint("RIGHT", markButton, "LEFT", -8, 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    if name.SetMaxLines then
        name:SetMaxLines(1)
    end
    row.name = name

    local detail = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail:SetPoint("BOTTOMLEFT", iconButton, "BOTTOMRIGHT", 8, 3)
    detail:SetPoint("RIGHT", markButton, "LEFT", -8, 0)
    detail:SetJustifyH("LEFT")
    detail:SetWordWrap(false)
    if detail.SetMaxLines then
        detail:SetMaxLines(1)
    end
    row.detail = detail

    iconButton:SetScript("OnEnter", function(self)
        local purchase = FindPurchase(self:GetParent().purchaseID)
        if not purchase then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if purchase.itemLink then
            GameTooltip:SetHyperlink(purchase.itemLink)
        else
            GameTooltip:SetItemByID(purchase.itemID)
        end
        GameTooltip:Show()
    end)
    iconButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return row
end

local function ApplyRow(row, purchase)
    row.purchaseID = purchase.id
    row:Show()

    local name, link, icon = ItemAppearance(purchase.itemID, purchase.itemLink)
    if link and link ~= purchase.itemLink then
        purchase.itemLink = link
    end

    row.name:SetText(link or name or ("Item " .. tostring(purchase.itemID)))
    if icon then
        row.icon:SetTexture(icon)
    else
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end

    local when = date("%b %d  %H:%M", purchase.boughtAt or GetServerTime())
    row.detail:SetText(string.format("x%d    %s    %s", purchase.quantity or 1, FormatMoney(purchase.totalCost, purchase.unverified), when))

    if purchase.investment then
        row:SetBackdropColor(0.10, 0.24, 0.13, 0.95)
        row:SetBackdropBorderColor(0.35, 0.62, 0.34, 1)
        row.markButton:SetText("Marked")
    else
        row:SetBackdropColor(0.07, 0.07, 0.07, 0.85)
        row:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)
        row.markButton:SetText("Mark")
    end
end

local function RefreshPurchases()
    if refreshing or not scrollFrame or not scrollContent then
        return
    end
    refreshing = true

    local ok, err = pcall(function()
    local purchases = DB().purchases
    local width = scrollFrame:GetWidth()
    if not width or width < 20 then
        width = 460
    end
    scrollContent:SetWidth(width)

    local shown = 0
    for index = #purchases, 1, -1 do
        shown = shown + 1
        local row = rowPool[shown]
        if not row then
            row = CreateRow(scrollContent)
            rowPool[shown] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", scrollContent, "TOPLEFT", 0, -((shown - 1) * ROW_STRIDE))
        row:SetPoint("TOPRIGHT", scrollContent, "TOPRIGHT", 0, -((shown - 1) * ROW_STRIDE))
        ApplyRow(row, purchases[index])
    end

    for index = shown + 1, #rowPool do
        rowPool[index]:Hide()
    end

    scrollContent:SetHeight(math.max(1, shown * ROW_STRIDE))
    if scrollFrame.UpdateScrollChildRect then
        scrollFrame:UpdateScrollChildRect()
    end

    local maxScroll = math.max(0, scrollContent:GetHeight() - scrollFrame:GetHeight())
    if scrollFrame:GetVerticalScroll() > maxScroll then
        scrollFrame:SetVerticalScroll(maxScroll)
    end

    emptyText:SetShown(shown == 0)
    if headerText then
        if shown == 0 then
            headerText:SetText("Recent purchases")
        else
            headerText:SetText(string.format("Recent purchases (%d)", shown))
        end
    end
    end)

    refreshing = false
    if not ok then
        geterrorhandler()(err)
    end
end

local function PlaceRightColumn(fontString, parent, column, yOffset)
    fontString:ClearAllPoints()
    fontString:SetPoint("RIGHT", parent, "RIGHT", -column.offset, yOffset or 0)
    fontString:SetWidth(column.width)
    fontString:SetJustifyH("RIGHT")
    fontString:SetWordWrap(false)
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

local function PositionMarketUnit()
    return nil
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
    end

    table.sort(order, function(a, b)
        local nameA = ItemAppearance(a.itemID, a.itemLink) or ""
        local nameB = ItemAppearance(b.itemID, b.itemLink) or ""
        if nameA ~= nameB then
            if strcmputf8i then
                return strcmputf8i(nameA, nameB) < 0
            end
            return nameA < nameB
        end
        return a.itemID < b.itemID
    end)

    return order
end

local function CreatePositionRow(parent)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetHeight(POSITION_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    highlight:SetVertexColor(1, 1, 1, 0.08)

    local chevron = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    chevron:SetPoint("LEFT", 8, 0)
    chevron:SetWidth(12)
    row.chevron = chevron

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(24, 24)
    icon:SetPoint("LEFT", 24, 0)
    row.icon = icon

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", 54, 0)
    name:SetPoint("RIGHT", row, "RIGHT", -(COLUMN_QTY.offset + COLUMN_QTY.width + 8), 0)
    name:SetJustifyH("LEFT")
    name:SetWordWrap(false)
    row.name = name

    row.quantity = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.avg = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.market = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.base = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.mktValue = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.unrealized = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.percent = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

    row:SetScript("OnClick", function(self)
        if not self.itemID then
            return
        end
        expandedPositions[self.itemID] = not expandedPositions[self.itemID]
        if mainFrame then
            mainFrame:RefreshPortfolio()
        end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.itemID then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemLink then
            GameTooltip:SetHyperlink(self.itemLink)
        else
            GameTooltip:SetItemByID(self.itemID)
        end
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return row
end

local function CreateLotRow(parent)
    local row = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    row:SetHeight(LOT_HEIGHT)
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    row:SetBackdropColor(0.04, 0.04, 0.04, 0.9)
    row:SetBackdropBorderColor(0.14, 0.14, 0.14, 1)

    local when = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    when:SetPoint("LEFT", 54, 0)
    when:SetPoint("RIGHT", row, "RIGHT", -(COLUMN_QTY.offset + COLUMN_QTY.width + 8), 0)
    when:SetJustifyH("LEFT")
    when:SetWordWrap(false)
    row.when = when

    row.quantity = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.avg = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.market = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.base = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.mktValue = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.unrealized = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    row.percent = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    return row
end

local function ApplyPositionColumns(row)
    PlaceRightColumn(row.quantity, row, COLUMN_QTY)
    PlaceRightColumn(row.avg, row, COLUMN_AVG)
    PlaceRightColumn(row.market, row, COLUMN_MARKET)
    PlaceRightColumn(row.base, row, COLUMN_BASIS)
    PlaceRightColumn(row.mktValue, row, COLUMN_MKT_VALUE)
    PlaceRightColumn(row.unrealized, row, COLUMN_UNREALIZED)
    PlaceRightColumn(row.percent, row, COLUMN_PERCENT)
end

local function ApplyPositionRow(row, position, expanded)
    row.itemID = position.itemID
    row.itemLink = position.itemLink
    row:Show()
    ApplyPositionColumns(row)

    local name, link, icon = ItemAppearance(position.itemID, position.itemLink)
    if link then
        row.itemLink = link
        for _, lot in ipairs(position.lots) do
            if not lot.itemLink then
                lot.itemLink = link
            end
        end
    end

    row.chevron:SetText(expanded and "-" or "+")
    row.name:SetText(link or name or ("Item " .. tostring(position.itemID)))
    if icon then
        row.icon:SetTexture(icon)
    else
        row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    end
    row.quantity:SetText(tostring(position.quantity))

    if position.costQuantity > 0 then
        row.avg:SetText(FormatMoney(position.avgCost, not position.knownCost))
        row.base:SetText(FormatMoney(position.baseCost, not position.knownCost))
    else
        row.avg:SetText("Unknown")
        row.base:SetText("Unknown")
    end

    local unitMarket = PositionMarketUnit(position)
    local marketValue = unitMarket and position.quantity and (unitMarket * position.quantity) or nil
    local basis = position.costQuantity > 0 and position.baseCost or nil
    row.market:SetText(unitMarket and FormatMoney(unitMarket) or "—")
    row.mktValue:SetText(marketValue and FormatMoney(marketValue) or "—")

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
    local unrealizedText, red, green, blue = FormatSignedMoney(unrealized)
    row.unrealized:SetText(unrealizedText)
    row.unrealized:SetTextColor(red, green, blue)
    local percentText, percentRed, percentGreen, percentBlue = FormatSignedPercent(percent)
    row.percent:SetText(percentText)
    row.percent:SetTextColor(percentRed, percentGreen, percentBlue)

    if expanded then
        row:SetBackdropColor(0.12, 0.11, 0.07, 0.95)
        row:SetBackdropBorderColor(0.72, 0.60, 0.22, 1)
    else
        row:SetBackdropColor(0.07, 0.07, 0.07, 0.9)
        row:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)
    end
end

local function ApplyLotRow(row, lot)
    row:Show()
    ApplyPositionColumns(row)
    local when = date("%b %d  %H:%M", lot.boughtAt or GetServerTime())
    if lot.kind == "bags" then
        when = when .. "   Bags"
    elseif lot.kind == "bank" then
        when = when .. "   Bank"
    end
    row.when:SetText(when)
    row.quantity:SetText(tostring(lot.quantity or 1))
    if type(lot.totalCost) == "number" and (lot.quantity or 1) > 0 then
        local unit = lot.unitCost or math.floor(lot.totalCost / (lot.quantity or 1))
        row.avg:SetText(FormatMoney(unit, lot.unverified))
        row.base:SetText(FormatMoney(lot.totalCost, lot.unverified))
    else
        row.avg:SetText("Unknown")
        row.base:SetText("Unknown")
    end
    row.market:SetText("—")
    row.mktValue:SetText("—")
    row.unrealized:SetText("—")
    row.percent:SetText("—")
end

local function RefreshPortfolio()
    if refreshingPortfolio or not portfolioScroll or not portfolioContent then
        return
    end
    refreshingPortfolio = true

    local ok, err = pcall(function()
        local positions = BuildPositions()
        local width = portfolioScroll:GetWidth()
        if not width or width < 20 then
            width = 820
        end
        portfolioContent:SetWidth(width)

        local y = 0
        local positionIndex = 0
        local lotIndex = 0
        for _, position in ipairs(positions) do
            positionIndex = positionIndex + 1
            local row = positionPool[positionIndex]
            if not row then
                row = CreatePositionRow(portfolioContent)
                positionPool[positionIndex] = row
            end
            local expanded = expandedPositions[position.itemID] and true or false
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", portfolioContent, "TOPLEFT", 0, -y)
            row:SetPoint("TOPRIGHT", portfolioContent, "TOPRIGHT", 0, -y)
            ApplyPositionRow(row, position, expanded)
            y = y + POSITION_HEIGHT + ROW_GAP

            if expanded then
                for _, lot in ipairs(position.lots) do
                    lotIndex = lotIndex + 1
                    local lotRow = lotPool[lotIndex]
                    if not lotRow then
                        lotRow = CreateLotRow(portfolioContent)
                        lotPool[lotIndex] = lotRow
                    end
                    lotRow:ClearAllPoints()
                    lotRow:SetPoint("TOPLEFT", portfolioContent, "TOPLEFT", 0, -y)
                    lotRow:SetPoint("TOPRIGHT", portfolioContent, "TOPRIGHT", 0, -y)
                    ApplyLotRow(lotRow, lot)
                    y = y + LOT_HEIGHT + 2
                end
            end
        end

        for index = positionIndex + 1, #positionPool do
            positionPool[index]:Hide()
        end
        for index = lotIndex + 1, #lotPool do
            lotPool[index]:Hide()
        end

        portfolioContent:SetHeight(math.max(1, y))
        if portfolioScroll.UpdateScrollChildRect then
            portfolioScroll:UpdateScrollChildRect()
        end
        local maxScroll = math.max(0, portfolioContent:GetHeight() - portfolioScroll:GetHeight())
        if portfolioScroll:GetVerticalScroll() > maxScroll then
            portfolioScroll:SetVerticalScroll(maxScroll)
        end

        portfolioEmpty:SetShown(#positions == 0)
        if portfolioTitle then
            if #positions == 0 then
                portfolioTitle:SetText("Positions")
            else
                portfolioTitle:SetText(string.format("Positions (%d)", #positions))
            end
        end
    end)

    refreshingPortfolio = false
    if not ok then
        geterrorhandler()(err)
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
        local nameA = ItemAppearance(a.itemID, a.itemLink) or ""
        local nameB = ItemAppearance(b.itemID, b.itemLink) or ""
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

local function CurrentHoldings()
    local record = CharacterRecord()
    if not record then
        return {}, nil
    end
    if holdingsLocation == "bank" then
        return record.bank or {}, record
    end
    return record.bags or {}, record
end

local function SelectedHolding()
    if not selectedHoldingID then
        return nil
    end
    for _, item in ipairs(holdingItems) do
        if item.itemID == selectedHoldingID then
            return item
        end
    end
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

local function ClearUnitCost()
    if holdingsCost and MoneyInputFrame_ResetMoney then
        MoneyInputFrame_ResetMoney(holdingsCost)
    end
end

local function ParseUnitCost()
    if not holdingsCost or not MoneyInputFrame_GetCopper then
        return nil
    end
    local copper = MoneyInputFrame_GetCopper(holdingsCost)
    if not copper or copper <= 0 then
        return nil
    end
    return copper
end

local function SelectHolding(itemID)
    selectedHoldingID = itemID
    local item = SelectedHolding()
    ClearUnitCost()
    if item and holdingsQuantity then
        holdingsQuantity:SetText(tostring(RegistrableQuantity(item)))
        holdingsQuantity:ClearFocus()
        formItemID = item.itemID
    end
    RefreshHoldings()
end

local function UpdateHoldingForm()
    local item = SelectedHolding()
    local available = RegistrableQuantity(item)
    if holdingsAddButton then
        holdingsAddButton:SetEnabled(available >= 1)
    end
    if not item then
        formItemID = nil
        return
    end
    if not holdingsQuantity then
        return
    end
    if formItemID ~= item.itemID then
        formItemID = item.itemID
        holdingsQuantity:SetText(tostring(available))
        return
    end
    local typed = tonumber(holdingsQuantity:GetText()) or 0
    if typed > available then
        holdingsQuantity:SetText(tostring(available))
    end
end

local function AddSelectedHolding()
    local item = SelectedHolding()
    if not item then
        return
    end
    local available = RegistrableQuantity(item)
    if available < 1 then
        return
    end
    local quantity = tonumber(holdingsQuantity and holdingsQuantity:GetText()) or available
    quantity = math.floor(quantity)
    if quantity < 1 then
        quantity = 1
    end
    if quantity > available then
        quantity = available
    end
    local unitCost = ParseUnitCost()
    local totalCost = unitCost and unitCost * quantity or nil
    AddPurchase({
        itemID = item.itemID,
        itemLink = item.itemLink,
        quantity = quantity,
        totalCost = totalCost,
        kind = holdingsLocation,
        investment = true,
        unverified = totalCost == nil,
    })
    if holdingsNote then
        local name = ItemAppearance(item.itemID, item.itemLink) or "Item"
        holdingsNote:SetText(string.format("Added %d %s to the portfolio.", quantity, name))
    end
    if holdingsQuantity then
        holdingsQuantity:SetText(tostring(RegistrableQuantity(item)))
    end
    RefreshPortfolio()
    RefreshHoldings()
end

local HOLDING_CELL_WIDTH = 76
local HOLDING_CELL_HEIGHT = 84
local HOLDING_CELL_GAP = 8

local function CreateHoldingRow(parent)
    local row = CreateFrame("Button", nil, parent, "BackdropTemplate")
    row:SetSize(HOLDING_CELL_WIDTH, HOLDING_CELL_HEIGHT)
    row:RegisterForClicks("LeftButtonUp")
    row:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 2,
    })
    row:EnableMouse(true)
    local selected = CreateFrame("Frame", nil, row, "BackdropTemplate")
    selected:SetAllPoints()
    selected:EnableMouse(false)
    selected:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 3,
    })
    selected:SetBackdropBorderColor(0.45, 0.86, 1, 1)
    selected:Hide()
    row.selected = selected
    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetTexture("Interface\\Buttons\\WHITE8X8")
    highlight:SetVertexColor(1, 1, 1, 0.06)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(36, 36)
    icon:SetPoint("TOP", 0, -8)
    row.icon = icon

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    name:SetPoint("TOPLEFT", 4, -46)
    name:SetPoint("TOPRIGHT", -4, -46)
    name:SetJustifyH("CENTER")
    name:SetWordWrap(false)
    row.name = name

    local quantity = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    quantity:SetPoint("BOTTOM", 0, 6)
    quantity:SetJustifyH("CENTER")
    row.quantity = quantity

    row:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and self.itemID then
            SelectHolding(self.itemID)
        end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.itemID then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self.itemLink then
            GameTooltip:SetHyperlink(self.itemLink)
        else
            GameTooltip:SetItemByID(self.itemID)
        end
        local held = self.heldQuantity or 0
        local registered = self.registeredQuantity or 0
        local open = self.openQuantity or 0
        GameTooltip:AddLine(string.format("%d held here, %d in portfolio, %d still open", held, registered, open), 1, 0.82, 0)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return row
end

function RefreshHoldings()
    if refreshingHoldings or not holdingsScroll or not holdingsContent then
        return
    end
    refreshingHoldings = true

    local ok, err = pcall(function()
        local items, record = CurrentHoldings()
        holdingItems = items
        if selectedHoldingID then
            local stillThere = false
            for _, item in ipairs(items) do
                if item.itemID == selectedHoldingID then
                    stillThere = true
                    break
                end
            end
            if not stillThere then
                selectedHoldingID = nil
                formItemID = nil
            end
        end

        local width = holdingsScroll:GetWidth()
        if not width or width < 20 then
            width = 820
        end
        holdingsContent:SetWidth(width)

        local stride = HOLDING_CELL_WIDTH + HOLDING_CELL_GAP
        local columns = math.max(1, math.floor((width + HOLDING_CELL_GAP) / stride))
        for index, item in ipairs(items) do
            local row = holdingPool[index]
            if not row then
                row = CreateHoldingRow(holdingsContent)
                holdingPool[index] = row
            end
            local column = (index - 1) % columns
            local gridRow = math.floor((index - 1) / columns)
            row.itemID = item.itemID
            row.itemLink = item.itemLink
            row:ClearAllPoints()
            row:SetSize(HOLDING_CELL_WIDTH, HOLDING_CELL_HEIGHT)
            row:SetPoint("TOPLEFT", holdingsContent, "TOPLEFT", column * stride, -(gridRow * (HOLDING_CELL_HEIGHT + HOLDING_CELL_GAP)))
            row:Show()

            local name, link, icon = ItemAppearance(item.itemID, item.itemLink)
            if link then
                item.itemLink = link
                row.itemLink = link
            end
            local held = item.quantity or 0
            local registered = PortfolioQuantity(item.itemID)
            local owned = OwnedQuantity(item.itemID)
            local full = owned > 0 and registered >= owned
            local partial = registered > 0 and not full
            row.heldQuantity = held
            row.registeredQuantity = registered
            row.openQuantity = RegistrableQuantity(item)
            row.name:SetText(name or ("Item " .. tostring(item.itemID)))
            row.quantity:SetText(string.format("%d/%d", held, registered))
            if icon then
                row.icon:SetTexture(icon)
            else
                row.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            end
            local isSelected = item.itemID == selectedHoldingID
            if full then
                row:SetBackdropColor(0.08, 0.24, 0.12, 0.95)
                row:SetBackdropBorderColor(0.30, 0.86, 0.40, 1)
                row.quantity:SetTextColor(0.45, 0.95, 0.55)
            elseif partial then
                row:SetBackdropColor(0.26, 0.22, 0.06, 0.95)
                row:SetBackdropBorderColor(0.92, 0.78, 0.22, 1)
                row.quantity:SetTextColor(0.98, 0.86, 0.35)
            elseif isSelected then
                row:SetBackdropColor(0.07, 0.14, 0.22, 0.95)
                row:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)
                row.quantity:SetTextColor(1, 1, 1)
            else
                row:SetBackdropColor(0.07, 0.07, 0.07, 0.9)
                row:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)
                row.quantity:SetTextColor(1, 1, 1)
            end
            if row.selected then
                row.selected:SetShown(isSelected)
            end
        end

        for index = #items + 1, #holdingPool do
            holdingPool[index]:Hide()
        end

        local rows = math.ceil(#items / columns)
        holdingsContent:SetHeight(math.max(1, rows * (HOLDING_CELL_HEIGHT + HOLDING_CELL_GAP)))
        if holdingsScroll.UpdateScrollChildRect then
            holdingsScroll:UpdateScrollChildRect()
        end

        local bankMissing = holdingsLocation == "bank" and record and not record.bankSeen
        if holdingsEmpty then
            holdingsEmpty:SetShown(#items == 0)
            if bankMissing then
                holdingsEmpty:SetText("Open your character bank once. Its contents stay saved after you leave.")
            elseif holdingsLocation == "bank" then
                holdingsEmpty:SetText("Nothing in the character bank.")
            else
                holdingsEmpty:SetText("Nothing in your bags.")
            end
        end
        if holdingsTitle then
            local label = holdingsLocation == "bank" and "Bank" or "Bags"
            holdingsTitle:SetText(string.format("%s (%d)", label, #items))
        end
        UpdateHoldingForm()
    end)

    refreshingHoldings = false
    if not ok then
        geterrorhandler()(err)
    end
end

local function SetTabVisual(button, selected)
    if not button then
        return
    end
    if selected then
        button:SetBackdropColor(0.18, 0.15, 0.08, 1)
        button:SetBackdropBorderColor(0.86, 0.72, 0.28, 1)
        button.label:SetTextColor(1, 0.86, 0.45)
    else
        button:SetBackdropColor(0.07, 0.07, 0.07, 1)
        button:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)
        button.label:SetTextColor(0.72, 0.72, 0.72)
    end
end

local function ShowTab(tab)
    activeTab = tab
    if purchasesPanel then
        purchasesPanel:SetShown(tab == "purchases")
    end
    if portfolioPanel then
        portfolioPanel:SetShown(tab == "portfolio")
    end
    if holdingsPanel then
        holdingsPanel:SetShown(tab == "holdings")
    end
    SetTabVisual(purchasesTab, tab == "purchases")
    SetTabVisual(portfolioTab, tab == "portfolio")
    SetTabVisual(holdingsTab, tab == "holdings")
    if tab == "portfolio" then
        RefreshPortfolio()
    elseif tab == "holdings" then
        ScanBags()
        ScanBank()
        RefreshHoldings()
    end
end

local function CreateColumnHeader(parent, text, column, note)
    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    PlaceRightColumn(label, parent, column)
    label:SetText(text)
    if note then
        local catcher = CreateFrame("Button", nil, parent)
        catcher:SetAllPoints(label)
        catcher:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(text)
            GameTooltip:AddLine(note, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        catcher:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
    end
    return label
end

local function CreateWindow()
    local frame = CreateFrame("Frame", "WorldOfWallStreetFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(1100, 520)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:SetClampedToScreen(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    if frame.SetTitle then
        frame:SetTitle("World of Wall Street")
    end
    if frame.TitleText then
        frame.TitleText:SetText("World of Wall Street")
    end

    tinsert(UISpecialFrames, "WorldOfWallStreetFrame")

    local function CreateTabButton(text, xOffset)
        local button = CreateFrame("Button", nil, frame, "BackdropTemplate")
        button:SetSize(120, 24)
        button:SetPoint("TOPLEFT", xOffset, -30)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("CENTER")
        label:SetText(text)
        button.label = label
        return button
    end

    portfolioTab = CreateTabButton("Portfolio", 16)
    purchasesTab = CreateTabButton("Purchases", 142)
    holdingsTab = CreateTabButton("Holdings", 268)
    purchasesTab:SetScript("OnClick", function()
        ShowTab("purchases")
    end)
    portfolioTab:SetScript("OnClick", function()
        ShowTab("portfolio")
    end)
    holdingsTab:SetScript("OnClick", function()
        ShowTab("holdings")
    end)

    local host = CreateFrame("Frame", nil, frame)
    host:SetPoint("TOPLEFT", 12, -60)
    host:SetPoint("BOTTOMRIGHT", -8, 12)

    purchasesPanel = CreateFrame("Frame", nil, host)
    purchasesPanel:SetAllPoints()
    portfolioPanel = CreateFrame("Frame", nil, host)
    portfolioPanel:SetAllPoints()
    holdingsPanel = CreateFrame("Frame", nil, host)
    holdingsPanel:SetAllPoints()

    local header = purchasesPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    header:SetPoint("TOPLEFT", 4, -2)
    header:SetText("Recent purchases")
    headerText = header

    local scroll = CreateFrame("ScrollFrame", nil, purchasesPanel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 0, -22)
    scroll:SetPoint("BOTTOMRIGHT", -22, 0)

    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(460, 1)
    scroll:SetScrollChild(content)

    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, content:GetHeight() - self:GetHeight())
        local nextScroll = self:GetVerticalScroll() - (delta * ROW_STRIDE * 2)
        nextScroll = math.max(0, math.min(maxScroll, nextScroll))
        self:SetVerticalScroll(nextScroll)
    end)

    local empty = purchasesPanel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    empty:SetPoint("CENTER", scroll, "CENTER", -8, 0)
    empty:SetText("Purchases show up here after you buy from the auction house.")
    emptyText = empty

    scrollFrame = scroll
    scrollContent = content
    scroll:SetScript("OnSizeChanged", RefreshPurchases)

    portfolioTitle = portfolioPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    portfolioTitle:SetPoint("TOPLEFT", 4, -2)
    portfolioTitle:SetText("Positions")

    portfolioHeader = CreateFrame("Frame", nil, portfolioPanel)
    portfolioHeader:SetPoint("TOPLEFT", 0, -20)
    portfolioHeader:SetPoint("TOPRIGHT", -22, -20)
    portfolioHeader:SetHeight(16)
    local itemHeader = portfolioHeader:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    itemHeader:SetPoint("LEFT", 54, 0)
    itemHeader:SetText("Item")
    CreateColumnHeader(portfolioHeader, "Qty", COLUMN_QTY)
    CreateColumnHeader(portfolioHeader, "Avg cost", COLUMN_AVG)
    CreateColumnHeader(portfolioHeader, "Market", COLUMN_MARKET, "Unit market price. Not connected yet.")
    CreateColumnHeader(portfolioHeader, "Cost basis", COLUMN_BASIS)
    CreateColumnHeader(portfolioHeader, "Mkt value", COLUMN_MKT_VALUE, "Quantity times the market price. Not connected yet.")
    CreateColumnHeader(portfolioHeader, "Unrealized", COLUMN_UNREALIZED, "Market value minus cost basis.")
    CreateColumnHeader(portfolioHeader, "%", COLUMN_PERCENT, "Unrealized gain or loss as a percent of cost basis.")

    local positionScroll = CreateFrame("ScrollFrame", nil, portfolioPanel, "UIPanelScrollFrameTemplate")
    positionScroll:SetPoint("TOPLEFT", 0, -38)
    positionScroll:SetPoint("BOTTOMRIGHT", -22, 0)
    local positionContent = CreateFrame("Frame", nil, positionScroll)
    positionContent:SetSize(820, 1)
    positionScroll:SetScrollChild(positionContent)
    positionScroll:EnableMouseWheel(true)
    positionScroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, positionContent:GetHeight() - self:GetHeight())
        local nextScroll = self:GetVerticalScroll() - (delta * (POSITION_HEIGHT + ROW_GAP) * 2)
        nextScroll = math.max(0, math.min(maxScroll, nextScroll))
        self:SetVerticalScroll(nextScroll)
    end)

    local portfolioEmptyText = portfolioPanel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    portfolioEmptyText:SetPoint("CENTER", positionScroll, "CENTER", -8, 0)
    portfolioEmptyText:SetText("Mark purchases as investments to add them here.")
    portfolioEmpty = portfolioEmptyText
    portfolioScroll = positionScroll
    portfolioContent = positionContent
    positionScroll:SetScript("OnSizeChanged", RefreshPortfolio)

    local bagsLocationButton
    local bankLocationButton

    local function StyleLocationButton(button, selected)
        if selected then
            button:SetBackdropColor(0.18, 0.15, 0.08, 1)
            button:SetBackdropBorderColor(0.86, 0.72, 0.28, 1)
        else
            button:SetBackdropColor(0.07, 0.07, 0.07, 1)
            button:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)
        end
    end

    local function ShowHoldingsLocation(location)
        holdingsLocation = location
        selectedHoldingID = nil
        formItemID = nil
        ClearUnitCost()
        StyleLocationButton(bagsLocationButton, location == "bags")
        StyleLocationButton(bankLocationButton, location == "bank")
        if holdingsNote then
            if location == "bank" then
                holdingsNote:SetText("Character bank. Open it once if this list is empty.")
            else
                holdingsNote:SetText("Backpack, equipped bags, and reagent bag.")
            end
        end
        RefreshHoldings()
    end

    holdingsTitle = holdingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    holdingsTitle:SetPoint("TOPLEFT", 4, -2)
    holdingsTitle:SetText("Bags")

    bagsLocationButton = CreateFrame("Button", nil, holdingsPanel, "BackdropTemplate")
    bagsLocationButton:SetSize(70, 22)
    bagsLocationButton:SetPoint("TOPLEFT", 160, 0)
    bagsLocationButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    local bagsLabel = bagsLocationButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bagsLabel:SetPoint("CENTER")
    bagsLabel:SetText("Bags")
    bagsLocationButton:SetScript("OnClick", function()
        ShowHoldingsLocation("bags")
    end)

    bankLocationButton = CreateFrame("Button", nil, holdingsPanel, "BackdropTemplate")
    bankLocationButton:SetSize(70, 22)
    bankLocationButton:SetPoint("LEFT", bagsLocationButton, "RIGHT", 6, 0)
    bankLocationButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    local bankLabel = bankLocationButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    bankLabel:SetPoint("CENTER")
    bankLabel:SetText("Bank")
    bankLocationButton:SetScript("OnClick", function()
        ShowHoldingsLocation("bank")
    end)
    StyleLocationButton(bagsLocationButton, true)
    StyleLocationButton(bankLocationButton, false)

    holdingsNote = holdingsPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    holdingsNote:SetPoint("TOPLEFT", 4, -26)
    holdingsNote:SetText("Backpack, equipped bags, and reagent bag.")

    local holdingScroll = CreateFrame("ScrollFrame", nil, holdingsPanel, "UIPanelScrollFrameTemplate")
    holdingScroll:SetPoint("TOPLEFT", 0, -46)
    holdingScroll:SetPoint("BOTTOMRIGHT", -22, 44)
    local holdingContent = CreateFrame("Frame", nil, holdingScroll)
    holdingContent:SetSize(820, 1)
    holdingScroll:SetScrollChild(holdingContent)
    holdingScroll:EnableMouseWheel(true)
    holdingScroll:SetScript("OnMouseWheel", function(self, delta)
        local maxScroll = math.max(0, holdingContent:GetHeight() - self:GetHeight())
        local nextScroll = self:GetVerticalScroll() - (delta * (HOLDING_CELL_HEIGHT + HOLDING_CELL_GAP))
        nextScroll = math.max(0, math.min(maxScroll, nextScroll))
        self:SetVerticalScroll(nextScroll)
    end)

    local holdingsEmptyText = holdingsPanel:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    holdingsEmptyText:SetPoint("CENTER", holdingScroll, "CENTER", -8, 0)
    holdingsEmptyText:SetText("Nothing in your bags.")
    holdingsEmpty = holdingsEmptyText
    holdingsScroll = holdingScroll
    holdingsContent = holdingContent
    holdingScroll:SetScript("OnSizeChanged", RefreshHoldings)

    local form = CreateFrame("Frame", nil, holdingsPanel)
    form:SetPoint("BOTTOMLEFT", 0, 0)
    form:SetPoint("BOTTOMRIGHT", -22, 0)
    form:SetHeight(40)

    local quantityLabel = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    quantityLabel:SetPoint("LEFT", 4, 0)
    quantityLabel:SetText("Quantity")

    holdingsQuantity = CreateFrame("EditBox", nil, form, "InputBoxTemplate")
    holdingsQuantity:SetSize(70, 20)
    holdingsQuantity:SetPoint("LEFT", quantityLabel, "RIGHT", 10, 0)
    holdingsQuantity:SetAutoFocus(false)
    holdingsQuantity:SetNumeric(true)
    holdingsQuantity:SetMaxLetters(8)
    holdingsQuantity:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)
    holdingsQuantity:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
    end)

    local costLabel = form:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    costLabel:SetPoint("LEFT", holdingsQuantity, "RIGHT", 16, 0)
    costLabel:SetText("avg. cost / unit")

    holdingsCost = CreateFrame("Frame", "WorldOfWallStreetUnitCost", form, "MoneyInputFrameTemplate")
    holdingsCost:SetPoint("LEFT", costLabel, "RIGHT", 8, 0)
    if MoneyInputFrame_SetPreviousFocus then
        MoneyInputFrame_SetPreviousFocus(holdingsCost, holdingsQuantity)
    end
    local copperBox = _G["WorldOfWallStreetUnitCostCopper"]
    if copperBox then
        copperBox:HookScript("OnEnterPressed", function(self)
            self:ClearFocus()
            AddSelectedHolding()
        end)
    end

    holdingsAddButton = CreateFrame("Button", nil, form, "UIPanelButtonTemplate")
    holdingsAddButton:SetSize(110, 22)
    holdingsAddButton:SetPoint("RIGHT", -4, 0)
    holdingsAddButton:SetText("Add lot")
    holdingsAddButton:SetScript("OnClick", AddSelectedHolding)
    holdingsAddButton:SetEnabled(false)

    frame.Refresh = function()
        RefreshPurchases()
        RefreshPortfolio()
        RefreshHoldings()
    end
    frame.RefreshPortfolio = RefreshPortfolio
    frame:SetScript("OnShow", function()
        frame:Refresh()
    end)

    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(980, 320, 1600, 1000)
    else
        frame:SetMinResize(980, 320)
        frame:SetMaxResize(1600, 1000)
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        local db = DB()
        db.windowWidth = frame:GetWidth()
        db.windowHeight = frame:GetHeight()
    end)
    grip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Drag to resize")
        GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    mainFrame = frame
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    ShowTab("portfolio")
end

local eventFrame = CreateFrame("Frame")

function eventFrame:ADDON_LOADED(name)
    if name ~= ADDON_NAME then
        return
    end
    local db = DB()
    PlaceMinimapButton(db.minimapAngle)
    if mainFrame and type(db.windowWidth) == "number" and type(db.windowHeight) == "number" then
        local width = math.max(980, math.min(1600, db.windowWidth))
        local height = math.max(320, math.min(1000, db.windowHeight))
        mainFrame:SetSize(width, height)
    end
end

function eventFrame:COMMODITY_SEARCH_RESULTS_UPDATED(itemID)
    itemID = PlainNumber(itemID)
    if itemID then
        lastCommodityItemID = itemID
    end
end

function eventFrame:COMMODITY_PRICE_UPDATED(unitPrice, totalPrice)
    local itemID, quantity = CommodityBuyContext()
    itemID = PlainNumber(itemID) or lastCommodityItemID
    pendingQuote = {
        unitPrice = PlainNumber(unitPrice),
        totalPrice = PlainNumber(totalPrice),
        itemID = itemID,
        quantity = PlainNumber(quantity),
        money = PlainNumber(GetMoney()),
    }
end

function eventFrame:COMMODITY_PURCHASE_FAILED()
    pendingQuote = nil
end

function eventFrame:COMMODITY_PURCHASE_SUCCEEDED()
    local quote = pendingQuote
    if not quote then
        return
    end

    local itemID = quote.itemID or lastCommodityItemID
    local totalCost = QuoteCost(quote)
    if CommitCommodityPurchase(itemID, quote.quantity, totalCost, quote.quantity == nil) then
        pendingQuote = nil
    end
end

function eventFrame:COMMODITY_PURCHASED(itemID, quantity)
    itemID = PlainNumber(itemID)
    quantity = PlainNumber(quantity)
    local quote = pendingQuote
    pendingQuote = nil

    if not itemID or WasJustRecorded(itemID) then
        return
    end

    local totalCost = QuoteCost(quote)
    local unverified = totalCost == nil
    if quote and quote.itemID and quote.itemID ~= itemID then
        totalCost = nil
        unverified = true
    end
    if quote and quote.quantity and quantity and quote.quantity ~= quantity then
        unverified = true
    end

    CommitCommodityPurchase(itemID, quantity, totalCost, unverified)
end

function eventFrame:ITEM_SEARCH_RESULTS_UPDATED(itemKey)
    CacheItemSearchResults(itemKey)
end

function eventFrame:AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID)
    local info = auctionCache[auctionID]
    auctionCache[auctionID] = nil
    if not info or not info.itemID or WasJustRecorded(info.itemID) then
        return
    end

    AddPurchase({
        itemID = info.itemID,
        itemLink = info.itemLink,
        quantity = info.quantity or 1,
        totalCost = info.buyout,
        kind = "item",
        unverified = type(info.buyout) ~= "number",
    })
end

function eventFrame:ITEM_PURCHASED(itemID)
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

function eventFrame:AUCTION_HOUSE_CLOSED()
    pendingQuote = nil
    auctionCache = {}
end

function eventFrame:PLAYER_ENTERING_WORLD()
    ScanBags()
    ScanBank()
    if activeTab == "holdings" and mainFrame and mainFrame:IsShown() then
        RefreshHoldings()
    end
end

function eventFrame:BAG_UPDATE_DELAYED()
    ScanBags()
    ScanBank()
    if activeTab == "holdings" and mainFrame and mainFrame:IsShown() then
        RefreshHoldings()
    end
end

function eventFrame:BANKFRAME_OPENED()
    characterBankOpen = true
    ScanBank()
    if activeTab == "holdings" and mainFrame and mainFrame:IsShown() then
        RefreshHoldings()
    end
end

function eventFrame:BANKFRAME_CLOSED()
    characterBankOpen = false
end

function eventFrame:PLAYERBANKSLOTS_CHANGED()
    ScanBank()
    if activeTab == "holdings" and mainFrame and mainFrame:IsShown() then
        RefreshHoldings()
    end
end

function eventFrame:ITEM_DATA_LOAD_RESULT(itemID, success)
    if not success then
        requestedItems[itemID] = nil
    end
    if mainFrame and mainFrame:IsShown() then
        mainFrame:Refresh()
    end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    local handler = self[event]
    if handler then
        handler(self, ...)
    end
end)

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("COMMODITY_SEARCH_RESULTS_UPDATED")
eventFrame:RegisterEvent("COMMODITY_PRICE_UPDATED")
eventFrame:RegisterEvent("COMMODITY_PURCHASE_FAILED")
eventFrame:RegisterEvent("COMMODITY_PURCHASE_SUCCEEDED")
eventFrame:RegisterEvent("COMMODITY_PURCHASED")
eventFrame:RegisterEvent("ITEM_SEARCH_RESULTS_UPDATED")
eventFrame:RegisterEvent("AUCTION_HOUSE_PURCHASE_COMPLETED")
eventFrame:RegisterEvent("ITEM_PURCHASED")
eventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
eventFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("BAG_UPDATE_DELAYED")
eventFrame:RegisterEvent("BANKFRAME_OPENED")
eventFrame:RegisterEvent("BANKFRAME_CLOSED")
eventFrame:RegisterEvent("PLAYERBANKSLOTS_CHANGED")

CreateWindow()
CreateMinimapButton()

SLASH_WORLDOFWALLSTREET1 = "/wows"
SLASH_WORLDOFWALLSTREET2 = "/wallstreet"
SlashCmdList.WORLDOFWALLSTREET = ToggleWindow
