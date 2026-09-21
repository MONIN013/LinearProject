function teacher = evaluate_ilc_teacher(history, iteration, velocity, settings)
%EVALUATE_ILC_TEACHER Validate applied trials and decide whether FF has settled.
% history.f is the submitted waveform; history.ff is the applied/logged row 7.
% Only completed columns participate. Unapplied next-iteration FF is not a teacher.
validateattributes(iteration, {'double'}, {'scalar','integer','positive'});
validateattributes(settings.minTrials, {'double'}, {'scalar','integer','>=',2});
validateattributes(settings.window, {'double'}, {'scalar','integer','>=',2});
for name = ["errorRelativeChange","ffRelativeChange","feedbackRatio", ...
        "trackingLimit","terminalLimit","maxInput"]
    validateattributes(settings.(name), {'double'}, {'scalar','finite','positive'});
end
validateattributes(settings.endPosition, {'double'}, {'scalar','finite'});
N = numel(history.reference);
validateattributes(velocity, {'double'}, {'column','finite','numel',N});
for name = ["count","r","f","ff","e","u","y","y_absolute"]
    value = history.(name);
    assert(size(value,1)==N && size(value,2)>=iteration && ...
        all(isfinite(value(:,1:iteration)),'all'), ...
        'NikonMotor:InvalidTeacherCapture', 'Teacher history must contain finite completed trials.');
end
ix = 1:iteration;
count = history.count(:,ix);
assert(all(count==fix(count),'all') && all(diff(count,1,1)==1,'all'), ...
    'NikonMotor:LostSamples', 'Teacher capture has missing or out-of-order samples.');
rExpected = repmat([0;history.reference(1:end-1)],1,iteration);
ffExpected = [zeros(1,iteration);history.f(1:end-1,ix)];
assert(max(abs(history.r(:,ix)-rExpected),[],'all')<1e-7 && ...
    max(abs(history.ff(:,ix)-ffExpected),[],'all')<1e-7 && ...
    max(abs(history.e(:,ix)-(history.r(:,ix)-history.y(:,ix))),[],'all')<1e-7, ...
    'NikonMotor:CaptureMismatch', 'Teacher reference, applied FF or error differs from this sequence.');
% Initial trials may clip while learning. The target still limits total
% current; only an unsaturated final trial can become a teacher.
assert(max(abs(history.u(:,ix)),[],'all')<=settings.maxInput+1e-6, ...
    'NikonMotor:CurrentLimitExceeded', 'Recorded current exceeds the active target limit.');
saturatedSamples = sum(abs(history.u(:,ix))>=settings.maxInput-1e-6,1);
assert(max(abs(history.e(:,ix)),[],'all')<settings.trackingLimit && ...
    all(abs(history.y(end,ix))<settings.terminalLimit) && ...
    max(history.y_absolute(:,ix),[],'all')<settings.endPosition, ...
    'NikonMotor:TrackingFailed', 'Teacher tracking, return position or travel limit failed.');

moving = abs([0;velocity(1:end-1)])>0.002;
assert(any(moving), 'NikonMotor:TeacherNotMoving', 'Teacher trajectory has no moving samples.');
errorRms = sqrt(mean(history.e(moving,ix).^2,1));
ffRms = sqrt(mean(history.ff(moving,ix).^2,1));
residualRms = sqrt(mean((history.u(moving,ix)-history.ff(moving,ix)).^2,1));
feedbackRatio = residualRms./max(ffRms,eps);
ffChange = nan(1,iteration);
if iteration>1
    ffChange(2:end) = vecnorm(diff(history.f(:,ix),1,2),2,1) ./ ...
        max(vecnorm(history.f(:,1:iteration-1),2,1),eps);
end
teacher = struct('converged',false, 'iterations',iteration, ...
    'errorRms',errorRms, 'ffRelativeChange',ffChange, ...
    'saturatedSamples',saturatedSamples, ...
    'feedbackRatio',feedbackRatio, 'errorPlateau',Inf, 'ffPlateau',Inf, ...
    'currentKind',"ilc_ff_A", 'settings',settings, 'validationReady',false, ...
    'validationTrials',0, 'averagedFFPlateau',Inf, ...
    'accuracyPassed',~isfield(settings,'rmsLimit'), 'relearnRequired',false, ...
    'meanUpdateReady',false, ...
    'accuracyRms',NaN, 'accuracyMovingRms',NaN, 'accuracyPeak',NaN);
if iteration < max(settings.minTrials,settings.window+1), return; end
recent = errorRms(end-settings.window:end);
teacher.errorPlateau = max(abs(diff(recent)))/max(mean(recent),eps);
teacher.ffPlateau = max(ffChange(end-settings.window+1:end));
requireRmsPlateau = ~isfield(settings,'requireRmsPlateau') || settings.requireRmsPlateau;
assert(requireRmsPlateau || (isfield(settings,'averagingWindow') && isfield(settings,'rmsLimit')), ...
    'NikonMotor:TeacherAccuracyRequired','Absolute acceptance requires fixed-FF validation and accuracy limits.');
teacher.converged = (~requireRmsPlateau || teacher.errorPlateau<=settings.errorRelativeChange) && ...
    teacher.ffPlateau<=settings.ffRelativeChange && ...
    feedbackRatio(end)<=settings.feedbackRatio && saturatedSamples(end)==0;
if isfield(settings,'averagingWindow')
    validateattributes(settings.averagingWindow,{'double'},{'scalar','integer','>=',2});
    validateattributes(settings.validationTrials,{'double'}, ...
        {'scalar','integer','>=',settings.window+1});
    w = settings.averagingWindow;
    learningStart = 1;
    if isfield(history,'learningStart')
        learningStart = history.learningStart;
        validateattributes(learningStart,{'double'},{'scalar','integer','positive','<=',iteration});
    end
    % Assess the averaged waveform that will actually be validated, rather
    % than individual updates containing nonrepeatable high-frequency input.
    if iteration>=max(2*w,w+settings.window)
        averaged = zeros(N,settings.window+1);
        for j = 0:settings.window
            last = iteration-settings.window+j;
            averaged(:,j+1) = mean(history.f(:,last-w+1:last),2);
        end
        teacher.averagedFFPlateau = max(vecnorm(diff(averaged,1,2),2,1) ./ ...
            max(vecnorm(averaged(:,1:end-1),2,1),eps));
    end
    teacher.validationReady = iteration>=max(2*w,w+settings.window) && ...
        iteration-learningStart+1>=w && ...
        teacher.averagedFFPlateau<=settings.ffRelativeChange && ...
        all(saturatedSamples(max(1,iteration-w+1):iteration)==0) && ...
        feedbackRatio(end)<=settings.feedbackRatio;
    if isfield(history,'validationStart') && history.validationStart>0
        first = history.validationStart;
        assert(first>w && first<=iteration, 'NikonMotor:InvalidTeacherValidation', ...
            'Validation must follow recorded learning trials.');
        expected = history.validationFF;
        validateattributes(expected,{'double'},{'column','finite','numel',N});
        assert(max(abs(history.f(:,first:iteration)-expected),[],'all')<1e-12, ...
            'NikonMotor:ValidationFFChanged', 'The validation waveform must remain the recorded ILC candidate.');
        teacher.validationTrials = iteration-first+1;
        teacher.relearnRequired = any(saturatedSamples(first:iteration)>0);
        teacher.converged = teacher.converged && ...
            teacher.validationTrials>=settings.validationTrials && ...
            all(saturatedSamples(first:iteration)==0);
    else
        teacher.converged = false;
    end
end
if isfield(settings,'rmsLimit')
    for name = ["rmsLimit","movingRmsLimit","peakErrorLimit"]
        validateattributes(settings.(name),{'double'},{'scalar','finite','positive'});
    end
    teacher.accuracyPassed = false;
    if teacher.validationTrials>=settings.validationTrials
        last = iteration-settings.validationTrials+1:iteration;
        teacher.accuracyRms = sqrt(mean(history.e(:,last).^2,'all'));
        teacher.accuracyMovingRms = sqrt(mean(history.e(moving,last).^2,'all'));
        teacher.accuracyPeak = max(abs(history.e(:,last)),[],'all');
        % Check both the repeated measurements and the final applied trial.
        teacher.accuracyPassed = max(teacher.accuracyRms,rms(history.e(:,iteration)))<=settings.rmsLimit && ...
            max(teacher.accuracyMovingRms,errorRms(end))<=settings.movingRmsLimit && ...
            teacher.accuracyPeak<=settings.peakErrorLimit;
        if ~requireRmsPlateau
            % Short-stroke repetitions can vary below the requested accuracy.
            % Accept only when EVERY fixed-FF repeat meets that accuracy.
            teacher.accuracyPassed = teacher.accuracyPassed && ...
                all(sqrt(mean(history.e(:,last).^2,1))<=settings.rmsLimit) && ...
                all(errorRms(last)<=settings.movingRmsLimit) && ...
                all(feedbackRatio(last)<=settings.feedbackRatio);
        end
        % A single poor RMS still prevents acceptance. Relearn when the
        % measured block fails, rather than chase one noisy RMS observation.
        teacher.relearnRequired = teacher.relearnRequired || ...
            teacher.accuracyRms>settings.rmsLimit || ...
            teacher.accuracyMovingRms>settings.movingRmsLimit || ...
            teacher.accuracyPeak>settings.peakErrorLimit;
    end
    teacher.converged = teacher.converged && teacher.accuracyPassed;
end
if isfield(settings,'averagingWindow')
    % An inaccurate fixed block must remain learnable even when its RMS varies.
    % The RMS stability gate above still applies to final teacher acceptance.
    teacher.meanUpdateReady = teacher.relearnRequired && ...
        teacher.validationTrials>=settings.validationTrials && ...
        all(saturatedSamples(iteration-teacher.validationTrials+1:iteration)==0);
    if isfield(settings,'maxTrials')
        validateattributes(settings.maxTrials,{'double'},{'scalar','integer','>=',iteration});
        % Keep validating the existing FF if a new block cannot finish.
        roomForValidation = iteration+settings.validationTrials<=settings.maxTrials;
        teacher.validationReady = teacher.validationReady && roomForValidation;
        teacher.meanUpdateReady = teacher.meanUpdateReady && roomForValidation;
    end
end
end
