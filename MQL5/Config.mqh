//+------------------------------------------------------------------+
//|                                                       Config.mqh |
//|                          PipMasters APEX v2.0 | Config Module    |
//|                                                                  |
//| PURPOSE: Central configuration block. Every tunable parameter    |
//|          referenced anywhere in the robot lives here. No magic   |
//|          numbers in other modules.                               |
//|                                                                  |
//| SPEC REFERENCES: Part C (full), Part B (risk), Part A (levels),  |
//|                  Part F (architecture).                          |
//+------------------------------------------------------------------+
#ifndef __APEX_CONFIG_MQH__
#define __APEX_CONFIG_MQH__

#property strict

//+------------------------------------------------------------------+
//| GLOBAL ENUMERATIONS (used across modules)                        |
//+------------------------------------------------------------------+

// Swing point classifications (Spec A3)
enum ENUM_SWING_TYPE
  {
   SWING_NONE = 0,   // Uninitialised / invalid
   SWING_HH   = 1,   // Higher High
   SWING_LH   = 2,   // Lower  High
   SWING_HL   = 3,   // Higher Low
   SWING_LL   = 4    // Lower  Low
  };

// Market structure state (Spec A4)
enum ENUM_STRUCTURE_STATE
  {
   STRUCT_NEUTRAL = 0,
   STRUCT_BULLISH = 1,
   STRUCT_BEARISH = 2
  };

// Break of Structure direction (Spec A5)
enum ENUM_BOS_DIRECTION
  {
   BOS_NONE    = 0,
   BOS_BULLISH = 1,
   BOS_BEARISH = 2
  };

// Setup lifecycle state (Spec A15 + D1)
enum ENUM_SETUP_STATE
  {
   SETUP_IDLE          = 0, // No active setup
   SETUP_BOS_CONFIRMED = 1, // BOS closed; waiting for post-BOS extreme
   SETUP_POST_EXTREME  = 2, // Post-BOS extreme identified; Fib drawn; waiting retrace
   SETUP_ORDERS_LIVE   = 3, // T1/T2 limit orders placed
   SETUP_TRIGGERED     = 4, // At least one trade filled
   SETUP_INVALIDATED   = 5  // Cancelled per A14 rules
  };

// Trailing R-milestones (Spec A13)
enum ENUM_TRAIL_STAGE
  {
   TRAIL_INITIAL = 0,  // SL at -10% Fib (entry)
   TRAIL_BE      = 1,  // SL moved to break even (1R hit)
   TRAIL_PLUS_1R = 2,  // SL moved to +1R (2R hit)
   TRAIL_PLUS_2R = 3,  // SL moved to +2R (3R hit)
   TRAIL_CLOSED  = 4   // 4R hit; position closed
  };

// Robot run-mode (drawdown protection — Spec B4)
enum ENUM_ROBOT_STATE
  {
   ROBOT_ACTIVE = 0,
   ROBOT_LOCKED = 1   // Max drawdown breached
  };

// Log event types (Spec E1)
enum ENUM_LOG_EVENT
  {
   LOG_INFO,
   LOG_WARN,
   LOG_ERROR,
   LOG_SWING_DETECTED,
   LOG_STRUCTURE_CHANGE,
   LOG_BOS_DETECTED,
   LOG_POST_BOS_EXTREME,
   LOG_FIB_APPLIED,
   LOG_ORDER_PLACED,
   LOG_ORDER_TRIGGERED,
   LOG_ORDER_CANCELLED,
   LOG_TRAIL_UPDATED,
   LOG_TRADE_CLOSED,
   LOG_SETUP_INVALIDATED,
   LOG_RISK_BLOCK,
   LOG_DAILY_SUMMARY
  };

//+------------------------------------------------------------------+
//| INPUT PARAMETERS — STRATEGY (Spec C1)                            |
//+------------------------------------------------------------------+
input group "=== Strategy Parameters ==="
input int    InpSwingLookback       = 5;       // Candles each side for swing confirmation (Spec A3)
input double InpFibZeroLevel        = 0.000;   // 0%   anchor (HL/LH before BOS)
input double InpFibT1Level          = 0.382;   // T1 entry — top of zone
input double InpFibT2Level          = 0.236;   // T2 entry — bottom of zone
input double InpFibTPLevel          = 1.000;   // Take profit level
input double InpFibSLExtension      = -0.100;  // Stop loss extension (-10%)

//+------------------------------------------------------------------+
//| INPUT PARAMETERS — INDICATORS (Spec C2, A9)                      |
//+------------------------------------------------------------------+
input group "=== Indicator Parameters ==="
input int    InpMAFastPeriod        = 50;      // MA50
input int    InpMASlowPeriod        = 200;     // MA200
input ENUM_MA_METHOD InpMAMethod    = MODE_SMA;// MA method (SMA default)
input ENUM_APPLIED_PRICE InpMAPrice = PRICE_CLOSE;
input int    InpRSIPeriod           = 14;
input double InpRSIBullThreshold    = 50.0;    // RSI above = bullish bias
input double InpRSIBearThreshold    = 50.0;    // RSI below = bearish bias
input int    InpATRPeriod           = 14;
input double InpATRMinThreshold     = 0.0;     // 0 = disabled; set per instrument
input double InpATRMaxThreshold     = 0.0;     // 0 = disabled; set per instrument

//+------------------------------------------------------------------+
//| INPUT PARAMETERS — RISK (Spec C3, B)                             |
//+------------------------------------------------------------------+
input group "=== Risk Parameters ==="
input double InpRiskPerTradePct     = 0.5;     // Spec B1
input double InpMaxDailyRiskPct     = 3.0;     // Spec B3
input double InpMaxDrawdownPct      = 10.0;    // Spec B4
input double InpMaxSpreadPips       = 3.0;     // Spec B6
input int    InpMaxConcurrentTrades = 2;       // Spec B5

//+------------------------------------------------------------------+
//| INPUT PARAMETERS — SESSION FILTER (Spec C4)                      |
//+------------------------------------------------------------------+
input group "=== Session Filter (Optional) ==="
input bool   InpUseSessionFilter    = false;
input int    InpSessionStartHourUTC = 7;
input int    InpSessionStartMinUTC  = 0;
input int    InpSessionEndHourUTC   = 20;
input int    InpSessionEndMinUTC    = 0;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS — NEWS PAUSE (Spec C5)                          |
//+------------------------------------------------------------------+
input group "=== News Pause (Optional) ==="
input bool   InpUseNewsPause        = false;
input int    InpNewsPauseMinsBefore = 30;
input int    InpNewsPauseMinsAfter  = 30;

//+------------------------------------------------------------------+
//| INPUT PARAMETERS — EXECUTION / MISC                              |
//+------------------------------------------------------------------+
input group "=== Execution & Misc ==="
input long   InpMagicNumber         = 20260419;   // Magic / EA id
input string InpTradeComment        = "APEX_v2";
input int    InpSlippagePoints      = 20;
input bool   InpAllowPartialClose   = false;      // Spec D3 (default OFF)
input bool   InpEnableDashboard     = true;       // Spec E3
input bool   InpEnableFileLog       = true;       // Spec E1
input int    InpMaxSwingsStored     = 200;        // Circular buffer of swing points
input int    InpMaxHistoryBars      = 1000;       // Bars to consider on init

//+------------------------------------------------------------------+
//| DERIVED / GLOBAL CONSTANTS                                       |
//+------------------------------------------------------------------+
#define APEX_TIMEFRAME        PERIOD_M15         // Spec A2
#define APEX_MAX_TRADES       2                   // Hard cap per BOS (Spec A16)

//+------------------------------------------------------------------+
//| RUNTIME GLOBAL CONFIG STRUCT                                     |
//| (Snapshot of inputs taken at OnInit — other modules read this.)  |
//+------------------------------------------------------------------+
struct SApexConfig
  {
   // Strategy
   int               swingLookback;
   double            fibZero;
   double            fibT1;
   double            fibT2;
   double            fibTP;
   double            fibSLExt;
   // Indicators
   int               maFast;
   int               maSlow;
   ENUM_MA_METHOD    maMethod;
   ENUM_APPLIED_PRICE maPrice;
   int               rsiPeriod;
   double            rsiBull;
   double            rsiBear;
   int               atrPeriod;
   double            atrMin;
   double            atrMax;
   // Risk
   double            riskPerTradePct;
   double            maxDailyRiskPct;
   double            maxDrawdownPct;
   double            maxSpreadPips;
   int               maxConcurrent;
   // Sessions
   bool              useSessionFilter;
   int               sessionStartH;
   int               sessionStartM;
   int               sessionEndH;
   int               sessionEndM;
   // News
   bool              useNewsPause;
   int               newsBefore;
   int               newsAfter;
   // Execution
   long              magic;
   string            tradeComment;
   int               slippage;
   bool              allowPartialClose;
   bool              enableDashboard;
   bool              enableFileLog;
   int               maxSwingsStored;
   int               maxHistoryBars;
   // Context
   string            symbol;
   ENUM_TIMEFRAMES   timeframe;
   int               digits;
   double            point;
   double            pipSize;   // point * 10 for 5-digit FX; else point
  };

// Single global config instance — populated by ApexConfig_Load().
SApexConfig g_cfg;

//+------------------------------------------------------------------+
//| ApexConfig_Load                                                  |
//| Called once from OnInit() to snapshot inputs into g_cfg.         |
//+------------------------------------------------------------------+
bool ApexConfig_Load()
  {
   g_cfg.swingLookback     = InpSwingLookback;
   g_cfg.fibZero           = InpFibZeroLevel;
   g_cfg.fibT1             = InpFibT1Level;
   g_cfg.fibT2             = InpFibT2Level;
   g_cfg.fibTP             = InpFibTPLevel;
   g_cfg.fibSLExt          = InpFibSLExtension;

   g_cfg.maFast            = InpMAFastPeriod;
   g_cfg.maSlow            = InpMASlowPeriod;
   g_cfg.maMethod          = InpMAMethod;
   g_cfg.maPrice           = InpMAPrice;
   g_cfg.rsiPeriod         = InpRSIPeriod;
   g_cfg.rsiBull           = InpRSIBullThreshold;
   g_cfg.rsiBear           = InpRSIBearThreshold;
   g_cfg.atrPeriod         = InpATRPeriod;
   g_cfg.atrMin            = InpATRMinThreshold;
   g_cfg.atrMax            = InpATRMaxThreshold;

   g_cfg.riskPerTradePct   = InpRiskPerTradePct;
   g_cfg.maxDailyRiskPct   = InpMaxDailyRiskPct;
   g_cfg.maxDrawdownPct    = InpMaxDrawdownPct;
   g_cfg.maxSpreadPips     = InpMaxSpreadPips;
   g_cfg.maxConcurrent     = InpMaxConcurrentTrades;

   g_cfg.useSessionFilter  = InpUseSessionFilter;
   g_cfg.sessionStartH     = InpSessionStartHourUTC;
   g_cfg.sessionStartM     = InpSessionStartMinUTC;
   g_cfg.sessionEndH       = InpSessionEndHourUTC;
   g_cfg.sessionEndM       = InpSessionEndMinUTC;

   g_cfg.useNewsPause      = InpUseNewsPause;
   g_cfg.newsBefore        = InpNewsPauseMinsBefore;
   g_cfg.newsAfter         = InpNewsPauseMinsAfter;

   g_cfg.magic             = InpMagicNumber;
   g_cfg.tradeComment      = InpTradeComment;
   g_cfg.slippage          = InpSlippagePoints;
   g_cfg.allowPartialClose = InpAllowPartialClose;
   g_cfg.enableDashboard   = InpEnableDashboard;
   g_cfg.enableFileLog     = InpEnableFileLog;
   g_cfg.maxSwingsStored   = InpMaxSwingsStored;
   g_cfg.maxHistoryBars    = InpMaxHistoryBars;

   g_cfg.symbol            = _Symbol;
   g_cfg.timeframe         = APEX_TIMEFRAME;
   g_cfg.digits            = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_cfg.point             = SymbolInfoDouble(_Symbol, SYMBOL_POINT);

   // Standard FX pip = 10 * point on 3/5-digit quotes; otherwise = point.
   g_cfg.pipSize = (g_cfg.digits == 3 || g_cfg.digits == 5)
                   ? g_cfg.point * 10.0
                   : g_cfg.point;

   //--- Validation --------------------------------------------------
   if(g_cfg.swingLookback < 2)
     {
      Print("[APEX][CONFIG] InpSwingLookback must be >= 2");
      return(false);
     }
   if(g_cfg.fibT1 <= g_cfg.fibT2)
     {
      Print("[APEX][CONFIG] T1 level must be > T2 level (spec: 0.382 > 0.236)");
      return(false);
     }
   if(g_cfg.fibSLExt >= 0.0)
     {
      Print("[APEX][CONFIG] fibSLExt must be negative (spec: -0.10)");
      return(false);
     }
   if(g_cfg.riskPerTradePct <= 0.0 || g_cfg.riskPerTradePct > 5.0)
     {
      Print("[APEX][CONFIG] RiskPerTrade out of sane range (0 < x <= 5)");
      return(false);
     }
   if(g_cfg.maFast >= g_cfg.maSlow)
     {
      Print("[APEX][CONFIG] MA fast period must be < slow period");
      return(false);
     }
   if(g_cfg.maxConcurrent < 1 || g_cfg.maxConcurrent > APEX_MAX_TRADES)
     {
      Print("[APEX][CONFIG] maxConcurrent out of range (1..", APEX_MAX_TRADES, ")");
      return(false);
     }
   if(g_cfg.point <= 0.0)
     {
      Print("[APEX][CONFIG] Symbol point is zero — market not ready?");
      return(false);
     }

   return(true);
  }

//+------------------------------------------------------------------+
//| Helper: convert pips to price distance for current symbol.       |
//+------------------------------------------------------------------+
double ApexConfig_PipsToPrice(const double pips)
  {
   return(pips * g_cfg.pipSize);
  }

//+------------------------------------------------------------------+
//| Helper: convert price distance to pips for current symbol.       |
//+------------------------------------------------------------------+
double ApexConfig_PriceToPips(const double priceDist)
  {
   if(g_cfg.pipSize <= 0.0)
      return(0.0);
   return(priceDist / g_cfg.pipSize);
  }

//+------------------------------------------------------------------+
//| Helper: normalise a price to the symbol's digits.                |
//+------------------------------------------------------------------+
double ApexConfig_NormalizePrice(const double price)
  {
   return(NormalizeDouble(price, g_cfg.digits));
  }

#endif // __APEX_CONFIG_MQH__
//+------------------------------------------------------------------+
