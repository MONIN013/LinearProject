function metrics = exp07_report(results, outputDir)
%EXP07_REPORT 保存した学習・固定FF再走行から記述統計を作る。
rows = cell(numel(results),1);
fLearning = figure; hold on; grid on;
for j = 1:numel(results)
    tr = load(results(j).trainFile, 'history', 'completedTrials', 'MAX_INPUT');
    rp = load(results(j).replayFile, 'history', 'completedTrials', 'frozenFF', 'MAX_INPUT');
    Et = tr.history.e(:, 1:tr.completedTrials);
    Er = rp.history.e(:, 1:rp.completedTrials);
    Ut = tr.history.u(:, 1:tr.completedTrials);
    Ur = rp.history.u(:, 1:rp.completedTrials);
    rmsTrain = sqrt(mean(Et.^2, 1));
    rmsReplay = sqrt(mean(Er.^2, 1));
    frozenCommand = repmat(rp.frozenFF, 1, rp.completedTrials);
    frozenApplied = repmat([0; rp.frozenFF(1:end-1)], 1, rp.completedTrials);
    unchanged = isequal(rp.history.f(:, 1:rp.completedTrials), frozenCommand) && ...
        max(abs(rp.history.ff(:, 1:rp.completedTrials)-frozenApplied), [], 'all') < 1e-12;
    plot(1:tr.completedTrials, rmsTrain, '-o', 'DisplayName', results(j).method);
    rows{j} = struct('method', string(results(j).method), ...
        'trainRMSMean_m', mean(rmsTrain), 'lastTrainRMS_m', rmsTrain(end), ...
        'replayRMSMean_m', mean(rmsReplay), 'replayRMSStd_m', std(rmsReplay), ...
        'meanErrorRMS_m', sqrt(mean(mean(Er, 2).^2)), ...
        'trialVariationRMS_m', sqrt(mean(var(Er, 0, 2))), ...
        'replayPeakError_m', max(abs(Er), [], 'all'), ...
        'replayPeakCommand_A', max(abs(Ur), [], 'all'), ...
        'trainSaturatedSamples', sum(abs(Ut) >= tr.MAX_INPUT-1e-6, 'all'), ...
        'lastTrainSaturatedSamples', sum(abs(Ut(:, end)) >= tr.MAX_INPUT-1e-6), ...
        'replaySaturatedSamples', sum(abs(Ur) >= rp.MAX_INPUT-1e-6, 'all'), ...
        'frozenFFUnchanged', unchanged, 'replayCount', rp.completedTrials);
end
xlabel('Applied trial'); ylabel('Full-record position RMS [m]');
legend('Location', 'best');
metrics = struct2table(vertcat(rows{:}));
writetable(metrics, fullfile(outputDir, 'repeatability_metrics.csv'));
fReplay = figure;
bar(categorical(metrics.method), metrics.replayRMSMean_m);
ylabel('Frozen-FF replay position RMS [m]'); grid on;
save_experiment_figures(outputDir, [fLearning, fReplay]);
save_experiment_result(outputDir, 'repeatability_metrics', struct('metrics', metrics));
end
