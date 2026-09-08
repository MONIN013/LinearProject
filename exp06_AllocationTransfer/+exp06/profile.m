function p = profile(Ts, distance, legTime, skew)
%PROFILE Quintic round trip with a C2 shape perturbation, no symbolic toolbox.
validateattributes(Ts,{'double'},{'scalar','finite','positive'});
validateattributes(distance,{'double'},{'scalar','finite','positive'});
validateattributes(legTime,{'double'},{'scalar','finite','positive'});
validateattributes(skew,{'double'},{'scalar','finite','>=',-2,'<=',2});
n=ceil(legTime/Ts); T=n*Ts; s=(0:n)'/n;
c=[-skew, 6+3*skew, -15-3*skew, 10+skew, 0, 0, 0];
x=distance*polyval(c,s); v=distance/T*polyval(polyder(c),s);
a=distance/T^2*polyval(polyder(polyder(c)),s);
j=distance/T^3*polyval(polyder(polyder(polyder(c))),s);
assert(all(diff(x)>=-1e-12),'exp06:Profile','Nonmonotone leg.');
npre=round(1.5/Ts); npause=round(1/Ts); npost=round(1.5/Ts);
p.r=[zeros(npre,1);x;repmat(distance,npause,1);distance-x(2:end);zeros(npost,1)];
p.v=[zeros(npre,1);v;zeros(npause,1);-v(2:end);zeros(npost,1)];
p.a=[zeros(npre,1);a;zeros(npause,1);-a(2:end);zeros(npost,1)];
p.j=[zeros(npre,1);j;zeros(npause,1);-j(2:end);zeros(npost,1)];
p.t=(0:numel(p.r)-1)'*Ts;
end
