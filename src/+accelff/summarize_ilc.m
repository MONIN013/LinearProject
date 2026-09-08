function summary = summarize_ilc(sequences, targetRms)
%SUMMARIZE_ILC Compare ILC convergence from different initial feedforwards.
% sequences is a struct array with fields:
%   initializer : "zero" | "thesis" | "acceleration"
%   results     : cell array of accepted execute_case results for one profile
% This reports transfer/learning metrics only; it never changes the ILC law.

assert(isstruct(sequences) && ~isempty(sequences),'accelff:ILCSummaryEmpty', ...
    'Provide at least one ILC sequence.');
validateattributes(targetRms,{'double'},{'scalar','finite','positive'});
rows=table('Size',[0,8],'VariableTypes', ...
    {'string','string','double','double','double','double','double','double'}, ...
    'VariableNames',{'initializer','profile_id','iterations','initial_rms_m', ...
    'final_rms_m','normalized_auc','iterations_to_target','final_ff_peak_A'});
profile="";
for s=1:numel(sequences)
    init=string(sequences(s).initializer);
    assert(ismember(init,["zero","thesis","acceleration"]), ...
        'accelff:ILCInitializer','Unknown ILC initializer.');
    results=sequences(s).results;
    assert(iscell(results) && ~isempty(results),'accelff:ILCSummaryEmpty', ...
        'Every initializer needs at least one captured trial.');
    e=nan(numel(results),1);
    for k=1:numel(results)
        r=results{k};
        assert(isstruct(r) && string(r.status)=="accepted" && isfield(r,'trace'), ...
            'accelff:ILCSummaryRejected','Only accepted captures may enter convergence comparison.');
        tr=r.trace;
        moving=abs(tr.v_ref)>=r.config.evaluation_velocity_floor;
        assert(any(moving),'accelff:ILCSummaryStopped','No moving samples in ILC result.');
        e(k)=sqrt(mean(tr.error(moving).^2));
        if strlength(profile)==0
            profile=string(tr.profile_id);
        else
            assert(string(tr.profile_id)==profile,'accelff:ILCSummaryProfile', ...
                'Compare initializers on the same held-out profile only.');
        end
    end
    hit=find(e<=targetRms,1,'first');
    if isempty(hit), hit=NaN; end
    auc=sum(e)/max(e(1),eps);
    ffPeak=max(abs(results{end}.job.f));
    rows=[rows;{init,profile,numel(results),e(1),e(end),auc,hit,ffPeak}]; %#ok<AGROW>
end
assert(numel(unique(rows.initializer))==height(rows),'accelff:ILCDuplicateInitializer', ...
    'Each initializer must appear exactly once.');
summary=struct('profile_id',profile,'target_rms_m',targetRms,'table',rows, ...
    'interpretation', ...
    "Compare first-trial transfer, convergence area, iterations-to-target, and final error under one frozen ILC law.");
end
