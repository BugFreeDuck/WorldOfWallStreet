local ADDON_NAME, NS = ...
local Data = NS.Data
local Logic = NS.Logic
local UI = NS.UI

local eventFrame = CreateFrame("Frame")

function eventFrame:ADDON_LOADED(name)
    UI.OnAddonLoaded(name, ADDON_NAME)
end

function eventFrame:COMMODITY_SEARCH_RESULTS_UPDATED(itemID)
    Data.OnCommoditySearchResultsUpdated(itemID)
end

function eventFrame:COMMODITY_PRICE_UPDATED(unitPrice, totalPrice)
    Data.OnCommodityPriceUpdated(unitPrice, totalPrice)
end

function eventFrame:COMMODITY_PURCHASE_FAILED()
    Data.OnCommodityPurchaseFailed()
end

function eventFrame:COMMODITY_PURCHASE_SUCCEEDED()
    Data.OnCommodityPurchaseSucceeded()
end

function eventFrame:COMMODITY_PURCHASED(itemID, quantity)
    Data.OnCommodityPurchased(itemID, quantity)
end

function eventFrame:ITEM_SEARCH_RESULTS_UPDATED(itemKey)
    Data.OnItemSearchResultsUpdated(itemKey)
end

function eventFrame:AUCTION_HOUSE_PURCHASE_COMPLETED(auctionID)
    Data.OnAuctionHousePurchaseCompleted(auctionID)
end

function eventFrame:ITEM_PURCHASED(itemID)
    Data.OnItemPurchased(itemID)
end

function eventFrame:AUCTION_HOUSE_CLOSED()
    Data.OnAuctionHouseClosed()
end

function eventFrame:PLAYER_ENTERING_WORLD()
    Data.OnEnteringWorld()
end

function eventFrame:BAG_UPDATE_DELAYED()
    Data.OnBagsChanged()
end

function eventFrame:BANKFRAME_OPENED()
    Data.OnBankOpened()
end

function eventFrame:BANKFRAME_CLOSED()
    Data.OnBankClosed()
end

function eventFrame:PLAYERBANKSLOTS_CHANGED()
    Data.OnBankSlotsChanged()
end

function eventFrame:ITEM_DATA_LOAD_RESULT(itemID, success)
    Logic.ClearItemRequest(itemID, success)
    UI.Refresh()
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
