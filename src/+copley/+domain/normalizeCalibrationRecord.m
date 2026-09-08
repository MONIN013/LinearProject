function calibration = normalizeCalibrationRecord(value)
%NORMALIZECALIBRATIONRECORD Normalize current and legacy MATLAB records.
if ~isstruct(value) || ~isscalar(value)
    error('copley:normalizeCalibrationRecord:InvalidRecord', ...
        'Calibration must be one struct.');
end

axisIndex = localInteger(localField(value, 'axis_index', 1), ...
    1, 4, 'axis_index', 'uint16');
metadataSource = localField(value, 'metadata', struct());
isReferenceRecord = isfield(value, 'reference_position_count') ...
    && isfield(value, 'reference_commutation_angle');
defaultSourceVersion = 1;
if isReferenceRecord
    defaultSourceVersion = 2;
end
inputVersion = localInteger(localMetadataField(metadataSource, value, ...
    'version', defaultSourceVersion), ...
    0, double(intmax('uint16')), 'version', 'uint16');
if isReferenceRecord
    version = inputVersion;
else
    version = uint16(2);
end
sourceVersion = localInteger(localMetadataField(metadataSource, value, ...
    'source_version', inputVersion), ...
    0, double(intmax('uint16')), 'source_version', 'uint16');
valid = localLogical(localMetadataField(metadataSource, value, ...
    'valid', false), 'valid');
accepted = localLogical(localMetadataField(metadataSource, value, ...
    'accepted', false), 'accepted');
timestamp_s = localFiniteScalar(localMetadataField(metadataSource, value, ...
    'accepted_timestamp_s', 0.0), 'accepted_timestamp_s');
electricalAngleSign = copley.domain.normalizeElectricalAngleSign( ...
    localMetadataField(metadataSource, value, ...
    'electrical_angle_sign', -1));

if isReferenceRecord
    referencePosition = localInteger(value.reference_position_count, ...
        double(intmin('int32')), double(intmax('int32')), ...
        'reference_position_count', 'int32');
    referenceAngle = localInteger(value.reference_commutation_angle, ...
        0, double(intmax('uint16')), ...
        'reference_commutation_angle', 'uint16');
    qAxisSign = localQAxisSign(localMetadataField(metadataSource, value, ...
        'q_axis_sign', 1));
    thetaOffset_rad = double(localMetadataField(metadataSource, value, ...
        'theta_offset_rad', NaN));
    dAxisAngle_rad = double(localMetadataField(metadataSource, value, ...
        'reference_d_axis_angle_rad', NaN));
    commutationAngle_rad = double(localMetadataField(metadataSource, value, ...
        'reference_commutation_angle_rad', ...
        double(referenceAngle) * 2*pi / 65536.0));
else
    required = {'theta_offset_rad', 'position_raw_zero'};
    if ~all(isfield(value, required))
        error('copley:normalizeCalibrationRecord:MissingReference', ...
            ['Calibration must contain the two reference fields or the ' ...
             'legacy theta_offset_rad and position_raw_zero fields.']);
    end
    qAxisSign = localQAxisSign(localField(value, 'q_axis_sign', 1));
    thetaOffset_rad = localFiniteScalar(value.theta_offset_rad, ...
        'theta_offset_rad');
    tauE_m = localFiniteScalar(localField(value, 'tau_e_m', 0.036), ...
        'tau_e_m');
    if tauE_m == 0.0
        error('copley:normalizeCalibrationRecord:InvalidScalar', ...
            'tau_e_m must be non-zero.');
    end
    positionZero_m = localFiniteScalar(localField(value, ...
        'position_zero_m', 0.0), 'position_zero_m');
    xRef_m = localFiniteScalar(localField(value, 'x_ref_m', 0.0), ...
        'x_ref_m');
    referencePosition = localInteger(value.position_raw_zero, ...
        double(intmin('int32')), double(intmax('int32')), ...
        'position_raw_zero', 'int32');
    dAxisAngle_rad = copley.analysis.wrapTo2Pi(thetaOffset_rad ...
        + double(electricalAngleSign) * 2*pi ...
        * (positionZero_m - xRef_m) / tauE_m);
    reference = copley.domain.makeCalibrationReference( ...
        referencePosition, dAxisAngle_rad, qAxisSign);
    referencePosition = reference.reference_position_count;
    referenceAngle = reference.reference_commutation_angle;
    dAxisAngle_rad = reference.reference_d_axis_angle_rad;
    commutationAngle_rad = reference.reference_commutation_angle_rad;
end

metadata = struct();
metadata.version = uint16(version);
metadata.source_version = uint16(sourceVersion);
metadata.valid = logical(valid);
metadata.accepted = logical(accepted);
metadata.accepted_timestamp_s = double(timestamp_s);
metadata.theta_offset_rad = double(thetaOffset_rad);
metadata.reference_d_axis_angle_rad = double(dAxisAngle_rad);
metadata.reference_commutation_angle_rad = double(commutationAngle_rad);
metadata.q_axis_sign = int16(qAxisSign);
metadata.electrical_angle_sign = int16(electricalAngleSign);

calibration = struct();
calibration.axis_index = uint16(axisIndex);
calibration.reference_position_count = int32(referencePosition);
calibration.reference_commutation_angle = uint16(referenceAngle);
calibration.metadata = metadata;
end

function value = localMetadataField(metadata, record, name, defaultValue)
value = defaultValue;
if isstruct(metadata) && isfield(metadata, name)
    value = metadata.(name);
elseif isstruct(record) && isfield(record, name)
    value = record.(name);
end
end

function value = localQAxisSign(value)
raw = double(value);
if ~isscalar(raw) || ~isfinite(raw) || (raw ~= -1.0 && raw ~= 1.0)
    error('copley:normalizeCalibrationRecord:InvalidQAxisSign', ...
        'q_axis_sign must be -1 or 1.');
end
value = int16(raw);
end

function value = localInteger(value, minValue, maxValue, name, typeName)
raw = double(value);
if ~isscalar(raw) || ~isfinite(raw) || raw ~= fix(raw) ...
        || raw < minValue || raw > maxValue
    error('copley:normalizeCalibrationRecord:InvalidInteger', ...
        '%s must be one %s value.', name, typeName);
end
value = cast(raw, typeName);
end

function value = localLogical(value, name)
raw = double(value);
if ~(islogical(value) || isnumeric(value)) || ~isscalar(raw) ...
        || ~isfinite(raw) || (raw ~= 0.0 && raw ~= 1.0)
    error('copley:normalizeCalibrationRecord:InvalidLogical', ...
        '%s must be one logical value.', name);
end
value = logical(raw);
end

function value = localFiniteScalar(value, name)
value = double(value);
if ~isscalar(value) || ~isfinite(value)
    error('copley:normalizeCalibrationRecord:InvalidScalar', ...
        '%s must be one finite scalar.', name);
end
end

function value = localField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
end
