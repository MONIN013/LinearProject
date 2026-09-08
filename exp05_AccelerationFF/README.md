# ILC教師と加減速区間を用いる位置依存FFの発展実験

対象は `MONIN013/LinearProject`。確認したベースは
`0085d1d58e96c68fac4fa17cc9888d7889cb6c7b`（2026-09-08）。
追加コードは `src/+accelff/`。既存のFB、Demo 4のILC学習則、Simulink、TwinCAT、
電流上限は変更しない。本変更は実機走行結果を含まない。現地のMATLAB検証・監視接続・
操作者承認まではDraftとして扱う。

## 実験の一本道

卒論手法では、各軌道に対してILCが反復外乱を打ち消すFFを学習し、その学習電流を
位置・速度に対して整理した。本発展では、**ILCを外さず**次の順で加減速区間まで使う。

1. 速度だけでなく、同じ位置を異なる加速度で通過する複数の学習軌道を用意する。
2. 各学習軌道で既存Demo 4と同じILCを収束させる。
3. 収束したILC FFを教師として、位置ごとに
   `g(x), b(x), c(x), alpha(x)` を同定する。
4. 未学習軌道へ一般化FFを一発適用し、FBのみ・卒論FFと比較する。
5. さらに同じ未学習軌道で、ゼロ／卒論FF／一般化FFを**ILC初期値**にして、
   同一学習則の収束速度を比較する。

したがってILCには二つの役割がある。学習データを作る **teacher ILC** と、
一般化FFが次のILCを何反復短縮できるかを見る **held-out ILC** である。

## 同定するモデル

各位置で、ILCが学習したFF電流を

```text
i_ILC(x,v,a) = g(x) + b(x)*v + c(x)*sign(v) + alpha(x)*a
```

と置く。係数順は `[g,b,c,alpha]`、単位は順に
`A, A*s/m, A, A*s^2/m`。

**回帰対象は収束したILCの学習FFである。** 現行10行ログでは7行目に対応する。
3行目の総制御入力は `ILC FF + 残留FB` なので教師には混ぜず、ILCが十分収束したかを
確認する残留FB診断に使う。相別実電流・並列枝路電流・推力そのものを直接同定するものではない。

現行 `exp03_FF/feedforward_experiment.m` の既定FF係数ゼロを勝手に「卒論手法」と呼ばない。
卒論で実際に使用した係数・補間・遅延・FF合成を現地で特定し、ファイルとSHA-256を固定する。
未発見なら卒論比較器は未構成と報告する。

## 既存コードとの接続

| 対象 | 使用・確認方法 |
|---|---|
| `exp04_ILC/ilc_experiment_neo.m` / `obtainMeasurement.m` | 既存ILC学習則の正本。更新式を変更しない |
| `setup_project.m` | 共通パスの設定だけ。実機接続なし |
| `config/sample_rate.m` | 現行4 kHz。古い125 usデータと混ぜない |
| `config/data/pana_params.mat` | 電流上限、エンコーダ・速度・電流換算 |
| `src/load_experiment_plant.m`, `fbDesign` | 現行周期のプラントと既存FB。設計を変更しない |
| `src/capture_tunable_trajectory.m` | r/fを渡して1回取得。停止・待機・raw退避処理を再利用 |
| `src/home_to_start.m` | 必要な場合だけ独立監視下で事前に明示実行。ILC中に自動実行しない |
| `src/tunable_trajectory_buffer_capacity.m` | 固定131072点。容量を変えない |
| `twincat/MotorRuntime` | 単一仮想CSTから実軸を選択。Simulinkに軸別ゲートを作らない |
| `config/copley/magnetic_pole_references.json` | 全4軸の磁極参照を読み取り照合。書き換えない |
| `docs/ff-verification-2026-09-08.md` | 1サンプルのログ遅延、2 A飽和、既存独立監視の記録 |

`accelff.ilc_update` はDemo 4の更新

```text
f_(k+1) = Q^2 { f_k + alpha_k [ C + Gn^-1 ] e_k }
alpha_k = max(0.9^k, 0.3)
Q: 4次Butterworth, Fc=420 Hz（現行値）
```

を1反復分だけ再利用する。25 ms端部処理も同じで、上限超過をクリップしない。
学習則を変えた比較にはしない。

古いMATの `history.y_ab` と現行ILCの `history.y_absolute` は形式が違う。
旧8 kHzデータは過去の仮説確認には使えるが、現行4 kHzの新同定と黙って混ぜない。

## 信号契約と遅延の区別

`capture_tunable_trajectory` の戻り値は10行×N点。

| 行 | 意味 | 単位・扱い |
|---:|---|---|
| 1 | 論理サンプルカウンタ | 整数、増分1。欠落を補間しない |
| 2 | 追従誤差 | m。行9−行5を照合 |
| 3 | 総制御入力 | A。ILC収束後の残留FB診断に使用 |
| 4 | 計測速度 | m/s。生信号を保存 |
| 5 | 相対位置 | m |
| 6 | トルク／電流フィードバック | 生値を保持。枝路実電流とはみなさない |
| 7 | 記録したFF | A。**収束ILCの教師信号** |
| 8 | 絶対位置 | m。位置マップの横軸 |
| 9 | 記録した参照 | m、相対位置 |
| 10 | 量子化参照 | 生計測に保持 |

`logging_delay_samples=1` は記録r/FFを入力波形と照合するための遅延。
`current_offset_samples` は**機械サンプルkと学習FFサンプルk+offsetを組にする**実測整合。
`advance` は一般化FFを出力する際の先行量。この三つは異なる。
8サンプルや40サンプルを無条件に転記せず、4 kHzの現行系で校正する。
`circshift`で信号末尾を先頭へ回さない。

## 軌道とsplit

```matlab
root = setup_project();
addpath(fullfile(root,'exp05_AccelerationFF'));
cases = plan_cases();             % 一発比較の計画
ilcPlan = plan_ilc_sequences();    % ILC系列の計画
p = accelff.profile(0.84,6,0.65,0.00025,[1.5,1,1.5]);
plot(p.t,p.x);                     % 候補値。運転許可ではない
```

`profile` は5次位置関数と時間軸変形から位置・速度・加速度・jerkを解析的に作る。
時間反転の復路では同一位置における速度・jerkは符号反転し、加速度は同符号になる。
速度スケーリングだけでは加速度列が速度列と共線になりやすいため、warpの異なる軌道を用いる。

profile単位で `train / validation / test` を事前固定する。
同じ参照を別名にして別splitへ入れない。ILCの15反復は15個の独立軌道ではない。

- train: 最大6軌道。各軌道でteacher ILCを実施する。
- validation: 一般化FFのgain、先行量、採用域を決める。testはまだ開かない。
- test: すべて固定後の最終評価だけに使う。

最初から6軌道すべてを走らせる必要はない。3軌道でrank・条件数・加速度partial leverageを確認し、
不足位置へ加速度が来る軌道を追加する。実験本数を増やすためだけの反復はしない。

## Teacher ILC

teacher ILCは**1反復ずつ明示実行**する。自動15往復ループは作らない。
各反復で独立監視と操作者承認を確認し、失敗・飽和を挟んだ系列を成功扱いしない。

第1反復は `f=zeros(...)`。取得後、次を計算する。

```matlab
[fNext, ilcInfo] = accelff.ilc_update( ...
    result.trace.ff, result.trace.error, result.trace.t, ...
    fb, Gn0, Ts, 420, iteration, MAX_INPUT);
```

実際には記録遅延を除いた**その反復で要求した `job.f`**を `f_k` とし、
`trace.error` を誤差として更新する。Codexは既存Demo 4と数値一致することをMATLABで確認してから使う。
次反復は新しいcase IDを作り、`method="ilc_teacher"` として
`accelff.execute_case` を1回だけ呼ぶ。

teacher採用は単に「15回終わった」では決めない。

```matlab
teacher = accelff.accept_ilc_teacher(sequenceResults, o);
```

少なくとも以下を満たす。

- 全反復が欠落なし・無飽和・追従／終点／停止確認を通る。
- 誤差RMSが設定した窓でplateauに入る。
- `f_k-f_(k-1)` が十分小さい。
- `row3-row7` の残留FB RMSが最終ILC FFに比べ十分小さい。

採用された `teacher.current` は最終trialの7行目ILC FFで、
`current_kind="ilc_ff_A"` になる。3行目総電流へ置き換えない。

## 位置・速度・加速度モデルの同定

```matlab
o = accelff.options();
o.current_offset_samples = calibratedOffset; % 4 kHzで校正した値
o.alignment_reviewed = true;
obs = accelff.observations(teachers, absolutePositionGrid, o);
model = accelff.fit_map(obs, absolutePositionGrid, o);
```

`observations` はtrain入力について、収束済み `ilc_ff_A` teacher以外を拒否する。
速度・加速度は絶対位置に対する局所3次多項式から求める。窓幅を保存し、端部を捨てる。
これはオフライン非因果処理であり、実時間フィルタではない。

各位置でランク4、列スケーリング後の条件数、独立加速profile数、残差自由度、
速度・方向・定数項で説明できない加速度成分を確認する。不成立位置は `valid=false, NaN`。
同じprofileのILC反復を独立励起として数えない。正則化でランク不足を隠さない。

## 一般化FFの生成

```matlab
limits = struct('velocity_floor',o.velocity_floor, ...
    'ff_A',reviewedFFBudget,'ff_slew_A_s',reviewedFFSlew);
[f, detail] = accelff.feedforward(model,origin_m+p.x,p.v,p.a, ...
    frozenBaselineFF,gain,p.Ts,calibratedAdvance,limits);
```

`baseline + weight*(modelFF-baseline)` として**総FFを置換**する。
`alpha*a` に慣性分が含まれるため、後から `Jn*a` を重ねない。
移動中の無効位置・範囲外・学習速度／加速度範囲外は運転前にエラーとする。
上限超過はクリップせず拒否する。FF予算だけではFB加算後の無飽和を保証できない。

## 実機入口

実機入口は `accelff.execute_case(job,cfg,"RUN "+job.id)`。
1回の呼出しは**1往復だけ**であり、ILC系列も同じ入口を反復ごとに使う。
`method` は `fb / thesis / acceleration / ilc_teacher / ilc_zero / ilc_thesis / ilc_acceleration`。

[CODEX_HANDOFF.md](CODEX_HANDOFF.md)の手順で現地に接続する。
`local_config_example` の未確認項目はNaN、独立監視probeは未接続で、そのままでは実行できない。
取得中の安全をホストの事前・事後チェックや例外cleanupだけに依存させない。

## 未学習軌道での二段階評価

### 1. 一発転送性能

同じprofile/repeatについて

```matlab
summary = accelff.compare_cases({fbResult,thesisResult,accelerationResult});
```

を使い、FBのみ・卒論FF・一般化FFの第1試行を比較する。
全時間、移動、加速、ほぼ等速、固定子上／間欠部のRMS、ピーク、電流、飽和、終点を残す。

### 2. ILC収束速度

同じheld-out profileに対して、ILC学習則を完全に固定し、初期FFだけを変える。

- `ilc_zero`: `f_1=0`
- `ilc_thesis`: `f_1=卒論FF`
- `ilc_acceleration`: `f_1=一般化FF`

各反復後はすべて `accelff.ilc_update` で更新する。初期値ごとに別系列として保存し、
途中で別手法の学習波形を流用しない。

```matlab
s = accelff.summarize_ilc(sequences, frozenTargetRms);
```

評価するのは

- 初回RMS：未学習軌道への転送性能
- normalized AUC：収束までに累積した誤差
- target RMS到達反復数
- 最終RMS
- 最終FFピークと飽和の有無

である。提案手法が「最終的にILCならどれも収束する」だけでなく、
**何反復分の学習を先取りできたか**を示せる。

## 物理解釈の限界

電流追従が十分速く、局所近似が成立し、質量が一定なら概ね
`b=(B_mech+B_circ)/Kq`, `alpha=m/Kq` なので `b/alpha=(B_mech+B_circ)/m`。
ただしここで同定するのはILCが学習した電流換算FFであり、電流応答、遅延、軸切替、
非反復外乱の影響も残り得る。`b/alpha` は循環電流の存在や組立公差の直接証明ではない。

## 検証状態

```matlab
results = runtests(fullfile(root,'tests','test_acceleration_ff.m'));
assert(all([results.Passed]));
```

MATLABテストは23件に更新したが、作成環境にMATLABがないため**未実行**。
Pythonによる既存の数式独立検証9件は実行済み。記録は
[numerical_verification.txt](numerical_verification.txt)。

```text
python tests/verify_acceleration_math.py
```

Python成功はMATLAB、既存Demo 4とのILC数値一致、Simulink、ADS、安全動作の検証を意味しない。
既存全件テスト、モデル再ビルド、Activate、実機運転は本変更の作成時には行っていない。
