function estimate = buildEstimationReference(samples, plan, thetaOffset_rad)
%BUILDESTIMATIONREFERENCE Capture one measured count and its d-axis angle.
thetaOffset_rad = double(thetaOffset_rad);
if ~isscalar(thetaOffset_rad) || ~isfinite(thetaOffset_rad)
    error('copley:buildEstimationReference:InvalidTheta', ...
        'thetaOffset_rad must be one finite scalar.');
end
if nargin < 2 || ~isstruct(plan)
    plan = struct();
end

rawZero = localInt32(localField(plan, 'position_raw_zero', 0));
positionZero_m = double(localField(plan, 'position_zero_m', 0.0));
scale_m_per_count = double(localField(plan, ...
    'position_m_per_count', 1.0e-7));
referenceCount = rawZero;
referencePosition_m = positionZero_m;

if istable(samples) && height(samples) > 0 ...
        && ismember('x_abs_m', samples.Properties.VariableNames)
    positions_m = double(samples.x_abs_m(:));
    valid = isfinite(positions_m);
    if any(valid)
        center_m = median(positions_m(valid));
        candidates = find(valid);
        [~, localIndex] = min(abs(positions_m(valid) - center_m));
        sampleIndex = candidates(localIndex);
        referencePosition_m = positions_m(sampleIndex);
        if ismember('encoder_position_raw', ...
                samples.Properties.VariableNames)
            referenceCount = localInt32( ...
                samples.encoder_position_raw(sampleIndex));
        elseif ismember('panasonic_position_raw', ...
                samples.Properties.VariableNames)
            referenceCount = localInt32( ...
                samples.panasonic_position_raw(sampleIndex));
        else
            if ~isfinite(scale_m_per_count) || scale_m_per_count == 0.0
                error('copley:buildEstimationReference:InvalidScale', ...
                    'position_m_per_count must be finite and non-zero.');
            end
            referenceCount = localInt32(double(rawZero) + round( ...
                (referencePosition_m - positionZero_m) ...
                / scale_m_per_count));
        end
    end
end

tauE_m = double(localField(plan, 'tau_e_m', 0.036));
xRef_m = double(localField(plan, 'x_ref_m', 0.0));
if ~isfinite(tauE_m) || tauE_m == 0.0 ...
        || ~isfinite(referencePosition_m) || ~isfinite(xRef_m)
    error('copley:buildEstimationReference:InvalidGeometry', ...
        'The electrical pitch and reference positions must be finite.');
end
electricalAngleSign = double(copley.domain.normalizeElectricalAngleSign( ...
    localField(plan, 'electrical_angle_sign', 1)));
dAxisAngle_rad = copley.analysis.wrapTo2Pi(thetaOffset_rad ...
    + electricalAngleSign * 2*pi ...
    * (referencePosition_m - xRef_m) / tauE_m);

estimate = struct();
estimate.estimation_absolute_position_raw = int32(referenceCount);
estimate.estimation_position_m = referencePosition_m;
estimate.theta_at_estimation_rad = dAxisAngle_rad;
estimate.theta_at_estimation_deg = dAxisAngle_rad * 180/pi;
end

function value = localInt32(value)
raw = double(value);
if ~isscalar(raw) || ~isfinite(raw) || raw ~= fix(raw) ...
        || raw < double(intmin('int32')) || raw > double(intmax('int32'))
    error('copley:buildEstimationReference:InvalidPositionCount', ...
        'The estimation position must fit one int32 count.');
end
value = int32(raw);
end

function value = localField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
end
