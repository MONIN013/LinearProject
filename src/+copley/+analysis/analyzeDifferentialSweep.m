function result = analyzeDifferentialSweep(rawLog, plan)
%ANALYZEDIFFERENTIALSWEEP Estimate the d-axis origin from alpha/alpha+pi pulses.
T = copley.analysis.toSampleTable(rawLog, plan, uint16(1));
result = localBaseResult();

if height(T) == 0
    result.reason = 'protocol 1 log is empty';
    result.quality = localQuality(false, result.reason);
    return;
end
if ~localHasVars(T, {'phase_id', 'angle_index', 'x_abs_m'})
    result.reason = 'protocol 1 log is missing phase/angle/position columns';
    result.quality = localQuality(false, result.reason);
    return;
end

angleIds = unique(T.angle_index(:))';
alpha = [];
response = [];
dxPositive = [];
dxOpposite = [];
actualMax = 0;
targetMax = 0;

for i = 1:numel(angleIds)
    angleId = angleIds(i);
    A = T(T.angle_index == angleId, :);
    P = A(A.phase_id == 1, :);
    N = A(A.phase_id == 3, :);
    if height(P) < 2 || height(N) < 2
        continue;
    end
    dxP = localPulseDelta(P.x_abs_m);
    dxN = localPulseDelta(N.x_abs_m);
    alpha(end+1, 1) = localAngleForPulse(P, plan, angleId); %#ok<AGROW>
    response(end+1, 1) = 0.5 .* (dxP - dxN); %#ok<AGROW>
    dxPositive(end+1, 1) = dxP; %#ok<AGROW>
    dxOpposite(end+1, 1) = dxN; %#ok<AGROW>
    actualMax = max(actualMax, max(abs(double(A.actual_current_count))));
    targetMax = max(targetMax, max(abs(double(A.target_current_count))));
end

if numel(response) < 4
    result.reason = 'protocol 1 has too few complete angle pulses';
    result.quality = localQuality(false, result.reason);
    result.alpha_rad = alpha;
    result.response = response;
    return;
end

X = [cos(alpha), sin(alpha), ones(size(alpha))];
coeff = X \ response;
fit = X * coeff;
residual = response - fit;
ssRes = sum(residual .^ 2);
ssTot = sum((response - mean(response)) .^ 2);
if ssTot > 0
    rSquared = 1.0 - ssRes ./ ssTot;
else
    rSquared = 0.0;
end

fitPhase = copley.analysis.wrapTo2Pi(atan2(coeff(2), coeff(1)));
thetaE = localSelectThetaCandidate(fitPhase, plan);
xMean = median(double(T.x_abs_m));
electricalAngleSign = double(copley.domain.normalizeElectricalAngleSign( ...
    localField(plan, 'electrical_angle_sign', 1)));
thetaOffset = copley.analysis.wrapTo2Pi(thetaE ...
    - electricalAngleSign .* 2*pi ...
      .* (xMean - localField(plan, 'x_ref_m', 0.0)) ...
      ./ localField(plan, 'tau_e_m', 0.036));

amplitude = hypot(coeff(1), coeff(2));
residualRms = sqrt(mean(residual .^ 2));
maxAbsDx = max(abs([dxPositive(:); dxOpposite(:)]));
minRequiredDx = localAnalysisField(plan, 'protocol1_min_required_dx_m', 5.0e-6);
minRSquared = localAnalysisField(plan, 'protocol1_min_r_squared', 0.80);

accepted = isfinite(thetaOffset) ...
    && rSquared >= minRSquared ...
    && localMeetsMinimum(maxAbsDx, minRequiredDx) ...
    && amplitude > 0;
if accepted
    reason = 'differential sweep accepted';
else
    reason = sprintf(['differential sweep rejected: r_squared=%.4g, ' ...
        'max_abs_dx_m=%.4g'], rSquared, maxAbsDx);
end

result.accepted = logical(accepted);
result.reason = reason;
result.theta_e_hat_rad = thetaE;
result.theta_e_hat_deg = thetaE * 180/pi;
result.fit_phase_rad = fitPhase;
result.fit_phase_deg = fitPhase * 180/pi;
result.theta_offset_hat_rad = thetaOffset;
result.theta_offset_hat_deg = thetaOffset * 180/pi;
estimate = copley.analysis.buildEstimationReference(T, plan, thetaOffset);
result.estimation_absolute_position_raw = ...
    estimate.estimation_absolute_position_raw;
result.estimation_position_m = estimate.estimation_position_m;
result.theta_at_estimation_rad = estimate.theta_at_estimation_rad;
result.theta_at_estimation_deg = estimate.theta_at_estimation_deg;
result.coefficients = coeff(:)';
result.alpha_rad = alpha(:)';
result.response = response(:)';
result.fit = fit(:)';
result.residual = residual(:)';
result.dx_positive_m = dxPositive(:)';
result.dx_opposite_m = dxOpposite(:)';
result.quality = localQuality(accepted, reason);
result.quality.r_squared = rSquared;
result.quality.residual_rms = residualRms;
result.quality.amplitude = amplitude;
result.quality.max_abs_dx_m = maxAbsDx;
result.quality.min_required_dx_m = minRequiredDx;
result.quality.max_abs_actual_current_count = actualMax;
result.quality.max_abs_target_current_count = targetMax;
result.quality.max_abs_actual_current_A = actualMax ...
    * double(localField(plan, 'actual_current_A_per_1000', 0.1)) / 1000.0;
result.quality.max_abs_target_current_A = targetMax ...
    * double(localField(plan, 'target_torque_A_per_1000', 0.1)) / 1000.0;
result.next_theta_offset_seed_rad = copley.analysis.wrapTo2Pi(thetaOffset ...
    + localAnalysisField(plan, 'protocol2_axis_shift_rad', pi/4));
end

function theta = localSelectThetaCandidate(fitPhase, plan)
offset = localAnalysisField(plan, 'protocol1_phase_offset_rad', 0.0);
theta = copley.analysis.wrapTo2Pi(fitPhase + offset);
reference = localAnalysisField(plan, 'protocol1_theta_reference_rad', NaN);
if isfinite(reference)
    candidates = copley.analysis.wrapTo2Pi([fitPhase, fitPhase - pi/2]);
    d = [localCircularDistance(candidates(1), reference), ...
        localCircularDistance(candidates(2), reference)];
    [~, idx] = min(d);
    theta = candidates(idx);
end
end

function d = localCircularDistance(a, b)
d = abs(atan2(sin(a - b), cos(a - b)));
end

function result = localBaseResult()
result = struct();
result.method = 'differential_sweep';
result.protocol_id = uint16(1);
result.accepted = false;
result.reason = '';
result.quality = localQuality(false, '');
end

function dx = localPulseDelta(x)
x = double(x(:));
if numel(x) < 2
    dx = 0.0;
    return;
end
dx = x(end) - x(1);
end

function alpha = localAngleForPulse(P, plan, angleId)
if ismember('experiment_angle_rad', P.Properties.VariableNames) && height(P) > 0
    alpha = median(double(P.experiment_angle_rad));
else
    alpha = localField(plan, 'angle_start_rad', 0.0) ...
        + double(angleId) .* localField(plan, 'angle_step_rad', pi/6);
end
alpha = copley.analysis.wrapTo2Pi(alpha);
end

function tf = localHasVars(T, names)
tf = true;
for i = 1:numel(names)
    tf = tf && ismember(names{i}, T.Properties.VariableNames);
end
end

function quality = localQuality(accepted, reason)
quality = struct();
quality.accepted = logical(accepted);
quality.reason = reason;
end

function value = localAnalysisField(plan, name, defaultValue)
value = defaultValue;
if isstruct(plan) && isfield(plan, 'analysis') && isstruct(plan.analysis) ...
        && isfield(plan.analysis, name)
    value = plan.analysis.(name);
elseif isstruct(plan) && isfield(plan, name)
    value = plan.(name);
end
end

function tf = localMeetsMinimum(value, minimum)
tol = max(1.0e-12, 1.0e-9 .* abs(double(minimum)));
tf = double(value) + tol >= double(minimum);
end

function value = localField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
end
