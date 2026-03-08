//+------------------------------------------------------------------+
//|                                                       Logger.mqh  |
//|                   SimpleScalper 分析用ログモジュール              |
//|  使用方法:                                                        |
//|    CLogger g_logger;                                              |
//|    g_logger.Init(csv, print, level, prefix, symbol, tf, fp, sp); |
//|    g_logger.LogEvent(LOG_LEVEL_TRADES, entry);                   |
//|    g_logger.Deinit();                                             |
//+------------------------------------------------------------------+
#property strict

//--- ログレベル定数
#define LOG_LEVEL_ERRORS   0   // エラーのみ
#define LOG_LEVEL_TRADES   1   // 取引イベント（エントリー・決済）
#define LOG_LEVEL_VERBOSE  2   // 全詳細（新バー・シグナル・スキップ含む）

//--- CSV ヘッダ（列順と一致させること）
#define LOGGER_CSV_HEADER \
   "timestamp_server,timestamp_local,symbol,timeframe,event_type,side,reason," \
   "fast_ma_period,slow_ma_period,fast_ma_value,slow_ma_value," \
   "price_bid,price_ask,spread_points,lot,sl_price,tp_price," \
   "order_ticket,position_ticket,deal_ticket,retcode,last_error,session_state," \
   "deal_reason,profit,commission,swap,deal_price"

//+------------------------------------------------------------------+
//| ログエントリ構造体                                                |
//+------------------------------------------------------------------+
struct SLogEntry
{
   string event_type;       // 例: INIT, DEINIT, NEW_BAR, SIGNAL, ENTRY, EXIT, DEAL_OUT, SKIP_TIME, SKIP_SYMBOL, ERROR など
   string side;             // BUY / SELL / NONE
   string reason;           // MA_CROSS_UP, MA_CROSS_DOWN, REVERSE_SIGNAL, TIME_EXIT, TAKE_PROFIT, STOP_LOSS, EA_CLOSE など
   double fast_ma_value;    // 短期MA値（判定に使った値）
   double slow_ma_value;    // 長期MA値（判定に使った値）
   double price_bid;
   double price_ask;
   int    spread_points;
   double lot;
   double sl_price;
   double tp_price;
   ulong  order_ticket;
   ulong  position_ticket;
   ulong  deal_ticket;
   uint   retcode;
   int    last_error;
   string session_state;    // 例: "IN:08:00-11:00(JST)" / "OUT(server)"
   string deal_reason;      // DEAL_REASON_TP / DEAL_REASON_SL / DEAL_REASON_EXPERT など（EnumToString値）
   double profit;           // 確定損益（DEAL_OUT時）
   double commission;       // コミッション（DEAL_OUT時）
   double swap;             // スワップ（DEAL_OUT時）
   double deal_price;       // 約定価格（DEAL_OUT時）

   SLogEntry()
   {
      event_type    = "";
      side          = "NONE";
      reason        = "";
      session_state = "";
      fast_ma_value = 0.0;
      slow_ma_value = 0.0;
      price_bid     = 0.0;
      price_ask     = 0.0;
      spread_points = 0;
      lot           = 0.0;
      sl_price      = 0.0;
      tp_price      = 0.0;
      order_ticket    = 0;
      position_ticket = 0;
      deal_ticket     = 0;
      retcode     = 0;
      last_error  = 0;
      deal_reason = "";
      profit      = 0.0;
      commission  = 0.0;
      swap        = 0.0;
      deal_price  = 0.0;
   }
};

//+------------------------------------------------------------------+
//| ロガークラス                                                      |
//+------------------------------------------------------------------+
class CLogger
{
private:
   int     m_fileHandle;
   bool    m_csvEnabled;
   bool    m_printEnabled;
   int     m_logLevel;
   string  m_symbol;
   string  m_timeframe;
   int     m_fastMaPeriod;
   int     m_slowMaPeriod;

   //--- 日時を CSV 向け文字列に変換
   string FormatDT(datetime t)
   {
      return TimeToString(t, TIME_DATE | TIME_SECONDS);
   }

   //--- double を文字列に変換（0.0 のとき空文字）
   string FormatDbl(double v, int digits = 5)
   {
      if (v == 0.0) return "";
      return DoubleToString(v, digits);
   }

   //--- ulong を文字列に変換（0 のとき空文字）
   string FormatUL(ulong v)
   {
      if (v == 0) return "";
      return IntegerToString((long)v);
   }

   //--- CSV 1行を構築
   string BuildCsvRow(const SLogEntry &e)
   {
      string row = "";
      row += FormatDT(TimeCurrent())                                          + ",";
      row += FormatDT(TimeLocal())                                            + ",";
      row += m_symbol                                                         + ",";
      row += m_timeframe                                                      + ",";
      row += e.event_type                                                     + ",";
      row += e.side                                                           + ",";
      row += e.reason                                                         + ",";
      row += IntegerToString(m_fastMaPeriod)                                  + ",";
      row += IntegerToString(m_slowMaPeriod)                                  + ",";
      row += FormatDbl(e.fast_ma_value)                                       + ",";
      row += FormatDbl(e.slow_ma_value)                                       + ",";
      row += FormatDbl(e.price_bid)                                           + ",";
      row += FormatDbl(e.price_ask)                                           + ",";
      row += (e.spread_points > 0 ? IntegerToString(e.spread_points) : "")   + ",";
      row += FormatDbl(e.lot, 2)                                              + ",";
      row += FormatDbl(e.sl_price)                                            + ",";
      row += FormatDbl(e.tp_price)                                            + ",";
      row += FormatUL(e.order_ticket)                                         + ",";
      row += FormatUL(e.position_ticket)                                      + ",";
      row += FormatUL(e.deal_ticket)                                          + ",";
      row += (e.retcode > 0    ? IntegerToString((long)e.retcode) : "")       + ",";
      row += (e.last_error != 0 ? IntegerToString(e.last_error)   : "")       + ",";
      row += e.session_state                                                   + ",";
      row += e.deal_reason                                                     + ",";
      row += FormatDbl(e.profit,     2)                                        + ",";
      row += FormatDbl(e.commission, 2)                                        + ",";
      row += FormatDbl(e.swap,       2)                                        + ",";
      row += FormatDbl(e.deal_price);
      return row;
   }

   //--- Experts タブ向けの簡潔なメッセージを構築
   string BuildPrintMsg(const SLogEntry &e)
   {
      string msg = "[" + e.event_type + "]";
      if (e.side != "NONE" && e.side != "")
         msg += " " + e.side;
      if (e.reason != "")
         msg += " " + e.reason;
      if (e.fast_ma_value > 0)
         msg += " fastMA=" + DoubleToString(e.fast_ma_value, 5);
      if (e.slow_ma_value > 0)
         msg += " slowMA=" + DoubleToString(e.slow_ma_value, 5);
      if (e.price_bid > 0)
         msg += " bid=" + FormatDbl(e.price_bid);
      if (e.price_ask > 0)
         msg += " ask=" + FormatDbl(e.price_ask);
      if (e.spread_points > 0)
         msg += " spread=" + IntegerToString(e.spread_points) + "pts";
      if (e.lot > 0)
         msg += " lot=" + DoubleToString(e.lot, 2);
      if (e.sl_price > 0)
         msg += " sl=" + FormatDbl(e.sl_price);
      if (e.tp_price > 0)
         msg += " tp=" + FormatDbl(e.tp_price);
      if (e.order_ticket > 0)
         msg += " order=" + IntegerToString((long)e.order_ticket);
      if (e.position_ticket > 0)
         msg += " pos=" + IntegerToString((long)e.position_ticket);
      if (e.retcode > 0)
         msg += " retcode=" + IntegerToString((long)e.retcode);
      if (e.last_error != 0)
         msg += " error=" + IntegerToString(e.last_error);
      if (e.session_state != "")
         msg += " session=" + e.session_state;
      if (e.deal_reason != "")
         msg += " deal_reason=" + e.deal_reason;
      if (e.deal_price > 0)
         msg += " deal_price=" + FormatDbl(e.deal_price);
      if (e.profit != 0.0)
         msg += " profit=" + DoubleToString(e.profit, 2);
      if (e.commission != 0.0)
         msg += " commission=" + DoubleToString(e.commission, 2);
      if (e.swap != 0.0)
         msg += " swap=" + DoubleToString(e.swap, 2);
      return msg;
   }

public:
   //--- コンストラクタ / デストラクタ
   CLogger() : m_fileHandle(INVALID_HANDLE),
               m_csvEnabled(false), m_printEnabled(true),
               m_logLevel(LOG_LEVEL_TRADES),
               m_fastMaPeriod(0), m_slowMaPeriod(0)
   {
      m_symbol = ""; m_timeframe = "";
   }

   ~CLogger() { Deinit(); }

   //--- 初期化（OnInit で呼ぶ）
   //    filePrefix : CSVファイル名のプレフィックス（例: "SimpleScalper"）
   //    ファイル名  : <filePrefix>_YYYYMMDD.csv  → MQL5/Files/ に保存される（日付はJST=TimeLocal()基準）
   bool Init(bool        csvEnabled,
             bool        printEnabled,
             int         logLevel,
             string      filePrefix,
             string      symbol,
             ENUM_TIMEFRAMES tf,
             int         fastPeriod,
             int         slowPeriod)
   {
      m_csvEnabled   = csvEnabled;
      m_printEnabled = printEnabled;
      m_logLevel     = logLevel;
      m_symbol       = symbol;
      m_timeframe    = EnumToString(tf);
      m_fastMaPeriod = fastPeriod;
      m_slowMaPeriod = slowPeriod;
      m_fileHandle   = INVALID_HANDLE;

      if (!m_csvEnabled) return true;

      // ファイル名: prefix_YYYYMMDD.csv（日付はJST=TimeLocal()基準）
      MqlDateTime dt;
      TimeToStruct(TimeLocal(), dt);
      string dateStr  = StringFormat("%04d%02d%02d", dt.year, dt.mon, dt.day);
      string fileName = filePrefix + "_" + dateStr + ".csv";

      // 既存ファイルに追記、なければ新規作成してヘッダを書く
      if (FileIsExist(fileName))
      {
         m_fileHandle = FileOpen(fileName,
            FILE_READ | FILE_WRITE | FILE_ANSI | FILE_SHARE_READ);
         if (m_fileHandle != INVALID_HANDLE)
            FileSeek(m_fileHandle, 0, SEEK_END);
      }
      else
      {
         m_fileHandle = FileOpen(fileName,
            FILE_WRITE | FILE_ANSI | FILE_SHARE_READ);
         if (m_fileHandle != INVALID_HANDLE)
         {
            FileWriteString(m_fileHandle, LOGGER_CSV_HEADER + "\n");
            FileFlush(m_fileHandle);
         }
      }

      if (m_fileHandle == INVALID_HANDLE)
      {
         Print("Logger: CSVファイルオープン失敗 file=", fileName,
               " error=", GetLastError());
         return false;
      }

      Print("Logger: CSVログ開始 file=", fileName);
      return true;
   }

   //--- 終了処理（OnDeinit で呼ぶ）
   void Deinit()
   {
      if (m_fileHandle != INVALID_HANDLE)
      {
         FileFlush(m_fileHandle);
         FileClose(m_fileHandle);
         m_fileHandle = INVALID_HANDLE;
      }
   }

   //--- イベントを記録する
   //    level: LOG_LEVEL_ERRORS(0) / LOG_LEVEL_TRADES(1) / LOG_LEVEL_VERBOSE(2)
   //    level が m_logLevel を超える場合は何もしない
   void LogEvent(int level, const SLogEntry &e)
   {
      if (level > m_logLevel) return;

      if (m_csvEnabled && m_fileHandle != INVALID_HANDLE)
      {
         FileWriteString(m_fileHandle, BuildCsvRow(e) + "\n");
         FileFlush(m_fileHandle);
      }

      if (m_printEnabled)
         Print(BuildPrintMsg(e));
   }
};
