# 2026-09-08: 加速度マップFF実験の実行・正常終了確認

**現在の判定:** 以下は各時点の実行記録。40 Hz化による精度低下が確認されたため、
実機バッチの正常終了を精度要件の達成として扱った判断を撤回した。入口のQ帯域は420 Hzへ戻した。

`exp05_AccelerationFF/acceleration_ff_experiment.m` をMATLAB R2025aの
バッチ1セッションで全体実行し、学習6本、同定、比較4本、保存まで完了した。
終了コードは0。全10試行の `passed=true`、終了後の全4軸無励磁を確認した。
この全体実行時点では対象スクリプトと取得関数は実行前スナップショットとSHA-256が一致した。
その後のTarget選択の修正と検証は末尾に記録する。

## 実行条件と確認範囲

- 実行時刻: 16:31:48–16:38:55 JST。
- 既存4 kHzプラントと `fbDesign`、周期250 µs、電流上限2 A、距離0.84 m。
  名目閉ループ安定、実測感度ピーク1.511371854（基準2未満）。
- 学習: 片道4/5/6 s、各warp ±0.65、各1回。比較: 4.5 s / −0.25と5.5 s / +0.25。
- `mapGain=1`、微分窓41点、入力対応−8点、両端接続2 cm。
  通常FF係数は全0のため、重複する通常FFの取得は既存仕様に従って省略。
- モデル・PLC・制御器・安全設定の変更、再ビルド、再Activateは実施していない。
- 実機ADS前後確認に加え、既存の独立ADS監視を今回の保存先で使用。
  監視した動作は実験10回とHoming1回、監視停止なし。
- 全件テストは再実行せず、実際のスクリプト実行と保存結果の確認に限定。

## 取得と同定

学習は48,001点×2、56,001点×2、64,001点×2。
比較は52,001点×2、60,001点×2。合計560,010サンプル、各10信号を取得した。
全試行で有限値、カウンタ連続、記録reference/FFの入力一致
（既存の1サンプル記録遅延を考慮）、追従・終端誤差、無飽和の判定に合格。
各試行の `result.mat` と `raw/` が保存されている。

全試行の最大電流は1.530804 A、最大追従誤差788.0 µm、
最大終端相対位置誤差10.2 µm。電流上限到達点数はすべて0。
位置マップは161/161点で有効だった。

| 未学習軌道 | 方法 | RMS [µm] | 加減速中RMS [µm] | ピーク誤差 [µm] | 電流ピーク [A] |
| --- | --- | ---: | ---: | ---: | ---: |
| 1 | FB | 154.38 | 189.24 | 786.3 | 1.461 |
| 1 | 加速度マップFF | 84.61 | 103.88 | 334.4 | 1.290 |
| 2 | FB | 146.87 | 176.50 | 751.8 | 1.294 |
| 2 | 加速度マップFF | 77.04 | 92.96 | 305.5 | 1.206 |

今回の2軌道ではRMSが45.2% / 47.5%低下した。各条件1回の結果であり、
再現性・他速度域への一般化・係数の物理的正確さは未評価。
同定対象は総電流指令で、実電流や推力の直接同定ではない。

## 終了状態と警告

最終FF前にHomingが1回発生し、54,101,101 countから54,100,240 countへ到達
（目標54,100,000 count、誤差24.0 µm、成功）。
実験完了時は54,100,510 count、MATLABプロセス終了後の独立確認では54,100,522 count。
終了後の速度0、Fault=0、I/O正常、TwinCAT Run、全軸TargetTorque=0、
StatusWord=5681（Operation Enabled/Faultビット0）、`p_active=p_servo=0`。
実験完了時の各ControlWordは6で、磁極参照もmanifestと一致した。

全実験・保存・終了状態検証の完了後、MATLABバッチ終了時に
「変更されたモデルを閉じられない」「モデルワークスペースを保存するか」の警告が2件出た。
ログと終了コード0を保持し、プロセス終了後も実機の停止・無励磁を独立確認した。
モデルファイルは保存されていない。警告のための実機再試行は行っていない。
バッチ用ラッパーでモデルを明示的に閉じていない点は残っている。

`config/config_tunable.m` の通常の保存処理により
`config/data/config_tunable.mat` は今回の設定で再生成された。
今回の実行は実ファイルへの `run(...)` で確認したもので、エディターの一時コピー経由の
実行は検証していない。

## 保存先

- [集計JSON](../data/acceleration_ff/20260908_1630_verification/summary.json)
- [バッチログ（終了時警告を含む）](../data/acceleration_ff/20260908_1630_verification/batch.log)
- [終了コード](../data/acceleration_ff/20260908_1630_verification/exit_code.txt)
- [MATLAB終了後の実機状態](../data/acceleration_ff/20260908_1630_verification/post_exit_state.json)
- [独立監視結果](../data/acceleration_ff/20260908_1630_verification/monitor.json)
- [実行ラッパー](../data/acceleration_ff/20260908_1630_verification/verify_acceleration_run.m)
- [学習途中経過（6本完了）](../data/acceleration_ff/20260908_163237_176_training/training_progress.mat)
- [同定マップ](../data/acceleration_ff/20260908_163642_262_map/acceleration_map.mat)
- [比較表MAT](../data/acceleration_ff/20260908_163644_705_comparison/comparison.mat)
- [比較軌道1の図](../data/acceleration_ff/20260908_163644_705_comparison/20260908_163715_567_profile_01_acceleration/figure_6.png)
- [比較軌道2の図](../data/acceleration_ff/20260908_163644_705_comparison/20260908_163825_897_profile_02_acceleration/figure_7.png)
- [Homing結果](../data/homing/20260908_163814_846_Homing_Result/Homing_Result.mat)

保存したラッパー・監視スクリプト・フラグは今回の実行記録。
再実行時は新しい保存先を使用し、既存の記録やフラグを流用しない。

## 追記: Target選択の自動化と実験入口の整理

初回の全体実行では `ExtModeMexArgs` が空で、ユーザーから各Connect時に
Targetを手動選択したとの報告があった。初回結果を「人手なしの全体実行成功」とは扱わない。

`src/capture_tunable_trajectory.m` で接続前に
`ExtModeMexArgs = '192.168.10.3.1.1' 0 16842784` を指定するよう修正した。
接続先は既存Homingと同じObject3（`0x01010020`）。exp03・exp05・Homingの共通取得に適用される。
試行単位の接続・切断と既存の停止処理・待機時間・電流保護は維持した。
ILCの1接続を保つループへ変更する必要はなく、接続先の明示で選択操作をなくせる。

`acceleration_ff_experiment.m` 本体にも名目安定性・感度の数値ゲートと
`ACCELERATION_FF_COMPLETE` の完了表示を追加した。
`verify_acceleration_run.m` は初回検証の集計用記録であり、実験の依存ファイルではない。
通常の入口は引き続き `exp05_AccelerationFF/acceleration_ff_experiment.m`。

修正後は、各回の接続引数をいったん空にして共通取得関数を2回呼び、
どちらも手操作なしで接続・切断できることをR2025aバッチで確認した。
reference 4点 / FF 3点を与え、接続後・サーボ有効化前に既知の
`NikonMotor:TrajectoryLengthMismatch` を発生させてcleanupまで検証した。
2回とも期待したエラーだけを捕捉し、`ExtModeConnected=off`、
`p_active=p_servo=0`、バッチ終了コード0、終了時警告なし。
独立監視の動作回数0、エンコーダ変動1 count、監視停止なし。
終了後も速度0、Fault=0、I/O正常、全軸指令0・StatusWord=5681を確認した。

接続検証の最初のバッチ起動はコマンド文字列の改行解釈で構文エラーになり、
実験コード実行前に終了した。出力を `disp` に変更して起動し直し、上記2回を検証した。
失敗ログも保持している。変更箇所の検証に絞り、全10往復と数値テスト全件は再実行していない。

- [自動接続2回の成功ログ](../data/acceleration_ff/20260908_1650_connection_check_retry/batch.log)
- [直接実行したバッチコマンド](../data/acceleration_ff/20260908_1650_connection_check_retry/batch_command.txt)
- [接続検証の終了コード](../data/acceleration_ff/20260908_1650_connection_check_retry/exit_code.txt)
- [接続検証中の独立監視](../data/acceleration_ff/20260908_1650_connection_check_retry/monitor.json)
- [接続検証後の実機状態](../data/acceleration_ff/20260908_1650_connection_check_retry/post_exit_state.json)
- [初回のコマンド構文エラー](../data/acceleration_ff/20260908_1650_connection_check/batch.log)

## 追記: Live Editorの起動パス・記法・可動域と速度

Live Editorが一時コピーから実行すると、スクリプト自身の `mfilename` から求めた
ルートがTemp配下になり、`config/config_tunable.m` を見つけられなかった。
プロジェクトの起動処理・パスに登録済みの `setup_project()` からルートを取得するよう修正した。
`ilc_experiment.m` に合わせて節見出し、代入、構造体、描画を整理し、各節の目的・
実機動作の有無・同定する4係数・出力の読み方を本文に記載した。古い実行エラーの保存表示も除いた。

ユーザー指定により、距離を1.25 m、終点を66,600,000 countに変更。
指定された可動域上限66,655,810 countまで5.581 mmを残し、Homing許容差と
追従誤差の余裕も開始前に検査する。最大速度はneo実験の2.0 m/sを基準とした。
同定は1.0・1.5・2.0 m/sの各2軌道、比較は1.25・1.75 m/s。
片道時間は指定速度から算出し、サンプリング後のピーク速度が指定値を超えないことを検査する。

`tests/test_acceleration_ff.m` の `testStartupFromTemporaryCopy` を追加し、
実際の準備節を一時フォルダーへコピーして実行する回帰テストに成功。
現行4 kHzで最大生成速度は約1.999 m/s、最大加速度6.235 m/s²、
各軌道25,725–35,443点で固定バッファ内。名目安定・感度1.511372も確認した。
MATLAB構文エラーなし。`rebuildTarget=false` により無効なビルド分岐に対する
Code AnalyzerのUNRCH通知は残る。

検証範囲は設定・軌道生成までで、実機接続・再ビルド・新条件での往復は実施していない。
上の全10試行成功とFF改善値は旧設定（0.84 m・低速）の結果であり、新条件への保証ではない。

## 追記: ILC教師取得の実機確認

学習FF単独を2 A未満に制限する `Learned FF must leave capacity for feedback.`
の判定を削除した。FBとFFが逆符号なら、FF単独の大きさから総電流飽和は判定できない。
FF 2.2 A・合計1.8 Aを許可し、合計2 Aは拒否する対象テストを確認済み。
有限値・既存の候補FF上限 `2*MAX_INPUT`・実機総電流2 Aの制限は保持した。
Live Editorに保存されていた同じ旧エラーの表示も除いた。

4 kHz、距離1.25 m、既存FB・Qフィルタ、明示Targetによる自動接続で次を実行した。
途中で失敗した実行は `passed=false` のまま保存し、教師として採用していない。

| 条件 | 実測結果 | 停止理由 |
| --- | --- | --- |
| 1.0 m/s、warp −0.65 | 3試行目の移動中RMS約24 µm、総電流2 Aが10点（2.5 ms） | 総電流飽和 |
| 1.0 m/s、warp +0.65 | 7試行すべて欠落・飽和なし、移動中RMS 223 → 7.6 µm、7試行目最大電流1.955 A | 8試行目前の開始位置が系列開始から101 µm変化 |
| 2.0 m/s、warp +0.65 | 2試行目の学習FF最大2.120 A、総電流2 Aが59点（14.75 ms）、最大追従誤差228 µm | 総電流飽和 |

1.0 m/s、warp +0.65の直近4試行RMSは9.9、6.9、8.8、7.6 µm。
直近3更新のFF変化は最大2.36%、最後の残留FB/FFは0.43%だったが、
現行の誤差RMS相対変化5%条件には達していない。収束判定は変更していない。
各試行の相対位置原点は更新され、終端誤差が各回100 µm以内でも絶対開始位置のずれが累積した。

各実行はMATLAB終了コード1。独立監視の可動域・追従・Faultによる中断はなく、
終了後にADSで `p_active=p_servo=0`、全4軸トルク0、StatusWord=5681、
速度0、Fault=0、I/O正常、周期250 µsを確認した。制御器・モデルの再ビルドはしていない。
**ILC教師6本の採用、係数同定、未学習軌道の比較は未完了。**

- [1.0 m/s負warpの履歴](../data/acceleration_ff/20260908_183133_265_training/20260908_183134_139_profile_01_ilc_teacher/teacher_failed.mat)
- [1.0 m/s正warpの履歴](../data/acceleration_ff/20260908_184427_ilc_profile_diagnostic/20260908_184544_836_profile_02_ilc_teacher/teacher_failed.mat)
- [1.0 m/s正warpの監視結果](../data/acceleration_ff/20260908_184427_ilc_profile_diagnostic/monitor.json)
- [2.0 m/s正warpの履歴](../data/acceleration_ff/20260908_185331_ilc_highspeed_diagnostic/20260908_185445_771_profile_06_ilc_teacher/teacher_failed.mat)
- [2.0 m/s正warpの実行ログ](../data/acceleration_ff/20260908_185331_ilc_highspeed_diagnostic/matlab.log)
- [2.0 m/s正warpの監視結果](../data/acceleration_ff/20260908_185331_ilc_highspeed_diagnostic/monitor.json)

### 開始位置補正と最初の教師の採用

累積した開始位置のずれが100 µmを超えた場合は、既存の停止・切断処理を通し、
`home_to_start` で系列開始位置へ戻してから同じTargetへ自動再接続するよう修正した。
学習FFと反復番号は引き継ぎ、補正後も既存の100 µm条件を確認する。
この分岐はexp05の教師取得だけで使い、補正前後とHomingの結果を `history.rehoming` に保存する。

1.0 m/s・warp +0.65をFF=0から実行し、7試行後の累積ずれ104.2 µmを自動補正した。
補正後の位置誤差は28.6 µm。8試行目のログは送信済み学習FFと一致し、
現行の収束条件（誤差変化5%、FF変化5%、残留FB比20%）を満たした。
誤差RMSの相対変化2.37%、FF変化2.60%、最終残留FB/FF比0.585%。
最終全区間RMS 8.083 µm、最大誤差49.4 µm、最大電流1.944 A。
全8試行の欠落・飽和は0。`result.mat` の `passed=true`、`teacher.converged=true` を確認した。

MATLAB終了コード0、対象の既存ILC契約テスト1件成功。
独立監視は補正Homingを含む9回の動作を確認し、監視中断なし。
終了後のADS状態は全軸無励磁・トルク0・Fault=0・速度0。
収束判定・電流上限を変更せず、教師を1本取得できた。全体の完遂は引き続き未完了。

- [採用済み教師と補正履歴](../data/acceleration_ff/20260908_190200_ilc_rehoming_check/20260908_190326_074_profile_02_ilc_teacher/result.mat)
- [実行ログ](../data/acceleration_ff/20260908_190200_ilc_rehoming_check/matlab.log)
- [独立監視](../data/acceleration_ff/20260908_190200_ilc_rehoming_check/monitor.json)
- [実行終了後のADS状態](../data/acceleration_ff/20260908_190200_ilc_rehoming_check/post_exit_state.json)

### 残りの未確認軌道

現行の途中飽和停止条件を保ち、未確認だったprofile 3・4・5を各FF=0から実行した。
各系列は2試行目に総電流2 Aを記録して停止した。全試行の欠落は0。
系列間に停止・無励磁を確認してから、次の未確認軌道を取得した。

| Profile | 最大速度・warp | 総電流飽和 | 学習FF最大 | 最大追従誤差 |
| --- | --- | --- | --- | --- |
| 3 | 1.5 m/s・−0.65 | 15点 / 3.75 ms | 2.013 A | 248.1 µm |
| 4 | 1.5 m/s・+0.65 | 16点 / 4.00 ms | 1.978 A | 182.0 µm |
| 5 | 2.0 m/s・−0.65 | 77点 / 19.25 ms | 2.153 A | 219.0 µm |

収集用バッチ自体は終了コード0だが、上記3系列の実験結果は失敗として保持した。
`COLLECTION_FINISHED` は診断バッチの終了であり、実験全体の正常終了を意味しない。
独立監視は6往復を記録して正常終了し、最終ADS状態は位置54,100,571 count、
速度0、全4軸無励磁・トルク0、Fault=0、I/O正常、周期250 µs。

6軌道のうち採用済み教師はprofile 2の1本。残る5軌道は途中飽和で未採用。
開始位置の補正・自動再接続は実機確認済みで、残る判断は途中飽和を許す学習にするか、
途中飽和を許さず軌道を調整するかである。ユーザーへ問い合わせ中のため、
飽和判定と軌道設定は変更していない。係数同定・未学習軌道比較は未実施。

- [採用済み教師の一覧・設定と未採用profile](../data/acceleration_ff/20260908_190726_ilc_remaining_profiles/training_progress.mat)
- [3系列の実測要約](../data/acceleration_ff/20260908_190726_ilc_remaining_profiles/capture_summary.json)
- [実行ログ](../data/acceleration_ff/20260908_190726_ilc_remaining_profiles/matlab.log)
- [独立監視](../data/acceleration_ff/20260908_190726_ilc_remaining_profiles/monitor.json)
- [最終ADS状態](../data/acceleration_ff/20260908_190726_ilc_remaining_profiles/post_exit_state.json)

### 途中の飽和を許すILCへ変更

上の問い合わせに対し、ユーザーが「途中の飽和を許してILCを続ける」を選択した。
全反復に対する飽和停止を除き、各試行の飽和点数を `teacher.saturatedSamples` に保存する。
最新試行が飽和している間は収束・採用とせず、既定の最大試行数まで学習を続ける。
最終教師・比較試行の飽和拒否、実機総電流2 A、候補FFの既存4 A上限、
欠落・追従・終端・可動域・停止確認は維持した。
2 Aを超える計測値は配備した電流上限と矛盾するためエラーにする。

`testTeacherConvergenceAndCaptureRejection` を更新して対象1件に成功した。
途中試行だけが飽和した履歴は採用可能、最新試行が飽和した履歴は未収束、
2.01 Aを記録した履歴は不正とすることを確認した。
取得済みprofile 2を保持して残る5軌道の再取得を開始した。

### 途中飽和を許可した再取得の結果

残る5軌道で計59試行を実施した。全試行の記録カウントは連続し、欠落は0。
追従誤差は減少したが、最終試行にも総電流指令の飽和が残り、追加教師は採用できなかった。
profile 5・6は次回候補FFが既存の4 A上限を超えたため、その候補を送信する前に停止した。

| Profile | 完了試行数 | 最終移動中RMS | 最終総電流指令の飽和点数 | 学習の停止理由 |
| --- | --- | --- | --- | --- |
| 1 | 15 | 3.91 µm | 12 | 最大反復数 |
| 3 | 15 | 7.57 µm | 27 | 最大反復数 |
| 4 | 15 | 5.70 µm | 51 | 最大反復数 |
| 5 | 6 | 18.34 µm | 138 | 次回候補FF > 4 A |
| 6 | 8 | 14.06 µm | 129 | 次回候補FF > 4 A |

各系列の最終評価は飽和を検出して `passed=false` を保存した。
バッチは `Accepted 1/6 teachers; inspect failed profiles.` で終了コード1。
マップ同定と未学習軌道比較には進んでいない。
独立監視は開始位置補正を含む65回の動作を記録し、監視による中断なし。
終了後は位置54,101,861 count、速度0、全4軸無励磁・トルク0、Fault=0、
I/O正常、周期250 µs、`p_active=p_servo=0` をADSで確認した。

- [各系列の数値要約](../data/acceleration_ff/20260908_191401_ilc_allow_intermediate_saturation/capture_summary.json)
- [採用済み教師と未採用系列](../data/acceleration_ff/20260908_191401_ilc_allow_intermediate_saturation/training_progress.mat)
- [実行ログ](../data/acceleration_ff/20260908_191401_ilc_allow_intermediate_saturation/matlab.log)
- [独立監視](../data/acceleration_ff/20260908_191401_ilc_allow_intermediate_saturation/monitor.json)
- [終了後の状態](../data/acceleration_ff/20260908_191401_ilc_allow_intermediate_saturation/post_exit_state.json)

### エンコーダ値のホールドに関する診断

ユーザーからエンコーダのホールド疑いが示されたため、追加運転をせずに保存波形と
停止中のADS入力を調べた。モデル・PLC・端子設定の変更や再Activateは実施していない。

- 上の59試行について、参照速度の絶対値が両端で0.05 m/sを超える731,168区間を確認した。
  row8の絶対位置を0.1 µm/countに戻した隣接差分が0の区間、参照と逆方向の区間はいずれも0。
  250 µsの記録周期で位置値が保持される現象は、この移動区間では確認できなかった。
- profile 1・15試行目の飽和位置6.392928 m付近でも、99区間すべてで位置は更新された。
  1周期あたりの変化は−2,157～−2,094 countで、総電流指令が−2 Aに制限される間も連続している。
- 停止中のPLC入力100回では、raw位置・公開位置は54,101,862～54,101,863 count。
  Ready=true、Error=false、TxPDO State=false、WcState=false、Fault=0。
  EtherCATのInputToggleは変化していた。
- 実機からEL5042を固定アドレス1002、ProductCode=0x13B23052として確認した。
  EtherCAT状態はOP、リンク異常なし。約3秒間隔の2回の診断で端子CRCエラーと
  マスタのcyclic/acyclic lost-frameカウンタはいずれも0だった。

現在の `encoderInputToggle` の接続先は `WcState^InputToggle` であり、
EL5042の `Status^Input cycle counter` ではない。したがって通信の更新停止を監視していても、
エンコーダ測定値の更新をこのカウンタで直接監視しているわけではない。
[EL5042公式仕様](https://infosys.beckhoff.com/content/1033/el5042/4217312267.html)では、
Input cycle counterは新しい測定値で増加する2ビット値とされている。

このカウンタ（CoE 0x6000:0F）を約2.37秒間に60回直接読み出すと、すべて3だった。
同じ取得中の位置（0x6000:11）は54,101,864～54,101,865 countに変化した。
非同期のCoE読出しは250 µs周期のPDO記録ではなく、2ビット値の周回もあるため、
この結果だけからカウンタ停止やエンコーダ故障を断定しない。
制御周期ごとのInput cycle counterと位置の同時記録は未実施であり、残る確認点とする。
また、今回の確認だけでは瞬間的な読取り異常や機械的な引っ掛かりの有無は確定できない。

- [59試行のホールド走査](../data/acceleration_ff/20260908_191401_ilc_allow_intermediate_saturation/encoder_hold_scan.json)
- [飽和位置付近の波形](../data/acceleration_ff/20260908_193415_encoder_diagnostic/encoder_near_saturation.png)
- [停止中のPLC入力](../data/acceleration_ff/20260908_193415_encoder_diagnostic/idle_encoder_samples.json)
- [EL5042のCoE入力](../data/acceleration_ff/20260908_193415_encoder_diagnostic/coe_encoder_samples.json)
- [EtherCAT通信診断](../data/acceleration_ff/20260908_193415_encoder_diagnostic/ethercat_diagnostics.json)

#### PDOの直接読出しによる追加確認

開いているTwinCATプロジェクトから、EL5042 Ch.1のStatusとPositionのADSアドレスを
読取り専用で取得した。Statusはport 11 / IG 0x03040020 / offset 0x80000093、
その直後のPositionはoffset 0x80000095。連続する10バイトを読み、同じ読出しのStatus上位2ビットと
64ビット位置を取り出した。約0.52秒間の200回でカウンタ0・1・2・3を確認した。
停止中の位置は54,101,867 countで一定でも、端子からの測定データ更新は続いている。
CoE読出しで3が続いた結果を、更新停止の証拠として扱わない。
port 11はADS周期通知をサポートしなかったため、250 µs周期のカウンタ記録は実施できていない。

StatusのDiagビットが立っていたため、CoE 0x10F3の履歴を消去・確認済み操作なしで保存した。
端子と同じProductCode/Revisionのインストール済みBeckhoff ESIでText IDを解釈した結果、
エラー2件は2026-08-31 12:23:05 JSTのCh.2 Watchdog / Single-Cycle-Dataエラーだった。
使用中Ch.1の診断0xA008は電源あり・データ有効・Error/SCD Error/WD Errorなし。
今回の実験に対応する新しいCh.1エラーは、この保持履歴には見つからなかった。
Diagビット自体は未確認の履歴があることを示し、現在のCh.1入力無効を意味しない。

位置ログのホールドなし・現在のPDOカウンタ更新・Ch.1の有効性を根拠に、
既存保護を維持してILCの学習帯域の検証へ進む。モデルや端子の再配備は行わない。

- [PDO Status/Positionの直接読出し](../data/acceleration_ff/20260908_193415_encoder_diagnostic/pdo_encoder_samples.json)
- [診断履歴とESIによる解釈](../data/acceleration_ff/20260908_193415_encoder_diagnostic/diag_history_decoded.json)
- [読出し用アドレス取得](../data/acceleration_ff/20260908_193415_encoder_diagnostic/read_io_address.ps1)

### Qフィルタ40 Hzでの高速教師取得

420 Hzの失敗履歴を調べると、総電流指令が±2 Aに制限される局所で学習FFが積み上がっていた。
保存FFの帯域を変えたオフライン解析を行い、距離・速度を変えずにQの帯域を40 Hzへ調整して
profile 6（最大1.999052 m/s、距離1.25 m）をFF=0から再取得した。
学習則・フィルタ次数・学習率・収束条件・4 A候補上限・実機2 A上限は維持した。
FB・プラント・モデル周期を変えていないため、再ビルド・Activateは実施していない。

10試行で既定の収束条件に達した。全試行で飽和・欠落0。
最終全区間RMS 11.750 µm、移動中RMS 17.853 µm、最大誤差92.0 µm、
最大総電流指令1.786814 A。誤差変化4.042%、FF変化1.193%、残留FB/FF約4.25%。
送信FFとrow7の1サンプル遅延照合にも合格し、保存結果は `passed=true`、`teacher.converged=true`。
独立監視は2回のHomingを含む12動作を確認して中断なし。
終了後は全4軸StatusWord=5681・トルク指令0、速度0、Fault=0、`p_active=p_servo=0`。

診断バッチは取得後のassertで `teacher.converged` を参照する誤りがあり、終了コード1となった。
正しい参照は `trialResult.teacher.converged`。保存済み結果を直接読み、上記の合格状態と
波形照合を確認した。取得自体を再実行せず、後続の収集バッチでは参照を修正した。
診断バッチの終了コード0や、実験全体の完了とは扱わない。

入口のFcと起動テストの期待値を40 Hzに変更した。
更新後の `testStartupFromTemporaryCopy` 1件は同じ後続MATLABセッションで成功した。
既に取得したprofile 6を再利用し、40 Hzで残る5軌道の取得を開始した。

- [高速教師の検証結果](../data/acceleration_ff/20260908_195525_ilc_bandwidth_40Hz/verified_result.json)
- [高速教師と10反復履歴](../data/acceleration_ff/20260908_195525_ilc_bandwidth_40Hz/20260908_195723_506_profile_06_ilc_teacher/result.mat)
- [終了後のADS状態](../data/acceleration_ff/20260908_195525_ilc_bandwidth_40Hz/post_exit_state.json)
- [後続収集の実行ログ](../data/acceleration_ff/20260908_200225_ilc_40Hz_collection/matlab.log)

### 40 Hzでの実機実行（精度要件の完了判定は撤回）

入口の準備節、同じ教師取得処理、入口の同定・比較節を実行し、
`ACCELERATION_FF_COMPLETE: 6 training runs, 4 comparisons, map 243/243 valid.` を確認した。
実機バッチはMATLAB終了コード0。40 Hzで確認済みのprofile 6を再利用し、
残る5軌道を新たに取得した。距離1.25 m、最大速度1.0・1.5・2.0 m/s、4 kHz、
既存FB、2 A上限、元の収束条件で実施し、Target選択・確認操作は不要だった。

| 教師 | 最大速度 [m/s] | warp | 反復数 | 最終全区間RMS [µm] | 最終最大電流指令 [A] |
| --- | --- | --- | --- | --- | --- |
| 1 | 1.0 | −0.65 | 7 | 20.27 | 1.5053 |
| 2 | 1.0 | +0.65 | 10 | 21.62 | 1.5205 |
| 3 | 1.5 | −0.65 | 9 | 16.09 | 1.5832 |
| 4 | 1.5 | +0.65 | 9 | 17.12 | 1.6139 |
| 5 | 2.0 | −0.65 | 14 | 12.20 | 1.7508 |
| 6 | 2.0 | +0.65 | 10 | 11.75 | 1.7868 |

全6教師で `passed=true`、収束判定を再評価しても合格。
計59反復の飽和・欠落は0。最終送信FFとrow7の1サンプル遅延も一致した。
教師はILCの適用FFであり、FBのみの総電流を混ぜていない。
同定した243地点の4係数はすべて有限値で、同じマップを学習に使わなかった2軌道へ適用した。
通常FFの係数は0のため重複する試行を省き、FBのみとマップFF（gain=1）の計4回を比較した。

| 未学習軌道 | 方法 | 全区間RMS [µm] | 加減速中RMS [µm] | 最大誤差 [µm] | 最大電流指令 [A] |
| --- | --- | --- | --- | --- | --- |
| 1.25 m/s | FBのみ | 199.15 | 267.38 | 661.8 | 1.7662 |
| 1.25 m/s | マップFF | 137.55 | 193.09 | 605.8 | 1.8728 |
| 1.75 m/s | FBのみ | 248.07 | 362.29 | 948.7 | 1.8602 |
| 1.75 m/s | マップFF | 167.89 | 261.32 | 910.5 | 1.9552 |

全区間RMSはそれぞれ30.93%、32.32%減少した。4比較とも飽和・欠落0で `passed=true`。
今回確認したのはこの2軌道・1回ずつの比較であり、他の速度や負荷での性能を保証するものではない。

比較表では文字列 `"VariableNames"` が名前引数として解釈されず余分な列になっていたため、
入口の該当箇所を文字ベクトル `'VariableNames'` に修正した。
実機を動かさず、修正した入口の表作成コードを保存済み4計測に適用した。
4行7列と列名・対応値を検査し、`comparison.mat` と `execution_result.mat` の表を更新した。
元の表は `comparison_before_column_fix.mat` に保持し、修正後の表はCSVにも書き出した。
このオフライン検証も終了コード0で `OFFLINE_AUDIT_COMPLETE` を確認した。

終了後の実機は位置54,100,632 count、速度0、Fault=0、I/O正常、周期250 µs。
全4軸StatusWord=5681・トルク指令0、`p_active=p_servo=0`。
独立監視は今回の収集・比較で59動作を記録して中断なし。診断用の先行profile 6は別に12動作。
MATLABバッチと監視プロセスの終了も確認した。

今回の59教師反復の移動714,084区間と、4比較の46,624区間で位置値のホールドは0だった。
判定対象は参照速度の絶対値が両端で0.05 m/sを超える隣接区間。
終了後もCh.1のデータは有効で、Error/SCD Error/WD Errorは0、診断履歴の最新番号は10のまま。
端子の周期カウンタの250 µs記録は未実施だが、直接PDO読出しでその更新は確認済み。

- [完了条件と実測値の監査結果](../data/acceleration_ff/20260908_200225_ilc_40Hz_collection/completion_audit.json)
- [収束と比較の図](../data/acceleration_ff/20260908_200225_ilc_40Hz_collection/experiment_summary.png)
- [教師ファイル一覧・設定](../data/acceleration_ff/20260908_200225_ilc_40Hz_collection/training_progress.mat)
- [同定マップ](../data/acceleration_ff/20260908_201411_216_map/acceleration_map.mat)
- [修正済み比較表](../data/acceleration_ff/20260908_201412_790_comparison/comparison.csv)
- [実機バッチの最終結果](../data/acceleration_ff/20260908_200225_ilc_40Hz_collection/execution_result.mat)
- [最終ADS状態](../data/acceleration_ff/20260908_200225_ilc_40Hz_collection/post_exit_state.json)
- [位置ホールドの最終走査](../data/acceleration_ff/20260908_200225_ilc_40Hz_collection/encoder_hold_audit.json)

### 精度低下の撤回と420 Hzでの飽和補正

ユーザーの「精度を犠牲にしない」という指定に従い、40 Hz化と精度要件の完了判定を撤回した。
同じprofile 2では420 Hzの全区間RMS 8.083 µm・最大誤差49.4 µmに対し、
40 Hzでは21.617 µm・152.5 µmへ悪化していた。飽和なし・誤差変化の収束だけでは精度の合格根拠にならない。
入口と起動テストを420 Hzへ戻した。距離、最高速度、2 A上限、既存の停止・収束条件は維持した。

教師取得のILC更新に限り、飽和した総電流指令と `row7 + C*e` の差を基準FFへ反映する。
ログの1サンプル遅延を戻して、実機へ出せなかった指令を次の反復へ積み上げない。
非飽和サンプルと、FBが打ち消して総電流が上限未満になるFFは変更しない。
補正後も420 HzのQフィルタ、元の学習率と25 ms端処理を使う。
実装は `src/remove_ilc_saturation.m`、呼出しはexp04の既存ループに置いた。
exp04の通常ILC経路は元の更新を維持する。

起動と飽和補正の対象テスト2件が成功した。保存済み420 Hzの5軌道の最終試行では、
非飽和時のFB再構成誤差は最大2.6e-11 A。補正した次候補の最大FFは2.02–2.28 Aで、
元の候補2.25–4.18 Aから未出力分の積み上がりが除かれた。
診断出力用の構造体配列への代入でオフラインバッチが2回失敗したが、セル配列へ修正後、
保存波形の検証は終了コード0。成功済みのテストは再実行していない。

その後、profile 6をFF=0から最大15試行まで実機取得した。最高速度1.999052 m/s、距離1.25 m。
比較する過去の結果も同じ参照軌道だが、別時刻の取得であり反復数も異なる。

| 設定 | 試行数 | 最終全区間RMS [µm] | 移動中RMS [µm] | 最大誤差 [µm] | 最終FF最大値 [A] | 最終飽和点数 |
| --- | --- | --- | --- | --- | --- | --- |
| 元の420 Hz | 8 | 11.30 | 14.06 | 112.0 | 3.978 | 129 |
| 40 Hz（採用撤回） | 10 | 11.75 | 17.85 | 92.0 | 1.725 | 0 |
| 420 Hz＋未出力分の補正 | 15 | 9.81 | 14.74 | 113.0 | 2.126 | 114 |

FF候補4 A超による途中停止を回避し、15試行まで学習できた。
全区間RMSは改善した一方、最大誤差まで改善したとはいえない。最終飽和は114点、合計28.5 ms、
最長連続5.0 ms。誤差変化5.664%も5%の収束条件を満たさない。
最終飽和の検査で `NikonMotor:CurrentSaturated`、MATLAB終了コード1となった。
`passed=false`、教師未採用。同定・未学習軌道の比較には進めておらず、実験全体は未完了である。
帯域縮小や精度・収束条件の緩和で成功扱いにすることはしない。

全15試行で欠落・順序異常・移動中の位置ホールドは0。1回の開始位置補正を含む16動作を
独立監視し、監視中断なし。終了後の実機位置54,101,436 count、速度0、Fault=0、I/O正常。
全4軸StatusWord=5681、各トルク指令0、実Targetの `p_active=p_servo=0` をADSで再確認した。
実験バッチと独立監視は終了済み。モデル・FB・PLCの再ビルドや再Activateは行っていない。

- [実測精度と飽和の比較](../data/acceleration_ff/20260908_203715_ilc_420Hz_saturation_correction/accuracy_audit.json)
- [比較波形](../data/acceleration_ff/20260908_203715_ilc_420Hz_saturation_correction/accuracy_comparison.png)
- [オフライン検証](../data/acceleration_ff/20260908_203715_ilc_420Hz_saturation_correction/offline_audit.json)
- [15試行の保存結果（未採用）](../data/acceleration_ff/20260908_203715_ilc_420Hz_saturation_correction/20260908_204300_914_profile_06_ilc_teacher/result.mat)
- [終了後の実Target状態](../data/acceleration_ff/20260908_203715_ilc_420Hz_saturation_correction/post_exit_state.json)
