function [reducedModel,rxnwithcomplexchange] = removeGenesWithRatio(model,genesToRemove,removeUnusedMets,removeBlockedRxns,standardizeRules,ratio)
% removeGenes
%   Deletes a set of genes from a model
%
%   model                   a model structure
%   genesToRemove           either a cell array of gene IDs, a logical vector
%                           with the same number of elements as genes in the model,
%                           or a vector of indexes to remove
%   removeUnusedMets        remove metabolites that are no longer in use (opt, default
%                           false)
%   removeBlockedRxns       remove reactions that get blocked after deleting the genes
%                           (opt, default false)
%   standardizeRules        format gene rules to be compliant with standard format
%                           (opt, default true)
%
%   reducedModel            an updated model structure
%
%   Usage: reducedModel = removeGenes(model,genesToRemove,removeUnusedMets,removeBlockedRxns)
%
%   Benjam??n J. S??nchez, 2018-04-16
%   Feiran Li, updated for cobra format.
%

if nargin<3
    removeUnusedMets = false;
end

if nargin<4
    removeBlockedRxns = false;
end

if nargin<5
    standardizeRules = true;
end
rxnwithcomplexchange = [];
%Format grRules and rxnGeneMatrix:
if standardizeRules
    [grRules,rxnGeneMat] = standardizeGrRules(model,true);
    model.grRules = grRules;
    model.rxnGeneMat = rxnGeneMat;
end

reducedModel = model;

%Only remove genes that are actually in the model
try
    ischar(genesToRemove{1});
    genesToRemove=genesToRemove(ismember(genesToRemove,model.genes));
end

if ~isempty(genesToRemove)
    indexesToRemove = getIndexes(model,genesToRemove,'genes');
    if ~isempty(indexesToRemove)
        %Make 0 corresponding columns from rxnGeneMat:
        reducedModel.rxnGeneMat(:,indexesToRemove) = 0;
        
        genes        = model.genes(indexesToRemove);
        canCarryFlux = true(size(model.rxns));
        reducedModel.grRules = strrep(reducedModel.grRules,'(','( ');
        reducedModel.grRules = strrep(reducedModel.grRules,')',' )');
        %Loop through genes and adapt rxns:
        for i = 1:length(genes)
            %Find all reactions for this gene and loop through them:
            %isGeneInRxn =~cellfun(@isempty,strfind(reducedModel.grRules,genes{i}));%cause a problem when there is aaa@seq1 and aaa@seq12
            
            isGeneInRxn = cell2mat(cellfun(@(x) ismember(genes(i),split(x,' ')),reducedModel.grRules,'UniformOutput',false));
            for j = 1:length(reducedModel.grRules)
                if isGeneInRxn(j) && canCarryFlux(j)
                    grRule = reducedModel.grRules{j};
                    
                    %Check if rxn can carry flux without this gene:
                    canCarryFlux(j) = canRxnCarryFlux(reducedModel,grRule,genes{i});
                    
                    %Adapt gene rule & gene matrix:
                    grRule = removeGeneFromRule(grRule,genes{i});
                    reducedModel.grRules{j} = grRule;
                end
            end

        end
        
        %Delete or block the reactions that cannot carry flux:
        if removeBlockedRxns
            rxnsToRemove = reducedModel.rxns(~canCarryFlux);
            rxnsToRemoveIdx = find(~canCarryFlux);
            for i = 1:length(rxnsToRemove)
                [canit,geneRule] = uptatecomplex(model.grRules{rxnsToRemoveIdx(i)},genesToRemove,ratio);
                canitall(i) = canit;
                canCarryFlux(rxnsToRemoveIdx(i)) = canit;
                reducedModel.grRules{rxnsToRemoveIdx(i)} = geneRule;
            end
            rxnwithcomplexchange = [reducedModel.rxns(rxnsToRemoveIdx(canitall)),reducedModel.grRules(rxnsToRemoveIdx(canitall)),model.grRules(rxnsToRemoveIdx(canitall))];
            rxnsToRemove = reducedModel.rxns(~canCarryFlux); % update the new rxnsToRemove after curation
            reducedModel = removeReactions(reducedModel,rxnsToRemove,removeUnusedMets,true);
        else
            reducedModel = removeReactions(reducedModel,[],removeUnusedMets,true);
            reducedModel.lb(~canCarryFlux) = 0;
            reducedModel.ub(~canCarryFlux) = 0;
        end
    end
    if isfield(reducedModel,'rules')
        reducedModel.rules=grrulesToRules(reducedModel);
    end
end

end

function canIt = canRxnCarryFlux(model,geneRule,geneToRemove)
%This function converts a gene rule to a logical statement, and then
%asseses if the rule is true (i.e. rxn can still carry flux) or not (cannot
%carry flux).
geneRule = [' ', geneRule, ' '];
for i = 1:length(model.genes)
    if strcmp(model.genes{i},geneToRemove)
        geneRule = strrep(geneRule,[' ' model.genes{i} ' '],' false ');
        geneRule = strrep(geneRule,['(' model.genes{i} ' '],'(false ');
        geneRule = strrep(geneRule,[' ' model.genes{i} ')'],' false)');
    else
        geneRule = strrep(geneRule,[' ' model.genes{i} ' '],' true ');
        geneRule = strrep(geneRule,['(' model.genes{i} ' '],'(true ');
        geneRule = strrep(geneRule,[' ' model.genes{i} ')'],' true)');
    end
end
geneRule = strtrim(geneRule);
geneRule = strrep(geneRule,'and','&&');
geneRule = strrep(geneRule,'or','||');
canIt    = eval(geneRule);
end

function geneRule = removeGeneFromRule(geneRule,geneToRemove)
%This function receives a standard gene rule and it returns it without the
%chosen gene.
geneRule = strrep(geneRule,'(','( ');
geneRule = strrep(geneRule,')',' )');
geneSets = strsplit(geneRule,' or ');
hasGene = cell2mat(cellfun(@(x) ismember(geneToRemove,split(x,' ')),geneSets,'UniformOutput',false));
geneSets = geneSets(~hasGene);
geneRule = strjoin(geneSets,' or ');
if length(geneSets) == 1 && ~isempty(strfind(geneRule,'('))
    geneRule = geneRule(2:end-1);
end
end

function [canit,geneRule] = uptatecomplex(geneRule,genesToRemove,ratio)
geneSets = strsplit(geneRule,' or ');
geneSets = strrep(geneSets,'(','');
geneSets = strrep(geneSets,')','');
count_original = count(geneSets,' and ');
count_original = count_original + 1;
tmp = cellfun(@(x) ismember(genesToRemove,strtrim(split(x,' and '))),geneSets,'UniformOutput',false);
count_new = cellfun(@sum,tmp);
count_new = count_original - count_new; % calculate the left subunits
ratioall = count_new./count_original;
geneSetsToKeep = geneSets(ratioall > ratio);

if ~isempty(geneSetsToKeep)
    % remove genes from the geneSets and combine again
    for i = 1:length(geneSetsToKeep)
        tmp = split(geneSetsToKeep{i},' and ');
        tmp = strtrim(tmp);
        tmp = setdiff(tmp,genesToRemove);
        geneSetsToKeep(i) = join(tmp,' and ');
    end
    if length(geneSetsToKeep) > 1
        geneSetsToKeep = strcat('( ', geneSetsToKeep,' )');
        geneRule = cell2mat(join(geneSetsToKeep,' or '));
        canit = true;
    else
        geneRule = cell2mat(geneSetsToKeep);
        canit = true;
    end
else
    canit = false;
    geneRule = '';
end
end
function rules=grrulesToRules(model)
%This function just takes grRules, changes all gene names to
%'x(geneNumber)' and also changes 'or' and 'and' relations to corresponding
%symbols
replacingGenes=cell([size(model.genes,1) 1]);
for i=1:numel(replacingGenes)
    replacingGenes{i}=strcat('x(',num2str(i),')');
end
rules = strcat({' '},model.grRules,{' '});
for i=1:length(model.genes)
    rules=regexprep(rules,[' ' model.genes{i} ' '],[' ' replacingGenes{i} ' ']);
    rules=regexprep(rules,['(' model.genes{i} ' '],['(' replacingGenes{i} ' ']);
    rules=regexprep(rules,[' ' model.genes{i} ')'],[' ' replacingGenes{i} ')']);
end
rules=regexprep(rules,' and ',' & ');
rules=regexprep(rules,' or ',' | ');
rules=strtrim(rules);
end
