function [fb, pfig_nyq, pfig_Sens] = fbDesign(Pfrd, Ts)
%FBDESIGN Configure the feedback controller used by Demo 3.

fb.pi = [0.8e3, 1];
fb.zp = [20, 300, 1];
fb.lp = [200, 1, 0];
fb.shap = { ...
    [31, 31, 1.2, 2.0, 0], ...
    [60, 60, 1.5, 2.0, 0], ...
    [50, 50, 1.3, 2.2, 0], ...
    [31, 31, 0.9, 2.0, 0], ...
    [28, 28, 0.8, 2.0, 0]};

fb = fbFilt(fb, Ts, Pfrd.Frequency);
pfig_nyq = 0;
pfig_Sens = 0;
end
