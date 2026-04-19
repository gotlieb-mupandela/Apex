//+------------------------------------------------------------------+
//| RiskEngine.mqh — Pip Masters APEX v2.0                           |
//| Position sizing, daily risk tracking, drawdown protection        |
//+------------------------------------------------------------------+
#pragma once
#include "Config.mqh"

class CRiskEngine
{
private:
   double   m_equityHighWatermark;
   double   m_dailyRiskCommitted;   // cumulative risk % committed today
   datetime m_dailyResetTime;       // midnight UTC of current trading day
   bool     m_locked;

   double GetDayStartMidnight()
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      return (double)StructToTime(dt);
   }

   void CheckDailyReset()
   {
      datetime midnight = (datetime)GetDayStartMidnight();
      if(midnight > m_dailyResetTime)
      {
         m_dailyRiskCommitted = 0;
         m_dailyResetTime     = midnight;
      }
   }

public:
   CRiskEngine() : m_equityHighWatermark(0), m_dailyRiskCommitted(0),
                   m_dailyResetTime(0), m_locked(false) {}

   void Init()
   {
      m_equityHighWatermark = AccountInfoDouble(ACCOUNT_EQUITY);
      m_dailyResetTime      = (datetime)GetDayStartMidnight();
      m_dailyRiskCommitted  = 0;
      m_locked              = false;
   }

   // Called each tick to update drawdown state
   void Update()
   {
      CheckDailyReset();

      double equity   = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity > m_equityHighWatermark)
         m_equityHighWatermark = equity;

      double ddPct = (m_equityHighWatermark - equity) / m_equityHighWatermark * 100.0;
      if(ddPct >= MAX_DRAWDOWN_PCT)
         m_locked = true;
   }

   // Unlock — called manually or at start of new week
   void Unlock() { m_locked = false; }

   bool IsLocked() const { return m_locked; }

   // Returns true if opening a new pair of T1+T2 trades (2 × RISK_PER_TRADE_PCT) is allowed
   bool CanOpenNewTrade()
   {
      if(m_locked) return false;
      double wouldAdd = RISK_PER_TRADE_PCT * 2.0;
      return (m_dailyRiskCommitted + wouldAdd <= MAX_DAILY_RISK_PCT);
   }

   // Register that a trade pair has been committed (call when limit orders are placed)
   void CommitRisk(double riskPctPerTrade)
   {
      m_dailyRiskCommitted += riskPctPerTrade;
   }

   // Position sizing: return lot size for a trade
   // entryPrice and slPrice are in price (not pips)
   double CalcLotSize(const string symbol, double entryPrice, double slPrice,
                      const InstrumentConfig &cfg)
   {
      double balance     = AccountInfoDouble(ACCOUNT_BALANCE);
      double riskAmount  = balance * (RISK_PER_TRADE_PCT / 100.0);
      double slDistance  = MathAbs(entryPrice - slPrice);
      if(slDistance <= 0) return cfg.minLot;

      double lots = riskAmount / (slDistance * cfg.pipValue /
                    SymbolInfoDouble(symbol, SYMBOL_POINT) *
                    SymbolInfoDouble(symbol, SYMBOL_POINT));

      // Simpler precise formula using tick value
      double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double tickVal  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double slTicks  = slDistance / tickSize;
      double riskPerLot = slTicks * tickVal;
      if(riskPerLot <= 0) return cfg.minLot;
      lots = riskAmount / riskPerLot;

      // Round down to lot step
      lots = MathFloor(lots / cfg.lotStep) * cfg.lotStep;

      // Clamp to broker minimum
      if(lots < cfg.minLot) lots = cfg.minLot;

      return NormalizeDouble(lots, 2);
   }

   double DailyRiskCommitted() const { return m_dailyRiskCommitted; }
   double EquityHighWatermark() const { return m_equityHighWatermark; }

   double DrawdownPct()
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_equityHighWatermark <= 0) return 0;
      return (m_equityHighWatermark - equity) / m_equityHighWatermark * 100.0;
   }
};
