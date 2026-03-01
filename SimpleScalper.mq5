//+------------------------------------------------------------------+
//|                                               SimpleScalper.mq5  |
//|                        USDJPY専用 MAクロス スキャルピングEA       |
//+------------------------------------------------------------------+
#property copyright "SimpleScalper"
#property version   "1.02"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include "Logger.mqh"

//--- ロットモード列挙型
enum ENUM_LOT_MODE
{
    LOT_FIXED        = 0, // 固定ロット
    LOT_RISK_PERCENT = 1  // リスク%ベース
};

//--- 入力パラメータ
input string   InpSymbol       = "USDJPY";    // 取引通貨ペア（変更不可）
input int      InpMagicNumber  = 20240001;    // マジックナンバー

//--- ロット設定
input ENUM_LOT_MODE InpLotMode    = LOT_FIXED; // ロットモード（Fixed/RiskPercent）
input double   InpLotSize      = 0.01;        // 固定ロット数（LotMode=Fixed時）
input double   InpRiskPercent  = 0.5;         // リスク%（LotMode=RiskPercent時）
input double   InpMinLot       = 0.01;        // 最小ロット（RiskPercent時の下限）
input double   InpMaxLot       = 1.0;         // 最大ロット（RiskPercent時の上限）

input int      InpMaxPositions = 3;           // 最大同時ポジション数
input int      InpTakeProfit   = 200;         // テイクプロフィット（ポイント）
input int      InpStopLoss     = 100;         // ストップロス（ポイント）

//--- 時間切れ決済
input int      InpMaxBarsInTrade          = 8; // 最大保有バー数（0=無効）
input int      InpTimeExitMinProfitPoints = 0;  // 時間切れ決済の最低含み益ポイント（0=無条件決済）

input int      InpShortMaPeriod = 5;          // 短期MA期間
input int      InpLongMaPeriod  = 20;         // 長期MA期間
input ENUM_MA_METHOD InpMaMethod = MODE_EMA;  // MA計算方法

//--- JST時間帯変換パラメータ
input bool     UseJST               = true;   // JST基準で時間帯判定する
input int      ServerUtcOffsetHours = 2;      // サーバ時間のUTCオフセット（時間）
input int      JSTUtcOffsetHours    = 9;      // JSTのUTCオフセット（時間、通常9）

//--- スプレッドフィルタ
input int      MaxSpreadPoints = 30;          // 最大許容スプレッド（ポイント）

//--- ログ
input bool     VerboseLog = true;             // 詳細ログを出力する（既存の詳細ログ）

//--- 分析ログ設定
input bool   EnableCsvLogging        = true;              // CSVログを出力する（MQL5/Files に保存）
input bool   EnablePrintLogging      = true;              // Expertsタブに構造化ログを出力する
input string LogFileName             = "SimpleScalper";   // CSVファイル名プレフィックス
input int    LogLevel                = 1;                 // ログレベル（0=エラーのみ, 1=取引, 2=詳細）
input bool   UseServerTimeForSessions = false;            // セッション判定にサーバ時刻を使用（false=UseJST設定を使用）

//--- グローバル変数
CTrade  Trade;
int     g_shortMaHandle = INVALID_HANDLE;
int     g_longMaHandle  = INVALID_HANDLE;
CLogger g_logger;

//+------------------------------------------------------------------+
//| サーバ時刻をJST時刻に変換してdatetimeを返す                      |
//+------------------------------------------------------------------+
datetime ServerTimeToJST(datetime serverTime)
{
    // サーバ時刻 → UTC → JST
    datetime utcTime = serverTime - ServerUtcOffsetHours * 3600;
    return utcTime + JSTUtcOffsetHours * 3600;
}

//+------------------------------------------------------------------+
//| 現在のJST時刻の「時」を返す                                       |
//+------------------------------------------------------------------+
int GetCurrentJSTHour()
{
    MqlDateTime dt;
    TimeToStruct(ServerTimeToJST(TimeCurrent()), dt);
    return dt.hour;
}

//+------------------------------------------------------------------+
//| セッション判定に使う「時」を返す                                  |
//| UseServerTimeForSessions=true → サーバ時刻                       |
//| false かつ UseJST=true       → JST変換後の時刻                   |
//| false かつ UseJST=false      → サーバ時刻                        |
//+------------------------------------------------------------------+
int GetSessionHour()
{
    if (UseServerTimeForSessions)
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        return dt.hour;
    }
    if (UseJST)
        return GetCurrentJSTHour();
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    return dt.hour;
}

//+------------------------------------------------------------------+
//| セッション状態文字列を返す（ログ用）                              |
//| 例: "IN:08:00-11:00(JST)" / "OUT(server)"                        |
//+------------------------------------------------------------------+
string GetSessionState()
{
    int    hour     = GetSessionHour();
    string timeBase = UseServerTimeForSessions ? "server" : (UseJST ? "JST" : "server");

    if (hour >= 8  && hour < 11) return "IN:08:00-11:00(" + timeBase + ")";
    if (hour >= 16 && hour < 18) return "IN:16:00-18:00(" + timeBase + ")";
    if (hour >= 21)              return "IN:21:00-24:00(" + timeBase + ")";
    return "OUT(" + timeBase + ")";
}

//+------------------------------------------------------------------+
//| 取引時間帯チェック                                                |
//+------------------------------------------------------------------+
bool IsTradeTime()
{
    int hour = GetSessionHour();

    // スキャルピング向け取引時間帯(JST): 8-11, 16-18, 21-24
    if ((hour >= 8  && hour < 11) ||
        (hour >= 16 && hour < 18) ||
        (hour >= 21))
        return true;
    return false;
}

//+------------------------------------------------------------------+
//| 保有ポジション数を取得（マジックナンバーで識別）                  |
//+------------------------------------------------------------------+
int CountPositions()
{
    int count = 0;
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket == 0) continue;
        if (PositionGetString(POSITION_SYMBOL) == InpSymbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            count++;
    }
    return count;
}

//+------------------------------------------------------------------+
//| 指定方向のポジションを全決済（逆シグナル決済）                    |
//+------------------------------------------------------------------+
void ClosePositionsByType(ENUM_POSITION_TYPE posType,
                          const string closeReason = "REVERSE_SIGNAL")
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket == 0) continue;
        if (PositionGetString(POSITION_SYMBOL) == InpSymbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == posType)
        {
            bool ok = Trade.PositionClose(ticket);

            SLogEntry e;
            e.event_type      = "EXIT";
            e.side            = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
            e.reason          = closeReason;
            e.position_ticket = ticket;
            e.retcode         = Trade.ResultRetcode();
            e.deal_ticket     = (ok ? Trade.ResultDeal() : 0);
            e.last_error      = (ok ? 0 : GetLastError());
            e.session_state   = GetSessionState();
            g_logger.LogEvent(LOG_LEVEL_TRADES, e);
        }
    }
}

//+------------------------------------------------------------------+
//| ロット数を計算する（固定またはリスク%ベース）                     |
//+------------------------------------------------------------------+
double CalcLot(double slPoints)
{
    if (InpLotMode == LOT_FIXED)
        return InpLotSize;

    // リスク%ベースのロット計算
    double balance  = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmt  = balance * InpRiskPercent / 100.0;
    double tickVal  = SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(InpSymbol, SYMBOL_TRADE_TICK_SIZE);
    double point    = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);

    if (tickVal <= 0 || tickSize <= 0 || slPoints <= 0)
    {
        if (VerboseLog)
            Print("CalcLot: パラメータ異常 tickVal=", tickVal,
                  " tickSize=", tickSize, " slPoints=", slPoints);
        return InpMinLot;
    }

    // 1ロットあたりのSL損失額 = slPoints * (point/tickSize) * tickVal
    double lossPerLot = slPoints * (point / tickSize) * tickVal;
    double lot        = (lossPerLot > 0) ? riskAmt / lossPerLot : InpMinLot;

    // ブローカーのボリューム制限に合わせて正規化
    double volStep = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_STEP);
    double volMin  = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MIN);
    double volMax  = SymbolInfoDouble(InpSymbol, SYMBOL_VOLUME_MAX);

    if (volStep > 0)
        lot = MathFloor(lot / volStep) * volStep;

    double minLot = MathMax(InpMinLot, volMin);
    double maxLot = MathMin(InpMaxLot, volMax);
    lot = MathMax(lot, minLot);
    lot = MathMin(lot, maxLot);

    if (VerboseLog)
        Print("CalcLot | Balance:", DoubleToString(balance, 2),
              " | Risk%:", InpRiskPercent,
              " | RiskAmt:", DoubleToString(riskAmt, 2),
              " | LossPerLot:", DoubleToString(lossPerLot, 4),
              " | Lot:", DoubleToString(lot, 2));
    return lot;
}

//+------------------------------------------------------------------+
//| 時間切れポジションを決済する（MaxBarsInTrade）                    |
//+------------------------------------------------------------------+
void CheckTimeExit()
{
    if (InpMaxBarsInTrade <= 0) return;

    double point = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket == 0) continue;
        if (PositionGetString(POSITION_SYMBOL) != InpSymbol) continue;
        if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

        // ポジション方向を先に取得（Close後は参照不可）
        ENUM_POSITION_TYPE posTypeForLog = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        datetime openTime    = (datetime)PositionGetInteger(POSITION_TIME);
        int      barsElapsed = iBarShift(InpSymbol, PERIOD_CURRENT, openTime, false);
        if (barsElapsed < 0) continue; // iBarShiftエラー時はスキップ
        if (barsElapsed < InpMaxBarsInTrade) continue;

        // 含み益条件チェック（TimeExitMinProfitPoints > 0 の場合）
        if (InpTimeExitMinProfitPoints > 0)
        {
            double             openPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
            double             currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
            ENUM_POSITION_TYPE posType      = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double profitPoints = (posType == POSITION_TYPE_BUY)
                                  ? (currentPrice - openPrice) / point
                                  : (openPrice - currentPrice) / point;
            if (profitPoints >= InpTimeExitMinProfitPoints)
            {
                if (VerboseLog)
                    Print("時間切れ決済スキップ | Ticket:", ticket,
                          " | 経過バー:", barsElapsed,
                          " | 含み益:", DoubleToString(profitPoints, 1), "pts >= 閾値:", InpTimeExitMinProfitPoints);
                continue;
            }
        }

        if (VerboseLog)
            Print("時間切れ決済 | Ticket:", ticket,
                  " | 経過バー:", barsElapsed,
                  " | 理由: TimeExit");

        bool ok = Trade.PositionClose(ticket);

        SLogEntry e;
        e.event_type      = "EXIT";
        e.side            = (posTypeForLog == POSITION_TYPE_BUY) ? "BUY" : "SELL";
        e.reason          = "TIME_EXIT";
        e.position_ticket = ticket;
        e.retcode         = Trade.ResultRetcode();
        e.deal_ticket     = (ok ? Trade.ResultDeal() : 0);
        e.last_error      = (ok ? 0 : GetLastError());
        e.session_state   = GetSessionState();
        g_logger.LogEvent(LOG_LEVEL_TRADES, e);
    }
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
    // 通貨ペアチェック
    if (Symbol() != InpSymbol)
    {
        Alert("このEAは " + InpSymbol + " 専用です。チャートを " + InpSymbol + " に変更してください。");
        return INIT_FAILED;
    }

    // パラメータ検証
    if (InpShortMaPeriod >= InpLongMaPeriod)
    {
        Alert("短期MA期間は長期MA期間より小さくしてください。");
        return INIT_FAILED;
    }
    if (InpLotMode == LOT_FIXED && InpLotSize <= 0)
    {
        Alert("固定ロットモード: ロット数は正の値を設定してください。");
        return INIT_FAILED;
    }
    if (InpLotMode == LOT_RISK_PERCENT && (InpRiskPercent <= 0 || InpRiskPercent > 100))
    {
        Alert("リスク%モード: RiskPercentは0より大きく100以下に設定してください。");
        return INIT_FAILED;
    }
    if (InpTakeProfit <= 0 || InpStopLoss <= 0)
    {
        Alert("TP・SLは正の値を設定してください。");
        return INIT_FAILED;
    }

    // MAインジケータ初期化
    g_shortMaHandle = iMA(InpSymbol, PERIOD_CURRENT, InpShortMaPeriod, 0, InpMaMethod, PRICE_CLOSE);
    g_longMaHandle  = iMA(InpSymbol, PERIOD_CURRENT, InpLongMaPeriod,  0, InpMaMethod, PRICE_CLOSE);

    if (g_shortMaHandle == INVALID_HANDLE || g_longMaHandle == INVALID_HANDLE)
    {
        Alert("MAインジケータの初期化に失敗しました。");
        return INIT_FAILED;
    }

    Trade.SetExpertMagicNumber(InpMagicNumber);
    Trade.SetDeviationInPoints(10);

    // ロガー初期化
    g_logger.Init(EnableCsvLogging, EnablePrintLogging, LogLevel,
                  LogFileName, InpSymbol, PERIOD_CURRENT,
                  InpShortMaPeriod, InpLongMaPeriod);

    // 起動時時刻ログ
    datetime serverNow = TimeCurrent();
    datetime utcNow    = serverNow - ServerUtcOffsetHours * 3600;
    datetime jstNow    = ServerTimeToJST(serverNow);
    string lotInfo = (InpLotMode == LOT_FIXED)
                     ? ("FixedLot:" + DoubleToString(InpLotSize, 2))
                     : ("RiskPercent:" + DoubleToString(InpRiskPercent, 2) + "%");
    Print("SimpleScalper 初期化完了 | Magic:", InpMagicNumber,
          " | LotMode:", (InpLotMode == LOT_FIXED ? "Fixed" : "RiskPercent"),
          " | ", lotInfo,
          " | TP:", InpTakeProfit, " | SL:", InpStopLoss,
          " | MaxBarsInTrade:", InpMaxBarsInTrade);
    Print("時刻情報 | Server:", TimeToString(serverNow, TIME_DATE|TIME_MINUTES),
          " | UTC:", TimeToString(utcNow, TIME_DATE|TIME_MINUTES),
          " | JST:", TimeToString(jstNow, TIME_DATE|TIME_MINUTES),
          " | UseJST:", (UseJST ? "true" : "false"),
          " | UseServerTimeForSessions:", (UseServerTimeForSessions ? "true" : "false"),
          " | ServerUtcOffset:", ServerUtcOffsetHours, "h");
    Print("取引時間帯判定 | 現在取引可能:", (IsTradeTime() ? "YES" : "NO"),
          " | セッション:", GetSessionState());

    // INIT イベントをログに記録
    SLogEntry initEntry;
    initEntry.event_type  = "INIT";
    initEntry.reason      = "EA_START";
    initEntry.session_state = GetSessionState();
    g_logger.LogEvent(LOG_LEVEL_TRADES, initEntry);

    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    SLogEntry e;
    e.event_type = "DEINIT";
    e.reason     = "reason_code=" + IntegerToString(reason);
    g_logger.LogEvent(LOG_LEVEL_TRADES, e);

    if (g_shortMaHandle != INVALID_HANDLE) IndicatorRelease(g_shortMaHandle);
    if (g_longMaHandle  != INVALID_HANDLE) IndicatorRelease(g_longMaHandle);
    g_logger.Deinit();
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    // 新しいバーの開始時のみ処理
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(InpSymbol, PERIOD_CURRENT, 0);
    if (currentBarTime == lastBarTime) return;
    lastBarTime = currentBarTime;

    // 時間切れ決済チェック
    CheckTimeExit();

    // 価格情報取得
    double point  = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
    double ask    = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
    double bid    = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
    int    spread = (point > 0) ? (int)MathRound((ask - bid) / point) : 0;

    // 取引時間帯チェック（GetSessionState()も含めて1回だけ評価）
    bool   inTradeTime  = IsTradeTime();
    string sessionState = GetSessionState();

    // VerboseLog: 基本情報出力
    if (VerboseLog)
    {
        datetime serverNow = TimeCurrent();
        datetime jstNow    = ServerTimeToJST(serverNow);
        Print("=== 新バー判定 | JST:", TimeToString(jstNow, TIME_DATE|TIME_MINUTES),
              " | ", InpSymbol,
              " | Bid:", DoubleToString(bid, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS)),
              " | Ask:", DoubleToString(ask, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS)),
              " | Spread:", spread, "pts",
              " | 取引時間帯:", (inTradeTime ? "YES" : "NO"),
              " | セッション:", sessionState);
    }

    // NEW_BAR イベント（詳細レベル）
    {
        SLogEntry e;
        e.event_type    = "NEW_BAR";
        e.price_bid     = bid;
        e.price_ask     = ask;
        e.spread_points = spread;
        e.session_state = sessionState;
        g_logger.LogEvent(LOG_LEVEL_VERBOSE, e);
    }

    if (!inTradeTime)
    {
        if (VerboseLog) Print("エントリー見送り | 理由: 取引時間外");

        SLogEntry e;
        e.event_type    = "SKIP_TIME";
        e.reason        = "OUT_OF_SESSION";
        e.price_bid     = bid;
        e.price_ask     = ask;
        e.spread_points = spread;
        e.session_state = sessionState;
        g_logger.LogEvent(LOG_LEVEL_TRADES, e);
        return;
    }

    // スプレッドフィルタ
    if (spread > MaxSpreadPoints)
    {
        if (VerboseLog) Print("エントリー見送り | 理由: スプレッド超過 | Spread:", spread, "pts > MaxSpread:", MaxSpreadPoints, "pts");

        SLogEntry e;
        e.event_type    = "SKIP_SYMBOL";
        e.reason        = "SPREAD_TOO_HIGH";
        e.price_bid     = bid;
        e.price_ask     = ask;
        e.spread_points = spread;
        e.session_state = sessionState;
        g_logger.LogEvent(LOG_LEVEL_TRADES, e);
        return;
    }

    // MAバッファ取得（直近2本分）
    double shortMa[2], longMa[2];
    if (CopyBuffer(g_shortMaHandle, 0, 1, 2, shortMa) < 2)
    {
        Print("短期MAデータの取得に失敗しました。");
        SLogEntry e;
        e.event_type  = "ERROR";
        e.reason      = "MA_BUFFER_COPY_FAIL";
        e.last_error  = GetLastError();
        e.session_state = sessionState;
        g_logger.LogEvent(LOG_LEVEL_ERRORS, e);
        return;
    }
    if (CopyBuffer(g_longMaHandle,  0, 1, 2, longMa)  < 2)
    {
        Print("長期MAデータの取得に失敗しました。");
        SLogEntry e;
        e.event_type  = "ERROR";
        e.reason      = "MA_BUFFER_COPY_FAIL";
        e.last_error  = GetLastError();
        e.session_state = sessionState;
        g_logger.LogEvent(LOG_LEVEL_ERRORS, e);
        return;
    }

    // インデックス: [0]=1本前, [1]=2本前
    double shortMaPrev = shortMa[1];
    double shortMaCurr = shortMa[0];
    double longMaPrev  = longMa[1];
    double longMaCurr  = longMa[0];

    bool buySignal  = (shortMaPrev <= longMaPrev) && (shortMaCurr > longMaCurr);
    bool sellSignal = (shortMaPrev >= longMaPrev) && (shortMaCurr < longMaCurr);

    // VerboseLog: MA値とクロス方向
    if (VerboseLog)
    {
        string crossDir = "なし";
        if (buySignal)  crossDir = "ゴールデンクロス(買い)";
        if (sellSignal) crossDir = "デッドクロス(売り)";
        Print("MA情報 | FastMA(前):", DoubleToString(shortMaPrev, 5),
              " FastMA(現):", DoubleToString(shortMaCurr, 5),
              " | SlowMA(前):", DoubleToString(longMaPrev, 5),
              " SlowMA(現):", DoubleToString(longMaCurr, 5),
              " | クロス:", crossDir);
    }

    // SIGNAL イベント（シグナルあり時のみ、詳細レベル）
    if (buySignal || sellSignal)
    {
        SLogEntry e;
        e.event_type    = "SIGNAL";
        e.side          = buySignal ? "BUY" : "SELL";
        e.reason        = buySignal ? "MA_CROSS_UP" : "MA_CROSS_DOWN";
        e.fast_ma_value = shortMaCurr;
        e.slow_ma_value = longMaCurr;
        e.price_bid     = bid;
        e.price_ask     = ask;
        e.spread_points = spread;
        e.session_state = sessionState;
        g_logger.LogEvent(LOG_LEVEL_VERBOSE, e);
    }

    // 買いシグナル: 売りポジションを逆シグナル決済 → 買いエントリー
    if (buySignal)
    {
        ClosePositionsByType(POSITION_TYPE_SELL);

        if (CountPositions() < InpMaxPositions)
        {
            double sl  = ask - InpStopLoss   * point;
            double tp  = ask + InpTakeProfit * point;
            double lot = CalcLot(InpStopLoss);
            double margin = 0;
            if (!OrderCalcMargin(ORDER_TYPE_BUY, InpSymbol, lot, ask, margin) ||
                AccountInfoDouble(ACCOUNT_FREEMARGIN) < margin)
            {
                if (VerboseLog)
                    Print("エントリー見送り | 理由: 証拠金不足 | Lot:", DoubleToString(lot, 2),
                          " | 必要証拠金:", DoubleToString(margin, 2),
                          " | 余剰証拠金:", DoubleToString(AccountInfoDouble(ACCOUNT_FREEMARGIN), 2));

                SLogEntry e;
                e.event_type    = "SKIP_SYMBOL";
                e.side          = "BUY";
                e.reason        = "INSUFFICIENT_MARGIN";
                e.fast_ma_value = shortMaCurr;
                e.slow_ma_value = longMaCurr;
                e.price_bid     = bid;
                e.price_ask     = ask;
                e.spread_points = spread;
                e.lot           = lot;
                e.session_state = sessionState;
                g_logger.LogEvent(LOG_LEVEL_TRADES, e);
            }
            else
            {
                bool ok = Trade.Buy(lot, InpSymbol, ask, sl, tp, "SimpleScalper Buy");
                if (ok)
                    Print("エントリー実行 | BUY | Ask:", DoubleToString(ask, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS)),
                          " | SL:", DoubleToString(sl, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS)),
                          " | TP:", DoubleToString(tp, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS)),
                          " | Lot:", DoubleToString(lot, 2));

                SLogEntry e;
                e.event_type    = ok ? "ENTRY" : "ERROR";
                e.side          = "BUY";
                e.reason        = ok ? "MA_CROSS_UP" : "ORDER_SEND_FAIL";
                e.fast_ma_value = shortMaCurr;
                e.slow_ma_value = longMaCurr;
                e.price_bid     = bid;
                e.price_ask     = ask;
                e.spread_points = spread;
                e.lot           = lot;
                e.sl_price      = sl;
                e.tp_price      = tp;
                e.order_ticket  = Trade.ResultOrder();
                e.deal_ticket   = Trade.ResultDeal();
                e.retcode       = Trade.ResultRetcode();
                e.last_error    = (ok ? 0 : GetLastError());
                e.session_state = sessionState;
                g_logger.LogEvent(ok ? LOG_LEVEL_TRADES : LOG_LEVEL_ERRORS, e);
            }
        }
        else
        {
            if (VerboseLog) Print("エントリー見送り | 理由: 最大ポジション数上限 | ポジション数:", CountPositions());
        }
    }

    // 売りシグナル: 買いポジションを逆シグナル決済 → 売りエントリー
    if (sellSignal)
    {
        ClosePositionsByType(POSITION_TYPE_BUY);

        if (CountPositions() < InpMaxPositions)
        {
            double sl  = bid + InpStopLoss   * point;
            double tp  = bid - InpTakeProfit * point;
            double lot = CalcLot(InpStopLoss);
            double margin = 0;
            if (!OrderCalcMargin(ORDER_TYPE_SELL, InpSymbol, lot, bid, margin) ||
                AccountInfoDouble(ACCOUNT_FREEMARGIN) < margin)
            {
                if (VerboseLog)
                    Print("エントリー見送り | 理由: 証拠金不足 | Lot:", DoubleToString(lot, 2),
                          " | 必要証拠金:", DoubleToString(margin, 2),
                          " | 余剰証拠金:", DoubleToString(AccountInfoDouble(ACCOUNT_FREEMARGIN), 2));

                SLogEntry e;
                e.event_type    = "SKIP_SYMBOL";
                e.side          = "SELL";
                e.reason        = "INSUFFICIENT_MARGIN";
                e.fast_ma_value = shortMaCurr;
                e.slow_ma_value = longMaCurr;
                e.price_bid     = bid;
                e.price_ask     = ask;
                e.spread_points = spread;
                e.lot           = lot;
                e.session_state = sessionState;
                g_logger.LogEvent(LOG_LEVEL_TRADES, e);
            }
            else
            {
                bool ok = Trade.Sell(lot, InpSymbol, bid, sl, tp, "SimpleScalper Sell");
                if (ok)
                    Print("エントリー実行 | SELL | Bid:", DoubleToString(bid, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS)),
                          " | SL:", DoubleToString(sl, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS)),
                          " | TP:", DoubleToString(tp, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS)),
                          " | Lot:", DoubleToString(lot, 2));

                SLogEntry e;
                e.event_type    = ok ? "ENTRY" : "ERROR";
                e.side          = "SELL";
                e.reason        = ok ? "MA_CROSS_DOWN" : "ORDER_SEND_FAIL";
                e.fast_ma_value = shortMaCurr;
                e.slow_ma_value = longMaCurr;
                e.price_bid     = bid;
                e.price_ask     = ask;
                e.spread_points = spread;
                e.lot           = lot;
                e.sl_price      = sl;
                e.tp_price      = tp;
                e.order_ticket  = Trade.ResultOrder();
                e.deal_ticket   = Trade.ResultDeal();
                e.retcode       = Trade.ResultRetcode();
                e.last_error    = (ok ? 0 : GetLastError());
                e.session_state = sessionState;
                g_logger.LogEvent(ok ? LOG_LEVEL_TRADES : LOG_LEVEL_ERRORS, e);
            }
        }
        else
        {
            if (VerboseLog) Print("エントリー見送り | 理由: 最大ポジション数上限 | ポジション数:", CountPositions());
        }
    }

    if (VerboseLog && !buySignal && !sellSignal)
        Print("エントリー見送り | 理由: MAクロスシグナルなし");
}
//+------------------------------------------------------------------+
