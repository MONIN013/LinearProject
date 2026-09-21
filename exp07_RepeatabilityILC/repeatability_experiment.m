%% Exp07: repeatability of the ILC teacher signal
% Execute sections in order, as in exp04/ilc_experiment_neo.m.
% Configuration/design do not enable the stage. Section 4 MOVES THE STAGE.
clear; close all;
projectRoot = fileparts(fileparts(mfilename("fullpath")));
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
Jhat = feedback(Pdn, Kd);

%% 2. Keep the exp04 filters; review actual feedback/sensitivity before running
Fc = 420;
[Qz, Qp, Qgain] = butter(4, Fc/(1/(2*Ts)));
[Qsos, Qscale] = zp2sos(Qz, Qp, Qgain);
Q = zpk(Qz, Qp, Qgain, Ts);
figure; bodemag(feedback(1, Pd*Kd), bop); grid on;
title('Measured feedback sensitivity: review against the existing design');
figure; nyquistplot(Pdn*Kd, nop); hold on; nyquistplot(Pd*Kd, nop);
legend('Nominal', 'Measured');
Jmeasured = feedback(Pd, Kd);
figure;
bodemag(Q^2*(1-0.9*Jmeasured/Jhat), bop); hold on;
bodemag(Q^2*(1-0.3*Jmeasured/Jhat), bop);
legend('alpha=0.9', 'alpha=0.3'); grid on;
title('Magnitude screening only: Q^2 magnitude = forward/backward |Q|^2');
% This plot is not a finite-record contraction proof or a proof for noisy gates.

% These are experiment settings, NOT newly certified machine limits.
% Start with a trajectory already completed successfully by exp04 at this origin.
dist = 1.25;
v_max = 0.3;
a_max = 19.0;
t_pause = 1.0; t_pre = 1.5; t_post = 1.5;
traj = generateMyProfile_TrajectTools( ...
    0.0, dist, v_max, a_max/2, Ts, t_pause, t_pre, t_post);
t = traj.time(:); r = traj.pos(:); N = numel(r); Tend = t(end);
ops.L = @(x) lsimFB(fb, x, t) + lsimInvModel(Gn0, x);
ops.B = @(x) ops.L(lsim(Jhat, x(:), t));
ops.Q = @(x) exp07_q(x, Qsos, Qscale, Ts);
opt = struct('mode', "standard", 'window', 5, 'minGain', 0.1);
trainTrials = 15;
replayTrials = 5; % SAME trajectory, frozen FF; NOT five held-out trajectories.
methods = ["standard", "raw_rcs", "transport_mean", "transport_rcs"];
orderSeed = 7;
rng(orderSeed, 'twister');
methods = methods(randperm(numel(methods)));
confirmEachTrial = false;
velocitySweepEnabled = false;

%% 3. Build only when the model/sample period/fixed buffer has changed
% Otherwise retain the already validated exp04 target. This PR changes no model.
% run(fullfile(projectRoot, "exp03_FF", "setup_tunable.m"));
% Publish/install and activate by the existing exp03/exp04 procedure if rebuilt.

%% 4. OPERATOR ACTION: train each method, then replay its last APPLIED FF
% No injected motor disturbance. Native trial variation is measured as it is.
% Repeat a complete block with another orderSeed to assess run-order/thermal drift.
open(fullfile(projectRoot, ModelName));
blockDir = create_run_directory(fullfile(projectRoot, "data", "ilc"), ...
    "exp07_repeatability");
manifest = struct('methods', methods, 'orderSeed', orderSeed, 'Ts', Ts, ...
    'trainTrials', trainTrials, 'replayTrials', replayTrials, 'opt', opt, ...
    'traj', traj, 'Kd', Kd, 'Gn0', Gn0, 'Q', Q, 'Fc', Fc, ...
    'plantPath', plantPath, 'v_max', v_max, 'dist', dist, 'a_max', a_max);
save_experiment_result(blockDir, "manifest", manifest);
results = struct([]);
for methodIndex = 1:numel(methods)
    method = methods(methodIndex);
    methodOpt = opt; methodOpt.mode = method;
    Ntrial = trainTrials;
    ilcRunDir = create_run_directory(blockDir, method+"_train");
    ilcExtension = struct('initialFeedforward', zeros(N, 1), ...
        'update', @(f,e,k,base,state) exp07_update( ...
            f,e,k,base,state,ops,methodOpt));
    run(fullfile(projectRoot, "exp04_ILC", "obtainMeasurement.m"));
    training = struct('history', history, 'completedTrials', completedTrials, ...
        'method', method, 'Ts', Ts, 'traj', traj, 'Kd', Kd, 'Gn0', Gn0, ...
        'Q', Q, 'Fc', Fc, 'plantPath', plantPath, 'opt', methodOpt);
    trainFile = save_experiment_result(ilcRunDir, "training", training);
    if completedTrials < Ntrial
        error('exp07:Incomplete', 'Training stopped; partial data: %s', trainFile);
    end
    frozenFF = history.f(:, completedTrials); % Not the unexecuted next update.
    Ntrial = replayTrials;
    ilcRunDir = create_run_directory(blockDir, method+"_replay");
    holdOpt = opt; holdOpt.mode = "hold";
    ilcExtension = struct('initialFeedforward', frozenFF, ...
        'update', @(f,e,k,base,state) exp07_update(f,e,k,base,state,ops,holdOpt));
    run(fullfile(projectRoot, "exp04_ILC", "obtainMeasurement.m"));
    replay = struct('history', history, 'completedTrials', completedTrials, ...
        'method', method, 'Ts', Ts, 'frozenFF', frozenFF, 'traj', traj);
    replayFile = save_experiment_result(ilcRunDir, "replay", replay);
    if completedTrials < Ntrial
        error('exp07:Incomplete', 'Replay stopped; partial data: %s', replayFile);
    end
    results(methodIndex).method = method;
    results(methodIndex).trainFile = string(trainFile);
    results(methodIndex).replayFile = string(replayFile);
    results(methodIndex).training = training;
    results(methodIndex).replay = replay;
    save_experiment_result(blockDir, "block", struct('manifest', manifest, ...
        'results', results));
end
clear ilcExtension extension;
summaryTable = exp07_report(results, blockDir);
disp(summaryTable);
