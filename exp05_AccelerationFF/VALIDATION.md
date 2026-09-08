# 検証範囲：2026-09-08

## 実行した検証

`python tests/verify_acceleration_math.py`：9件成功。
軌道の端点・単調性、解析的導関数、往復加速度の符号、4係数回帰の回復、
加速度共線性の検出、局所多項式微分、ログ遅延、FF先行処理、候補軌道の内点ランクを検証した。
実行出力は `numerical_verification.txt`。

この検証はMATLABと同じ基礎式を独立にNumPyで計算したもの。
MATLABソースの実行、Simulink、ADS接続、ILC実行、実機安全動作の検証ではない。
候補軌道の内点ランク検査も、全位置で全識別条件を満たす保証ではない。

## ILCを含めて作成したが未実行

`tests/test_acceleration_ff.m`：MATLAB関数テスト23件。
本作成環境にMATLABがないため、合格とは記載しない。

追加したILC関連コード：

- `src/+accelff/ilc_update.m`：既存Demo 4の1反復学習則を独立関数化。
- `src/+accelff/accept_ilc_teacher.m`：誤差plateau、FF変化、残留FBから教師採否を判定。
- `src/+accelff/summarize_ilc.m`：未学習軌道で初期FF別のILC収束を比較。
- `exp05_AccelerationFF/plan_ilc_sequences.m`：train教師ILCとheld-out収束比較の系列計画。

現地MATLABで、`accelff.ilc_update` と
`exp04_ILC/obtainMeasurement.m` の同一入力に対する `fNext` の数値一致を追加検証する。
一致確認前に新runnerでteacher ILCへ進まない。

## 教師信号の変更

初版PRではtrainをFB走行の**総電流指令（ログ3行目）**から作る設計だった。
ILCを卒論手法の核として保持するため、現在のPRではこれを廃止した。

trainの回帰対象は、収束したteacher ILCの**学習FF（ログ7行目）**。
総電流指令は `ILC FF + 残留FB` なので教師には混ぜず、ILC収束診断にのみ使う。
`src/+accelff/observations.m` はtrainについて `ilc_ff_A` 以外を拒否する。

## 実施していないこと

Simulink/TwinCATのビルド、Activate、Homing、励磁、teacher ILC、held-out ILC、
実機収録、独立監視アダプタ接続、非常停止／通信断の故障注入、卒論FFとの実機性能比較。
既存ILCやFBの全件テストも、本追加の確認とは分けて扱う。

## 現地で確定する項目

卒論比較器の元実装と係数、4 kHzでのILC FF→機械応答の時間整合、
監視プロセスの問い合わせと鮮度確認、承認済み運転上限、
固定子上／間欠部の区間、各軌道で有効な同定範囲、
teacher採用閾値、held-out ILCの固定target RMS。

現行構成の根拠は既存の `exp04_ILC/obtainMeasurement.m`、
`docs/ff-verification-2026-09-08.md`、`config/sample_rate.m`、
`src/capture_tunable_trajectory.m`、`twincat/MotorRuntime/POUs/PRG_MotorRuntime.TcPOU`、
`config/copley/magnetic_pole_references.json`。
これらの過去の成功記録を、新規コードの実機検証結果として転用しない。
