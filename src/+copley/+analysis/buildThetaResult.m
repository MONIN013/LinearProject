function theta = buildThetaResult(result)
%BUILDTHETARESULT Build the persisted magnetic pole identification summary.
theta = struct();
theta.schema_version = '3.0.0';
theta.method = 'ipp_current_ratio_identification_sequence';
theta.protocol_order = uint16([]);
theta.created_by = 'MATLAB analysis pipeline';

results = localField(result, 'protocol_results', {});
plan = localFirstPlan(result);
theta.scaling = localScaling(plan);
for i = 1:numel(results)
    r = results{i};
    if ~isstruct(r) || ~isfield(r, 'protocol_id')
        continue;
    end
    pid = double(r.protocol_id);
    theta.protocol_order(end+1) = uint16(pid);
    switch pid
        case 1
            theta.protocol1 = r;
            theta.differential = r;
        case 2
            theta.protocol2 = r;
        case 3
            theta.protocol3 = r;
            theta.q_axis = r;
    end
end

function plan = localFirstPlan(result)
plan = struct();
if isstruct(result) && isfield(result, 'protocol_plans') ...
        && iscell(result.protocol_plans) && ~isempty(result.protocol_plans)
    plan = result.protocol_plans{1};
end
end

function scaling = localScaling(plan)
scaling = struct();
scaling.sample_period_s = localField(plan, 'task_period_s', 1.25e-4);
scaling.position_m_per_pulse = localField(plan, 'position_m_per_count', 1.0e-7);
scaling.velocity_mps_per_count = localField(plan, 'velocity_mps_per_count', 1.0e-6);
scaling.target_torque_A_per_1000_count = localField(plan, 'target_torque_A_per_1000', 0.1);
scaling.target_torque_A_per_count = scaling.target_torque_A_per_1000_count / 1000.0;
scaling.actual_current_A_per_1000_count = localField(plan, 'actual_current_A_per_1000', 0.1);
scaling.actual_current_A_per_count = scaling.actual_current_A_per_1000_count / 1000.0;
end

if isfield(theta, 'protocol2') && isfield(theta.protocol2, 'theta_offset_hat_rad')
    theta.theta_offset_hat_rad = theta.protocol2.theta_offset_hat_rad;
    estimateSource = theta.protocol2;
elseif isfield(theta, 'protocol1') && isfield(theta.protocol1, 'theta_offset_hat_rad')
    theta.theta_offset_hat_rad = theta.protocol1.theta_offset_hat_rad;
    estimateSource = theta.protocol1;
else
    theta.theta_offset_hat_rad = NaN;
    estimateSource = struct();
end
theta.theta_offset_hat_deg = theta.theta_offset_hat_rad * 180/pi;
theta.estimation_absolute_position_raw = int32(localField(estimateSource, ...
    'estimation_absolute_position_raw', localField(plan, ...
    'position_raw_zero', 0)));
positionRawZero = double(localField(plan, 'position_raw_zero', 0));
positionZero_m = double(localField(plan, 'position_zero_m', 0.0));
positionScale_m_per_count = double(localField(plan, ...
    'position_m_per_count', 1.0e-7));
defaultEstimationPosition_m = positionZero_m ...
    + (double(theta.estimation_absolute_position_raw) - positionRawZero) ...
    * positionScale_m_per_count;
theta.estimation_position_m = double(localField(estimateSource, ...
    'estimation_position_m', defaultEstimationPosition_m));
tauE_m = double(localField(plan, 'tau_e_m', 0.036));
xRef_m = double(localField(plan, 'x_ref_m', 0.0));
electricalAngleSign = double(copley.domain.normalizeElectricalAngleSign( ...
    localField(plan, 'electrical_angle_sign', 1)));
theta.electrical_angle_sign = int16(electricalAngleSign);
if isfinite(theta.theta_offset_hat_rad) && isfinite(tauE_m) ...
        && tauE_m ~= 0.0
    defaultThetaAtEstimation_rad = copley.analysis.wrapTo2Pi( ...
        theta.theta_offset_hat_rad + electricalAngleSign * 2*pi ...
        * (theta.estimation_position_m - xRef_m) / tauE_m);
    theta.theta_at_estimation_rad = double(localField(estimateSource, ...
        'theta_at_estimation_rad', defaultThetaAtEstimation_rad));
else
    theta.theta_at_estimation_rad = NaN;
end
theta.theta_at_estimation_deg = theta.theta_at_estimation_rad * 180/pi;
if isfinite(theta.theta_at_estimation_rad) ...
        && isfinite(positionScale_m_per_count) ...
        && isfinite(tauE_m) && tauE_m ~= 0.0
    deltaToEncoderZero_m = -double( ...
        theta.estimation_absolute_position_raw) * positionScale_m_per_count;
    theta.theta_at_absolute_encoder_zero_rad = ...
        copley.analysis.wrapTo2Pi(theta.theta_at_estimation_rad ...
        + electricalAngleSign * 2*pi * deltaToEncoderZero_m / tauE_m);
else
    theta.theta_at_absolute_encoder_zero_rad = NaN;
end
theta.theta_at_absolute_encoder_zero_deg = ...
    theta.theta_at_absolute_encoder_zero_rad * 180/pi;

if isfield(theta, 'protocol2')
    p2 = theta.protocol2;
    theta.axis_shift_deg = localField(p2, 'axis_shift_deg', NaN);
    theta.axis_shift_error_deg = localField(p2, 'axis_shift_error_deg', NaN);
    theta.current_ratio_q_over_d = localField(p2, 'current_ratio_q_over_d', NaN);
    theta.current_equality_mismatch_fraction = ...
        localField(p2, 'current_equality_mismatch_fraction', NaN);
end
if isfield(theta, 'protocol3')
    p3 = theta.protocol3;
    theta.q_axis_sign = localField(p3, 'recommended_q_axis_sign', int16(1));
    theta.theta_offset_verified_rad = localField(p3, ...
        'theta_offset_verified_rad', theta.theta_offset_hat_rad);
    theta.theta_offset_verified_deg = theta.theta_offset_verified_rad * 180/pi;
else
    theta.q_axis_sign = int16(1);
    theta.theta_offset_verified_rad = theta.theta_offset_hat_rad;
    theta.theta_offset_verified_deg = theta.theta_offset_hat_deg;
end

[accepted, reason] = localOverallQuality(theta);
theta.quality = struct('accepted', logical(accepted), 'reason', reason);
theta.accepted = logical(accepted);
[calibration, calibrationMetadata] = localCalibrationSummary( ...
    result, plan, theta);
theta.reference_position_count = calibration.reference_position_count;
theta.reference_commutation_angle = ...
    calibration.reference_commutation_angle;
theta.reference_commutation_angle_rad = double(localField( ...
    calibrationMetadata, 'reference_commutation_angle_rad', ...
    double(theta.reference_commutation_angle) * 2*pi / 65536.0));
theta.reference_commutation_angle_deg = ...
    double(theta.reference_commutation_angle) * 360.0 / 65536.0;
theta.calibration_metadata = calibrationMetadata;
end

function [calibration, metadata] = localCalibrationSummary(result, plan, theta)
if isstruct(result) && isfield(result, 'calibration') ...
        && isstruct(result.calibration)
    calibration = copley.domain.normalizeCalibrationRecord( ...
        result.calibration);
    metadata = calibration.metadata;
    return;
end

metadata = struct();
metadata.version = uint16(localField(plan, 'calibration_version', 2));
metadata.valid = false;
metadata.accepted = false;
metadata.accepted_timestamp_s = 0.0;
referencePosition = theta.estimation_absolute_position_raw;
referenceDAxisAngle_rad = theta.theta_at_estimation_rad;
referenceThetaOffset_rad = theta.theta_offset_hat_rad;
if isfield(theta, 'protocol3') ...
        && isfield(theta.protocol3, 'estimation_absolute_position_raw') ...
        && isfield(theta.protocol3, 'theta_at_estimation_rad')
    referencePosition = theta.protocol3.estimation_absolute_position_raw;
    referenceDAxisAngle_rad = theta.protocol3.theta_at_estimation_rad;
    referenceThetaOffset_rad = localField(theta.protocol3, ...
        'theta_offset_verified_rad', localField(theta.protocol3, ...
        'theta_offset_hat_rad', referenceThetaOffset_rad));
end
metadata.theta_offset_rad = double(referenceThetaOffset_rad);
metadata.reference_d_axis_angle_rad = NaN;
metadata.reference_commutation_angle_rad = NaN;
metadata.q_axis_sign = int16(theta.q_axis_sign);
metadata.electrical_angle_sign = int16(theta.electrical_angle_sign);
calibration = struct( ...
    'axis_index', uint16(localField(plan, 'axis_index', 1)), ...
    'reference_position_count', int32(localField(plan, ...
    'position_raw_zero', 0)), ...
    'reference_commutation_angle', uint16(0), ...
    'metadata', metadata);

if ~isfinite(theta.theta_offset_hat_rad)
    return;
end
reference = copley.domain.makeCalibrationReference( ...
    referencePosition, referenceDAxisAngle_rad, theta.q_axis_sign);
calibration.reference_position_count = ...
    reference.reference_position_count;
calibration.reference_commutation_angle = ...
    reference.reference_commutation_angle;
metadata.valid = true;
metadata.accepted = logical(theta.accepted);
metadata.reference_d_axis_angle_rad = reference.reference_d_axis_angle_rad;
metadata.reference_commutation_angle_rad = ...
    reference.reference_commutation_angle_rad;
calibration.metadata = metadata;
end

function [accepted, reason] = localOverallQuality(theta)
accepted = true;
reason = 'Protocol 1, Protocol 2, and Protocol 3 accepted';
for pid = 1:3
    key = sprintf('protocol%d', pid);
    if ~isfield(theta, key)
        accepted = false;
        reason = sprintf('Protocol %d missing', pid);
        return;
    end
    r = theta.(key);
    if ~isfield(r, 'quality') || ~isstruct(r.quality) ...
            || ~isfield(r.quality, 'accepted') || ~logical(r.quality.accepted)
        accepted = false;
        if isfield(r, 'quality') && isfield(r.quality, 'reason')
            reason = sprintf('Protocol %d rejected: %s', pid, r.quality.reason);
        elseif isfield(r, 'reason')
            reason = sprintf('Protocol %d rejected: %s', pid, r.reason);
        else
            reason = sprintf('Protocol %d rejected', pid);
        end
        return;
    end
end
end

function value = localField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
end
