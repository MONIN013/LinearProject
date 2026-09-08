function calibration = makeCalibrationRecord(plan, results, timestamp_s)
%MAKECALIBRATIONRECORD Create the MotorRuntime RETAIN calibration payload.
theta = NaN;
qAxisSign = localField(plan, 'q_axis_sign', 1);
referencePosition = [];
referenceDAxisAngle_rad = NaN;
for i = 1:numel(results)
    result = results{i};
    if isstruct(result) && isfield(result, 'theta_offset_hat_rad')
        theta = double(result.theta_offset_hat_rad);
        referencePosition = [];
        referenceDAxisAngle_rad = NaN;
        if isfield(result, 'estimation_absolute_position_raw') ...
                && isfield(result, 'theta_at_estimation_rad')
            referencePosition = ...
                result.estimation_absolute_position_raw;
            referenceDAxisAngle_rad = double( ...
                result.theta_at_estimation_rad);
        end
    end
    if isstruct(result) && isfield(result, 'recommended_q_axis_sign')
        qAxisSign = int16(result.recommended_q_axis_sign);
    end
end
if ~isfinite(theta)
    error('copley:makeCalibrationRecord:MissingTheta', ...
        'Accepted protocol results did not contain theta_offset_hat_rad.');
end

if isempty(referencePosition) || ~isfinite(referenceDAxisAngle_rad)
    legacyEstimate = copley.analysis.buildEstimationReference( ...
        table(), plan, theta);
    referencePosition = legacyEstimate.estimation_absolute_position_raw;
    referenceDAxisAngle_rad = legacyEstimate.theta_at_estimation_rad;
end
reference = copley.domain.makeCalibrationReference( ...
    referencePosition, referenceDAxisAngle_rad, qAxisSign);
metadata = struct();
metadata.version = uint16(localField(plan, 'calibration_version', 2));
metadata.valid = true;
metadata.accepted = true;
metadata.accepted_timestamp_s = double(timestamp_s);
metadata.theta_offset_rad = theta;
metadata.reference_d_axis_angle_rad = reference.reference_d_axis_angle_rad;
metadata.reference_commutation_angle_rad = ...
    reference.reference_commutation_angle_rad;
metadata.q_axis_sign = int16(qAxisSign);
metadata.electrical_angle_sign = ...
    copley.domain.normalizeElectricalAngleSign(localField(plan, ...
    'electrical_angle_sign', 1));

calibration = struct();
calibration.axis_index = uint16(localField(plan, 'axis_index', 1));
calibration.reference_position_count = ...
    reference.reference_position_count;
calibration.reference_commutation_angle = ...
    reference.reference_commutation_angle;
calibration.metadata = metadata;
end

function value = localField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
end
