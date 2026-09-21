# NikonMotorProject2025

MATLAB R2025aでルートの `setup_project` を実行する。共通関数をpathへ追加し、実機接続やビルドは行わない。
TwinCATは Visual Studio 2019で `twincat/NikonMotorProject2025.sln` を開く。

`data/` 配下の結果MATをGit LFSで管理する。1条件の全試行・軸別ログを1個の結果MATにまとめる。
クローン後は `git lfs install` と `git lfs pull` を実行して実体を取得する。
実機ライセンス、ローカルarming設定、TwinCAT生成物はGit管理対象外。
今回の実験確認は [exp01〜06の検証記録](docs/experiments-verification-2026-09-21.md) に記録する。

- `exp00_Commissioning/`: 磁極推定の操作。`config/copley/` に設定、`src/+copley/` に通信・推定処理。
- `exp01_SI/`、`exp02_FB/`、`exp03_FF/`、`exp04_ILC/`: 同定・FB・FF・ILC実験。
- `exp05_AccelerationFF/`: [加減速を含む位置依存FFの同定・比較](exp05_AccelerationFF/README.md)。
- `exp06_AllocationTransfer/`: [2軸への電流配分を変えたFFの同定・比較](exp06_AllocationTransfer/README.md)。
- `src/`: 取得、Homing、解析、保存の共通関数。
- `config/`、`simulink/`、`twincat/`: 実験設定、制御モデル、PLC。

通常FFはSimulinkから1本のトルク指令を出し、実軸選択と磁極参照は `twincat/MotorRuntime` が扱う。
磁極推定は専用のcommissioning手順とarmingを使用する。実行手順は [FF実験](exp03_FF/README.md)、磁極推定の入口は `exp00_Commissioning/magnetic_pole_commissioning_live.m`。
モデル・周期・固定バッファが同じなら、軌道・FF係数の変更で再ビルド・再Activateは不要。
exp01〜06は共通の `linear_exp_tunable_2025a` を使う。SIの定数ゲイン、PID、通常FBは
同じ2次制御器の係数をMATLABから切り替える。固定バッファは800,001点で、4/8 kHzの100秒同定を収める。
停止処理、電流上限、通信保護、実験前後の状態確認は維持する。

## データ

結果は `data/<commissioning|si|fb|ff|ilc|acceleration_ff|allocation_transfer|homing>/` に集約する。
過去の単独MATは種別フォルダ直下に置く。生計測・結果・図など複数ファイルを扱う新規実験は `<日時_実験名>/` にまとめる。
途中保存は `save_experiment_result`、終了時の保存は `finalize_experiment_result` に明示的な構造体を渡す。
終了時に分割計測を `captures`、配分記録を `history.allocationLog`（比較試行は `allocationLog`）へ集約する。
`captures` は時刻と未保存の信号だけを持ち、ILC履歴や結果の信号を重複保存しない。
`[measurement, axisLog, time] = read_experiment_capture(load(resultFile), trialIndex)` で計測を復元できる。
`trialIndex` は `captures` の添字で、ILCの試行番号は各要素の `trial` に残る。
通常実験の図は結果MATと同じ場所に置く。
通常実験の取得・保存・解析はMATLAB側に集約する。リアルタイム取得には既存のSimulink File Writerを使い、
先頭10信号とPLCの4軸スナップショットを同じ30行のMATへ記録する。
読み込み後は従来の10行 `measurement` と `measurement_metadata.axisLog` に分かれる。
PLCは配分と現在値の公開を担当し、exp06専用の履歴バッファは持たない。
commissioningのレポート用SVGは相対リンクに合わせて `figures/` に置く。
取得中のILC計測は `raw/<速度>/trial_<番号>/`、途中結果は `ilc_progress_<速度>.mat` の1個に保存する。
結果MATの保存・再読込を確認した後、分割MATと途中結果は `.codex-temp/data-originals/` に退避する。
この退避先と実行用の一時スクリプト・作業ログはGit管理対象外。独立した計測や失敗試行は結果MAT内に残す。
`simulink/data/` は取得中の一時置場とし、停止後に退避する。開始前の残存計測は今回のrunの `raw/previous/`、
ILCでは `raw/<速度>/before_trial_<番号>/` に分けて保持し、今回の計測を上書きしない。`data/archive/` は自動作成しない。

同定後はrunに `plant.mat` を保存してから、保存された `Ts` に対応する
`data/plants/4khz/current.mat` または `8khz/current.mat` を自動更新する。過去結果と他周期は保持する。
周期の選択は `config/sample_rate.m`。`config/data/` は設定・ビルド情報用。

旧データの内容・元ファイル名は保持し、対応は [migration.csv](data/migration.csv) に記録した。
`exp04_ILC/data_4k/` に残っていた2026-08-31の結果14件も `data/ilc/20260831_4khz/` に集約済み。
実験フォルダ内には結果用の `data` / `data_4k` を作らず、ルートの `data/<実験種別>/` に保存する。
単独ファイルを包んでいた階層は平坦化し、失敗記録や重複候補も元のファイル名で保持している。
元の試作リポジトリ `C:\Users\AKZW\source\repos\CopleyTest` は変更していない。
過去の実機結果は [統合記録](docs/copley-integration-2026-09-07.md) を参照。
