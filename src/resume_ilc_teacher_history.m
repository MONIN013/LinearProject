function [history, firstTrial] = resume_ilc_teacher_history(data, traj, Ntrial, settings, runtime)
%RESUME_ILC_TEACHER_HISTORY Continue a checked capture with its last applied FF.
% This performs no hardware access. Runtime/model checks precede reconnection.
assert(isfield(data,'method') && data.method=="ilc_teacher", ...
    'NikonMotor:TeacherResumeMismatch','Only an ILC teacher history can be resumed.');
for name = ["Ts","Fc","Qsos","Qscale","Kd","Ndelay","plantPath"]
    assert(isfield(data,name) && isequal(data.(name),runtime.(name)), ...
        'NikonMotor:TeacherResumeMismatch','Saved teacher %s differs from the current setup.',name);
end
completed = data.completedTrials;
validateattributes(completed,{'double'},{'scalar','integer','positive'});
validateattributes(Ntrial,{'double'},{'scalar','integer','>',completed});
history = data.history;
if isfield(data,'captures'), history.captures = data.captures; end
assert(isequal(history.reference,traj.pos) && isequal(history.t,traj.time), ...
    'NikonMotor:TeacherResumeMismatch','Resume requires the same reference and sample times.');
history.teacher = evaluate_ilc_teacher(history,completed,traj.vel,settings);
firstTrial = completed+1;
% Keep every recorded column. Future references are submitted before the
% model's logging delay, while the completed columns retain their logged form.
for name = ["count","r","f","ff","e","u","y","y_absolute"]
    value = zeros(numel(traj.pos),Ntrial);
    value(:,1:completed) = history.(name)(:,1:completed);
    history.(name) = value;
end
history.r(:,firstTrial:end) = repmat(traj.pos,1,Ntrial-completed);
history.f(:,firstTrial) = history.f(:,completed);
if isfield(settings,'averagingWindow') && completed>=2*settings.averagingWindow
    % Conditions may have changed during the interruption. Measure a fresh
    % block before using its error for correction or accepting the waveform.
    history.validationFF = history.f(:,completed);
    history.validationStart = firstTrial;
    if ~isfield(history,'validationStarts'), history.validationStarts = []; end
    history.validationStarts(end+1) = firstTrial;
    history.teacher.converged = false;
    history.teacher.accuracyPassed = false;
    history.teacher.validationTrials = 0;
    history.teacher.meanUpdateReady = false;
end
for name = ["eNorm","alpha"]
    value = nan(1,Ntrial);
    value(1:completed) = history.(name)(1:completed);
    history.(name) = value;
end
end
