function tests = test_position_feedback_diagnostics
tests = functiontests(localfunctions);
end

function setupOnce(~)
repoRoot = fileparts(fileparts(mfilename("fullpath")));
addpath(fullfile(repoRoot, "src"));
end

function testLoaderAcceptsLegacySchemaV2(testCase)
[dataDir, cleanup] = localTempDirectory();
tc_yout = localTwinCATOutput(zeros(7, 4), 12, 0.000125);
save(fullfile(dataDir, "measurement_part2.mat"), "tc_yout");

[measurement, timeRaw, timeElapsed, matPath, metadata] = ...
    load_latest_twincat_measurement(dataDir, 0.000125);

verifySize(testCase, measurement, [7, 4]);
verifyEqual(testCase, metadata.schema_version, uint16(2));
verifyEqual(testCase, metadata.signal_count, uint16(7));
verifyEqual(testCase, metadata.signal_names(1:7), localSignalNames(7));
verifyEqual(testCase, timeRaw, 12 + (0:3) * 0.000125, ...
    "AbsTol", eps(12));
verifyEqual(testCase, timeElapsed, (0:3) * 0.000125, ...
    "AbsTol", eps(12));
verifyEqual(testCase, string(matPath), ...
    fullfile(dataDir, "measurement_part2.mat"));
delete(cleanup);
end

function testLoaderAcceptsDiagnosticSchemaV3AndNewestPart(testCase)
[dataDir, cleanup] = localTempDirectory();
tc_yout = localTwinCATOutput(ones(7, 3), 1, 0.001);
save(fullfile(dataDir, "measurement_part1.mat"), "tc_yout");
expected = reshape(1:(17 * 3), 17, 3);
tc_yout = localTwinCATOutput(expected, 2, 0.001);
save(fullfile(dataDir, "measurement_part11.mat"), "tc_yout");

[measurement, ~, ~, matPath, metadata] = ...
    load_latest_twincat_measurement(dataDir, 0.001);

verifyEqual(testCase, measurement, expected);
verifyEqual(testCase, metadata.schema_version, uint16(3));
verifyEqual(testCase, metadata.signal_count, uint16(17));
verifyEqual(testCase, metadata.signal_names, localSignalNames(17));
verifyEqual(testCase, string(matPath), ...
    fullfile(dataDir, "measurement_part11.mat"));
delete(cleanup);
end

function testLoaderRejectsUnsupportedWidth(testCase)
[dataDir, cleanup] = localTempDirectory();
tc_yout = localTwinCATOutput(zeros(8, 3), 0, 0.001);
save(fullfile(dataDir, "measurement_part1.mat"), "tc_yout");

verifyError(testCase, ...
    @()load_latest_twincat_measurement(dataDir, 0.001), ...
    "NikonMotor:UnsupportedMeasurementWidth");
delete(cleanup);
end

function testClassifiesVirtualCstFeedbackMappingStall(testCase)
measurement = localHeldMeasurement();
hold = localHoldIndices();
measurement(8, hold) = measurement(8, hold) + (0:(numel(hold) - 1));
report = localAnalyze(measurement);
localVerifyCause(testCase, report, ...
    "virtual_cst_feedback_mapping_stall");
end

function testClassifiesSharedEthercatInvalid(testCase)
measurement = localHeldMeasurement();
hold = localHoldIndices();
measurement(10, hold) = 1;
measurement(12, hold) = 1;
report = localAnalyze(measurement);
localVerifyCause(testCase, report, ...
    "shared_ethercat_process_data_invalid");
end

function testClassifiesPanasonicEthercatInvalid(testCase)
measurement = localHeldMeasurement();
measurement(10, localHoldIndices()) = 1;
report = localAnalyze(measurement);
localVerifyCause(testCase, report, ...
    "panasonic_ethercat_process_data_invalid");
end

function testClassifiesSharedValidTelegramStall(testCase)
measurement = localHeldMeasurement();
diagnosticWindow = localDiagnosticWindow();
measurement(11, diagnosticWindow) = 7;
measurement(13, diagnosticWindow) = 9;
report = localAnalyze(measurement);
localVerifyCause(testCase, report, ...
    "shared_valid_telegram_stall");
end

function testClassifiesPanasonicValidTelegramStall(testCase)
measurement = localHeldMeasurement();
diagnosticWindow = localDiagnosticWindow();
measurement(11, diagnosticWindow) = 7;
measurement(13, diagnosticWindow) = 0:(numel(diagnosticWindow) - 1);
report = localAnalyze(measurement);
localVerifyCause(testCase, report, ...
    "panasonic_valid_telegram_stall");
end

function testClassifiesDriveOrEncoderGenerationStall(testCase)
measurement = localHeldMeasurement();
report = localAnalyze(measurement);
localVerifyCause(testCase, report, ...
    "panasonic_drive_or_encoder_value_generation_stall");
end

function testClassifiesTaskExceedAndKeepsCorrelation(testCase)
measurement = localHeldMeasurement();
diagnosticWindow = localDiagnosticWindow();
measurement(10:13, diagnosticWindow) = nan;
measurement(16, localHoldIndices()) = 1;
measurement(17, :) = 40;
measurement(17, diagnosticWindow(10):end) = 41;
report = localAnalyze(measurement);

localVerifyCause(testCase, report, ...
    "motor_runtime_task_exceed_correlated");
verifyTrue(testCase, report.events.task_exceed_correlated(1));
verifyEqual(testCase, report.events.task_exceed_counter_delta(1), ...
    uint64(1));
verifyTrue(testCase, report.summary.task_exceed_correlated);
verifyEqual(testCase, ...
    report.summary.task_exceed_correlated_event_count, uint32(1));
end

function testStrongCauseWinsButTaskCorrelationRemains(testCase)
measurement = localHeldMeasurement();
hold = localHoldIndices();
measurement(10, hold) = 1;
measurement(12, hold) = 1;
measurement(17, :) = 4;
measurement(17, hold(20):end) = 5;
report = localAnalyze(measurement);

localVerifyCause(testCase, report, ...
    "shared_ethercat_process_data_invalid");
verifyTrue(testCase, report.events.task_exceed_correlated(1));
verifyEqual(testCase, report.events.task_exceed_counter_delta(1), ...
    uint64(1));
end

function testInvalidTaskCounterSentinelIsNotAnIncrement(testCase)
measurement = localHeldMeasurement();
diagnosticWindow = localDiagnosticWindow();
measurement(10:13, diagnosticWindow) = nan;
measurement(17, diagnosticWindow) = double(intmax("uint32"));
report = localAnalyze(measurement);

localVerifyCause(testCase, report, "unknown");
verifyFalse(testCase, report.events.task_exceed_correlated(1));
verifyEqual(testCase, report.events.task_exceed_counter_delta(1), ...
    uint64(0));
verifyGreaterThan(testCase, ...
    report.summary.task_exceed_counter_invalid_sample_count, uint32(0));
end

function testAnalyzesSavedMatStructWithSignalNamesAndTime(testCase)
[dataDir, cleanup] = localTempDirectory();
measurement = localHeldMeasurement();
signal_names = localSignalNames(17);
time = (0:(size(measurement, 2) - 1)) * 0.001 + 100;
matPath = fullfile(dataDir, "saved_result.mat");
save(matPath, "measurement", "signal_names", "time");

report = analyze_position_feedback_health(matPath, ...
    "SamplePeriod", 0.001, "MinimumHold_s", 0.05);

localVerifyCause(testCase, report, ...
    "panasonic_drive_or_encoder_value_generation_stall");
verifyEqual(testCase, report.schema_version, uint16(3));
verifyEqual(testCase, report.events.start_time_s(1), 0.099, ...
    "AbsTol", 1e-12);
delete(cleanup);
end

function report = localAnalyze(measurement)
input = struct();
input.measurement = measurement;
input.signal_names = localSignalNames(size(measurement, 1));
input.time = (0:(size(measurement, 2) - 1)) * 0.001;
report = analyze_position_feedback_health(input, ...
    "SamplePeriod", 0.001, "MinimumHold_s", 0.05);
end

function measurement = localHeldMeasurement()
sampleCount = 300;
measurement = zeros(17, sampleCount);
measurement(1, :) = 0:(sampleCount - 1);
measurement(3, :) = linspace(0, 0.03, sampleCount);
measurement(4, :) = 0.5;
measurement(5, :) = linspace(0, 0.03, sampleCount);
measurement(6, :) = 0.01;
measurement(8, :) = round(measurement(5, :) / 1e-7);
measurement(9, :) = round(measurement(6, :) / 1e-7);
measurement(10, :) = 0;
measurement(11, :) = mod(0:(sampleCount - 1), 2);
measurement(12, :) = 0;
measurement(13, :) = mod(0:(sampleCount - 1), 2);
measurement(14, :) = hex2dec("0027");
measurement(15, :) = 0;
measurement(16, :) = 0;
measurement(17, :) = 0;

hold = localHoldIndices();
measurement(5, hold) = measurement(5, hold(1) - 1);
measurement(6, hold) = 0;
measurement(8, hold) = measurement(8, hold(1) - 1);
measurement(9, hold) = 0;
end

function hold = localHoldIndices()
hold = 101:220;
end

function indices = localDiagnosticWindow()
hold = localHoldIndices();
indices = (hold(1) - 1):hold(end);
end

function names = localSignalNames(width)
legacy = [ ...
    "count", "tracking_error_m", "reference_m", "control_current_A", ...
    "position_m", "velocity_m_per_s", "torque_actual_A"];
diagnostic = [ ...
    "panasonic_position_raw_count", ...
    "panasonic_velocity_raw_count", ...
    "panasonic_wcstate", ...
    "panasonic_input_toggle", ...
    "copley_wcstate", ...
    "copley_input_toggle", ...
    "panasonic_statusword", ...
    "panasonic_error_code", ...
    "task_cycle_time_exceeded", ...
    "task_exceed_counter"];
if width == 7
    names = legacy;
else
    names = [legacy, diagnostic];
end
end

function tc_yout = localTwinCATOutput(data, startTime, samplePeriod)
sampleCount = size(data, 2);
tc_yout = repmat(struct("time", 0, ...
    "data", zeros(size(data, 1), 1)), 1, sampleCount);
for i = 1:sampleCount
    tc_yout(i).time = startTime + (i - 1) * samplePeriod;
    tc_yout(i).data = data(:, i);
end
end

function localVerifyCause(testCase, report, expected)
verifyTrue(testCase, report.feedback_path_stale);
verifyEqual(testCase, report.event_count, uint32(1));
verifyGreaterThan(testCase, report.longest_hold_s, 0.05);
verifyEqual(testCase, report.primary_cause, expected);
verifyEqual(testCase, report.events.cause(1), expected);
end

function [directory, cleanup] = localTempDirectory()
directory = string(tempname);
mkdir(directory);
cleanup = onCleanup(@()rmdir(directory, "s"));
end
