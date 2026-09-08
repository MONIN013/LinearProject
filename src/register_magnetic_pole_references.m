function result = register_magnetic_pole_references(varargin)
%REGISTER_MAGNETIC_POLE_REFERENCES Register the authoritative axis records.
%
% Dry-run is the default. A real RETAIN write requires both DryRun=false and
% AllowRetainWrite=true. This maintenance operation never requests motion;
% AdsMotorRuntimePort rejects a normal Operation Enabled request, requires
% zero torque and commissioning 0/0, and requires the commutation override
% to be disabled immediately before each write.

repoRoot = copley_project_root();

opts = localParseInputs(repoRoot, varargin{:});
manifest = copley.infra.readJsonFile(opts.ManifestFile);
references = localValidateManifest(manifest);
motorPort = opts.MotorPort;

if isempty(motorPort)
    connection = localConnection(opts);
    connection.dryRun = logical(opts.DryRun);
    if ~connection.dryRun && ~logical(opts.AllowRetainWrite)
        error('register_magnetic_pole_references:RetainWriteNotAllowed', ...
            ['Refusing a real RETAIN write. Pass AllowRetainWrite=true ' ...
             'only after target activation and the registration preflight.']);
    end
    motorPort = copley.infra.AdsMotorRuntimePort( ...
        copley.infra.AdsClient(connection));
elseif ~isa(motorPort, 'copley.ports.MotorRuntimePort')
    error('register_magnetic_pole_references:InvalidMotorPort', ...
        'MotorPort must implement copley.ports.MotorRuntimePort.');
end

if isa(motorPort, 'copley.infra.AdsMotorRuntimePort')
    registered = motorPort.registerReferenceSet(references);
else
    registered = cell(1, numel(references));
    for i = 1:numel(references)
        registered{i} = motorPort.registerReference(references{i});
    end
end

result = struct();
result.schema_version = char(manifest.schema_version);
result.manifest_file = char(opts.ManifestFile);
result.dry_run = logical(opts.DryRun);
result.registered = registered;
result.counts_per_electrical_period = int32( ...
    manifest.counts_per_electrical_period);

if logical(opts.Verbose)
    for i = 1:numel(registered)
        reference = registered{i};
        fprintf(['Axis %u registered: position=%d, angle=%u, ' ...
            'direction=%d%s\n'], uint16(reference.axis_index), ...
            int32(reference.reference_position_count), ...
            uint16(reference.reference_commutation_angle), ...
            int16(reference.electrical_direction), ...
            localDryRunSuffix(result.dry_run));
    end
end
end

function opts = localParseInputs(repoRoot, varargin)
p = inputParser;
addParameter(p, 'ManifestFile', fullfile(repoRoot, 'config', 'copley', ...
    'magnetic_pole_references.json'));
addParameter(p, 'ConfigFile', '');
addParameter(p, 'Config', []);
addParameter(p, 'MotorPort', []);
addParameter(p, 'DryRun', true);
addParameter(p, 'AllowRetainWrite', false);
addParameter(p, 'Verbose', true);
parse(p, varargin{:});
opts = p.Results;
opts.ManifestFile = char(opts.ManifestFile);
opts.ConfigFile = char(opts.ConfigFile);
end

function references = localValidateManifest(manifest)
required = {'schema_version', 'counts_per_electrical_period', 'axes'};
for i = 1:numel(required)
    if ~isstruct(manifest) || ~isfield(manifest, required{i})
        error('register_magnetic_pole_references:InvalidManifest', ...
            'Manifest is missing %s.', required{i});
    end
end
if ~isfield(manifest, 'registration_enabled') ...
        || ~logical(manifest.registration_enabled)
    error('register_magnetic_pole_references:RegistrationDisabled', ...
        'This manifest is not approved for the active encoder profile.');
end
if double(manifest.counts_per_electrical_period) ~= 360000
    error('register_magnetic_pole_references:UnexpectedElectricalPeriod', ...
        'Manifest electrical period must match the PLC constant 360000.');
end
axes = manifest.axes;
if ~isstruct(axes) || ~ismember(numel(axes), [2 4])
    error('register_magnetic_pole_references:InvalidAxes', ...
        'Manifest must contain exactly axes 1-2 or axes 1-4.');
end

axisCount = numel(axes);
expectedAxes = 1:axisCount;
axisIndices = zeros(1, axisCount);
unorderedReferences = cell(1, axisCount);
seen = false(1, 4);
for i = 1:numel(axes)
    [~, unorderedReferences{i}] = ...
        copley.domain.toMotorRuntimeCalibrationPayload(axes(i));
    axisIndex = double(unorderedReferences{i}.axis_index);
    if seen(axisIndex)
        error('register_magnetic_pole_references:DuplicateAxis', ...
            'Manifest contains axis %u more than once.', axisIndex);
    end
    seen(axisIndex) = true;
    axisIndices(i) = axisIndex;
end
if ~isequal(sort(axisIndices), expectedAxes)
    error('register_magnetic_pole_references:MissingAxis', ...
        'Manifest must contain exactly axes 1-%u.', axisCount);
end
references = cell(1, axisCount);
references(axisIndices) = unorderedReferences;
end

function connection = localConnection(opts)
connection = opts.Config;
if isempty(connection) && ~isempty(opts.ConfigFile)
    connection = copley.infra.readJsonFile(opts.ConfigFile);
end
if isstruct(connection) && isfield(connection, 'connection')
    connection = connection.connection;
end
if isempty(connection)
    if ~logical(opts.DryRun)
        error('register_magnetic_pole_references:RealWriteNeedsConfig', ...
            'A real RETAIN write requires ConfigFile or Config.');
    end
    connection = struct();
end
if ~isstruct(connection) || ~isscalar(connection)
    error('register_magnetic_pole_references:InvalidConfig', ...
        'Config must be one connection struct or contain connection.');
end
if isfield(connection, 'motorAdsPort')
    connection.adsPort = connection.motorAdsPort;
elseif ~isfield(connection, 'adsPort')
    connection.adsPort = 852;
else
    % Registration always targets MotorRuntime, never ExperimentSequencer.
    connection.adsPort = 852;
end
end

function suffix = localDryRunSuffix(dryRun)
suffix = '';
if dryRun
    suffix = ' (dry-run)';
end
end
