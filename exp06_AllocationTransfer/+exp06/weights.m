function w = weights(beta, ratio)
%WEIGHTS Nominal force-preserving pair weights; ratio is g1/g2, not measured here.
validateattributes(beta,{'double'},{'scalar','finite','>=',-.2,'<=',.2});
validateattributes(ratio,{'double'},{'scalar','finite','>=',.5,'<=',2});
w=[1+beta,1-beta*ratio];
end
