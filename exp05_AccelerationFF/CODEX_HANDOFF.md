# Codex実行指示：ILC教師から加速度マップFFを作る実機実験

作業先は **MONIN013/LinearProject**。Rootの`AGENTS.md`を最優先する。
対象はPR #1の `exp05_AccelerationFF/` と `src/+accelff/`。
この文書は実験手順であって運転許可ではない。操作者承認、既存独立監視、
I/O watchdog、全軸停止確認を省略しない。

## 0. 研究目的を固定する

今回の発展はILCを廃止することではない。

1. 加速度の異なる複数軌道で既存ILCを収束させる。
2. 収束したILC FFを教師に `i_ILC(x,v,a)` を同定する。
3. 未学習軌道へ一般化FFを転送する。
4. 一般化FFを初期値にしたILCが、ゼロ初期／卒論FF初期より少ない反復で収束するか評価する。

ILC学習則は `exp04_ILC/obtainMeasurement.m` のものを変更しない。
発展点は学習軌道に加速度励起を持たせ、その複数軌道の収束FFを共通モデルへ落とすこと。

## 1. 既存系と卒論比較器を確定する

最初に`git status`、branch、HEADを記録し、未コミット変更を上書きしない。
次を読んで `integration_record.md` に実ファイル・行番号・単位付きで対応表を作る。

- `AGENTS.md`
- `exp03_FF/README.md`
- `exp04_ILC/ilc_experiment_neo.m`
- `exp04_ILC/obtainMeasurement.m`
- `src/capture_tunable_trajectory.m`
- `config/sample_rate.m`
- `config/data/pana_params.mat`
- `config/copley/magnetic_pole_references.json`
- `docs/ff-verification-2026-09-08.md`

特に次を確定する。

| 項目 | 必ず記録するもの |
|---|---|
| 既存ILC | `Q`, `Fc`, `alpha_k`, `lsimFB`, `lsimInvModel`, 25 ms端処理、停止条件 |
| 卒論FF | 係数ファイル、補間、方向項、慣性項、先行量、SHA-256 |
| 10行計測 | 行3総入力、行7FF、行8絶対位置、行9参照、単位 |
| 時間整合 | 1サンプル記録遅延と、FF→機械応答の遅延を別々に扱う |
| 実機 | 4 kHz周期、現在のplant/FB、MAX_INPUT、固定バッファ、仮想CST、4軸磁極参照 |
| 独立監視 | 起動法、heartbeat、case_id、位置・電流・Fault監視、異常時停止経路 |

現行FFスクリプトの既定係数ゼロを「卒論手法」と呼ばない。卒論比較器が見つからない場合は
未構成と報告し、教師ILCと一般化モデルの構築まで進める。

## 2. MATLAB無励磁検証

`setup_project`後、新規テストだけを実行する。

```matlab
root = setup_project();
r = runtests(fullfile(root,'tests','test_acceleration_ff.m'));
assert(all([r.Passed]));
```

23件を想定する。環境依存skipを成功扱いしない。
特に `accelff.ilc_update` が既存Demo 4の1反復更新と数値一致するテストを現地で追加する。
同じ `f,e,t,fb,Gn0,Ts,Fc,iteration` に対し、`fNext` が丸め誤差範囲で一致すること。
一致しなければ実機ILCへ進まない。

`plan_cases()` と `plan_ilc_sequences()` は計画表を作るだけで実機には触れない。
全候補軌道について点数、端点、速度、加速度、jerk、絶対位置範囲、131072点容量を確認する。

## 3. 現地設定と監視を接続する

`local_config_example.m` を参考に、Git管理外へローカル設定を作る。
NaNは承認済み値で置換し、assertを通すために上限を広げない。

- `current_limit_A` は配備中の `MAX_INPUT` と一致。
- `ff_limit_A` はFB余裕を残してそれ未満。
- 位置、速度、加速度、jerk、slewは現地の承認値。
- `approved_Kd` は今使うFBそのもの。
- `supervisor_probe` は別プロセス監視の**現在状態**を問い合わせる。定数true禁止。

2026-09-08の1 m/s, 17 m/s²条件には2 A飽和があるため、上限を上げず、
まず低リスク条件で無飽和のILC系列を成立させる。

## 4. 制御変数と原点を準備する

現行FFスクリプトの設定・plant読込・`fbDesign`だけを使って
`Ts,Kd,feedbackFlag,MAX_INPUT,CURRENT_TO_UNIT,ENCODER_RESOLUTION,VELOCITY_RESOLUTION`
を生成時と同じbase workspaceへ置く。model workspaceへ移さない。

モデル、周期、固定バッファが同じなら再ビルド・再Activateしない。
Homingが必要な場合だけ、ILC系列開始前に独立監視下で明示実行する。
ILC反復の途中でHomingしない。同一系列で原点を変えない。

## 5. Teacher ILCを1反復ずつ実行する

`plan_ilc_sequences()` のtrain行から開始する。最初は最低3profileでよい。
各profileは同じ参照を最大15反復し、反復ごとに操作者が個別承認する。
自動15往復for-loopを新設しない。

### Trial 1

```matlab
job.method = "ilc_teacher";
job.split = "train";
job.repeat = 1;
job.f = zeros(size(job.r));
result{1} = accelff.execute_case(job,cfg,"RUN "+job.id);
```

### Trial k+1

既存Demo 4と一致確認済みの更新を使う。

```matlab
[fNext,info] = accelff.ilc_update( ...
    job.f, result{k}.trace.error, result{k}.trace.t, ...
    fb, Gn0, Ts, 420, k, MAX_INPUT);
```

`fNext`はクリップしない。`2*MAX_INPUT`超過、FF予算／slew超過、飽和、追従失敗、監視異常なら
系列を停止し理由を保存する。上限を広げて継続しない。

次のjobは同一profile/reference/originで、IDだけ反復番号を含む一意値へ変える。
`method="ilc_teacher"`を維持して `execute_case` をもう1回だけ呼ぶ。

各trialについて少なくとも次を保存する。

- `job.f`
- 10行raw計測
- `trace.error`
- `trace.ff`（ログ7行目）
- `trace.current`（総入力、ログ3行目）
- `ilc_update`のinfo
- エラーRMS、FF変化率、電流ピーク、飽和点数
- 前後の全軸停止・Fault・I/O・監視証拠

## 6. ILC教師を採用する

単に15回完了したから採用しない。

```matlab
o = accelff.options();
teacher = accelff.accept_ilc_teacher(result,o);
```

採用条件は、全trialの品質合格に加え、最終区間で

- 誤差RMSがplateau
- FF更新量がplateau
- `row3-row7` の残留FBが学習FFに対して十分小さい

こと。

**同定教師は最終trialのrow 7 ILC FF。** row 3総入力ではない。
これにより、卒論と同様にILCが学習した反復外乱補償をモデル化する。
row 3は残留FB診断として保存する。

teacher採用に失敗したprofileは、そのままfitへ入れない。原因を確認し、
新しい物理励起が必要なら別profileを事前定義して追加する。

## 7. 加速度マップを同定する

3profile以上のteacherを得たら、まず識別性だけ確認する。

```matlab
o.current_offset_samples = calibratedOffset;
o.alignment_reviewed = true;
obs = accelff.observations(teachers,absolutePositionGrid,o);
model = accelff.fit_map(obs,absolutePositionGrid,o);
```

`current_offset_samples`は4 kHz現行系で校正する。昔の8/40サンプルを転記しない。

各位置で

- rank 4
- scaled condition number
- profile数
- dynamic profile数
- residual DOF
- acceleration partial leverage

を確認する。無効位置をNaNのまま地図化する。
不足位置に加減速が来るprofileを追加し、再ILCしてteacherを増やす。
ILC反復数を独立profile数として水増ししない。

## 8. Validationで一般化FFを固定する

validation profileだけを開き、

1. FBのみ
2. 凍結した卒論FF
3. `accelff.feedforward`による一般化FF

を同一参照・FB・上限で一発比較する。gain、advance、採用域をvalidationだけで決める。
`alpha*a`へ別の慣性FFを重ねない。無効位置、学習範囲外、FF/slew超過をクリップして通さない。

決定後、モデル、gain、advance、位置grid、options、卒論比較器SHAを凍結する。
その後までtest profileを使わない。

## 9. Held-out ILCで学習短縮を比較する

validation/testの同一profileについて、ILC学習則を完全に同じにし、初期FFだけを変える。

| 系列 | Trial 1のFF | method |
|---|---|---|
| zero | 0 | `ilc_zero` |
| thesis | 凍結卒論FF | `ilc_thesis` |
| acceleration | 凍結一般化FF | `ilc_acceleration` |

Trial 2以降は全系列で同じ `accelff.ilc_update` を使う。
別系列で学習済みの波形を流用しない。最大反復数は `plan_ilc_sequences` に従う。

```matlab
summary = accelff.summarize_ilc(sequences,frozenTargetRms);
```

最低限報告するのは

- 初回RMS
- normalized AUC
- target RMS到達反復数
- 最終RMS
- 最終FFピーク
- 飽和・失敗の有無

一般化FFの価値は、未学習軌道の初回性能だけでなく、**ILCが必要とする反復数を何回減らしたか**で評価する。

## 10. PR #1へ記録する

実機実験ごとにPRへ追記する。

- 使用commitと配備版
- MATLABテスト結果、Demo 4とのILC更新一致
- 使用profileとsplit
- 各teacher ILCの学習曲線とteacher採否
- 位置ごとの識別性診断
- validationで固定したパラメータ
- testの一発比較
- 3初期値のILC収束比較
- 飽和、失敗、停止理由
- 全軸停止、Fault=0、I/O、監視証拠
- 未実施事項

成功例だけを抜き出さない。改善しなかった場合も結果として残す。
