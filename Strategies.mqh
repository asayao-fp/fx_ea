//+------------------------------------------------------------------+
//|                                                   Strategies.mqh  |
//|                        複数戦略シグナル評価モジュール              |
//|  使用方法:                                                        |
//|    SStrategySignal sig = EvaluateMACross(shortHandle, longHandle);|
//|    SStrategySignal sig = EvaluateBreakout(symbol, N, buf);       |
//+------------------------------------------------------------------+
#property strict

//+------------------------------------------------------------------+
//| 戦略シグナル構造体                                                |
//| 各戦略評価関数がこの構造体を返す                                  |
//+------------------------------------------------------------------+
struct SStrategySignal
{
   string signal;        // "BUY" / "SELL" / "NONE"
   string reason;        // ログ用理由文字列
   bool   error;         // データ取得失敗フラグ（true時は signal="NONE"）

   // MAクロス詳細（EvaluateMACross のみ設定される）
   double shortMaCurr;   // 短期MA 最新確定値（1本前）
   double shortMaPrev;   // 短期MA 前々確定値（2本前）
   double longMaCurr;    // 長期MA 最新確定値（1本前）
   double longMaPrev;    // 長期MA 前々確定値（2本前）

   // ブレイクアウト詳細（EvaluateBreakout のみ設定される）
   double boHighestHigh; // 参照範囲の最高値
   double boLowestLow;   // 参照範囲の最安値

   SStrategySignal()
   {
      signal       = "NONE";
      reason       = "";
      error        = false;
      shortMaCurr  = 0.0;
      shortMaPrev  = 0.0;
      longMaCurr   = 0.0;
      longMaPrev   = 0.0;
      boHighestHigh = 0.0;
      boLowestLow   = 0.0;
   }
};

//+------------------------------------------------------------------+
//| MAクロス戦略評価                                                  |
//|                                                                  |
//| 直近2本の確定足（shift=1, 2）のMAを比較してゴールデン/デッドクロス |
//| を判定する。                                                      |
//|                                                                  |
//| 返り値: SStrategySignal                                          |
//|   signal = "BUY"  → ゴールデンクロス（MA_CROSS_UP）             |
//|   signal = "SELL" → デッドクロス    （MA_CROSS_DOWN）            |
//|   signal = "NONE" → クロスなし / エラー                         |
//+------------------------------------------------------------------+
SStrategySignal EvaluateMACross(int shortMaHandle, int longMaHandle)
{
   SStrategySignal result;

   double shortBuf[2], longBuf[2];
   // CopyBuffer: shift=1 から 2本取得 → [0]=1本前, [1]=2本前
   if (CopyBuffer(shortMaHandle, 0, 1, 2, shortBuf) < 2 ||
       CopyBuffer(longMaHandle,  0, 1, 2, longBuf)  < 2)
   {
      result.error  = true;
      result.reason = "MA_BUFFER_COPY_FAIL";
      return result;
   }

   result.shortMaPrev = shortBuf[1];
   result.shortMaCurr = shortBuf[0];
   result.longMaPrev  = longBuf[1];
   result.longMaCurr  = longBuf[0];

   // ゴールデンクロス: 前バーで shortMA <= longMA だったが現バーで shortMA > longMA に
   if (result.shortMaPrev <= result.longMaPrev && result.shortMaCurr > result.longMaCurr)
   {
      result.signal = "BUY";
      result.reason = "MA_CROSS_UP";
   }
   // デッドクロス: 前バーで shortMA >= longMA だったが現バーで shortMA < longMA に
   else if (result.shortMaPrev >= result.longMaPrev && result.shortMaCurr < result.longMaCurr)
   {
      result.signal = "SELL";
      result.reason = "MA_CROSS_DOWN";
   }

   return result;
}

//+------------------------------------------------------------------+
//| ブレイクアウト戦略評価                                            |
//|                                                                  |
//| 稼働足（PERIOD_CURRENT）の直近 lookbackBars 本の確定足（bar 1〜N）|
//| の高値/安値を計算し、現在価格がブレイクアウトしているか判定する。  |
//|                                                                  |
//| BUY 条件 : Ask >= 直近N本高値 + buffer                           |
//| SELL条件 : Bid <= 直近N本安値 - buffer                           |
//|                                                                  |
//| 返り値: SStrategySignal                                          |
//|   signal = "BUY"  → 上方ブレイクアウト（BREAKOUT_UP）           |
//|   signal = "SELL" → 下方ブレイクアウト（BREAKOUT_DOWN）          |
//|   signal = "NONE" → ブレイクアウトなし / エラー                 |
//+------------------------------------------------------------------+
SStrategySignal EvaluateBreakout(const string symbol, int lookbackBars, int bufferPoints)
{
   SStrategySignal result;

   if (lookbackBars <= 0)
      return result;

   double highArray[], lowArray[];
   // shift=1 で形成中の足（bar 0）を除外し確定済みの足を使う
   if (CopyHigh(symbol, PERIOD_CURRENT, 1, lookbackBars, highArray) < lookbackBars ||
       CopyLow (symbol, PERIOD_CURRENT, 1, lookbackBars, lowArray)  < lookbackBars)
   {
      result.error  = true;
      result.reason = "PRICE_BUFFER_COPY_FAIL";
      return result;
   }

   double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double buffer = bufferPoints * point;

   int highIdx = ArrayMaximum(highArray);
   int lowIdx  = ArrayMinimum(lowArray);
   result.boHighestHigh = highArray[highIdx];
   result.boLowestLow   = lowArray[lowIdx];

   double ask = SymbolInfoDouble(symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(symbol, SYMBOL_BID);

   if (ask >= result.boHighestHigh + buffer)
   {
      result.signal = "BUY";
      result.reason = "BREAKOUT_UP";
   }
   else if (bid <= result.boLowestLow - buffer)
   {
      result.signal = "SELL";
      result.reason = "BREAKOUT_DOWN";
   }

   return result;
}
