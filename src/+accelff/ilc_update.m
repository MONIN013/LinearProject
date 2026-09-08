function [fNext, info] = ilc_update(f, errorSignal, t, fb, Gn0, Ts, Fc, iteration, maxInput)
%ILC_UPDATE Reproduce the existing Demo 4 ILC update for one completed trial.
% Pure MATLAB calculation: no ADS, Simulink connection, servo command, or file I/O.
% The learning law intentionally matches exp04_ILC/obtainMeasurement.m:
%   f_{k+1}=Q^2{f_k + alpha_k[(C+Gn^{-1})e_k]}.
% Q is implemented by the same forward/backward SOS filtering used there.
% The result is NEVER clipped; an excessive candidate stops the sequence.

validateattributes(f,{'double'},{'column','real','finite'});
validateattributes(errorSignal,{'double'},{'column','real','finite','numel',numel(f)});
validateattributes(t,{'double'},{'column','real','finite','numel',numel(f)});
validateattributes(Ts,{'double'},{'scalar','real','finite','positive'});
validateattributes(Fc,{'double'},{'scalar','real','finite','positive','<',1/(2*Ts)});
validateattributes(iteration,{'double'},{'scalar','integer','positive'});
validateattributes(maxInput,{'double'},{'scalar','real','finite','positive'});
assert(numel(f)>round(0.05/Ts),'accelff:ILCTooShort', ...
    'The trajectory is too short for the existing 25 ms edge padding.');
assert(max(abs(diff(t)-Ts))<=1e-12,'accelff:ILCTime', ...
    'ILC time vector does not match Ts.');

[z,p,g]=butter(4,Fc/(1/(2*Ts)));
[Qsos,Qscale]=zp2sos(z,p,g);
alpha=max(0.9^iteration,0.3);
correction=lsimFB(fb,errorSignal,t)+lsimInvModel(Gn0,errorSignal);
candidate=filtfilt_clean(Qsos,Qscale,f+alpha*correction);

padding=round(0.025/Ts);
assert(numel(candidate)>2*padding,'accelff:ILCTooShort', ...
    'The ILC trajectory is too short for edge padding.');
candidate(1:padding)=candidate(padding+1);
candidate(end-padding+1:end)=candidate(end-padding);

peak=max(abs(candidate));
assert(peak<=2*maxInput,'accelff:ILCInputLimit', ...
    ['The next learned input exceeds 2*MAX_INPUT. Stop the ILC sequence; ' ...
     'do not clip the learned waveform or raise the machine limit.']);

fNext=candidate;
info=struct('iteration',iteration,'alpha',alpha,'Fc_Hz',Fc, ...
    'correction_norm',norm(correction,2),'previous_ff_norm',norm(f,2), ...
    'next_ff_norm',norm(fNext,2),'next_ff_peak_A',peak, ...
    'padding_samples',padding,'learning_law', ...
    "same_as_exp04_ILC_obtainMeasurement_2026-09-08");
end
