function s = idle_snapshot(cfg)
%IDLE_SNAPSHOT Read-only ADS verification of the existing four-axis runtime.
% Pre/post check only: not an in-motion monitor or a safety-rated stop.
% Unavailable symbols fail closed. No reset, calibration write, or arming.
NET.addAssembly(char(cfg.ads_dll));
ads=TwinCAT.Ads.TcAdsClient;
guard=onCleanup(@()ads.Dispose()); %#ok<NASGU>
ads.Timeout=2000;
ads.Connect(char(cfg.ams_net_id),cfg.ads_port);
state=ads.ReadState();
assert(string(state.AdsState)=="Run",'accelff:NotRun','TwinCAT is not in Run.');
read=@(name)double(ads.ReadSymbol(ads.ReadSymbolInfo(char(name))));
s=struct('position_m',read('GVL_MotorRuntime.Status.PositionActualValue')*cfg.encoder_m_per_count, ...
    'velocity_m_s',read('GVL_MotorRuntime.Status.VelocityActualValue')*cfg.velocity_m_s_per_count, ...
    'fault',read('GVL_MotorRuntimeInternal.Feedback.fault_id'), ...
    'io_ready',read('PRG_MotorRuntime.fbIoWatchdog.SafeToDrive'), ...
    'task_period_s',read('PRG_MotorRuntime.taskPeriod_s'));
assert(all(isfinite([s.position_m,s.velocity_m_s,s.fault,s.io_ready,s.task_period_s])) && ...
    s.fault==0 && s.io_ready==1 && abs(s.velocity_m_s)<=cfg.idle_velocity_m_s && ...
    abs(s.task_period_s-cfg.Ts)<=1e-12, ...
    'accelff:NotIdle','Idle, fault, I/O, or task-period check failed.');
assert(read('GVL_MotorRuntime.Command.TargetTorque')==0 && ...
    bitand(uint16(read('GVL_MotorRuntime.Command.ControlWord')),uint16(15))~=15 && ...
    read('GVL_MotorRuntimeInternal.CommissioningCommand.ControlWord')==0 && ...
    read('GVL_MotorRuntimeInternal.CommissioningCommand.TargetTorque')==0 && ...
    read('GVL_MotorRuntimeInternal.CommutationOverride.enable')==0, ...
    'accelff:CompetingCommand','A normal or commissioning command is still active.');
manifest=jsondecode(fileread(cfg.calibration_manifest));
assert(numel(manifest.axes)==4,'accelff:Calibration','Expected four calibrated axes.');
s.axis_status=zeros(4,1); s.axis_target=zeros(4,1);
for k=1:4
    s.axis_status(k)=read(sprintf('PRG_MotorRuntime.copleyStatusWordModule%d',k));
    s.axis_target(k)=read(sprintf('PRG_MotorRuntime.copleyTargetTorqueModule%d',k));
    assert(isfinite(s.axis_status(k)) && isfinite(s.axis_target(k)) && ...
        bitand(uint16(s.axis_status(k)),uint16(12))==0 && s.axis_target(k)==0, ...
        'accelff:AxisEnabled','Axis %d is enabled, faulted, or requesting torque.',k);
    expected=manifest.axes([manifest.axes.axis_index]==k);
    assert(isscalar(expected),'accelff:Calibration','Axis manifest is not unique.');
    assert(read(sprintf('GVL_MotorRuntimeInternal.RegisteredReferenceValid[%d]',k))==1, ...
        'accelff:Calibration','An axis calibration is invalid.');
    for name={'reference_position_count','reference_commutation_angle','electrical_direction'}
        value=read(sprintf('GVL_MotorRuntimeInternal.RegisteredReference[%d].%s',k,name{1}));
        assert(value==expected.(name{1}),'accelff:Calibration','Axis %d reference differs.',k);
    end
end
% Verify host model switches as well as independently read physical outputs.
model='linear_exp_tunable_2025a';
assert(bdIsLoaded(model),'accelff:ModelUnavailable','Cannot verify model switches.');
w=get_param(model,'ModelWorkspace');
for name={'p_active','p_servo'}
    value=w.evalin(name{1});
    if isa(value,'Simulink.Parameter'), value=value.Value; end
    assert(isnumeric(value) && isscalar(value) && isfinite(value) && value==0, ...
        'accelff:ModelArmed','A model enable switch is not zero.');
    s.(name{1})=value;
end
end
