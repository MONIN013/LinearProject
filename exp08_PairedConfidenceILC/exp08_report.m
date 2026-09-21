function metrics = exp08_report(results,manifest,outputDir)
%EXP08_REPORT Acquisition-count comparison and held-out frozen-FF replays.
rows = struct([]); figures = gobjects(0);
figures(1) = figure; hold on; grid on;
active = manifest.activeMask;
for j = 1:numel(results)
    tr = results(j).training; rp = results(j).replay;
    Et = tr.history.e(:,1:tr.completedTrials);
    Er = rp.history.e(:,1:rp.completedTrials);
    Ur = rp.history.u(:,1:rp.completedTrials);
    curve = sqrt(mean(Et(active,:).^2,1));
    plot(1:tr.completedTrials,curve,'-o','DisplayName',results(j).method);
    infos = tr.history.updateInfo(1:tr.completedTrials);
    decisions = sum(cellfun(@(x) x.updateFormed,infos));
    row = struct('method',string(results(j).method), ...
        'trainAcquisitions',tr.completedTrials,'updateDecisions',decisions, ...
        'replayAcquisitions',rp.completedTrials, ...
        'trainingSeconds',tr.elapsedSeconds,'replaySeconds',rp.elapsedSeconds, ...
        'trainMovingRMSMean_m',mean(curve), ...
        'replayMovingRMSMean_m',mean(sqrt(mean(Er(active,:).^2,1))), ...
        'replayFullRMSMean_m',mean(sqrt(mean(Er.^2,1))), ...
        'replayMeanErrorRMS_m',sqrt(mean(mean(Er(active,:),2).^2)), ...
        'replayTrialVariationRMS_m',sqrt(mean(var(Er(active,:),0,2))), ...
        'replayPeakError_m',max(abs(Er),[],'all'), ...
        'replayPeakCommand_A',max(abs(Ur),[],'all'));
    rows(j) = row; %#ok<AGROW>
    % Export diagnostic position/direction gates, not locally weighted inputs.
    for k = 1:numel(infos)
        s = infos{k}.pairStats;
        if ~isfield(s,'binGate') || isempty(s.binGate), continue; end
        d = manifest.binTable(1:numel(s.binGate),:);
        d.acquisition = repmat(k,height(d),1);
        d.signalEnergy = s.binSignalEnergy;
        d.noiseEnergy = s.binNoiseEnergy;
        d.gate = s.binGate;
        if k == 2, bins = d; else, bins = [bins;d]; end %#ok<AGROW>
    end
    if exist('bins','var')
        writetable(bins,fullfile(outputDir,results(j).method+"_position_confidence.csv"));
        clear bins
    end
end
xlabel('Physical training acquisition'); ylabel('Moving-window position RMS [m]');
legend('Location','best');
metrics = struct2table(rows);
writetable(metrics,fullfile(outputDir,'paired_confidence_metrics.csv'));
figures(2) = figure; hold on; grid on;
for j = 1:numel(results)
    infos = results(j).training.history.updateInfo;
    gates = cellfun(@(x) x.gate,infos);
    plot(1:numel(gates),gates,'-o','DisplayName',results(j).method);
end
xlabel('Physical training acquisition'); ylabel('Scalar gate (first pair runs omitted)');
legend('Location','best');
save_experiment_figures(outputDir,figures);
save_experiment_result(outputDir,'paired_confidence_metrics',struct('metrics',metrics));
end
