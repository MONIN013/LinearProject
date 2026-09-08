function [payload, reference] = toMotorRuntimeCalibrationPayload(value)
%TOMOTORRUNTIMECALIBRATIONPAYLOAD Build the fixed 8-byte reference ABI.
if ~isstruct(value) || ~isscalar(value)
    error('copley:MotorRuntimeReference:InvalidRecord', ...
        'MotorRuntime reference must be one struct.');
end

% Legacy MATLAB artifacts can still be explicitly registered. Conversion is
% only needed when the artifact predates the measured reference-pair fields.
if ~isfield(value, 'reference_position_count') ...
        || ~isfield(value, 'reference_commutation_angle')
    value = copley.domain.normalizeCalibrationRecord(value);
end

axisIndex = localInteger(localField(value, 'axis_index', 1), ...
    1, 4, 'axis_index', 'uint16');
positionCount = localInteger(value.reference_position_count, ...
    double(intmin('int32')), double(intmax('int32')), ...
    'reference_position_count', 'int32');
commutationAngle = localInteger(value.reference_commutation_angle, ...
    0, double(intmax('uint16')), ...
    'reference_commutation_angle', 'uint16');
electricalDirection = localInteger(localElectricalDirection(value), ...
    double(intmin('int16')), double(intmax('int16')), ...
    'electrical_direction', 'int16');

% Field order is the PLC structure order and therefore the wire order.
payload = struct();
payload.reference_position_count = int32(positionCount);
payload.reference_commutation_angle = uint16(commutationAngle);
payload.electrical_direction = int16(electricalDirection);

% Preserve analysis metadata for artifacts and fakes. Runtime selection uses
% only axis_index; metadata valid/accepted/version never enters the payload.
reference = value;
reference.axis_index = uint16(axisIndex);
reference.reference_position_count = int32(positionCount);
reference.reference_commutation_angle = uint16(commutationAngle);
reference.electrical_direction = int16(electricalDirection);
end

function value = localElectricalDirection(reference)
value = -1;
if isfield(reference, 'electrical_direction')
    value = reference.electrical_direction;
    return;
end
if isfield(reference, 'metadata') && isstruct(reference.metadata)
    if isfield(reference.metadata, 'electrical_direction')
        value = reference.metadata.electrical_direction;
        return;
    end
    if isfield(reference.metadata, 'electrical_angle_sign')
        value = reference.metadata.electrical_angle_sign;
        return;
    end
end
if isfield(reference, 'electrical_angle_sign')
    value = reference.electrical_angle_sign;
end
end

function value = localInteger(value, minValue, maxValue, name, typeName)
raw = double(value);
if ~isnumeric(value) || ~isreal(value) || ~isscalar(raw) ...
        || ~isfinite(raw) || raw ~= fix(raw) ...
        || raw < minValue || raw > maxValue
    error('copley:MotorRuntimeReference:InvalidInteger', ...
        '%s must be one %s value.', name, typeName);
end
value = cast(raw, typeName);
end

function value = localField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
end
