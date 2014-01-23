classdef(ConstructOnLoad) ConditionDescriptor 
% ConditionDescriptor is a static representation of a A-dimensional combinatorial
% list of attribute values

    % the following properties are computed dynamically on the fly as they
    % are easy to compute
    properties(Dependent, Transient)
        nAttributes % how many attributes: ndims(values)
        nValuesByAttribute % how many values per attribute: size(values)
        
        nAxes % how many dimensions of grouping axe
        nValuesAlongAxes % X x 1 array of number of elements along the axis
        
        nConditions % how many total conditions
        conditionsSize 
        
        allAxisValueListsManual
        allAttributeValueListsManual
        allValueListsManual % true if all attribute lists and axis lists are manually (not automatically determined)
    end
        
    % the following properties are computed dynamically on the fly as they
    % are easy to compute
    properties(Dependent, Transient)
        attributeDescriptions
        attributeAlongWhichAxis % A x 1 array indicating which axis an attribute contributes to (or NaN)
        attributeValueModes % A x 1 array of AttributeValue* constants above
        attributeActsAsFilter % A x 1 logical array : does this attribute have a
                % value list or manual bin setup that would invalidate trials?
        
        axisNames % strcell with a short name for each axis
        axisDescriptions % strcell describing each axis

        axisValueListModesAsStrings
        axisRandomizeModesAsStrings
        
        conditionsAsLinearInds % linear index corresponding to each condition if flattened 
    end

    properties
        description = '';
        
        % updates cache on set
        nameFn % function which maps .values(i) struct --> name of condition i
        
        % updates cache on set
        appearanceFn; % function which takes struct('attrName1', attrVal1, 'attrName2', attrVal2)
                      % and returns struct('color', 'k', 'lineWidth', 2, ...);      
    end
     
    properties(SetAccess=protected)
        % A x 1 : by attribute                       
        attributeNames = {}; % A x 1 cell array : list of attributes for each dimension
        attributeRequestAs = {}; % A x 1 cell array : list of names by which each attribute should be requested corresponding to attributeNames
        
        axisAttributes % G x 1 cell : each is cellstr of attributes utilized along that grouping axis
    end
    
    properties(SetAccess=protected, Hidden)
        attributeNumeric = []; % A x 1 logical array : is this attribute a numeric value? 
        attributeValueListsManual = {}; % A x 1 cell array of permitted values (or cells of values) for this attribute
        attributeValueBinsManual = {}; % A x 1 cell array of value Nbins x 2 value bins to use for numeric lists
        attributeValueBinsAutoCount % A x 1 numeric array of Nbins to use when auto computing the bins, NaN if not in use
        attributeValueBinsAutoModes % A x 1 numeric array of either AttributeValueBinsAutoUniform or AttributeValueBinsAutoQuantiles
        
        axisValueListsManual % G x 1 cell of cells: each contains a struct specifying an attribute specification for each element along the axis
        axisValueListsOccupiedOnly % G x 1 logical indicating whether to constrain the combinatorial valueList to only occupied elements (with > 0 trials)

        axisRandomizeModes % G x 1 numeric of constants beginning with Axis* (see below)
        axisRandomizeWithReplacement % G x 1 logical indicating whether ot not to use replacement
        axisRandomizeResampleFromList % G x 1 cell of cells: each specifies which axis value bin to resample from, 
            % i.e. {2 1} would be sampling from trials with value 2 to fill bin 1, and from trials with value 1 to fill bin 2, like a swap
            % {1 2 3} would be the equivalent of AxisResampleFromSame
            
        isResampledWithinConditions = false; % boolean flag indicating whether to resampleFromSame the listByCondition
                      % after building it, which resamples with replacement
                      % without changing condition labels.

        randomSeed = 0;
        
        % scalar numeric seed initializing the RandStream which will generate shuffling or resampling along each axis
        % the persistence of this seed ensures that the randomization can reliably be repeated, but the results may change if anything
        % about any of the attributes / axes is changed.
    end
    
    % END OF STORED TO DISK PROPERTIES
    
    properties(Hidden, Transient, Access=protected)
        odc % handle to a ConditionDescriptorOnDemandCache
    end
    
    % THE FOLLOWING PROPERTIES WRAP EQUIVALENT PROPERTIES IN ODC
    % on get: retrieve from odc, if empty {call build<Property>, store in odc, return it}
    % on set: make copy of odc to alleviate dependency, store in odc
    % 
    % Note: we use the build<Property> methods because property getters
    % cannot be inherited, so subclasses can override the build method
    % instead.
    properties(Transient, Dependent, SetAccess=protected)        
        % These are generated on the fly by property get, but cached for speed, see invalidateCache to reset them 
        
        % these are X-dimensional objects where X is nAxes
        conditions % X-dimensional struct where values(...idx...).attribute is the value of that attribute on that condition
        conditionsAsStrings % includes attribute values as strings rather than numeric 
        conditionsAxisAttributesOnly % includes only the attributes actively selected for
        
        appearances % A-dimensional struct of appearance values
        names % A-dimensional cellstr array with names of each condition 
        attributeValueLists % A x 1 cell array of values allowed for this attribute
                           % here just computed from attributeValueListManual, but in ConditionInfo
                           % can be automatically computed from the data
        attributeValueListsAsStrings % same as above, but everything is a string
        
        axisValueLists % G dimensional cell array of structs which select attribute values for that position along an axis
        axisValueListsAsStrings
        axisValueListModes % G dimensional array of AxisValueList* constants below indicating how axis value lists are generated
    end
    
    % how are attribute values determined for a given attribute?
    properties(Constant, Hidden)
        % for attributeValueListModes
        AttributeValueListManual = 1;
        AttributeValueListAuto = 2;
        AttributeValueBinsManual = 3;
        AttributeValueBinsAutoUniform = 4;
        AttributeValueBinsAutoQuantiles = 5;
        
        % for axisRandomizeModes
        AxisOriginal = 1; % use original axis ordering
        AxisShuffled = 2; % shuffle the labels along this axis preserving the original counts within each bin
        AxisResampledFromSpecified = 3; % resample with replacement from a different bin (see axisRandomizeResampleFromList)
        
        % for axisValueListModes
        AxisValueListAutoAll = 1;
        AxisValueListAutoOccupied = 2;
        AxisValueListManual = 3;
    end
    
    % Constructor, load, save methods
    methods
        function ci = ConditionDescriptor()
            ci.odc = ci.buildOdc();
        end
        
        function odc = buildOdc(varargin)
            odc = ConditionDescriptorOnDemandCache();
        end
    end

    methods % General methods, setters and getters
        
        % flush the contents of odc as they are invalid
        % call this at the end of any methods which would want to
        % regenerate these values
        function ci = invalidateCache(ci)
            ci.warnIfNoArgOut(nargout);

            % here we precompute these things to save time, 
            % but each of these things also has a get method that will
            % recompute this for us
            ci.odc  = ci.odc.copy();
            ci.odc.flush();
        end

        function ci = set.nameFn(ci, fn)
            ci.nameFn = fn;
            ci = ci.invalidateCache();
        end

        function ci = set.appearanceFn(ci, fn)
            ci.appearanceFn = fn;
            ci = ci.invalidateCache();
        end
        
        function printDescription(ci) 
            tcprintf('yellow', '%s:\n', class(ci));
            tcprintf('inline', '\t{bright blue}Attributes: {white}%s\n', strjoin(ci.attributeDescriptions));
            tcprintf('inline', '\t{bright blue}Axes: {white}%s\n', strjoin(ci.axisDescriptions, ', '));
            
            nRandom = nnz(ci.axisRandomizeModes ~= ci.AxisOriginal);
            if nRandom > 0
                if nRandom == 1
                    s = 'axis';
                else
                    s = 'axes';
                end
                tcprintf('inline', '\t{bright red}%d %s with randomization applied\n', nRandom, s);
            end
            
            if ci.isResampledWithinConditions
                tcprintf('inline', '\t{bright red}Trials resampled within conditions\n');
            end
        end
        
        function printOneLineDescription(ci)           
            if ci.nAxes == 0
                axisStr = 'no grouping axes';
            else
                axisStr = strjoin(ci.axisDescriptions, ' , ');
            end
            
            attrFilter = ci.attributeNames(ci.attributeActsAsFilter);
            if isempty(attrFilter)
                filterStr = 'no filtering';
            else
                filterStr = sprintf('filtering by %s', strjoin(attrFilter));
            end
            
            tcprintf('inline', '{yellow}%s: {none}%s, %s\n', ...
                class(ci), axisStr, filterStr);
        end

        function disp(ci)
            ci.printDescription();
            fprintf('\n');
            builtin('disp', ci);
        end
        
        function tf = get.allAxisValueListsManual(ci)
            % returns true if all axis value
            % lists are manually specified, false otherwise if anything is
            % automatically determined
            
            tf = all(ci.axisValueListModes == ci.AxisValueListManual);
        end
        
        function tf = get.allAttributeValueListsManual(ci)
            % returns true if all attribute value lists 
            % are manually specified, false otherwise if anything is
            % automatically determined
            
            tf = all(ismember(ci.attributeValueModes, [ci.AttributeValueListManual, ci.AttributeValueBinsManual]));
        end
        
        function tf = get.allValueListsManual(ci)
            % returns true if all attribute value lists and axis value
            % lists are manually specified, false otherwise if anything is
            % automatically determined
            tf = ci.allAxisValueListsManual && ci.allAttributeValueListsManual;
        end
    end

    methods % Axis related 
        function n = get.nAxes(ci)
            n = numel(ci.axisAttributes);
        end
        
        function a = get.attributeAlongWhichAxis(ci)
            a = nanvec(ci.nAttributes);
            for iX = 1:ci.nAxes
                a(ci.getAttributeIdx(ci.axisAttributes{iX})) = iX;
            end
        end
        
        function modes = get.axisValueListModes(ci)
            modes = nanvec(ci.nAxes);
            
            for iX = 1:ci.nAxes
                if ~isempty(ci.axisValueListsManual{iX})
                    modes(iX) = ci.AxisValueListManual;
                elseif ci.axisValueListsOccupiedOnly(iX)
                    modes(iX) = ci.AxisValueListAutoOccupied;
                else
                    modes(iX) = ci.AxisValueListAutoAll;
                end
            end
        end
        
        % determine whether each attribute acts to filter valid trials
        function tf = get.attributeActsAsFilter(ci)
            modes = ci.attributeValueModes;
            tf = ismember(modes, [ci.AttributeValueListManual, ci.AttributeValueBinsManual]);
        end
        
        function names = get.axisNames(ci)
            names = cellvec(ci.nAxes);            
            for iX = 1:ci.nAxes
                attr = ci.axisAttributes{iX};
                names{iX} = strjoin(attr, ' x ');
            end
        end
        
        function desc = get.axisDescriptions(ci)
            desc = cellvec(ci.nAxes);
            
            vlStrCell = ci.axisValueListModesAsStrings;
            randStrCell = ci.axisRandomizeModesAsStrings;
            for iX = 1:ci.nAxes
                attr = ci.axisAttributes{iX};
                nv = ci.conditionsSize(iX);
                vlStr = vlStrCell{iX};
                randStr = randStrCell{iX}; 
                if ~isempty(vlStr)
                    vlStr = [' ' vlStr]; %#ok<AGROW>
                end
                if ~isempty(randStr)
                    randStr = [' ' randStr]; %#ok<AGROW>
                end
                desc{iX} = sprintf('%s (%d%s%s)', ...
                    strjoin(attr, ' x '), nv, vlStr, randStr);
            end
        end
        
        function strCell = get.axisValueListModesAsStrings(ci)
            strCell = cellvec(ci.nAxes);
            for iX = 1:ci.nAxes
                switch ci.axisValueListModes(iX)
                    case ci.AxisValueListAutoAll
                        vlStr = 'auto';
                    case ci.AxisValueListAutoOccupied
                        vlStr = 'autoOccupied';
                    case ci.AxisValueListManual
                        vlStr = 'manual';
                    otherwise
                        error('Unknown axisValueListMode for axis %d', iX);
                end
                strCell{iX} = vlStr;
            end
        end

        function strCell = get.axisRandomizeModesAsStrings(ci)
            strCell = cellvec(ci.nAxes);
            for iX = 1:ci.nAxes
                if ci.axisRandomizeWithReplacement(iX)
                    replaceStr = 'WithReplacement';
                else
                    replaceStr = '';
                end
                switch ci.axisRandomizeModes(iX)
                    case ci.AxisOriginal
                        randStr = '';
                    case ci.AxisShuffled
                        randStr = ['shuffled' replaceStr];
                    case ci.AxisResampledFromSpecified
                        randStr = ['resampled' replaceStr];
                    otherwise
                        error('Unknown axisRandomizeMode for axis %d', iX);
                end
                strCell{iX} = randStr;
            end
        end

        function ci = addAxis(ci, varargin)
            ci.warnIfNoArgOut(nargout);

            p = inputParser;
            p.addOptional('attributes', {}, @(x) ischar(x) || iscellstr(x));
            p.addParamValue('name', '', @ischar);
            p.addParamValue('valueList', {}, @(x) true);
            p.parse(varargin{:});

            if ~iscell(p.Results.attributes)
                attr = {p.Results.attributes};
            else
                attr = p.Results.attributes;
            end
            ci.assertHasAttribute(attr);
            
            ci = ci.removeAttributesFromAxes(attr);

            % create a grouping axis
            idx = ci.nAxes + 1; 
            ci.axisAttributes{idx} = attr;
            ci.axisValueListsManual{idx} = p.Results.valueList;
            ci.axisRandomizeModes(idx) = ci.AxisOriginal;
            ci.axisRandomizeWithReplacement(idx) = false;
            ci.axisRandomizeResampleFromList{idx} = [];
            
            ci.axisValueListsOccupiedOnly(idx) = false;

            ci = ci.invalidateCache();
        end
        
        function ci = maskAxes(ci, mask)
            ci.warnIfNoArgOut(nargout);
            
            ci.axisAttributes = ci.axisAttributes(mask);
            ci.axisValueListsManual = ci.axisValueListsManual(mask);
            ci.axisRandomizeModes = ci.axisRandomizeModes(mask);
            ci.axisRandomizeWithReplacement = ci.axisRandomizeWithReplacement(mask);
            ci.axisRandomizeResampleFromList = ci.axisRandomizeResampleFromList(mask);
            ci.axisValueListsOccupiedOnly = ci.axisValueListsOccupiedOnly(mask);
            
            ci = ci.invalidateCache();
        end

        % wipe out existing axes and creates simple auto axes along each 
        function ci = groupBy(ci, varargin)
            ci.warnIfNoArgOut(nargout);
            ci = ci.clearAxes();
            
            for i = 1:numel(varargin)
                ci = ci.addAxis(varargin{i});
            end
        end

        function ci = groupByAll(ci)
            ci.warnIfNoArgOut(nargout);
            ci = ci.groupBy(ci.attributeNames{:});
        end

        % remove all axes
        function ci = clearAxes(ci)
            ci.warnIfNoArgOut(nargout);

            ci = ci.maskAxes([]);

            ci = ci.invalidateCache();
        end
        
        function ci = removeAttributesFromAxes(ci, namesOrIdx)
            ci.warnIfNoArgOut(nargout);
            attrIdx = ci.getAttributeIdx(namesOrIdx);
            attrNames = ci.attributeNames(attrIdx);
            
            if ci.nAxes == 0
                return;
            end
            
            whichAxis = ci.attributeAlongWhichAxis;
            removeAxisMask = falsevec(ci.nAxes);
            for iAI = 1:numel(attrIdx)
                iA = attrIdx(iAI);
                iX = whichAxis(iA);
                if isnan(iX)
                    continue;
                end
                
                % remove this attribute from axis iX
                if ci.axisRandomizeModes(iX) ~= ci.AxisOriginal
                    error('Cowardly refusing to remove attributes from axis with randomization applied');
                end
                if ci.axisValueListModes(iX) == ci.AxisValueListManual
                    error('Cowardly refusing to remove attributes from axis with manual value list specified');
                end
                
                maskInAxis = strcmp(ci.axisAttributes{iX}, attrNames{iAI});
                if all(maskInAxis)
                    removeAxisMask(iX) = true;
                else
                    ci.axisAttributes{iX} = ci.axisAttributes{iX}(~maskInAxis);
                    % clear out manual value list as it's likely invalid now
                    ci.axisValueListsManual{iX} = [];
                    % and reset the randomization
                    ci.axisRandomizeModes(iX) = ci.AxisOriginal;
                end
            end
            
            ci = ci.maskAxes(~removeAxisMask);
        end
        
        function ci = setAxisValueList(ci, axisSpec, valueList)
            ci.warnIfNoArgOut(nargout);
            idx = ci.axisLookupByAttributes(axisSpec);
            
            assert(isstruct(valueList) && isvector(valueList), ....
                'Value list must be a struct vector');
            assert(isempty(setxor(fieldnames(valueList), ci.axisAttributes{idx})), ...
                'Value list fields must match axis attributes');
            ci.axisValueListsManual{idx} = valueList;
            
            ci = ci.invalidateCache();
        end
        
        function nv = get.conditionsSize(ci)
            nv = TensorUtils.expandSizeToNDims(size(ci.conditions), ci.nAxes);
        end

        function linearInds = get.conditionsAsLinearInds(ci)
            linearInds = TensorUtils.containingLinearInds(ci.conditionsSize);
        end

        function n = get.nConditions(ci)
            n = prod(ci.conditionsSize);
        end

        % lookup axis idx by attribute char or cellstr, or cell of attribute cellstr
        % if a numeric indices are passed in, returns them through.
        % if not found, throws an error
        % useful for accepting either axis idx or attributes in methods
        function idx = axisLookupByAttributes(ci, attr)
            if isnumeric(attr)
                assert(all(attr >= 1 & attr <= ci.nAxes), 'Axis index out of range');
                idx = attr;
                return;
            end

            if ischar(attr)
                attr = {attr};
            end
            if iscellstr(attr)
                attr = {attr};
            end
            
            % attr is a cell of cellstr of attributes, and axisAttributes is a cell
            % of such cellstr (the attributes along each axis).
            % Consequently, we're looking for an EXACT match between attr
            % and an axis
            idx = nanvec(numel(attr));
            for iAttr = 1:numel(attr)
                for i = 1:ci.nAxes
                    if isempty(setxor(attr{iAttr}, ci.axisAttributes{i}))
                        idx(iAttr) = i;
                        break;
                    end
                end
                
                assert(~isnan(idx(iAttr)), 'Axis with attributes %s not found', ...
                    strjoin(attr{iAttr}, ' x '));
            end
            
        end
    end

    methods % Axis randomization related
        function ci = setRandomSeed(ci, seed)
            ci.warnIfNoArgOut(nargout);
            ci.randomSeed = seed; 
        end
        
        function ci = newRandomSeed(ci)
            ci.warnIfNoArgOut(nargout);
            ci = ci.setRandomSeed(RandStream.shuffleSeed());
        end
        
        function ci = newRandomSeedIfEmpty(ci)
            ci.warnIfNoArgOut(nargout);
            if isempty(ci.randomSeed)
                warning('Automatically selecting random seed. Call .setRandomSeed(seed) for deterministic resuls');
                ci = ci.newRandomSeed();
            end
        end
        
        function seedRandStream(ci, seed)
            if nargin < 2
                seed = ci.randomSeed;
            end
                
            s = RandStream('mt19937ar', 'Seed', seed);
            RandStream.setGlobalStream(s);
        end
        
        function ci = noRandomization(ci)
            ci.warnIfNoArgOut(nargout);
            ci.isResampledWithinConditions = false;
            for i = 1:ci.nAxes
                ci = ci.axisNoRandomization(i);
            end
        end  
        
        function ci = resampleTrialsWithinConditions(ci)
            ci.warnIfNoArgOut(nargout);
            ci = ci.newRandomSeedIfEmpty();
            ci.isResampledWithinConditions = true;
            ci = ci.invalidateCache();
        end
        
        function ci = axisNoRandomization(ci, idxOrAttr)
            ci.warnIfNoArgOut(nargout);
            idx = ci.axisLookupByAttributes(idxOrAttr);
            ci.axisRandomizeModes(idx) = ci.AxisOriginal;
            ci.axisRandomizeResampleFromList{idx} = [];
            ci.axisRandomizeWithReplacement(idx) = false;
            ci = ci.invalidateCache();
        end
                   
        function ci = axisShuffle(ci, idxOrAttr, replace) 
            ci.warnIfNoArgOut(nargout);
            if nargin < 3
                replace = false;
            end
            
            ci = ci.newRandomSeedIfEmpty();
            idx = ci.axisLookupByAttributes(idxOrAttr);
            ci.axisRandomizeModes(idx) = ci.AxisShuffled;
            ci.axisRandomizeResampleFromList{idx} = [];
            ci.axisRandomizeWithReplacement(idx) = replace;
            ci = ci.invalidateCache();
        end

        function ci = axisResampleFromSpecified(ci, axisIdxOrAttr, resampleFromList, replace) 
            ci.warnIfNoArgOut(nargout);
            if nargin < 4
                replace = false;
            end
            ci = ci.newRandomSeedIfEmpty();
            idx = ci.axisLookupByAttributes(axisIdxOrAttr);
            assert(isscalar(idx), 'Method operates on only one axis');

            nValues = ci.nValuesAlongAxes(idx);
            if isscalar(resampleFromList)
                % all resampling from same, clone to length of axis
                resampleFromList = repmat(resampleFromList, nValues, 1);
            end
            if isvector (resampleFromList)
                % convert to cell array
                resampleFromList = num2cell(resampleFromList);
            end

            assert(numel(resampleFromList) == ci.nValues, 'Resample from list must match number of values along axis');
            ci.axisRandomizeModes(idx) = ci.AxisResampleFromSpecified;
            ci.axisResampleFromLists{idx} = resampleFromList;
            ci.axisRandomizeWithReplacement(idx) = replace;

            ci = ci.invalidateCache();
        end
    end

    methods % Attribute related 
        function [tf, idx] = hasAttribute(ci, name)
            if isnumeric(name)
                [tf, idx] = ismember(name, 1:ci.nAttributes);
            else
                [tf, idx] = ismember(name, ci.attributeNames);
            end
        end

        function idx = assertHasAttribute(ci, name)
            [tf, idx] = ci.hasAttribute(name);
            if ~all(tf)
                if isnumeric(name)
                    name = strjoin(name(~tf), ', ');
                elseif iscell(name)
                    name = strjoin(name(~tf));
                end
                error('Attribute(s) %s not found', name);
            end
        end

        function na = get.nAttributes(ci)
            na = length(ci.attributeNames);
        end

        function idxList = getAttributeIdx(ci,name)
            if isempty(name)
                idxList = [];
                return;
            end
            
            if isnumeric(name)
                % already idx, just return
                idxList = floor(name);
                idxList(idxList < 0 | idxList > ci.nAttributes) = NaN;
                return;
            end
            
            if ~iscell(name)
                name = {name};
            end

            idxList = nan(length(name), 1);
            for i = 1:length(name)
                if ischar(name{i})
                    idx = find(strcmp(ci.attributeNames, name{i}), 1);
                else
                    idx = name{i};
                end
                if isempty(idx)
                    error('Cannot find attribute named %s', name{i});
                end
                idxList(i) = idx;
            end
        end
        
        function tf = getIsAttributeNumeric(ci, name)
            idx = ci.getAttributeIdx(name);
            tf = ci.attributeNumeric(idx);
        end
        
        % return an A x 1 numeric array of constants in the AttributeValue*
        % set listed above, describing how this attribute's values are
        % determined
        function modes = get.attributeValueModes(ci)
            % check for manual value list, then manual bins, then auto
            % bins, otherwise auto value list
            modes = nanvec(ci.nAttributes);
            for i = 1:ci.nAttributes
                if ~isempty(ci.attributeValueListsManual{i})
                    modes(i) = ci.AttributeValueListManual;
                elseif ~isempty(ci.attributeValueBinsManual{i})
                    modes(i) = ci.AttributeValueBinsManual;
                elseif ~isnan(ci.attributeValueBinsAutoCount(i))
                    modes(i) = ci.attributeValueBinsAutoModes(i);
                else
                    modes(i) = ci.AttributeValueListAuto;
                end
            end
        end

        % determine the number of attributes, where possible, otherwise
        % leave as NaN. returns A x 1 numeric array
        function nv = get.nValuesByAttribute(ci)
            nv = nanvec(ci.nAttributes);
            for i = 1:ci.nAttributes
                nv(i) = numel(ci.attributeValueLists{i});
            end
        end

        function desc = get.attributeDescriptions(ci)
            desc = cellvec(ci.nAttributes);
            isFilter = ci.attributeActsAsFilter;
            modes = ci.attributeValueModes;
            for i = 1:ci.nAttributes
                name = ci.attributeNames{i};  
                nValues = ci.nValuesByAttribute(i);
                nAutoBins = ci.attributeValueBinsAutoCount(i);

                switch modes(i)
                    case ci.AttributeValueListManual
                        suffix = sprintf('(%d)', nValues);
                    case ci.AttributeValueListAuto
                        suffix = sprintf('(%d auto)', nValues);
                    case ci.AttributeValueBinsManual
                        suffix = sprintf('(%d bins)', nValues);
                    case ci.AttributeValueBinsAutoUniform
                        suffix = sprintf('(%d uniform-bins)', nAutoBins);
                    case ci.AttributeValueBinsAutoQuantiles
                        suffix = sprintf('(%d quantiles)', nAutoBins);
                end
                
                if isFilter(i)
                    filterStr = ' [filter]';
                else
                    filterStr = '';
                end

                if ci.attributeNumeric(i)
                    numericStr = '#';
                else
                    numericStr = '';
                end
                desc{i} = sprintf('%s %s%s%s', name, numericStr, suffix, filterStr);
            end
        end 

        % add a new attribute
        function ci = addAttribute(ci, name, varargin)
            ci.warnIfNoArgOut(nargout);

            p = inputParser;
            p.addRequired('name', @ischar);
            % is this attribute always numeric?
            % list of allowed values for this value (other values will be ignored)
            p.addParamValue('requestAs', '', @ischar);
            p.addParamValue('valueList', {}, @(x) isnumeric(x) || iscell(x)); 
            p.addParamValue('valueBins', {}, @(x) isnumeric(x) || iscell(x));
            p.parse(name, varargin{:});
            valueList = p.Results.valueList;
            requestAs = p.Results.requestAs;
            if isempty(requestAs)
                requestAs = name;
            end

            if ci.hasAttribute(name)
                error('ConditionDescriptor already has attribute %s', name);
            end
            
            iAttr = ci.nAttributes + 1;
            ci.attributeNames{iAttr} = name;
            ci.attributeNumeric(iAttr) = isnumeric(valueList) || islogical(valueList); 
            ci.attributeRequestAs{iAttr} = requestAs;

            if isempty(valueList)
                ci.attributeValueListsManual{iAttr} = {};
            else
                assert(isnumeric(valueList) || iscell(valueList), 'ValueList must be numeric or cell');
                % filter for unique values or 
                ci.attributeValueListsManual{iAttr} = unique(valueList, 'stable');
            %    if ~iscell(valueList)
             %       valueList = num2cell(valueList);
             %   end
            end

            ci.attributeValueBinsManual{iAttr} = [];
            ci.attributeValueBinsAutoCount(iAttr) = NaN;
            ci.attributeValueBinsAutoModes(iAttr) = NaN;

            ci = ci.invalidateCache();
        end

        function ci = addAttributes(ci, names)
            ci.warnIfNoArgOut(nargout);
            for i = 1:numel(names)
                ci = ci.addAttribute(names{i});
            end
        end
        
        % remove an existing attribute
        function ci = removeAttribute(ci, varargin)
            ci.warnIfNoArgOut(nargout);

            if iscell(varargin{1})
                attributes = varargin{1};
            else
                attributes = varargin;
            end

            ci.warnIfNoArgOut(nargout);

            if ~isnumeric(attributes)
                % check all exist
                ci.getAttributeIdx(attributes);
            else
                attributes = ci.attributeNames(attributes);
            end

            if ~ci.hasAttribute(attributes)
                error('ConditionDescriptor has no attribute %s', name);
            end

            iAttr = ci.getAttributeIdx(attributes);
            maskOther = true(ci.nAttributes, 1);
            maskOther(iAttr) = false;

            ci = ci.maskAttributes(maskOther);
        end
        
        function ci = maskAttributes(ci, mask)
            ci.warnIfNoArgOut(nargout);
            
            idxRemove = find(~mask);
            if ~any(idxRemove)
                return;
            end
            
            % first remove the attributes from any axes they are on
            ci = ci.removeAttributesFromAxes(idxRemove); 

            % then remove it from the attribute lists
            ci.attributeNames = ci.attributeNames(mask);
            ci.attributeRequestAs = ci.attributeRequestAs(mask);
            ci.attributeNumeric = ci.attributeNumeric(mask);
            ci.attributeValueListsManual = ci.attributeValueListsManual(mask);
            ci.attributeValueLists = ci.attributeValueLists(mask);
            ci.attributeValueListsAsStrings = ci.attributeValueListsAsStrings(mask);
            ci.attributeValueBinsAutoCount = ci.attributeValueBinsAutoCount(mask);
            ci.attributeValueBinsAutoModes = ci.attributeValueBinsAutoModes(mask);
            ci.attributeValueBinsManual = ci.attributeValueBinsManual(mask);
        end 
        
        % set all attribute value lists to auto
        function ci = setAllAttributeValueListsAuto(ci)
            ci.warnIfNoArgOut(nargout);
            for i = 1:ci.nAttributes
                ci = ci.setAttributeValueListAuto(i);
            end
        end
        
        % restore value list to automatically include all values, with no
        % binning
        function ci = setAttributeValueListAuto(ci, attr)
            ci.warnIfNoArgOut(nargout);
            iAttr = ci.assertHasAttribute(attr);
            ci.attributeValueListsManual{iAttr} = [];
            ci.attributeValueBinsManual{iAttr} = [];
            ci.attributeValueBinsAutoCount(iAttr) = NaN;
            ci.attributeValueBinsAutoModes(iAttr) = NaN;
            ci = ci.invalidateCache();
        end
        
        function ci = setAttributeNumeric(ci, attr, tf)
            ci.warnIfNoArgOut(nargout);
            iAttr = ci.assertHasAttribute(attr);
            ci.attributeNumeric(iAttr) = tf;
        end  

        % manually set the attribute value list
        function ci = setAttributeValueList(ci, name, valueList)
            ci.warnIfNoArgOut(nargout);

            iAttr = ci.getAttributeIdx(name);           
            if isempty(valueList)
                ci.attributeValueListsManual{iAttr} = {};
            else
                ci.attributeValueListsManual{iAttr} = valueList;                
            end
            
            %ci.attributeNumeric(iAttr) = isnumeric(valueList) || islogical(valueList);

            ci = ci.invalidateCache();
        end

        % manually set attribute bins
        function ci = binAttribute(ci, name, bins)
            ci.warnIfNoArgOut(nargout);

            if isvector(bins) && isnumeric(bins)
                assert(issorted(bins), 'Bins specified as vector must be in sorted order');
                binsMat = nan(numel(bins)-1, 2);
                binsMat(:, 1) = bins(1:end-1);
                binsMat(:, 2) = bins(2:end);
            elseif iscell(bins)
                binsMat = cell2mat(bins);
            else
                binsMat = bins;
            end
            
            assert(ismatrix(binsMat) && size(binsMat, 2) == 2, 'Bins matrix must be nBins x 2');
            assert(all(binsMat(:, 2) >= binsMat(:, 1)), 'Bins matrix must have larger value in second column than first');
            
            % convert nBins x 2 matrix to nBins x 1 cellvec 
            binsCell = mat2cell(binsMat, ones(size(binsMat, 1), 1), 2);

            iAttr = ci.getAttributeIdx(name); 
            ci.attributeValueBinsManual{iAttr} = binsCell;
            ci.attributeNumeric(iAttr) = true;
            ci.attributeValueListsManual{iAttr} = {};
            ci.attributeValueBinsAutoCount(iAttr) = NaN;
            ci.attributeValueBinsAutoModes(iAttr) = NaN;

            ci = ci.invalidateCache();
        end

        % automatically set attribute binned uniformly by range
        function ci = binAttributeUniform(ci, name, nBins)
            ci.warnIfNoArgOut(nargout);
            
            iAttr = ci.getAttributeIdx(name);

            ci.attributeValueBinsManual{iAttr} = [];
            ci.attributeNumeric(iAttr) = true;
            ci.attributeValueListsManual{iAttr} = {};
            ci.attributeValueBinsAutoCount(iAttr) = nBins;
            ci.attributeValueBinsAutoModes(iAttr) = ci.AttributeValueBinsAutoUniform;

            ci = ci.invalidateCache();
        end

        % automatically set attribute binned into quantiles
        function ci = binAttributeQuantiles(ci, name, nQuantiles)
            ci.warnIfNoArgOut(nargout);

            iAttr = ci.assertHasAttribute(name);
            ci.attributeValueBinsManual{iAttr} = [];
            ci.attributeNumeric(iAttr) = true;
            ci.attributeValueListsManual{iAttr} = {};
            ci.attributeValueBinsAutoCount(iAttr) = nQuantiles;
            ci.attributeValueBinsAutoModes(iAttr) = ci.AttributeValueBinsAutoQuantiles;

            ci = ci.invalidateCache();
        end
    end

    % get, set data stored inside odc
    methods 
        % NOTE: all of these should copy odc before writing to it
        
        function v = get.conditions(ci)
            v = ci.odc.conditions;
            if isempty(v)
                ci.odc.conditions = ci.buildConditions();
                v = ci.odc.conditions;
            end
        end
        
        function ci = set.conditions(ci, v)
            ci.odc = ci.odc.copy();
            ci.odc.conditions = v;
        end
        
        function v = get.conditionsAsStrings(ci)
            v = ci.odc.conditionsAsStrings;
            if isempty(v)
                ci.odc.conditionsAsStrings = ci.buildConditionsAsStrings();
                v = ci.odc.conditionsAsStrings;
            end
        end
        
        function ci = set.conditionsAsStrings(ci, v)
            ci.odc = ci.odc.copy();
            ci.odc.conditionsAsStrings = v;
        end
        
        function v = get.conditionsAxisAttributesOnly(ci)
            v = ci.odc.conditionsAxisAttributesOnly;
            if isempty(v)
                ci.odc.conditionsAxisAttributesOnly = ci.buildConditionsAxisAttributesOnly();
                v = ci.odc.conditionsAxisAttributesOnly;
            end
        end
        
        function ci = set.conditionsAxisAttributesOnly(ci, v)
            ci.odc = ci.odc.copy();
            ci.odc.conditionsAxisAttributesOnly = v;
        end
        
        function v = get.appearances(ci)
            v = ci.odc.appearances;
            if isempty(v)
                ci.odc.appearances = ci.buildAppearances();
                v = ci.odc.appearances;
            end
        end
        
        function ci = set.appearances(ci, v)
            ci.odc = ci.odc.copy();
            ci.odc.appearances = v;
        end
        
        function v = get.names(ci)
            v = ci.odc.names;
            if isempty(v)
                ci.odc.names = ci.buildNames();
                v = ci.odc.names;
            end
        end 
        
        function ci = set.names(ci, v)
            ci.odc = ci.odc.copy();
            ci.odc.names = v;
        end
        
        function v = get.attributeValueLists(ci)
            v = ci.odc.attributeValueLists;
            if isempty(v)
                ci.odc.attributeValueLists = ci.buildAttributeValueLists();
                v = ci.odc.attributeValueLists;
            end
        end
        
        function ci = set.attributeValueLists(ci, v)
            ci.odc = ci.odc.copy();
            ci.odc.attributeValueLists = v;
        end
        
        function v = get.attributeValueListsAsStrings(ci)
            v = ci.odc.attributeValueListsAsStrings;
            if isempty(v)
                ci.odc.attributeValueListsAsStrings = ci.buildAttributeValueListsAsStrings();
                v = ci.odc.attributeValueListsAsStrings;
            end
        end
        
        function ci = set.attributeValueListsAsStrings(ci, v)
            ci.odc = ci.odc.copy();
            ci.odc.attributeValueListsAsStrings = v;
        end

        function v = get.axisValueLists(ci)
            v = ci.odc.axisValueLists;
            if isempty(v)
                ci.odc.axisValueLists = ci.buildAxisValueLists();
                v = ci.odc.axisValueLists;
            end
        end

        function ci = set.axisValueLists(ci, v)
            ci.odc = ci.odc.copy();
            ci.odc.axisValueLists = v;
        end
        
        function v = get.axisValueListsAsStrings(ci)
            v = ci.odc.axisValueListsAsStrings;
            if isempty(v)
                ci.odc.axisValueListsAsStrings = ci.buildAxisValueListsAsStrings();
                v = ci.odc.axisValueListsAsStrings;
            end
        end

        function ci = set.axisValueListsAsStrings(ci, v)
            ci.odc = ci.odc.copy();
            ci.odc.axisValueListsAsStrings = v;
        end
    end

    % build data stored inside odc (used by getters above)
    methods 
        function values = buildConditionsAxisAttributesOnly(ci)
            if ci.nAxes == 0
                values = struct();
            else
                valueLists = ci.axisValueLists; 
                values = TensorUtils.mapFromAxisLists(@structMergeMultiple,...
                    valueLists, 'asCell', false);
            end
        end
        
        function values = buildConditions(ci)
            values = ci.conditionsAxisAttributesOnly;
            
            % and add "wildcard" match for all other attributes that act as
            % filter (i.e. have manual value list or bins specified)
            whichAxis = ci.attributeAlongWhichAxis;
            isFilter = ci.attributeActsAsFilter;
            valueLists = ci.attributeValueLists;
            for iA = 1:ci.nAttributes
                if isnan(whichAxis(iA)) && isFilter(iA)
                    valueList = valueLists{iA};
                    
                    % flatten any subgroupings of values in the value list
                    if ci.attributeNumeric(iA) && iscell(valueList)
                        valueList = [valueList{:}];
                    elseif ~ci.attributeNumeric(iA) && ~iscellstr(valueList) && ~ischar(valueList)
                        valueList = [valueList{:}];
                    end
                    % wrap in cell to avoid scalar expansion
                    values = assignIntoStructArray(values, ci.attributeNames{iA}, {valueList});
                end
            end
        end
        
        % build a wildcard search struct where each .attribute field is the
        % value list for that attribute
        function values = buildStructAllAttributeValueLists(ci)
            values = struct();
            for iA = 1:ci.nAttributes
                values = assignIntoStructArray(values, ci.attributeNames{iA}, ...
                    ci.attributeValueLists(iA));
            end
        end
        
        function values = buildStructNonAxisAttributeValueLists(ci)
            whichAxis = ci.attributeAlongWhichAxis;
            values = struct();
            for iA = 1:ci.nAttributes
                if isnan(whichAxis(iA))
                    values = assignIntoStructArray(values, ci.attributeNames{iA}, ...
                        ci.attributeValueLists(iA));
                end
            end
        end
        
        function values = buildConditionsAsStrings(ci)
            if ci.nAxes == 0
                values = {structToString(ci.conditions)};
            else
                valueLists = ci.axisValueListsAsStrings; 
                values = TensorUtils.mapFromAxisLists(@(varargin) strjoin(varargin, ' '),...
                    valueLists, 'asCell', true);
            end
        end
        
        function valueListByAxes = buildAxisValueLists(ci)
            valueListByAxes = cellvec(ci.nAxes);
            for iX = 1:ci.nAxes
                % build a cellstr of descriptions of the values along this axis
               
                % G x 1 cell of cells: each contains a struct specifying an attribute specification for each element along the axis
                if isempty(ci.axisValueListsManual{iX})
                    % build auto list of attributes
                    valueListByAxes{iX} = makecol(buildAutoValueListForAttributeSet(ci.axisAttributes{iX}));
                else
                    valueListByAxes{iX} = makecol(ci.axisValueListsManual{iX});
                end
            end

            function values = buildAutoValueListForAttributeSet(attributes)
                % build a struct array for a set of attributes that walks all possible combinations of the attribute values 
                if ischar(attributes)
                    attributes = {attributes};
                end
                attrIdx = ci.getAttributeIdx(attributes);
                valueLists = ci.attributeValueLists(attrIdx);

                % convert bin edges value lists to the cell vectors
                for i = 1:numel(attrIdx)
                    switch ci.attributeValueModes(attrIdx(i))
                        case {ci.AttributeValueBinsManual, ci.AttributeValueBinsAutoUniform, ...
                                ci.AttributeValueBinsAutoQuantiles}
                            % convert valueList from Nbins x 2 matrix to
                            % Nbins x 1 cellvector so that it gets mapped
                            % correctly
                            valueLists{i} = mat2cell(valueLists{i}, ones(size(valueLists{i}, 1), 1));
                    end
                end
                            
                values = TensorUtils.mapFromAxisLists(@buildStruct, valueLists, ...
                    'asCell', false);

                function s = buildStruct(varargin)
                    for j = 1:numel(varargin)
                        s.(attributes{j}) = varargin{j};
                    end
                end

            end
        end
        
        function strCell = buildAxisValueListsAsStrings(ci)
            strCell = cellvec(ci.nAxes);
            valueLists = ci.axisValueLists;
            randStrCell = ci.axisRandomizeModesAsStrings;
            
            % describe the list of values selected for along each position on each axis
            for iX = 1:ci.nAxes  
                
                % start with axisValueLists
                attr = ci.axisAttributes{iX};
                attrIdx = ci.getAttributeIdx(attr);
                
                % replace binned values with strings
                for iA = 1:numel(attrIdx)
                    switch ci.attributeValueModes(attrIdx(iA))
                        case {ci.AttributeValueBinsManual, ci.AttributeValueBinsAutoUniform, ...
                                ci.AttributeValueBinsAutoQuantiles}
                            % convert valueList from 1 x 2 vector to '#-#' string
                            for iV = 1:numel(valueLists{iX})
                                if ~iscellstr(valueLists{iX}(iV).(attr{iA}))
                                    valueLists{iX}(iV).(attr{iA}) = sprintf('%g-%g', cell2mat(valueLists{iX}(iV).(attr{iA})));
                                end
                            end
                    end
                end
                
                strCell{iX} = arrayfun(@structToString, makecol(valueLists{iX}), ...
                   'UniformOutput', false);

                % append randomization indicator when axis is randomized
                if ci.axisRandomizeModes(iX) ~= ci.AxisOriginal
                    strCell{iX} = cellfun(@(s) [s ' ' randStrCell{iX}], strCell{iX}, 'UniformOutput', false);
                end
            end
        end

        function names = buildNames(ci)
            % pass along values(i) and the subscripts of that condition in case useful 
            if ci.nConditions > 0
                fn = ci.nameFn;
                if isempty(fn)
                    fn = @ConditionDescriptor.defaultNameFn;
                end
                names = fn(ci);
                assert(iscellstr(names) && TensorUtils.compareSizeVectors(size(names), ci.conditionsSize), ...
                    'nameFn must return cellstr with same size as .conditions');
            else
                names = {};
            end
        end

        function appearances = buildAppearances(ci)
            if ci.nConditions > 0
                appearFn = ci.appearanceFn;

                if isempty(appearFn)
                    appearances = ci.defaultAppearanceFn();
                else
                    appearances = appearFn(ci);
                end
            else
                appearances = [];
            end
        end

        function valueList = buildAttributeValueLists(ci)
            % just pull the manual lists (ConditionInfo will deal
            modes = ci.attributeValueModes;
            valueList = cellvec(ci.nAttributes);
            for i = 1:ci.nAttributes
                switch modes(i) 
                    case ci.AttributeValueListManual
                        valueList{i} = ci.attributeValueListsManual{i};
                    case ci.AttributeValueBinsManual
                        valueList{i} = ci.attributeValueBinsManual{i};
                    case ci.AttributeValueBinsAutoUniform
                        % placeholder string to be replaced by actual bins
                        % matrix
                        valueList{i} = arrayfun(@(bin) sprintf('bin%d', bin), ...
                            1:ci.attributeValueBinsAutoCount(i), 'UniformOutput', false);
                    case ci.AttributeValueBinsAutoQuantiles
                        % the number of bins is known, so they can be specified here
                        valueList{i} = arrayfun(@(bin) sprintf('quantile%d', bin), ...
                            1:ci.attributeValueBinsAutoCount(i), 'UniformOutput', false);
                    otherwise
                         % place holder, must be determined when
                        % ConditionInfo applies it to data
                        if ci.attributeNumeric(i)
                            valueList{i} = NaN;
                        else
                            valueList{i} = {'?'};
                        end
                end
                valueList{i} = makecol(valueList{i});
            end
        end
        
        function valueList = buildAttributeValueListsAsStrings(ci)
            modes = ci.attributeValueModes;
            valueList = ci.attributeValueLists;
            for i = 1:ci.nAttributes
                switch modes(i) 
                    case ci.AttributeValueListManual
                        if ci.attributeNumeric(i)
                            if iscell(valueList{i})
                                % could have multiple attribute values
                                % grouped together as one element
                                valueList{i} = cellfun(@(i) sprintf('%.3g', i), valueList{i}, 'UniformOutput', false);
                                valueList{i} = cellfun(@(vals) strjoin(vals, ','), valueList{i}, 'UniformOutput', false);
                            else
                                valueList{i} = arrayfun(@(i) sprintf('%.3g', i), valueList{i}, 'UniformOutput', false);
                            end
                        else
                            % non-numeric, can leave as is unless...
                            if ~iscellstr(valueList{i})
                                % could have multiple attribute values
                                % grouped together as one element
                                valueList{i} = cellfun(@(vals) strjoin(vals, ','), valueList{i}, 'UniformOutput', false);
                            end
                        end
                                
                    case {ci.AttributeValueBinsManual, ci.AttributeValueBinsAutoUniform, ci.AttributeValueBinsAutoQuantiles}
                        if ~iscell(valueList{i})
                            bins = valueList{i};
                            valueList{i} = arrayfun(@(row) sprintf('%g-%g', bins(row, 1), bins(row, 2)), ...
                                1:size(bins, 1), 'UniformOutput', false);
                        else
                            % already cellstr for auto bins, leave as is
                        end
                    case ci.AttributeValueListAuto
                        % auto list leave empty, must be determined when
                        % ConditionInfo applies it to data
                        valueList{i} = {'?'};   
                end
                valueList{i} = makecol(valueList{i});
            end
        end

        function valueList = getAttributeValueList(ci, name)
            idx = ci.getAttributeIdx(name);
            valueList = makecol(ci.attributeValueLists{idx});
        end

        function valueIdx = getAttributeValueIdx(ci, attr, value)
            [tf, valueIdx] = ismember(value, ci.getAttributeValueLists(attr));
            assert(tf, 'Value not found in attribute %s valueList', attr);
        end
        
        function a = defaultAppearanceFn(ci, varargin)
            % returns a AppearSpec array specifying the default set of appearance properties 
            % for the given group. indsGroup is a length(ci.groupByList) x 1 array
            % of the inds where this group is located in the high-d array, and dimsGroup
            % gives the full dimensions of the list of groups.
            %
            % We vary color along all axes simultaneously, using the linear
            % inds.
            %
            % Alternatively, if no arguments are passed, simply return a set of defaults

            nConditions = ci.nConditions;

            a(ci.conditionsSize()) = AppearanceSpec();

            if nConditions == 1
                cmap = [0.3 0.3 1];
            else
                if nConditions > 256
                    cmap = jet(nConditions);
                else
                    cmap = distinguishable_colors(nConditions);
                end
            end

            for iC = 1:nConditions
                a(iC).Color = cmap(iC, :);
            end
        end
    end
    
    methods(Static) % Default nameFn and appearanceFn
        function nameCell = defaultNameFn(ci, varargin) 
            % receives the condition descriptor itself and returns a
            %  a cell tensor specifying the names of each condition
            nameCell = ci.conditionsAsStrings;
        end
    end

    methods(Static) % construct from another condition descriptor, used primarily by ConditionInfo
        function cdNew = fromConditionDescriptor(cd, cdNew)
            cd.warnIfNoArgOut(nargout);
            
            if nargin < 2
                cdNew = ConditionDescriptor();
            end

            meta = ?ConditionDescriptor;
            props = meta.PropertyList;

            for iProp = 1:length(props)
                prop = props(iProp);
                if prop.Dependent || prop.Constant || prop.Transient
                    continue;
                else
                    name = prop.Name;
                    cdNew.(name) = cd.(name);
                end
            end

            cdNew = cdNew.invalidateCache();
        end
        
        % construct condition descriptor from a struct of attribute values
        % for numeric attributes, if there are more than 10 different
        % values, the attribute will be binned into quintiles
        function cd = fromStruct(s)
            cd = ConditionDescriptor();
            cd = cd.addAttributes(fieldnames(s));
        end
    end
    
    methods
        function cd = getConditionDescriptor(cd)
            % this does nothing here since it's already a condition
            % descriptor. This is used for "casting" back to ConditionDescriptor 
            % from subclasses.
            cd.warnIfNoArgOut(nargout);
        end
        
        function cdManual = fixValueListsByApplyingToTrialData(cd, td)
            % converts automatic attribute and axis value lists to manual
            % lists, by building a ConditionInfo instance, applying to a
            % TrialData instance, fixing all value lists, and converting
            % back to a condition descriptor
            cd.warnIfNoArgOut(nargout);
            ci = ConditionInfo.fromConditionDescriptor(cd, td);
            cdManual = ci.getFixedConditionDescriptor();
        end
    end

    methods(Access=protected) % Utility methods
        function warnIfNoArgOut(obj, nargOut)
            if nargOut == 0 && ~isa(obj, 'handle')
                warning('WARNING: %s is not a handle class. If the instance handle returned by this method is not stored, this call has no effect.\\n', ...
                    class(obj));
            end
        end
        
        function obj = copyIfHandle(obj)
            if isa(obj, 'handle')
                obj = obj.copy(); %#ok<MCNPN>
            end
        end
    end
end

