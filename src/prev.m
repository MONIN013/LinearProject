function signal_prev = prev(signal,Nsample)
n = length(signal);
signal = reshape(signal,n,[]);
nstart = max(1,1+Nsample);
nend = min(n,n+Nsample);
signal_prev = [repmat(signal(1,:),-Nsample,1);signal(nstart:nend,:);repmat(signal(end,:),Nsample,1)];
end