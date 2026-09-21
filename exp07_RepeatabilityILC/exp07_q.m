function y = exp07_q(x, Qsos, Qscale, Ts)
%EXP07_Q exp04と同じ往復フィルタと25 msの端処理。
y = filtfilt_clean(Qsos, Qscale, x(:));
padding = round(0.025/Ts);
assert(numel(y) > 2*padding, 'Trajectory is too short for 25 ms padding.');
y(1:padding) = y(padding+1);
y(end-padding+1:end) = y(end-padding);
end
