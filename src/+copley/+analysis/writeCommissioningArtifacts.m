function theta = writeCommissioningArtifacts(result, runDir, varargin)
%WRITECOMMISSIONINGARTIFACTS Persist theta_result.json, report.md, and figures.
if nargin < 2 || isempty(runDir)
    runDir = pwd;
end
showFigures = localShowFigures(varargin{:});
if ~exist(runDir, 'dir')
    mkdir(runDir);
end
figDir = fullfile(runDir, 'figures');
if ~exist(figDir, 'dir')
    mkdir(figDir);
end

theta = copley.analysis.buildThetaResult(result);
localWriteText(fullfile(runDir, 'theta_result.json'), jsonencode(theta));
localWriteText(fullfile(runDir, 'report.md'), localReport(theta));
localWriteFigures(result, theta, figDir, showFigures);
end

function localWriteFigures(result, theta, figDir, showFigures)
localPlotTimeSeries(result, figDir, showFigures);
if isfield(theta, 'protocol1')
    localPlotDifferential(theta.protocol1, figDir, showFigures);
end
if isfield(theta, 'protocol2')
    localPlotProtocol2(theta.protocol2, figDir, showFigures);
end
if isfield(theta, 'protocol3')
    localPlotQAxis(theta.protocol3, figDir, showFigures);
end
end

function localPlotTimeSeries(result, figDir, showFigures)
[T, ok] = localCombinedTable(result);
if ~ok || height(T) == 0
    return;
end
f = localFigure(showFigures);
subplot(2, 1, 1);
[tx, x] = localPlotBreaks(T, T.x_abs_m);
plot(tx, x, 'LineWidth', 1.0);
grid on;
xlabel('t [s]');
ylabel('position [m]');
title('Position');
subplot(2, 1, 2);
[tx, iq] = localPlotBreaks(T, T.iq_cmd_A);
plot(tx, iq, 'LineWidth', 1.0);
hold on;
[tx, outputTorque] = localPlotBreaks(T, T.output_torque_A);
plot(tx, outputTorque, '--', 'LineWidth', 1.0);
[tx, actualCurrent] = localPlotBreaks(T, T.actual_current_A);
plot(tx, actualCurrent, ':', 'LineWidth', 1.0);
grid on;
xlabel('t [s]');
ylabel('current [A]');
legend({'iq request', 'output torque', 'actual current'}, 'Location', 'best');
title('Current');
localSaveFigure(f, fullfile(figDir, 'time_series.svg'), showFigures);
end

function [x, y] = localPlotBreaks(T, values)
x = double(T.t_s(:));
y = double(values(:));
if numel(x) < 2
    return;
end
breakAt = false(size(x));
dt = localMedianPositiveDiff(x);
if ~isfinite(dt) || dt <= 0.0
    dt = 0.0;
end
timeGap = diff(x) > max(10.0 * dt, dt + eps);
phaseGap = diff(double(T.protocol_id(:))) ~= 0 ...
    | diff(double(T.phase_id(:))) ~= 0;
sampleGap = diff(double(T.sample_index(:))) > 1.0;
breakAt(2:end) = timeGap | phaseGap | sampleGap;
x(breakAt) = NaN;
y(breakAt) = NaN;
end

function localPlotDifferential(p1, figDir, showFigures)
if ~isfield(p1, 'alpha_rad') || isempty(p1.alpha_rad)
    return;
end
alphaDeg = double(p1.alpha_rad(:)) * 180/pi;
f = localFigure(showFigures);
plot(alphaDeg, double(p1.response(:)), 'o', 'LineWidth', 1.0);
hold on;
if isfield(p1, 'fit')
    plot(alphaDeg, double(p1.fit(:)), '-', 'LineWidth', 1.2);
end
grid on;
xlabel('experiment angle [deg]');
ylabel('differential response [m]');
legend({'measured', 'sine fit'}, 'Location', 'best');
title('Differential Sweep Fit');
localSaveFigure(f, fullfile(figDir, 'differential_angle_fit.svg'), showFigures);

if isfield(p1, 'residual')
    f = localFigure(showFigures);
    stem(alphaDeg, double(p1.residual(:)), 'filled');
    grid on;
    xlabel('experiment angle [deg]');
    ylabel('residual [m]');
    title('Differential Sweep Residual');
    localSaveFigure(f, fullfile(figDir, 'differential_residual.svg'), showFigures);
end
end

function localPlotProtocol2(p2, figDir, showFigures)
stage = p2;
if isfield(p2, 'coarse') && isstruct(p2.coarse)
    stage = p2.coarse;
end
if ~isfield(stage, 'regression_x_A') || isempty(stage.regression_x_A)
    return;
end
x = double(stage.regression_x_A(:));
y = double(stage.regression_y_A(:));
f = localFigure(showFigures);
plot(x, y, '.', 'MarkerSize', 8);
hold on;
lim = max(abs([x; y]));
plot([-lim lim], [-lim lim], 'k--', 'LineWidth', 1.0);
grid on;
xlabel('d-axis shifted current [A]');
ylabel('q-axis shifted current [A]');
title('Protocol 2 Current Pair Regression');
localSaveFigure(f, fullfile(figDir, 'protocol2_regression.svg'), showFigures);

f = localFigure(showFigures);
plot(x, 'LineWidth', 1.0);
hold on;
plot(y, 'LineWidth', 1.0);
grid on;
xlabel('paired sample');
ylabel('current [A]');
legend({'d-axis shifted', 'q-axis shifted'}, 'Location', 'best');
title('Protocol 2 Paired Currents');
localSaveFigure(f, fullfile(figDir, ...
    'protocol2_current_pair_shifted_axis.svg'), showFigures);

if isfield(stage, 'epsilon_samples_rad')
    eDeg = double(stage.epsilon_samples_rad(:)) * 180/pi;
    axisShiftDeg = double(localField(stage, 'axis_shift_deg', 45.0));
    f = localFigure(showFigures);
    plot(eDeg - axisShiftDeg, '.', 'MarkerSize', 8);
    grid on;
    xlabel('paired sample');
    ylabel('shift error [deg]');
    title(sprintf('Protocol 2 %.6gdeg Shift Samples', axisShiftDeg));
    localSaveFigure(f, fullfile(figDir, ...
        'protocol2_epsilon_samples.svg'), showFigures);

    f = localFigure(showFigures);
    residual = eDeg - median(eDeg);
    plot(residual, '.', 'MarkerSize', 8);
    grid on;
    xlabel('paired sample');
    ylabel('residual [deg]');
    title('Protocol 2 Shift Residual');
    localSaveFigure(f, fullfile(figDir, ...
        'protocol2_residual.svg'), showFigures);
end
end

function localPlotQAxis(p3, figDir, showFigures)
if ~isfield(p3, 'positive_response_m') || ~isfield(p3, 'negative_response_m')
    return;
end
f = localFigure(showFigures);
bar([double(p3.positive_response_m), double(p3.negative_response_m)]);
set(gca, 'XTickLabel', {'positive q', 'negative q'});
grid on;
ylabel('response [m]');
title('Q-axis Pulse Response');
localSaveFigure(f, fullfile(figDir, 'q_axis_response.svg'), showFigures);
end

function [T, ok] = localCombinedTable(result)
ok = false;
T = table();
if ~isfield(result, 'protocol_runs')
    return;
end
plans = {};
if isfield(result, 'protocol_plans')
    plans = result.protocol_plans;
end
nextTimeOffset_s = 0.0;
for i = 1:numel(result.protocol_runs)
    run = result.protocol_runs{i};
    if ~isstruct(run) || ~isfield(run, 'rawLog')
        continue;
    end
    plan = [];
    if numel(plans) >= i
        plan = plans{i};
    end
    Ti = copley.analysis.toSampleTable(run.rawLog, plan, []);
    if height(Ti) == 0
        continue;
    end
    Ti = localStandardColumns(Ti);
    [Ti, nextTimeOffset_s] = localOffsetProtocolTime(Ti, nextTimeOffset_s);
    if isempty(T)
        T = Ti;
    else
        T = [T; Ti]; %#ok<AGROW>
    end
end
ok = height(T) > 0;
end

function [T, nextTimeOffset_s] = localOffsetProtocolTime(T, timeOffset_s)
localTime = double(T.protocol_t_s(:));
if isempty(localTime) || ~any(isfinite(localTime))
    localTime = double(T.t_s(:));
end
localTime = localTime - localTime(1);
T.protocol_t_s = localTime;
T.t_s = localTime + double(timeOffset_s);

dt = localMedianPositiveDiff(localTime);
if ~isfinite(dt)
    dt = 0.0;
end
nextTimeOffset_s = max(double(T.t_s(:))) + dt;
end

function dt = localMedianPositiveDiff(t)
d = diff(unique(double(t(:))));
d = d(isfinite(d) & d > 0);
if isempty(d)
    dt = NaN;
else
    dt = median(d);
end
end

function T = localStandardColumns(T)
names = {'sample_index', 't_s', 'protocol_t_s', ...
    'protocol_id', 'phase_id', 'angle_index', ...
    'protocol2_local_sample_index', 'experiment_angle_rad', 'x_abs_m', ...
    'x_ref_traj_m', 'v_est_mps', 'v_actual_mps', 'iq_cmd_count_req', ...
    'iq_cmd_count_req_lreal', ...
    'target_current_count_lreal', ...
    'target_current_count', 'output_torque_count', 'actual_current_count', ...
    'iq_cmd_raw_A', 'iq_cmd_A', 'target_current_A', ...
    'output_torque_A', 'actual_current_A'};
for i = 1:numel(names)
    if ~ismember(names{i}, T.Properties.VariableNames)
        T.(names{i}) = zeros(height(T), 1);
    end
end
T = T(:, names);
end

function text = localReport(theta)
acceptedText = '採用不可';
if isfield(theta, 'accepted') && logical(theta.accepted)
    acceptedText = '採用可';
end
reason = '';
if isfield(theta, 'quality') && isfield(theta.quality, 'reason')
    reason = theta.quality.reason;
end

lines = {};
lines{end+1} = '# 磁極位置同定レポート';
lines{end+1} = '';
lines{end+1} = '## 判定サマリ';
lines{end+1} = '';
lines{end+1} = sprintf('- runtime reference_position_count: %d count', ...
    int32(localField(theta, 'reference_position_count', 0)));
lines{end+1} = sprintf(['- runtime reference_commutation_angle: ' ...
    '%u count / %.6g deg'], ...
    uint16(localField(theta, 'reference_commutation_angle', 0)), ...
    localField(theta, 'reference_commutation_angle_deg', NaN));
calibrationMetadata = localField(theta, 'calibration_metadata', struct());
lines{end+1} = sprintf('- calibration metadata: version=%u, valid=%d, accepted=%d', ...
    uint16(localField(calibrationMetadata, 'version', 0)), ...
    logical(localField(calibrationMetadata, 'valid', false)), ...
    logical(localField(calibrationMetadata, 'accepted', false)));
lines{end+1} = sprintf('- 推定時の絶対エンコーダ位置: %d count', ...
    int32(localField(theta, 'estimation_absolute_position_raw', 0)));
lines{end+1} = sprintf('- 推定位置での d軸角: %.12g rad / %.6g deg', ...
    localField(theta, 'theta_at_estimation_rad', NaN), ...
    localField(theta, 'theta_at_estimation_deg', NaN));
lines{end+1} = sprintf('- 絶対位置エンコーダ 0 での d軸角: %.12g rad / %.6g deg', ...
    localField(theta, 'theta_at_absolute_encoder_zero_rad', NaN), ...
    localField(theta, 'theta_at_absolute_encoder_zero_deg', NaN));
lines{end+1} = sprintf('- 推定した d軸原点: %.12g rad / %.6g deg', ...
    localField(theta, 'theta_offset_hat_rad', NaN), ...
    localField(theta, 'theta_offset_hat_deg', NaN));
lines{end+1} = sprintf('- Protocol 3 で確認した d軸原点候補: %.12g rad / %.6g deg', ...
    localField(theta, 'theta_offset_verified_rad', NaN), ...
    localField(theta, 'theta_offset_verified_deg', NaN));
lines{end+1} = sprintf('- 意図的にずらした制御 d-q 軸: %.6g deg', ...
    localField(theta, 'axis_shift_deg', NaN));
lines{end+1} = sprintf('- 45degからの残差: %.6g deg', ...
    localField(theta, 'axis_shift_error_deg', NaN));
lines{end+1} = sprintf('- q軸入力電流 / d軸入力電流: %.6g', ...
    localField(theta, 'current_ratio_q_over_d', NaN));
lines{end+1} = sprintf('- q/d入力電流の相対差: %.6g', ...
    localField(theta, 'current_equality_mismatch_fraction', NaN));
lines{end+1} = sprintf('- q軸符号設定: %d', int16(localField(theta, 'q_axis_sign', int16(1))));
lines{end+1} = sprintf('- 電気角進行方向: %d', ...
    int16(localField(theta, 'electrical_angle_sign', int16(1))));
lines{end+1} = sprintf('- 採用判定: %s', acceptedText);
lines{end+1} = sprintf('- 判定理由: %s', reason);
lines{end+1} = '';
lines{end+1} = '## スケーリング';
lines{end+1} = '';
if isfield(theta, 'scaling') && isstruct(theta.scaling)
    s = theta.scaling;
    lines{end+1} = sprintf('- サンプリング周期 Ts: %.12g s', ...
        localField(s, 'sample_period_s', NaN));
    lines{end+1} = sprintf('- 位置換算: %.12g m/pulse', ...
        localField(s, 'position_m_per_pulse', NaN));
    lines{end+1} = sprintf('- TargetTorque 換算: %.12g A / 1000 count = %.12g A/count', ...
        localField(s, 'target_torque_A_per_1000_count', NaN), ...
        localField(s, 'target_torque_A_per_count', NaN));
    lines{end+1} = sprintf('- 実電流診断換算: %.12g A / 1000 count = %.12g A/count', ...
        localField(s, 'actual_current_A_per_1000_count', NaN), ...
        localField(s, 'actual_current_A_per_count', NaN));
end
lines{end+1} = '';
lines{end+1} = '## 同定シーケンス';
lines{end+1} = '';
lines = localAppendProtocolSummary(lines, theta, 1, '差動角度スイープ');
lines = localAppendProtocolSummary(lines, theta, 2, '45degシフト q/d 電流比較');
lines = localAppendProtocolSummary(lines, theta, 3, 'q軸正逆パルス検証');
lines{end+1} = '';
lines{end+1} = '## 図';
lines{end+1} = '';
lines{end+1} = '![位置と電流の時系列](figures/time_series.svg)';
lines{end+1} = '';
lines{end+1} = '![差動角度スイープの応答と正弦波フィット](figures/differential_angle_fit.svg)';
lines{end+1} = '';
lines{end+1} = '![差動角度スイープの残差](figures/differential_residual.svg)';
lines{end+1} = '';
lines{end+1} = '![Protocol 2 電流比回帰](figures/protocol2_regression.svg)';
lines{end+1} = '';
lines{end+1} = '![Protocol 2 45degシフト q/d 電流ペア](figures/protocol2_current_pair_shifted_axis.svg)';
lines{end+1} = '';
lines{end+1} = '![Protocol 2 45degからのずれサンプル](figures/protocol2_epsilon_samples.svg)';
lines{end+1} = '';
lines{end+1} = '![Protocol 2 角度ずれ残差](figures/protocol2_residual.svg)';
lines{end+1} = '';
lines{end+1} = '![q軸検証の正逆パルス応答](figures/q_axis_response.svg)';
text = sprintf('%s\n', lines{:});
end

function lines = localAppendProtocolSummary(lines, theta, protocolId, label)
key = sprintf('protocol%d', protocolId);
if ~isfield(theta, key)
    lines{end+1} = sprintf('- Protocol %d（%s）: データなし', protocolId, label);
    return;
end
r = theta.(key);
accepted = false;
reason = '';
if isfield(r, 'quality') && isfield(r.quality, 'accepted')
    accepted = logical(r.quality.accepted);
end
if isfield(r, 'quality') && isfield(r.quality, 'reason')
    reason = r.quality.reason;
elseif isfield(r, 'reason')
    reason = r.reason;
end
judge = '採用不可';
if accepted
    judge = '採用可';
end
thetaRad = localField(r, 'theta_offset_hat_rad', ...
    localField(r, 'theta_offset_verified_rad', NaN));
thetaDeg = thetaRad * 180/pi;
lines{end+1} = sprintf('- Protocol %d（%s）: d軸原点=%.12g rad / %.6g deg, 判定=%s, 理由=%s', ...
    protocolId, label, thetaRad, thetaDeg, judge, reason);
end

function f = localFigure(showFigures)
if showFigures
    visibility = 'on';
else
    visibility = 'off';
end
f = figure('Visible', visibility);
end

function localSaveFigure(f, path, keepOpen)
try
    print(f, path, '-dsvg');
catch
    print(f, strrep(path, '.svg', '.png'), '-dpng', '-r150');
end
if ~keepOpen
    close(f);
end
end

function showFigures = localShowFigures(varargin)
p = inputParser;
addParameter(p, 'ShowFigures', false, ...
    @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
parse(p, varargin{:});
showFigures = logical(p.Results.ShowFigures);
end

function localWriteText(path, text)
fid = fopen(path, 'w', 'n', 'UTF-8');
if fid < 0
    error('copley:analysis:WriteFailed', 'Could not write %s.', path);
end
cleanup = onCleanup(@()fclose(fid));
fwrite(fid, text, 'char');
delete(cleanup);
end

function value = localField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
end
