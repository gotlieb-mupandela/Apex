//+------------------------------------------------------------------+
//| Config.mqh — Pip Masters APEX v2.0                               |
//| All configurable input parameters and instrument table           |
//+------------------------------------------------------------------+
#pragma once

//--- Strategy
input int    SWING_LOOKBACK          = 5;       // Candles each side for swing detection
input double FIB_T1_LEVEL            = 0.382;   // T1 entry Fibonacci level
input double FIB_T2_LEVEL            = 0.236;   // T2 entry Fibonacci level
input double FIB_TP_LEVEL            = 1.0;     // Take profit Fibonacci level
input double FIB_SL_EXTENSION        = -0.10;   // SL extension below 0%

//--- Indicators
input int    MA_FAST_PERIOD          = 50;      // Fast SMA period
input int    MA_SLOW_PERIOD          = 200;     // Slow SMA period
input int    RSI_PERIOD              = 14;      // RSI period
input double RSI_BULL_THRESHOLD      = 50.0;    // RSI level for bullish filter
input double RSI_BEAR_THRESHOLD      = 50.0;    // RSI level for bearish filter
input int    ATR_PERIOD              = 14;      // ATR period
input double ATR_MIN_THRESHOLD       = 0.0005;  // Min ATR (instrument-specific)
input double ATR_MAX_THRESHOLD       = 0.01;    // Max ATR (instrument-specific)

//--- Risk
input double RISK_PER_TRADE_PCT      = 0.5;     // % account risk per trade (T1 and T2)
input double MAX_DAILY_RISK_PCT      = 3.0;     // Max total daily risk %
input double MAX_DRAWDOWN_PCT        = 10.0;    // Max drawdown from equity peak %
input double MAX_SPREAD_PIPS         = 3.0;     // Max allowed spread in pips
input int    MAX_CONCURRENT_TRADES   = 2;       // Max open trades at once
input double MAX_SLIPPAGE_PIPS       = 3.0;     // Max fill slippage before closing

//--- Session filter
input bool   USE_SESSION_FILTER      = false;   // Enable trading hour restriction
input string SESSION_START_UTC       = "07:00"; // Session open (UTC)
input string SESSION_END_UTC         = "20:00"; // Session close (UTC)

//--- News pause
input bool   USE_NEWS_PAUSE          = false;   // Enable news pause window
input int    NEWS_PAUSE_MIN_BEFORE   = 30;      // Minutes before news to pause
input int    NEWS_PAUSE_MIN_AFTER    = 30;      // Minutes after news to resume

//--- Partial close (optional)
input bool   USE_PARTIAL_CLOSE       = false;   // Enable partial close feature
input int    PARTIAL_CLOSE_AT_R      = 2;       // Close partial at this R milestone
input double PARTIAL_CLOSE_PCT       = 50.0;    // % of position to close partially

//--- Logging
input string LOG_BASE_PATH           = "PipMastersApex"; // Log file base path

//+------------------------------------------------------------------+
//| Instrument configuration struct                                  |
//+------------------------------------------------------------------+
struct InstrumentConfig
{
   string symbol;
   double pipValue;    // Monetary value of 1 pip per standard lot
   double minLot;      // Broker minimum lot size
   double lotStep;     // Broker lot increment
   int    digits;      // Price decimal places
   double atrMin;      // ATR floor for this symbol
   double atrMax;      // ATR ceiling for this symbol
};

//--- Resolve instrument config dynamically from broker data
InstrumentConfig GetInstrumentConfig(const string sym)
{
   InstrumentConfig cfg;
   cfg.symbol   = sym;
   cfg.minLot   = SymbolInfoDouble(sym, SYMBOL_VOLUME_MIN);
   cfg.lotStep  = SymbolInfoDouble(sym, SYMBOL_VOLUME_STEP);
   cfg.digits   = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);

   // Pip value per standard lot in account currency
   double tickVal  = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(sym, SYMBOL_TRADE_TICK_SIZE);
   double point    = SymbolInfoDouble(sym, SYMBOL_POINT);

   // 1 pip = 10 points for 5-digit brokers, 1 point for 2-digit (JPY pairs)
   double pipPoints = (cfg.digits == 3 || cfg.digits == 5) ? 10.0 : 1.0;
   cfg.pipValue = (tickVal / tickSize) * point * pipPoints;

   cfg.atrMin = ATR_MIN_THRESHOLD;
   cfg.atrMax = ATR_MAX_THRESHOLD;
   return cfg;
}

//--- Robot state enum
enum RobotState
{
   STATE_SCANNING,       // Watching for BOS
   STATE_SETUP_FORMING,  // BOS confirmed, waiting for post-BOS extreme & retrace
   STATE_ORDERS_PLACED,  // Limit orders are live
   STATE_TRADE_ACTIVE,   // One or both trades are filled and being managed
   STATE_LOCKED,         // Drawdown limit hit — no new trades
   STATE_PAUSED          // Session/news filter active
};

//--- BOS direction
enum BOSDirection { BOS_NONE, BOS_BULLISH, BOS_BEARISH };

//--- Swing label
enum SwingLabel { SWING_NONE, SWING_HH, SWING_HL, SWING_LH, SWING_LL };

//--- Trend classification
enum TrendState { TREND_NEUTRAL, TREND_BULLISH, TREND_BEARISH };

//--- Filter result
enum FilterResult { FILTER_PASS, FILTER_FAIL };

//--- Setup invalidation reason (for logging)
enum InvalidationReason
{
   INV_NONE,
   INV_ZERO_LEVEL_BREACH,
   INV_OPPOSITE_BOS,
   INV_NEW_STRUCTURE
};
