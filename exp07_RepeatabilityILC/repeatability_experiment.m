%% 1. 設定を読み込み、既存のフィードバック制御器を設計する
clear; close all;
projectRoot = setup_project();
run(fullfile(projectRoot, "config", "config_tunable.m"));
addpath(fullfile(projectRoot, "exp07_RepeatabilityILC"));
load(fullfile(projectRoot, "config", "data", "pana_params.mat"));
[plant, plantPath] = load_experiment_plant(projectRoot, plantDataFile, Ts);
Pd = plant.Pd;
Pd0 = struct("m", plant.Jn, "d", plant.Dn, "k", 0, ...
    "delay", plant.Ndelay, "lp", [0, 0, 0]);
[~, Gn0] = modelCreate(Pd0, Ts, Pd.Frequency);
Pdn = Gn0.modelDelayed;
[fb, ~, ~] = fbDesign(Pd, Ts);
Kd = fb.K;
feedbackFlag = 1;
fprintf("Sample rate: %.0f Hz, plant: %s\n", 1/Ts, plantPath);

%% 2. 安定性・感度と学習フィルタを確認する
Smax = 2;
S = feedback(1, Pd*Kd);
assert(isstable(feedback(Pdn*Kd, 1)) && ...
    max(abs(S.ResponseData), [], 'all') < Smax, ...
    'NikonMotor:ControllerCheckFailed', ...
    'Check stability and sensitivity before ILC.');
theta = linspace(0, 2*pi, 1000);
figure;
nyquistplot(Pdn*Kd, nop); hold on;
nyquistplot(Pd*Kd, nop);
plot(cos(theta)/Smax-1, sin(theta)/Smax, "k--"); hold off;
legend("Nominal", "Measured", "1/Smax boundary");
figure;
bodemag(S, bop); hold on;
bodemag(frd(Smax*ones(numel(Pd.Frequency), 1), ...
    Pd.Frequency, "FrequencyUnit", "Hz"), bop, "k--"); hold off;
legend("Measured", "Smax"); grid on;

Fc = 420;
[Qz, Qp, Qgain] = butter(4, Fc/(1/(2*Ts)));
[Qsos, Qscale] = zp2sos(Qz, Qp, Qgain);
Q = zpk(Qz, Qp, Qgain, Ts);
Jhat = feedback(Pdn, Kd);
J = feedback(Pd, Kd);
figure;
bodemag(Q^2*(1-0.9*J/Jhat), bop); hold on;
bodemag(Q^2*(1-0.3*J/Jhat), bop);
plot([1, 1/(2*Ts)], [0, 0], "k--"); hold off;
legend("alpha=0.9", "alpha=0.3", "0 dB"); grid on;
title("ILC learning response");

%% 3. 軌道と比較条件を設定する
dist = 1.25;                 % 往路距離 [m]
v_max = 0.3;                 % 最大速度 [m/s]
a_max = 12.0;                % neoと同じ設定。生成器には半分を渡す。
t_pause = 1.0; t_pre = 1.5; t_post = 1.5;
startCount = 54100000;
traj = generateMyProfile_TrajectTools( ...
    0.0, dist, v_max, a_max/2, Ts, t_pause, t_pre, t_post);
t = traj.time(:); r = traj.pos(:); N = numel(r); Tend = t(end);
ops.L = @(x) lsimFB(fb, x, t) + lsimInvModel(Gn0, x);
ops.B = @(x) ops.L(lsim(Jhat, x(:), t));
ops.Q = @(x) exp07_q(x, Qsos, Qscale, Ts);
opt = struct('window', 5, 'minGain', 0.1);
trainTrials = 15;
replayTrials = 5;
methods = ["standard", "raw_rcs", "transport_mean", "transport_rcs"];
orderSeed = 7;
rng(orderSeed, 'twister');
methods = methods(randperm(numel(methods)));
confirmEachTrial = false;
velocitySweepEnabled = false;

figure;
tiledlayout(3, 1);
nexttile; plot(t, traj.pos); grid on; ylabel("Position [m]");
nexttile; plot(t, traj.vel); grid on; ylabel("Velocity [m/s]");
nexttile; plot(t, traj.acc); grid on; ylabel("Acceleration [m/s^2]");
xlabel("Time [s]");

%% 4. モデル・周期・固定バッファを変更したときだけビルドする
rebuildTarget = false;
if rebuildTarget
    run(fullfile(projectRoot, "exp03_FF", "setup_tunable.m"));
end
% ビルドした場合は既存のPublish/Install/Activate手順を完了してから次節へ。

%% 5. 各手法を15回学習し、最後に適用したFFで5回再走行する
load_system(fullfile(projectRoot, ModelName));
blockDir = create_run_directory(fullfile(projectRoot, "data", "ilc"), ...
    "exp07_repeatability");
manifest = struct('methods', methods, 'orderSeed', orderSeed, 'Ts', Ts, ...
    'trainTrials', trainTrials, 'replayTrials', replayTrials, 'opt', opt, ...
    'traj', traj, 'Kd', Kd, 'Gn0', Gn0, 'Q', Q, 'Fc', Fc, ...
    'plantPath', plantPath, 'v_max', v_max, 'dist', dist, 'a_max', a_max, ...
    'startCount', startCount, 'MAX_INPUT', MAX_INPUT);
results = struct('method', {}, 'trainFile', {}, 'replayFile', {});
blockFile = save_experiment_result(blockDir, "block", ...
    struct('manifest', manifest, 'results', results));

for methodIndex = 1:numel(methods)
    method = methods(methodIndex);
    fprintf("\nMethod %d/%d: %s\n", methodIndex, numel(methods), method);
    methodOpt = opt; methodOpt.mode = method;
    Ntrial = trainTrials;
    ilcRunDir = create_run_directory(blockDir, method+"_train");
    read_tunable_idle_state(Ts);
    [~, homing] = home_to_start(startCount);
    pre = read_tunable_idle_state(Ts);
    assert(abs(pre.positionCount-startCount) <= 1000 && ...
        all(pre.positionCount*ENCODER_RESOLUTION+r >= 5.4054804 & ...
            pre.positionCount*ENCODER_RESOLUTION+r <= 6.6655810), ...
        'NikonMotor:StartPositionChanged', 'Check the start position and trajectory range.');
    ilcExtension = struct('initialFeedforward', zeros(N, 1), ...
        'update', @(f,e,k,base,state) exp07_update( ...
            f,e,k,base,state,ops,methodOpt));
    run(fullfile(projectRoot, "exp04_ILC", "obtainMeasurement.m"));
    post = read_tunable_idle_state(Ts);
    trainFile = finalize_experiment_result(ilcRunDir, "training", struct( ...
        'history', history, 'completedTrials', completedTrials, ...
        'method', method, 'Ts', Ts, 'traj', traj, 'Kd', Kd, 'Gn0', Gn0, ...
        'Q', Q, 'Fc', Fc, 'plantPath', plantPath, 'opt', methodOpt, ...
        'MAX_INPUT', MAX_INPUT, 'homing', homing, 'pre', pre, 'post', post), ...
        fullfile('raw', 'single'), "ilc_progress_single.mat");
    results(methodIndex) = struct('method', method, ...
        'trainFile', string(trainFile), 'replayFile', "");
    save_experiment_result(blockDir, "block", ...
        struct('manifest', manifest, 'results', results));
    assert(completedTrials == trainTrials, 'exp07:Incomplete', ...
        'Training stopped; partial data: %s', trainFile);
    frozenFF = history.f(:, completedTrials);
    Ntrial = replayTrials;
    ilcRunDir = create_run_directory(blockDir, method+"_replay");
    read_tunable_idle_state(Ts);
    [~, homing] = home_to_start(startCount);
    pre = read_tunable_idle_state(Ts);
    assert(abs(pre.positionCount-startCount) <= 1000 && ...
        all(pre.positionCount*ENCODER_RESOLUTION+r >= 5.4054804 & ...
            pre.positionCount*ENCODER_RESOLUTION+r <= 6.6655810), ...
        'NikonMotor:StartPositionChanged', 'Check the start position and trajectory range.');
    holdOpt = opt; holdOpt.mode = "hold";
    ilcExtension = struct('initialFeedforward', frozenFF, ...
        'update', @(f,e,k,base,state) exp07_update(f,e,k,base,state,ops,holdOpt));
    run(fullfile(projectRoot, "exp04_ILC", "obtainMeasurement.m"));
    post = read_tunable_idle_state(Ts);
    replayFile = finalize_experiment_result(ilcRunDir, "replay", struct( ...
        'history', history, 'completedTrials', completedTrials, ...
        'method', method, 'Ts', Ts, 'frozenFF', frozenFF, 'traj', traj, ...
        'MAX_INPUT', MAX_INPUT, 'homing', homing, 'pre', pre, 'post', post), ...
        fullfile('raw', 'single'), "ilc_progress_single.mat");
    results(methodIndex).replayFile = string(replayFile);
    save_experiment_result(blockDir, "block", ...
        struct('manifest', manifest, 'results', results));
    assert(completedTrials == replayTrials, 'exp07:Incomplete', ...
        'Replay stopped; partial data: %s', replayFile);
end
clear ilcExtension;

%% 6. 学習曲線・固定FFの再現性を描画し、保存する
summaryTable = exp07_report(results, blockDir);
disp(summaryTable);
assert(all(summaryTable.replaySaturatedSamples == 0) && ...
    all(summaryTable.frozenFFUnchanged), 'exp07:ReplayInvalid', ...
    'Replay saturated or changed its FF; inspect the saved comparison.');
fprintf("Exp07 completed: %s\n", blockFile);
