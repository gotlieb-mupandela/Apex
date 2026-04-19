//+------------------------------------------------------------------+
//| StructureEngine.mqh — Pip Masters APEX v2.0                      |
//| Trend classification and Break of Structure detection            |
//+------------------------------------------------------------------+
#pragma once
#include "Config.mqh"
#include "SwingEngine.mqh"

class CStructureEngine
{
private:
   CSwingEngine *m_swing;
   string        m_symbol;
   ENUM_TIMEFRAMES m_tf;

   TrendState    m_trend;
   BOSDirection  m_lastBOS;
   double        m_bosPrice;
   datetime      m_bosTime;

   // Track the previous swing high/low confirmed before this BOS
   double        m_preBOSStructuralBase; // HL (bullish) or LH (bearish)

   // Prevent re-firing the same BOS event
   datetime      m_lastBOSTime;

   TrendState ClassifyTrend()
   {
      // Need at least 4 swings to classify a sequence
      if(m_swing.Count() < 4) return TREND_NEUTRAL;

      // Collect recent swing highs and lows (last 6 swings for context)
      double highs[6]; int hCount = 0;
      double lows[6];  int lCount = 0;

      for(int i = m_swing.Count() - 1; i >= 0 && (hCount < 6 || lCount < 6); i--)
      {
         SwingPoint sp = m_swing.Get(i);
         if(sp.isHigh && hCount < 6) highs[hCount++] = sp.price;
         else if(!sp.isHigh && lCount < 6) lows[lCount++] = sp.price;
      }

      if(hCount < 2 || lCount < 2) return TREND_NEUTRAL;

      // Bullish: most recent high > previous high, most recent low > previous low
      bool bullHigHigh = highs[0] > highs[1];
      bool bullHigLow  = lows[0] > lows[1];

      // Bearish: most recent high < previous high, most recent low < previous low
      bool bearLowHigh = highs[0] < highs[1];
      bool bearLowLow  = lows[0] < lows[1];

      if(bullHigHigh && bullHigLow) return TREND_BULLISH;
      if(bearLowHigh && bearLowLow) return TREND_BEARISH;
      return TREND_NEUTRAL;
   }

public:
   CStructureEngine() : m_trend(TREND_NEUTRAL), m_lastBOS(BOS_NONE),
                        m_bosPrice(0), m_bosTime(0), m_lastBOSTime(0),
                        m_preBOSStructuralBase(0) {}

   void Init(CSwingEngine *swing, const string symbol, ENUM_TIMEFRAMES tf)
   {
      m_swing  = swing;
      m_symbol = symbol;
      m_tf     = tf;
   }

   // Returns true if a new BOS was detected on this update
   bool Update()
   {
      m_trend = ClassifyTrend();

      // Candle at bar 1 is the most recently CLOSED bar — BOS must close beyond level
      double closePrice = iClose(m_symbol, m_tf, 1);
      datetime barTime  = iTime(m_symbol, m_tf, 1);

      // Prevent re-triggering on the same bar
      if(barTime == m_lastBOSTime) return false;

      double lastHH = m_swing.LastConfirmedHH();
      double lastLL = m_swing.LastConfirmedLL();

      // Bullish BOS: close above the last confirmed HH
      if(m_trend == TREND_BULLISH && lastHH > 0 && closePrice > lastHH)
      {
         m_lastBOS              = BOS_BULLISH;
         m_bosPrice             = lastHH;
         m_bosTime              = barTime;
         m_lastBOSTime          = barTime;
         m_preBOSStructuralBase = m_swing.LastHL(); // HL before BOS = 0% anchor
         return true;
      }

      // Bearish BOS: close below the last confirmed LL
      if(m_trend == TREND_BEARISH && lastLL < DBL_MAX && closePrice < lastLL)
      {
         m_lastBOS              = BOS_BEARISH;
         m_bosPrice             = lastLL;
         m_bosTime              = barTime;
         m_lastBOSTime          = barTime;
         m_preBOSStructuralBase = m_swing.LastLH(); // LH before BOS = 0% anchor
         return true;
      }

      return false;
   }

   // Check if a new BOS in the OPPOSITE direction has formed (invalidation trigger)
   bool OppositeBoSFormed(BOSDirection currentSetupDir)
   {
      double closePrice = iClose(m_symbol, m_tf, 1);
      if(currentSetupDir == BOS_BULLISH)
      {
         double lastLL = m_swing.LastConfirmedLL();
         return (lastLL < DBL_MAX && closePrice < lastLL);
      }
      if(currentSetupDir == BOS_BEARISH)
      {
         double lastHH = m_swing.LastConfirmedHH();
         return (lastHH > 0 && closePrice > lastHH);
      }
      return false;
   }

   TrendState    Trend()                const { return m_trend; }
   BOSDirection  LastBOS()              const { return m_lastBOS; }
   double        BOSPrice()             const { return m_bosPrice; }
   datetime      BOSTime()              const { return m_bosTime; }
   double        PreBOSStructuralBase() const { return m_preBOSStructuralBase; }

   void ResetBOS()
   {
      m_lastBOS              = BOS_NONE;
      m_bosPrice             = 0;
      m_bosTime              = 0;
      m_preBOSStructuralBase = 0;
   }
};
