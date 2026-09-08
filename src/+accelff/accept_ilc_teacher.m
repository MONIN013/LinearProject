function teacher = accept_ilc_teacher(results, o)
%ACCEPT_ILC_TEACHER Accept the converged learned FF as identification teacher.
% `results` is a cell array of accepted accelff.execute_case results from ONE
% predeclared training profile. Each trial must use method="ilc_teacher".
% The regression target is the learned ILC FF (row 7), not total command row 3.
% Row 3-row 7 is retained as a residual-feedback diagnostic.

assert(iscell(results) && ~isempty(results),'accelff:ILCTeacherEmpty', ...
    'Provide one nonempty ILC sequence.');
for name={'teacher_min_iterations','teacher_plateau_window', ...
        'teacher_error_relative_change','teacher_ff_relative_change', ...
        'teacher_feedback_ratio'}
    validateattributes(o.(name{1}),{'double'},{'scalar','finite','positive'});
end
validateattributes(o.teacher_min_iterations,{'double'},{'integer'});
validateattributes(o.teacher_plateau_window,{'double'},{'integer','>=',2});
assert(numel(results)>=max(o.teacher_min_iterations,o.teacher_plateau_window+1), ...
    'accelff:ILCTeacherShort','ILC sequence is too short for the convergence gate.');

n=numel(results); eRms=nan(n,1); ffChange=nan(n,1); residualRatio=nan(n,1);
profile=""; split="";
for k=1:n
    r=results{k};
    assert(isstruct(r) && string(r.status)=="accepted" && isfield(r,'trace'), ...
        'accelff:ILCTeacherRejected','Every teacher trial must be an accepted capture.');
    tr=r.trace;
    assert(string(tr.method)=="ilc_teacher" && string(tr.split)=="train", ...
        'accelff:ILCTeacherRole','Teacher ILC may use only predeclared train profiles.');
    if k==1
        profile=string(tr.profile_id); split=string(tr.split);
    else
        assert(string(tr.profile_id)==profile && string(tr.split)==split, ...
            'accelff:ILCTeacherMixed','Do not mix profiles or splits in one ILC sequence.');
        assert(isequal(r.job.r,results{1}.job.r) && isequal(r.job.Ts,results{1}.job.Ts), ...
            'accelff:ILCTeacherReference','ILC iterations must repeat the same reference.');
    end
    moving=abs(tr.v_ref)>=o.velocity_floor;
    assert(any(moving),'accelff:ILCTeacherStopped','No moving samples in teacher trial.');
    eRms(k)=sqrt(mean(tr.error(moving).^2));
    residual=tr.current(moving)-tr.ff(moving);
    ffRms=sqrt(mean(tr.ff(moving).^2));
    residualRatio(k)=sqrt(mean(residual.^2))/max(ffRms,eps);
    if k>1
        previous=results{k-1}.job.f;
        current=r.job.f;
        ffChange(k)=norm(current-previous,2)/max(norm(previous,2),eps);
    end
end

w=o.teacher_plateau_window;
recent=eRms(end-w:end);
errorRelative=max(abs(diff(recent)))/max(mean(recent),eps);
ffRelative=max(ffChange(end-w+1:end));
assert(errorRelative<=o.teacher_error_relative_change, ...
    'accelff:ILCTeacherNotConverged','Tracking error has not reached the configured plateau.');
assert(ffRelative<=o.teacher_ff_relative_change, ...
    'accelff:ILCTeacherNotConverged','Learned FF is still changing too much.');
assert(residualRatio(end)<=o.teacher_feedback_ratio, ...
    'accelff:ILCTeacherFeedbackResidual', ...
    'Final feedback effort is too large relative to learned FF for teacher use.');

% Use the FINAL APPLIED learned FF as the repeatable disturbance teacher.
% Do not replace it with row-3 total command, because that would fold the
% remaining feedback correction into the map and depart from the thesis ILC
% decomposition. The total command remains available in diagnostics.
teacher=results{end}.trace;
teacher.current=teacher.ff;
teacher.current_kind="ilc_ff_A";
teacher.method="ilc_teacher";
teacher.quality_passed=true;
teacher.ilc_teacher_converged=true;
teacher.ilc_diagnostics=struct('iterations',n,'error_rms_m',eRms, ...
    'ff_relative_change',ffChange,'feedback_to_ff_rms_ratio',residualRatio, ...
    'plateau_error_relative_change',errorRelative, ...
    'plateau_ff_relative_change',ffRelative, ...
    'source_total_command_kind',"command_A",'teacher_current_kind',"ilc_ff_A");
end
