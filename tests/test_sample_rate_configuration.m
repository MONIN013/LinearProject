function tests = test_sample_rate_configuration
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(repoRoot, "src"));
testCase.TestData.repoRoot = repoRoot;
end

function testLoadsMatchingFourAndEightKilohertzPlants(testCase)
cases = { ...
    "data_4k/charp_plant.mat", 1/4000, 110; ...
    "data/plant.mat", 1/8000, 80};

for k = 1:size(cases, 1)
    [plant, plantPath] = load_experiment_plant( ...
        testCase.TestData.repoRoot, cases{k, 1}, cases{k, 2});
    verifyEqual(testCase, plant.Ts, cases{k, 2}, "AbsTol", 1e-12);
    verifyEqual(testCase, plant.Pd.Ts, cases{k, 2}, "AbsTol", 1e-12);
    verifyTrue(testCase, isfile(plantPath));

    fb = fbDesign(plant.Pd, cases{k, 2});
    nominal = struct("m", plant.Jn, "d", plant.Dn, "k", 0, ...
        "delay", plant.Ndelay, "lp", [0, 0, 0]);
    [~, discreteNominal] = modelCreate( ...
        nominal, cases{k, 2}, plant.Pd.Frequency);
    verifyTrue(testCase, isstable(feedback( ...
        discreteNominal.modelDelayed*fb.K, 1)));
    sensitivity = feedback(1, plant.Pd*fb.K);
    verifyLessThanOrEqual(testCase, ...
        max(abs(sensitivity.ResponseData), [], "all"), 2);

    pid = designpid(plant.Dn/plant.Jn, 0, 1/plant.Jn, cases{k, 3});
    discretePid = c2d(pid, cases{k, 2}, "tustin");
    pidSensitivity = feedback(1, plant.Pd*discretePid);
    verifyLessThanOrEqual(testCase, ...
        max(abs(pidSensitivity.ResponseData), [], "all"), 2);
end
end

function testRejectsMismatchedPlant(testCase)
verifyError(testCase, ...
    @()load_experiment_plant(testCase.TestData.repoRoot, ...
        "data_4k/charp_plant.mat", 1/8000), ...
    "NikonMotor:PlantSamplePeriodMismatch");
end

function testExperimentScriptsUseTheSelectedPlant(testCase)
experimentFiles = [ ...
    "exp02_FB/feedback_experiment.m", ...
    "exp03_FF/feedforward_experiment.m", ...
    "exp04_ILC/ilc_experiment.m"];

for experimentFile = experimentFiles
    source = string(fileread(fullfile( ...
        testCase.TestData.repoRoot, experimentFile)));
    verifyTrue(testCase, contains(source, "load_experiment_plant"));
    verifyFalse(testCase, contains(source, "load(""data/plant.mat"")"));
end

chirpSource = string(fileread(fullfile(testCase.TestData.repoRoot, ...
    "exp01_SI", "chirpsine_closeloop.m")));
verifyTrue(testCase, contains(chirpSource, "save(plantDataFile"));
end

function testFeedbackControllerBuildsAtBothSampleRates(testCase)
frequencyHz = logspace(0, 3, 20);
for samplePeriod = [1/4000, 1/8000]
    measuredPlant = frd(ones(size(frequencyHz)), frequencyHz, ...
        "FrequencyUnit", "Hz");
    measuredPlant.Ts = samplePeriod;
    fb = fbDesign(measuredPlant, samplePeriod);
    verifyEqual(testCase, fb.K.Ts, samplePeriod, "AbsTol", eps(samplePeriod));
    verifyTrue(testCase, iscell(fb.sh));
end
end

function testTunableBuildGuardRejectsMissingAndMismatchedBuilds(testCase)
temporaryRoot = string(tempname);
mkdir(fullfile(temporaryRoot, "config", "data"));
cleanup = onCleanup(@()rmdir(temporaryRoot, "s"));

verifyError(testCase, ...
    @()assert_target_built(temporaryRoot, ...
        "tunable_build_info.mat", 1/4000), ...
    "NikonMotor:TargetRebuildRequired");

builtSamplePeriod = 1/8000;
save(fullfile(temporaryRoot, "config", "data", ...
    "tunable_build_info.mat"), "builtSamplePeriod");
verifyError(testCase, ...
    @()assert_target_built(temporaryRoot, ...
        "tunable_build_info.mat", 1/4000), ...
    "NikonMotor:TargetRebuildRequired");

builtSamplePeriod = 1/4000;
save(fullfile(temporaryRoot, "config", "data", ...
    "tunable_build_info.mat"), "builtSamplePeriod");
assert_target_built(temporaryRoot, "tunable_build_info.mat", 1/4000);
delete(cleanup);
end
