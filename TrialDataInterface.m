classdef TrialDataInterface < handle & matlab.mixin.Copyable
% TrialDataInterface is an AbstractImplementor class which acts as a wrapper
% around a set of trials. Subclasses must provide a list of ChannelDescriptors
% for each data channel within, and provide an accessor for channels by name

    methods(Abstract)
        % return a string describing the data set wrapped by this TDI
        datasetName = getDatasetName(tdi, varargin);

        % return a scalar struct containing any arbitrary metadata
        datasetMeta = getDatasetMeta(tdi, varargin);

        % return the number of trials wrapped by this interface
        nTrials = getTrialCount(tdi, varargin);

        % return the name of the time unit used by this interface
        timeUnitName = getTimeUnitName(tdi, varargin);

        % Describe the channels present in the dataset 
        % channelDescriptors: scalar struct. fields are channel names, values are ChannelDescriptor 
        channelDescriptors = getChannelDescriptors(tdi, varargin);
        
        % return a nTrials x 1 struct with all the data for each specified channel 
        % in channelNames cellstr array
        %
        % the fields of this struct are determined as:
        % .channelName for the primary data associated with that channel
        % .channelName_extraData for extra data fields associated with that channel
        %   e.g. for an AnalogChannel, .channelName_time
        %   e.g. for an EventChannel, .channelName_tags
        %
        % channelNames may include any of the channels returned by getChannelDescriptors()
        %   as well as any of the following "special" channels used by TrialData:
        %
        %   subject : string, subject from whom the data were collected
        %   protocol : string, protocol in which the data were collected
        %   protocolVersion: numeric version identifier for that protocol
        %   trialId : a unique numeric identifier for this trial
        %   trialIdStr: a unique string describing this trial
        %   saveTag : a numeric identifier for the containing block of trials
        %   duration : time length of each trial in tUnits
        %   tStartWallclock : wallclock datenum indicating when this trial began
        %   tStopWallclock : wallclock datenum indicating when this trial ended
        %
        channelData = getChannelData(tdi, channelNames, varargin);
    end

    methods
        % return the time conversion factor, i.e. number of time units in 1 second
        function N = getTimeUnitsPerSecond(tdi, varargin)
            timeUnitName = tdi.getTimeUnitName();

            switch(timeUnitName)
                case 'ms'
                    N = 1000;
                case 's'
                    N = 1;
                otherwise
                    error('Unrecognized timeUnits %s', timeUnitName);
            end
        end

    end

    methods(Sealed)
        % build ParamChannelDescriptors around each of the special param names
        % .special will be marked as true
        function cds = getSpecialParamChannelDescriptors(tdi)
            cd = ParamChannelDescriptor.buildStringParam('subject');
            cd.special = true;
            cds = cd;

            cd = ParamChannelDescriptor.buildStringParam('protocol');
            cd.special = true;
            cds(end+1) = cd;

            cd = ParamChannelDescriptor.buildScalarParam('protocolVersion');
            cd.special = true;
            cds(end+1) = cd;

            cd = ParamChannelDescriptor.buildStringParam('trialIdStr');
            cd.special = true;
            cds(end+1) = cd;

            cd = ParamChannelDescriptor.buildScalarParam('trialId');
            cd.special = true;
            cds(end+1) = cd;

            cd = ParamChannelDescriptor.buildScalarParam('saveTag');
            cd.special = true;
            cds(end+1) = cd;

            cd = ParamChannelDescriptor.buildScalarParam('duration');
            cd.units = tdi.getTimeUnitName();
            cd.special = true;
            cds(end+1) = cd;
            
            cd = ParamChannelDescriptor.buildDatenumParam('timeStartWallclock');
            cd.special = true;
            cds(end+1) = cd;
            
            tUnits = tdi.getTimeUnitName();
            cd = EventChannelDescriptor.buildSingleEvent('TrialStart', tUnits);
            cd.special = true;
            cds(end+1) = cd;
            
            cd = EventChannelDescriptor.buildSingleEvent('TrialEnd', tUnits);
            cd.special = true;
            cds(end+1) = cd;
        end
    end

end
