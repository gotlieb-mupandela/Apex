//+------------------------------------------------------------------+
//| TrailManager.mqh — Pip Masters APEX v2.0                         |
//| R-milestone trailing stop logic, independent per trade           |
//+------------------------------------------------------------------+
#pragma once
#include "Config.mqh"
#include "OrderManager.mqh"

// Milestone flags — each fires only once per trade
struct RMilestones
{
   bool at1R; // SL moved to break even
   bool at2R; // SL moved to +1R
   bool at3R; // SL moved to +2R
   bool at4R; // Trade closed
   bool partialDone; // Partial close already executed
};

class CTrailManager
{
private:
   COrderManager *m_orders;
   string         m_symbol;
   RMilestones    m_milestones[2]; // one per slot

   double CurrentPrice(BOSDirection dir)
   {
      return (dir == BOS_BULLISH)
             ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
             : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
   }

   double CalcFloatR(const TradeInfo &t, double price)
   {
      if(t.initialRisk <= 0) return 0;
      if(t.dir == BOS_BULLISH) return (price - t.entryPrice) / t.initialRisk;
      else                     return (t.entryPrice - price) / t.initialRisk;
   }

   // For SELL trades, SL movement is downward (lower = better protection)
   bool SLBetterThan(BOSDirection dir, double newSL, double currentSL)
   {
      if(dir == BOS_BULLISH) return newSL > currentSL;
      else                   return newSL < currentSL;
   }

   void ProcessSlot(TradeSlot slot)
   {
      TradeInfo &t = m_orders.GetTrade(slot);
      if(t.state != TS_TRIGGERED) return;

      double price  = CurrentPrice(t.dir);
      double floatR = CalcFloatR(t, price);
      RMilestones &m = m_milestones[slot];

      // Partial close (optional feature)
      if(USE_PARTIAL_CLOSE && !m.partialDone && floatR >= PARTIAL_CLOSE_AT_R)
      {
         m_orders.ClosePartial(slot, PARTIAL_CLOSE_PCT);
         // Move SL to break even on remainder
         double beSL = t.entryPrice;
         if(SLBetterThan(t.dir, beSL, t.slPrice))
            m_orders.ModifySL(slot, beSL);
         m.partialDone = true;
      }

      // 4R — close trade immediately
      if(!m.at4R && floatR >= 4.0)
      {
         m_orders.CloseAtMarket(slot);
         m.at4R = true;
         return;
      }

      // 3R — move SL to +2R
      if(!m.at3R && floatR >= 3.0)
      {
         double newSL = (t.dir == BOS_BULLISH)
                        ? t.entryPrice + 2.0 * t.initialRisk
                        : t.entryPrice - 2.0 * t.initialRisk;
         if(SLBetterThan(t.dir, newSL, t.slPrice))
            m_orders.ModifySL(slot, newSL);
         m.at3R = true;
      }

      // 2R — move SL to +1R
      if(!m.at2R && floatR >= 2.0)
      {
         double newSL = (t.dir == BOS_BULLISH)
                        ? t.entryPrice + 1.0 * t.initialRisk
                        : t.entryPrice - 1.0 * t.initialRisk;
         if(SLBetterThan(t.dir, newSL, t.slPrice))
            m_orders.ModifySL(slot, newSL);
         m.at2R = true;
      }

      // 1R — move SL to break even
      if(!m.at1R && floatR >= 1.0)
      {
         double newSL = t.entryPrice;
         if(SLBetterThan(t.dir, newSL, t.slPrice))
            m_orders.ModifySL(slot, newSL);
         m.at1R = true;
      }
   }

public:
   CTrailManager() {}

   void Init(COrderManager *orders, const string symbol)
   {
      m_orders = orders;
      m_symbol = symbol;
      ResetAll();
   }

   void ResetAll()
   {
      for(int i = 0; i < 2; i++)
      {
         m_milestones[i].at1R      = false;
         m_milestones[i].at2R      = false;
         m_milestones[i].at3R      = false;
         m_milestones[i].at4R      = false;
         m_milestones[i].partialDone = false;
      }
   }

   void ResetSlot(TradeSlot slot)
   {
      m_milestones[slot].at1R      = false;
      m_milestones[slot].at2R      = false;
      m_milestones[slot].at3R      = false;
      m_milestones[slot].at4R      = false;
      m_milestones[slot].partialDone = false;
   }

   // Call every tick for all active trades
   void Update()
   {
      ProcessSlot(SLOT_T1);
      ProcessSlot(SLOT_T2);
   }

   RMilestones GetMilestones(TradeSlot slot) const { return m_milestones[slot]; }
};
