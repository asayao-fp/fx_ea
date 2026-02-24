//+------------------------------------------------------------------+
//|                                               SimpleScalper.mq5  |
//|                        USDJPY専用 MAクロス スキャルピングEA       |
//+------------------------------------------------------------------+
#property copyright "SimpleScalper"
#property version   "1.00"
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

//--- グローバル変数
CTrade  Trade;
int     g_shortMaHandle = INVALID_HANDLE;
int     g_longMaHandle  = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| 取引時間帯チェック                                                |
//+------------------------------------------------------------------+
bool IsTradeTime()
{
    MqlDateTime dt;
    TimeToStruct(TimeCurrent(), dt);
    int hour = dt.hour;

    // スキャルピング向け取引時間帯: 8-11, 16-18, 21-23
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

    Print("SimpleScalper 初期化完了 | Magic:", InpMagicNumber,
          " | Lot:", InpLotSize, " | TP:", InpTakeProfit, " | SL:", InpStopLoss);
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

    // 取引時間帯チェック
    if (!IsTradeTime()) return;

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

    double point = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
    double ask   = SymbolInfoDouble(InpSymbol, SYMBOL_ASK);
    double bid   = SymbolInfoDouble(InpSymbol, SYMBOL_BID);

    // 買いシグナル: 売りポジションを逆シグナル決済 → 買いエントリー
    if (buySignal)
    {
        ClosePositionsByType(POSITION_TYPE_SELL);

        if (CountPositions() < InpMaxPositions)
        {
            double sl = ask - InpStopLoss   * point;
            double tp = ask + InpTakeProfit * point;
            Trade.Buy(InpLotSize, InpSymbol, ask, sl, tp, "SimpleScalper Buy");
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
            Trade.Sell(InpLotSize, InpSymbol, bid, sl, tp, "SimpleScalper Sell");
        }
    }
}
//+------------------------------------------------------------------+
