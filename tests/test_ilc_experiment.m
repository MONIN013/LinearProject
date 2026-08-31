function tests = test_ilc_experiment
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
repoRoot = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(repoRoot, "src"));
testCase.TestData.repoRoot = repoRoot;
end

function testExperimentUsesCurrentTunableAndMeasurementContracts(testCase)
source = fileread(fullfile(testCase.TestData.repoRoot, ...
    "exp04_ILC", "ilc_experiment.m"));
captureSource = fileread(fullfile(testCase.TestData.repoRoot, ...
    "exp04_ILC", "obtainMeasurement.m"));

verifySubstring(testCase, source, "%[text] # Demo 4");
verifySubstring(testCase, source, "%[appendix]{""version"":""1.0""}");
verifySubstring(testCase, source, ...
    "fullfile(projectRoot, ""exp03_FF"", ""setup_tunable.m"")");
verifySubstring(testCase, source, ...
    "fullfile(projectRoot, ""exp04_ILC"", ""obtainMeasurement.m"")");
verifySubstring(testCase, source, "open(ModelName)");
verifySubstring(testCase, captureSource, ...
    "history.e(:, iteration) = measurement(2, :).'");
verifySubstring(testCase, captureSource, ...
    "history.y(:, iteration) = measurement(5, :).'");
verifySubstring(testCase, captureSource, ...
    "history.y_absolute(:, iteration) = measurement(8, :).'");
verifySubstring(testCase, captureSource, ...
    "history.r(:, iteration) = measurement(9, :).'");
verifySubstring(testCase, captureSource, "max(0.9^iteration, 0.3)");
verifySubstring(testCase, source, "Fc = 420");
verifySubstring(testCase, source, "[Qsos, Qscale] = zp2sos(Qz, Qp, Qgain)");
verifySubstring(testCase, captureSource, "filtfilt_clean(Qsos, Qscale");
verifySubstring(testCase, captureSource, "max(abs(fNext)) > 2*MAX_INPUT");
verifySubstring(testCase, source, "confirmEachTrial = false");
verifySubstring(testCase, captureSource, "questdlg( ...");
verifySubstring(testCase, source, "pubfig(gcf)");

connectCall = "set_param(model, ""SimulationCommand"", ""connect"")";
disconnectCall = "set_param(model, ""SimulationCommand"", ""disconnect"")";
startCall = "set_param(model, ""SimulationCommand"", ""start"")";
verifyEqual(testCase, count(string(captureSource), connectCall), 1);
verifyEqual(testCase, count(string(captureSource), disconnectCall), 1);
verifyEqual(testCase, count(string(captureSource), startCall), 1);
verifyLessThan(testCase, strfind(captureSource, connectCall), ...
    strfind(captureSource, "for iteration = 1:Ntrial"));
verifyLessThan(testCase, strfind(captureSource, startCall), ...
    strfind(captureSource, "for iteration = 1:Ntrial"));
verifySubstring(testCase, captureSource, "cleanupGuard = onCleanup");
verifySubstring(testCase, captureSource, "[~, modelName] = fileparts(ModelName)");
verifySubstring(testCase, captureSource, "string(modelName)");
verifySubstring(testCase, captureSource, "wait_until_connected(model, 10)");
verifySubstring(testCase, captureSource, ...
    "setvars(model, struct(""p_active"", 0, ""p_servo"", 0))");
verifySubstring(testCase, captureSource, "servoSettlingTime = 3");
verifySubstring(testCase, captureSource, ...
    "set_param(model, ""SimulationCommand"", ""stop"")");
verifySubstring(testCase, captureSource, ...
    "wait_for_measurement_file(dataDir, 10)");
verifySubstring(testCase, captureSource, ...
    "if isempty(figureHandle) || ~isgraphics(figureHandle, ""figure"")");
verifySubstring(testCase, captureSource, """WindowStyle"", ""normal""");
end

function testNeoExperimentAutomatesVelocitySweep(testCase)
source = fileread(fullfile(testCase.TestData.repoRoot, ...
    "exp04_ILC", "ilc_experiment_neo.m"));
captureSource = fileread(fullfile(testCase.TestData.repoRoot, ...
    "exp04_ILC", "obtainMeasurement.m"));

verifySubstring(testCase, source, "%[text] # Demo 4 Neo");
verifySubstring(testCase, source, "%[appendix]{""version"":""1.0""}");
verifySubstring(testCase, source, "Ntrial = 10");
verifySubstring(testCase, source, "v_max_list = 0.1:0.1:1.5");
verifySubstring(testCase, source, "feedbackFlag = 1");
verifySubstring(testCase, source, "velocitySweepEnabled = true");
measurementRun = ...
    "fullfile(projectRoot, ""exp04_ILC"", ""obtainMeasurement.m"")";
verifyEqual(testCase, count(string(source), measurementRun), 1);
verifyLessThan(testCase, strfind(source, "feedbackFlag = 1"), ...
    strfind(source, ...
        "fullfile(projectRoot, ""exp03_FF"", ""setup_tunable.m"")"));
verifySubstring(testCase, captureSource, ...
    "for velocityIndex = 1:numel(vMaxList)");
verifySubstring(testCase, captureSource, "if completedTrials < Ntrial");
verifySubstring(testCase, captureSource, ...
    "sprintf(""ilc_result_V%.3f"", v_max)");
verifyFalse(testCase, contains(source, newline + "function "));

sweepStart = strfind(captureSource, "function sweep = run_ilc_velocity_sweep");
velocityLoop = strfind(captureSource, "for velocityIndex = 1:numel(vMaxList)");
connectionCalls = strfind(captureSource, "connect_external_mode(model);");
sweepConnection = connectionCalls( ...
    connectionCalls > sweepStart & connectionCalls < velocityLoop);
verifyNumElements(testCase, sweepConnection, 1);
cleanupCalls = strfind(captureSource, "cleanupGuard = onCleanup");
verifyEqual(testCase, ...
    sum(cleanupCalls > sweepStart & cleanupCalls < sweepConnection), 1);
end

function testFeedbackSimulationPreservesSignalShape(testCase)
Ts = 0.01;
signal = (1:20).';
time = (0:numel(signal)-1).'*Ts;
fb = struct( ...
    "PI", tf(2, 1, Ts), ...
    "zp", [0, 0, 1], ...
    "lead", tf(3, 1, Ts), ...
    "lp", [0, 0, 0]);

output = lsimFB(fb, signal, time);

verifyEqual(testCase, output, 6*signal, "AbsTol", 1e-12);
verifySize(testCase, output, size(signal));
end

function testSosQFilterMatchesDirectForm(testCase)
Ts = 1.25e-4;
[b, a] = butter(3, 400/(1/(2*Ts)));
[z, p, k] = butter(3, 400/(1/(2*Ts)));
[sos, scale] = zp2sos(z, p, k);
t = (0:Ts:1).';
signal = sin(2*pi*20*t) + 0.1*sin(2*pi*1000*t);

directOutput = filtfilt_clean(b, a, signal);
sosOutput = filtfilt_clean(sos, scale, signal);

verifyEqual(testCase, sosOutput, directOutput, "AbsTol", 1e-11);
end

function testInverseModelAppliesGainAndDelay(testCase)
Ts = 0.01;
signal = (1:20).';
model = struct( ...
    "Ts", Ts, ...
    "base", tf(2, 1, Ts), ...
    "lpf", tf(1, 1, Ts), ...
    "delay", 2);

output = lsimInvModel(model, signal);
expected = [signal(3:end)/2; 0; 0];

verifyEqual(testCase, output, expected, "AbsTol", 1e-10);
verifySize(testCase, output, size(signal));
end
