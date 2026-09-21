function result = configure_tunable_axis_logging(modelFile)
%CONFIGURE_TUNABLE_AXIS_LOGGING Append the PLC snapshot to the existing writer.
% Calling this helper changes and saves the model; rebuild its TcCOM module and
% map AxisSnapshot.Raw to GVL_AllocationTransfer.Snapshot before using it.
if nargin < 1
    projectRoot = fileparts(fileparts(mfilename('fullpath')));
    modelFile = fullfile(projectRoot,'simulink','linear_exp_tunable_2025a.slx');
end
[~,model] = fileparts(string(modelFile));
wasLoaded = bdIsLoaded(model);
load_system(modelFile);
guard = onCleanup(@()close_if_opened(model,wasLoaded));
mux = model+'/Mux2';
subsystem = model+'/Axis Snapshot';
marker = 'NikonMotor:AxisSnapshot:v2';
original = get_param(mux,'PortConnectivity');
original = original(1:10);
assert(all(arrayfun(@(port)~isempty(port.SrcBlock),original)), ...
    'NikonMotor:DisconnectedLegacySignal','The original ten writer signals must be connected.');
if getSimulinkBlockHandle(subsystem)>=0
    assert(strcmp(get_param(subsystem,'Tag'),marker), ...
        'NikonMotor:AxisSnapshotConflict','An unrelated Axis Snapshot block exists.');
    delete_block(subsystem);
    set_param(mux,'Inputs','10');
end
assert(strcmp(get_param(mux,'Inputs'),'10'), ...
    'NikonMotor:UnexpectedFileWriterSchema','Expected the original ten writer inputs.');
add_block('built-in/Subsystem',subsystem,'Position',[2290 1120 2450 1180],'Tag',marker);
add_block(model+'/linear system/Position Actual Value',subsystem+'/Raw', ...
    'Position',[30 35 180 65]);
set_param(subsystem+'/Raw','PortDataType','int32','Value','zeros(20,1)', ...
    'PortDim','20','SampleTime','-1','CodeGenConnectType','DataArea (InputDst)');
add_block('simulink/Signal Attributes/Data Type Conversion',subsystem+'/ToDouble', ...
    'OutDataTypeStr','double','Position',[230 35 330 65]);
add_block('simulink/Sinks/Out1',subsystem+'/Snapshot', ...
    'Position',[380 42 410 58]);
add_line(subsystem,'Raw/1','ToDouble/1');
add_line(subsystem,'ToDouble/1','Snapshot/1');
set_param(mux,'Inputs','11');
add_line(model,'Axis Snapshot/1','Mux2/11','autorouting','on');
updated = get_param(mux,'PortConnectivity');
for k = 1:10
    assert(isequal(updated(k).SrcBlock,original(k).SrcBlock) && ...
        isequal(updated(k).SrcPort,original(k).SrcPort), ...
        'NikonMotor:LegacySignalOrderChanged','The original ten writer signals changed.');
end

% A request belongs to the same run as p_ref/p_ff. Every ordinary run sets it
% to zero, so an interrupted exp06 setup cannot affect another experiment.
workspace = get_param(model,'ModelWorkspace');
parameter = Simulink.Parameter(uint32(0));
assignin(workspace,'p_allocation_request_id',parameter);
constant = model+'/Allocation Request';
output = model+'/Allocation Request Id';
if getSimulinkBlockHandle(constant)<0
    add_block('simulink/Sources/Constant',constant, ...
        'Position',[2290 1220 2450 1250],'Tag',marker);
else
    assert(strcmp(get_param(constant,'Tag'),marker), ...
        'NikonMotor:AllocationRequestConflict','An unrelated Allocation Request block exists.');
end
set_param(constant,'Value','p_allocation_request_id','OutDataTypeStr','uint32');
if getSimulinkBlockHandle(output)<0
    add_block(model+'/linear system/Target Torque',output, ...
        'Position',[2550 1220 2700 1250],'Tag',marker);
    add_line(model,'Allocation Request/1','Allocation Request Id/1','autorouting','on');
else
    assert(strcmp(get_param(output,'Tag'),marker), ...
        'NikonMotor:AllocationRequestConflict','An unrelated Allocation Request Id block exists.');
end
set_param(output,'PortDataType','uint32','SampleTime','-1', ...
    'CodeGenConnectType','DataArea (OutputSrc)');
save_system(model);
result = struct('model',model,'schema_name',"feedforward_axis_v2", ...
    'file_writer_width',30,'snapshot_input',subsystem+'/Raw','request_output',output);
end

function close_if_opened(model,wasLoaded)
if ~wasLoaded && bdIsLoaded(model), close_system(model,0); end
end
