# SimpleScalper — USDJPY限定 MAクロス スキャルピングEA

MT5（MetaTrader 5）用の最小構成スキャルピングEAです。  
USDJPY専用・取引時間帯制限付き（JST対応）・MAクロスによるエントリーロジック・スプレッドフィルタを実装しています。

---

## ロジック概要

| 項目 | 内容 |
|------|------|
| 通貨ペア | USDJPY 固定 |
| 取引時間帯 | 8:00〜11:00 / 16:00〜18:00 / 21:00〜24:00（JST基準、`UseJST=true`の場合） |
| エントリー | 短期MAが長期MAを**上抜け** → 買い<br>短期MAが長期MAを**下抜け** → 売り |
| 決済 | 固定TP/SL、逆シグナル発生時の即決済、または時間切れ（MaxBarsInTrade） |
| バー確認 | 新規バー開始時のみシグナルを評価（バー確定後エントリー） |
| スプレッドフィルタ | スプレッドが `MaxSpreadPoints` を超える場合はエントリーしない |

---

## パラメータ一覧

### 基本設定

| パラメータ | デフォルト | 説明 |
|-----------|-----------|------|
| `InpSymbol` | `USDJPY` | 取引通貨ペア（変更不可） |
| `InpMagicNumber` | `20240001` | EA識別用マジックナンバー |
| `InpMaxPositions` | `3` | 同時保有最大ポジション数 |
| `InpTakeProfit` | `200` | テイクプロフィット（ポイント） |
| `InpStopLoss` | `100` | ストップロス（ポイント） |

### ロット設定

| パラメータ | デフォルト | 説明 |
|-----------|-----------|------|
| `InpLotMode` | `LOT_FIXED` | ロットモード：`LOT_FIXED`（固定）または `LOT_RISK_PERCENT`（リスク%ベース） |
| `InpLotSize` | `0.01` | 固定ロット数（`LotMode=LOT_FIXED` 時に使用） |
| `InpRiskPercent` | `0.5` | 1トレードあたりのリスク%（`LotMode=LOT_RISK_PERCENT` 時に使用） |
| `InpMinLot` | `0.01` | リスク%計算結果の最小ロット上限 |
| `InpMaxLot` | `1.0` | リスク%計算結果の最大ロット上限 |

### 時間切れ決済（MaxBarsInTrade）

| パラメータ | デフォルト | 説明 |
|-----------|-----------|------|
| `InpMaxBarsInTrade` | `8` | ポジション保有の最大バー数。この本数を超えたら強制決済（`0` で無効） |
| `InpTimeExitMinProfitPoints` | `0` | 時間切れ決済の条件付き閾値（ポイント）。`0` なら含み損益に関係なく決済。正の値を設定すると含み益がその値**以上**の場合は決済をスキップし継続する |

### MAシグナル

| パラメータ | デフォルト | 説明 |
|-----------|-----------|------|
| `InpShortMaPeriod` | `5` | 短期MA期間 |
| `InpLongMaPeriod` | `20` | 長期MA期間 |
| `InpMaMethod` | `MODE_EMA` | MA計算方法（EMA/SMA/SMMA/LWMA） |

### JST・スプレッド・ログ

| パラメータ | デフォルト | 説明 |
|-----------|-----------|------|
| `UseJST` | `true` | JST（日本標準時）基準で取引時間帯を判定する |
| `ServerUtcOffsetHours` | `2` | ブローカーサーバのUTCオフセット（時間単位） |
| `JSTUtcOffsetHours` | `9` | JSTのUTCオフセット（通常9、変更不要） |
| `MaxSpreadPoints` | `30` | 新規エントリー時の最大許容スプレッド（ポイント） |
| `VerboseLog` | `true` | 詳細ログをエキスパートタブに出力する |

### 分析ログ設定

| パラメータ | デフォルト | 説明 |
|-----------|-----------|------|
| `EnableCsvLogging` | `true` | CSVファイルへのログ出力を有効にする（`MQL5/Files/` に保存） |
| `EnablePrintLogging` | `true` | Expertsタブへの構造化ログ出力を有効にする |
| `LogFileName` | `SimpleScalper` | CSVファイル名のプレフィックス（日付が自動付与される） |
| `LogLevel` | `1` | ログ出力レベル（`0`=エラーのみ, `1`=取引イベント, `2`=全詳細） |
| `UseServerTimeForSessions` | `false` | `true` のとき取引時間帯判定にサーバ時刻を使用（`false` のとき `UseJST` 設定を使用） |

### スプレッドスパイク後クールダウン

| パラメータ | デフォルト | 説明 |
|-----------|-----------|------|
| `EnableSpreadCooldown` | `true` | スプレッドスパイク後クールダウンを有効にする |
| `SpreadSpikeThresholdPoints` | `60` | スパイクと判定するスプレッド閾値（ポイント）。この値**以上**でクールダウン開始 |
| `SpreadCooldownMinutes` | `30` | スパイク検知後の新規エントリー抑制時間（分） |
| `SpreadCooldownAppliesOutsideSession` | `true` | `true` のとき取引時間外でもスパイクを検知し、次のIN時間帯でクールダウンを適用する |

### 上位足（H1）トレンドフィルタ

| パラメータ | デフォルト | 説明 |
|-----------|-----------|------|
| `EnableHigherTimeframeFilter` | `false` | 上位足トレンドフィルタを有効にする |
| `HigherTimeframe` | `PERIOD_H1` | 上位足の時間足（H1 推奨） |
| `HigherFastMAPeriod` | `20` | 上位足の短期MA期間 |
| `HigherSlowMAPeriod` | `50` | 上位足の長期MA期間 |

> **注意**: USDJPYチャートの場合、1ポイント ≒ 0.001円相当（5桁ブローカーでは `100ポイント = 約1銭`）。

---

## リスク%ベースのロット計算（LotMode = LOT_RISK_PERCENT）

`InpLotMode = LOT_RISK_PERCENT` に設定すると、固定ロットの代わりに口座残高と設定したリスク%からロットを自動計算します。

### 計算式

```
リスク金額     = 口座残高 × RiskPercent / 100
SL損失額/Lot   = SL距離(ポイント) × (Point / TickSize) × TickValue
自動ロット数   = リスク金額 / SL損失額/Lot
```

計算後、ブローカーのボリュームステップ（`SYMBOL_VOLUME_STEP`）に切り捨て丸めし、`InpMinLot`〜`InpMaxLot` の範囲にクランプします。

### 推奨初期値

| 口座残高 | RiskPercent | SL=100pts のおよそのロット |
|---------|-------------|--------------------------|
| $1,000  | 0.5%        | 約 0.05 lot               |
| $10,000 | 0.5%        | 約 0.50 lot               |
| $1,000  | 1.0%        | 約 0.10 lot               |

> **ポイント**: `RiskPercent = 0.5` かつ `SL = 100ポイント` の場合、1回のトレードで口座残高の最大0.5%を失うよう設定されます。

> **注意**: 上記ロット数はTickValue・TickSizeがブローカーやタイムゾーンによって異なるため概算です。実際のロットは `CalcLot` のVerboseLogで確認してください。

### 証拠金チェック

エントリー直前に `OrderCalcMargin` で必要証拠金を確認し、余剰証拠金（`ACCOUNT_FREEMARGIN`）が不足している場合はエントリーをスキップします。スキップ時は `VerboseLog=true` なら理由がログに出力されます。

---

## 時間切れ決済（MaxBarsInTrade）

`InpMaxBarsInTrade > 0` に設定すると、ポジション保有バー数が上限を超えた場合に強制決済します。

- 新しいバーが確定するたびに全保有ポジションを確認
- ポジションのオープン時刻から `iBarShift` で経過バー数を算出
- 経過バー数 ≥ `InpMaxBarsInTrade` になったらクローズ
- `InpTimeExitMinProfitPoints > 0` の場合、含み益がその値以上なら**クローズしない**（TP到達まで継続）
- クローズ時のログに `理由: TimeExit` を出力

### 決済の優先順位

1. **逆シグナル決済**（MAクロスで反対方向シグナル発生時）  
2. **TP/SL**（ブローカー側で自動執行）  
3. **時間切れ決済**（MaxBarsInTrade超過時、新バーごとにチェック）

> **TP/SL決済はOnTradeTransactionで記録される**  
> TP/SLによるサーバ側での自動決済は EA の `OnTick` では捕捉できないため、`OnTradeTransaction` ハンドラで取引履歴のDeal（`DEAL_ENTRY_OUT`）を監視してログに記録します。  
> CSVでは `event_type=DEAL_OUT`、`reason` 列に `TAKE_PROFIT` / `STOP_LOSS` が記録されます（→ [reason一覧](#reason-一覧) を参照）。  
> EA側の明示的な決済（逆シグナル・時間切れ）は `event_type=EXIT` として記録され、同じ決済について `DEAL_OUT` 行も別途追記されます。`deal_reason` 列でサーバ側の理由（`DEAL_REASON_EXPERT` など）を確認することで、どちらの仕組みで決済されたか区別できます。

---

## スプレッドスパイク後クールダウン

経済指標発表などでスプレッドが一時的に急拡大した直後の取引を避け、スキャルピングの期待値を改善するフィルタです。

- **スパイク検知はすべてのティックで実行** される（新バー待ちなし）
- `SpreadCooldownAppliesOutsideSession=true`（デフォルト）のとき、**取引時間帯外のスパイクも検知** し、次に取引時間帯に入っても即エントリーを抑制できる
- スパイク検知時は `g_cooldownUntil = 現在時刻 + SpreadCooldownMinutes` を設定（延長可）
- クールダウン中は **新規エントリーのみ** を抑制し、既存ポジションの決済・管理は継続
- スキップ時のログ: `event_type=SKIP_COOLDOWN`, `reason=SPREAD_COOLDOWN`, `cooldown_until`（終了時刻）列に記録

### クールダウンの流れ

```
[Out時間帯] Spread=80pts >= Threshold=60pts → g_cooldownUntil = 現在時刻 + 30分
[In時間帯に移行] TimeCurrent() < g_cooldownUntil → SKIP_COOLDOWN ログ出力 → エントリーしない
[30分経過後]  クールダウン終了 → 通常通りエントリー判定
```

---

## 上位足（H1）トレンドフィルタ

M15 の MAクロスシグナルを、上位足のトレンド方向に沿ったものだけ採用するフィルタです。

- `EnableHigherTimeframeFilter=false`（デフォルト）では無効。有効にすると上位足方向と反対のエントリーをブロック
- 判定ロジック:
  - 上位足 fastMA **>** slowMA → **BUYのみ** 許可（SELLはブロック）
  - 上位足 fastMA **<** slowMA → **SELLのみ** 許可（BUYはブロック）
  - fastMA = slowMA（FLAT）の場合はBUY/SELL両方ブロック
- ブロック時のログ: `event_type=SKIP_SYMBOL`, `reason=HTF_FILTER_BLOCKED`
- `htf_fast_ma_value`, `htf_slow_ma_value`, `htf_trend`（UP/DOWN/FLAT）がCSVに記録される

### A/Bテスト推奨設定

HTFフィルタの効果を比較する場合、`MagicNumber` と `LogFileName` を分けて同じチャートに2つEAを稼働させてください。

| 設定項目 | EA_A（フィルタなし） | EA_B（フィルタあり） |
|---------|---------------------|---------------------|
| `InpMagicNumber` | `20240001` | `20240002` |
| `LogFileName` | `Scalper_A` | `Scalper_B` |
| `EnableHigherTimeframeFilter` | `false` | `true` |

---

## JST時間帯判定の仕組み

`UseJST=true`（デフォルト）のとき、EAは内部で次の計算によりサーバ時刻をJSTに変換して時間帯を判定します。

```
UTC時刻     = サーバ時刻 − ServerUtcOffsetHours
JST時刻     = UTC時刻 + JSTUtcOffsetHours
```

### ServerUtcOffsetHours の設定方法

ブローカーのサーバ時間は証券会社ごとに異なります。以下の手順で正しい値を確認してください。

1. MT5の気配値表示画面で現在の**サーバ時刻**を確認する  
2. その時刻に対応する**UTC時刻**（世界協定時）を調べる  
3. `サーバ時刻 − UTC時刻 = ServerUtcOffsetHours`

**例（本EAのデフォルト値の根拠）:**  
- MT5気配値でサーバ時刻が**15:00**と表示されている  
- 実際のJST（日本時間）が**22:00**  
- → JST(22) - サーバ(15) = 7時間差 → サーバはJSTより-7h → UTC+2  
- → `ServerUtcOffsetHours = 2`（デフォルト値）

---

## スプレッドフィルタ（MaxSpreadPoints）

新規エントリーの直前にBid/Askから現在スプレッドをポイント単位で計算し、`MaxSpreadPoints`を超えている場合はエントリーをスキップします。  
スプレッドが広い局面（経済指標発表前後・早朝など）での不利なエントリーを防ぐための機能です。

- **推奨値**: 通常のUSDJPYスプレッドが1〜3pipsの環境では `20〜30` 程度  
- エントリーをスキップした場合、エキスパートタブに `エントリー見送り | 理由: スプレッド超過` と出力されます

---

## ログの見方

`VerboseLog=true`（デフォルト）のとき、新しいバーが確定するたびにMT5の**エキスパートタブ**へ以下のようなログが出力されます。

```
=== 新バー判定 | JST:2024.01.15 10:05 | USDJPY | Bid:148.500 | Ask:148.503 | Spread:3pts | 取引時間帯:YES
MA情報 | FastMA(前):148.450 FastMA(現):148.510 | SlowMA(前):148.430 SlowMA(現):148.460 | クロス:ゴールデンクロス(買い)
CalcLot | Balance:10000.00 | Risk%:0.5 | RiskAmt:50.00 | LossPerLot:10.0000 | Lot:0.50
エントリー実行 | BUY | Ask:148.503 | SL:148.403 | TP:148.703 | Lot:0.50
```

```
時間切れ決済 | Ticket:12345678 | 経過バー:8 | 理由: TimeExit
```

| ログ項目 | 説明 |
|---------|------|
| `=== 新バー判定` | バー確定時の基本情報（JST時刻・Symbol・Bid/Ask・スプレッド・時間帯判定） |
| `MA情報` | FastMA/SlowMAの前バー・現バー値とクロス方向 |
| `CalcLot` | リスク%モード時のロット計算詳細（残高・リスク額・ロット） |
| `エントリー実行` | エントリー方向・価格・SL/TP・ロット数 |
| `エントリー見送り` | スキップ理由（時間外／スプレッド超過／ポジション上限／証拠金不足／シグナルなし） |
| `時間切れ決済` | MaxBarsInTrade超過による強制決済（理由: TimeExit） |
| `時間切れ決済スキップ` | 含み益が閾値以上のため時間切れ決済を見送り |

**EA起動時**（OnInit）にもサーバ時刻・UTC時刻・JST時刻および取引可能かどうかが出力されます：

```
SimpleScalper 初期化完了 | Magic:20240001 | LotMode:RiskPercent | RiskPercent:0.50% | TP:200 | SL:100 | MaxBarsInTrade:8
時刻情報 | Server:2024.01.15 01:05 | UTC:2024.01.14 23:05 | JST:2024.01.15 08:05 | UseJST:true | ServerUtcOffset:2h
取引時間帯判定 | 現在取引可能:YES
```

---

## 設置方法

1. MetaEditor（MT5付属）を開く
2. `SimpleScalper.mq5` を `MQL5/Experts/` フォルダにコピー
3. MetaEditorで`F7`キーを押してコンパイル（エラーがないことを確認）
4. MT5のナビゲーターウィンドウ → **エキスパートアドバイザー** に `SimpleScalper` が表示される
5. **USDJPYチャート**（推奨：M5またはM15）へドラッグ＆ドロップ
6. パラメータを設定し「自動売買を許可する」にチェックを入れてOK

---

## デモ口座でのテスト手順

### ストラテジーテスター（バックテスト）

1. MT5メニュー → **表示 → ストラテジーテスター**（Ctrl+R）を開く
2. 以下を設定：
   - **エキスパート**: `SimpleScalper`
   - **シンボル**: `USDJPY`
   - **タイムフレーム**: `M5`（または`M15`）
   - **モデリング**: `全ティック`（精度優先）または `始値のみ`（高速確認用）
   - **期間**: 任意（直近3〜6ヶ月推奨）
3. **スタート**ボタンをクリックしてバックテスト実行
4. 結果タブで損益・ドローダウンを確認

### デモ口座リアルタイム動作確認

1. デモ口座でMT5にログイン
2. USDJPYチャートにEAをアタッチ
3. MT5ツールバーの **自動売買**ボタン（緑の矢印）がオンになっていることを確認
4. 取引時間帯（JST 8-11時、16-18時、21-24時）にMAクロスが発生するとエントリーされることを確認
5. **エキスパートタブ**のログでEAの動作状況を確認

---

## 分析用ログ出力

`EnableCsvLogging=true`（デフォルト）にすると、MT5のデータフォルダ内の `MQL5/Files/` に CSV ファイルが生成されます。

### ファイルの場所

- **Expertsタブ（Print ログ）**: MT5の「エキスパート」タブでリアルタイムに確認できます
- **CSV ファイル**: MT5メニュー → **ファイル → データフォルダを開く** → `MQL5/Files/SimpleScalper_YYYYMMDD.csv`

同じ日に再起動した場合は、既存ファイルの末尾に追記されます。

### CSV 列の説明

| 列名 | 説明 |
|------|------|
| `timestamp_server` | サーバ時刻（`TimeTradeServer`相当） |
| `timestamp_local` | ローカル時刻（`TimeLocal`） |
| `symbol` | 取引通貨ペア |
| `timeframe` | 稼働時間足（例: `PERIOD_M5`） |
| `event_type` | イベント種別（下表参照） |
| `side` | 売買方向（`BUY` / `SELL` / `NONE`） |
| `reason` | イベント理由（下表参照） |
| `fast_ma_period` | 短期MA期間（EA設定値） |
| `slow_ma_period` | 長期MA期間（EA設定値） |
| `fast_ma_value` | 判定に使った短期MA値 |
| `slow_ma_value` | 判定に使った長期MA値 |
| `price_bid` | Bid 価格 |
| `price_ask` | Ask 価格 |
| `spread_points` | スプレッド（ポイント） |
| `lot` | ロット数 |
| `sl_price` | ストップロス価格 |
| `tp_price` | テイクプロフィット価格 |
| `order_ticket` | 注文チケット番号 |
| `position_ticket` | ポジションチケット番号 |
| `deal_ticket` | 約定チケット番号 |
| `retcode` | 注文送信の戻りコード（10009=成功） |
| `last_error` | エラー時の `GetLastError()` 値 |
| `session_state` | セッション判定結果（例: `IN:08:00-11:00(JST)` / `OUT(server)`） |
| `deal_reason` | サーバ側のDeal理由（EnumToString値: `DEAL_REASON_TP` / `DEAL_REASON_SL` / `DEAL_REASON_EXPERT` など）。`DEAL_OUT` 行のみ設定 |
| `profit` | 確定損益（`DEAL_OUT` 行のみ） |
| `commission` | コミッション（`DEAL_OUT` 行のみ） |
| `swap` | スワップ（`DEAL_OUT` 行のみ） |
| `deal_price` | 約定価格（`DEAL_OUT` 行のみ） |
| `cooldown_until` | クールダウン終了時刻（`SKIP_COOLDOWN` 行のみ） |
| `htf_fast_ma_value` | 上位足短期MA値（HTFフィルタ有効時・`SKIP_SYMBOL/reason=HTF_FILTER_BLOCKED` 行） |
| `htf_slow_ma_value` | 上位足長期MA値（HTFフィルタ有効時・`SKIP_SYMBOL/reason=HTF_FILTER_BLOCKED` 行） |
| `htf_trend` | 上位足トレンド方向（`UP` / `DOWN` / `FLAT`）（HTFフィルタ有効時） |

### event_type 一覧

| event_type | 説明 |
|-----------|------|
| `INIT` | EA初期化完了 |
| `DEINIT` | EA終了 |
| `NEW_BAR` | 新規バー確定（`LogLevel=2` のみ出力） |
| `SIGNAL` | MAクロスシグナル検出（`LogLevel=2` のみ出力） |
| `ENTRY` | エントリー注文送信成功 |
| `EXIT` | EA起点のポジション決済（逆シグナル・時間切れ） |
| `DEAL_OUT` | 取引履歴に追加されたクローズDeal（TP/SL含む全決済）。`OnTradeTransaction` で記録 |
| `SKIP_TIME` | 取引時間外のためスキップ |
| `SKIP_SYMBOL` | スプレッド超過・証拠金不足・HTFフィルタブロックのためスキップ |
| `SKIP_COOLDOWN` | スプレッドスパイク後クールダウン中のためスキップ |
| `ERROR` | 注文失敗・MAデータ取得失敗などのエラー |

### reason 一覧

| reason | 説明 |
|--------|------|
| `MA_CROSS_UP` | ゴールデンクロス（買いシグナル） |
| `MA_CROSS_DOWN` | デッドクロス（売りシグナル） |
| `REVERSE_SIGNAL` | 逆シグナルによるポジション決済 |
| `TIME_EXIT` | 最大保有バー数超過による決済 |
| `TAKE_PROFIT` | TP到達による自動決済（`DEAL_OUT` 行） |
| `STOP_LOSS` | SL到達による自動決済（`DEAL_OUT` 行） |
| `EA_CLOSE` | EA（EXPERT）が発行したクローズ（`DEAL_OUT` 行。逆シグナル・時間切れ等） |
| `MANUAL` | 手動操作によるクローズ（CLIENT/MOBILE/WEB）（`DEAL_OUT` 行） |
| `STOP_OUT` | 強制ロスカットによるクローズ（`DEAL_OUT` 行） |
| `ROLLOVER` | ロールオーバーによるクローズ（`DEAL_OUT` 行） |
| `OUT_OF_SESSION` | 取引時間帯外 |
| `SPREAD_TOO_HIGH` | スプレッド超過（`MaxSpreadPoints` 超え） |
| `SPREAD_COOLDOWN` | スプレッドスパイク後クールダウン中（`SKIP_COOLDOWN` 行） |
| `INSUFFICIENT_MARGIN` | 証拠金不足 |
| `HTF_FILTER_BLOCKED` | 上位足トレンドフィルタにより方向不一致でブロック |
| `ORDER_SEND_FAIL` | 注文送信失敗 |
| `MA_BUFFER_COPY_FAIL` | MAバッファ取得失敗 |
| `EA_START` | EA起動（INIT イベント） |

### session_state の読み方

`session_state` 列には「判定結果:セッション枠(使用時刻ベース)」の形式で出力されます。

```
IN:08:00-11:00(JST)   → JST 8〜11時台（取引時間内）
IN:16:00-18:00(JST)   → JST 16〜18時台（取引時間内）
IN:21:00-24:00(JST)   → JST 21時以降（取引時間内）
OUT(JST)              → 上記以外（取引時間外）
IN:08:00-11:00(server) → サーバ時刻使用時（UseServerTimeForSessions=true）
```

### CSV サンプル出力

```
timestamp_server,timestamp_local,symbol,timeframe,event_type,side,reason,fast_ma_period,slow_ma_period,fast_ma_value,slow_ma_value,price_bid,price_ask,spread_points,lot,sl_price,tp_price,order_ticket,position_ticket,deal_ticket,retcode,last_error,session_state
2024.01.15 01:05:00,2024.01.15 09:05:00,USDJPY,PERIOD_M5,INIT,NONE,EA_START,5,20,,,,,,,,,,,,,,IN:08:00-11:00(JST)
2024.01.15 01:05:00,2024.01.15 09:05:00,USDJPY,PERIOD_M5,NEW_BAR,NONE,,5,20,,,,148.50000,148.50300,3,,,,,,,,,IN:08:00-11:00(JST)
2024.01.15 01:05:00,2024.01.15 09:05:00,USDJPY,PERIOD_M5,SIGNAL,BUY,MA_CROSS_UP,5,20,148.51000,148.46000,148.50000,148.50300,3,,,,,,,,,IN:08:00-11:00(JST)
2024.01.15 01:05:00,2024.01.15 09:05:00,USDJPY,PERIOD_M5,ENTRY,BUY,MA_CROSS_UP,5,20,148.51000,148.46000,148.50000,148.50300,3,0.01,148.40300,148.70300,12345678,,67890123,10009,,IN:08:00-11:00(JST)
2024.01.15 02:00:00,2024.01.15 10:00:00,USDJPY,PERIOD_M5,EXIT,BUY,REVERSE_SIGNAL,5,20,,,,,,,,,,12345678,,87654321,10009,,IN:08:00-11:00(JST)
2024.01.15 03:00:00,2024.01.15 11:00:00,USDJPY,PERIOD_M5,SKIP_TIME,NONE,OUT_OF_SESSION,5,20,,,,148.60000,148.60300,3,,,,,,,,,OUT(JST)
```

### ログを貼り付けて分析依頼する際の注意

> ⚠️ **プライバシー・セキュリティに関するご注意**
>
> CSV ファイルには **口座番号・残高・個人情報は含まれません**（TicketID は含まれます）。  
> ただし、チケット番号からポジション情報が特定される可能性があるため、共有前に以下をご確認ください。
>
> - `order_ticket` / `position_ticket` / `deal_ticket` 列が気になる場合は削除してから共有してください
> - 本番口座のログを共有する場合は、チケット番号を別の番号に置換することをお勧めします
> - CSVはデモ口座で動作確認した後に取得することを推奨します

---

## ファイル構成

```
fx_ea/
├── SimpleScalper.mq5   # EA本体
├── Logger.mqh          # 分析ログモジュール（CSV/Print ログ）
└── README.md           # このファイル
```

---

## 注意事項

- 本EAはデモ口座での動作検証用の最小構成実装です
- 実口座での使用は自己責任でお願いします
- ブローカーによってサーバー時間が異なるため、`ServerUtcOffsetHours` を実環境に合わせて設定してください
- `MaxBarsInTrade` による時間切れ決済は含み損が発生していてもポジションを強制クローズします。リスク管理の観点で設定値にご注意ください

