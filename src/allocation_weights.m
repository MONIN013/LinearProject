function weights = allocation_weights(beta, ratio)
%ALLOCATION_WEIGHTS Pair gains preserving nominal force for ratio = g1/g2.
validateattributes(beta,{'double'},{'scalar','finite','>=',-.2,'<=',.2});
validateattributes(ratio,{'double'},{'scalar','finite','>=',.5,'<=',2});
weights = [1+beta, 1-beta*ratio];
assert(all(weights>=.8 & weights<=1.2), 'NikonMotor:AllocationWeights', ...
    'Both axis gains must lie in [0.8,1.2]; reduce beta for this force ratio.');
end
