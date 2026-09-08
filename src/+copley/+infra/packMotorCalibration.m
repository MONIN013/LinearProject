function bytes = packMotorCalibration(value)
%PACKMOTORCALIBRATION Encode the fixed 8-byte MotorRuntime reference ABI.
bytes = zeros(1, 8, 'uint8');
bytes(1:4) = typecast(int32(localField(value, ...
    'reference_position_count', 0)), 'uint8');
bytes(5:6) = typecast(uint16(localField(value, ...
    'reference_commutation_angle', 0)), 'uint8');
bytes(7:8) = typecast(int16(localField(value, ...
    'electrical_direction', 0)), 'uint8');
end

function value = localField(s, name, defaultValue)
value = defaultValue;
if isstruct(s) && isfield(s, name)
    value = s.(name);
end
end
