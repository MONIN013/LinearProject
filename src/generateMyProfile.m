function traj = generateMyProfile( ...
        posStart, posStep, velMax, accAve, dt, Tstay, TidlePre, TidlePost)
% generateMyProfile  4 次スナップ付き S 字軌道（往復版）
%                    + 開始／終了アイドル時間対応
%
% ── 区間構成 ─────────────────────────────────────────────
% [0 ～ TidlePre)          : アイドル (pos = posStart)
% [TidlePre ～ …        ) : 行き  : posStart            → posStart+posStep
% 停止  Tstay
% 帰り                    : posStart+posStep → posStart
% 停止  Tstay
% [… ～ end]              : 終了アイドル (TidlePost)
%
% Optional:
%   TidlePre  ? 軌道開始前のアイドル時間 [s]（既定 0）
%   TidlePost ? 往復が終わった後のアイドル時間 [s]（既定 0）
%
% 返却フィールド: time, pos, vel, acc, jerk, snap, Tmove, dt
%
% ※「帰り後の Tstay は要らない」場合は呼び出し側で Tstay=0 を渡してください
% -------------------------------------------------------------------------

    % ── デフォルト設定 ─────────────────────────────────────
    if nargin < 7 || isempty(TidlePre),  TidlePre  = 0;  end
    if nargin < 8 || isempty(TidlePost), TidlePost = 0;  end
    if isempty(Tstay), Tstay = 0; end

    % 入力正規化（数値健全性）
    assert(dt > 0, "dt must be > 0");
    Tstay     = max(0, Tstay);
    TidlePre  = max(0, TidlePre);
    TidlePost = max(0, TidlePost);

    % ── 1. 行き（forward）軌道 ────────────────────────────
    %   ※ velMax が負でも singleMove 内で絶対値化され、方向は posStep で決まる
    fwd = singleMove(posStart, posStep, velMax, accAve, dt, Tstay);

    % ── 2. 帰り（backward）軌道 ──────────────────────────
    bwd = singleMove(posStart + posStep, -posStep, velMax, accAve, dt, Tstay);
    bwd.time = bwd.time + fwd.time(end);           % 行きの終端をオフセット

    % ── 3. 開始アイドル区間 ────────────────────────────
    NidPre  = max(0, round(TidlePre/dt));
    tidPre  = (0:NidPre-1).' * dt;
    posPre  = posStart*ones(NidPre,1);
    zPre    = zeros(NidPre,1);

    % ── 4. 本移動区間の時間を TidlePre だけシフト ──────────
    fwd.time = fwd.time + TidlePre;
    bwd.time = bwd.time + TidlePre;

    % ── 5. 終了アイドル区間 ────────────────────────────
    NidPost = max(0, round(TidlePost/dt));
    tidPost = (1:NidPost).' * dt + bwd.time(end);  % bwd 終端の次サンプルから
    posPost = posStart*ones(NidPost,1);
    zPost   = zeros(NidPost,1);

    % ── 6. 折り返し重複サンプル除去＆連結 ────────────────
    % bwd の 1 サンプル目は fwd と同時刻なので除外
    if numel(bwd.time) >= 2
        idx = 2:numel(bwd.time);
    else
        idx = [];
    end

    traj.time = [tidPre ; fwd.time ; bwd.time(idx) ; tidPost];
    traj.pos  = [posPre ; fwd.pos  ; bwd.pos(idx)  ; posPost];
    traj.vel  = [zPre   ; fwd.vel  ; bwd.vel(idx)  ; zPost];
    traj.acc  = [zPre   ; fwd.acc  ; bwd.acc(idx)  ; zPost];
    traj.jerk = [zPre   ; fwd.jerk ; bwd.jerk(idx) ; zPost];
    traj.snap = [zPre   ; fwd.snap ; bwd.snap(idx) ; zPost];

    % ── 7. 付帯情報 ──────────────────────────────────
    traj.Tmove = fwd.Tmove + bwd.Tmove + Tstay;  % 純移動+中央停止のみ
    traj.dt    = dt;
end

function traj = singleMove(posStart,posStep,velMax,accAve,dt,Tstay)
% singleMove  「4 次 snap 付き」片道軌道を生成
%
% 入力:
%   posStart : 開始位置 [m]
%   posStep  : 目標変位（負なら負方向へ移動）[m]
%   velMax   : 最高速度 [m/s]（負も可。大きさのみ使用）
%   accAve   : 平均（定格）加速度 [m/s^2]（符号は無視して大きさ使用）
%   dt       : サンプリング周期 [s]
%   Tstay    : 終点での停止時間 [s]
%
% 出力 (struct):
%   traj.time  : 時間軸ベクトル
%   traj.pos   : 位置指令
%   traj.vel   : 速度指令
%   traj.acc   : 加速度指令
%   traj.jerk  : ジャーク指令
%   traj.snap  : スナップ指令
%   traj.Tmove : 移動完了までの時間 (=2*Tacc+Tcon)
%   traj.dt    : サンプリング周期 (入力そのまま)

    if nargin < 6 || isempty(Tstay),  Tstay = 0;  end
    Tstay = max(0, Tstay);

    % ── 進行方向の決定 ────────────────────────────────────
    %   ・基本は posStep の符号で決定
    %   ・posStep==0 のときだけ velMax の符号で決める
    if posStep ~= 0
        sgn = sign(posStep);
    else
        sgn = sign(velMax);
        if sgn == 0, sgn = 1; end  % 完全ゼロなら便宜上 + 方向
    end

    % 大きさ（正値）として扱うパラメータ
    D      = abs(posStep);      % 変位の大きさ
    vmax   = abs(velMax);       % 最高速度の大きさ
    a_bar  = abs(accAve);       % 平均加速度の大きさ

    assert(vmax > 0,  "abs(velMax) must be > 0");
    assert(a_bar > 0, "abs(accAve) must be > 0");
    assert(dt > 0,    "dt must be > 0");

    % ゼロ距離なら停止のみ返す
    if D == 0
        N      = max(1, round(Tstay/dt) + 1);
        t      = (0:N-1).'*dt;
        pos    = posStart*ones(N,1);
        zcol   = zeros(N,1);
        traj.time  = t;
        traj.pos   = pos;
        traj.vel   = zcol;
        traj.acc   = zcol;
        traj.jerk  = zcol;
        traj.snap  = zcol;
        traj.Tmove = 0;
        traj.dt    = dt;
        return;
    end

    % ── 基本時定数・距離の算出 ────────────────────────────────
    %   三角（巡航 0）と台形（巡航あり）を自動切替
    Tacc   = vmax / a_bar;        % 加速時間（定格 a_bar を満たす三角想定）
    posCon = vmax * Tacc;         % 加減速で要する距離（両端合計）
    Tcon   = (D - posCon) / vmax; % 巡航時間（負なら三角）

    if D <= posCon + eps
        % 三角：巡航なし。要求距離に合うよう a_bar を微調整
        Tcon  = 0;
        a_bar = D / max(eps, Tacc^2);
        velpk = a_bar * Tacc;     % 実効巡航速度（終端で到達する速度）
    else
        % 台形：巡航あり
        velpk = vmax;
    end

    % snap（4 次導関数）係数（Tacc==0 のケア）
    if Tacc > 0
        A = 6*velpk / (Tacc^3);
    else
        A = 0;
    end

    Tmove = 2*Tacc + Tcon;        % 純移動時間
    N   = max(1, round((Tstay + Tmove)/dt) + 1);
    t   = (0:N-1).'*dt;           % 列ベクトル
    pos = zeros(N,1);  vel = pos;  acc = pos;  jerk = pos;  snap = pos;

    % ── 区間別の式（snap 一定：±2A）─────────────────────────
    for k = 1:N
        tk = t(k);

        if tk <= 0
            % 初期点：既定 0

        elseif tk <= Tacc
            % 加速区間
            pos(k)  = -(1/12)*A*tk^4 + (1/6)*A*Tacc*tk^3;
            vel(k)  = -(1/3)*A*tk^3  + 0.5*A*Tacc*tk^2;
            acc(k)  = -A*tk^2        + A*Tacc*tk;
            jerk(k) = -2*A*tk        + A*Tacc;
            snap(k) = -2*A;

        elseif (Tcon > 0) && (tk <= Tacc + Tcon)
            % 巡航区間
            tc      = tk - Tacc;
            pos(k)  = 0.5*Tacc*velpk + velpk*tc;
            vel(k)  = velpk;

        elseif tk < Tmove
            % 減速区間
            td      = tk - Tacc - Tcon;
            pos(k)  = (1/12)*A*td^4 - (1/6)*A*Tacc*td^3 + velpk*td + velpk*(Tcon + 0.5*Tacc);
            vel(k)  = (1/3)*A*td^3 - 0.5*A*Tacc*td^2 + velpk;
            acc(k)  =  A*td^2      - A*Tacc*td;
            jerk(k) =  2*A*td      - A*Tacc;
            snap(k) =  2*A;

        else
            % 停止（滞留）区間
            pos(k) = D;
            % vel/acc/jerk/snap は 0 のまま
        end
    end

    % ── 進行方向の符号を適用し，開始位置を加算 ──────────────
    pos  = posStart + sgn*pos;
    vel  = sgn*vel;
    acc  = sgn*acc;
    jerk = sgn*jerk;
    snap = sgn*snap;

    % ── 構造体へ格納して返却 ────────────────────────────────
    traj.time  = t;
    traj.pos   = pos;
    traj.vel   = vel;
    traj.acc   = acc;
    traj.jerk  = jerk;
    traj.snap  = snap;
    traj.Tmove = Tmove;
    traj.dt    = dt;
end
