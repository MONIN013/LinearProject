# NikonMotorProject2025

MATLAB R2025aでルートの `setup_project` を実行する。共通関数をpathへ追加し、実機接続やビルドは行わない。
TwinCATは Visual Studio 2019で `twincat/NikonMotorProject2025.sln` を開く。

100 MiBを超える過去のFB計測MAT 2件はGit LFSで管理する。
クローン後は `git lfs install` と `git lfs pull` を実行して実体を取得する。
実機ライセンス、ローカルarming設定、TwinCAT生成物、`data/ff/integration_*/` の
生計測はGit管理対象外。今回の実験結果は `docs/ff-verification-2026-09-08.md` に記録した。

- `exp00_Commissioning/`: 磁極推定の操作。`config/copley/` に設定、`src/+copley/` に通信・推定処理。
- `exp01_SI/`、`exp02_FB/`、`exp03_FF/`、`exp04_ILC/`: 同定・FB・FF・ILC実験。
- `src/`: 取得、Homing、解析、保存の共通関数。
- `config/`、`simulink/`、`twincat/`: 実験設定、制御モデル、PLC。

通常FFはSimulinkから1本のトルク指令を出し、実軸選択と磁極参照は `twincat/MotorRuntime` が扱う。
磁極推定は専用のcommissioning手順とarmingを使用する。実行手順は [FF実験](exp03_FF/README.md)、磁極推定の入口は `exp00_Commissioning/magnetic_pole_commissioning_live.m`。
モデル・周期・固定バッファが同じなら、軌道・FF係数の変更で再ビルド・再Activateは不要。
停止処理、電流上限、通信保護、実験前後の状態確認は維持する。

## データ

結果は `data/<commissioning|si|fb|ff|ilc|homing>/<日時_実験名>/` に保存する。
MATの変数は明示的な構造体で `save_experiment_result` に渡す。生計測は同じrunの `raw/`、図は `figures/` に置く。
ILCの生計測は `raw/<速度>/trial_<番号>/`、途中結果は `ilc_progress_<速度>.mat` に保存する。
`simulink/data/` は取得中の一時置場とし、停止後に退避する。帰属不明の残存計測は `data/archive/` に保持する。

同定後はrunに `plant.mat` を保存してから、保存された `Ts` に対応する
`data/plants/4khz/current.mat` または `8khz/current.mat` を自動更新する。過去結果と他周期は保持する。
周期の選択は `config/sample_rate.m`。`config/data/` は設定・ビルド情報用。

旧データの内容・元ファイル名は保持し、対応は [migration.csv](data/migration.csv) に記録した。
移行した単独ファイルのrun日時はファイル更新日時に由来する。既存runの構成、失敗記録、重複候補も保持している。
元の試作リポジトリ `C:\Users\AKZW\source\repos\CopleyTest` は変更していない。
過去の実機結果は [統合記録](docs/copley-integration-2026-09-07.md) を参照。
