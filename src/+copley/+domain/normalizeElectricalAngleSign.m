function value = normalizeElectricalAngleSign(value)
%NORMALIZEELECTRICALANGLESIGN Validate the encoder-to-electrical angle direction.
raw = double(value);
if ~isscalar(raw) || ~isfinite(raw) || (raw ~= -1.0 && raw ~= 1.0)
    error('copley:normalizeElectricalAngleSign:InvalidValue', ...
        'electrical_angle_sign must be -1 or 1.');
end
value = int16(raw);
end
