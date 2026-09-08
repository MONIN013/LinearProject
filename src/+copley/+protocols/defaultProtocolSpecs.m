function specs = defaultProtocolSpecs()
%DEFAULTPROTOCOLSPECS Protocol definitions for magnetic pole identification.
specs = [
    copley.domain.ProtocolSpec(1, 'differential_sweep', ...
        @copley.analysis.analyzeDifferentialSweep, @localQuality)
    copley.domain.ProtocolSpec(2, 'shifted_axis_current_equality', ...
        @copley.analysis.analyzeIppCurrentRatio, @localQuality)
    copley.domain.ProtocolSpec(3, 'q_axis_verification', ...
        @copley.analysis.analyzeQAxisVerification, @localQuality)
    ];
end

function quality = localQuality(result)
quality = struct();
quality.accepted = false;
quality.reason = 'analysis did not return an acceptance decision';
if isstruct(result) && isfield(result, 'quality') && isstruct(result.quality)
    quality = result.quality;
elseif isstruct(result) && isfield(result, 'accepted')
    quality.accepted = logical(result.accepted);
    if isfield(result, 'reason')
        quality.reason = result.reason;
    end
end
end
