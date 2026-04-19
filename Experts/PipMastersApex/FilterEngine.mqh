//+------------------------------------------------------------------+
//| FilterEngine.mqh — Pip Masters APEX v2.0                         |
//| MA50/200, RSI(14), ATR(14), and spread filter gates              |
//+------------------------------------------------------------------+
#pragma once
#include "Config.mqh"

enum FilterFailReason
{
   FF_NONE,
   FF_MA_DISAGREEMENT,
   FF_RSI_WRONG_SIDE,
   FF_ATR_TOO_LOW,
   FF_ATR_TOO_HIGH,
   FF_SPREAD_TOO_WIDE
};

struct FilterCheckResult
{
   FilterResult      result;
   FilterFailReason  reason;
};

class CFilterEngine
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;

   int m_handleMA50;
   int m_handleMA200;
   int m_handleRSI;
   int m_handleATR;

   double GetIndicatorValue(int handle, int shift = 1)
   {
      double buf[1];
      if(CopyBuffer(handle, 0, shift, 1, buf) < 1) return 0;
      return buf[0];
   }

public:
   CFilterEngine() : m_handleMA50(INVALID_HANDLE), m_handleMA200(INVALID_HANDLE),
                     m_handleRSI(INVALID_HANDLE), m_handleATR(INVALID_HANDLE) {}

   bool Init(const string symbol, ENUM_TIMEFRAMES tf)
   {
      m_symbol = symbol;
      m_tf     = tf;

      m_handleMA50  = iMA(symbol, tf, MA_FAST_PERIOD, 0, MODE_SMA, PRICE_CLOSE);
      m_handleMA200 = iMA(symbol, tf, MA_SLOW_PERIOD, 0, MODE_SMA, PRICE_CLOSE);
      m_handleRSI   = iRSI(symbol, tf, RSI_PERIOD, PRICE_CLOSE);
      m_handleATR   = iATR(symbol, tf, ATR_PERIOD);

      return (m_handleMA50 != INVALID_HANDLE &&
              m_handleMA200 != INVALID_HANDLE &&
              m_handleRSI   != INVALID_HANDLE &&
              m_handleATR   != INVALID_HANDLE);
   }

   void Deinit()
   {
      if(m_handleMA50  != INVALID_HANDLE) IndicatorRelease(m_handleMA50);
      if(m_handleMA200 != INVALID_HANDLE) IndicatorRelease(m_handleMA200);
      if(m_handleRSI   != INVALID_HANDLE) IndicatorRelease(m_handleRSI);
      if(m_handleATR   != INVALID_HANDLE) IndicatorRelease(m_handleATR);
   }

   FilterCheckResult Check(BOSDirection dir)
   {
      FilterCheckResult res;
      res.result = FILTER_PASS;
      res.reason = FF_NONE;

      double ma50  = GetIndicatorValue(m_handleMA50);
      double ma200 = GetIndicatorValue(m_handleMA200);
      double rsi   = GetIndicatorValue(m_handleRSI);
      double atr   = GetIndicatorValue(m_handleATR);

      // MA filter
      if(dir == BOS_BULLISH && ma50 <= ma200)
      { res.result = FILTER_FAIL; res.reason = FF_MA_DISAGREEMENT; return res; }
      if(dir == BOS_BEARISH && ma50 >= ma200)
      { res.result = FILTER_FAIL; res.reason = FF_MA_DISAGREEMENT; return res; }

      // RSI filter
      if(dir == BOS_BULLISH && rsi <= RSI_BULL_THRESHOLD)
      { res.result = FILTER_FAIL; res.reason = FF_RSI_WRONG_SIDE; return res; }
      if(dir == BOS_BEARISH && rsi >= RSI_BEAR_THRESHOLD)
      { res.result = FILTER_FAIL; res.reason = FF_RSI_WRONG_SIDE; return res; }

      // ATR floor — dead market
      if(atr < ATR_MIN_THRESHOLD)
      { res.result = FILTER_FAIL; res.reason = FF_ATR_TOO_LOW; return res; }

      // ATR ceiling — extreme spike / news
      if(atr > ATR_MAX_THRESHOLD)
      { res.result = FILTER_FAIL; res.reason = FF_ATR_TOO_HIGH; return res; }

      // Spread filter
      long spreadPts = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      double spreadPips = spreadPts * SymbolInfoDouble(m_symbol, SYMBOL_POINT)
                          / ((SymbolInfoInteger(m_symbol, SYMBOL_DIGITS) == 3 ||
                              SymbolInfoInteger(m_symbol, SYMBOL_DIGITS) == 5)
                             ? 0.0001 : 0.01);
      if(spreadPips > MAX_SPREAD_PIPS)
      { res.result = FILTER_FAIL; res.reason = FF_SPREAD_TOO_WIDE; return res; }

      return res;
   }

   // Individual accessors for logging
   double MA50()  { return GetIndicatorValue(m_handleMA50); }
   double MA200() { return GetIndicatorValue(m_handleMA200); }
   double RSI()   { return GetIndicatorValue(m_handleRSI); }
   double ATR()   { return GetIndicatorValue(m_handleATR); }

   string FailReasonStr(FilterFailReason r)
   {
      switch(r)
      {
         case FF_MA_DISAGREEMENT: return "MA_DISAGREEMENT";
         case FF_RSI_WRONG_SIDE:  return "RSI_WRONG_SIDE";
         case FF_ATR_TOO_LOW:     return "ATR_TOO_LOW";
         case FF_ATR_TOO_HIGH:    return "ATR_TOO_HIGH";
         case FF_SPREAD_TOO_WIDE: return "SPREAD_TOO_WIDE";
         default:                 return "NONE";
      }
   }
};
