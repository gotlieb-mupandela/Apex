//+------------------------------------------------------------------+
//| OrderManager.mqh — Pip Masters APEX v2.0                         |
//| Limit order placement, lifecycle tracking, fill detection,       |
//| invalidation cancellation                                        |
//+------------------------------------------------------------------+
#pragma once
#include "Config.mqh"
#include "RiskEngine.mqh"

enum TradeSlot  { SLOT_T1 = 0, SLOT_T2 = 1 };
enum TradeState { TS_EMPTY, TS_PENDING, TS_TRIGGERED, TS_CLOSED, TS_CANCELLED };

struct TradeInfo
{
   TradeState  state;
   TradeSlot   slot;
   ulong       ticket;        // MT5 order/position ticket
   double      entryPrice;    // Limit order price
   double      slPrice;       // Current SL price
   double      slInitial;     // Original SL price (for R calculation)
   double      tpPrice;
   double      lots;
   double      initialRisk;   // In price units (|entry - slInitial|)
   datetime    placedTime;
   datetime    fillTime;
   double      fillPrice;
   double      slippage;      // pips slippage on fill
   BOSDirection dir;
};

class COrderManager
{
private:
   TradeInfo   m_trades[2];   // Slots 0=T1, 1=T2
   string      m_symbol;
   CRiskEngine *m_risk;
   InstrumentConfig m_cfg;

   int m_maxRetries;
   int m_retryDelayMs;

   bool PlaceLimitOrder(TradeSlot slot, ENUM_ORDER_TYPE orderType,
                        double entryPrice, double sl, double tp,
                        double lots, BOSDirection dir)
   {
      MqlTradeRequest req = {};
      MqlTradeResult  res = {};

      req.action       = TRADE_ACTION_PENDING;
      req.symbol       = m_symbol;
      req.volume       = lots;
      req.price        = NormalizeDouble(entryPrice, m_cfg.digits);
      req.sl           = NormalizeDouble(sl, m_cfg.digits);
      req.tp           = NormalizeDouble(tp, m_cfg.digits);
      req.type         = orderType;
      req.type_filling = ORDER_FILLING_RETURN;
      req.comment      = (slot == SLOT_T1) ? "PMAPEX_T1" : "PMAPEX_T2";

      for(int attempt = 0; attempt < m_maxRetries; attempt++)
      {
         if(OrderSend(req, res))
         {
            m_trades[slot].state       = TS_PENDING;
            m_trades[slot].slot        = slot;
            m_trades[slot].ticket      = res.order;
            m_trades[slot].entryPrice  = entryPrice;
            m_trades[slot].slPrice     = sl;
            m_trades[slot].slInitial   = sl;
            m_trades[slot].tpPrice     = tp;
            m_trades[slot].lots        = lots;
            m_trades[slot].initialRisk = MathAbs(entryPrice - sl);
            m_trades[slot].placedTime  = TimeCurrent();
            m_trades[slot].dir         = dir;
            return true;
         }
         if(attempt < m_maxRetries - 1) Sleep(m_retryDelayMs);
      }
      return false; // All retries failed — never fall back to market
   }

   bool CancelOrder(ulong ticket)
   {
      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action = TRADE_ACTION_REMOVE;
      req.order  = ticket;
      return OrderSend(req, res);
   }

   void CheckFills()
   {
      for(int i = 0; i < 2; i++)
      {
         if(m_trades[i].state != TS_PENDING) continue;

         // Check if pending order is now gone (filled into position)
         if(!OrderSelect(m_trades[i].ticket))
         {
            // Order no longer exists as pending — check if it became a position
            for(int p = PositionsTotal() - 1; p >= 0; p--)
            {
               ulong posTicket = PositionGetTicket(p);
               if(PositionSelectByTicket(posTicket))
               {
                  string comment = PositionGetString(POSITION_COMMENT);
                  string expected = (m_trades[i].slot == SLOT_T1) ? "PMAPEX_T1" : "PMAPEX_T2";
                  if(comment == expected && PositionGetString(POSITION_SYMBOL) == m_symbol)
                  {
                     m_trades[i].state      = TS_TRIGGERED;
                     m_trades[i].ticket     = posTicket;
                     m_trades[i].fillTime   = TimeCurrent();
                     m_trades[i].fillPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
                     m_trades[i].slippage   = MathAbs(m_trades[i].fillPrice - m_trades[i].entryPrice)
                                              / SymbolInfoDouble(m_symbol, SYMBOL_POINT) / 10.0;
                     break;
                  }
               }
            }
         }
      }
   }

   void CheckExternalCloses()
   {
      for(int i = 0; i < 2; i++)
      {
         if(m_trades[i].state != TS_TRIGGERED) continue;
         if(!PositionSelectByTicket(m_trades[i].ticket))
            m_trades[i].state = TS_CLOSED; // Closed externally
      }
   }

public:
   COrderManager() : m_maxRetries(3), m_retryDelayMs(1000) {}

   void Init(const string symbol, CRiskEngine *risk, const InstrumentConfig &cfg)
   {
      m_symbol = symbol;
      m_risk   = risk;
      m_cfg    = cfg;
      for(int i = 0; i < 2; i++) m_trades[i].state = TS_EMPTY;
   }

   // Place both T1 and T2 limit orders
   // Returns a bitmask: bit0 = T1 placed, bit1 = T2 placed
   int PlaceOrders(const FibLevels &fib, BOSDirection dir)
   {
      if(ActiveTradeCount() >= MAX_CONCURRENT_TRADES) return 0;

      int placed = 0;
      ENUM_ORDER_TYPE ot = (dir == BOS_BULLISH) ? ORDER_TYPE_BUY_LIMIT : ORDER_TYPE_SELL_LIMIT;

      double lotsT1 = m_risk.CalcLotSize(m_symbol, fib.t1, fib.sl, m_cfg);
      double lotsT2 = m_risk.CalcLotSize(m_symbol, fib.t2, fib.sl, m_cfg);

      if(PlaceLimitOrder(SLOT_T1, ot, fib.t1, fib.sl, fib.tp, lotsT1, dir))
      {
         m_risk.CommitRisk(RISK_PER_TRADE_PCT);
         placed |= 1;
      }
      if(PlaceLimitOrder(SLOT_T2, ot, fib.t2, fib.sl, fib.tp, lotsT2, dir))
      {
         m_risk.CommitRisk(RISK_PER_TRADE_PCT);
         placed |= 2;
      }
      return placed;
   }

   // Cancel all pending orders (on invalidation)
   void CancelAllPending()
   {
      for(int i = 0; i < 2; i++)
      {
         if(m_trades[i].state == TS_PENDING)
         {
            CancelOrder(m_trades[i].ticket);
            m_trades[i].state = TS_CANCELLED;
         }
      }
   }

   // Update SL of an active trade
   bool ModifySL(TradeSlot slot, double newSL)
   {
      if(m_trades[slot].state != TS_TRIGGERED) return false;
      if(!PositionSelectByTicket(m_trades[slot].ticket)) return false;

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action   = TRADE_ACTION_SLTP;
      req.position = m_trades[slot].ticket;
      req.symbol   = m_symbol;
      req.sl       = NormalizeDouble(newSL, m_cfg.digits);
      req.tp       = NormalizeDouble(m_trades[slot].tpPrice, m_cfg.digits);

      if(OrderSend(req, res))
      {
         m_trades[slot].slPrice = newSL;
         return true;
      }
      return false;
   }

   // Close a trade at market
   bool CloseAtMarket(TradeSlot slot)
   {
      if(m_trades[slot].state != TS_TRIGGERED) return false;
      if(!PositionSelectByTicket(m_trades[slot].ticket)) return false;

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action   = TRADE_ACTION_DEAL;
      req.position = m_trades[slot].ticket;
      req.symbol   = m_symbol;
      req.volume   = m_trades[slot].lots;
      req.type     = (m_trades[slot].dir == BOS_BULLISH) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.type_filling = ORDER_FILLING_FOK;

      if(OrderSend(req, res))
      {
         m_trades[slot].state = TS_CLOSED;
         return true;
      }
      return false;
   }

   // Partial close
   bool ClosePartial(TradeSlot slot, double pct)
   {
      if(m_trades[slot].state != TS_TRIGGERED) return false;
      if(!PositionSelectByTicket(m_trades[slot].ticket)) return false;

      double partialLots = NormalizeDouble(m_trades[slot].lots * pct / 100.0, 2);
      if(partialLots < m_cfg.minLot) partialLots = m_cfg.minLot;

      MqlTradeRequest req = {};
      MqlTradeResult  res = {};
      req.action   = TRADE_ACTION_DEAL;
      req.position = m_trades[slot].ticket;
      req.symbol   = m_symbol;
      req.volume   = partialLots;
      req.type     = (m_trades[slot].dir == BOS_BULLISH) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
      req.type_filling = ORDER_FILLING_FOK;

      if(OrderSend(req, res))
      {
         m_trades[slot].lots -= partialLots;
         return true;
      }
      return false;
   }

   // Call every tick
   void Update()
   {
      CheckFills();
      CheckExternalCloses();
   }

   bool AllSettled()
   {
      for(int i = 0; i < 2; i++)
         if(m_trades[i].state == TS_PENDING || m_trades[i].state == TS_TRIGGERED)
            return false;
      return true;
   }

   int ActiveTradeCount()
   {
      int count = 0;
      for(int i = 0; i < 2; i++)
         if(m_trades[i].state == TS_TRIGGERED) count++;
      return count;
   }

   bool AnyPendingOrActive()
   {
      for(int i = 0; i < 2; i++)
         if(m_trades[i].state == TS_PENDING || m_trades[i].state == TS_TRIGGERED)
            return true;
      return false;
   }

   void Reset()
   {
      CancelAllPending();
      for(int i = 0; i < 2; i++) m_trades[i].state = TS_EMPTY;
   }

   TradeInfo& GetTrade(TradeSlot slot) { return m_trades[slot]; }
};
