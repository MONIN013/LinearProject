function [measurement, logFile] = capture_with_allocation(capture, allocation, Ts, runDir)
%CAPTURE_WITH_ALLOCATION Wrap an existing capture; never implements servo I/O.
% capture(requestId) returns [measurement,unused,metadata] from the common
% Simulink File Writer. The PLC only publishes the current axis snapshot.
weights = allocation_weights(allocation.beta,allocation.ratio);
validateattributes(allocation.pair,{'double'},{'scalar','integer','>=',1,'<=',3});
assert(Ts==1/4000,'NikonMotor:AllocationPeriod','Exp06 uses the 4 kHz target.');
read_tunable_idle_state(Ts);
NET.addAssembly(['C:\Program Files (x86)\Beckhoff\TwinCAT\Functions\' ...
    'TE14xx-ToolsForMatlabAndSimulink\TE141x\NET\TwinCAT.Ads.dll']);
ads = TwinCAT.Ads.TcAdsClient;
ads.Timeout = 2000;
ads.Connect('192.168.10.3.1.1',852);
guard = onCleanup(@()ads.Dispose());
read = @(name)double(ads.ReadSymbol(ads.ReadSymbolInfo(['GVL_AllocationTransfer.' name])));
assert(read('SCHEMA_VERSION')==2, ...
    'NikonMotor:AllocationRuntimeVersion','Deploy the exp06 MotorRuntime before capture.');
assert(read('FaultId')==0, ...
    'NikonMotor:AllocationBusy','Inspect the previous allocation fault before another trial.');
% An earlier MATLAB process may have stopped after arming but before servo ON.
% The idle check above makes clearing that pending request unambiguous.
if read('Active')~=0, request_allocation(ads,false); end
[measurement,logFile] = capture_allocated(ads,capture,allocation,weights,Ts,runDir);
end

function [measurement,logFile] = capture_allocated(ads,capture,allocation,weights,Ts,runDir)
guard = onCleanup(@()release_allocation(ads));
read = @(name)double(ads.ReadSymbol(ads.ReadSymbolInfo(['GVL_AllocationTransfer.' name])));
write_value(ads,'RequestedPair',uint16(allocation.pair));
write_value(ads,'RequestedBeta',allocation.beta);
write_value(ads,'RequestedRatio',allocation.ratio);
requestId = request_allocation(ads,true);
assert(read('Active')==1 && read('Pair')==allocation.pair && ...
    read('Beta')==allocation.beta && read('Ratio')==allocation.ratio, ...
    'NikonMotor:AllocationReadback','PLC did not latch the requested allocation.');
record = struct('allocation',allocation,'weights',weights,'Ts',Ts, ...
    'requestId',requestId,'passed',false);
logFile = save_experiment_result(runDir,'allocation_log',record);
try
    [measurement,~,metadata] = capture(requestId);
    record.active = logical(read('Active'));
    record.complete = logical(read('Complete'));
    record.faultId = read('FaultId');
    assert(record.complete && ~record.active && record.faultId==0, ...
        'NikonMotor:AllocationIncomplete','Allocation trial did not complete normally.');
    assert(isfield(metadata,'axisLog'), 'NikonMotor:AllocationLogMissing', ...
        'The common File Writer must contain the per-axis snapshot.');
    axisLog = metadata.axisLog;
    record.axisLog = axisLog;
    record.initialIdleSamples = validate_allocation_capture(axisLog,measurement,record);
    read_tunable_idle_state(Ts);
    request_allocation(ads,false);
    cancel(guard);
    record.passed = true;
catch cause
    record.failure = cause.message;
    % The common capture retains its raw MAT parts even when decoding fails.
    save_experiment_result(runDir,'allocation_log',record);
    rethrow(cause);
end
save_experiment_result(runDir,'allocation_log',record);
end

function write_value(ads,name,value)
ads.WriteSymbol(ads.ReadSymbolInfo(['GVL_AllocationTransfer.' name]),value);
end

function id = request_allocation(ads,enabled)
read = @(name)double(ads.ReadSymbol(ads.ReadSymbolInfo(['GVL_AllocationTransfer.' name])));
% Zero is reserved for ordinary experiments without allocation.
id = uint32(mod(read('AckId'),2^32-1)+1);
write_value(ads,'RequestedEnabled',logical(enabled));
write_value(ads,'RequestId',id);
started = tic;
while read('AckId')~=double(id) && toc(started)<2, pause(.01); end
assert(read('AckId')==double(id) && read('RejectId')==0, ...
    'NikonMotor:AllocationRequestRejected','PLC rejected allocation request (code %d).',read('RejectId'));
end

function release_allocation(ads)
try
    request_allocation(ads,false);
catch cause
    warning('NikonMotor:AllocationResetFailed','%s',cause.message);
end
end
