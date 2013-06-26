classdef ParamChannelDescriptor < ChannelDescriptor

    methods
        function type = getType(cdesc)
            type = 'param';
        end

        function str = describe(cdesc)
            str = sprintf('Param (%s)', cdesc.name, cdesc.units);  
        end

        function dataFields = getExtraDataFields(cdesc)
            dataFields = {};
        end

        function cd = ParamChannelDescriptor(varargin)
            cd = cd@ChannelDescriptor(varargin{:});
            cd.defaultValue = NaN;
            cd.scalar = true; % by default, change this if not true
        end
    end

end
