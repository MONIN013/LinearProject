classdef FileRunStore < copley.ports.RunStore
    properties
        BaseDir
    end

    methods
        function obj = FileRunStore(baseDir)
            if nargin < 1 || isempty(baseDir)
                baseDir = fullfile('data', 'commissioning');
            end
            obj.BaseDir = baseDir;
        end

        function runDir = saveResult(obj, result)
            runDir = create_run_directory(obj.BaseDir, 'commissioning');
            save_experiment_result(runDir, 'commissioning_result', ...
                struct('result', result));

            summary = struct('schema_version', result.schema_version, ...
                'accepted', logical(result.accepted), ...
                'calibration_applied', logical(result.calibration_applied), ...
                'rejection_reason', result.rejection_reason);
            if isfield(result, 'calibration') && isstruct(result.calibration)
                summary.calibration = ...
                    copley.domain.normalizeCalibrationRecord( ...
                    result.calibration);
            end
            fid = fopen(fullfile(runDir, 'commissioning_result.json'), 'w');
            if fid < 0
                error('copley:FileRunStore:OpenFailed', 'Could not write result summary.');
            end
            cleanup = onCleanup(@()fclose(fid));
            fwrite(fid, jsonencode(summary), 'char');
            delete(cleanup);

            if isfield(result, 'protocol_results')
                copley.analysis.writeCommissioningArtifacts(result, runDir);
            end
        end
    end
end
