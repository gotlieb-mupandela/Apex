//+------------------------------------------------------------------+
//|                                                  SwingEngine.mqh |
//|                      PipMasters APEX v2.0 | Swing Detection      |
//|                                                                  |
//| PURPOSE: Scans the M15 chart and identifies confirmed swing      |
//|          highs and swing lows using the fractal-style lookback   |
//|          rule from Spec A3. Every confirmed swing is classified  |
//|          (HH / HL / LH / LL) and stored in a circular buffer     |
//|          for downstream modules (StructureEngine, FibEngine).    |
//|                                                                  |
//| SPEC REFERENCES:                                                 |
//|   A3 — Swing detection, classification, lookback (default 5).    |
//|   A16 — Never infer swings from unfinished bars.                 |
//|   C1 — SWING_LOOKBACK parameter.                                 |
//+------------------------------------------------------------------+
#ifndef __APEX_SWING_ENGINE_MQH__
#define __APEX_SWING_ENGINE_MQH__

#include "Config.mqh"

#property strict

//+------------------------------------------------------------------+
//| Swing point record.                                              |
//| Stores the price, bar index (ShiftFromCurrent at confirmation),  |
//| bar time, and the classification label.                         |
//+------------------------------------------------------------------+
struct SSwingPoint
  {
   double            price;       // Exact high/low of the swing candle
   datetime          time;        // Candle open time (UTC broker time)
   int               shift;       // Bar shift at time of confirmation (0 = current)
   bool              isHigh;      // true = high-type, false = low-type
   ENUM_SWING_TYPE   label;       // HH / LH / HL / LL
  };

//+------------------------------------------------------------------+
//| Circular buffer of swing points.                                 |
//| Newest element = g_swings[g_swingCount - 1]. Oldest drops off    |
//| once we exceed cfg.maxSwingsStored.                             |
//+------------------------------------------------------------------+
SSwingPoint g_swings[];
int         g_swingCount     = 0;
datetime    g_lastScannedBar = 0;

//+------------------------------------------------------------------+
//| Swing_Reset — wipes all stored swings. Called on init / symbol   |
//| or timeframe change.                                             |
//+------------------------------------------------------------------+
void Swing_Reset()
  {
   ArrayResize(g_swings, g_cfg.maxSwingsStored);
   g_swingCount     = 0;
   g_lastScannedBar = 0;
  }

//+------------------------------------------------------------------+
//| Internal: push a new swing onto the circular buffer.             |
//+------------------------------------------------------------------+
void Swing_Push(const SSwingPoint &sp)
  {
   if(g_cfg.maxSwingsStored <= 0)
      return;

   if(g_swingCount < g_cfg.maxSwingsStored)
     {
      g_swings[g_swingCount] = sp;
      g_swingCount++;
      return;
     }

   // Buffer full — shift left by one, append at tail.
   for(int i = 0; i < g_cfg.maxSwingsStored - 1; i++)
      g_swings[i] = g_swings[i + 1];
   g_swings[g_cfg.maxSwingsStored - 1] = sp;
  }

//+------------------------------------------------------------------+
//| Swing_Count — public getter for number of stored swings.         |
//+------------------------------------------------------------------+
int Swing_Count()
  {
   return(g_swingCount);
  }

//+------------------------------------------------------------------+
//| Swing_Get — fetch swing by index (0 = oldest, Count-1 = newest). |
//+------------------------------------------------------------------+
bool Swing_Get(const int index, SSwingPoint &out)
  {
   if(index < 0 || index >= g_swingCount)
      return(false);
   out = g_swings[index];
   return(true);
  }

//+------------------------------------------------------------------+
//| Swing_GetLast — last stored swing regardless of type.            |
//+------------------------------------------------------------------+
bool Swing_GetLast(SSwingPoint &out)
  {
   if(g_swingCount <= 0)
      return(false);
   out = g_swings[g_swingCount - 1];
   return(true);
  }

//+------------------------------------------------------------------+
//| Swing_GetLastHigh — most recent high-type swing (any class).     |
//+------------------------------------------------------------------+
bool Swing_GetLastHigh(SSwingPoint &out)
  {
   for(int i = g_swingCount - 1; i >= 0; i--)
     {
      if(g_swings[i].isHigh)
        {
         out = g_swings[i];
         return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Swing_GetLastLow — most recent low-type swing (any class).       |
//+------------------------------------------------------------------+
bool Swing_GetLastLow(SSwingPoint &out)
  {
   for(int i = g_swingCount - 1; i >= 0; i--)
     {
      if(!g_swings[i].isHigh)
        {
         out = g_swings[i];
         return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Swing_GetLastByLabel — latest swing matching a class label.      |
//+------------------------------------------------------------------+
bool Swing_GetLastByLabel(const ENUM_SWING_TYPE label, SSwingPoint &out)
  {
   for(int i = g_swingCount - 1; i >= 0; i--)
     {
      if(g_swings[i].label == label)
        {
         out = g_swings[i];
         return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Internal: classify a high-type swing against the previous high.  |
//+------------------------------------------------------------------+
ENUM_SWING_TYPE Swing_ClassifyHigh(const double newHigh)
  {
   SSwingPoint prev;
   if(!Swing_GetLastHigh(prev))
      return(SWING_HH);               // First high — mark as HH by convention
   return(newHigh > prev.price ? SWING_HH : SWING_LH);
  }

//+------------------------------------------------------------------+
//| Internal: classify a low-type swing against the previous low.    |
//+------------------------------------------------------------------+
ENUM_SWING_TYPE Swing_ClassifyLow(const double newLow)
  {
   SSwingPoint prev;
   if(!Swing_GetLastLow(prev))
      return(SWING_HL);               // First low — mark as HL by convention
   return(newLow > prev.price ? SWING_HL : SWING_LL);
  }

//+------------------------------------------------------------------+
//| Internal: check if the bar at `shift` is a swing high candle.    |
//| Spec A3: lookback left AND right must show strictly lower highs. |
//| Equal highs are treated as NOT a swing (conservative).           |
//+------------------------------------------------------------------+
bool Swing_IsSwingHigh(const int shift, const int lookback)
  {
   const double mid = iHigh(_Symbol, APEX_TIMEFRAME, shift);
   if(mid <= 0.0)
      return(false);

   for(int k = 1; k <= lookback; k++)
     {
      const double leftH  = iHigh(_Symbol, APEX_TIMEFRAME, shift + k);
      const double rightH = iHigh(_Symbol, APEX_TIMEFRAME, shift - k);
      if(leftH  <= 0.0 || rightH <= 0.0)
         return(false);
      if(leftH  >= mid) return(false);
      if(rightH >= mid) return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Internal: check if the bar at `shift` is a swing low candle.     |
//+------------------------------------------------------------------+
bool Swing_IsSwingLow(const int shift, const int lookback)
  {
   const double mid = iLow(_Symbol, APEX_TIMEFRAME, shift);
   if(mid <= 0.0)
      return(false);

   for(int k = 1; k <= lookback; k++)
     {
      const double leftL  = iLow(_Symbol, APEX_TIMEFRAME, shift + k);
      const double rightL = iLow(_Symbol, APEX_TIMEFRAME, shift - k);
      if(leftL  <= 0.0 || rightL <= 0.0)
         return(false);
      if(leftL  <= mid) return(false);
      if(rightL <= mid) return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Internal: has a swing at this time already been recorded?        |
//| Prevents duplicate pushes when the scanner revisits bars.        |
//+------------------------------------------------------------------+
bool Swing_AlreadyRecorded(const datetime t, const bool isHigh)
  {
   for(int i = g_swingCount - 1; i >= 0; i--)
     {
      if(g_swings[i].time == t && g_swings[i].isHigh == isHigh)
         return(true);
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Swing_TryConfirmAt — evaluate a candidate swing bar at `shift`.  |
//| Returns true if a new swing was recorded, and fills `outSwing`.  |
//| Spec A3: a swing is CONFIRMED only after `lookback` candles on   |
//| the RIGHT side have closed showing lower highs / higher lows.    |
//+------------------------------------------------------------------+
bool Swing_TryConfirmAt(const int shift, SSwingPoint &outSwing)
  {
   const int lb = g_cfg.swingLookback;
   if(shift < lb)
      return(false);   // Not enough right-side bars confirmed yet.

   const datetime t = iTime(_Symbol, APEX_TIMEFRAME, shift);
   if(t == 0)
      return(false);

   // --- Swing High? -----------------------------------------------
   if(Swing_IsSwingHigh(shift, lb) && !Swing_AlreadyRecorded(t, true))
     {
      SSwingPoint sp;
      sp.price  = iHigh(_Symbol, APEX_TIMEFRAME, shift);
      sp.time   = t;
      sp.shift  = shift;
      sp.isHigh = true;
      sp.label  = Swing_ClassifyHigh(sp.price);
      Swing_Push(sp);
      outSwing = sp;
      return(true);
     }

   // --- Swing Low? ------------------------------------------------
   if(Swing_IsSwingLow(shift, lb) && !Swing_AlreadyRecorded(t, false))
     {
      SSwingPoint sp;
      sp.price  = iLow(_Symbol, APEX_TIMEFRAME, shift);
      sp.time   = t;
      sp.shift  = shift;
      sp.isHigh = false;
      sp.label  = Swing_ClassifyLow(sp.price);
      Swing_Push(sp);
      outSwing = sp;
      return(true);
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Swing_SeedFromHistory                                            |
//| Called once during OnInit to back-fill the swing buffer from     |
//| recent chart history, so the engine starts with context.         |
//|                                                                  |
//| Scans from the oldest eligible bar forward to bar `lookback`,    |
//| respecting the right-side confirmation window.                   |
//+------------------------------------------------------------------+
void Swing_SeedFromHistory()
  {
   Swing_Reset();

   const int lb    = g_cfg.swingLookback;
   const int bars  = Bars(_Symbol, APEX_TIMEFRAME);
   if(bars <= (lb * 2 + 2))
      return;

   // Cap the seed window so we don't scan the entire history.
   int startShift = MathMin(bars - lb - 1, g_cfg.maxHistoryBars);
   if(startShift < lb + 1)
      return;

   // Walk from oldest (highest shift) to newest confirmed (shift = lb).
   for(int shift = startShift; shift >= lb; shift--)
     {
      SSwingPoint tmp;
      Swing_TryConfirmAt(shift, tmp);
     }

   // Record the latest bar time we've covered.
   g_lastScannedBar = iTime(_Symbol, APEX_TIMEFRAME, lb);
  }

//+------------------------------------------------------------------+
//| Swing_OnNewBar                                                   |
//| Call this on every confirmed new bar (bar close of shift 1).     |
//| Evaluates whether bar at shift = lookback is NOW a confirmed     |
//| swing (it just received its last right-side confirmation).      |
//|                                                                  |
//| Returns the number of new swings recorded (0 or 1 typically).    |
//+------------------------------------------------------------------+
int Swing_OnNewBar(SSwingPoint &newest)
  {
   const int lb = g_cfg.swingLookback;
   SSwingPoint tmp;
   int added = 0;

   if(Swing_TryConfirmAt(lb, tmp))
     {
      newest = tmp;
      added  = 1;
     }

   g_lastScannedBar = iTime(_Symbol, APEX_TIMEFRAME, 0);
   return(added);
  }

//+------------------------------------------------------------------+
//| Swing_LabelToString — human-readable label for logs/dashboard.   |
//+------------------------------------------------------------------+
string Swing_LabelToString(const ENUM_SWING_TYPE t)
  {
   switch(t)
     {
      case SWING_HH: return("HH");
      case SWING_LH: return("LH");
      case SWING_HL: return("HL");
      case SWING_LL: return("LL");
      default:       return("--");
     }
  }

//+------------------------------------------------------------------+
//| Swing_DescribeLast — compact debug string for the newest swing.  |
//+------------------------------------------------------------------+
string Swing_DescribeLast()
  {
   SSwingPoint s;
   if(!Swing_GetLast(s))
      return("no swings yet");
   return(StringFormat("[%s] %.*f @ %s (shift=%d)",
                       Swing_LabelToString(s.label),
                       g_cfg.digits, s.price,
                       TimeToString(s.time, TIME_DATE|TIME_MINUTES),
                       s.shift));
  }

#endif // __APEX_SWING_ENGINE_MQH__
//+------------------------------------------------------------------+
