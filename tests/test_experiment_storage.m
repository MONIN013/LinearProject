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
staging = fullfile(runDir,'staging'); mkdir(staging);
save(fullfile(staging,'measurement_part1.mat'),'-struct','values');
paths = archive_measurement_parts(staging,runDir,fullfile('raw','velocity_001','trial_001'));
verifyEqual(testCase,load(paths(1)),values);
verifyEmpty(testCase,dir(fullfile(staging,'measurement_*.mat')));
save(fullfile(staging,'measurement_part1.mat'),'-struct','values');
verifyError(testCase,@()archive_measurement_parts(staging,runDir, ...
    fullfile('raw','velocity_001','trial_001')),'NikonMotor:RawFileExists');
verifyTrue(testCase,isfile(fullfile(staging,'measurement_part1.mat')));
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
