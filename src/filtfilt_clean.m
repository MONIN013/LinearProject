function y = filtfilt_clean(B,A,x,Npad)
%filtfilt_clean - filtfilt with constant padding for transient removal
%
% y = filtfilt_clean(B,A,x,Npad)
% B,A     : numerator/denominator coefficients, or SOS matrix/scale value
% x       : signal to be filtered
% Npad    : additional padding before and after signal for transient removal (optional)
%
% Author  : Kentaro Tsurumoto, The University of Tokyo, 2023
narginchk(3,4);
if nargin < 4; Npad = 100; end
xPad = [repmat(x(1,:),Npad,1); x; repmat(x(end,:),Npad,1)];
yPad = filtfilt(B,A,xPad);
y = yPad(1+Npad:end-Npad,:);
end
