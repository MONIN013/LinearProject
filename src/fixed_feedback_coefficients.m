function values = fixed_feedback_coefficients(Kd,Ts)
%FIXED_FEEDBACK_COEFFICIENTS Same two-state realization for SI, PID and FF.
% Padding both polynomials with trailing zeros preserves the transfer function.
controller = tf(Kd);
assert(isequal(size(controller),[1,1]) && ...
    (controller.Ts==0 || abs(controller.Ts-Ts)<1e-12), ...
    'NikonMotor:FeedbackPeriod','Use a scalar discrete controller at the experiment period.');
[b,a] = tfdata(controller,'v');
assert(numel(a)<=3 && numel(b)<=numel(a) && all(isfinite([a,b])) && a(1)~=0, ...
    'NikonMotor:FeedbackOrder','The common target supports proper controllers up to order two.');
assert(controller.Ts~=0 || numel(a)==1, ...
    'NikonMotor:FeedbackPeriod','Discretize a dynamic controller before capture.');
b = [zeros(1,numel(a)-numel(b)),b]/a(1);
a = a/a(1);
values = struct('p_fb_num',[b,zeros(1,3-numel(b))]', ...
    'p_fb_den',[a,zeros(1,3-numel(a))]');
end
