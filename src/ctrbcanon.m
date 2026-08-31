function [ csys ] = ctrbcanon(sys)
%CTRBCANON Compute controllability canonical form

[n,d]=tfdata(tf(sys),'v');
W=hankel(fliplr(d(1:numel(d)-1)));
G=ss(sys);
UC=ctrb(G);
S=UC*W;
csys=ss(inv(S)*G.a*S,inv(S)*G.b,G.c*S,G.d);

end