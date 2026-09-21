function tests = test_experiment_storage
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(root);
testCase.TestData.root = setup_project();
end

function testRunSaveLoadFromExperimentFolder(testCase)
root = testCase.TestData.root;
previous = pwd;
cdGuard = onCleanup(@()cd(previous));
cd(fullfile(root,'exp01_SI'));
runDir = create_run_directory(fullfile('.codex-temp'),'storage_test');
guard = onCleanup(@()rmdir(runDir,'s'));
values = struct('Ts',1/4000,'measurement',[1 2;3 4]);
matPath = save_experiment_result(runDir,'result',values);
verifyEqual(testCase,load(matPath),values);
verifyTrue(testCase,startsWith(runDir,root));
values.measurement = values.measurement*2;
save_experiment_result(runDir,'result',values);
verifyEqual(testCase,load(matPath),values);
verifyEqual(testCase,numel(dir(fullfile(runDir,'*.mat'))),1);
staging = fullfile(runDir,'staging'); mkdir(staging);
save(fullfile(staging,'measurement_part1.mat'),'-struct','values');
verifyError(testCase,@()archive_measurement_parts(staging), ...
    'NikonMotor:RunDirectoryRequired');
verifyTrue(testCase,isfile(fullfile(staging,'measurement_part1.mat')));
previousPaths = archive_measurement_parts(staging,runDir,fullfile('raw','previous'));
verifyEqual(testCase,load(previousPaths(1)),values);
save(fullfile(staging,'measurement_part1.mat'),'-struct','values');
paths = archive_measurement_parts(staging,runDir,fullfile('raw','velocity_001','trial_001'));
verifyEqual(testCase,load(paths(1)),values);
verifyEmpty(testCase,dir(fullfile(staging,'measurement_*.mat')));
save(fullfile(staging,'measurement_part1.mat'),'-struct','values');
verifyError(testCase,@()archive_measurement_parts(staging,runDir, ...
    fullfile('raw','velocity_001','trial_001')),'NikonMotor:RawFileExists');
verifyTrue(testCase,isfile(fullfile(staging,'measurement_part1.mat')));
verifyEqual(testCase,load(previousPaths(1)),values);
fig = figure('Visible','off');
figureGuard = onCleanup(@()close(fig));
plot(1:3);
figurePaths = save_experiment_figures(runDir,fig);
verifyEqual(testCase,fileparts(figurePaths(1)),string(runDir));
verifyTrue(testCase,isfile(figurePaths(1)));
end

function testSaveWaitsForTemporaryWindowsFileLock(testCase)
assumeTrue(testCase,ispc);
runDir = create_run_directory(fullfile(testCase.TestData.root,'.codex-temp'), ...
    'storage_lock_test');
original = struct('trial',1);
file = save_experiment_result(runDir,'result',original);
locked = System.IO.File.Open(file,System.IO.FileMode.Open, ...
    System.IO.FileAccess.Read,System.IO.FileShare.None);
lockGuard = onCleanup(@()locked.Dispose());
release = timer('StartDelay',0.15,'TimerFcn',@(~,~)locked.Dispose());
timerGuard = onCleanup(@()delete(release));
start(release);
updated = struct('trial',2);
save_experiment_result(runDir,'result',updated);
verifyEqual(testCase,load(file),updated);
verifyEqual(testCase,numel(dir(fullfile(runDir,'*.mat'))),1);
archiveRun = create_run_directory(fullfile(testCase.TestData.root,'data','storage_test'),'lock');
source = save_experiment_result(archiveRun,'result',updated);
sourceLock = System.IO.File.Open(source,System.IO.FileMode.Open, ...
    System.IO.FileAccess.Read,System.IO.FileShare.None);
sourceGuard = onCleanup(@()sourceLock.Dispose());
releaseSource = timer('StartDelay',0.15,'TimerFcn',@(~,~)sourceLock.Dispose());
sourceTimerGuard = onCleanup(@()delete(releaseSource));
start(releaseSource);
archive_experiment_intermediates(string(source));
verifyFalse(testCase,isfile(source));
archived = strrep(source,[filesep 'data' filesep], ...
    [filesep '.codex-temp' filesep 'data-originals' filesep]);
verifyEqual(testCase,load(archived),updated);
end

function testPlantPublicationKeepsHistoryAndOtherPeriod(testCase)
root = testCase.TestData.root;
baseDir = tempname; mkdir(baseDir);
guard = onCleanup(@()rmdir(baseDir,'s'));
plantsDir = fullfile(baseDir,'plants');
plant4 = load_experiment_plant(root,'data/plants/4khz/current.mat',1/4000);
plant8 = load_experiment_plant(root,'data/plants/8khz/current.mat',1/8000);
[history8,current8] = save_experiment_plant(fullfile(baseDir,'si8'),plant8,plantsDir);
[history4,current4] = save_experiment_plant(fullfile(baseDir,'si4'),plant4,plantsDir);
plant4.Jn = plant4.Jn*1.01;
save_experiment_plant(fullfile(baseDir,'si4_second'),plant4,plantsDir);
published = load(current4);
original = load(history4);
verifyEqual(testCase,published.Jn,plant4.Jn);
verifyNotEqual(testCase,original.Jn,published.Jn);
verifyEqual(testCase,load(current8),load(history8));
invalid = plant4; invalid.Ts = 1/8000;
verifyError(testCase,@()save_experiment_plant(fullfile(baseDir,'invalid'),invalid,plantsDir), ...
    'NikonMotor:PlantSamplePeriodMismatch');
verifyEqual(testCase,load(current8),load(history8));
end

function testPackedCaptureRetainsEverySignal(testCase)
root = testCase.TestData.root;
runDir = create_run_directory(fullfile(root,'data','storage_test'),'roundtrip');
rawDir = fullfile(runDir,'raw','teacher','trial_001'); mkdir(rawDir);
Ts = 1/4000;
measurement = reshape(1:50,10,5);
snapshot = zeros(20,5); snapshot(1,:) = 101:105; snapshot(19,:) = 2500;
data = [measurement;snapshot];
tc_yout = struct('time',num2cell((0:4)*Ts),'data',num2cell(data,1));
save(fullfile(rawDir,'measurement_part1.mat'),'tc_yout');
record = struct('axisLog',decode_axis_snapshot(snapshot,Ts),'passed',true);
save(fullfile(rawDir,'allocation_log.mat'),'-struct','record');
fields = {'count','e','u','y','ff','y_absolute','r'}; rows = [1 2 3 5 7 8 9];
history = struct();
for k = 1:numel(rows), history.(fields{k}) = measurement(rows(k),:)'; end
history.allocationLogFiles = {fullfile(rawDir,'allocation_log.mat')};
failedDir = fullfile(runDir,'raw','teacher','trial_002'); mkdir(failedDir);
save(fullfile(failedDir,'measurement_part2.mat'),'tc_yout');
failed = record; failed.passed = false;
save(fullfile(failedDir,'allocation_log.mat'),'-struct','failed');
result = struct('history',history,'Ts',Ts);
file = finalize_experiment_result(runDir,'result',result);
packed = load(file);
[actual,axis,time] = read_experiment_capture(packed,1);
verifyEqual(testCase,actual,measurement);
verifyEqual(testCase,axis,record.axisLog);
verifyEqual(testCase,time,(0:4)*Ts);
verifyEqual(testCase,packed.captures{1}.rows,[4 6 10]);
[actualFailed,axisFailed] = read_experiment_capture(packed,2);
verifyEqual(testCase,actualFailed,measurement);
verifyEqual(testCase,axisFailed,record.axisLog);
verifyFalse(testCase,packed.captures{2}.allocationLog.passed);
resumed = packed; resumed.history.captures = packed.captures;
resumed = rmfield(resumed,'captures');
resumedFile = finalize_experiment_result(runDir,'resumed',resumed);
[resumedMeasurement,resumedAxis] = read_experiment_capture(resumedFile,1);
verifyEqual(testCase,resumedMeasurement,measurement);
verifyEqual(testCase,resumedAxis,record.axisLog);
verifyEmpty(testCase,dir(fullfile(runDir,'**','measurement_*.mat')));
archive = fullfile(root,'.codex-temp','data-originals','storage_test');
verifyTrue(testCase,isfile(fullfile(archive,erase(runDir,[fullfile(root,'data','storage_test') filesep]), ...
    'raw','teacher','trial_001','measurement_part1.mat')));
rmdir(runDir,'s');
end
