function paths = save_experiment_figures(runDir, figures)
%SAVE_EXPERIMENT_FIGURES Export only the figure handles supplied by the experiment.
figures = figures(isgraphics(figures,'figure'));
paths = strings(numel(figures),1);
if isempty(figures), return; end
if ~isfolder(runDir), mkdir(runDir); end
for k = 1:numel(figures)
    paths(k) = string(fullfile(runDir,sprintf('figure_%d.png',figures(k).Number)));
    exportgraphics(figures(k),paths(k));
end
end
