function map = interpolate_allocation_map(maps, betas, beta)
%INTERPOLATE_ALLOCATION_MAP Interpolate exp05 coefficients along allocation beta.
validateattributes(betas,{'double'},{'vector','finite','increasing','numel',numel(maps)});
validateattributes(beta,{'double'},{'scalar','finite','>=',betas(1),'<=',betas(end)});
left = find(betas<=beta,1,'last');
right = find(betas>=beta,1,'first');
map = maps{left}; other = maps{right};
assert(isequal(map.x,other.x) && all(map.valid) && all(other.valid), ...
    'NikonMotor:InvalidAllocationMap','Allocation maps must share an identified position grid.');
if left~=right
    w = (beta-betas(left))/(betas(right)-betas(left));
    map.coefficients = (1-w)*map.coefficients+w*other.coefficients;
    map.currentRange = (1-w)*map.currentRange+w*other.currentRange;
end
% Residuals and condition numbers belong to the fitted maps, not this estimate.
map = rmfield(map,intersect(fieldnames(map),{'conditionNumber','residualRms'}));
map.beta = beta;
end
