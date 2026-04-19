//+------------------------------------------------------------------+
//| Logger.mqh — Pip Masters APEX v2.0                               |
//| Structured event log and daily summary                           |
//+------------------------------------------------------------------+
#pragma once
#include "Config.mqh"

class CLogger
{
private:
   int      m_fileHandle;
   string   m_basePath;
   string   m_currentDate;

   // Daily counters
   int      m_tradesOpened;
   int      m_tradesClosed;
   int      m_tradesSL;
   int      m_tradesTP;
   int      m_tradesTrail;
   int      m_setupsScanned;
   int      m_setupsTaken;
   int      m_filterRejections;
   double   m_dailyPnL;

   string DateStr()
   {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      return StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);
   }

   string TimeStr()
   {
      MqlDateTime dt;
      TimeToStruct(TimeGMT(), dt);
      return StringFormat("%04d-%02d-%02d %02d:%02d:%02d UTC",
                          dt.year, dt.mon, dt.day, dt.hour, dt.min, dt.sec);
   }

   void OpenFile()
   {
      if(m_fileHandle != INVALID_HANDLE) FileClose(m_fileHandle);
      string fname = m_basePath + "_" + m_currentDate + ".log";
      m_fileHandle = FileOpen(fname, FILE_WRITE | FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
      if(m_fileHandle != INVALID_HANDLE)
         FileSeek(m_fileHandle, 0, SEEK_END); // Append
   }

   void WriteLine(const string line)
   {
      if(m_fileHandle == INVALID_HANDLE) return;
      FileWriteString(m_fileHandle, line + "\n");
   }

   void CheckDateRollover()
   {
      string today = DateStr();
      if(today != m_currentDate)
      {
         WriteDailySummary();
         ResetDailyCounters();
         m_currentDate = today;
         OpenFile();
      }
   }

   void ResetDailyCounters()
   {
      m_tradesOpened    = 0; m_tradesClosed   = 0;
      m_tradesSL        = 0; m_tradesTP       = 0;
      m_tradesTrail     = 0; m_setupsScanned  = 0;
      m_setupsTaken     = 0; m_filterRejections = 0;
      m_dailyPnL        = 0;
   }

public:
   CLogger() : m_fileHandle(INVALID_HANDLE) { ResetDailyCounters(); }

   void Init(const string basePath)
   {
      m_basePath    = basePath;
      m_currentDate = DateStr();
      OpenFile();
      Log("SYSTEM", "PipMasters APEX v2.0 started | Symbol: " + _Symbol);
   }

   void Deinit()
   {
      Log("SYSTEM", "PipMasters APEX v2.0 stopping");
      if(m_fileHandle != INVALID_HANDLE)
      {
         FileClose(m_fileHandle);
         m_fileHandle = INVALID_HANDLE;
      }
   }

   void Log(const string eventType, const string details)
   {
      CheckDateRollover();
      WriteLine(TimeStr() + " | " + eventType + " | " + details);
   }

   // Convenience typed log calls
   void BOSDetected(BOSDirection dir, double price)
   {
      m_setupsScanned++;
      Log("BOS_DETECTED", StringFormat("Direction=%s Price=%.5f",
          dir == BOS_BULLISH ? "BULLISH" : "BEARISH", price));
   }

   void PostBOSExtreme(double price) { Log("POST_BOS_EXTREME", StringFormat("Price=%.5f", price)); }

   void FibApplied(double base, double t2, double t1, double tp, double sl)
   {
      Log("FIB_APPLIED", StringFormat("Base=%.5f T2=%.5f T1=%.5f TP=%.5f SL=%.5f",
          base, t2, t1, tp, sl));
   }

   void FilterFail(const string reason)
   {
      m_filterRejections++;
      Log("FILTER_FAIL", "Reason=" + reason);
   }

   void OrderPlaced(const string slot, double price, double lots)
   {
      m_setupsTaken++;
      Log("ORDER_PLACED", StringFormat("Slot=%s Price=%.5f Lots=%.2f", slot, price, lots));
   }

   void OrderFilled(const string slot, double fillPrice, double slippage)
   {
      m_tradesOpened++;
      Log("ORDER_FILLED", StringFormat("Slot=%s FillPrice=%.5f Slippage=%.1f pips",
          slot, fillPrice, slippage));
   }

   void OrderCancelled(const string slot, const string reason)
   { Log("ORDER_CANCELLED", "Slot=" + slot + " Reason=" + reason); }

   void SLMoved(const string slot, double oldSL, double newSL, const string trigger)
   {
      Log("SL_MOVED", StringFormat("Slot=%s OldSL=%.5f NewSL=%.5f Trigger=%s",
          slot, oldSL, newSL, trigger));
   }

   void TPHit(const string slot, double pnl) { m_tradesClosed++; m_tradesTP++; m_dailyPnL += pnl;
      Log("TP_HIT", StringFormat("Slot=%s PnL=%.2f", slot, pnl)); }

   void SLHit(const string slot, double pnl) { m_tradesClosed++; m_tradesSL++; m_dailyPnL += pnl;
      Log("SL_HIT", StringFormat("Slot=%s PnL=%.2f", slot, pnl)); }

   void TrailClose(const string slot, double pnl) { m_tradesClosed++; m_tradesTrail++; m_dailyPnL += pnl;
      Log("TRAIL_CLOSE", StringFormat("Slot=%s PnL=%.2f", slot, pnl)); }

   void Invalidation(const string reason)  { Log("INVALIDATION", "Reason=" + reason); }
   void DailyRiskLimit()                   { Log("DAILY_RISK_LIMIT", "Daily cap reached — no new trades"); }
   void DrawdownAlert(double pct)          { Log("DRAWDOWN_ALERT", StringFormat("Drawdown=%.2f%%", pct)); }
   void SpreadReject(double spreadPips)    { Log("SPREAD_REJECT", StringFormat("Spread=%.1f pips", spreadPips)); }
   void SessionBlock()                     { Log("SESSION_BLOCK", "Outside trading session"); }
   void NewsPause()                        { Log("NEWS_PAUSE", "News window active"); }
   void Error(const string msg)            { Log("ERROR", msg); }

   void WriteDailySummary()
   {
      string date = m_currentDate;
      double bal  = AccountInfoDouble(ACCOUNT_BALANCE);
      double pct  = (bal > 0) ? m_dailyPnL / bal * 100.0 : 0;
      Log("DAILY_SUMMARY", StringFormat(
          "Date=%s TradesOpened=%d TradesClosed=%d TP=%d SL=%d Trail=%d "
          "SetupsScanned=%d SetupsTaken=%d FilterRejections=%d PnL=%.2f PnL%%=%.2f",
          date, m_tradesOpened, m_tradesClosed, m_tradesTP, m_tradesSL, m_tradesTrail,
          m_setupsScanned, m_setupsTaken, m_filterRejections, m_dailyPnL, pct));
   }

   void Flush()
   {
      if(m_fileHandle != INVALID_HANDLE) FileFlush(m_fileHandle);
   }
};
