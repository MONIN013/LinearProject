# 2026-09-08: 統合先TwinCATによるFF実機確認

このリポジトリの `twincat/NikonMotorProject2025.sln` をビルド・Activateし、
FF実験の取得、0.84 m往復、停止を確認した。サブエージェントは使用していない。
共通取得関数で見つかった終了処理の警告を修正した。
電流飽和は残っており、FF係数の最適化やµm級追従の達成を意味しない。

## 構成と配備

- MATLAB R2025a、TwinCAT target `192.168.10.3.1.1`。
- 統合先ソリューションをVS2019の `/Build "Debug|TwinCAT RT (x64)"` でビルド。
  3プロジェクト成功または最新、失敗0・skip0。両PLCはエラー0・警告0。
  初回は生成TMCがなかったため、生成後に診断検査を実施した。
- `twincat/scripts/VerifyFeedbackDiagnostics.ps1` 成功。
  Feedback 20 bytes、LoggerSample 72 bytes、物理診断リンク10本。
- `ActivateTwinCATConfiguration.ps1 -PreflightOnly` 成功後、同スクリプトで
  統合先をActivate・再起動。ADSでRunへの復帰を確認。
  ライセンス検査は移植元の既存ファイルを読み取り、有効期限2026-09-15を確認した。
- Simulinkモジュールは既存 `linear_exp_tunable_2025a` 0.0.0.36、Object ID `0x01010020`。
  モデルの再生成・再ビルドは行っていない。外部モード接続成功。
- 実機周期250 µs、I/O watchdog正常、Faultなし。
  全4軸の磁極参照3フィールドと有効フラグが
  `config/copley/magnetic_pole_references.json` に一致。
- 現行4 kHzプラントと `fbDesign` を使用。名目閉ループ安定、実測感度ピーク1.511371854。

## 条件と計測

現行スクリプトと同じ `dist=0.84 m`, `v_max=1 m/s`, `a_max=17 m/s²`
（生成関数には `a_max/2`）、折返し待機1 s、前後待機各1.5 s、`Ts=0.00025 s`、
`MAX_INPUT=2 A`。FFは `Kfa=0.1*Jn=0.00626780333137952`、他係数は0、8サンプル先行。
設定ファイルとスクリプトの既定係数は変更していない。

開始位置は54,099,538 count。`home_to_start(54100000)` が許容差100 µm以内と判定し、
Homing移動を省略した。修正後の開始位置も54,099,351 countで許容差内。

| 条件 | 点数 | 欠落 | 誤差RMS [µm] | 誤差ピーク [µm] | 電流ピーク [A] | 2 A到達点数 | 最終相対位置 [µm] |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| FF係数0・修正前 | 23,662 | 0 | 368.244 | 2037.1 | 2.000 | 79 | 3.0 |
| 加速度FF 10%・修正前 | 23,662 | 0 | 353.828 | 1947.8 | 2.000 | 53 | 3.1 |
| 加速度FF 10%・修正後 | 23,662 | 0 | 354.206 | 1924.6 | 2.000 | 47 | 3.2 |

全試行で10信号、有限値、カウンタ連続を確認。記録referenceとFFは既存の1サンプル遅延を
考慮すると入力と完全一致。修正後の実位置ピークは0.840889 m。
独立ADS監視で位置範囲・追従誤差・Faultを確認し、監視による停止は発生しなかった。

`metrics.passed` は取得・往復・停止の判定。ピーク追従誤差3 mm未満、終端100 µm未満、
電流上限2 A以内を含む。無飽和やFFによる性能改善の合格判定ではない。

## 終了処理の修正と検証

修正前は正常取得後に、`onCleanup` のネスト関数が破棄済みの `finished` 変数を参照する
警告が2回発生した。通常の明示的停止処理は完了していたが、例外時のcleanupにも同じ問題があった。

`src/capture_tunable_trajectory.m` のcleanupを独立したローカル関数へ変更し、
必要な引数を匿名関数で保持する。正常に停止・保存した後はR2025aの `cancel` で
cleanupを解除する。停止順序、電流上限、待機時間、I/O保護は維持した。
この方式は [MathWorksのonCleanupの注意事項](https://www.mathworks.com/help/matlab/ref/oncleanup.html) と
[R2025aのcancel](https://www.mathworks.com/help/matlab/ref/oncleanup.cancel.html) に沿う。
変更はMATLAB取得側のみなので、再ビルド・再Activateは不要。

修正後の実機FFを1回実施し、cleanupのデストラクター警告が消えたことをログで確認。
検証スクリプトの全警告禁止判定は `Simulink:Data:CopyWillNotPreserveCodeProps` を検出して
取得後の集計を停止した。保存済みrawを別途読み直し、上表の判定を実施した。
この検証スクリプトの失敗は `failure.json` とログに保持し、再往復は行っていない。

さらに、reference 4点・FF 3点の不一致を意図的に与え、サーボ有効化前に
`NikonMotor:TrajectoryLengthMismatch` を発生させる検証に成功した。
例外後も `p_active=p_servo=0`、全軸無励磁で、cleanupのデストラクター警告なし。
独立監視では励磁を伴う実行0回、エンコーダ変動1 count、監視停止なし。
結果は下記の `summary.json` の `cleanup_error_check` と保存ログに記録した。
全件テストは実行せず、変更した取得関数の実機再確認と例外経路の確認に限定した。

最終状態はTwinCAT Run、全4軸TargetTorque=0、ControlWord=6、StatusWord=5681
（Operation Enabledビット0）、速度0、Fault=0、I/O正常、磁極参照一致、
`p_active=p_servo=0`。実験後は無励磁のまま停止している。

## 記録

- [修正前2条件の集計](../data/ff/integration_20260908_verify/summary.json)
- [修正後FFと例外cleanupの集計](../data/ff/integration_20260908_after_cleanup_fix/summary.json)
- [修正後FFのMAT](../data/ff/integration_20260908_after_cleanup_fix/acceleration_ff_10pct/acceleration_ff_10pct.mat)
- [修正後FFの図](../data/ff/integration_20260908_after_cleanup_fix/acceleration_ff_10pct/acceleration_ff_10pct.png)

各試行のraw、実行スクリプト、ログも同じrun配下に保持した。
実行スクリプトは当日の記録であり、再実行時は新しいrun/workディレクトリを使う。
通常の実験手順は [exp03_FF/README.md](../exp03_FF/README.md) を参照。

残課題は電流飽和とFF性能調整。通信断や非常停止の故障注入は今回実施していない。
