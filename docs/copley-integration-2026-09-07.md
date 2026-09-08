# 2026-09-07: CopleyTest統合と実機FF検証

## 統合内容

`C:\Users\AKZW\source\repos\CopleyTest` の現在の作業ツリーを
[`CopleyTest/`](../CopleyTest/README.md) に取り込んだ。
元リポジトリと既存の未コミット変更は保持している。履歴の移植やコミットは行っていない。
TwinCATの2つのPLC、仮想CST構成、磁極参照、MATLABパッケージ、設定例、手順を含む。
外部のYT Scopeプロジェクト参照は統合先のソリューションから除去した。

`setup_project` は親の `src` と `CopleyTest/MATLAB` をMATLAB pathへ追加する。
実機接続・励磁・ビルドは行わない。通常FFの取得とHomingは既存の親プロジェクトを使用する。
PLC、制御器、Simulinkモデル、サンプル周期、電流上限の変更は行っていない。

ローカルの `_Repository` に必要な配布物を配置した:

- `motor_config` 0.0.0.4
- `linear_exp_tunable_2025a` 0.0.0.36（実験で使用）
- `linear_exp_2025a` 0.0.0.44（無効なlegacyオブジェクトの参照解決用）

配布物、生成物、ライセンス、実機arming設定、過去のcommissioningデータはGit管理対象外。
ライセンスと実機arming設定はコピーしていない。別PCでは同版のモジュールと有効な
TF1400 runtime licenseが必要。磁極参照manifestの過去データへのリンクは出典であり、
元の実験データは移植元に保持する。

## 検証

- コピー後に変更していないソース113件のSHA-256一致を確認。
- VS2019で統合先ソリューションを開き、両PLCとTcCOM Objects、target NetId
  `192.168.10.3.1.1` を確認。Activateは行っていない。
- `ActivateTwinCATConfiguration.ps1 -PreflightOnly` 成功。
  今回は移植元の既存 `TrialLicense.tclrs` を `-TrialLicensePath` で読み取り、
  有効期限2026-09-15を確認した。ライセンス情報のコピー・再発行は行っていない。
- MATLAB R2025a Update 1、`runtests('tests/test_feedforward_experiment.m')`:
  9件成功、1件skip。skipはSymbolicライセンス事前判定によるもの。
  実験に使う軌道生成は直接実行し、23,662点を生成できた。
- 統合先の `testNewArchitectureUseCases` から
  `testAdsClientRejectsDirectOutputWrites` と `testFourAxisRegistrationManifestDryRun`:
  2件成功。後者はFakeMotorRuntimePortを使ったdry-runで、実機には書き込まない。
- 実際に使った4 kHzプラントと `fbDesign` について、名目閉ループ安定、
  実測FRDの感度ピーク1.51137（基準2未満）を確認。
- 実機で周期250 µs、I/O watchdog正常、Faultなし、4軸の登録有効フラグと
  登録値が統合したmanifestに一致することを確認。
- 外部モード接続と実機取得が成功。既存0.0.0.36の再ビルド・再Activateは不要だった。

## 実機実験

Homingは55,313,296 count付近から54,100,000 countへ実行し、54,099,637 countに到達。
到達誤差−36.3 µmで許容差100 µm以内。取得カウンタの連続性、電流上限、終了状態を確認した。
元の保存先は `data/homing/20260907_192015_Homing_Result_2026-09-07_5/Homing_Result_2026-09-07_5.mat`。

3回とも同じ軌道: 距離0.84 mの往復、`v_max=1 m/s`、`a_max=17 m/s²`
（軌道生成関数には `a_max/2` を渡す）、折返し待機1 s、前後待機各1.5 s、
`Ts=0.00025 s`、`MAX_INPUT=2 A`。
FFは `f = Kfa * traj.acc` に既存の8サンプル先行補償を適用。
`Kfj=Kfv=Kfc=0` とし、同定値 `Jn=0.0626780333` の10%と5%を比較した。

| 条件 | Kfa | FFピーク [A] | 誤差RMS [µm] | 誤差ピーク [µm] | 電流ピーク [A] | 上限到達点数 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| FBのみ | 0 | 0 | 356.398 | 1859.2 | 1.91499 | 0 |
| 加速度FF 10% | 0.00626780333 | 0.0799145 | 355.516 | 1947.1 | 2.00000 | 53 |
| 加速度FF 5% | 0.00313390167 | 0.0399572 | 361.508 | 2010.6 | 2.00000 | 63 |

全条件で10信号・23,662点を取得し、カウンタ欠落・逆転なし。
記録referenceとFFは、既存の `Reference/Delay2` / `Delay1` による
1サンプル遅延を考慮すると入力と完全一致した。
最終相対位置は順に2.8 / 2.9 / 3.4 µm。

記録内 `metrics.passed` は、点数・有限値・連続性・入力一致・電流上限、
ピーク誤差3 mm未満・終端誤差100 µm未満・取得後の無効化を確認するための判定。
FF性能向上や無飽和の判定ではない。10%・5%とも飽和があり、
今回の試験では追従改善を確認できなかった。係数最適化は未完了。
実験スクリプトの既定FF係数はすべて0のまま保持した。

最終確認: 全4軸TargetTorque=0、速度=0、Fault=0、I/O正常、
`p_active=p_servo=0`。各ControlWord=6（Shutdown）、各StatusWord=5681で
Operation Enabledビットは0。TwinCATはRunを維持した。

## 記録と再実行

データは [`data/ff/integration_20260907_191838/`](../data/ff/integration_20260907_191838/) に保存。
各MATに全計測値、軌道、FF、制御器、開始・終了状態、評価値を含む。
raw partも条件別に退避し、開始前に存在したraw partを `previous_raw/` に保持した。

- [集計JSON](../data/ff/integration_20260907_191838/summary.json)
- [比較図](../data/ff/integration_20260907_191838/comparison.png)
- [FBのみ](../data/ff/integration_20260907_191838/baseline.mat)
- [加速度FF 10%](../data/ff/integration_20260907_191838/acceleration_ff_10pct.mat)
- [加速度FF 5%](../data/ff/integration_20260907_191838/acceleration_ff_5pct.mat)

再実行はプロジェクトルートで `setup_project` を実行し、
[`feedforward_experiment.m`](../exp03_FF/feedforward_experiment.m) の設定と軌道生成節を実行する。
基準は全FF係数0。上表の条件を再現するときだけKfaを設定してFF計算をやり直す。
モデル・周期・固定バッファが同じならビルド節を飛ばし、Homingを含む実験節を実行する。
今回の2つの非ゼロ係数は調整候補の測定値であり、改善済みの推奨設定ではない。
次の性能調整では電流飽和を避ける軌道条件とFFの符号・大きさ・先行量を評価する。
