%% Exp08: identical-FF pairs for confidence-weighted ILC
% Execute sections in order, as in exp04/ilc_experiment_neo.m.
% Configuration/design do not enable the stage. Section 4 MOVES THE STAGE.
clear; close all;
projectRoot = fileparts(fileparts(mfilename("fullpath")));
run(fullfile(projectRoot, "config", "config_tunable.m"));
addpath(fullfile(projectRoot, "exp07_RepeatabilityILC"), ...
    fullfile(projectRoot, "exp08_PairedConfidenceILC"));
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
ops.Q = @(x) exp07_q(x, Qsos, Qscale, Ts);

% Record position/direction diagnostics on the SAME reference grid each trial.
positionBinWidth = 0.01; % [m], diagnostic resolution only
minAbsVelocity = 0.01; % [m/s], excludes dwell/near-reversal from moving metrics
activeMask = abs(traj.vel(:)) > minAbsVelocity;
assert(any(activeMask),'No moving samples for the selected trajectory.');
x0 = min(r); nPosition = max(1,ceil((max(r)-x0)/positionBinWidth));
binIndex = min(nPosition,floor((r-x0)/positionBinWidth)+1);
binIndex = binIndex + nPosition*(traj.vel(:)<0);
binIndex(~activeMask) = 0;
ids = (1:2*nPosition)';
left = x0+mod(ids-1,nPosition)*positionBinWidth;
right = min(left+positionBinWidth,max(r));
direction = [ones(nPosition,1);-ones(nPosition,1)];
binTable = table(ids,left,right,direction, ...
    accumarray(binIndex(activeMask),1,[2*nPosition,1]), ...
    'VariableNames',{'bin','referenceLeft_m','referenceRight_m','direction','samples'});
opt = struct('mode',"standard",'binIndex',binIndex, ...
    'rawWindow',5,'acquisitionBudget',30);
replayTrials = 5;
assert(mod(opt.acquisitionBudget,2)==0 && opt.acquisitionBudget>=2, ...
    'Use an even physical acquisition budget to finish each pair.');
methods = ["standard","raw_rcs","pair_mean","pair_confidence"];
orderSeed = 8; rng(orderSeed,'twister');
methods = methods(randperm(numel(methods)));
confirmEachTrial = false;
velocitySweepEnabled = false;

%% 3. Build only when the model/sample period/fixed buffer has changed
% Otherwise retain the already validated exp04 target. This PR changes no model.
% run(fullfile(projectRoot, "exp03_FF", "setup_tunable.m"));
% Publish/install and activate by the existing exp03/exp04 procedure if rebuilt.

%% 4. OPERATOR ACTION: 30 acquisitions + 5 frozen-FF evaluations per method
% Initial FF is zero for every method. No artificial disturbance is injected.
% Pair #1/#2 have exactly the same FF, with normal FB enabled on both runs.
% Replay #1 is the FIRST application of the candidate learned from run #30.
open(fullfile(projectRoot,ModelName));
blockDir = create_run_directory(fullfile(projectRoot,"data","ilc"),"exp08_paired_confidence");
manifest = struct('methods',methods,'orderSeed',orderSeed,'Ts',Ts,'opt',opt, ...
    'replayTrials',replayTrials,'traj',traj,'Kd',Kd,'Gn0',Gn0,'Q',Q,'Fc',Fc, ...
    'plantPath',plantPath,'dist',dist,'v_max',v_max,'a_max',a_max, ...
    'activeMask',activeMask,'binTable',binTable,'positionBinWidth',positionBinWidth, ...
    'minAbsVelocity',minAbsVelocity,'alphaClock',"physical_pair_closing_acquisition");
save_experiment_result(blockDir,"manifest",manifest);
results = struct([]);
for methodIndex = 1:numel(methods)
    method = methods(methodIndex); methodOpt = opt; methodOpt.mode = method;
    Ntrial = opt.acquisitionBudget;
    ilcRunDir = create_run_directory(blockDir,method+"_train");
    ilcExtension = struct('initialFeedforward',zeros(N,1), ...
        'update',@(f,e,k,base,state) exp08_update(f,e,k,base,state,ops,methodOpt));
    trainingClock = tic;
    run(fullfile(projectRoot,"exp04_ILC","obtainMeasurement.m"));
    elapsedSeconds = toc(trainingClock);
    training = struct('history',history,'completedTrials',completedTrials, ...
        'method',method,'Ts',Ts,'elapsedSeconds',elapsedSeconds,'opt',methodOpt);
    trainFile = save_experiment_result(ilcRunDir,"training",training);
    if completedTrials < Ntrial
        error('exp08:Incomplete','Training stopped; partial data: %s',trainFile);
    end
    frozenFF = history.updateInfo{completedTrials}.nextFF;
    % Same bound as the existing hook; no clipping or relaxed machine limit.
    assert(numel(frozenFF)==N && all(isfinite(frozenFF)) && ...
        max(abs(frozenFF))<=2*MAX_INPUT, ...
        'Final candidate is unavailable or exceeds the existing ILC limit.');
    Ntrial = replayTrials;
    ilcRunDir = create_run_directory(blockDir,method+"_replay");
    holdOpt = opt; holdOpt.mode = "hold";
    ilcExtension = struct('initialFeedforward',frozenFF, ...
        'update',@(f,e,k,base,state) exp08_update(f,e,k,base,state,ops,holdOpt));
    replayClock = tic;
    run(fullfile(projectRoot,"exp04_ILC","obtainMeasurement.m"));
    elapsedSeconds = toc(replayClock);
    replay = struct('history',history,'completedTrials',completedTrials, ...
        'method',method,'Ts',Ts,'frozenFF',frozenFF,'elapsedSeconds',elapsedSeconds, ...
        'firstAppliedHere',true);
    replayFile = save_experiment_result(ilcRunDir,"replay",replay);
    if completedTrials < Ntrial
        error('exp08:Incomplete','Replay stopped; partial data: %s',replayFile);
    end
    results(methodIndex).method = method;
    results(methodIndex).trainFile = string(trainFile);
    results(methodIndex).replayFile = string(replayFile);
    results(methodIndex).training = training;
    results(methodIndex).replay = replay;
    save_experiment_result(blockDir,"block",struct('manifest',manifest,'results',results));
end
clear ilcExtension extension;
summaryTable = exp08_report(results,manifest,blockDir);
disp(summaryTable);
