//+------------------------------------------------------------------+
//| SwingEngine.mqh — Pip Masters APEX v2.0                          |
//| Swing high/low detection, labelling, and ring buffer storage     |
//+------------------------------------------------------------------+
#pragma once
#include "Config.mqh"

#define MAX_SWINGS 200

struct SwingPoint
{
   double      price;
   int         barIndex;   // iBarShift index at time of confirmation
   datetime    time;
   SwingLabel  label;
   bool        isHigh;     // true = swing high, false = swing low
};

class CSwingEngine
{
private:
   SwingPoint  m_swings[MAX_SWINGS];
   int         m_count;
   int         m_lookback;
   string      m_symbol;
   ENUM_TIMEFRAMES m_tf;

   // Last confirmed swing high and low (for BOS reference)
   double      m_lastConfirmedHH;
   double      m_lastConfirmedLL;
   double      m_lastHL;   // HL that preceded the last bullish BOS candidate
   double      m_lastLH;   // LH that preceded the last bearish BOS candidate

   bool IsSwingHigh(int bar)
   {
      double h = iHigh(m_symbol, m_tf, bar);
      for(int i = 1; i <= m_lookback; i++)
      {
         if(iHigh(m_symbol, m_tf, bar + i) >= h) return false;
         if(iHigh(m_symbol, m_tf, bar - i) >= h) return false;
      }
      return true;
   }

   bool IsSwingLow(int bar)
   {
      double l = iLow(m_symbol, m_tf, bar);
      for(int i = 1; i <= m_lookback; i++)
      {
         if(iLow(m_symbol, m_tf, bar + i) <= l) return false;
         if(iLow(m_symbol, m_tf, bar - i) <= l) return false;
      }
      return true;
   }

   void AddSwing(double price, int barIndex, datetime t, bool isHigh, SwingLabel lbl)
   {
      // Shift ring buffer
      if(m_count < MAX_SWINGS)
         m_count++;
      else
      {
         // Shift everything left to make room
         for(int i = 0; i < MAX_SWINGS - 1; i++)
            m_swings[i] = m_swings[i + 1];
      }
      int idx = m_count - 1;
      m_swings[idx].price    = price;
      m_swings[idx].barIndex = barIndex;
      m_swings[idx].time     = t;
      m_swings[idx].label    = lbl;
      m_swings[idx].isHigh   = isHigh;

      if(isHigh && lbl == SWING_HH) m_lastConfirmedHH = price;
      if(!isHigh && lbl == SWING_LL) m_lastConfirmedLL = price;
      if(!isHigh && lbl == SWING_HL) m_lastHL = price;
      if(isHigh  && lbl == SWING_LH) m_lastLH = price;
   }

   SwingLabel ClassifyHigh(double price)
   {
      // Find the previous swing high to compare
      for(int i = m_count - 1; i >= 0; i--)
         if(m_swings[i].isHigh)
            return (price > m_swings[i].price) ? SWING_HH : SWING_LH;
      return SWING_HH; // First swing high defaults to HH
   }

   SwingLabel ClassifyLow(double price)
   {
      for(int i = m_count - 1; i >= 0; i--)
         if(!m_swings[i].isHigh)
            return (price > m_swings[i].price) ? SWING_HL : SWING_LL;
      return SWING_HL; // First swing low defaults to HL
   }

   // Track which bars have already been registered as swings
   bool m_registeredBars[MAX_SWINGS * 2];
   int  m_registeredBarIndices[MAX_SWINGS * 2];
   int  m_regCount;

   bool AlreadyRegistered(int bar)
   {
      for(int i = 0; i < m_regCount; i++)
         if(m_registeredBarIndices[i] == bar) return true;
      return false;
   }

   void RegisterBar(int bar)
   {
      if(m_regCount < MAX_SWINGS * 2)
      {
         m_registeredBarIndices[m_regCount] = bar;
         m_regCount++;
      }
   }

public:
   CSwingEngine() : m_count(0), m_regCount(0),
                    m_lastConfirmedHH(0), m_lastConfirmedLL(DBL_MAX),
                    m_lastHL(0), m_lastLH(DBL_MAX) {}

   void Init(const string symbol, ENUM_TIMEFRAMES tf, int lookback)
   {
      m_symbol   = symbol;
      m_tf       = tf;
      m_lookback = lookback;
      m_count    = 0;
      m_regCount = 0;
      ArrayInitialize(m_registeredBarIndices, -1);
   }

   // Call on every new bar (bar 0 is current forming bar; bar 1+ are closed)
   // We confirm swings at bar m_lookback+1 — all right-side candles are closed.
   void Update()
   {
      // The bar we are examining for swing potential is m_lookback+1 bars back
      // (it needs m_lookback closed bars to its right)
      int examBar = m_lookback + 1;

      if(AlreadyRegistered(iBarShift(m_symbol, m_tf, iTime(m_symbol, m_tf, examBar))))
         return;

      if(IsSwingHigh(examBar))
      {
         double price = iHigh(m_symbol, m_tf, examBar);
         datetime t   = iTime(m_symbol, m_tf, examBar);
         SwingLabel lbl = ClassifyHigh(price);
         AddSwing(price, examBar, t, true, lbl);
         RegisterBar(iBarShift(m_symbol, m_tf, t));
      }
      else if(IsSwingLow(examBar))
      {
         double price = iLow(m_symbol, m_tf, examBar);
         datetime t   = iTime(m_symbol, m_tf, examBar);
         SwingLabel lbl = ClassifyLow(price);
         AddSwing(price, examBar, t, false, lbl);
         RegisterBar(iBarShift(m_symbol, m_tf, t));
      }
   }

   // Accessors
   int         Count()              const { return m_count; }
   SwingPoint  Get(int i)           const { return m_swings[i]; }
   double      LastConfirmedHH()    const { return m_lastConfirmedHH; }
   double      LastConfirmedLL()    const { return m_lastConfirmedLL; }
   double      LastHL()             const { return m_lastHL; }
   double      LastLH()             const { return m_lastLH; }

   // Most recent swing of a given type (search from newest)
   bool GetLatestByLabel(SwingLabel lbl, SwingPoint &out)
   {
      for(int i = m_count - 1; i >= 0; i--)
         if(m_swings[i].label == lbl) { out = m_swings[i]; return true; }
      return false;
   }

   // Most recent swing high (any label)
   bool GetLatestHigh(SwingPoint &out)
   {
      for(int i = m_count - 1; i >= 0; i--)
         if(m_swings[i].isHigh) { out = m_swings[i]; return true; }
      return false;
   }

   // Most recent swing low (any label)
   bool GetLatestLow(SwingPoint &out)
   {
      for(int i = m_count - 1; i >= 0; i--)
         if(!m_swings[i].isHigh) { out = m_swings[i]; return true; }
      return false;
   }
};
