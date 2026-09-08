function y = wrapTo2Pi(theta)
%WRAPTO2PI Wrap radians to [0, 2*pi).
y = mod(theta, 2*pi);
y(y < 0) = y(y < 0) + 2*pi;
end
