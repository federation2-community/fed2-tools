-- Analyze commodity price data and calculate profitability
-- Provides functions for determining best trading opportunities

-- Analyze a single commodity's price data
-- Returns: {commodity, avg_buy, avg_sell, profit, margin, top_buy, top_sell}
function f2t_price_analyze_commodity(commodity, parsed_data)
    local top = f2t_price_get_top_exchanges(parsed_data)

    -- Calculate averages from top exchanges
    local avg_buy_price = f2t_price_calculate_average(top.buy)
    local avg_sell_price = f2t_price_calculate_average(top.sell)

    -- Calculate profit per ton
    local profit = avg_buy_price - avg_sell_price

    -- Calculate profit margin percentage: (profit / cost) * 100
    local margin = 0
    if avg_sell_price > 0 then
        margin = (profit / avg_sell_price) * 100
    end

    return {
        commodity = commodity,
        avg_buy_price = avg_buy_price,    -- Average price where exchanges BUY (we sell)
        avg_sell_price = avg_sell_price,  -- Average price where exchanges SELL (we buy)
        profit = profit,                   -- Profit per ton
        margin = margin,                   -- Profit margin percentage
        top_buy = top.buy,                 -- Top exchanges buying (where we sell)
        top_sell = top.sell                -- Top exchanges selling (where we buy)
    }
end

f2t_debug_log("[commodities] Price analyzer loaded")