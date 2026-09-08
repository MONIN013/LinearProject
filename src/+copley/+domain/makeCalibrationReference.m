function reference = makeCalibrationReference(referencePositionCount, ...
        dAxisAngle_rad, qAxisSign)
%MAKECALIBRATIONREFERENCE Pair one measured position with its commutation angle.
dAxisAngle_rad = double(dAxisAngle_rad);
if ~isscalar(dAxisAngle_rad) || ~isfinite(dAxisAngle_rad)
    error('copley:makeCalibrationReference:InvalidTheta', ...
        'dAxisAngle_rad must be one finite scalar.');
end
qAxisSign = double(qAxisSign);
if ~isscalar(qAxisSign) || ~isfinite(qAxisSign) ...
        || (qAxisSign ~= -1.0 && qAxisSign ~= 1.0)
    error('copley:makeCalibrationReference:InvalidQAxisSign', ...
        'qAxisSign must be -1 or 1.');
end

positionCount = localInt32(referencePositionCount, ...
    'referencePositionCount');
dAxisAngle_rad = copley.analysis.wrapTo2Pi(dAxisAngle_rad);
commutationAngle_rad = copley.analysis.wrapTo2Pi( ...
    dAxisAngle_rad + qAxisSign * pi/2);

reference = struct();
reference.reference_position_count = positionCount;
reference.reference_commutation_angle = ...
    copley.domain.radToCopleyUint(commutationAngle_rad);
reference.reference_d_axis_angle_rad = dAxisAngle_rad;
reference.reference_commutation_angle_rad = commutationAngle_rad;
reference.q_axis_sign = int16(qAxisSign);
end

function value = localInt32(value, name)
raw = double(value);
if ~isscalar(raw) || ~isfinite(raw) || raw ~= fix(raw) ...
        || raw < double(intmin('int32')) || raw > double(intmax('int32'))
    error('copley:makeCalibrationReference:InvalidPosition', ...
        '%s must be one int32 value.', name);
end
value = int32(raw);
end
