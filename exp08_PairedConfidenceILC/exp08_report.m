function metrics = exp08_report(results,manifest,outputDir)
%EXP08_REPORT Load finalized results and summarize equal-cost comparisons.
rows = cell(numel(results),1);
figures(1) = figure; hold on; grid on;
active = manifest.activeMask;
for j = 1:numel(results)
    tr = load(results(j).trainFile);
    rp = load(results(j).replayFile);
    Et = tr.history.e(:,1:tr.completedTrials);
    Er = rp.history.e(:,1:rp.completedTrials);
    Ur = rp.history.u(:,1:rp.completedTrials);
    curve = sqrt(mean(Et(active,:).^2,1));
    plot(1:tr.completedTrials,curve,'-o','DisplayName',results(j).method);
    infos = tr.history.updateInfo(1:tr.completedTrials);
    decisions = sum(cellfun(@(x)x.updateFormed,infos));
    rows{j} = struct('method',string(results(j).method), ...
        'trainAcquisitions',tr.completedTrials,'updateDecisions',decisions, ...
        'replayAcquisitions',rp.completedTrials, ...
        'trainingSeconds',tr.elapsedSeconds,'replaySeconds',rp.elapsedSeconds, ...
        'trainMovingRMSMean_m',mean(curve), ...
        'replayMovingRMSMean_m',mean(sqrt(mean(Er(active,:).^2,1))), ...
        'replayFullRMSMean_m',mean(sqrt(mean(Er.^2,1))), ...
        'replayMeanErrorRMS_m',sqrt(mean(mean(Er(active,:),2).^2)), ...
        'replayTrialVariationRMS_m',sqrt(mean(var(Er(active,:),0,2))), ...
        'replayPeakError_m',max(abs(Er),[],'all'), ...
        'replayPeakCommand_A',max(abs(Ur),[],'all'), ...
        'trainSaturatedSamples',tr.saturatedSamples, ...
        'replaySaturatedSamples',rp.saturatedSamples);
    bins = table();
    for k = 1:numel(infos)
        stats = infos{k}.pairStats;
        if ~isfield(stats,'binGate') || isempty(stats.binGate), continue; end
        diagnostic = manifest.binTable(1:numel(stats.binGate),:);
        diagnostic.acquisition = repmat(k,height(diagnostic),1);
        diagnostic.signalEnergy = stats.binSignalEnergy;
        diagnostic.noiseEnergy = stats.binNoiseEnergy;
        diagnostic.gate = stats.binGate;
        bins = [bins;diagnostic]; %#ok<AGROW>
    end
    if ~isempty(bins)
        writetable(bins,fullfile(outputDir,results(j).method+"_position_confidence.csv"));
    end
end
xlabel('Physical training acquisition'); ylabel('Moving position RMS [m]');
legend('Location','best');
metrics = struct2table(vertcat(rows{:}));
writetable(metrics,fullfile(outputDir,'paired_confidence_metrics.csv'));
figures(2) = figure; hold on; grid on;
for j = 1:numel(results)
    tr = load(results(j).trainFile,'history','completedTrials');
    infos = tr.history.updateInfo(1:tr.completedTrials);
    gates = cellfun(@(x)x.gate,infos);
    use = isfinite(gates);
    plot(find(use),gates(use),'-o','DisplayName',results(j).method);
end
xlabel('Physical training acquisition'); ylabel('Scalar gate');
legend('Location','best');
save_experiment_figures(outputDir,figures);
save_experiment_result(outputDir,'paired_confidence_metrics',struct('metrics',metrics));
end
