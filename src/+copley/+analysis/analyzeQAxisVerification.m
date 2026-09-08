function result = analyzeQAxisVerification(rawLog, plan)
%ANALYZEQAXISVERIFICATION Check q-axis sign with positive/negative pulses.
T = copley.analysis.toSampleTable(rawLog, plan, uint16(3));
result = localBaseResult(plan);

if height(T) == 0
    result.reason = 'protocol 3 log is empty';
    result.quality = localQuality(false, result.reason);
    return;
end
if ~localHasVars(T, {'phase_id', 'x_abs_m', 'v_actual_mps'})
    result.reason = 'protocol 3 log is missing phase/position/velocity columns';
    result.quality = localQuality(false, result.reason);
    return;
end

positive = localPulseResponse(T(T.phase_id == 1, :), plan);
negative = localPulseResponse(T(T.phase_id == 3, :), plan);
minResponse = localAnalysisField(plan, 'protocol3_min_response_m', 1.0e-8);
allowOneSided = logical(localAnalysisField(plan, ...
    'protocol3_allow_one_sided_response', false));
qSign = int16(localField(plan, 'q_axis_sign', 1));

positiveOk = positive.response_m > minResponse;
negativeOk = negative.response_m < -minResponse;
reversed = positive.response_m < -minResponse && negative.response_m > minResponse;
positiveWeak = abs(positive.response_m) <= minResponse;
negativeWeak = abs(negative.response_m) <= minResponse;
oneSided = false;
if positiveOk && negativeOk
    accepted = true;
    recommended = qSign;
    reason = 'q-axis response accepted';
elseif reversed
    accepted = true;
    recommended = int16(-double(qSign));
    reason = 'q-axis response accepted with reversed sign recommendation';
elseif allowOneSided && positiveOk && negativeWeak
    accepted = true;
    recommended = qSign;
    oneSided = true;
    reason = 'q-axis response accepted from positive pulse';
elseif allowOneSided && negativeOk && positiveWeak
    accepted = true;
    recommended = qSign;
    oneSided = true;
    reason = 'q-axis response accepted from negative pulse';
elseif allowOneSided && positive.response_m < -minResponse && negativeWeak
    accepted = true;
    recommended = int16(-double(qSign));
    oneSided = true;
    reason = 'q-axis response accepted from reversed positive pulse';
elseif allowOneSided && negative.response_m > minResponse && positiveWeak
    accepted = true;
    recommended = int16(-double(qSign));
    oneSided = true;
    reason = 'q-axis response accepted from reversed negative pulse';
else
    accepted = false;
    recommended = qSign;
    reason = 'q-axis response unclear';
end

theta = copley.analysis.wrapTo2Pi(localField(plan, 'initial_theta_offset_guess_rad', 0.0));
result.accepted = logical(accepted);
result.reason = reason;
result.theta_offset_verified_rad = theta;
result.theta_offset_verified_deg = theta * 180/pi;
result.theta_offset_hat_rad = theta;
result.theta_offset_hat_deg = theta * 180/pi;
estimate = copley.analysis.buildEstimationReference(T, plan, theta);
result.estimation_absolute_position_raw = ...
    estimate.estimation_absolute_position_raw;
result.estimation_position_m = estimate.estimation_position_m;
result.theta_at_estimation_rad = estimate.theta_at_estimation_rad;
result.theta_at_estimation_deg = estimate.theta_at_estimation_deg;
result.q_axis_sign = qSign;
result.recommended_q_axis_sign = int16(recommended);
result.positive_response_m = positive.response_m;
result.negative_response_m = negative.response_m;
result.positive_position_delta_m = positive.position_delta_m;
result.negative_position_delta_m = negative.position_delta_m;
result.positive_velocity_mps = positive.velocity_mps;
result.negative_velocity_mps = negative.velocity_mps;
result.positive_response_source = positive.source;
result.negative_response_source = negative.source;
result.min_response_m = minResponse;
result.quality = localQuality(accepted, reason);
result.quality.positive_ok = logical(positiveOk);
result.quality.negative_ok = logical(negativeOk);
result.quality.reversed = logical(reversed);
result.quality.one_sided = logical(oneSided);
end

function result = localBaseResult(plan)
theta = copley.analysis.wrapTo2Pi(localField(plan, 'initial_theta_offset_guess_rad', 0.0));
result = struct();
result.method = 'q_axis_verification';
result.protocol_id = uint16(3);
result.theta_offset_verified_rad = theta;
result.theta_offset_verified_deg = theta * 180/pi;
result.q_axis_sign = int16(localField(plan, 'q_axis_sign', 1));
result.recommended_q_axis_sign = result.q_axis_sign;
result.accepted = false;
result.reason = '';
end

function r = localPulseResponse(P, plan)
r = struct();
r.position_delta_m = 0.0;
r.velocity_mps = 0.0;
r.response_m = 0.0;
r.source = 'missing';
if height(P) == 0
    return;
end

x = double(P.x_abs_m(:));
r.position_delta_m = x(end) - x(1);
r.velocity_mps = mean(double(P.v_actual_mps(:)));
positionResolution = abs(localField(plan, 'position_m_per_count', 1.0e-7));
if abs(r.position_delta_m) >= max(positionResolution, 1.0e-12)
    r.response_m = r.position_delta_m;
    r.source = 'position_delta';
else
    pulseTime = localProtocolField(plan, 3, 'pulse_time_s', 0.05);
    r.response_m = r.velocity_mps .* pulseTime;
    r.source = 'velocity_fallback';
end
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
