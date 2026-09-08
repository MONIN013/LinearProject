function map = fit_acceleration_ff(training, xGrid, derivativeWindow, currentOffsetSamples)
%FIT_ACCELERATION_FF Fit i = g(x)+b(x)*v+c(x)*sign(v)+alpha(x)*a [A].
% training contains accepted exp05 ILC teachers, never FB-only total commands.
% Mechanical sample k is paired with logged FF(k+currentOffsetSamples).
% xGrid is absolute position [m]. Repeats share profileIndex and are averaged.
% The logged reference identifies passes; all fitted kinematics stay measured.
validateattributes(xGrid, {'double'}, {'column','finite','increasing','nonempty'});
validateattributes(derivativeWindow, {'double'}, {'scalar','integer','odd','>=',5});
validateattributes(currentOffsetSamples, {'double'}, {'scalar','integer','finite'});
assert(~isempty(training), 'NikonMotor:NoTrainingData', 'Collect converged ILC teachers first.');
h = (derivativeWindow-1)/2;
s = (-h:h)'/h;
W = pinv([ones(size(s)), s, s.^2, s.^3]);
samples = nan(numel(xGrid), 2*numel(training), 3);
profileIndex = zeros(1, 2*numel(training));
for trial = 1:numel(training)
    data = training{trial};
    assert(data.passed && data.method == "ilc_teacher" && ...
        isfield(data,'teacher') && data.teacher.converged && ...
        data.teacher.currentKind == "ilc_ff_A", ...
        'NikonMotor:InvalidTrainingRun', 'Use successful, converged ILC teachers.');
    x = data.y_absolute_ex(:); u = data.ff_ex(:); Ts = data.Ts;
    validateattributes(Ts, {'double'}, {'scalar','finite','positive'});
    assert(numel(x)>2*h+4 && numel(u)==numel(x) && ...
        numel(data.count_ex)==numel(x) && all(diff(data.count_ex)==1) && ...
        all(isfinite([x;u])), 'NikonMotor:InvalidTrainingData', ...
        'Training data must be finite and have continuous samples.');
    reference = data.r_ex(:);
    assert(numel(reference)==numel(x) && all(isfinite(reference)), ...
        'NikonMotor:InvalidTrainingData','Provide the reference logged with the measured position.');
    % Offline local cubic differentiation of measured position; no reference
    % acceleration is substituted when the stage does not track the command.
    xf = conv(x, flipud(W(1,:)'), 'valid');
    vf = conv(x, flipud(W(2,:)'), 'valid')/(h*Ts);
    af = 2*conv(x, flipud(W(3,:)'), 'valid')/(h*Ts)^2;
    referenceVelocity = conv(reference,flipud(W(2,:)'),'valid')/(h*Ts);
    k = (h+1:numel(x)-h)' + currentOffsetSamples;
    keep = k>=1 & k<=numel(u);
    xf = xf(keep); vf = vf(keep); af = af(keep); u = u(k(keep));
    referenceVelocity = referenceVelocity(keep);
    for direction = [-1,1]
        column = 2*trial-(direction<0);
        profileIndex(column) = data.profileIndex;
        % Dwell motion belongs to neither pass. It must not be concatenated
        % with a commanded pass just because its measured speed exceeds 2 mm/s.
        ix = find(direction*vf>0.002 & direction*referenceVelocity>0.002);
        if direction<0, ix = flipud(ix); end
        if numel(ix)<2, continue; end
        assert(all(diff(xf(ix))>0), 'NikonMotor:NonmonotoneTraining', ...
            'Measured motion reverses within a pass; inspect this training run.');
        values = interp1(xf(ix), [vf(ix),af(ix),u(ix)], xGrid, 'linear', NaN);
        samples(:,column,:) = reshape(values, numel(xGrid), 1, 3);
    end
end

% Repeating one shape improves averaging, not the number of independent shapes.
profiles = unique(profileIndex);
averaged = nan(numel(xGrid), 2*numel(profiles), 3);
for p = 1:numel(profiles)
    for direction = 1:2
        columns = profileIndex==profiles(p) & mod(1:numel(profileIndex),2)==mod(direction,2);
        averaged(:,2*p-2+direction,:) = mean(samples(:,columns,:),2,'omitnan');
    end
end
coefficients = nan(numel(xGrid),4);
currentRange = nan(numel(xGrid),4); % [reverse min/max, forward min/max] [A]
conditionNumber = inf(size(xGrid)); residualRms = nan(size(xGrid));
for k = 1:numel(xGrid)
    z = reshape(averaged(k,:,:), [], 3);
    z = z(all(isfinite(z),2),:);
    X = [ones(size(z,1),1), z(:,1), sign(z(:,1)), z(:,2)];
    if size(X,1)<6, continue; end
    scale = sqrt(mean(X.^2,1)); scale(scale==0) = 1;
    Z = X./scale;
    conditionNumber(k) = cond(Z);
    if rank(Z)<4 || conditionNumber(k)>1e3, continue; end
    coefficients(k,:) = (Z\z(:,3))'./scale;
    residualRms(k) = sqrt(mean((X*coefficients(k,:)'-z(:,3)).^2));
    for direction = [-1,1]
        observed = z(sign(z(:,1))==direction,3);
        columns = (1:2)+2*(direction>0);
        currentRange(k,columns) = [min(observed),max(observed)];
    end
end
map = struct('x',xGrid, 'coefficients',coefficients, ...
    'currentRange',currentRange, ...
    'coefficientNames',["g","b","c","alpha"], ...
    'valid',all(isfinite(coefficients),2), ...
    'conditionNumber',conditionNumber, 'residualRms',residualRms, ...
    'currentKind',"ilc_ff_A", ...
    'derivativeWindow',derivativeWindow, 'currentOffsetSamples',currentOffsetSamples);
end
