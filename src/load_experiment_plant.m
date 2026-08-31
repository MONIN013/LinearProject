function [plant, plantPath] = load_experiment_plant( ...
        projectRoot, plantDataFile, samplePeriod)
%LOAD_EXPERIMENT_PLANT Load plant data and reject sample-period mismatches.

validateattributes(samplePeriod, {'numeric'}, ...
    {'real', 'finite', 'scalar', 'positive'}, mfilename, 'samplePeriod');
plantPath = string(fullfile(projectRoot, plantDataFile));
if ~isfile(plantPath)
    error("NikonMotor:PlantDataNotFound", ...
        "Plant data for %.0f Hz was not found: %s", ...
        1/samplePeriod, plantPath);
end

plant = load(plantPath);
requiredFields = ["Pd", "Jn", "Dn", "Ndelay", "Ts"];
missingFields = requiredFields(~isfield(plant, requiredFields));
if ~isempty(missingFields)
    error("NikonMotor:IncompletePlantData", ...
        "Plant data is missing fields (%s): %s", ...
        strjoin(missingFields, ", "), plantPath);
end

plantPeriods = [double(plant.Ts), double(plant.Pd.Ts)];
if isfield(plant, "Pdn")
    plantPeriods(end+1) = double(plant.Pdn.Ts);
end
tolerance = max(1e-12, 1e-9*samplePeriod);
if any(~isfinite(plantPeriods)) || ...
        any(abs(plantPeriods - samplePeriod) > tolerance)
    error("NikonMotor:PlantSamplePeriodMismatch", ...
        "Configured Ts is %.9g s, but %s contains sample periods %s s. " + ...
        "Select matching plant data before building or operating the stage.", ...
        samplePeriod, plantPath, mat2str(plantPeriods, 9));
end
end
