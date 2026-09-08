function result = analyzeIppCurrentRatio(rawLog, plan)
%ANALYZEIPPCURRENTRATIO Estimate d-axis origin from shifted-axis q/d current equality.
T = copley.analysis.toSampleTable(rawLog, plan, uint16(2));
result = localBaseResult(plan);

if height(T) == 0
    result.reason = 'protocol 2 log is empty';
    result.quality = localQuality(false, result.reason);
    return;
end
if ~localHasVars(T, {'phase_id', 'protocol2_local_sample_index', 'iq_cmd_count_req'})
    result.reason = 'protocol 2 log is missing phase/local-sample/current columns';
    result.quality = localQuality(false, result.reason);
    return;
end

pairs = localPairCurrents(T, plan);
result.coarse = pairs;
result.fine = localEmptyStage('fine_symmetric_delta');

if pairs.paired_sample_count == 0
    result.reason = pairs.reason;
    result.quality = localProtocolQuality(false, pairs.reason, pairs);
    return;
end

epsilonHat = median(pairs.epsilon_samples_rad);
axisShift = localAnalysisField(plan, 'protocol2_axis_shift_rad', pi/4);
thetaSeed = localField(plan, 'initial_theta_offset_guess_rad', 0.0);
thetaHat = copley.analysis.wrapTo2Pi(thetaSeed - epsilonHat);
axisShiftError = epsilonHat - axisShift;
ratio = median(abs(pairs.regression_y_count) ./ max(abs(pairs.regression_x_count), 1));
mismatch = mean(abs(abs(pairs.regression_y_count) - abs(pairs.regression_x_count)) ...
    ./ max(max(abs(pairs.regression_x_count), abs(pairs.regression_y_count)), 1));

pairs.epsilon_hat_rad = epsilonHat;
pairs.epsilon_hat_deg = epsilonHat * 180/pi;
pairs.theta_offset_hat_rad = thetaHat;
pairs.theta_offset_hat_deg = thetaHat * 180/pi;
pairs.theta_offset_coarse_rad = thetaHat;
pairs.theta_offset_coarse_deg = thetaHat * 180/pi;
pairs.axis_shift_rad = axisShift;
pairs.axis_shift_deg = axisShift * 180/pi;
pairs.axis_shift_error_rad = axisShiftError;
pairs.axis_shift_error_deg = axisShiftError * 180/pi;
pairs.current_ratio_q_over_d = ratio;
pairs.current_equality_mismatch_fraction = mismatch;

maxAxisShiftErrorDeg = localAnalysisField(plan, 'protocol2_max_axis_shift_error_deg', 7.0);
maxRampLimited = localAnalysisField(plan, 'protocol2_max_ramp_limited_fraction', 0.10);
maxNearZero = localAnalysisField(plan, 'protocol2_max_near_zero_denominator_fraction', 0.10);
maxLowCurrent = localAnalysisField(plan, 'protocol2_max_low_current_pair_fraction', 0.50);
maxDegenerate = localAnalysisField(plan, ...
    'protocol2_max_degenerate_pair_fraction', 0.95);
maxCurrentMismatch = localAnalysisField(plan, ...
    'protocol2_max_current_equality_mismatch_fraction', 0.20);
minPairs = localAnalysisField(plan, 'protocol2_min_paired_sample_count', 20);
minValidPairFraction = localAnalysisField(plan, 'protocol2_min_valid_pair_fraction', 0.10);
rampOk = pairs.ramp_limited_fraction <= maxRampLimited ...
    || pairs.valid_pair_fraction >= minValidPairFraction;

accepted = pairs.paired_sample_count >= minPairs ...
    && abs(pairs.axis_shift_error_deg) <= maxAxisShiftErrorDeg ...
    && rampOk ...
    && pairs.near_zero_denominator_fraction <= maxNearZero ...
    && pairs.low_current_pair_fraction <= maxLowCurrent ...
    && pairs.degenerate_pair_fraction <= maxDegenerate ...
    && pairs.current_equality_mismatch_fraction <= maxCurrentMismatch ...
    && isfinite(thetaHat);
if accepted
    reason = 'shifted-axis stage accepted';
else
    reason = sprintf(['shifted-axis stage rejected: pairs=%u, ' ...
        'axis_shift_error_deg=%.4g, ramp_limited_fraction=%.4g, ' ...
        'valid_pair_fraction=%.4g, degenerate_pair_fraction=%.4g, ' ...
        'current_equality_mismatch_fraction=%.4g'], ...
        uint32(pairs.paired_sample_count), pairs.axis_shift_error_deg, ...
        pairs.ramp_limited_fraction, pairs.valid_pair_fraction, ...
        pairs.degenerate_pair_fraction, pairs.current_equality_mismatch_fraction);
end
pairs.accepted = logical(accepted);
pairs.reason = reason;

result.accepted = logical(accepted);
result.reason = reason;
result.coarse = pairs;
result.quality = localProtocolQuality(accepted, reason, pairs);
result.epsilon_coarse_rad = epsilonHat;
result.epsilon_coarse_deg = epsilonHat * 180/pi;
result.theta_offset_coarse_rad = thetaHat;
result.theta_offset_coarse_deg = thetaHat * 180/pi;
result.axis_shift_deg = pairs.axis_shift_deg;
result.axis_shift_error_deg = pairs.axis_shift_error_deg;
result.current_ratio_q_over_d = ratio;
result.current_equality_mismatch_fraction = mismatch;
result.theta_offset_hat_rad = thetaHat;
result.theta_offset_hat_deg = thetaHat * 180/pi;
estimate = copley.analysis.buildEstimationReference(T, plan, thetaHat);
result.estimation_absolute_position_raw = ...
    estimate.estimation_absolute_position_raw;
result.estimation_position_m = estimate.estimation_position_m;
result.theta_at_estimation_rad = estimate.theta_at_estimation_rad;
result.theta_at_estimation_deg = estimate.theta_at_estimation_deg;
result.next_theta_offset_seed_rad = thetaHat;
result.current_source = pairs.current_source;
result.current_source_definition = pairs.current_source_definition;
result.current_scale_A_per_count = pairs.current_scale_A_per_count;
end

function result = localBaseResult(plan)
result = struct();
result.method = 'ipp_current_ratio';
result.protocol_id = uint16(2);
result.theta_offset_seed_rad = localField(plan, 'initial_theta_offset_guess_rad', 0.0);
result.theta_offset_seed_deg = result.theta_offset_seed_rad * 180/pi;
result.current_source = 'auto';
result.current_source_definition = 'resolved during Protocol 2 pairing';
result.current_scale_A_per_count = NaN;
result.velocity_limit_source = 'v_est_mps';
result.pairing_mode = 'local_sample_index';
result.accepted = false;
result.reason = '';
end

function pairs = localPairCurrents(T, plan)
pairs = localEmptyStage('shifted_axis_q_d');
pairs.has_data = true;
pairs.pairing_mode = 'local_sample_index';
currentSource = localCurrentSource(T, plan);
pairs.current_source = currentSource.name;
pairs.current_source_definition = currentSource.definition;
pairs.current_scale_A_per_count = currentSource.scale;

Q = sortrows(T(T.phase_id == 10, :), {'sample_index'});
D = sortrows(T(T.phase_id == 11, :), {'sample_index'});
if height(Q) == 0 || height(D) == 0
    pairs.reason = 'protocol 2 does not contain phase 10 and phase 11 samples';
    return;
end

localIds = intersect(unique(Q.protocol2_local_sample_index), ...
    unique(D.protocol2_local_sample_index));
edgeDiscard_s = localAnalysisField(plan, 'protocol2_edge_discard_s', 0.002);
dt = localMedianDt(T);
edgeSamples = ceil(edgeDiscard_s ./ max(dt, eps));

x = [];
y = [];
commandX = [];
commandY = [];
targetX = [];
targetY = [];
outputX = [];
outputY = [];
vel = [];
localIndex = [];
for i = 1:numel(localIds)
    id = localIds(i);
    if double(id) <= edgeSamples
        continue;
    end
    qRows = Q(Q.protocol2_local_sample_index == id, :);
    dRows = D(D.protocol2_local_sample_index == id, :);
    n = min(height(qRows), height(dRows));
    for j = 1:n
        x(end+1, 1) = double(dRows.(currentSource.column)(j)); %#ok<AGROW>
        y(end+1, 1) = double(qRows.(currentSource.column)(j)); %#ok<AGROW>
        commandX(end+1, 1) = localCommandCurrentCount(dRows, j); %#ok<AGROW>
        commandY(end+1, 1) = localCommandCurrentCount(qRows, j); %#ok<AGROW>
        targetX(end+1, 1) = localTargetCurrentCount(dRows, j); %#ok<AGROW>
        targetY(end+1, 1) = localTargetCurrentCount(qRows, j); %#ok<AGROW>
        outputX(end+1, 1) = double(dRows.output_torque_count(j)); %#ok<AGROW>
        outputY(end+1, 1) = double(qRows.output_torque_count(j)); %#ok<AGROW>
        vel(end+1, 1) = max(abs(double(dRows.v_est_mps(j))), ...
            abs(double(qRows.v_est_mps(j)))); %#ok<AGROW>
        localIndex(end+1, 1) = double(id); %#ok<AGROW>
    end
end

pairs.paired_sample_count_before_guards = uint32(numel(x));
if isempty(x)
    pairs.reason = 'protocol 2 has no paired samples after edge discard';
    return;
end

maxTarget = max(max(abs([commandX; commandY; targetX; targetY; outputX; outputY])), ...
    double(localProtocolField(plan, 2, 'max_target_count', localField(plan, 'max_target_count', 50))));
if maxTarget <= 0
    maxTarget = 1;
end
minCurrent = localAnalysisField(plan, 'protocol2_min_pair_current_count', ...
    5);
rampTol = localAnalysisField(plan, 'protocol2_ramp_delta_tol_count', ...
    50);
nearZero = abs(x) < minCurrent | abs(y) < minCurrent;
lowCurrent = nearZero;
saturated = abs(commandX) >= 0.98 * maxTarget | abs(commandY) >= 0.98 * maxTarget ...
    | abs(targetX) >= 0.98 * maxTarget | abs(targetY) >= 0.98 * maxTarget;
rampLimited = abs(targetX - commandX) > rampTol ...
    | abs(targetY - commandY) > rampTol;

stationaryThreshold = localAnalysisField(plan, 'protocol2_min_ref_velocity_mps', ...
    localAnalysisField(plan, 'protocol2_min_ref_velocity_fraction', 0.0) ...
    * localField(plan, 'protocol2_vmax_mps', 0.002));
stationary = vel <= stationaryThreshold;

valid = ~nearZero & ~saturated & ~rampLimited;
if ~any(valid)
    pairs.reason = 'all protocol 2 pairs were removed by current/ramp/saturation guards';
    pairs.near_zero_denominator_fraction = mean(double(nearZero));
    pairs.low_current_pair_fraction = mean(double(lowCurrent));
    pairs.saturation_fraction = mean(double(saturated));
    pairs.ramp_limited_fraction = mean(double(rampLimited));
    pairs.stationary_sample_fraction = mean(double(stationary));
    pairs.degenerate_pair_fraction = 1.0;
    return;
end

xv = x(valid);
yv = y(valid);
pairs.paired_sample_count = uint32(numel(xv));
pairs.valid_pair_fraction = double(numel(xv)) ./ double(numel(x));
pairs.saturation_fraction = mean(double(saturated));
pairs.ramp_limited_fraction = mean(double(rampLimited));
pairs.near_zero_denominator_fraction = mean(double(nearZero));
pairs.low_current_pair_fraction = mean(double(lowCurrent));
pairs.stationary_sample_fraction = mean(double(stationary));
pairs.target_actual_delta_deg = localTargetActualDeltaDeg(xv, yv, targetX(valid), targetY(valid));
pairs.degenerate_pair_fraction = localDegeneratePairFraction(xv, yv);
pairs.beta_rad = [0, -pi/2];
pairs.I0 = median(yv);
pairs.I90 = median(xv);
pairs.I0_A = pairs.I0 .* pairs.current_scale_A_per_count;
pairs.I90_A = pairs.I90 .* pairs.current_scale_A_per_count;
pairs.epsilon_samples_rad = atan2(abs(yv), abs(xv));
pairs.regression_x_count = xv(:)';
pairs.regression_y_count = yv(:)';
pairs.regression_x_A = pairs.regression_x_count .* pairs.current_scale_A_per_count;
pairs.regression_y_A = pairs.regression_y_count .* pairs.current_scale_A_per_count;
pairs.command_x_count = commandX(valid)';
pairs.command_y_count = commandY(valid)';
pairs.target_x_count = targetX(valid)';
pairs.target_y_count = targetY(valid)';
pairs.output_x_count = outputX(valid)';
pairs.output_y_count = outputY(valid)';
pairs.local_sample_index = localIndex(valid)';
pairs.reason = 'paired samples analyzed';
end

function source = localCurrentSource(T, plan)
requested = localRequestedCurrentSource(plan);
if ~isempty(requested)
    source = localSourceForColumn(T, plan, requested);
    if ~isempty(source)
        return;
    end
end

if localLoggedFiniteColumn(T, 'iq_cmd_count_req_lreal')
    source = localSource('iq_cmd_count_req_lreal_A', ...
        'controller current request immediately before INT conversion', ...
        'iq_cmd_count_req_lreal', localTargetAperCount(plan));
elseif localColumnHasSignal(T, 'iq_cmd_count_req')
    source = localSource('iq_cmd_count_req_A', ...
        'controller current request after INT conversion', ...
        'iq_cmd_count_req', localTargetAperCount(plan));
elseif localLoggedFiniteColumn(T, 'target_current_count_lreal')
    source = localSource('target_current_count_lreal_A', ...
        'ramped target current immediately before INT conversion', ...
        'target_current_count_lreal', localTargetAperCount(plan));
elseif localColumnHasSignal(T, 'target_current_count')
    source = localSource('target_current_count_A', ...
        'ramped target current after INT conversion', ...
        'target_current_count', localTargetAperCount(plan));
else
    source = localSource('actual_current_A', ...
        'drive actual current feedback converted to ampere', ...
        'actual_current_count', localActualAperCount(plan));
end
end

function requested = localRequestedCurrentSource(plan)
requested = localAnalysisField(plan, 'protocol2_current_source', '');
if isstring(requested)
    requested = char(requested);
end
if ~ischar(requested)
    requested = '';
end
requested = lower(strtrim(requested));
end

function source = localSourceForColumn(T, plan, requested)
source = [];
switch requested
    case {'iq_cmd_count_req_lreal', 'iq_cmd_count_req_lreal_a', ...
            'raw', 'raw_lreal', 'command_lreal'}
        if localLoggedFiniteColumn(T, 'iq_cmd_count_req_lreal')
            source = localSource('iq_cmd_count_req_lreal_A', ...
                'controller current request immediately before INT conversion', ...
                'iq_cmd_count_req_lreal', localTargetAperCount(plan));
        end
    case {'iq_cmd_count_req', 'iq_cmd_a', 'command'}
        if localColumnHasSignal(T, 'iq_cmd_count_req')
            source = localSource('iq_cmd_count_req_A', ...
                'controller current request after INT conversion', ...
                'iq_cmd_count_req', localTargetAperCount(plan));
        end
    case {'target_current_count_lreal', 'target_current_count_lreal_a', ...
            'target_lreal'}
        if localLoggedFiniteColumn(T, 'target_current_count_lreal')
            source = localSource('target_current_count_lreal_A', ...
                'ramped target current immediately before INT conversion', ...
                'target_current_count_lreal', localTargetAperCount(plan));
        end
    case {'target_current_count', 'target_current_a', 'target'}
        if localColumnHasSignal(T, 'target_current_count')
            source = localSource('target_current_count_A', ...
                'ramped target current after INT conversion', ...
                'target_current_count', localTargetAperCount(plan));
        end
    case {'output_torque_count', 'output_torque_a', 'output'}
        if localColumnHasSignal(T, 'output_torque_count')
            source = localSource('output_torque_A', ...
                'motor runtime output torque command converted to ampere', ...
                'output_torque_count', localTargetAperCount(plan));
        end
    case {'actual_current_count', 'actual_current_a', 'actual'}
        if localColumnHasSignal(T, 'actual_current_count')
            source = localSource('actual_current_A', ...
                'drive actual current feedback converted to ampere', ...
                'actual_current_count', localActualAperCount(plan));
        end
end
end

function source = localSource(name, definition, column, scale)
source = struct();
source.name = name;
source.definition = definition;
source.column = column;
source.scale = scale;
end

function tf = localLoggedFiniteColumn(T, name)
flagName = [name '_from_log'];
tf = ismember(name, T.Properties.VariableNames) ...
    && ismember(flagName, T.Properties.VariableNames) ...
    && any(logical(T.(flagName)) & isfinite(double(T.(name))) ...
        & double(T.(name)) ~= 0);
end

function tf = localColumnHasSignal(T, name)
tf = ismember(name, T.Properties.VariableNames) ...
    && any(isfinite(double(T.(name))) & double(T.(name)) ~= 0);
end

function value = localCommandCurrentCount(T, row)
if localLoggedFiniteColumn(T, 'iq_cmd_count_req_lreal')
    value = double(T.iq_cmd_count_req_lreal(row));
else
    value = double(T.iq_cmd_count_req(row));
end
end

function value = localTargetCurrentCount(T, row)
if localLoggedFiniteColumn(T, 'target_current_count_lreal')
    value = double(T.target_current_count_lreal(row));
else
    value = double(T.target_current_count(row));
end
end

function fraction = localDegeneratePairFraction(x, y)
if isempty(x)
    fraction = 1.0;
    return;
end
tolerance = 0.5;
fraction = mean(double(abs(double(x(:)) - double(y(:))) <= tolerance));
end

function deg = localTargetActualDeltaDeg(x, y, targetX, targetY)
currentAngle = atan2(median(abs(y)), median(abs(x)));
targetAngle = atan2(median(abs(targetY)), median(abs(targetX)));
deg = (currentAngle - targetAngle) * 180/pi;
if ~isfinite(deg)
    deg = 0.0;
end
end

function dt = localMedianDt(T)
if ismember('protocol_t_s', T.Properties.VariableNames)
    t = double(T.protocol_t_s(:));
elseif ismember('t_s', T.Properties.VariableNames)
    t = double(T.t_s(:));
else
    dt = 0.000125;
    return;
end
d = diff(unique(t));
d = d(isfinite(d) & d > 0);
if isempty(d)
    dt = 0.000125;
else
    dt = median(d);
end
end

function stage = localEmptyStage(name)
stage = struct();
stage.name = name;
stage.has_data = false;
stage.accepted = false;
stage.reason = 'stage data not present';
stage.pairing_mode = 'none';
stage.current_source = '';
stage.current_source_definition = '';
stage.current_scale_A_per_count = NaN;
stage.paired_sample_count = uint32(0);
stage.paired_sample_count_before_guards = uint32(0);
stage.valid_pair_fraction = 0.0;
stage.saturation_fraction = 1.0;
stage.ramp_limited_fraction = 1.0;
stage.near_zero_denominator_fraction = 1.0;
stage.low_current_pair_fraction = 1.0;
stage.stationary_sample_fraction = 1.0;
stage.degenerate_pair_fraction = 1.0;
stage.current_equality_mismatch_fraction = Inf;
stage.target_actual_delta_deg = NaN;
stage.epsilon_samples_rad = [];
stage.regression_x_count = [];
stage.regression_y_count = [];
stage.regression_x_A = [];
stage.regression_y_A = [];
end

function quality = localProtocolQuality(accepted, reason, pairs)
quality = localQuality(accepted, reason);
quality.coarse_accepted = logical(accepted);
quality.fine_accepted = false;
quality.paired_sample_count = uint32(pairs.paired_sample_count);
quality.valid_pair_fraction = pairs.valid_pair_fraction;
quality.saturation_fraction = pairs.saturation_fraction;
quality.ramp_limited_fraction = pairs.ramp_limited_fraction;
quality.near_zero_denominator_fraction = pairs.near_zero_denominator_fraction;
quality.low_current_pair_fraction = pairs.low_current_pair_fraction;
quality.stationary_sample_fraction = pairs.stationary_sample_fraction;
quality.degenerate_pair_fraction = pairs.degenerate_pair_fraction;
quality.current_equality_mismatch_fraction = ...
    pairs.current_equality_mismatch_fraction;
quality.target_actual_delta_deg = pairs.target_actual_delta_deg;
end

function quality = localQuality(accepted, reason)
quality = struct();
quality.accepted = logical(accepted);
quality.reason = reason;
end

function tf = localHasVars(T, names)
tf = true;
for i = 1:numel(names)
    tf = tf && ismember(names{i}, T.Properties.VariableNames);
end
end

function value = localProtocolField(plan, protocolId, fieldName, defaultValue)
value = defaultValue;
if isstruct(plan) && isfield(plan, fieldName)
    value = plan.(fieldName);
end
key = sprintf('protocol%d', double(protocolId));
if isstruct(plan) && isfield(plan, key)
    p = plan.(key);
    if isstruct(p) && isfield(p, fieldName)
        value = p.(fieldName);
    end
end
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

function value = localField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
end

function scale = localTargetAperCount(plan)
scale = double(localField(plan, 'target_torque_A_per_1000', 0.1)) / 1000.0;
end

function scale = localActualAperCount(plan)
scale = double(localField(plan, 'actual_current_A_per_1000', 0.1)) / 1000.0;
end
