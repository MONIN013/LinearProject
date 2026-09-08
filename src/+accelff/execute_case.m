function result = execute_case(job, cfg, confirmation)
%EXECUTE_CASE ONE operator-authorized capture using the existing tunable path.
% WARNING: this function enables the real servo and moves the stage.
% No build, Activate, homing, auto-retry, calibration write, or limit increase.
% ILC is intentionally ONE TRIAL PER CALL. Learning updates are computed
% offline by accelff.ilc_update; this runner never auto-runs an ILC sequence.
% cfg.supervisor_probe must query the independent LOCAL monitor. A constant
% true callback is not a valid implementation. See exp05_AccelerationFF/README.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
assert(string(confirmation)=="RUN "+string(job.id),'accelff:NotArmed', ...
    'The operator must explicitly authorize this case ID.');
assert(isa(cfg.supervisor_probe,'function_handle'),'accelff:Supervisor', ...
    'Connect a live independent supervisor probe before real operation.');
for name={'current_limit_A','ff_limit_A','ff_slew_A_s','velocity_limit_m_s', ...
        'acceleration_limit_m_s2','jerk_limit_m_s3','tracking_limit_m', ...
        'terminal_limit_m','origin_tolerance_m','idle_velocity_m_s', ...
        'encoder_m_per_count','velocity_m_s_per_count','saturation_margin_A','signal_tolerance', ...
        'evaluation_velocity_floor','evaluation_acceleration_threshold'}
    validateattributes(cfg.(name{1}),{'double'},{'scalar','finite','positive'});
end
validateattributes(cfg.Ts,{'double'},{'scalar','finite','positive'});
validateattributes(cfg.position_limits_m,{'double'},{'vector','numel',2,'finite'});
assert(cfg.position_limits_m(1)<cfg.position_limits_m(2) && ...
    cfg.ff_limit_A<cfg.current_limit_A && cfg.saturation_margin_A<cfg.current_limit_A, ...
    'accelff:Limits','Invalid position interval, FF reserve, or saturation margin.');
allowed=["fb","thesis","acceleration","ilc_teacher", ...
    "ilc_zero","ilc_thesis","ilc_acceleration"];
assert(ismember(string(job.method),allowed),'accelff:Method','Unknown comparison/ILC method.');
assert(ismember(string(job.split),["train","validation","test"]), ...
    'accelff:Split','Unknown data split.');
assert((string(job.method)=="ilc_teacher" && string(job.split)=="train") || ...
    string(job.method)~="ilc_teacher",'accelff:ILCTeacherSplit', ...
    'ILC teacher trials must remain in the predeclared train split.');
assert(strlength(string(job.profile_id))>0 && ...
    ~isempty(regexp(char(job.id),'^[A-Za-z0-9_-]+$','once')), ...
    'accelff:ID','Case ID must be a nonempty path-safe identifier.');
validateattributes(job.repeat,{'double'},{'scalar','integer','positive'});
n=numel(job.r);
validateattributes(cfg.logging_delay_samples,{'double'},{'scalar','integer','nonnegative','<',n});
validateattributes(job.origin_m,{'double'},{'scalar','finite'});
for name={'r','v','a','j','f'}
    validateattributes(job.(name{1}),{'double'},{'column','finite','real','numel',n});
end
assert(n>=5 && n<=tunable_trajectory_buffer_capacity() && job.Ts==cfg.Ts, ...
    'accelff:Buffer','Invalid trajectory length, fixed-buffer size, or period.');
assert(job.r(1)==0 && abs(job.r(end))<=cfg.terminal_limit_m, ...
    'accelff:Endpoint','This experiment requires a relative zero-to-zero round trip.');
assert(max(abs(job.v))<=cfg.velocity_limit_m_s && ...
    max(abs(diff(job.r)))/cfg.Ts<=cfg.velocity_limit_m_s && ...
    max(abs(job.a))<=cfg.acceleration_limit_m_s2 && ...
    max(abs(diff(job.r,2)))/cfg.Ts^2<=cfg.acceleration_limit_m_s2*1.01 && ...
    max(abs(job.j))<=cfg.jerk_limit_m_s3 && ...
    max(abs(diff(job.r,3)))/cfg.Ts^3<=cfg.jerk_limit_m_s3*1.02,'accelff:MotionLimit','Trajectory exceeds approved limits.');
assert(max(abs(job.f))<=cfg.ff_limit_A && ...
    max(abs(diff(job.f)))/cfg.Ts<=cfg.ff_slew_A_s, ...
    'accelff:FFLimit','FF violates its reserved amplitude/slew budget.');
if string(job.method)=="fb" || string(job.method)=="ilc_zero"
    assert(all(job.f==0),'accelff:Baseline','Zero-initialized condition must have zero FF.');
end
x=job.origin_m+job.r;
assert(all(x>=cfg.position_limits_m(1) & x<=cfg.position_limits_m(2)), ...
    'accelff:Travel','Requested absolute position exceeds reviewed travel.');
assert_target_built(root,'tunable_build_info.mat',cfg.Ts);
assert(evalin('base','Ts')==cfg.Ts && evalin('base','feedbackFlag')==1 && ...
    evalin('base','MAX_INPUT')==cfg.current_limit_A && ...
    isequaln(evalin('base','Kd'),cfg.approved_Kd) && ...
    evalin('base','ENCODER_RESOLUTION')==cfg.encoder_m_per_count && ...
    evalin('base','VELOCITY_RESOLUTION')==cfg.velocity_m_s_per_count, ...
    'accelff:Context','Prepared controller/current limit/scaling differs from reviewed settings.');
ModelName='simulink/linear_exp_tunable_2025a.slx';
model='linear_exp_tunable_2025a'; load_system(fullfile(root,ModelName));
assert(string(get_param(model,'SimulationStatus'))=="stopped" && ...
    strtrim(string(get_param(model,'ExtModeMexArgs')))==strtrim(string(cfg.extmode_args)), ...
    'accelff:Model','Model is busy or the external-mode target differs.');
% Do not shadow base-workspace controller symbols: that changes checksums.
w=get_param(model,'ModelWorkspace');
for name={'Ts','Kd','MAX_INPUT','feedbackFlag','CURRENT_TO_UNIT','ENCODER_RESOLUTION','VELOCITY_RESOLUTION'}
    assert(~w.hasVariable(name{1}),'accelff:Scope','Controller symbols must keep their build-time scope.');
end
for name={'p_servo','p_active'}
    value=w.evalin(name{1}); if isa(value,'Simulink.Parameter'), value=value.Value; end
    assert(isequal(value,0),'accelff:ModelArmed','The model is already armed.');
end
pre=accelff.idle_snapshot(cfg);
assert(abs(pre.position_m-job.origin_m)<=cfg.origin_tolerance_m, ...
    'accelff:Origin','Homing origin differs; reprepare this case using the actual position.');
preSupervisor=check_supervisor(cfg,job);
[gitStatus,revision]=system(sprintf('git -C "%s" rev-parse HEAD',root));
assert(gitStatus==0,'accelff:Revision','Cannot record the repository revision.');
category="ff";
if startsWith(string(job.method),"ilc"), category="ilc"; end
runDir=create_run_directory(fullfile(root,'data',category),"acceleration_"+string(job.id));
% supervisor handles stay local; retain all numerical settings and evidence.
recordCfg=rmfield(cfg,'supervisor_probe');
result=struct('status',"running",'job',job,'config',recordCfg, ...
    'revision',strtrim(string(revision)),'pre',pre,'supervisor_pre',preSupervisor, ...
    'run_directory',string(runDir));
save_experiment_result(runDir,'case_started',result);
try
    measurement=capture_tunable_trajectory(ModelName,job.r,job.f,cfg.Ts,runDir);
    result.measurement=measurement; % retain evidence even when decoding fails
    result.post=accelff.idle_snapshot(cfg);
    result.supervisor_post=check_supervisor(cfg,job);
    tr=accelff.decode(measurement,job,cfg.logging_delay_samples,cfg.signal_tolerance);
    moving=abs(tr.v_ref)>=cfg.evaluation_velocity_floor;
    accelerated=moving & abs(tr.a_ref)>=cfg.evaluation_acceleration_threshold;
    metrics=struct('rms_all_m',sqrt(mean(tr.error.^2)), ...
        'peak_m',max(abs(tr.error)),'terminal_m',abs(tr.y_relative(end)), ...
        'current_peak_A',max(abs(tr.current)), ...
        'saturated_samples',sum(abs(tr.current)>=cfg.current_limit_A-cfg.saturation_margin_A), ...
        'rms_moving_m',NaN,'rms_accelerating_m',NaN,'rms_near_constant_m',NaN);
    if any(moving), metrics.rms_moving_m=sqrt(mean(tr.error(moving).^2)); end
    if any(accelerated), metrics.rms_accelerating_m=sqrt(mean(tr.error(accelerated).^2)); end
    nearConstant=moving & ~accelerated;
    if any(nearConstant), metrics.rms_near_constant_m=sqrt(mean(tr.error(nearConstant).^2)); end
    accepted=any(moving) && metrics.peak_m<=cfg.tracking_limit_m && ...
        metrics.terminal_m<=cfg.terminal_limit_m && metrics.saturated_samples==0 && ...
        all(tr.x>=cfg.position_limits_m(1) & tr.x<=cfg.position_limits_m(2));
    tr.quality_passed=accepted;
    result.trace=tr; result.metrics=metrics;
    assert(accepted,'accelff:Rejected','Captured but rejected: saturation, tracking, travel, or terminal check.');
    result.status="accepted";
catch cause
    result.status="failed"; result.failure_id=string(cause.identifier);
    result.failure_message=string(cause.message);
    % The existing capture owns servo shutdown on exceptions. Never silently
    % treat its warning-only cleanup as verified de-energization.
    try, result.post=accelff.idle_snapshot(cfg);
    catch stopCause, result.stop_unverified=string(stopCause.message); end
    save_experiment_result(runDir,'case_failed',result);
    rethrow(cause)
end
save_experiment_result(runDir,'case_result',result);
end

function s=check_supervisor(cfg,job)
s=cfg.supervisor_probe();
assert(isstruct(s) && isscalar(s) && isequal(s.running,true) && ...
    isequal(s.trip_latched,false) && string(s.case_id)==string(job.id), ...
    'accelff:Supervisor','Independent monitor unavailable, tripped, or monitoring another case.');
end
