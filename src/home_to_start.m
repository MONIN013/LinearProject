function [measurement, homing] = home_to_start(targetCount)
%HOME_TO_START Move to an absolute encoder position through the virtual CST.
% Callable from any experiment without loading FF settings. Requires the
% deployed linear_exp_tunable_2025a module. The caller's workspace/controller
% and trajectory are preserved. This is not an encoder-zero/limit-switch seek.
if nargin < 1, targetCount = 54100000; end
validateattributes(targetCount, {'numeric'}, ...
    {'scalar','real','finite','integer','>=',54054804,'<=',66655810});
projectRoot = fileparts(fileparts(mfilename('fullpath')));
settings = load(fullfile(projectRoot,'config','data','config_tunable.mat'),'ModelName');
ModelName = settings.ModelName;
run(fullfile(projectRoot,'config','sample_rate.m'));
motor = load(fullfile(projectRoot,'config','data','pana_params.mat'));
ENCODER_RESOLUTION = motor.ENCODER_RESOLUTION;
NET.addAssembly(['C:\Program Files (x86)\Beckhoff\TwinCAT\Functions\' ...
    'TE14xx-ToolsForMatlabAndSimulink\TE141x\NET\TwinCAT.Ads.dll']);
ads = TwinCAT.Ads.TcAdsClient;
guard = onCleanup(@()ads.Dispose());
ads.Timeout = 2000;
ads.Connect('192.168.10.3.1.1',852);
readValue = @(name)double(ads.ReadSymbol(ads.ReadSymbolInfo(char(name))));
startCount = readValue('GVL_MotorRuntime.Status.PositionActualValue');
assert(startCount >= 54054804 && startCount <= 66655810, ...
    'NikonMotor:HomingRange','Current position is outside the measured travel range.');
assert(readValue('GVL_MotorRuntime.Command.TargetTorque') == 0 ...
    && abs(readValue('GVL_MotorRuntime.Status.VelocityActualValue')) <= 1000 ...
    && readValue('GVL_MotorRuntimeInternal.Feedback.fault_id') == 0, ...
    'NikonMotor:HomingNotIdle','Homing requires an idle, fault-free stage.');
distance = (targetCount-startCount)*ENCODER_RESOLUTION;
if abs(targetCount-startCount) <= 1000
    measurement = [];
    homing = struct('start_count',startCount,'target_count',targetCount, ...
        'final_count',startCount,'success',true,'skipped',true);
    fprintf('HOMING already at start: %.0f count\n',startCount);
    return
end
velocityLimit = 0.2; accelerationLimit = 0.5;
% Quintic rest-to-rest motion: max ds/dt=1.875, max d2s/dt2=10/sqrt(3).
duration = max(1.875*abs(distance)/velocityLimit, ...
    sqrt((10/sqrt(3))*abs(distance)/accelerationLimit));
duration = max(Ts,ceil(duration/Ts)*Ts);
phase = (0:Ts:duration)'/duration;
r = [zeros(round(0.5/Ts),1); ...
    distance*(10*phase.^3-15*phase.^4+6*phase.^5); ...
    repmat(distance,round(1/Ts),1)];
f = zeros(size(r)); N = numel(r); Tend = (N-1)*Ts;
assert(max(abs(diff(r)/Ts)) <= velocityLimit+1e-8);
assert(max(abs(diff(r,2)/Ts^2)) <= accelerationLimit+1e-6);
homing = struct('start_count',startCount,'target_count',targetCount, ...
    'velocity_limit_m_s',velocityLimit,'acceleration_limit_m_s2',accelerationLimit);
fprintf('HOMING start=%.0f target=%.0f distance=%g m duration=%g s\n', ...
    startCount,targetCount,distance,Tend);
[plant, plantPath] = load_experiment_plant(projectRoot,plantDataFile,Ts);
[fb,~,~] = fbDesign(plant.Pd,Ts);
[~,model] = fileparts(ModelName);
wasLoaded = bdIsLoaded(model);
load_system(fullfile(projectRoot,ModelName));
assert(string(get_param(model,'SimulationStatus')) == "stopped", ...
    'NikonMotor:HomingModelBusy','Finish the current capture before Homing.');
workspace = get_param(model,'ModelWorkspace');
context = struct('Ts',Ts,'Kd',fb.K,'feedbackFlag',1, ...
    'MAX_INPUT',motor.MAX_INPUT,'CURRENT_TO_UNIT',motor.CURRENT_TO_UNIT, ...
    'ENCODER_RESOLUTION',motor.ENCODER_RESOLUTION, ...
    'VELOCITY_RESOLUTION',motor.VELOCITY_RESOLUTION);
names = [fieldnames(context); {'p_ref';'p_ff';'p_count';'p_active';'p_servo'}];
previous = cell(size(names)); existed = false(size(names));
previousParameterValues = cell(size(names));
for k = 1:numel(names)
    existed(k) = workspace.hasVariable(names{k});
    if existed(k)
        previous{k} = workspace.evalin(names{k});
        if isa(previous{k},'Simulink.Parameter')
            previousParameterValues{k} = previous{k}.Value;
        end
    end
end
previousDirty = get_param(model,'Dirty');
previousMode = get_param(model,'SimulationMode');
previousExtArgs = get_param(model,'ExtModeMexArgs');
contextNames = fieldnames(context);
baseExisted = false(size(contextNames)); basePrevious = cell(size(contextNames));
for k = 1:numel(contextNames)
    baseExisted(k) = evalin('base',sprintf('exist(''%s'',''var'')',contextNames{k}));
    if baseExisted(k), basePrevious{k} = evalin('base',contextNames{k}); end
end
contextGuard = onCleanup(@()restore_context( ...
    model,workspace,names,existed,previous,previousParameterValues,wasLoaded,previousDirty, ...
    contextNames,baseExisted,basePrevious,previousMode,previousExtArgs));
% Deployed common trajectory module (Object3, 0x01010020).
set_param(model,'ExtModeMexArgs',"'192.168.10.3.1.1' 0 16842784");
for k = 1:numel(contextNames)
    % Keep the scope used during code generation; moving these symbols into
    % model workspace changes the external-mode structural checksum.
    if workspace.hasVariable(contextNames{k})
        evalin(workspace,['clear ' contextNames{k}]);
    end
    assignin('base',contextNames{k},context.(contextNames{k}));
end
runDir = create_run_directory('data/homing','Homing_Result');
measurement = capture_tunable_trajectory(ModelName,r,f,Ts,runDir);
homing.final_count = readValue('GVL_MotorRuntime.Status.PositionActualValue');
homing.success = abs(homing.final_count-targetCount) <= 1000;
homing.result_path = fullfile(runDir,'Homing_Result.mat');
save_experiment_result(runDir,'Homing_Result',struct( ...
    'measurement',measurement,'homing',homing,'r',r,'f',f,'Ts',Ts,'plantPath',plantPath));
fprintf('HOMING_RESULT final=%.0f error=%.0f count success=%d\n', ...
    homing.final_count,homing.final_count-targetCount,homing.success);
assert(homing.success,'NikonMotor:HomingFailed','Homing did not reach the start position within 100 um.');
clear contextGuard guard
end

function restore_context(model,workspace,names,existed,previous,values,wasLoaded,dirty, ...
        baseNames,baseExisted,basePrevious,previousMode,previousExtArgs)
for k = 1:numel(baseNames)
    if baseExisted(k)
        assignin('base',baseNames{k},basePrevious{k});
    else
        evalin('base',['clear ' baseNames{k}]);
    end
end
for k = 1:numel(names)
    if existed(k)
        if isa(previous{k},'Simulink.Parameter')
            % Restore Value without copying away model-owned CoderInfo.
            previous{k}.Value = values{k};
        end
        assignin(workspace,names{k},previous{k});
    else
        evalin(workspace,['clear ' names{k}]);
    end
end
if wasLoaded
    set_param(model,'SimulationMode',previousMode,'ExtModeMexArgs',previousExtArgs);
    set_param(model,'Dirty',dirty);
else
    close_system(model,0);
end
end
