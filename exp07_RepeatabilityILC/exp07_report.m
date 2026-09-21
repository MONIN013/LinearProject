function metrics = exp07_report(results, outputDir)
%EXP07_REPORT Descriptive performance for identical-path, frozen-FF replays.
% No claim that the mean error is the noiseless error; replay drift can bias it.
rows = struct([]);
fLearning = figure; hold on; grid on;
for j = 1:numel(results)
    tr = results(j).training;
    rp = results(j).replay;
    Et = tr.history.e(:, 1:tr.completedTrials);
    Er = rp.history.e(:, 1:rp.completedTrials);
    U = rp.history.u(:, 1:rp.completedTrials);
    rmsTrain = sqrt(mean(Et.^2, 1));
    rmsReplay = sqrt(mean(Er.^2, 1));
    plot(1:tr.completedTrials, rmsTrain, '-o', 'DisplayName', results(j).method);
    row = struct('method', string(results(j).method), ...
        'trainRMSMean_m', mean(rmsTrain), 'lastTrainRMS_m', rmsTrain(end), ...
        'replayRMSMean_m', mean(rmsReplay), 'replayRMSStd_m', std(rmsReplay), ...
        'meanErrorRMS_m', sqrt(mean(mean(Er, 2).^2)), ...
        'trialVariationRMS_m', sqrt(mean(var(Er, 0, 2))), ...
        'replayPeakError_m', max(abs(Er), [], 'all'), ...
        'replayPeakCommand_A', max(abs(U), [], 'all'), ...
        'replayCount', rp.completedTrials);
    rows(j) = row; %#ok<AGROW>
end
xlabel('Applied trial'); ylabel('Full-record position RMS [m]'); legend('Location','best');
metrics = struct2table(rows);
writetable(metrics, fullfile(outputDir, 'repeatability_metrics.csv'));
fReplay = figure;
bar(categorical(metrics.method), metrics.replayRMSMean_m);
ylabel('Frozen-FF replay position RMS [m]'); grid on;
save_experiment_figures(outputDir, [fLearning, fReplay]);
save_experiment_result(outputDir, 'repeatability_metrics', struct('metrics', metrics));
end
