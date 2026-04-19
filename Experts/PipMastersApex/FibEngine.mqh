//+------------------------------------------------------------------+
//| FibEngine.mqh — Pip Masters APEX v2.0                            |
//| Fibonacci level calculation, post-BOS extreme tracking,          |
//| entry zone detection, and setup invalidation                     |
//+------------------------------------------------------------------+
#pragma once
#include "Config.mqh"

enum FibSetupState
{
   FIB_IDLE,            // No active setup
   FIB_WAITING_EXTREME, // BOS confirmed, watching for post-BOS extreme
   FIB_RETRACING,       // Post-BOS extreme locked; retracement underway
   FIB_ENTRY_ZONE,      // Price is inside 23.6%–38.2% entry zone
   FIB_INVALID          // Setup invalidated
};

struct FibLevels
{
   double sl;     // -10% extension
   double base;   // 0%  structural base
   double t2;     // 23.6% T2 entry
   double t1;     // 38.2% T1 entry
   double mid50;  // 50%
   double mid618; // 61.8%
   double tp;     // 100% post-BOS extreme (TP target)
};

class CFibEngine
{
private:
   string          m_symbol;
   ENUM_TIMEFRAMES m_tf;

   BOSDirection    m_dir;
   FibSetupState   m_state;
   FibLevels       m_levels;

   double          m_bosBase;        // 0% anchor: HL (bull) or LH (bear)
   double          m_postBOSExtreme; // 100% anchor: highest/lowest after BOS
   bool            m_extremeLocked;

   // Track post-BOS extreme dynamically until retracement confirms
   double          m_runningExtreme;

   void CalcLevels()
   {
      double range = m_postBOSExtreme - m_bosBase; // positive for bull, negative for bear

      m_levels.tp     = m_postBOSExtreme;                      // 100%
      m_levels.mid618 = m_postBOSExtreme - 0.382 * range;      // 61.8% retrace = 38.2% from top
      m_levels.mid50  = m_postBOSExtreme - 0.5   * range;      // 50%
      m_levels.t1     = m_postBOSExtreme - FIB_T1_LEVEL * range; // 38.2%
      m_levels.t2     = m_postBOSExtreme - FIB_T2_LEVEL * range; // 23.6%
      m_levels.base   = m_bosBase;                               // 0%
      m_levels.sl     = m_bosBase + FIB_SL_EXTENSION * range;   // -10%
   }

   bool IsPriceInEntryZone(double price)
   {
      if(m_dir == BOS_BULLISH)
         return (price >= m_levels.t2 && price <= m_levels.t1);
      if(m_dir == BOS_BEARISH)
         return (price <= m_levels.t2 && price >= m_levels.t1);
      return false;
   }

   // Returns true if the last closed candle's CLOSE breaches the 0% base
   bool ZeroLevelBreached()
   {
      double close1 = iClose(m_symbol, m_tf, 1);
      if(m_dir == BOS_BULLISH) return close1 < m_levels.base;
      if(m_dir == BOS_BEARISH) return close1 > m_levels.base;
      return false;
   }

public:
   CFibEngine() : m_state(FIB_IDLE), m_dir(BOS_NONE), m_postBOSExtreme(0),
                  m_bosBase(0), m_extremeLocked(false), m_runningExtreme(0) {}

   void Init(const string symbol, ENUM_TIMEFRAMES tf)
   {
      m_symbol = symbol;
      m_tf     = tf;
   }

   // Called immediately when a BOS is confirmed
   void OnBOS(BOSDirection dir, double structuralBase)
   {
      m_dir           = dir;
      m_bosBase       = structuralBase;
      m_extremeLocked = false;
      m_state         = FIB_WAITING_EXTREME;

      // Seed the running extreme with current bar high/low
      m_runningExtreme = (dir == BOS_BULLISH)
                         ? iHigh(m_symbol, m_tf, 0)
                         : iLow(m_symbol, m_tf, 0);

      ZeroMemory(m_levels);
   }

   // Call on every tick / bar update after BOS
   // Returns true when the state changes to ENTRY_ZONE for the first time
   bool Update()
   {
      if(m_state == FIB_IDLE || m_state == FIB_INVALID) return false;

      double currentHigh  = iHigh(m_symbol, m_tf, 0);
      double currentLow   = iLow(m_symbol, m_tf, 0);
      double close1       = iClose(m_symbol, m_tf, 1);

      // Invalidation check (0% breach by closed candle) — applies in any active state
      if(ZeroLevelBreached())
      {
         m_state = FIB_INVALID;
         return false;
      }

      if(m_state == FIB_WAITING_EXTREME)
      {
         // Keep tracking the running extreme
         if(m_dir == BOS_BULLISH)
         {
            if(currentHigh > m_runningExtreme) m_runningExtreme = currentHigh;

            // Retracement begun: current bar's high is below the running extreme
            // and price is now pulling back (current close < running extreme)
            if(close1 < m_runningExtreme && m_runningExtreme > m_bosBase)
            {
               m_postBOSExtreme = m_runningExtreme;
               m_extremeLocked  = true;
               CalcLevels();
               m_state = FIB_RETRACING;
            }
         }
         else if(m_dir == BOS_BEARISH)
         {
            if(currentLow < m_runningExtreme) m_runningExtreme = currentLow;

            if(close1 > m_runningExtreme && m_runningExtreme < m_bosBase)
            {
               m_postBOSExtreme = m_runningExtreme;
               m_extremeLocked  = true;
               CalcLevels();
               m_state = FIB_RETRACING;
            }
         }
      }

      if(m_state == FIB_RETRACING || m_state == FIB_ENTRY_ZONE)
      {
         double midPrice = (currentHigh + currentLow) / 2.0;
         bool inZone = IsPriceInEntryZone(midPrice) ||
                       IsPriceInEntryZone(currentHigh) ||
                       IsPriceInEntryZone(currentLow);

         if(inZone)
         {
            bool wasAlreadyInZone = (m_state == FIB_ENTRY_ZONE);
            m_state = FIB_ENTRY_ZONE;
            return !wasAlreadyInZone; // signal only on first entry
         }
         else if(m_state == FIB_ENTRY_ZONE)
         {
            m_state = FIB_RETRACING; // price left zone without triggering — wait
         }
      }

      return false;
   }

   // Check for a confirmed bullish/bearish candle CLOSE inside the entry zone
   // (spec: candle BODY must close between 38.2% and 23.6%)
   bool EntrySignalOnClose()
   {
      if(m_state != FIB_ENTRY_ZONE) return false;
      double close1 = iClose(m_symbol, m_tf, 1);
      double open1  = iOpen(m_symbol, m_tf, 1);

      bool closeInZone = IsPriceInEntryZone(close1);
      if(!closeInZone) return false;

      // Candle direction must match BOS direction
      if(m_dir == BOS_BULLISH) return close1 > open1; // bullish close
      if(m_dir == BOS_BEARISH) return close1 < open1; // bearish close
      return false;
   }

   void Reset()
   {
      m_state         = FIB_IDLE;
      m_dir           = BOS_NONE;
      m_extremeLocked = false;
      m_runningExtreme = 0;
      ZeroMemory(m_levels);
   }

   FibSetupState State()           const { return m_state; }
   FibLevels     Levels()          const { return m_levels; }
   BOSDirection  Direction()       const { return m_dir; }
   double        PostBOSExtreme()  const { return m_postBOSExtreme; }
   double        StructuralBase()  const { return m_bosBase; }
   bool          IsActive()        const { return m_state != FIB_IDLE && m_state != FIB_INVALID; }
};
