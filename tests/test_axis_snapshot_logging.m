function tests = test_axis_snapshot_logging
tests = functiontests(localfunctions);
end

function setupOnce(~)
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(projectRoot,'src'));
end

function testSharedRecordPreservesTenRowsAndDecodesUnsignedFields(testCase)
folder = tempname;
mkdir(folder);
cleanup = onCleanup(@()rmdir(folder,'s'));
Ts = 1/4000;
raw = fixture();
expected = reshape(1:40,10,4);
tc_yout = struct('data',num2cell([expected;double(raw)],1), ...
    'time',num2cell(15+(0:3)*Ts));
save(fullfile(folder,'measurement_part0.mat'),'tc_yout');
[measurement,timeRaw,timeElapsed,~,metadata] = load_latest_twincat_measurement(folder,Ts);
verifyEqual(testCase,measurement,expected);
verifyEqual(testCase,metadata.schema_name,"feedforward_axis_v2");
verifyEqual(testCase,metadata.signal_count,uint16(30));
verifyEqual(testCase,numel(metadata.signal_names),30);
verifyEqual(testCase,metadata.measurement_signal_count,uint16(10));
verifyEqual(testCase,metadata.measurement_time_raw,timeRaw);
verifyEqual(testCase,metadata.measurement_time,timeElapsed);
log = metadata.axisLog;
verifyEqual(testCase,log.time,timeElapsed');
verifyEqual(testCase,log.cycle,[2^32-2;2^32-1;0;1]);
verifyEqual(testCase,log.requestId,repmat(uint32(2^32-1),4,1));
verifyEqual(testCase,log.position,repmat(5.61,4,1),'AbsTol',1e-12);
verifyEqual(testCase,log.virtualCurrent,repmat(.2,4,1),'AbsTol',1e-12);
verifyEqual(testCase,log.targetCurrent,repmat([.22 .18 0 0],4,1),'AbsTol',1e-12);
verifyEqual(testCase,log.actualCurrent,repmat([.21 .19 0 0],4,1),'AbsTol',1e-12);
verifyEqual(testCase,log.statusWord,repmat(uint16([39 39 0 0]),4,1));
end

function testRejectsRepeatedCyclesAndWrongPeriod(testCase)
raw = fixture();
raw(1,3) = raw(1,2);
verifyError(testCase,@()decode_axis_snapshot(double(raw),1/4000), ...
    'NikonMotor:AxisSnapshotContinuity');
raw = fixture();
verifyError(testCase,@()decode_axis_snapshot(double(raw),1/8000), ...
    'NikonMotor:AxisSnapshotContinuity');
end

function testRejectsFractionalOrTruncatedSnapshot(testCase)
raw = double(fixture());
raw(5,2) = .5;
verifyError(testCase,@()decode_axis_snapshot(raw,1/4000),'NikonMotor:AxisSnapshotValue');
verifyError(testCase,@()decode_axis_snapshot(raw(1:19,:),1/4000),'NikonMotor:AxisSnapshotSize');
end

function testAllocationAllowsOnlyUnpoweredInitialPrefix(testCase)
Ts = 1/4000;
record = struct('requestId',uint32(2^32-1),'Ts',Ts, ...
    'allocation',struct('pair',1),'weights',[1.1,.9]);
measurement = zeros(10,4);
raw = fixture();
log = decode_axis_snapshot(double(raw),Ts);
verifyEqual(testCase,validate_allocation_capture(log,measurement,record),0);
raw([4:8,13:16,20],1) = 0;
log = decode_axis_snapshot(double(raw),Ts);
verifyEqual(testCase,validate_allocation_capture(log,measurement,record),1);
bad = log; bad.requestId(2) = 0;
verifyError(testCase,@()validate_allocation_capture(bad,measurement,record), ...
    'NikonMotor:AllocationCaptureFailed');
bad = log; bad.virtualCurrent(1) = .002;
verifyError(testCase,@()validate_allocation_capture(bad,measurement,record), ...
    'NikonMotor:AllocationCaptureFailed');
bad = log; bad.statusWord(1,1) = uint16(4);
verifyError(testCase,@()validate_allocation_capture(bad,measurement,record), ...
    'NikonMotor:AllocationCaptureFailed');
bad = log; bad.targetCurrent(2,1) = .23;
verifyError(testCase,@()validate_allocation_capture(bad,measurement,record), ...
    'NikonMotor:AllocationNotApplied');
raw([4:8,13:16,20],2) = 0;
log = decode_axis_snapshot(double(raw),Ts);
verifyEqual(testCase,validate_allocation_capture(log,measurement,record),2);
bad = log; bad.requestId(4) = 0;
verifyError(testCase,@()validate_allocation_capture(bad,measurement,record), ...
    'NikonMotor:AllocationCaptureFailed');
bad = log; bad.requestId(:) = 0;
verifyError(testCase,@()validate_allocation_capture(bad,measurement,record), ...
    'NikonMotor:AllocationCaptureFailed');
measurement(9,2) = .001;
verifyError(testCase,@()validate_allocation_capture(log,measurement,record), ...
    'NikonMotor:AllocationCaptureFailed');
end

function raw = fixture()
raw = zeros(20,4,'int32');
raw(1,:) = [-2 -1 0 1];
raw(2,:) = 56100000;
raw(4,:) = 100;
raw(5:8,:) = repmat(int32([2200;1800;0;0]),1,4);
raw(9:12,:) = repmat(int32([2100;1900;0;0]),1,4);
raw(13:16,:) = repmat(int32([39;39;0;0]),1,4);
raw(18,:) = 1;
raw(19,:) = 2500;
raw(20,:) = -1;
end
