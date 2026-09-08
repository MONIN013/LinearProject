function [fNext, diagnostic] = update_ilc_constrained(history, iteration, model, fb, Qsos, Qscale, maxInput, rate, learningWeight)
%UPDATE_ILC_CONSTRAINED Project the original Q-filtered update onto current limits.
% Keep Q on the accumulated FF as well as its correction. Filtering only the
% new error lets unmodelled high-frequency input persist across iterations.
% FF itself is not clipped: opposing feedback may put it above the current bound.
N = numel(history.t);
e = history.e(:,iteration); u = history.u(:,iteration);
[b,a] = tfdata(model.model,'v');
b = [zeros(1,numel(a)-numel(b)),b];
A = spdiags(repmat(a,N,1),-(0:numel(a)-1),N,N);
B = spdiags(repmat(b,N,1),-(model.delay+(0:numel(b)-1)),N,N);
% Micrometres keep the equality constraints and objective numerically scaled.
constraint = [A,-1e6*B];
if nargin<8, rate = max(.9^iteration,.3); end
validateattributes(rate,{'double'},{'scalar','finite','positive','<=',1});
if nargin<9, learningWeight = 1; end
validateattributes(learningWeight,{'double'},{'column','finite','>=',0,'<=',1});
assert(isscalar(learningWeight) || numel(learningWeight)==N, ...
    'NikonMotor:ILCLearningWeight','Learning weight must be scalar or match the waveform.');
feedbackCurrent = lsimFB(fb,e,history.t);
candidate = filtfilt_clean(Qsos,Qscale,history.f(:,iteration) + ...
    rate*learningWeight.*(feedbackCurrent+lsimInvModel(model,e)));
loggedCandidate = [0;candidate(1:end-1)];
effectiveFF = u-feedbackCurrent;
% State-space interconnection avoids a poorly conditioned high-order TF when
% the controller and the explicit sample delay are combined.
P = ss(model.model)*ss(tf(1,[1,zeros(1,model.delay)],model.model.Ts));
desiredPosition = lsim(feedback(P,ss(fb.K)),loggedCandidate-effectiveFF,history.t);
desiredCurrent = loggedCandidate-effectiveFF-lsimFB(fb,desiredPosition,history.t);
desired = 1e6*desiredPosition;
% Keep any necessary constraint correction smooth, without changing a
% feasible candidate from the existing 420 Hz learning law.
D2 = diff(speye(N),2,1);
currentCurvature = D2'*D2;
currentWeight = .01*speye(N)+currentCurvature;
H = blkdiag(speye(N),currentWeight);
linear = [-desired;-currentWeight*desiredCurrent];
% Reserve the measured prediction uncertainty in total current, not in FF.
margin = .15;
if isfield(history,'teacher') && isfield(history.teacher.settings,'currentMargin')
    margin = history.teacher.settings.currentMargin;
end
validateattributes(margin,{'double'},{'scalar','finite','positive','<',maxInput});
limit = maxInput-margin;
lower = [-inf(N,1);-limit-u];
upper = [inf(N,1);limit-u];
% The capture's first FF sample is fixed at zero by Reference/Delay1.
lower(N+1) = 0; upper(N+1) = 0;
feasible = max(abs(u+desiredCurrent))<=limit;
if feasible
    z = [desired;desiredCurrent]; flag = 1; output.iterations = 0;
else
    options = optimoptions('quadprog','Algorithm','interior-point-convex', ...
        'Display','off','MaxIterations',100,'ConstraintTolerance',1e-8, ...
        'OptimalityTolerance',1e-7);
    [z,~,flag,output] = quadprog(H,linear,[],[],constraint,zeros(N,1), ...
        lower,upper,[],options);
end
assert(flag>0,'NikonMotor:ILCOptimizationFailed','Constrained ILC optimization did not solve.');
predictedError = e-z(1:N)*1e-6;
predictedCurrent = u+z(N+1:end);
loggedFF = predictedCurrent-lsimFB(fb,predictedError,history.t);
% Row 7 records [0; f(1:end-1)]; undo this delay once for the next submission.
fNext = [loggedFF(2:end);loggedFF(end)];
if feasible, fNext = candidate; end
diagnostic = struct('flag',flag,'iterations',output.iterations, ...
    'constraintResidual',max(abs(constraint*z)), ...
    'predictedCurrent',predictedCurrent,'predictedError',predictedError, ...
    'peakFF',max(abs(fNext)),'rate',rate,'currentBound',limit, ...
    'learningWeight',learningWeight);
assert(all(isfinite(fNext)) && diagnostic.peakFF<2*maxInput && ...
    max(abs(predictedCurrent))<=limit+1e-6, ...
    'NikonMotor:InvalidILCOptimization','Constrained ILC returned an invalid candidate.');
end
