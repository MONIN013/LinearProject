function output = lsimFB(fb, signal, time)
%LSIMFB Apply the feedback-controller stages without forming one high-order TF.
signal = signal(:);
time = time(:);
output = lsim(fb.PI, signal, time);

if fb.zp(3) == 1
    output = lsim(fb.lead, output, time);
end
if fb.lp(3) > 0
    output = lsim(fb.lpf, output, time);
end
if isfield(fb, "shap")
    for k = 1:numel(fb.shap)
        if fb.shap{k}(5) > 0
            output = lsim(fb.sh{k}, output, time);
        end
    end
end
end
