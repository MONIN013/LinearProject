function [Pn, Gn] = modelCreate(P, Ts, fout)
%MODELCREATE Build continuous, discrete, and frequency-response plant models.

s = tf("s");
z = tf("z", Ts);

Gn.Ts = Ts;
Gn.Mn = P.m;
Gn.Dn = P.d;
Gn.Kn = P.k;

Pn.base = tf(1, [P.m, P.d, P.k]);
Gn.base = c2d(Pn.base, Ts, "zoh");

switch P.lp(3)
    case 2
        wlp = P.lp(1)*2*pi;
        dlp = P.lp(2);
        Pn.lpf = tf(1, [1/wlp^2, 2*dlp/wlp, 1]);
        Gn.lpf = c2d(Pn.lpf, Ts, "zoh");
    case 1
        wlp = P.lp(1)*2*pi;
        Pn.lpf = tf(1, [1/wlp, 1]);
        Gn.lpf = c2d(Pn.lpf, Ts, "zoh");
    otherwise
        Pn.lpf = tf(1);
        Gn.lpf = tf(1, 1, Ts);
end

Gn.frdReso = tf(1, 1, Ts);
Pn.resoAll = tf(1);
Gn.resoAll = tf(1, 1, Ts);
if isfield(P, "reso")
    for i = 1:numel(P.reso)
        if P.reso{i}(5) > 0
            w1 = P.reso{i}(1)*2*pi;
            w2 = P.reso{i}(2)*2*pi;
            d1 = P.reso{i}(3);
            d2 = P.reso{i}(4);
            Pn.reso(i) = tf([1/w1^2, 2*d1/w1, 1]*w1, ...
                [1/w2^2, 2*d2/w2, 1]*w1);
            Gn.reso(i) = c2d(Pn.reso(i), Ts, "zoh");
        else
            Pn.reso(i) = tf(1);
            Gn.reso(i) = tf(1, 1, Ts);
        end
        Gn.frdReso = Gn.frdReso*frd(Gn.reso(i), fout, "FrequencyUnit", "Hz");
        Pn.resoAll = Pn.resoAll*Pn.reso(i);
        Gn.resoAll = Gn.resoAll*Gn.reso(i);
    end
end

Gn.frd = Gn.frdReso*frd(Gn.base, fout, "FrequencyUnit", "Hz") ...
    *frd(Gn.lpf, fout, "FrequencyUnit", "Hz");
Gn.frdDelayed = Gn.frd*frd(z^-P.delay, fout, "FrequencyUnit", "Hz");

Pn.model = Pn.base*Pn.lpf*Pn.resoAll;
Gn.model = Gn.base*Gn.lpf*Gn.resoAll;
Pn.delay = P.delay;
Gn.delay = P.delay;
Pn.modelDelayed = Pn.model*exp(-Ts*P.delay*s);
Gn.modelDelayed = Gn.model*z^-P.delay;
end
