//+------------------------------------------------------------------+
//| Main.mq5 — Pip Masters APEX v2.0                                 |
//| MetaTrader 5 Expert Advisor Entry Point                          |
//| Structure Sweep Strategy — Full Autonomous Build                 |
//+------------------------------------------------------------------+
#property copyright "Pip Masters APEX v2.0"
#property version   "2.00"
#property strict

#include "Config.mqh"
#include "SwingEngine.mqh"
#include "StructureEngine.mqh"
#include "FibEngine.mqh"
#include "FilterEngine.mqh"
#include "RiskEngine.mqh"
#include "OrderManager.mqh"
#include "TrailManager.mqh"
#include "Logger.mqh"
#include "Dashboard.mqh"

//--- Module instances
CSwingEngine     g_swing;
CStructureEngine g_structure;
CFibEngine       g_fib;
CFilterEngine    g_filter;
CRiskEngine      g_risk;
COrderManager    g_orders;
CTrailManager    g_trail;
CLogger          g_log;
CDashboard       g_dash;

//--- State
RobotState       g_state = STATE_SCANNING;
double           g_dailyPnL = 0;
datetime         g_lastBarTime = 0;
InstrumentConfig g_cfg;

//--- News pause time (set manually if USE_NEWS_PAUSE = true)
datetime g_newsPauseUntil = 0;

//+------------------------------------------------------------------+
//| Utility: parse "HH:MM" string into seconds since midnight        |
//+------------------------------------------------------------------+
int ParseTimeStr(const string t)
{
   int h = (int)StringToInteger(StringSubstr(t, 0, 2));
   int m = (int)StringToInteger(StringSubstr(t, 3, 2));
   return h * 3600 + m * 60;
}

//+------------------------------------------------------------------+
//| Utility: current UTC time in seconds since midnight              |
//+------------------------------------------------------------------+
int CurrentUTCSeconds()
{
   MqlDateTime dt;
   TimeToStruct(TimeGMT(), dt);
   return dt.hour * 3600 + dt.min * 60 + dt.sec;
}

//+------------------------------------------------------------------+
//| Session filter check                                             |
//+------------------------------------------------------------------+
bool IsWithinSession()
{
   if(!USE_SESSION_FILTER) return true;
   int now   = CurrentUTCSeconds();
   int start = ParseTimeStr(SESSION_START_UTC);
   int end   = ParseTimeStr(SESSION_END_UTC);
   return (now >= start && now <= end);
}

//+------------------------------------------------------------------+
//| News pause check                                                 |
//+------------------------------------------------------------------+
bool IsNewsPause()
{
   if(!USE_NEWS_PAUSE) return false;
   return (TimeCurrent() < g_newsPauseUntil);
}

//+------------------------------------------------------------------+
//| Reset after a completed or invalidated setup                     |
//+------------------------------------------------------------------+
void ResetSetup(const string reason)
{
   g_log.Invalidation(reason);
   g_orders.CancelAllPending();
   g_trail.ResetAll();
   g_fib.Reset();
   g_structure.ResetBOS();
   g_dash.RemoveFibDrawings();
   g_state = STATE_SCANNING;
}

//+------------------------------------------------------------------+
//| New-bar detector                                                 |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, PERIOD_M15, 0);
   if(t != g_lastBarTime) { g_lastBarTime = t; return true; }
   return false;
}

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   g_cfg = GetInstrumentConfig(_Symbol);

   g_swing.Init(_Symbol, PERIOD_M15, SWING_LOOKBACK);
   g_structure.Init(&g_swing, _Symbol, PERIOD_M15);
   g_fib.Init(_Symbol, PERIOD_M15);
   g_risk.Init();
   g_orders.Init(_Symbol, &g_risk, g_cfg);
   g_trail.Init(&g_orders, _Symbol);
   g_dash.Init(_Symbol, ChartID());

   if(!g_filter.Init(_Symbol, PERIOD_M15))
   {
      Alert("PMAPEX: Failed to create indicator handles. EA not started.");
      return INIT_FAILED;
   }

   g_log.Init(LOG_BASE_PATH);
   g_log.Log("SYSTEM", StringFormat("Symbol=%s MinLot=%.2f LotStep=%.2f Digits=%d PipValue=%.5f",
             _Symbol, g_cfg.minLot, g_cfg.lotStep, g_cfg.digits, g_cfg.pipValue));

   g_state = STATE_SCANNING;
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| OnDeinit                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_log.WriteDailySummary();
   g_log.Deinit();
   g_filter.Deinit();
   g_dash.Deinit();
}

//+------------------------------------------------------------------+
//| OnTick — Main execution loop (Part F3, steps 1–14)              |
//+------------------------------------------------------------------+
void OnTick()
{
   // STEP 1 — Locked/Paused early exit
   g_risk.Update();
   if(g_risk.IsLocked())
   {
      if(g_state != STATE_LOCKED)
      {
         g_state = STATE_LOCKED;
         g_log.DrawdownAlert(g_risk.DrawdownPct());
      }
      g_orders.Update();
      g_trail.Update();
      g_dash.Render(g_state, g_fib, g_orders, g_dailyPnL);
      g_log.Flush();
      return;
   }

   // STEP 2 — Session filter
   if(!IsWithinSession())
   {
      if(g_state == STATE_SCANNING)
      {
         g_state = STATE_PAUSED;
         g_log.SessionBlock();
      }
      g_orders.Update();
      g_trail.Update();
      g_dash.Render(g_state, g_fib, g_orders, g_dailyPnL);
      g_log.Flush();
      return;
   }
   else if(g_state == STATE_PAUSED)
      g_state = STATE_SCANNING;

   // STEP 3 — News pause
   if(IsNewsPause())
   {
      if(g_state == STATE_SCANNING) g_log.NewsPause();
      g_orders.Update();
      g_trail.Update();
      g_dash.Render(g_state, g_fib, g_orders, g_dailyPnL);
      g_log.Flush();
      return;
   }

   bool newBar = IsNewBar();

   // STEP 4 — Spread check (only blocks placing new orders, handled below)

   // STEP 5 — Update swing points (only on new bar — candle-close based)
   if(newBar) g_swing.Update();

   // STEP 6 — Update structure classification
   // STEP 7 — Check for new BOS
   if(newBar && g_state == STATE_SCANNING)
   {
      bool bosDetected = g_structure.Update();
      if(bosDetected)
      {
         BOSDirection bosDir  = g_structure.LastBOS();
         double       bosBase = g_structure.PreBOSStructuralBase();

         if(bosBase > 0)
         {
            g_log.BOSDetected(bosDir, g_structure.BOSPrice());
            g_fib.OnBOS(bosDir, bosBase);
            g_state = STATE_SETUP_FORMING;
         }
      }
   }

   // STEP 8 — Update Fibonacci engine (ticks, watching for post-BOS extreme & retrace)
   if(g_state == STATE_SETUP_FORMING || g_state == STATE_ORDERS_PLACED)
   {
      g_fib.Update();

      if(g_fib.State() == FIB_INVALID)
      {
         ResetSetup("FIB_ZERO_LEVEL_BREACH");
         goto manage_trades;
      }

      // Opposite BOS invalidation
      if(newBar && g_structure.OppositeBoSFormed(g_fib.Direction()))
      {
         ResetSetup("OPPOSITE_BOS");
         goto manage_trades;
      }
   }

   // STEP 9 — Indicator filters
   // STEP 10 — Place orders when all conditions met
   if(g_state == STATE_SETUP_FORMING && g_fib.State() == FIB_ENTRY_ZONE && newBar)
   {
      // Check entry signal on closed candle
      if(g_fib.EntrySignalOnClose())
      {
         // Run all filters
         FilterCheckResult fres = g_filter.Check(g_fib.Direction());

         if(fres.result == FILTER_FAIL)
         {
            g_log.FilterFail(g_filter.FailReasonStr(fres.reason));
         }
         else
         {
            // Spread check
            long spreadPts = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
            double spreadPips = spreadPts * SymbolInfoDouble(_Symbol, SYMBOL_POINT)
                                / ((g_cfg.digits == 3 || g_cfg.digits == 5) ? 0.0001 : 0.01);
            if(spreadPips > MAX_SPREAD_PIPS)
            {
               g_log.SpreadReject(spreadPips);
            }
            else if(!g_risk.CanOpenNewTrade())
            {
               g_log.DailyRiskLimit();
            }
            else if(!g_orders.AnyPendingOrActive())
            {
               FibLevels lvl = g_fib.Levels();
               int placed = g_orders.PlaceOrders(lvl, g_fib.Direction());

               if(placed & 1)
               {
                  g_log.OrderPlaced("T1", lvl.t1, g_orders.GetTrade(SLOT_T1).lots);
                  g_dash.RenderFibLevels(lvl, g_fib.Direction(), g_fib.State());
               }
               if(placed & 2)
                  g_log.OrderPlaced("T2", lvl.t2, g_orders.GetTrade(SLOT_T2).lots);

               if(placed) g_state = STATE_ORDERS_PLACED;
            }
         }
      }
   }

manage_trades:
   // STEP 11 — Manage all active trades (trailing stop R milestones)
   g_orders.Update();

   // Log newly filled orders
   for(int i = 0; i < 2; i++)
   {
      TradeInfo &t = g_orders.GetTrade((TradeSlot)i);
      if(t.state == TS_TRIGGERED && t.fillTime > 0)
      {
         string slot = (i == 0) ? "T1" : "T2";
         // Log fill once (fillTime set on transition)
         static datetime lastFillLogged[2] = {0, 0};
         if(t.fillTime != lastFillLogged[i])
         {
            g_log.OrderFilled(slot, t.fillPrice, t.slippage);

            // Excessive slippage — close immediately
            if(t.slippage > MAX_SLIPPAGE_PIPS)
            {
               g_log.Error(StringFormat("%s: Slippage %.1f pips exceeds max — closing", slot, t.slippage));
               g_orders.CloseAtMarket((TradeSlot)i);
            }
            lastFillLogged[i] = t.fillTime;
            if(g_state == STATE_ORDERS_PLACED) g_state = STATE_TRADE_ACTIVE;
         }
      }
   }

   g_trail.Update();

   // Detect if all trades are settled — reset for next setup
   if((g_state == STATE_ORDERS_PLACED || g_state == STATE_TRADE_ACTIVE)
       && g_orders.AllSettled())
   {
      g_dash.RemoveFibDrawings();
      g_fib.Reset();
      g_structure.ResetBOS();
      g_trail.ResetAll();
      g_state = STATE_SCANNING;
   }

   // STEP 12 — Invalidation check (already handled above via fib.State())

   // STEP 13 — Render dashboard
   g_dash.Render(g_state, g_fib, g_orders, g_dailyPnL);

   // STEP 14 — Flush log
   g_log.Flush();
}
