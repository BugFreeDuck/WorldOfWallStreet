local _, NS = ...

NS.UI = {}

local DB = NS.Data.DB
local FindPurchase = NS.Data.FindPurchase
local AddPurchase = NS.Data.AddPurchase
local ScanBags = NS.Data.ScanBags
local ScanBank = NS.Data.ScanBank
local CharacterRecord = NS.Data.CharacterRecord
local FormatMoney = NS.Logic.FormatMoney
local ItemAppearance = NS.Logic.ItemAppearance
local FormatSignedMoney = NS.Logic.FormatSignedMoney
local FormatSignedPercent = NS.Logic.FormatSignedPercent
local BuildPositions = NS.Logic.BuildPositions
local PortfolioOverview = NS.Logic.PortfolioOverview
local PositionMarketUnit = NS.Logic.PositionMarketUnit
local MarketUnitPrice = NS.Logic.MarketUnitPrice
local OwnedQuantity = NS.Logic.OwnedQuantity
local PortfolioQuantity = NS.Logic.PortfolioQuantity
local RegistrableQuantity = NS.Logic.RegistrableQuantity
local EffectiveMarketSource = NS.Logic.EffectiveMarketSource
local EffectiveTSMPriceSource = NS.Logic.EffectiveTSMPriceSource
local TSMPriceLabel = NS.Logic.TSMPriceLabel
local TSM_PRICE_SOURCES = NS.Logic.TSM_PRICE_SOURCES
local MARKET_SOURCE_TSM = NS.Logic.MARKET_SOURCE_TSM
local MARKET_SOURCE_AUCTIONATOR = NS.Logic.MARKET_SOURCE_AUCTIONATOR
local AddonIsInstalled = NS.Logic.AddonIsInstalled
local TSMAvailable = NS.Logic.TSMAvailable
local AuctionatorAvailable = NS.Logic.AuctionatorAvailable
local MarketSparkline = NS.Logic.MarketSparkline


local ROW_HEIGHT = 44
local ROW_GAP = 4
local ROW_STRIDE = ROW_HEIGHT + ROW_GAP
local POSITION_HEIGHT = 36
local LOT_HEIGHT = 24
local OVERVIEW_HEIGHT = 176
local DONUT_SEGMENTS = 160
local DONUT_RADIUS = 44
local DONUT_THICKNESS = 20
local LEGEND_ROWS = 6
local LEGEND_ROW = 18
local DONUT_COLORS = {
    { 0.93, 0.75, 0.32 },
    { 0.36, 0.67, 0.95 },
    { 0.38, 0.80, 0.48 },
    { 0.92, 0.46, 0.40 },
    { 0.72, 0.52, 0.92 },
    { 0.36, 0.80, 0.78 },
    { 0.96, 0.62, 0.28 },
    { 0.86, 0.48, 0.68 },
    { 0.62, 0.74, 0.38 },
    { 0.95, 0.84, 0.48 },
    { 0.58, 0.58, 0.62 },
}

local mainFrame
local scrollFrame
local scrollContent
local emptyText
local rowPool = {}
local minimapButton

local refreshing = false
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
local portfolioOverview
local overviewValue
local overviewValueNote
local overviewGain
local overviewGainPercent
local overviewDonut
local positionPool = {}
local lotPool = {}
local expandedPositions = {}
local refreshingPortfolio = false
local activeTab = "portfolio"
local holdingsPanel
local holdingsTab
local settingsPanel
local settingsTab
local tsmSourceButton
local auctionatorSourceButton
local tsmSourceStatus
local auctionatorSourceStatus
local tsmPriceLabel
local tsmPriceButton
local tsmPriceMenu
local settingsWarning
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

local COLUMN_PERCENT = { offset = 8, width = 52 }
local COLUMN_UNREALIZED = { offset = 64, width = 112 }
local COLUMN_SPARK = { offset = 180, width = 72 }
local COLUMN_MKT_VALUE = { offset = 256, width = 112 }
local COLUMN_BASIS = { offset = 372, width = 112 }
local COLUMN_MARKET = { offset = 488, width = 100 }
local COLUMN_AVG = { offset = 592, width = 100 }
local COLUMN_QTY = { offset = 696, width = 44 }



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

local function DrawSparkline(spark, prices)
    spark.prices = prices
    local lines = spark.lines
    local count = prices and #prices or 0
    if count < 2 then
        for index = 1, #lines do
            lines[index]:Hide()
        end
        spark.empty:Show()
        return
    end
    spark.empty:Hide()
    local minPrice, maxPrice = prices[1], prices[1]
    for index = 2, count do
        if prices[index] < minPrice then
            minPrice = prices[index]
        end
        if prices[index] > maxPrice then
            maxPrice = prices[index]
        end
    end
    local span = maxPrice - minPrice
    local width = spark:GetWidth()
    local height = spark:GetHeight()
    if not width or width < 4 then
        width = COLUMN_SPARK.width - 16
    end
    if not height or height < 4 then
        height = 18
    end
    local function sparkY(price)
        if span <= 0 then
            return height / 2
        end
        return 1 + ((price - minPrice) / span) * (height - 2)
    end
    local rising = prices[count] >= prices[1]
    local red, green, blue = 0.95, 0.38, 0.32
    if rising then
        red, green, blue = 0.30, 0.86, 0.40
    end
    local segments = count - 1
    for index = 1, math.max(segments, #lines) do
        local line = lines[index]
        if not line then
            line = spark:CreateTexture(nil, "ARTWORK")
            line:SetTexture("Interface\\Buttons\\WHITE8X8")
            lines[index] = line
        end
        if index > segments then
            line:Hide()
        else
            local x1 = (index - 1) / segments * (width - 2) + 1
            local x2 = index / segments * (width - 2) + 1
            local y1 = sparkY(prices[index])
            local y2 = sparkY(prices[index + 1])
            local dx = x2 - x1
            local dy = y2 - y1
            local length = math.sqrt(dx * dx + dy * dy)
            if length < 1 then
                length = 1
            end
            line:ClearAllPoints()
            line:SetSize(length, 2)
            line:SetPoint("CENTER", spark, "BOTTOMLEFT", (x1 + x2) / 2, (y1 + y2) / 2)
            if line.SetRotation then
                line:SetRotation(math.atan2(dy, dx))
            end
            line:SetVertexColor(red, green, blue, 1)
            line:Show()
        end
    end
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

    local spark = CreateFrame("Frame", nil, row)
    spark:SetSize(COLUMN_SPARK.width - 16, 18)
    spark:SetPoint("CENTER", row, "RIGHT", -(COLUMN_SPARK.offset + COLUMN_SPARK.width / 2), 0)
    spark:EnableMouse(true)
    spark.lines = {}
    local sparkEmpty = spark:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sparkEmpty:SetAllPoints()
    sparkEmpty:SetJustifyH("CENTER")
    sparkEmpty:SetText("—")
    spark.empty = sparkEmpty
    spark:SetScript("OnEnter", function(self)
        local prices = self.prices
        if not prices or #prices < 2 then
            return
        end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(string.format("Market price, %d days", #prices))
        GameTooltip:AddLine("Oldest  " .. FormatMoney(prices[1]), 1, 1, 1)
        GameTooltip:AddLine("Latest  " .. FormatMoney(prices[#prices]), 1, 1, 1)
        GameTooltip:Show()
    end)
    spark:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    spark:SetScript("OnMouseUp", function(_, button)
        if button == "LeftButton" then
            row:Click()
        end
    end)
    row.spark = spark

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
    local priceColor = unitMarket and 1 or 0.5
    row.market:SetTextColor(priceColor, priceColor, priceColor)
    row.mktValue:SetTextColor(priceColor, priceColor, priceColor)

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
    if row.spark then
        DrawSparkline(row.spark, MarketSparkline(position.itemID, row.itemLink or position.itemLink))
    end

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
    local quantity = lot.quantity or 1
    local unitMarket = MarketUnitPrice(lot.itemID, lot.itemLink or row.itemLink)
    local marketValue = unitMarket and (unitMarket * quantity) or nil
    local basis = type(lot.totalCost) == "number" and lot.totalCost or nil
    row.market:SetText(unitMarket and FormatMoney(unitMarket) or "—")
    row.mktValue:SetText(marketValue and FormatMoney(marketValue) or "—")

    local unrealized = nil
    local percent = nil
    if basis and marketValue then
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
end

local function PaintOverviewDonut(slices)
    local segments = overviewDonut.segments
    local bounds = {}
    local cursor = 0
    for index, slice in ipairs(slices) do
        local startAt = cursor
        cursor = cursor + (slice.weight or 0)
        bounds[index] = { startAt = startAt, finish = cursor, color = slice.color }
    end
    if #bounds > 0 then
        bounds[#bounds].finish = 1
    end
    for segmentIndex = 1, #segments do
        local turn = (segmentIndex - 0.5) / #segments
        local red, green, blue = 0.22, 0.22, 0.24
        for index, bound in ipairs(bounds) do
            if turn >= bound.startAt and (turn < bound.finish or index == #bounds) then
                red, green, blue = bound.color[1], bound.color[2], bound.color[3]
                break
            end
        end
        segments[segmentIndex]:SetVertexColor(red, green, blue, 1)
    end
end

local function UpdatePortfolioOverview(positions)
    if not portfolioOverview or not overviewDonut then
        return
    end
    local summary = PortfolioOverview(positions)
    if summary.currentValue then
        overviewValue:SetText(FormatMoney(summary.currentValue))
        overviewValue:SetTextColor(1, 0.82, 0)
    else
        overviewValue:SetText("—")
        overviewValue:SetTextColor(0.65, 0.65, 0.65)
    end
    if summary.missingPrice > 0 then
        local noun = summary.missingPrice == 1 and "position has" or "positions have"
        overviewValueNote:SetText(string.format("%d %s no market price", summary.missingPrice, noun))
    else
        overviewValueNote:SetText("")
    end

    local gainText, gainRed, gainGreen, gainBlue = FormatSignedMoney(summary.unrealized)
    overviewGain:SetText(gainText)
    overviewGain:SetTextColor(gainRed, gainGreen, gainBlue)
    if summary.unrealized == nil then
        overviewGainPercent:SetText("")
    else
        local percentText, percentRed, percentGreen, percentBlue = FormatSignedPercent(summary.unrealizedPercent)
        overviewGainPercent:SetText(percentText)
        overviewGainPercent:SetTextColor(percentRed, percentGreen, percentBlue)
    end

    local slices = summary.slices
    for index, slice in ipairs(slices) do
        if slice.isOther then
            slice.color = DONUT_COLORS[11]
        else
            slice.color = DONUT_COLORS[index] or DONUT_COLORS[11]
        end
    end
    overviewDonut.slices = slices
    PaintOverviewDonut(slices)

    for index, entry in ipairs(overviewDonut.legend) do
        local slice = slices[index]
        if slice then
            entry.slice = slice
            entry.swatch:SetVertexColor(slice.color[1], slice.color[2], slice.color[3], 1)
            entry.name:SetText(slice.name)
            entry.weight:SetText(string.format("%.1f%%", (slice.weight or 0) * 100))
            entry:Show()
        else
            entry.slice = nil
            entry:Hide()
        end
    end
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

        UpdatePortfolioOverview(positions)
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

local function StyleChoiceButton(button, selected)
    if not button then
        return
    end
    if selected then
        button:SetBackdropColor(0.18, 0.15, 0.08, 1)
        button:SetBackdropBorderColor(0.86, 0.72, 0.28, 1)
        if button.label then
            button.label:SetTextColor(1, 0.86, 0.45)
        end
    else
        button:SetBackdropColor(0.07, 0.07, 0.07, 1)
        button:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)
        if button.label then
            button.label:SetTextColor(0.85, 0.85, 0.85)
        end
    end
end

local function SetSourceStatus(fontString, installed, available, detail)
    if not fontString then
        return
    end
    if available then
        fontString:SetText("Installed. " .. detail)
        fontString:SetTextColor(0.45, 0.95, 0.55)
    elseif installed then
        fontString:SetText("Installed, but its price API is not available.")
        fontString:SetTextColor(0.95, 0.78, 0.28)
    else
        fontString:SetText("Not installed.")
        fontString:SetTextColor(0.65, 0.65, 0.65)
    end
end

local function RefreshSettings()
    if not tsmSourceButton then
        return
    end
    local source = EffectiveMarketSource()
    StyleChoiceButton(tsmSourceButton, source == MARKET_SOURCE_TSM)
    StyleChoiceButton(auctionatorSourceButton, source == MARKET_SOURCE_AUCTIONATOR)
    SetSourceStatus(tsmSourceStatus, AddonIsInstalled("TradeSkillMaster"), TSMAvailable(), "Choose a TSM price below.")
    SetSourceStatus(auctionatorSourceStatus, AddonIsInstalled("Auctionator"), AuctionatorAvailable(), "Uses the last scanned auction price.")
    local tsmSelected = source == MARKET_SOURCE_TSM
    if tsmPriceLabel then
        tsmPriceLabel:SetShown(tsmSelected)
    end
    if tsmPriceButton then
        tsmPriceButton:SetShown(tsmSelected)
        if tsmPriceButton.label then
            tsmPriceButton.label:SetText(TSMPriceLabel(EffectiveTSMPriceSource()))
        end
    end
    if tsmPriceMenu and not tsmSelected then
        tsmPriceMenu:Hide()
    end
    if auctionatorSourceButton then
        auctionatorSourceButton:ClearAllPoints()
        auctionatorSourceButton:SetPoint("TOPLEFT", 4, tsmSelected and -146 or -106)
    end
    if settingsWarning then
        settingsWarning:ClearAllPoints()
        settingsWarning:SetPoint("TOPLEFT", 4, tsmSelected and -186 or -148)
        settingsWarning:SetPoint("RIGHT", settingsPanel, "RIGHT", -8, 0)
        local available = (source == MARKET_SOURCE_AUCTIONATOR and AuctionatorAvailable()) or (source == MARKET_SOURCE_TSM and TSMAvailable())
        if available then
            settingsWarning:SetText("")
        elseif source == MARKET_SOURCE_AUCTIONATOR then
            settingsWarning:SetText("Auctionator is not available, so market prices stay empty.")
        else
            settingsWarning:SetText("TSM is not available, so market prices stay empty.")
        end
    end
end

local function SetMarketSource(source)
    DB().marketSource = source
    RefreshSettings()
    RefreshPortfolio()
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
    if settingsPanel then
        settingsPanel:SetShown(tab == "settings")
    end
    SetTabVisual(purchasesTab, tab == "purchases")
    SetTabVisual(portfolioTab, tab == "portfolio")
    SetTabVisual(holdingsTab, tab == "holdings")
    SetTabVisual(settingsTab, tab == "settings")
    if tab == "portfolio" then
        RefreshPortfolio()
    elseif tab == "holdings" then
        ScanBags()
        ScanBank()
        RefreshHoldings()
    elseif tab == "settings" then
        RefreshSettings()
    end
end

local portfolioHeaderLabels = {}

local function PortfolioSortState()
    local key = DB().portfolioSortKey
    if key ~= "item" and key ~= "qty" and key ~= "avg" and key ~= "market"
        and key ~= "basis" and key ~= "mktValue" and key ~= "unrealized" and key ~= "percent" then
        key = "item"
    end
    local ascending = DB().portfolioSortAscending
    if type(ascending) ~= "boolean" then
        ascending = true
    end
    return key, ascending
end

local function UpdatePortfolioSortHeaders()
    local key, ascending = PortfolioSortState()
    local mark = ascending and " ^" or " v"
    for _, header in ipairs(portfolioHeaderLabels) do
        if header.sortKey == key then
            header.label:SetText(header.title .. mark)
            header.label:SetTextColor(1, 0.86, 0.45)
        else
            header.label:SetText(header.title)
            header.label:SetTextColor(0.65, 0.65, 0.65)
        end
    end
end

local function SetPortfolioSort(sortKey)
    local key, ascending = PortfolioSortState()
    local db = DB()
    if key == sortKey then
        db.portfolioSortAscending = not ascending
    else
        db.portfolioSortKey = sortKey
        db.portfolioSortAscending = sortKey == "item"
    end
    UpdatePortfolioSortHeaders()
    RefreshPortfolio()
end

local function CreateColumnHeader(parent, text, column, sortKey, note)
    local button = CreateFrame("Button", nil, parent)
    button:SetPoint("RIGHT", parent, "RIGHT", -column.offset, 0)
    button:SetSize(column.width, 16)
    button:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    button:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
    local label = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    label:SetAllPoints()
    label:SetJustifyH("RIGHT")
    label:SetJustifyV("MIDDLE")
    label:SetWordWrap(false)
    label:SetText(text)
    button:SetScript("OnClick", function()
        SetPortfolioSort(sortKey)
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(text)
        if note then
            GameTooltip:AddLine(note, 1, 1, 1, true)
        end
        GameTooltip:AddLine("Click to sort.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    portfolioHeaderLabels[#portfolioHeaderLabels + 1] = { label = label, title = text, sortKey = sortKey }
    return label
end

local function CreatePurchasesPanel()
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
end

local function CreatePortfolioPanel()
    portfolioOverview = CreateFrame("Frame", nil, portfolioPanel, "BackdropTemplate")
    portfolioOverview:SetPoint("TOPLEFT", 0, -2)
    portfolioOverview:SetPoint("TOPRIGHT", -22, -2)
    portfolioOverview:SetHeight(OVERVIEW_HEIGHT)
    portfolioOverview:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    portfolioOverview:SetBackdropColor(0.05, 0.05, 0.05, 0.72)
    portfolioOverview:SetBackdropBorderColor(0.22, 0.22, 0.22, 1)

    local valueLabel = portfolioOverview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    valueLabel:SetPoint("TOPLEFT", 14, -36)
    valueLabel:SetText("Current value")

    overviewValue = portfolioOverview:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    overviewValue:SetPoint("TOPLEFT", valueLabel, "BOTTOMLEFT", 0, -2)
    overviewValue:SetWidth(220)
    overviewValue:SetJustifyH("LEFT")
    overviewValue:SetWordWrap(false)
    overviewValue:SetText("—")

    overviewValueNote = portfolioOverview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    overviewValueNote:SetPoint("TOPLEFT", overviewValue, "BOTTOMLEFT", 0, -2)
    overviewValueNote:SetJustifyH("LEFT")
    overviewValueNote:SetTextColor(0.65, 0.65, 0.65)

    local gainLabel = portfolioOverview:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    gainLabel:SetPoint("TOPLEFT", 14, -104)
    gainLabel:SetText("Unrealized")

    overviewGain = portfolioOverview:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    overviewGain:SetPoint("TOPLEFT", gainLabel, "BOTTOMLEFT", 0, -2)
    overviewGain:SetJustifyH("LEFT")
    overviewGain:SetText("—")

    overviewGainPercent = portfolioOverview:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    overviewGainPercent:SetPoint("LEFT", overviewGain, "RIGHT", 10, 0)
    overviewGainPercent:SetJustifyH("LEFT")
    overviewGainPercent:SetText("")

    overviewDonut = CreateFrame("Frame", nil, portfolioOverview)
    local donutSize = (DONUT_RADIUS + DONUT_THICKNESS / 2) * 2 + 8
    overviewDonut:SetSize(donutSize, donutSize)
    overviewDonut:SetPoint("LEFT", portfolioOverview, "LEFT", 248, 0)
    overviewDonut:EnableMouse(true)
    overviewDonut.segments = {}
    local arc = (2 * math.pi * DONUT_RADIUS / DONUT_SEGMENTS) + 2
    for index = 1, DONUT_SEGMENTS do
        local segment = overviewDonut:CreateTexture(nil, "ARTWORK")
        segment:SetTexture("Interface\\AddOns\\WorldOfWallStreet\\DonutSegment")
        segment:SetBlendMode("BLEND")
        segment:SetSize(DONUT_THICKNESS, arc)
        if segment.SetSnapToPixelGrid then
            segment:SetSnapToPixelGrid(false)
        end
        if segment.SetTexelSnappingBias then
            segment:SetTexelSnappingBias(0)
        end
        local turn = (index - 0.5) / DONUT_SEGMENTS
        local angle = math.pi / 2 - turn * 2 * math.pi
        segment:SetPoint("CENTER", overviewDonut, "CENTER", math.cos(angle) * DONUT_RADIUS, math.sin(angle) * DONUT_RADIUS)
        segment:SetRotation(angle)
        segment:SetVertexColor(0.22, 0.22, 0.24, 1)
        overviewDonut.segments[index] = segment
    end
    overviewDonut.legend = {}
    local legendTop = math.floor((OVERVIEW_HEIGHT - LEGEND_ROWS * LEGEND_ROW) / 2)
    local legendLeft = 248 + donutSize + 18
    for index = 1, 11 do
        local column = index > LEGEND_ROWS and 1 or 0
        local row = (index - 1) % LEGEND_ROWS
        local entry = CreateFrame("Frame", nil, portfolioOverview)
        entry:SetSize(230, LEGEND_ROW)
        entry:SetPoint("TOPLEFT", portfolioOverview, "TOPLEFT", legendLeft + column * 240, -(legendTop + row * LEGEND_ROW))
        entry:EnableMouse(true)
        local swatch = entry:CreateTexture(nil, "ARTWORK")
        swatch:SetTexture("Interface\\Buttons\\WHITE8X8")
        swatch:SetSize(8, 8)
        swatch:SetPoint("LEFT", 0, 0)
        entry.swatch = swatch
        local name = entry:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        name:SetPoint("LEFT", 14, 0)
        name:SetJustifyH("LEFT")
        name:SetWordWrap(false)
        entry.name = name
        local weight = entry:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        weight:SetPoint("RIGHT", 0, 0)
        weight:SetJustifyH("RIGHT")
        entry.weight = weight
        name:SetPoint("RIGHT", weight, "LEFT", -6, 0)
        entry:SetScript("OnEnter", function(self)
            local slice = self.slice
            if not slice then
                return
            end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if slice.itemLink then
                GameTooltip:SetHyperlink(slice.itemLink)
            elseif slice.itemID then
                GameTooltip:SetItemByID(slice.itemID)
            else
                GameTooltip:SetText(slice.name or "Other")
            end
            GameTooltip:AddLine(FormatMoney(slice.value) .. "   " .. string.format("%.1f%%", (slice.weight or 0) * 100), 1, 1, 1)
            GameTooltip:Show()
        end)
        entry:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        entry:Hide()
        overviewDonut.legend[index] = entry
    end

    local function SliceAt(turn)
        local slices = overviewDonut.slices
        if not slices then
            return nil
        end
        local cursor = 0
        for index, slice in ipairs(slices) do
            cursor = cursor + (slice.weight or 0)
            if turn < cursor or index == #slices then
                return slice
            end
        end
        return nil
    end

    local function ShowDonutTooltip()
        local slices = overviewDonut.slices
        if not slices or #slices == 0 then
            return
        end
        local cx, cy = overviewDonut:GetCenter()
        if not cx or not cy then
            return
        end
        local scale = overviewDonut:GetEffectiveScale() or 1
        local x, y = GetCursorPosition()
        local angle = math.atan2((y / scale) - cy, (x / scale) - cx)
        local turn = (math.pi / 2 - angle) / (2 * math.pi)
        turn = turn % 1
        local slice = SliceAt(turn)
        if not slice then
            return
        end
        GameTooltip:SetOwner(overviewDonut, "ANCHOR_RIGHT")
        if slice.itemLink then
            GameTooltip:SetHyperlink(slice.itemLink)
        elseif slice.itemID then
            GameTooltip:SetItemByID(slice.itemID)
        else
            GameTooltip:SetText(slice.name or "Other")
        end
        local red, green, blue = 1, 1, 1
        if slice.color then
            red, green, blue = slice.color[1], slice.color[2], slice.color[3]
        end
        GameTooltip:AddLine(string.format("%.1f%%", (slice.weight or 0) * 100), red, green, blue)
        GameTooltip:AddLine(FormatMoney(slice.value), 1, 1, 1)
        GameTooltip:Show()
    end

    overviewDonut:SetScript("OnEnter", function(self)
        self:SetScript("OnUpdate", ShowDonutTooltip)
        ShowDonutTooltip()
    end)
    overviewDonut:SetScript("OnLeave", function(self)
        self:SetScript("OnUpdate", nil)
        GameTooltip:Hide()
    end)

    portfolioTitle = portfolioPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    portfolioTitle:SetPoint("TOPLEFT", 4, -(OVERVIEW_HEIGHT + 10))
    portfolioTitle:SetText("Positions")

    portfolioHeader = CreateFrame("Frame", nil, portfolioPanel)
    portfolioHeader:SetPoint("TOPLEFT", 0, -(OVERVIEW_HEIGHT + 28))
    portfolioHeader:SetPoint("TOPRIGHT", -22, -(OVERVIEW_HEIGHT + 28))
    portfolioHeader:SetHeight(16)
    local itemButton = CreateFrame("Button", nil, portfolioHeader)
    itemButton:SetPoint("LEFT", 54, 0)
    itemButton:SetPoint("RIGHT", portfolioHeader, "RIGHT", -(COLUMN_QTY.offset + COLUMN_QTY.width + 8), 0)
    itemButton:SetHeight(16)
    itemButton:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    itemButton:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
    local itemHeader = itemButton:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    itemHeader:SetPoint("LEFT")
    itemHeader:SetPoint("RIGHT")
    itemHeader:SetJustifyH("LEFT")
    itemHeader:SetWordWrap(false)
    itemHeader:SetText("Item")
    itemButton:SetScript("OnClick", function()
        SetPortfolioSort("item")
    end)
    itemButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Item")
        GameTooltip:AddLine("Click to sort.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    itemButton:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    portfolioHeaderLabels[#portfolioHeaderLabels + 1] = { label = itemHeader, title = "Item", sortKey = "item" }
    CreateColumnHeader(portfolioHeader, "Qty", COLUMN_QTY, "qty")
    CreateColumnHeader(portfolioHeader, "Avg cost", COLUMN_AVG, "avg")
    CreateColumnHeader(portfolioHeader, "Market", COLUMN_MARKET, "market", "Unit price from the addon selected in Settings.")
    CreateColumnHeader(portfolioHeader, "Cost basis", COLUMN_BASIS, "basis")
    CreateColumnHeader(portfolioHeader, "Mkt value", COLUMN_MKT_VALUE, "mktValue", "Quantity times the market price from Settings.")
    local sparkHeader = portfolioHeader:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    PlaceRightColumn(sparkHeader, portfolioHeader, COLUMN_SPARK)
    sparkHeader:SetJustifyH("CENTER")
    sparkHeader:SetText("30d")
    sparkHeader:SetTextColor(0.65, 0.65, 0.65)
    CreateColumnHeader(portfolioHeader, "Unrealized", COLUMN_UNREALIZED, "unrealized", "Market value minus cost basis.")
    CreateColumnHeader(portfolioHeader, "%", COLUMN_PERCENT, "percent", "Unrealized gain or loss as a percent of cost basis.")
    UpdatePortfolioSortHeaders()

    local positionScroll = CreateFrame("ScrollFrame", nil, portfolioPanel, "UIPanelScrollFrameTemplate")
    positionScroll:SetPoint("TOPLEFT", 0, -(OVERVIEW_HEIGHT + 46))
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
end

local function CreateHoldingsPanel()
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
end

local function CreateSettingsPanel()
    local settingsTitle = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    settingsTitle:SetPoint("TOPLEFT", 4, -2)
    settingsTitle:SetText("Market price")

    local settingsNote = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    settingsNote:SetPoint("TOPLEFT", 4, -24)
    settingsNote:SetPoint("RIGHT", settingsPanel, "RIGHT", -8, 0)
    settingsNote:SetJustifyH("LEFT")
    settingsNote:SetWordWrap(true)
    settingsNote:SetText("Choose which addon supplies the portfolio market price. Until you choose, TSM is used when it is installed, and Auctionator is used otherwise.")

    local function CreateSourceButton(text, y)
        local button = CreateFrame("Button", nil, settingsPanel, "BackdropTemplate")
        button:SetSize(160, 26)
        button:SetPoint("TOPLEFT", 4, y)
        button:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        local label = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        label:SetPoint("CENTER")
        label:SetText(text)
        button.label = label
        local status = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        status:SetPoint("LEFT", button, "RIGHT", 12, 0)
        status:SetJustifyH("LEFT")
        return button, status
    end

    tsmSourceButton, tsmSourceStatus = CreateSourceButton("TSM", -72)
    auctionatorSourceButton, auctionatorSourceStatus = CreateSourceButton("Auctionator", -106)
    tsmSourceButton:SetScript("OnClick", function()
        SetMarketSource(MARKET_SOURCE_TSM)
    end)
    auctionatorSourceButton:SetScript("OnClick", function()
        SetMarketSource(MARKET_SOURCE_AUCTIONATOR)
    end)

    tsmPriceLabel = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tsmPriceLabel:SetPoint("TOPLEFT", 4, -110)
    tsmPriceLabel:SetText("TSM price")

    tsmPriceButton = CreateFrame("Button", nil, settingsPanel, "BackdropTemplate")
    tsmPriceButton:SetSize(220, 26)
    tsmPriceButton:SetPoint("LEFT", tsmPriceLabel, "RIGHT", 12, 0)
    tsmPriceButton:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    tsmPriceButton:SetBackdropColor(0.07, 0.07, 0.07, 1)
    tsmPriceButton:SetBackdropBorderColor(0.28, 0.28, 0.28, 1)
    local tsmPriceButtonLabel = tsmPriceButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tsmPriceButtonLabel:SetPoint("LEFT", 8, 0)
    tsmPriceButtonLabel:SetPoint("RIGHT", -18, 0)
    tsmPriceButtonLabel:SetJustifyH("LEFT")
    tsmPriceButtonLabel:SetText("Min Buyout")
    tsmPriceButton.label = tsmPriceButtonLabel
    local tsmPriceArrow = tsmPriceButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    tsmPriceArrow:SetPoint("RIGHT", -8, 0)
    tsmPriceArrow:SetText("v")

    tsmPriceMenu = CreateFrame("Frame", nil, settingsPanel, "BackdropTemplate")
    tsmPriceMenu:SetPoint("TOPLEFT", tsmPriceButton, "BOTTOMLEFT", 0, -2)
    tsmPriceMenu:SetSize(220, #TSM_PRICE_SOURCES * 22 + 8)
    tsmPriceMenu:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    tsmPriceMenu:SetBackdropColor(0.05, 0.05, 0.05, 0.98)
    tsmPriceMenu:SetBackdropBorderColor(0.86, 0.72, 0.28, 1)
    tsmPriceMenu:SetFrameLevel(settingsPanel:GetFrameLevel() + 20)
    tsmPriceMenu:Hide()

    for index, option in ipairs(TSM_PRICE_SOURCES) do
        local optionButton = CreateFrame("Button", nil, tsmPriceMenu)
        optionButton:SetSize(210, 20)
        optionButton:SetPoint("TOPLEFT", 5, -4 - (index - 1) * 22)
        optionButton:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
        optionButton:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.08)
        local optionLabel = optionButton:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        optionLabel:SetPoint("LEFT", 6, 0)
        optionLabel:SetPoint("RIGHT", -6, 0)
        optionLabel:SetJustifyH("LEFT")
        optionLabel:SetText(option.label)
        optionButton.label = optionLabel
        optionButton.priceKey = option.key
        optionButton:SetScript("OnClick", function(self)
            DB().tsmPriceSource = self.priceKey
            tsmPriceMenu:Hide()
            RefreshSettings()
            RefreshPortfolio()
        end)
        tsmPriceMenu[index] = optionButton
    end

    local function StyleTSMPriceOptions()
        local selected = EffectiveTSMPriceSource()
        for index = 1, #TSM_PRICE_SOURCES do
            local optionButton = tsmPriceMenu[index]
            if optionButton.priceKey == selected then
                optionButton.label:SetTextColor(1, 0.86, 0.45)
            else
                optionButton.label:SetTextColor(0.9, 0.9, 0.9)
            end
        end
    end
    tsmPriceMenu:SetScript("OnShow", StyleTSMPriceOptions)
    tsmPriceButton:SetScript("OnClick", function()
        tsmPriceMenu:SetShown(not tsmPriceMenu:IsShown())
    end)

    settingsWarning = settingsPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    settingsWarning:SetPoint("TOPLEFT", 4, -148)
    settingsWarning:SetPoint("RIGHT", settingsPanel, "RIGHT", -8, 0)
    settingsWarning:SetJustifyH("LEFT")
    settingsWarning:SetWordWrap(true)
    settingsWarning:SetTextColor(0.95, 0.78, 0.28)
    RefreshSettings()
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
    settingsTab = CreateTabButton("Settings", 394)
    purchasesTab:SetScript("OnClick", function()
        ShowTab("purchases")
    end)
    portfolioTab:SetScript("OnClick", function()
        ShowTab("portfolio")
    end)
    holdingsTab:SetScript("OnClick", function()
        ShowTab("holdings")
    end)
    settingsTab:SetScript("OnClick", function()
        ShowTab("settings")
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
    settingsPanel = CreateFrame("Frame", nil, host)
    settingsPanel:SetAllPoints()

    CreatePurchasesPanel()
    CreatePortfolioPanel()
    CreateHoldingsPanel()
    CreateSettingsPanel()

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


NS.UI.Refresh = function()
    if mainFrame and mainFrame:IsShown() and mainFrame.Refresh then
        mainFrame:Refresh()
    end
end

NS.UI.RefreshPortfolio = function()
    if mainFrame and mainFrame.RefreshPortfolio and mainFrame:IsShown() then
        mainFrame.RefreshPortfolio()
    end
end

NS.UI.RefreshHoldings = function()
    RefreshHoldings()
end

NS.UI.HoldingsVisible = function()
    return activeTab == "holdings" and mainFrame and mainFrame:IsShown()
end

NS.UI.OnAddonLoaded = function(name, addonName)
    if name == addonName then
        local db = DB()
        PlaceMinimapButton(db.minimapAngle)
        if mainFrame and type(db.windowWidth) == "number" and type(db.windowHeight) == "number" then
            local width = math.max(980, math.min(1600, db.windowWidth))
            local height = math.max(320, math.min(1000, db.windowHeight))
            mainFrame:SetSize(width, height)
        end
    end
    NS.Logic.WatchAuctionator()
    if name == addonName or name == "TradeSkillMaster" or name == "Auctionator" then
        RefreshSettings()
        if mainFrame and mainFrame:IsShown() and activeTab == "portfolio" then
            RefreshPortfolio()
        end
    end
end
CreateWindow()
CreateMinimapButton()

SLASH_WORLDOFWALLSTREET1 = "/wows"
SLASH_WORLDOFWALLSTREET2 = "/wallstreet"
SlashCmdList.WORLDOFWALLSTREET = ToggleWindow
