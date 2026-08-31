function fb = fbFilt(fb, Ts, f)
%FBFILT Assemble the discrete feedback controller and its FRD model.

kp = fb.pi(1);
ki = fb.pi(2)*2*pi;
fb.PI = c2d(tf(kp*[1, ki], [1, 0]), Ts, "tustin");
fb.C = tf(kp*[1, ki], [1, 0]);

if fb.zp(3) == 1
    z = fb.zp(1)*2*pi;
    p = fb.zp(2)*2*pi;
    fb.lead = c2d(tf([1/z, 1], [1/p, 1]), Ts, "tustin");
    fb.C = fb.C*tf([1/z, 1], [1/p, 1]);
else
    fb.lead = tf(1, 1, Ts);
end

if fb.lp(3) > 0
    Fc = fb.lp(1);
    [Qnum, Qden] = butter(3, Fc/(1/(2*Ts)));
    fb.lpf = tf(Qnum, Qden, Ts);
    [bn, an] = butter(3, Fc*2*pi, "s");
    fb.C = fb.C*tf(bn, an);
else
    fb.lpf = tf(1, 1, Ts);
end

fb.frdSh = tf(1, 1, Ts);
fb.sf = tf(1, 1, Ts);
if isfield(fb, "shap")
    fb.sh = cell(1, numel(fb.shap));
    for i = 1:numel(fb.shap)
        if fb.shap{i}(5) > 0
            w1 = fb.shap{i}(1)*2*pi;
            w2 = fb.shap{i}(2)*2*pi;
            d1 = fb.shap{i}(3);
            d2 = fb.shap{i}(4);
            fb.sh{i} = c2d(tf([1/w1^2, 2*d1/w1, 1], ...
                [1/w2^2, 2*d2/w2, 1]), Ts, "matched");
            fb.C = fb.C*tf([1/w1^2, 2*d1/w1, 1], ...
                [1/w2^2, 2*d2/w2, 1]);
        else
            fb.sh{i} = tf(1, 1, Ts);
        end
        fb.frdSh = fb.frdSh*frd(fb.sh{i}, f, "FrequencyUnit", "Hz");
        fb.sf = fb.sf*fb.sh{i};
    end
end

fb.frd = fb.frdSh*frd(fb.PI, f, "FrequencyUnit", "Hz") ...
    *frd(fb.lead, f, "FrequencyUnit", "Hz") ...
    *frd(fb.lpf, f, "FrequencyUnit", "Hz");
fb.K = fb.PI*fb.lead*fb.lpf*fb.sf;
end
