//+------------------------------------------------------------------+
//|                                               SimpleScalper.mq5  |
//|                        USDJPY専用 MAクロス スキャルピングEA       |
//+------------------------------------------------------------------+
#property copyright "SimpleScalper"
#property version   "1.01"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

//--- 入力パラメータ
input string   InpSymbol       = "USDJPY";    // 取引通貨ペア（変更不可）
input int      InpMagicNumber  = 20240001;    // マジックナンバー
input double   InpLotSize      = 0.01;        // ロット数
input int      InpMaxPositions = 3;           // 最大同時ポジション数
input int      InpTakeProfit   = 200;         // テイクプロフィット（ポイント）
input int      InpStopLoss     = 100;         // ストップロス（ポイント）
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
input bool     VerboseLog = true;             // 詳細ログを出力する

//--- グローバル変数
CTrade  Trade;
int     g_shortMaHandle = INVALID_HANDLE;
int     g_longMaHandle  = INVALID_HANDLE;

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
//| 取引時間帯チェック                                                |
//+------------------------------------------------------------------+
bool IsTradeTime()
{
    int hour;
    if (UseJST)
    {
        hour = GetCurrentJSTHour();
    }
    else
    {
        MqlDateTime dt;
        TimeToStruct(TimeCurrent(), dt);
        hour = dt.hour;
    }

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
void ClosePositionsByType(ENUM_POSITION_TYPE posType)
{
    for (int i = PositionsTotal() - 1; i >= 0; i--)
    {
        ulong ticket = PositionGetTicket(i);
        if (ticket == 0) continue;
        if (PositionGetString(POSITION_SYMBOL) == InpSymbol &&
            PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
            (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE) == posType)
        {
            Trade.PositionClose(ticket);
        }
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
    if (InpLotSize <= 0 || InpTakeProfit <= 0 || InpStopLoss <= 0)
    {
        Alert("ロット数・TP・SLは正の値を設定してください。");
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

    // 起動時時刻ログ
    datetime serverNow = TimeCurrent();
    datetime utcNow    = serverNow - ServerUtcOffsetHours * 3600;
    datetime jstNow    = ServerTimeToJST(serverNow);
    Print("SimpleScalper 初期化完了 | Magic:", InpMagicNumber,
          " | Lot:", InpLotSize, " | TP:", InpTakeProfit, " | SL:", InpStopLoss);
    Print("時刻情報 | Server:", TimeToString(serverNow, TIME_DATE|TIME_MINUTES),
          " | UTC:", TimeToString(utcNow, TIME_DATE|TIME_MINUTES),
          " | JST:", TimeToString(jstNow, TIME_DATE|TIME_MINUTES),
          " | UseJST:", (UseJST ? "true" : "false"),
          " | ServerUtcOffset:", ServerUtcOffsetHours, "h");
    Print("取引時間帯判定 | 現在取引可能:", (IsTradeTime() ? "YES" : "NO"));
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    if (g_shortMaHandle != INVALID_HANDLE) IndicatorRelease(g_shortMaHandle);
    if (g_longMaHandle  != INVALID_HANDLE) IndicatorRelease(g_longMaHandle);
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

    // 価格情報取得
    double point  = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
    double ask    = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
    double bid    = SymbolInfoDouble(InpSymbol, SYMBOL_BID);
    int    spread = (point > 0) ? (int)MathRound((ask - bid) / point) : 0;

    // 取引時間帯チェック
    bool inTradeTime = IsTradeTime();

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
              " | 取引時間帯:", (inTradeTime ? "YES" : "NO"));
    }

    if (!inTradeTime)
    {
        if (VerboseLog) Print("エントリー見送り | 理由: 取引時間外");
        return;
    }

    // スプレッドフィルタ
    if (spread > MaxSpreadPoints)
    {
        if (VerboseLog) Print("エントリー見送り | 理由: スプレッド超過 | Spread:", spread, "pts > MaxSpread:", MaxSpreadPoints, "pts");
        return;
    }

    // MAバッファ取得（直近2本分）
    double shortMa[2], longMa[2];
    if (CopyBuffer(g_shortMaHandle, 0, 1, 2, shortMa) < 2)
    {
        Print("短期MAデータの取得に失敗しました。");
        return;
    }
    if (CopyBuffer(g_longMaHandle,  0, 1, 2, longMa)  < 2)
    {
        Print("長期MAデータの取得に失敗しました。");
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

    // 買いシグナル: 売りポジションを逆シグナル決済 → 買いエントリー
    if (buySignal)
    {
        ClosePositionsByType(POSITION_TYPE_SELL);

        if (CountPositions() < InpMaxPositions)
        {
            double sl = ask - InpStopLoss   * point;
            double tp = ask + InpTakeProfit * point;
            if (Trade.Buy(InpLotSize, InpSymbol, ask, sl, tp, "SimpleScalper Buy"))
                Print("エントリー実行 | BUY | Ask:", DoubleToString(ask, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS)),
                      " | SL:", DoubleToString(sl, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS)),
                      " | TP:", DoubleToString(tp, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS)));
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
            double sl = bid + InpStopLoss   * point;
            double tp = bid - InpTakeProfit * point;
            if (Trade.Sell(InpLotSize, InpSymbol, bid, sl, tp, "SimpleScalper Sell"))
                Print("エントリー実行 | SELL | Bid:", DoubleToString(bid, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS)),
                      " | SL:", DoubleToString(sl, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS)),
                      " | TP:", DoubleToString(tp, (int)SymbolInfoInteger(InpSymbol, SYMBOL_DIGITS)));
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
