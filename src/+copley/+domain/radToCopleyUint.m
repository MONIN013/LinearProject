function value = radToCopleyUint(theta_rad)
%RADTOCOPLEYUINT Convert radians to one unsigned 16-bit electrical revolution.
theta_rad = double(theta_rad);
if ~isscalar(theta_rad) || ~isfinite(theta_rad)
    error('copley:radToCopleyUint:InvalidAngle', ...
        'theta_rad must be one finite scalar.');
end

wrapped = mod(theta_rad, 2*pi);
counts = mod(round(wrapped / (2*pi) * 65536.0), 65536.0);
value = uint16(counts);
end
