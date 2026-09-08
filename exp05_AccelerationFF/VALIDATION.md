# 検証範囲：2026-09-08

## 実行した検証

`python tests/verify_acceleration_math.py`：9件成功。
軌道の端点・単調性、解析的導関数、往復加速度の符号、4係数回帰の回復、
加速度共線性の検出、局所多項式微分、ログ遅延、FF先行処理、候補軌道の内点ランクを検証した。
実行出力は `numerical_verification.txt`。

この検証はMATLABと同じ式を独立にNumPyで計算したもの。
MATLABソースの実行、Simulink、ADS接続、実機安全動作の検証ではない。
候補軌道の内点ランク検査も、全位置で全識別条件を満たす保証ではない。

## 作成したが未実行

`tests/test_acceleration_ff.m`：MATLAB関数テスト19件。
本作成環境にMATLABがないため、合格とは記載しない。

実機前に、現地でこのテストと必要なコード解析を行う。
ライブrunnerとADS状態確認はMATLABオフラインテストの対象外であり、別途確認する。

## 実施していないこと

Simulink/TwinCATのビルド、Activate、Homing、励磁、実機収録、
独立監視アダプタ接続、非常停止／通信断の故障注入、卒論FFとの実機性能比較。
既存ILCやFBの全件テストも、本追加の確認とは分けて扱う。

## 現地で確定する項目

卒論比較器の元実装と係数、指令電流と機械応答の時間整合、
監視プロセスの問い合わせと鮮度確認、承認済み運転上限、
固定子上／間欠部の区間、各軌道で有効な同定範囲。

現行構成の根拠は既存の `docs/ff-verification-2026-09-08.md`、
`config/sample_rate.m`、`src/capture_tunable_trajectory.m`、
`twincat/MotorRuntime/POUs/PRG_MotorRuntime.TcPOU`、
`config/copley/magnetic_pole_references.json`。
これらの過去の成功記録を、新規コードの実機検証結果として転用しない。
