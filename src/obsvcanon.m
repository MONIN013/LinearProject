function [ csys ] = obsvcanon(sys)
%OBSVCANON Compute observability canonical form

[n,d]=tfdata(tf(sys),'v');
W=hankel(fliplr(d(1:numel(d)-1)));
G=ss(sys);
U0=obsv(G);
S=W*U0;
csys=ss(S*G.a*inv(S),S*G.b,G.c*inv(S),G.d);

end