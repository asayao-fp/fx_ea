//+------------------------------------------------------------------+
//|                                               SimpleScalper.mq5  |
//|                        マルチ通貨対応 MAクロス スキャルピングEA   |
//+------------------------------------------------------------------+
#property copyright "SimpleScalper"
#property version   "1.04"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include "Logger.mqh"
#include "Strategies.mqh"

//--- ロットモード列挙型
enum ENUM_LOT_MODE
{
    LOT_FIXED        = 0, // 固定ロット
    LOT_RISK_PERCENT = 1  // リスク%ベース
};

//--- 入力パラメータ
input string   InpSymbol       = "";           // 取引通貨ペア（空欄=チャートのシンボル, 明示指定も可）
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

//--- スプレッドスパイク後クールダウン
input bool     EnableSpreadCooldown           = true; // スプレッドスパイク後クールダウンを有効にする
input int      SpreadSpikeThresholdPoints     = 60;   // スプレッドスパイク判定閾値（ポイント）
input int      SpreadCooldownMinutes          = 30;   // スパイク後の新規エントリー抑制時間（分）

//--- 上位足（H1）トレンド方向フィルタ
input bool            EnableHigherTimeframeFilter = false;      // 上位足トレンドフィルタを有効にする
input ENUM_TIMEFRAMES HigherTimeframe             = PERIOD_H1;  // 上位足タイムフレーム
input int             HigherFastMAPeriod          = 20;         // 上位足 短期MA期間
input int             HigherSlowMAPeriod          = 50;         // 上位足 長期MA期間

//--- ブレイクアウト戦略
input bool  EnableBreakoutStrategy   = true; // ブレイクアウト戦略を有効にする
input int   BreakoutLookbackBars     = 20;   // ブレイクアウト判定の参照バー数（確定足）
input int   BreakoutBufferPoints     = 2;    // ブレイクアウトバッファ（ポイント）
input bool  BreakoutConfirmByClose   = true; // 終値確定版を使用する（true=精度優先, false=Ask/Bid）

//--- 取引回数制限（安全弁）
input int   DailyMaxTrades           = 10;  // 1日の最大取引回数（0=無制限, JSTベース）
input int   MinMinutesBetweenEntries = 5;   // エントリー間隔の最小時間（分, 0=無制限）

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
string  g_symbol        = "";    // 稼働シンボル（InpSymbol 空欄時は _Symbol を使用）

// スプレッドクールダウン
datetime g_cooldownUntil   = 0;

// 上位足MAハンドル
int      g_htfFastMaHandle = INVALID_HANDLE;
int      g_htfSlowMaHandle = INVALID_HANDLE;

// 取引回数管理（JSTベース日次カウント）
int      g_dailyTradeCount = 0;          // 本日の取引回数
datetime g_lastEntryTime   = 0;          // 最後のエントリー時刻
string   g_lastTradeDate   = "";         // 最後にカウントリセットした日付（JST）

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
//| 現在のJST日付を "YYYY-MM-DD" 形式の文字列で返す                  |
//| 取引回数の日次リセット判定に使用する                              |
//+------------------------------------------------------------------+
string GetJSTDateString()
{
    MqlDateTime dt;
    TimeToStruct(ServerTimeToJST(TimeCurrent()), dt);
    return StringFormat("%04d-%02d-%02d", dt.year, dt.mon, dt.day);
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
        if (PositionGetString(POSITION_SYMBOL) == g_symbol &&
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
        if (PositionGetString(POSITION_SYMBOL) == g_symbol &&
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
    double tickVal  = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_VALUE);
    double tickSize = SymbolInfoDouble(g_symbol, SYMBOL_TRADE_TICK_SIZE);
    double point    = SymbolInfoDouble(g_symbol, SYMBOL_POINT);

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
    double volStep = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_STEP);
    double volMin  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MIN);
    double volMax  = SymbolInfoDouble(g_symbol, SYMBOL_VOLUME_MAX);

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

    double point = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket == 0) continue;
        if (PositionGetString(POSITION_SYMBOL) != g_symbol) continue;
        if (PositionGetInteger(POSITION_MAGIC) != InpMagicNumber) continue;

        // ポジション方向を先に取得（Close後は参照不可）
        ENUM_POSITION_TYPE posTypeForLog = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

        datetime openTime    = (datetime)PositionGetInteger(POSITION_TIME);
        int      barsElapsed = iBarShift(g_symbol, PERIOD_CURRENT, openTime, false);
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
//| Deal理由を可読文字列に変換する                                    |
//+------------------------------------------------------------------+
string DealReasonToString(ENUM_DEAL_REASON reason)
{
    switch (reason)
    {
        case DEAL_REASON_CLIENT:   return "MANUAL";
        case DEAL_REASON_MOBILE:   return "MANUAL";
        case DEAL_REASON_WEB:      return "MANUAL";
        case DEAL_REASON_EXPERT:   return "EA_CLOSE";
        case DEAL_REASON_SL:       return "STOP_LOSS";
        case DEAL_REASON_TP:       return "TAKE_PROFIT";
        case DEAL_REASON_SO:       return "STOP_OUT";
        case DEAL_REASON_ROLLOVER: return "ROLLOVER";
        case DEAL_REASON_VMARGIN:  return "VMARGIN";
        case DEAL_REASON_SPLIT:    return "SPLIT";
        default:                   return EnumToString(reason);
    }
}

//+------------------------------------------------------------------+
//| Expert initialization                                             |
//+------------------------------------------------------------------+
int OnInit()
{
    // 稼働シンボルを確定（InpSymbol が空欄ならチャートのシンボルを使用）
    g_symbol = (InpSymbol == "") ? _Symbol : InpSymbol;

    // 稼働シンボルがチャートと一致しているか確認（警告のみ、強制停止しない）
    if (g_symbol != _Symbol)
        Print("SimpleScalper: チャートシンボル(", _Symbol, ")と稼働シンボル(", g_symbol,
              ")が異なります。意図的な設定であればこのメッセージは無視してください。");

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
    g_shortMaHandle = iMA(g_symbol, PERIOD_CURRENT, InpShortMaPeriod, 0, InpMaMethod, PRICE_CLOSE);
    g_longMaHandle  = iMA(g_symbol, PERIOD_CURRENT, InpLongMaPeriod,  0, InpMaMethod, PRICE_CLOSE);

    if (g_shortMaHandle == INVALID_HANDLE || g_longMaHandle == INVALID_HANDLE)
    {
        Alert("MAインジケータの初期化に失敗しました。");
        return INIT_FAILED;
    }

    // 上位足MAインジケータ初期化
    if (EnableHigherTimeframeFilter)
    {
        if (HigherFastMAPeriod >= HigherSlowMAPeriod)
        {
            Alert("上位足フィルタ: HigherFastMAPeriodはHigherSlowMAPeriodより小さくしてください。"
                  " FastMA=", HigherFastMAPeriod, " SlowMA=", HigherSlowMAPeriod);
            return INIT_FAILED;
        }
        g_htfFastMaHandle = iMA(g_symbol, HigherTimeframe, HigherFastMAPeriod, 0, InpMaMethod, PRICE_CLOSE);
        g_htfSlowMaHandle = iMA(g_symbol, HigherTimeframe, HigherSlowMAPeriod, 0, InpMaMethod, PRICE_CLOSE);
        if (g_htfFastMaHandle == INVALID_HANDLE || g_htfSlowMaHandle == INVALID_HANDLE)
        {
            Alert("上位足MAインジケータの初期化に失敗しました。");
            return INIT_FAILED;
        }
    }

    Trade.SetExpertMagicNumber(InpMagicNumber);
    Trade.SetDeviationInPoints(10);

    // ロガー初期化
    g_logger.Init(EnableCsvLogging, EnablePrintLogging, LogLevel,
                  LogFileName, g_symbol, PERIOD_CURRENT,
                  InpShortMaPeriod, InpLongMaPeriod);

    // 起動時時刻ログ
    datetime serverNow = TimeCurrent();
    datetime utcNow    = serverNow - ServerUtcOffsetHours * 3600;
    datetime jstNow    = ServerTimeToJST(serverNow);
    string lotInfo = (InpLotMode == LOT_FIXED)
                     ? ("FixedLot:" + DoubleToString(InpLotSize, 2))
                     : ("RiskPercent:" + DoubleToString(InpRiskPercent, 2) + "%");
    Print("SimpleScalper 初期化完了 | Symbol:", g_symbol,
          " | Magic:", InpMagicNumber,
          " | LotMode:", (InpLotMode == LOT_FIXED ? "Fixed" : "RiskPercent"),
          " | ", lotInfo,
          " | TP:", InpTakeProfit, " | SL:", InpStopLoss,
          " | MaxBarsInTrade:", InpMaxBarsInTrade,
          " | SpreadCooldown:", (EnableSpreadCooldown ? "ON" : "OFF"),
          " | HTFFilter:", (EnableHigherTimeframeFilter ? "ON" : "OFF"),
          " | Breakout:", (EnableBreakoutStrategy ? "ON" : "OFF"),
          " | BreakoutConfirmByClose:", (BreakoutConfirmByClose ? "ON" : "OFF"),
          " | DailyMaxTrades:", DailyMaxTrades,
          " | MinMinutesBetweenEntries:", MinMinutesBetweenEntries);
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
    if (g_htfFastMaHandle != INVALID_HANDLE) IndicatorRelease(g_htfFastMaHandle);
    if (g_htfSlowMaHandle != INVALID_HANDLE) IndicatorRelease(g_htfSlowMaHandle);
    g_logger.Deinit();
}

//+------------------------------------------------------------------+
//| Expert tick function                                              |
//+------------------------------------------------------------------+
void OnTick()
{
    // 新しいバーの開始時のみ処理
    static datetime lastBarTime = 0;
    datetime currentBarTime = iTime(g_symbol, PERIOD_CURRENT, 0);
    if (currentBarTime == lastBarTime) return;
    lastBarTime = currentBarTime;

    // 日次トレードカウントのリセット（JST日付変更時）
    string todayJST = GetJSTDateString();
    if (todayJST != g_lastTradeDate)
    {
        if (g_lastTradeDate != "")
            Print("日次トレードカウントリセット | 前日:", g_lastTradeDate,
                  " 取引回数:", g_dailyTradeCount, "回");
        g_dailyTradeCount = 0;
        g_lastTradeDate   = todayJST;
    }

    // 時間切れ決済チェック
    CheckTimeExit();

    // 価格情報取得
    double point  = SymbolInfoDouble(g_symbol, SYMBOL_POINT);
    double ask    = SymbolInfoDouble(g_symbol, SYMBOL_ASK);
    double bid    = SymbolInfoDouble(g_symbol, SYMBOL_BID);
    int    spread = (point > 0) ? (int)MathRound((ask - bid) / point) : 0;

    // 取引時間帯チェック（GetSessionState()も含めて1回だけ評価）
    bool   inTradeTime  = IsTradeTime();
    string sessionState = GetSessionState();

    // スプレッドスパイク検知（取引時間外でも実施）
    if (EnableSpreadCooldown && spread >= SpreadSpikeThresholdPoints)
    {
        datetime newCooldown = TimeCurrent() + SpreadCooldownMinutes * 60;
        if (newCooldown > g_cooldownUntil)
            g_cooldownUntil = newCooldown;
        if (VerboseLog)
            Print("スプレッドスパイク検知 | Spread:", spread, "pts >= 閾値:", SpreadSpikeThresholdPoints,
                  "pts | クールダウン終了:", TimeToString(g_cooldownUntil, TIME_DATE|TIME_MINUTES));
    }

    // VerboseLog: 基本情報出力
    if (VerboseLog)
    {
        datetime serverNow = TimeCurrent();
        datetime jstNow    = ServerTimeToJST(serverNow);
        Print("=== 新バー判定 | JST:", TimeToString(jstNow, TIME_DATE|TIME_MINUTES),
              " | ", g_symbol,
              " | Bid:", DoubleToString(bid, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS)),
              " | Ask:", DoubleToString(ask, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS)),
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

    // スプレッドクールダウンチェック
    if (EnableSpreadCooldown && TimeCurrent() < g_cooldownUntil)
    {
        int remainMinutes = (int)((g_cooldownUntil - TimeCurrent() + 59) / 60); // 切り上げ
        if (VerboseLog)
            Print("エントリー見送り | 理由: スプレッドクールダウン中 | 残り約:", remainMinutes,
                  "分 | クールダウン終了:", TimeToString(g_cooldownUntil, TIME_DATE|TIME_MINUTES));

        SLogEntry e;
        e.event_type    = "SKIP_COOLDOWN";
        e.reason        = "SPREAD_COOLDOWN";
        e.price_bid     = bid;
        e.price_ask     = ask;
        e.spread_points = spread;
        e.cooldown_until = g_cooldownUntil;
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

    // --- 戦略評価 ---

    // MAクロス戦略評価
    SStrategySignal maSig = EvaluateMACross(g_shortMaHandle, g_longMaHandle);
    if (maSig.error)
    {
        Print("短期/長期MAデータの取得に失敗しました。");
        SLogEntry e;
        e.event_type    = "ERROR";
        e.reason        = maSig.reason;
        e.last_error    = GetLastError();
        e.session_state = sessionState;
        g_logger.LogEvent(LOG_LEVEL_ERRORS, e);
        return;
    }
    bool maBuy  = (maSig.signal == "BUY");
    bool maSell = (maSig.signal == "SELL");

    // VerboseLog: MAクロス情報
    if (VerboseLog)
    {
        string crossDir = "なし";
        if (maBuy)  crossDir = "ゴールデンクロス(買い)";
        if (maSell) crossDir = "デッドクロス(売り)";
        Print("MA情報 | FastMA(前):", DoubleToString(maSig.shortMaPrev, 5),
              " FastMA(現):", DoubleToString(maSig.shortMaCurr, 5),
              " | SlowMA(前):", DoubleToString(maSig.longMaPrev, 5),
              " SlowMA(現):", DoubleToString(maSig.longMaCurr, 5),
              " | クロス:", crossDir);
    }

    // MAクロス SIGNALイベント（詳細レベル）
    if (maBuy || maSell)
    {
        SLogEntry e;
        e.event_type    = "SIGNAL";
        e.side          = maBuy ? "BUY" : "SELL";
        e.reason        = maSig.reason;
        e.fast_ma_value = maSig.shortMaCurr;
        e.slow_ma_value = maSig.longMaCurr;
        e.price_bid     = bid;
        e.price_ask     = ask;
        e.spread_points = spread;
        e.session_state = sessionState;
        g_logger.LogEvent(LOG_LEVEL_VERBOSE, e);
    }

    // ブレイクアウト戦略評価
    bool boBuy  = false;
    bool boSell = false;
    SStrategySignal boSig;
    if (EnableBreakoutStrategy)
    {
        boSig = EvaluateBreakout(g_symbol, BreakoutLookbackBars, BreakoutBufferPoints,
                                  BreakoutConfirmByClose);
        if (boSig.error)
        {
            if (VerboseLog)
                Print("ブレイクアウト価格データ取得失敗 | reason:", boSig.reason);
            SLogEntry e;
            e.event_type    = "ERROR";
            e.reason        = boSig.reason;
            e.last_error    = GetLastError();
            e.session_state = sessionState;
            g_logger.LogEvent(LOG_LEVEL_ERRORS, e);
            // エラー時はブレイクアウトシグナルを NONE として扱い継続
        }
        else
        {
            boBuy  = (boSig.signal == "BUY");
            boSell = (boSig.signal == "SELL");

            // ブレイクアウト SIGNALイベント + 詳細ログ（LogLevel=2 のみ）
            if (boBuy || boSell)
            {
                if (LogLevel >= LOG_LEVEL_VERBOSE)
                    Print("ブレイクアウト情報 | Lookback:", BreakoutLookbackBars,
                          " | HighestHigh:", DoubleToString(boSig.boHighestHigh, 5),
                          " | LowestLow:", DoubleToString(boSig.boLowestLow, 5),
                          " | Buffer:", DoubleToString(BreakoutBufferPoints * point, 5),
                          " | Ask:", DoubleToString(ask, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS)),
                          " | Bid:", DoubleToString(bid, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS)),
                          " | ConfirmByClose:", (BreakoutConfirmByClose ? "YES" : "NO"),
                          " | Signal:", boSig.signal);

                SLogEntry e;
                e.event_type    = "SIGNAL";
                e.side          = boBuy ? "BUY" : "SELL";
                e.reason        = boSig.reason;
                e.price_bid     = bid;
                e.price_ask     = ask;
                e.spread_points = spread;
                e.session_state = sessionState;
                g_logger.LogEvent(LOG_LEVEL_VERBOSE, e);
            }
        }
    }

    // --- 上位足トレンドフィルタ（共通ゲート：方向フィルタ） ---
    double htfFastMaVal = 0.0, htfSlowMaVal = 0.0;
    string htfTrend     = "";
    bool   anyBuy       = maBuy  || boBuy;
    bool   anySell      = maSell || boSell;

    if (EnableHigherTimeframeFilter && (anyBuy || anySell))
    {
        double htfFastBuf[1], htfSlowBuf[1];
        bool htfOk = (CopyBuffer(g_htfFastMaHandle, 0, 1, 1, htfFastBuf) >= 1) &&
                     (CopyBuffer(g_htfSlowMaHandle,  0, 1, 1, htfSlowBuf) >= 1);
        if (!htfOk)
        {
            Print("上位足MAデータの取得に失敗しました。");
            SLogEntry e;
            e.event_type    = "ERROR";
            e.reason        = "MA_BUFFER_COPY_FAIL";
            e.last_error    = GetLastError();
            e.session_state = sessionState;
            g_logger.LogEvent(LOG_LEVEL_ERRORS, e);
            maBuy = maSell = boBuy = boSell = false;
        }
        else
        {
            htfFastMaVal = htfFastBuf[0];
            htfSlowMaVal = htfSlowBuf[0];
            htfTrend = (htfFastMaVal > htfSlowMaVal) ? "UP"
                     : (htfFastMaVal < htfSlowMaVal) ? "DOWN" : "FLAT";

            if (VerboseLog)
                Print("HTFフィルタ | TF:", EnumToString(HigherTimeframe),
                      " | FastMA:", DoubleToString(htfFastMaVal, 5),
                      " | SlowMA:", DoubleToString(htfSlowMaVal, 5),
                      " | Trend:", htfTrend);

            // BUYシグナルが上位足方向と不一致（DOWN or FLAT）→ ブロック
            if (anyBuy && htfFastMaVal <= htfSlowMaVal)
            {
                string blockedReason = "";
                if (maBuy) blockedReason += (blockedReason == "" ? "" : "+") + maSig.reason;
                if (boBuy) blockedReason += (blockedReason == "" ? "" : "+") + boSig.reason;
                if (VerboseLog)
                    Print("エントリー見送り | 理由: 上位足トレンド不一致 | シグナル:BUY | HTF:", htfTrend,
                          " | ブロック対象:", blockedReason);

                SLogEntry e;
                e.event_type        = "SKIP_SYMBOL";
                e.side              = "BUY";
                e.reason            = "HTF_FILTER_BLOCKED";
                e.fast_ma_value     = maSig.shortMaCurr;
                e.slow_ma_value     = maSig.longMaCurr;
                e.htf_fast_ma_value = htfFastMaVal;
                e.htf_slow_ma_value = htfSlowMaVal;
                e.htf_trend         = htfTrend;
                e.price_bid         = bid;
                e.price_ask         = ask;
                e.spread_points     = spread;
                e.session_state     = sessionState;
                g_logger.LogEvent(LOG_LEVEL_TRADES, e);
                maBuy = false;
                boBuy = false;
            }

            // SELLシグナルが上位足方向と不一致（UP or FLAT）→ ブロック
            if (anySell && htfFastMaVal >= htfSlowMaVal)
            {
                string blockedReason = "";
                if (maSell) blockedReason += (blockedReason == "" ? "" : "+") + maSig.reason;
                if (boSell) blockedReason += (blockedReason == "" ? "" : "+") + boSig.reason;
                if (VerboseLog)
                    Print("エントリー見送り | 理由: 上位足トレンド不一致 | シグナル:SELL | HTF:", htfTrend,
                          " | ブロック対象:", blockedReason);

                SLogEntry e;
                e.event_type        = "SKIP_SYMBOL";
                e.side              = "SELL";
                e.reason            = "HTF_FILTER_BLOCKED";
                e.fast_ma_value     = maSig.shortMaCurr;
                e.slow_ma_value     = maSig.longMaCurr;
                e.htf_fast_ma_value = htfFastMaVal;
                e.htf_slow_ma_value = htfSlowMaVal;
                e.htf_trend         = htfTrend;
                e.price_bid         = bid;
                e.price_ask         = ask;
                e.spread_points     = spread;
                e.session_state     = sessionState;
                g_logger.LogEvent(LOG_LEVEL_TRADES, e);
                maSell = false;
                boSell = false;
            }
        }
    }

    // --- OR集約 ---
    bool finalBuy  = maBuy  || boBuy;
    bool finalSell = maSell || boSell;

    // 戦略ごとのreason文字列を構築
    string buyReasonStr  = "";
    string sellReasonStr = "";
    if (maBuy)  buyReasonStr  += (buyReasonStr  == "" ? "" : "+") + maSig.reason;
    if (boBuy)  buyReasonStr  += (buyReasonStr  == "" ? "" : "+") + boSig.reason;
    if (maSell) sellReasonStr += (sellReasonStr == "" ? "" : "+") + maSig.reason;
    if (boSell) sellReasonStr += (sellReasonStr == "" ? "" : "+") + boSig.reason;

    // --- コンフリクトチェック（同一バーでBUYとSELLが同時に出たら見送り） ---
    if (finalBuy && finalSell)
    {
        string detail = "BUY(" + buyReasonStr + ")+SELL(" + sellReasonStr + ")";
        if (VerboseLog)
            Print("エントリー見送り | 理由: シグナルコンフリクト | ", detail);

        SLogEntry e;
        e.event_type    = "SKIP_SYMBOL";
        e.side          = "NONE";
        e.reason        = "SIGNAL_CONFLICT";
        e.fast_ma_value = maSig.shortMaCurr;
        e.slow_ma_value = maSig.longMaCurr;
        e.price_bid     = bid;
        e.price_ask     = ask;
        e.spread_points = spread;
        e.session_state = sessionState;
        g_logger.LogEvent(LOG_LEVEL_TRADES, e);
        return;
    }

    // シグナルなし
    if (!finalBuy && !finalSell)
    {
        if (VerboseLog) Print("エントリー見送り | 理由: シグナルなし");
        return;
    }

    // --- 取引回数制限チェック ---
    string entrySide   = finalBuy ? "BUY" : "SELL";
    string entryReason = finalBuy ? buyReasonStr : sellReasonStr;

    if (DailyMaxTrades > 0 && g_dailyTradeCount >= DailyMaxTrades)
    {
        if (VerboseLog)
            Print("エントリー見送り | 理由: 日次取引上限 | 本日:", g_dailyTradeCount,
                  "回 / 上限:", DailyMaxTrades, "回");

        SLogEntry e;
        e.event_type    = "SKIP_SYMBOL";
        e.side          = entrySide;
        e.reason        = "DAILY_TRADE_LIMIT";
        e.price_bid     = bid;
        e.price_ask     = ask;
        e.spread_points = spread;
        e.session_state = sessionState;
        g_logger.LogEvent(LOG_LEVEL_TRADES, e);
        return;
    }

    if (MinMinutesBetweenEntries > 0 && g_lastEntryTime > 0 &&
        TimeCurrent() < g_lastEntryTime + MinMinutesBetweenEntries * 60)
    {
        int remainMin = (int)((g_lastEntryTime + MinMinutesBetweenEntries * 60 - TimeCurrent() + 59) / 60); // +59 で切り上げ
        if (VerboseLog)
            Print("エントリー見送り | 理由: エントリー間隔未達 | 残り約:", remainMin, "分");

        SLogEntry e;
        e.event_type    = "SKIP_SYMBOL";
        e.side          = entrySide;
        e.reason        = "ENTRY_TOO_SOON";
        e.price_bid     = bid;
        e.price_ask     = ask;
        e.spread_points = spread;
        e.session_state = sessionState;
        g_logger.LogEvent(LOG_LEVEL_TRADES, e);
        return;
    }

    // --- エントリー実行 ---

    // BUYエントリー
    if (finalBuy)
    {
        ClosePositionsByType(POSITION_TYPE_SELL);

        // 保有中は新規禁止（同一シンボル・同一MagicNumberでポジションがあればスキップ）
        if (CountPositions() > 0)
        {
            if (VerboseLog)
                Print("エントリー見送り | 理由: ポジション保有中 | BUY | ポジション数:", CountPositions());

            SLogEntry e;
            e.event_type    = "SKIP_SYMBOL";
            e.side          = "BUY";
            e.reason        = "POSITION_ALREADY_OPEN";
            e.fast_ma_value = maSig.shortMaCurr;
            e.slow_ma_value = maSig.longMaCurr;
            e.price_bid     = bid;
            e.price_ask     = ask;
            e.spread_points = spread;
            e.session_state = sessionState;
            g_logger.LogEvent(LOG_LEVEL_TRADES, e);
        }
        else if (CountPositions() < InpMaxPositions)
        {
            double sl  = ask - InpStopLoss   * point;
            double tp  = ask + InpTakeProfit * point;
            double lot = CalcLot(InpStopLoss);
            double margin = 0;
            if (!OrderCalcMargin(ORDER_TYPE_BUY, g_symbol, lot, ask, margin) ||
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
                e.fast_ma_value = maSig.shortMaCurr;
                e.slow_ma_value = maSig.longMaCurr;
                e.price_bid     = bid;
                e.price_ask     = ask;
                e.spread_points = spread;
                e.lot           = lot;
                e.session_state = sessionState;
                g_logger.LogEvent(LOG_LEVEL_TRADES, e);
            }
            else
            {
                bool ok = Trade.Buy(lot, g_symbol, ask, sl, tp, "SimpleScalper Buy");
                if (ok)
                {
                    g_dailyTradeCount++;
                    g_lastEntryTime = TimeCurrent();
                    Print("エントリー実行 | BUY | Ask:", DoubleToString(ask, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS)),
                          " | SL:", DoubleToString(sl, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS)),
                          " | TP:", DoubleToString(tp, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS)),
                          " | Lot:", DoubleToString(lot, 2),
                          " | Strategy:", entryReason);
                }

                SLogEntry e;
                e.event_type    = ok ? "ENTRY" : "ERROR";
                e.side          = "BUY";
                e.reason        = ok ? entryReason : "ORDER_SEND_FAIL";
                e.fast_ma_value = maSig.shortMaCurr;
                e.slow_ma_value = maSig.longMaCurr;
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

    // SELLエントリー
    if (finalSell)
    {
        ClosePositionsByType(POSITION_TYPE_BUY);

        // 保有中は新規禁止（同一シンボル・同一MagicNumberでポジションがあればスキップ）
        if (CountPositions() > 0)
        {
            if (VerboseLog)
                Print("エントリー見送り | 理由: ポジション保有中 | SELL | ポジション数:", CountPositions());

            SLogEntry e;
            e.event_type    = "SKIP_SYMBOL";
            e.side          = "SELL";
            e.reason        = "POSITION_ALREADY_OPEN";
            e.fast_ma_value = maSig.shortMaCurr;
            e.slow_ma_value = maSig.longMaCurr;
            e.price_bid     = bid;
            e.price_ask     = ask;
            e.spread_points = spread;
            e.session_state = sessionState;
            g_logger.LogEvent(LOG_LEVEL_TRADES, e);
        }
        else if (CountPositions() < InpMaxPositions)
        {
            double sl  = bid + InpStopLoss   * point;
            double tp  = bid - InpTakeProfit * point;
            double lot = CalcLot(InpStopLoss);
            double margin = 0;
            if (!OrderCalcMargin(ORDER_TYPE_SELL, g_symbol, lot, bid, margin) ||
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
                e.fast_ma_value = maSig.shortMaCurr;
                e.slow_ma_value = maSig.longMaCurr;
                e.price_bid     = bid;
                e.price_ask     = ask;
                e.spread_points = spread;
                e.lot           = lot;
                e.session_state = sessionState;
                g_logger.LogEvent(LOG_LEVEL_TRADES, e);
            }
            else
            {
                bool ok = Trade.Sell(lot, g_symbol, bid, sl, tp, "SimpleScalper Sell");
                if (ok)
                {
                    g_dailyTradeCount++;
                    g_lastEntryTime = TimeCurrent();
                    Print("エントリー実行 | SELL | Bid:", DoubleToString(bid, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS)),
                          " | SL:", DoubleToString(sl, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS)),
                          " | TP:", DoubleToString(tp, (int)SymbolInfoInteger(g_symbol, SYMBOL_DIGITS)),
                          " | Lot:", DoubleToString(lot, 2),
                          " | Strategy:", entryReason);
                }

                SLogEntry e;
                e.event_type    = ok ? "ENTRY" : "ERROR";
                e.side          = "SELL";
                e.reason        = ok ? entryReason : "ORDER_SEND_FAIL";
                e.fast_ma_value = maSig.shortMaCurr;
                e.slow_ma_value = maSig.longMaCurr;
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
}

//+------------------------------------------------------------------+
//| Trade transaction handler（TP/SL含む全決済Dealをログ記録）       |
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest&     request,
                        const MqlTradeResult&      result)
{
    // DEAL_ADD トランザクションのみ処理
    if (trans.type != TRADE_TRANSACTION_DEAL_ADD) return;

    // 取引履歴からDeal情報を取得
    if (!HistoryDealSelect(trans.deal)) return;

    // このEAのマジックナンバーと通貨ペアに限定
    if ((long)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber) return;
    if (HistoryDealGetString(trans.deal, DEAL_SYMBOL) != g_symbol) return;

    // クローズ（OUT）または部分決済（INOUT）のみ対象
    ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
    if (dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_INOUT) return;

    // Deal情報取得
    ENUM_DEAL_TYPE   dealType   = (ENUM_DEAL_TYPE)HistoryDealGetInteger(trans.deal, DEAL_TYPE);
    ENUM_DEAL_REASON dealReason = (ENUM_DEAL_REASON)HistoryDealGetInteger(trans.deal, DEAL_REASON);
    double           dealProfit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
    double           dealComm   = HistoryDealGetDouble(trans.deal, DEAL_COMMISSION);
    double           dealSwap   = HistoryDealGetDouble(trans.deal, DEAL_SWAP);
    double           dealPrice  = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
    double           dealVol    = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);
    ulong            posId      = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);

    SLogEntry e;
    e.event_type      = "DEAL_OUT";
    e.side            = (dealType == DEAL_TYPE_BUY) ? "BUY" : "SELL";
    e.reason          = DealReasonToString(dealReason);
    e.deal_reason     = EnumToString(dealReason);
    e.profit          = dealProfit;
    e.commission      = dealComm;
    e.swap            = dealSwap;
    e.deal_price      = dealPrice;
    e.lot             = dealVol;
    e.position_ticket = posId;
    e.deal_ticket     = trans.deal;
    e.session_state   = GetSessionState();
    g_logger.LogEvent(LOG_LEVEL_TRADES, e);
}
//+------------------------------------------------------------------+
