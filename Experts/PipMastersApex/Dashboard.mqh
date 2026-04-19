//+------------------------------------------------------------------+
//| Dashboard.mqh — Pip Masters APEX v2.0                            |
//| Chart overlay panel and on-chart drawings                        |
//+------------------------------------------------------------------+
#pragma once
#include "Config.mqh"
#include "FibEngine.mqh"
#include "OrderManager.mqh"
#include "RiskEngine.mqh"

#define OBJ_PREFIX "PMAPEX_"

class CDashboard
{
private:
   string m_symbol;
   long   m_chartId;

   // Colour scheme
   color  m_colorBull;      // Blue
   color  m_colorBear;      // Red
   color  m_colorInvalid;   // Grey
   color  m_colorProfit;    // Green
   color  m_colorLoss;      // Red (loss zone)
   color  m_colorPanel;     // Panel background

   void DeleteObj(const string name)
   { if(ObjectFind(m_chartId, OBJ_PREFIX + name) >= 0) ObjectDelete(m_chartId, OBJ_PREFIX + name); }

   void CreateLabel(const string name, int x, int y, const string text,
                    color clr, int fontSize = 9)
   {
      string n = OBJ_PREFIX + name;
      if(ObjectFind(m_chartId, n) < 0)
      {
         ObjectCreate(m_chartId, n, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chartId, n, OBJPROP_CORNER,   CORNER_LEFT_UPPER);
         ObjectSetInteger(m_chartId, n, OBJPROP_XDISTANCE, x);
         ObjectSetInteger(m_chartId, n, OBJPROP_YDISTANCE, y);
         ObjectSetInteger(m_chartId, n, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chartId, n, OBJPROP_HIDDEN, true);
      }
      ObjectSetString(m_chartId, n, OBJPROP_TEXT, text);
      ObjectSetInteger(m_chartId, n, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chartId, n, OBJPROP_FONTSIZE, fontSize);
   }

   void CreateHLine(const string name, double price, color clr,
                    ENUM_LINE_STYLE style = STYLE_SOLID, int width = 1)
   {
      string n = OBJ_PREFIX + name;
      if(ObjectFind(m_chartId, n) < 0)
         ObjectCreate(m_chartId, n, OBJ_HLINE, 0, 0, price);
      ObjectSetDouble(m_chartId, n, OBJPROP_PRICE, price);
      ObjectSetInteger(m_chartId, n, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chartId, n, OBJPROP_STYLE, style);
      ObjectSetInteger(m_chartId, n, OBJPROP_WIDTH, width);
      ObjectSetInteger(m_chartId, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chartId, n, OBJPROP_HIDDEN, true);
   }

   void CreateRectangle(const string name, datetime t1, double p1, datetime t2, double p2,
                        color clr, bool fill = true)
   {
      string n = OBJ_PREFIX + name;
      if(ObjectFind(m_chartId, n) < 0)
         ObjectCreate(m_chartId, n, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
      ObjectSetInteger(m_chartId, n, OBJPROP_COLOR,   clr);
      ObjectSetInteger(m_chartId, n, OBJPROP_FILL,    fill);
      ObjectSetInteger(m_chartId, n, OBJPROP_BACK,    true);
      ObjectSetInteger(m_chartId, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(m_chartId, n, OBJPROP_HIDDEN, true);
   }

   string StateStr(RobotState s)
   {
      switch(s)
      {
         case STATE_SCANNING:      return "SCANNING";
         case STATE_SETUP_FORMING: return "SETUP FORMING";
         case STATE_ORDERS_PLACED: return "ORDERS PLACED";
         case STATE_TRADE_ACTIVE:  return "TRADE ACTIVE";
         case STATE_LOCKED:        return "LOCKED";
         case STATE_PAUSED:        return "PAUSED";
         default:                  return "UNKNOWN";
      }
   }

public:
   CDashboard()
      : m_colorBull(clrDodgerBlue), m_colorBear(clrRed),
        m_colorInvalid(clrGray), m_colorProfit(clrLimeGreen),
        m_colorLoss(clrOrangeRed), m_colorPanel(clrBlack) {}

   void Init(const string symbol, long chartId)
   {
      m_symbol  = symbol;
      m_chartId = chartId;
   }

   void Deinit()
   {
      // Remove all objects with our prefix
      int total = ObjectsTotal(m_chartId);
      for(int i = total - 1; i >= 0; i--)
      {
         string name = ObjectName(m_chartId, i);
         if(StringFind(name, OBJ_PREFIX) == 0)
            ObjectDelete(m_chartId, name);
      }
      ChartRedraw(m_chartId);
   }

   void RenderPanel(RobotState state, double dailyPnL, int openTrades)
   {
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      double dailyPct = (balance > 0) ? dailyPnL / balance * 100.0 : 0;

      color stateColor = (state == STATE_LOCKED)   ? m_colorBear  :
                         (state == STATE_TRADE_ACTIVE) ? m_colorProfit :
                         (state == STATE_PAUSED)   ? m_colorInvalid : clrWhite;

      int x = 10, y = 15, dy = 15;
      CreateLabel("panel_title",  x, y,       "== PIP MASTERS APEX v2.0 ==", clrGold, 10); y += dy + 3;
      CreateLabel("panel_status", x, y,       "Status: " + StateStr(state),   stateColor);  y += dy;
      CreateLabel("panel_bal",    x, y,       StringFormat("Balance: $%.2f", balance), clrWhite); y += dy;
      CreateLabel("panel_eq",     x, y,       StringFormat("Equity:  $%.2f", equity),  clrWhite); y += dy;
      color pnlColor = (dailyPnL >= 0) ? m_colorProfit : m_colorLoss;
      CreateLabel("panel_pnl",    x, y,       StringFormat("Daily P&L: $%.2f (%.2f%%)", dailyPnL, dailyPct), pnlColor); y += dy;
      CreateLabel("panel_trades", x, y,       StringFormat("Open Trades: %d", openTrades), clrWhite);
   }

   void RenderFibLevels(const FibLevels &fib, BOSDirection dir, FibSetupState fibState)
   {
      bool isInvalid = (fibState == FIB_INVALID || fibState == FIB_IDLE);
      color baseColor = isInvalid ? m_colorInvalid : (dir == BOS_BULLISH ? m_colorBull : m_colorBear);
      color entryColor = isInvalid ? m_colorInvalid : clrGold;

      CreateHLine("fib_sl",   fib.sl,     clrDarkRed,       STYLE_DOT, 1);
      CreateHLine("fib_base", fib.base,   baseColor,        STYLE_SOLID, 2);
      CreateHLine("fib_t2",   fib.t2,     entryColor,       STYLE_DASH, 1);
      CreateHLine("fib_t1",   fib.t1,     entryColor,       STYLE_DASH, 1);
      CreateHLine("fib_50",   fib.mid50,  clrSilver,        STYLE_DOT, 1);
      CreateHLine("fib_618",  fib.mid618, clrSilver,        STYLE_DOT, 1);
      CreateHLine("fib_tp",   fib.tp,     m_colorProfit,    STYLE_SOLID, 2);

      // Entry zone shading — extend from current time 50 bars forward
      if(!isInvalid && fib.t1 > 0 && fib.t2 > 0)
      {
         datetime t1 = iTime(m_symbol, PERIOD_M15, 20);
         datetime t2 = iTime(m_symbol, PERIOD_M15, 0) + 50 * 15 * 60;
         double   zoneTop = MathMax(fib.t1, fib.t2);
         double   zoneBtm = MathMin(fib.t1, fib.t2);
         CreateRectangle("entry_zone", t1, zoneBtm, t2, zoneTop,
                         isInvalid ? m_colorInvalid : clrGold);
      }
   }

   void RenderTrade(TradeSlot slot, const TradeInfo &t)
   {
      if(t.state != TS_TRIGGERED) return;
      string tag = (slot == SLOT_T1) ? "t1" : "t2";

      CreateHLine("sl_" + tag, t.slPrice, clrOrangeRed, STYLE_SOLID, 2);
      CreateHLine("tp_" + tag, t.tpPrice, m_colorProfit, STYLE_SOLID, 2);
   }

   void RemoveFibDrawings()
   {
      string fibNames[] = {"fib_sl","fib_base","fib_t2","fib_t1","fib_50","fib_618","fib_tp","entry_zone"};
      for(int i = 0; i < ArraySize(fibNames); i++) DeleteObj(fibNames[i]);
   }

   void RemoveTradeDrawings(TradeSlot slot)
   {
      string tag = (slot == SLOT_T1) ? "t1" : "t2";
      DeleteObj("sl_" + tag);
      DeleteObj("tp_" + tag);
   }

   void Render(RobotState state, const CFibEngine &fib, COrderManager &orders,
               double dailyPnL)
   {
      RenderPanel(state, dailyPnL, orders.ActiveTradeCount());

      if(fib.IsActive())
         RenderFibLevels(fib.Levels(), fib.Direction(), fib.State());

      for(int i = 0; i < 2; i++)
         RenderTrade((TradeSlot)i, orders.GetTrade((TradeSlot)i));

      ChartRedraw(m_chartId);
   }
};
