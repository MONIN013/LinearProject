classdef AnalyzeProtocolUseCase < handle
    %ANALYZEPROTOCOLUSECASE Analyze one protocol using a ProtocolSpec.
    methods
        function result = run(obj, rawLog, protocolSpec, plan) %#ok<INUSD>
            if isstruct(rawLog) && isfield(rawLog, 'analysisResult') ...
                    && isstruct(rawLog.analysisResult)
                result = rawLog.analysisResult;
                return;
            end
            if isstruct(rawLog) && isfield(rawLog, 'synthetic') ...
                    && logical(rawLog.synthetic) ...
                    && ~isfield(rawLog, 'rawTable') ...
                    && ~isfield(rawLog, 'samples')
                result = localSyntheticAcceptedResult(rawLog, protocolSpec, plan);
                return;
            end
            if isstruct(rawLog) && isfield(rawLog, 'accepted') ...
                    && ~logical(rawLog.accepted) ...
                    && ~isfield(rawLog, 'rawTable')
                result = struct();
                result.method = 'forced_rejection';
                result.protocol_id = uint16(protocolSpec.ProtocolId);
                result.accepted = false;
                result.reason = localReason(rawLog);
                result.quality = struct('accepted', false, ...
                    'reason', result.reason);
                return;
            end
            result = protocolSpec.analyze(rawLog, plan);
        end
    end
end

function result = localSyntheticAcceptedResult(rawLog, protocolSpec, plan)
protocolId = uint16(protocolSpec.ProtocolId);
switch double(protocolId)
    case 1
        result = localSyntheticProtocol1(rawLog, plan);
    case 2
        result = localSyntheticProtocol2(rawLog, plan);
    case 3
        result = localSyntheticProtocol3(rawLog, plan);
    otherwise
        result = struct('method', 'synthetic_acceptance', ...
            'protocol_id', protocolId, 'accepted', true, ...
            'reason', 'synthetic dry-run accepted', ...
            'quality', localQuality(true, 'synthetic dry-run accepted'));
end
end

function result = localSyntheticProtocol1(rawLog, plan)
theta = localReferenceTheta(plan, 1.25);
axisShift = localAnalysisField(plan, 'protocol2_axis_shift_rad', ...
    localField(plan, 'protocol2_axis_shift_rad', pi/4));
angleCount = uint16(localProtocolField(plan, 1, 'angle_count', 12));
angleStep = localProtocolField(plan, 1, 'angle_step_rad', pi/6);
angleStart = localProtocolField(plan, 1, 'angle_start_rad', 0.0);
alpha = angleStart + (0:double(angleCount)-1) .* angleStep;
response = 1.0e-5 .* cos(alpha - theta);
result = struct();
result.method = 'synthetic_differential_sweep';
result.protocol_id = uint16(1);
result.accepted = true;
result.reason = 'synthetic differential sweep accepted';
result.theta_e_hat_rad = theta;
result.theta_e_hat_deg = theta * 180/pi;
result.theta_offset_hat_rad = theta;
result.theta_offset_hat_deg = theta * 180/pi;
result.coefficients = [cos(theta), sin(theta), 0.0];
result.alpha_rad = alpha;
result.response = response;
result.fit = response;
result.residual = zeros(size(response));
result.quality = localQuality(true, result.reason);
result.quality.r_squared = 1.0;
result.quality.residual_rms = 0.0;
result.quality.amplitude = max(abs(response));
result.quality.max_abs_dx_m = max(abs(response));
result.quality.min_required_dx_m = localAnalysisField(plan, ...
    'protocol1_min_required_dx_m', 5.0e-6);
result.quality.max_abs_actual_current_count = 100;
result.quality.max_abs_target_current_count = 100;
result.next_theta_offset_seed_rad = copley.analysis.wrapTo2Pi(theta + axisShift);
result = localAddEstimationReference(result, plan, theta);
end

function result = localSyntheticProtocol2(rawLog, plan)
axisShift = localAnalysisField(plan, 'protocol2_axis_shift_rad', ...
    localField(plan, 'protocol2_axis_shift_rad', pi/4));
thetaSeed = localField(plan, 'initial_theta_offset_guess_rad', 1.25 + axisShift);
theta = copley.analysis.wrapTo2Pi(thetaSeed - axisShift);
counts = [100 120 140 160];
amps = counts .* double(localField(plan, 'target_torque_A_per_1000', 0.1)) / 1000.0;
stage = localSyntheticStage(counts, amps, axisShift, theta);
result = struct();
result.method = 'synthetic_ipp_current_ratio';
result.protocol_id = uint16(2);
result.accepted = true;
result.reason = 'synthetic shifted-axis stage accepted';
result.theta_offset_seed_rad = thetaSeed;
result.theta_offset_seed_deg = thetaSeed * 180/pi;
result.current_source = 'iq_cmd_A';
result.current_source_definition = 'synthetic dry-run controller current request';
result.velocity_limit_source = 'v_est_mps';
result.pairing_mode = 'local_sample_index';
result.coarse = stage;
result.fine = localEmptyStage('fine_symmetric_delta');
result.quality = localProtocol2Quality(true, result.reason, stage);
result.epsilon_coarse_rad = axisShift;
result.epsilon_coarse_deg = axisShift * 180/pi;
result.theta_offset_coarse_rad = theta;
result.theta_offset_coarse_deg = theta * 180/pi;
result.axis_shift_deg = axisShift * 180/pi;
result.axis_shift_error_deg = 0.0;
result.current_ratio_q_over_d = 1.0;
result.current_equality_mismatch_fraction = 0.0;
result.theta_offset_hat_rad = theta;
result.theta_offset_hat_deg = theta * 180/pi;
result.next_theta_offset_seed_rad = theta;
result = localAddEstimationReference(result, plan, theta);
end

function result = localSyntheticProtocol3(rawLog, plan)
theta = copley.analysis.wrapTo2Pi(localField(plan, ...
    'initial_theta_offset_guess_rad', localReferenceTheta(plan, 1.25)));
qSign = int16(localField(plan, 'q_axis_sign', 1));
result = struct();
result.method = 'synthetic_q_axis_verification';
result.protocol_id = uint16(3);
result.accepted = true;
result.reason = 'synthetic q-axis response accepted';
result.theta_offset_verified_rad = theta;
result.theta_offset_verified_deg = theta * 180/pi;
result.theta_offset_hat_rad = theta;
result.theta_offset_hat_deg = theta * 180/pi;
result.q_axis_sign = qSign;
result.recommended_q_axis_sign = qSign;
result.positive_response_m = 5.0e-6;
result.negative_response_m = -5.0e-6;
result.positive_position_delta_m = result.positive_response_m;
result.negative_position_delta_m = result.negative_response_m;
result.positive_velocity_mps = 1.0e-4;
result.negative_velocity_mps = -1.0e-4;
result.positive_response_source = 'synthetic';
result.negative_response_source = 'synthetic';
result.min_response_m = localAnalysisField(plan, 'protocol3_min_response_m', 1.0e-8);
result.quality = localQuality(true, result.reason);
result.quality.positive_ok = true;
result.quality.negative_ok = true;
result.quality.reversed = false;
result = localAddEstimationReference(result, plan, theta);
end

function result = localAddEstimationReference(result, plan, thetaOffset_rad)
estimate = copley.analysis.buildEstimationReference( ...
    table(), plan, thetaOffset_rad);
result.estimation_absolute_position_raw = ...
    estimate.estimation_absolute_position_raw;
result.estimation_position_m = estimate.estimation_position_m;
result.theta_at_estimation_rad = estimate.theta_at_estimation_rad;
result.theta_at_estimation_deg = estimate.theta_at_estimation_deg;
end

function theta = localReferenceTheta(plan, defaultValue)
theta = localAnalysisField(plan, 'protocol1_theta_reference_rad', defaultValue);
theta = copley.analysis.wrapTo2Pi(theta);
end

function stage = localSyntheticStage(counts, amps, axisShift, theta)
stage = struct();
stage.name = 'shifted_axis_q_d';
stage.has_data = true;
stage.accepted = true;
stage.reason = 'synthetic shifted-axis stage accepted';
stage.pairing_mode = 'local_sample_index';
stage.current_source = 'iq_cmd_A';
stage.paired_sample_count = uint32(numel(counts));
stage.paired_sample_count_before_guards = uint32(numel(counts));
stage.saturation_fraction = 0.0;
stage.ramp_limited_fraction = 0.0;
stage.near_zero_denominator_fraction = 0.0;
stage.low_current_pair_fraction = 0.0;
stage.stationary_sample_fraction = 0.0;
stage.target_actual_delta_deg = 0.0;
stage.beta_rad = [0, -pi/2];
stage.I0 = median(counts);
stage.I90 = median(counts);
stage.epsilon_samples_rad = repmat(axisShift, 1, numel(counts));
stage.epsilon_hat_rad = axisShift;
stage.epsilon_hat_deg = axisShift * 180/pi;
stage.theta_offset_hat_rad = theta;
stage.theta_offset_hat_deg = theta * 180/pi;
stage.theta_offset_coarse_rad = theta;
stage.theta_offset_coarse_deg = theta * 180/pi;
stage.axis_shift_rad = axisShift;
stage.axis_shift_deg = axisShift * 180/pi;
stage.axis_shift_error_rad = 0.0;
stage.axis_shift_error_deg = 0.0;
stage.current_ratio_q_over_d = 1.0;
stage.current_equality_mismatch_fraction = 0.0;
stage.regression_x_count = counts;
stage.regression_y_count = counts;
stage.regression_x_A = amps;
stage.regression_y_A = amps;
stage.local_sample_index = 1:numel(counts);
end

function stage = localEmptyStage(name)
stage = struct();
stage.name = name;
stage.has_data = false;
stage.accepted = false;
stage.reason = 'stage data not present';
stage.pairing_mode = 'none';
stage.current_source = '';
stage.paired_sample_count = uint32(0);
stage.paired_sample_count_before_guards = uint32(0);
stage.saturation_fraction = 1.0;
stage.ramp_limited_fraction = 1.0;
stage.near_zero_denominator_fraction = 1.0;
stage.low_current_pair_fraction = 1.0;
stage.stationary_sample_fraction = 1.0;
stage.target_actual_delta_deg = NaN;
stage.epsilon_samples_rad = [];
stage.regression_x_count = [];
stage.regression_y_count = [];
stage.regression_x_A = [];
stage.regression_y_A = [];
end

function quality = localProtocol2Quality(accepted, reason, stage)
quality = localQuality(accepted, reason);
quality.coarse_accepted = logical(accepted);
quality.fine_accepted = false;
quality.paired_sample_count = uint32(stage.paired_sample_count);
quality.saturation_fraction = stage.saturation_fraction;
quality.ramp_limited_fraction = stage.ramp_limited_fraction;
quality.near_zero_denominator_fraction = stage.near_zero_denominator_fraction;
quality.low_current_pair_fraction = stage.low_current_pair_fraction;
quality.stationary_sample_fraction = stage.stationary_sample_fraction;
quality.target_actual_delta_deg = stage.target_actual_delta_deg;
end

function quality = localQuality(accepted, reason)
quality = struct('accepted', logical(accepted), 'reason', reason);
end

function reason = localReason(rawLog)
reason = 'protocol rejected by logger/test double';
if isstruct(rawLog) && isfield(rawLog, 'reason')
    reason = char(rawLog.reason);
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
