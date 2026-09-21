# Exp07: ILC 教師信号の反復再現性

対象は、卒論の成分分離に渡す ILC 教師信号の取得段階。学習軌道を変えず、学習過渡を雑音として数えてしまう反復統計を修正する。任意軌道への転用や新規アルゴリズムの優越性を実証した PR ではない。

- 理論・先行研究・数値結果: [研究会用ノート](../docs/exp07/research_note.md)
- 対象会話と取得範囲: [再考察の記録](../docs/exp07/conversation_audit.md)
- 実行入口: `repeatability_experiment.m`

## 実行

1. ルートの `setup_project` を実行し、本フォルダの `repeatability_experiment.m` を開く。
2. 第1・2節で、exp04 と同じ設定・プラント・FB・学習フィルタを読み込む。実機で既に成功した原点・ストローク・速度を設定し、感度と収束の周波数応答を確認する。既定の 1.25 m / 0.3 m/s は装置の安全限界ではない。
3. モデル・周期・固定バッファを変えていなければ再ビルドしない。変えた場合だけ、第3節の既存 `exp03_FF/setup_tunable.m` と既存の Publish / Activate 手順を使う。
4. 第4節が実機動作。4手法を乱数シードで決めた順に各15試行し、各手法の最後に**実際に印加した** FF を固定して同じ軌道を5回再走行する。5回は5種類の評価軌道ではない。実機への模擬外乱注入は追加していない。
5. `data/ilc/<日時_exp07_repeatability>/` の `manifest.mat`、`block.mat`、各 train / replay の MAT・raw、および `repeatability_metrics.csv` を確認する。部分終了データは残す。途中失敗から自動継続する機構は設けない。

手法順による温度・時間変化を調べる場合は、別の `orderSeed` でブロックを繰り返す。5回の replay だけを独立な装置個体数として統計処理しない。既存の計測欠落・電流上限・停止・無励磁確認を引き続き用いる。新しい arming、監視プロセス、PLC 状態機械、通信再試行は追加しない。

## 手法の対応

| mode | 更新 | 位置づけ |
|---|---|---|
| `standard` | exp04 が計算した候補をそのまま採用 | 既存比較基準 |
| `raw_rcs` | 過去の未補正更新量の分散からスカラーゲートを計算 | 学習過渡混入の診断用。特定論文の再実装ではない |
| `transport_mean` | `z = L e + L Jhat f` を5試行平均し、現在の FF へ戻す | 過渡補正平均の効果 |
| `transport_rcs` | 同じ平均にスカラーゲートを追加 | ゲート自体の追加効果 |
| `hold` | FF を更新しない | 独立した学習法ではなく replay 用 |

ゲートは Q の内側ではなく、Q と端処理を含む更新全体を緩和する。ゲート式は最適性を証明した推定器ではなく、比較用に固定したヒューリスティック。`window=5`, `minGain=0.1`。この値を test 結果から再調整した場合、その結果を未使用データの評価とは呼ばない。

## 既存コードとの差分

`exp04_ILC/obtainMeasurement.m` の単一軌道入口に任意の `ilcExtension` を追加した。指定しない場合、従来の更新演算と履歴フィールドを保持する。速度スイープは従来どおり。

```matlab
ilcExtension.initialFeedforward = initialFF;
ilcExtension.update = @(f,e,k,baseline,state) my_update(f,e,k,baseline,state);
```

callback は `[nextFF,state,info]` を返す。`baseline` は従来の `alpha`、`filtfilt_clean`、25 ms 端処理を適用済みの候補。`info` は `history.updateInfo{k}` に保存する。callback が返す波形にも従来と同じ入力上限を適用する。生計測・停止処理・MotorRuntime・Simulink モデルは変更しない。

## 検証状態

Python / NumPy / SciPy の閉ループ誤差空間での合成数値例を実行済み。実機データの分析・再計測、MATLAB、Simulink、TwinCAT の実行は未実施。この環境に MATLAB / Octave はない。

```bash
python exp07_RepeatabilityILC/simulate_reference.py --output docs/exp07/synthetic
```

合成例では円環周波数モデルと正則化逆を使い、実機 MATLAB では既存の有限長逆モデルと端処理を使う。この差を隠して MATLAB の動作確認の代わりにはしない。数値結果の表・設定・代数確認を `docs/exp07/synthetic/` に保存した。実機の `data/` と区別する。

MATLAB で変更箇所を確認するときは、本フォルダを path に追加して `check_exp07` を1回実行する。新しいテスト基盤や全件テストは追加しない。実機実行後、必要な確認は取得された位置・入力・停止状態に対して行う。
