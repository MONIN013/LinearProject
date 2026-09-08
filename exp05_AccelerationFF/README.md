# 加減速区間を用いる位置依存FFの同定・比較実験

対象は `MONIN013/LinearProject`。確認したベースは
`0085d1d58e96c68fac4fa17cc9888d7889cb6c7b`（2026-09-08）。
追加コードは `src/+accelff/`。既存の制御器、ILC更新、Simulink、TwinCAT、電流上限は変更しない。
本変更は実機走行結果を含まない。現地のMATLAB検証・監視接続・操作者承認まではDraftとして扱う。

## 検証する命題

同じ位置を異なる速度・加速度で通過するデータから、電流換算のモデル

```text
i_cmd(x,v,a) = g(x) + b(x)*v + c(x)*sign(v) + alpha(x)*a
```

を同定する。係数順は `[g,b,c,alpha]`、単位は順に
`A, A*s/m, A, A*s^2/m`。入力に使うのは現行計測の**総電流指令**であり、
相別実電流・並列枝路電流・推力そのものではない。

比較対象はFBのみ、固定した卒論FF、加速度マップFF。同じ未学習軌道、同じFB、
同じ電流上限で比較する。加速度を含む前処理は既に検討済みであり、
本実装の目的は位置依存加速度係数を含む補償の実機比較を再現可能にすること。

現行 `exp03_FF/feedforward_experiment.m` の既定FF係数はゼロである。
これを勝手に「卒論手法」と呼ばない。卒論で実際に使用した係数・補間・遅延・
FF合成を現地で特定し、ファイルとパラメータを固定する。未発見なら比較器は未構成と報告する。

## 既存コードとの接続

| 対象 | 使用・確認方法 |
|---|---|
| `setup_project.m` | 共通パスの設定だけ。実機接続なし |
| `config/sample_rate.m` | 現行4 kHz。古い125 usデータと混ぜない |
| `config/data/pana_params.mat` | 電流上限、エンコーダ・速度・電流換算 |
| `src/load_experiment_plant.m`, `fbDesign` | 現行周期のプラントと既存FB。設計を変更しない |
| `src/capture_tunable_trajectory.m` | r/fを渡して1回取得。停止・待機・raw退避処理を再利用 |
| `src/home_to_start.m` | 必要な場合だけ独立監視下で事前に明示実行。runnerから自動実行しない |
| `src/tunable_trajectory_buffer_capacity.m` | 固定131072点。容量を変えない |
| `twincat/MotorRuntime` | 単一仮想CSTから実軸を選択。Simulinkに軸別ゲートを作らない |
| `config/copley/magnetic_pole_references.json` | 全4軸の磁極参照を読み取り照合。書き換えない |
| `docs/ff-verification-2026-09-08.md` | 1サンプルのログ遅延、2 A飽和、既存独立監視の記録 |

古いMATの `history.y_ab` と現行ILCの `history.y_absolute` は形式が違う。
本デコーダに古いhistoryを直接渡してはいけない。旧データの単位・周期・電流信号は別途監査する。

## 信号契約と遅延の区別

`capture_tunable_trajectory` の戻り値は10行×N点。

| 行 | 意味 | 単位・扱い |
|---:|---|---|
| 1 | 論理サンプルカウンタ | 整数、増分1。欠落を補間しない |
| 2 | 追従誤差 | m。行9−行5を照合 |
| 3 | 総制御入力 | A。電流換算同定に使用 |
| 4 | 計測速度 | m/s。生信号を保存 |
| 5 | 相対位置 | m |
| 6 | トルク／電流フィードバック | 生値を保持。枝路実電流とはみなさない |
| 7 | 記録したFF | A |
| 8 | 絶対位置 | m。位置マップの横軸 |
| 9 | 記録した参照 | m、相対位置 |
| 10 | 量子化参照 | 生計測に保持 |

`logging_delay_samples=1` は記録r/FFを入力波形と照合するための遅延。
`current_offset_samples` は**機械サンプルkと電流k+offsetを組にする**実測整合。
負なら前の電流と組にする。`advance` はモデルFFを出力する際の先行量。
この三つは異なる。8サンプルや40サンプルを無条件に転記しない。
`circshift`で信号末尾を先頭へ回さない。

## オフライン準備

```matlab
root = setup_project();
addpath(fullfile(root,'exp05_AccelerationFF'));
cases = plan_cases();  % 計画表だけ。実機には触れない
p = accelff.profile(0.84,6,0.65,0.00025,[1.5,1,1.5]);
plot(p.t,p.x);         % この数値は候補であり運転許可ではない
```

`profile` は5次位置関数と時間軸の変形から位置・速度・加速度・jerkを解析的に作る。
時間反転の復路では、同一位置における速度・jerkは符号反転し、加速度は同符号になる。
往復平均だけで加速度項を位置外乱から分離できるとは限らない。

`plan_cases` は学習6形状×3回、検証2形状×3手法×3回、最終評価2形状×3手法×3回を作る。
計54ケースだが、一括運転機能はない。試走・識別性評価を先に行い、必要な条件だけ実施する。
学習時は受理された低誤差・無飽和のFB試行の総電流指令を使う。
品質基準を満たさない場合、既存ILCによる追従改善は別の明示実験として扱い、
このrunnerへ未検証のILC更新を足さない。

取得済みの `result.trace` を次のように処理する。

```matlab
o = accelff.options();
o.current_offset_samples = calibratedOffset; % 校正記録に基づく値
o.alignment_reviewed = true;
obs = accelff.observations(trials, absolutePositionGrid, o);
model = accelff.fit_map(obs(obs.split=="train",:), absolutePositionGrid, o);
```

速度・加速度は絶対位置に対する局所3次多項式から求める。窓幅を保存し、端部を捨てる。
これはオフライン非因果処理であり、実時間フィルタではない。位置の並べ替えで逆行や反転を隠さない。
各試行の同じ位置・方向で1観測まで。同一軌道の反復は平均してから独立観測数を数える。

各位置でランク4、列スケーリング後の条件数、独立加速軌道数、残差自由度、
速度・方向・定数項で説明できない加速度成分を確認する。不成立位置は `valid=false, NaN`。
正則化でランク不足を隠したり、無効位置を補外して運転に使ったりしない。

微分窓・励起閾値は実験計画の設定であり、実機で最適と確認した値ではない。
ノイズ床、追従誤差、遅延、速度・加速度相関を確認して採用する。
閉ループデータの推定バイアスも残り得るため、係数の再現と未使用軌道の性能を分けて評価する。

## FF合成と実機入口

```matlab
limits = struct('velocity_floor',o.velocity_floor, ...
    'ff_A',reviewedFFBudget,'ff_slew_A_s',reviewedFFSlew);
[f, detail] = accelff.feedforward(model,origin_m+p.x,p.v,p.a, ...
    frozenBaselineFF,gain,p.Ts,calibratedAdvance,limits);
```

`baseline + weight*(modelFF-baseline)` として**総FFを置換**する。
`alpha*a` に慣性分が含まれるため、後から `Jn*a` を重ねない。
停止除外閾値以下ではbaselineを保持し、その上で連続的に提案値へ接続する。
移動中の無効位置・範囲外・隣接セルの速度／加速度範囲外は運転前にエラーとする。
個別min/maxは速度・加速度の**同時分布の凸包を保証しない**。新軌道の組合せは別に確認する。
上限超過はクリップせず拒否する。FF予算だけではFB加算後の無飽和を保証できない。

実機入口は `accelff.execute_case(job,cfg,"RUN "+job.id)`。
[CODEX_HANDOFF.md](CODEX_HANDOFF.md)の手順で現地に接続する。
`local_config_example` の未確認項目はNaN、独立監視probeは未接続で、そのままでは実行できない。
probeは既存の別プロセス監視を実際に問い合わせる現地アダプタ。定数trueの代用品は禁止。
取得中の安全をホストの事前・事後チェックや例外cleanupだけに依存させない。

## 比較と合否

runnerは生計測を保存し、波形一致、カウンタ、追従、終点、飽和、実位置範囲、
全軸無励磁、Fault、I/O、周期、磁極参照、p_active/p_servoを検査する。
加速・移動・ほぼ等速の区間は同じ**参照**から作り、実測追従の違いで評価区間を変えない。
`accepted` は品質条件を満たした意味であり、卒論FFより改善した意味ではない。

```matlab
summary = accelff.compare_cases({fbResult,thesisResult,accelerationResult});
```

明示した結果だけを比較し、同じprofile/repeatに3手法が必要。学習ケース、失敗、飽和、
別の参照・FB・上限を黙って除外／混合しない。RMS比だけで有意差を主張しない。
位置領域別の評価は実測した固定子上／間欠部の区間表を別途固定する。
PLCの鎖交マージンは物理的な固定子境界ではない。

## 物理解釈の限界

電流追従が十分速く、局所近似が成立し、質量が一定なら、概ね
`b=(B_mech+B_circ)/Kq`, `alpha=m/Kq` なので `b/alpha=(B_mech+B_circ)/m`。
ただし指令電流から得た係数には電流応答、遅延、軸切替などの影響も入り得る。
alphaが十分識別されゼロ近傍でない位置だけで比を見る。循環電流の存在や組立公差の直接証明ではない。

## 検証状態

```matlab
results = runtests(fullfile(root,'tests','test_acceleration_ff.m'));
assert(all([results.Passed]));
```

MATLABテスト19件は作成済み、作成環境にMATLABがないため**未実行**。
Pythonによる式の独立検証9件は実行済み。記録は [numerical_verification.txt](numerical_verification.txt)。

```text
python tests/verify_acceleration_math.py
```

Python成功はMATLAB、Simulink、ADS、安全動作の検証を意味しない。
既存全件テスト、モデル再ビルド、Activate、実機運転は本変更の作成時には行っていない。
