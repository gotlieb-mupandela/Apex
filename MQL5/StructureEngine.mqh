//+------------------------------------------------------------------+
//|                                              StructureEngine.mqh |
//|          PipMasters APEX v2.0 | Structure + BOS Detection        |
//|                                                                  |
//| PURPOSE: Consumes confirmed swing points produced by             |
//|          SwingEngine.mqh and decides:                            |
//|            1. Current market structure state (BULL/BEAR/NEUTRAL) |
//|               based on the HL-HH-HL-HH / LH-LL-LH-LL pattern.    |
//|            2. Whether a Break of Structure (BOS) has occurred —  |
//|               confirmed ONLY by a CLOSE beyond the most recent   |
//|               confirmed swing (wick breaks are ignored).         |
//|                                                                  |
//| SPEC REFERENCES:                                                 |
//|   A4  — Trend classification patterns.                           |
//|   A5  — BOS rule (CLOSE beyond level; wicks invalid).            |
//|   A14 — Opposing BOS invalidates the existing setup.             |
//|   A16 — Never treat wicks as BOS; never anchor Fib at BOS candle.|
//+------------------------------------------------------------------+
#ifndef __APEX_STRUCTURE_ENGINE_MQH__
#define __APEX_STRUCTURE_ENGINE_MQH__

#include "Config.mqh"
#include "SwingEngine.mqh"

#property strict

//+------------------------------------------------------------------+
//| BOS event descriptor.                                            |
//+------------------------------------------------------------------+
struct SBosEvent
  {
   ENUM_BOS_DIRECTION direction;    // BOS_BULLISH / BOS_BEARISH / BOS_NONE
   double             brokenLevel;  // Price of the swing that was broken
   datetime           brokenTime;   // Time of the broken swing candle
   double             closePrice;   // Close price of the BOS candle
   datetime           closeTime;    // Time of the BOS candle
   int                closeShift;   // Bar shift of the BOS candle at detection

   // Anchor swing for Fibonacci 0% (Spec A6).
   // For a BULLISH BOS this is the HL that preceded the BOS.
   // For a BEARISH BOS this is the LH that preceded the BOS.
   double             fibAnchorPrice;
   datetime           fibAnchorTime;
   ENUM_SWING_TYPE    fibAnchorLabel;
   bool               fibAnchorValid;
  };

//+------------------------------------------------------------------+
//| Structure state + last BOS — live globals owned by this module.  |
//+------------------------------------------------------------------+
ENUM_STRUCTURE_STATE g_structureState = STRUCT_NEUTRAL;
SBosEvent            g_lastBos;
bool                 g_lastBosValid   = false;
datetime             g_lastBosBarTime = 0;

//+------------------------------------------------------------------+
//| Structure_Reset — clear cached state. Call on init or reload.    |
//+------------------------------------------------------------------+
void Structure_Reset()
  {
   g_structureState        = STRUCT_NEUTRAL;
   g_lastBosValid          = false;
   g_lastBosBarTime        = 0;
   g_lastBos.direction     = BOS_NONE;
   g_lastBos.brokenLevel   = 0.0;
   g_lastBos.brokenTime    = 0;
   g_lastBos.closePrice    = 0.0;
   g_lastBos.closeTime     = 0;
   g_lastBos.closeShift    = -1;
   g_lastBos.fibAnchorPrice= 0.0;
   g_lastBos.fibAnchorTime = 0;
   g_lastBos.fibAnchorLabel= SWING_NONE;
   g_lastBos.fibAnchorValid= false;
  }

//+------------------------------------------------------------------+
//| Structure_State — public getter.                                 |
//+------------------------------------------------------------------+
ENUM_STRUCTURE_STATE Structure_State()
  {
   return(g_structureState);
  }

//+------------------------------------------------------------------+
//| Structure_LastBos — copy last BOS event to caller (if any).      |
//+------------------------------------------------------------------+
bool Structure_LastBos(SBosEvent &out)
  {
   if(!g_lastBosValid)
      return(false);
   out = g_lastBos;
   return(true);
  }

//+------------------------------------------------------------------+
//| Structure_StateToString — human-readable label.                  |
//+------------------------------------------------------------------+
string Structure_StateToString(const ENUM_STRUCTURE_STATE s)
  {
   switch(s)
     {
      case STRUCT_BULLISH: return("BULLISH");
      case STRUCT_BEARISH: return("BEARISH");
      default:             return("NEUTRAL");
     }
  }

//+------------------------------------------------------------------+
//| Structure_BosDirectionToString                                   |
//+------------------------------------------------------------------+
string Structure_BosDirectionToString(const ENUM_BOS_DIRECTION d)
  {
   switch(d)
     {
      case BOS_BULLISH: return("BULLISH_BOS");
      case BOS_BEARISH: return("BEARISH_BOS");
      default:          return("NONE");
     }
  }

//+------------------------------------------------------------------+
//| Internal: test the last N swings against a label sequence.       |
//|   `seq` is an array of ENUM_SWING_TYPE in oldest->newest order.  |
//| Returns true iff the last swings match the sequence exactly.     |
//+------------------------------------------------------------------+
bool Structure_MatchTail(const ENUM_SWING_TYPE &seq[], const int seqLen)
  {
   if(seqLen <= 0)
      return(false);
   if(Swing_Count() < seqLen)
      return(false);

   const int start = Swing_Count() - seqLen;
   for(int i = 0; i < seqLen; i++)
     {
      SSwingPoint sp;
      if(!Swing_Get(start + i, sp))
         return(false);
      if(sp.label != seq[i])
         return(false);
     }
   return(true);
  }

//+------------------------------------------------------------------+
//| Structure_Classify                                               |
//| Spec A4:                                                         |
//|   BULLISH pattern: HL -> HH -> HL -> HH                          |
//|   BEARISH pattern: LH -> LL -> LH -> LL                          |
//| Returns the recognised state; NEUTRAL otherwise.                 |
//+------------------------------------------------------------------+
ENUM_STRUCTURE_STATE Structure_Classify()
  {
   ENUM_SWING_TYPE bull[4];
   bull[0] = SWING_HL;
   bull[1] = SWING_HH;
   bull[2] = SWING_HL;
   bull[3] = SWING_HH;
   if(Structure_MatchTail(bull, 4))
      return(STRUCT_BULLISH);

   ENUM_SWING_TYPE bear[4];
   bear[0] = SWING_LH;
   bear[1] = SWING_LL;
   bear[2] = SWING_LH;
   bear[3] = SWING_LL;
   if(Structure_MatchTail(bear, 4))
      return(STRUCT_BEARISH);

   return(STRUCT_NEUTRAL);
  }

//+------------------------------------------------------------------+
//| Structure_Update                                                 |
//| Recomputes the market structure state. Call whenever a new swing |
//| is confirmed. Returns true if the state CHANGED.                 |
//+------------------------------------------------------------------+
bool Structure_Update(ENUM_STRUCTURE_STATE &newState)
  {
   const ENUM_STRUCTURE_STATE prev = g_structureState;
   const ENUM_STRUCTURE_STATE now  = Structure_Classify();

   // Only downgrade to NEUTRAL if there is no matching tail AND the
   // most recent swing would break the current trend pattern. We keep
   // the trend "sticky" until a confirming sequence appears in the
   // opposite direction — conservative and aligned with spec intent.
   if(now != STRUCT_NEUTRAL)
      g_structureState = now;
   else if(prev == STRUCT_NEUTRAL)
      g_structureState = STRUCT_NEUTRAL;
   // else leave as previous sticky state

   newState = g_structureState;
   return(newState != prev);
  }

//+------------------------------------------------------------------+
//| Internal: find the most recent HL before a given time.           |
//| Used as Fibonacci 0% anchor for a BULLISH BOS (Spec A6 STEP 3).  |
//+------------------------------------------------------------------+
bool Structure_FindPrecedingHL(const datetime bosCloseTime, SSwingPoint &out)
  {
   for(int i = Swing_Count() - 1; i >= 0; i--)
     {
      SSwingPoint sp;
      if(!Swing_Get(i, sp))
         continue;
      if(sp.time >= bosCloseTime)
         continue;
      if(sp.label == SWING_HL)
        {
         out = sp;
         return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Internal: find the most recent LH before a given time.           |
//| Used as Fibonacci 0% anchor for a BEARISH BOS (Spec A6 STEP 3).  |
//+------------------------------------------------------------------+
bool Structure_FindPrecedingLH(const datetime bosCloseTime, SSwingPoint &out)
  {
   for(int i = Swing_Count() - 1; i >= 0; i--)
     {
      SSwingPoint sp;
      if(!Swing_Get(i, sp))
         continue;
      if(sp.time >= bosCloseTime)
         continue;
      if(sp.label == SWING_LH)
        {
         out = sp;
         return(true);
        }
     }
   return(false);
  }

//+------------------------------------------------------------------+
//| Internal: populate fib-anchor fields on a BOS event.             |
//+------------------------------------------------------------------+
void Structure_AttachFibAnchor(SBosEvent &e)
  {
   e.fibAnchorValid = false;
   e.fibAnchorPrice = 0.0;
   e.fibAnchorTime  = 0;
   e.fibAnchorLabel = SWING_NONE;

   SSwingPoint sp;
   if(e.direction == BOS_BULLISH)
     {
      if(Structure_FindPrecedingHL(e.closeTime, sp))
        {
         e.fibAnchorPrice = sp.price;
         e.fibAnchorTime  = sp.time;
         e.fibAnchorLabel = sp.label;
         e.fibAnchorValid = true;
        }
     }
   else if(e.direction == BOS_BEARISH)
     {
      if(Structure_FindPrecedingLH(e.closeTime, sp))
        {
         e.fibAnchorPrice = sp.price;
         e.fibAnchorTime  = sp.time;
         e.fibAnchorLabel = sp.label;
         e.fibAnchorValid = true;
        }
     }
  }

//+------------------------------------------------------------------+
//| Structure_CheckBOS                                               |
//| Spec A5: A BOS is confirmed ONLY when a candle CLOSES beyond the |
//| most recent confirmed swing high (bullish) or swing low (bear).  |
//|                                                                  |
//| Call this after bar close (shift = 1 is the candle that just     |
//| closed). The `shift` parameter is the candle to evaluate.        |
//|                                                                  |
//| Returns true if a new BOS was detected and stored in g_lastBos.  |
//+------------------------------------------------------------------+
bool Structure_CheckBOS(const int shift, SBosEvent &event)
  {
   event.direction = BOS_NONE;

   if(shift < 0)
      return(false);

   const double closePx  = iClose(_Symbol, APEX_TIMEFRAME, shift);
   const datetime closeT = iTime(_Symbol, APEX_TIMEFRAME, shift);
   if(closePx <= 0.0 || closeT == 0)
      return(false);

   // De-dup: don't re-report the same BOS bar.
   if(g_lastBosValid && g_lastBosBarTime == closeT)
      return(false);

   // Evaluate bullish BOS (close > last confirmed swing high).
   SSwingPoint lastHigh;
   bool haveHigh = Swing_GetLastHigh(lastHigh);
   if(haveHigh && lastHigh.time < closeT)
     {
      if(closePx > lastHigh.price)
        {
         event.direction   = BOS_BULLISH;
         event.brokenLevel = lastHigh.price;
         event.brokenTime  = lastHigh.time;
         event.closePrice  = closePx;
         event.closeTime   = closeT;
         event.closeShift  = shift;
         Structure_AttachFibAnchor(event);

         g_lastBos        = event;
         g_lastBosValid   = true;
         g_lastBosBarTime = closeT;
         return(true);
        }
     }

   // Evaluate bearish BOS (close < last confirmed swing low).
   SSwingPoint lastLow;
   bool haveLow = Swing_GetLastLow(lastLow);
   if(haveLow && lastLow.time < closeT)
     {
      if(closePx < lastLow.price)
        {
         event.direction   = BOS_BEARISH;
         event.brokenLevel = lastLow.price;
         event.brokenTime  = lastLow.time;
         event.closePrice  = closePx;
         event.closeTime   = closeT;
         event.closeShift  = shift;
         Structure_AttachFibAnchor(event);

         g_lastBos        = event;
         g_lastBosValid   = true;
         g_lastBosBarTime = closeT;
         return(true);
        }
     }

   return(false);
  }

//+------------------------------------------------------------------+
//| Structure_IsOpposingBOS                                          |
//| Spec A14: a new BOS in the OPPOSITE direction to the current     |
//| active setup invalidates that setup. Callers can use this to     |
//| short-circuit pending-order cancellation.                        |
//+------------------------------------------------------------------+
bool Structure_IsOpposingBOS(const ENUM_BOS_DIRECTION activeDir,
                             const ENUM_BOS_DIRECTION newDir)
  {
   if(activeDir == BOS_BULLISH && newDir == BOS_BEARISH) return(true);
   if(activeDir == BOS_BEARISH && newDir == BOS_BULLISH) return(true);
   return(false);
  }

//+------------------------------------------------------------------+
//| Structure_OnNewBar                                               |
//| Composite helper: call on each confirmed bar close.              |
//|   1. Re-classify structure after any new swings.                 |
//|   2. Check whether the just-closed bar (shift = 1) formed a BOS. |
//| Returns true if a BOS was detected (event filled).               |
//+------------------------------------------------------------------+
bool Structure_OnNewBar(SBosEvent &event)
  {
   ENUM_STRUCTURE_STATE dummy;
   Structure_Update(dummy);

   // Spec A5: evaluate on the just-closed candle only.
   return(Structure_CheckBOS(1, event));
  }

//+------------------------------------------------------------------+
//| Structure_DescribeLastBos — compact debug string for logs.       |
//+------------------------------------------------------------------+
string Structure_DescribeLastBos()
  {
   if(!g_lastBosValid)
      return("no BOS yet");

   string anchor = g_lastBos.fibAnchorValid
                   ? StringFormat(" | fib0=%s@%.*f",
                                  Swing_LabelToString(g_lastBos.fibAnchorLabel),
                                  g_cfg.digits, g_lastBos.fibAnchorPrice)
                   : " | fib0=NONE";

   return(StringFormat("[%s] broke %.*f (set %s) | close=%.*f @ %s%s",
                       Structure_BosDirectionToString(g_lastBos.direction),
                       g_cfg.digits, g_lastBos.brokenLevel,
                       TimeToString(g_lastBos.brokenTime, TIME_DATE|TIME_MINUTES),
                       g_cfg.digits, g_lastBos.closePrice,
                       TimeToString(g_lastBos.closeTime, TIME_DATE|TIME_MINUTES),
                       anchor));
  }

#endif // __APEX_STRUCTURE_ENGINE_MQH__
//+------------------------------------------------------------------+
