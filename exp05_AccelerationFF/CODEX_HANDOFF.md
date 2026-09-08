# Codex実行指示：加速度マップFFの段階的実験

作業先は **MONIN013/LinearProject**。別の研究用リポジトリへ変更しない。
対象コードは `src/+accelff/`、入口文書はこのディレクトリのREADME。
変更箇所に対応した検証を1回行い、同じ状態で全件テストを繰り返さない。
この文書を読んだこと自体は実機の運転許可ではない。

## 1. ベースと卒論比較器を確定する

`git status`、ブランチ、HEADを記録する。未コミットの他人の変更を上書きしない。
ベース `0085d1d58e96c68fac4fa17cc9888d7889cb6c7b` 以降に取得形式・モデル・設定が変わっていれば確認する。
RootのAGENTS.md、exp03_FF/README.md、docs/ff-verification-2026-09-08.mdを読む。

次の対応表を実ファイル名・行番号・単位付きで、ローカルrunの `integration_record.md` へ保存する。

| 確定する対象 | 記録事項 |
|---|---|
| 卒論FF | 係数ファイル、補間、方向項、慣性FFとの加算順、先行量、元ファイルSHA-256 |
| 取得経路 | capture_tunable_trajectoryのr/fと10行計測、絶対位置原点、電流換算 |
| 周期と制御器 | sample_rate.m、周期別plant、fbDesign、配備済みtunable版、固定バッファ容量 |
| 仮想CST | 全4軸磁極参照、軸1/2配線交換後の対応、CURRENT_TO_UNITとドライバ換算 |
| 独立監視 | 既存別プロセス監視の起動・問い合わせ方法、異常時停止経路、ログ |

既定FFゼロの現行スクリプトを卒論手法としてラベル付けしない。
比較器が未発見なら未構成と記録し、FB計測・オフライン解析までは進める。
卒論比較器を適当な近似で捏造しない。既存ILCの学習則は変更しない。

## 2. 新規コードをMATLABで検証する（無励磁）

`setup_project` 後、`runtests('tests/test_acceleration_ff.m')` を一度実行する。
失敗したら該当関数を修正して対応テストを再確認する。環境依存skipを成功としない。
Pythonの9件は式の独立検証でありMATLAB検証の代用にはならない。

`plan_cases` の候補を実際のTsで `accelff.profile` へ渡し、端点、点数、速度・加速度・jerk、
絶対移動範囲を確認する。容量は秒数ではなく点数で検査する。
4 kHzと8 kHzでは同じ131072点でも保持可能時間が違う。軌道を黙って切り捨てない。
容量変更はモデル変更として別途扱い、実験反復のためだけに再ビルドしない。

## 3. 現地設定と独立監視を接続する

`local_config_example.m` を `local_config.local.m` にコピーし、先頭の関数名も
`local_config` にするか、適切なローカル関数名とファイル名を揃える。
またはGit対象外のディレクトリへ置く。接続先・DLL・磁極manifest・単位は現地で再確認する。
すべてのNaNを承認済み数値へ置き換える。assertを通すための閾値拡大は禁止。
`approved_Kd` は使用する既存FBを保存した値。`current_limit_A` は現在のMAX_INPUTと一致、
FF予算はその値未満とする。新手法を通すために2 A上限を上げない。
2026-09-08の高速試験には飽和があるため、まず低速度・低加速度で無飽和の基準を作る。

`cfg.supervisor_probe` は、独立動作中の既存監視を実際に問い合わせる引数なし関数。
返り値は次のフィールドを持つ。通信不明・古い状態・停止済みなら例外を送出する。

```matlab
% 返り値の契約。これを定数関数として実装してはいけない。
struct('running',logical(...), 'trip_latched',logical(...), 'case_id',string(...))
```

問い合わせアダプタはハートビートの鮮度を検査し、同じcase_idで監視が連続していたことを
監視ログから確認する。古いJSONを読んでrunning=trueを返すだけでは不十分。
監視プロセスは位置範囲、追従、電流条件、Fault、通信状態を監視し、MATLABがブロック・
異常終了しても所定の停止経路を持つ必要がある。実際に採用した監視範囲と停止経路を記録する。

この接続は作成環境では未検証。既存監視はローカルrunの記録にあり、公開ソースから
停止経路を推測して書き換えない。probe未接続のまま実機runnerは実行しない。
`idle_snapshot` は事前・事後の読み取り専用確認で、運転中の監視や非常停止の代用品ではない。
I/O watchdog、独立した実機保護、実験前後の全軸確認は維持する。
自動Faultリセット、Flash保存、磁極書き換え、CSTCA切替、保護無効化を追加しない。

## 4. 作業変数・原点・軌道を準備する

現行FFスクリプトの「設定・plant読込・FB設計」の節だけで作業変数を準備する。
「すべて実行」はビルドと実機運転まで進むため使わない。
`Ts,Kd,feedbackFlag,MAX_INPUT,CURRENT_TO_UNIT,ENCODER_RESOLUTION,VELOCITY_RESOLUTION`
は生成時と同じbase workspaceに置く。model workspaceへ移してチェックサムを変えない。
新runnerは設定を上書きせず既存値を照合する。CURRENT_TO_UNITは現地の対応表と照合して保存する。

モデル・周期・固定バッファが同じなら再ビルド・再Activateはしない。
チェックサム不一致は原因を調べる。検査を削って回避しない。
Homingが必要なときだけ独立監視下で `home_to_start(54100000)` を明示実行する。
連続ILC中や別capture中に呼ばない。実際の絶対位置からjob.origin_mを確定する。
比較群で同じ原点を維持し、許容値拡大で原点差を隠さない。

## 5. 1ケースずつ実行する

| jobフィールド | 内容 |
|---|---|
| id | 英数字・_・-だけの一意なケースID |
| profile_id | 軌道形状ID。反復で変えない |
| split | train / validation / test。事前計画から変えない |
| repeat | 1以上の整数。手法間で対応させる |
| method | fb / thesis / acceleration |
| Ts | 制御周期[s] |
| origin_m | 相対参照0の絶対位置[m] |
| r,v,a,j | 同長列ベクトル。相対参照と解析的導関数 |
| f | 同長列ベクトル。先行処理済み総FF[A] |

```matlab
% p, origin_m, cfg, caseRow は事前に検証した値。
job = struct('id',caseRow.id,'profile_id',caseRow.profile_id, ...
    'split',caseRow.split,'repeat',caseRow.repeat,'method',caseRow.method, ...
    'Ts',p.Ts,'origin_m',origin_m,'r',p.x,'v',p.v,'a',p.a,'j',p.j,'f',f);
% この1行だけが1回の運転を行う。現地操作者のケース別承認後に呼ぶ。
result = accelff.execute_case(job,cfg,"RUN "+job.id);
```

FBのfはゼロ。thesisは凍結した卒論FF。accelerationは `accelff.feedforward` による総FF置換結果。
慣性FFを別に重ねない。低速域のbaseline接続も含め、実際に使った波形を保存する。
合成データの係数を実機へ渡さない。model.hardware_approved=falseは数値回帰が
運転承認ではないことを表す。f全体の電流・slew・範囲を現地でレビューする。

実行順は、無励磁の検査、承認した低リスクFB 1回、学習軌道、検証軌道の3手法、最後に未使用test。
54ケースを無条件のforループで走らせない。gain・先行量変更時は新ケースIDと条件版を使う。
失敗時はrawと理由を保持し、原因に関係する変更なしに再試行しない。

保存先は `data/ff/<日時_acceleration_case>/`。既存取得関数がrawを保存する。
case_started、case_failed、case_resultを保存し、runningのまま終わったrunは中断扱いにする。
model、解析options、元データの明示パスとSHA-256、卒論係数、採用gain・advanceも同じrunへ保存する。
実機結果、ライセンス、ローカル設定、生成物をレビューせずGitへ追加しない。

## 6. 同定・検証・凍結

ログ1サンプル遅延の照合を通す。総電流指令と機械応答の整合は別に校正する。
offset=0を既定値だから採用しない。確認後に `o.alignment_reviewed=true` とする。
絶対位置grid、微分窓、停止除外・加速励起閾値を保存する。
全trialをobservationsへ渡してsplit混入を検査し、train行だけをfit_mapへ渡す。

無効位置を一覧化し、その場所へ加減速が来る形状の追加を検討する。
正則化、補間、ゼロ埋めで無効位置を隠さない。移動中の無効セルはFF生成が拒否する。
検証データでgain・先行量・採用域を決め、最終testを開く前に固定する。
サンプル内R²と未使用軌道での追従性能を混同しない。

## 7. 比較結果をPRへ記録する

同じprofile・repeatの3手法をcompare_casesへ渡す。
失敗・飽和があればその条件は比較不成立と記録し、成功例だけを抜き出さない。
全時間・移動・加速・ほぼ等速のRMS、ピーク、電流ピーク、飽和点数、終点誤差を残す。
固定子上／間欠部は確認済み区間表を使い、PLCの鎖交マージンを物理境界にしない。
反復間のばらつきと個別ケース値を示し、3反復だけで大きな一般化や有意差を断定しない。

提出物は使用コミット、機密を除いた条件、各結果の明示パス、テスト結果、失敗履歴、比較表、
全軸停止確認、未実施事項。改善しなかった場合もその結果を残す。
