function stimuli_onset_offset = ...
    find_stim_int(itrace, minwidth, threshold_val)
% find_stim_int: function reads stimuli trace and outputs 
%   the start and end of stimuli.
%
% Usage:
%   stimuli_onset_offset = ...
%       find_stim_int(itrace, minwidth, threshold_val)
%
% Args:
%   itrace: input stimuli trace
%   minwidth: minimun width of stimuli timepoints
%   threshold_val: voltage threshold

if ~exist('threshold_val', 'var')
   threshold_val = 0; 
end

itrace = abs(itrace) > threshold_val;

if size(itrace, 1) > 1
    itrace = itrace';
end

% get onset
onset = (find(diff(itrace) == 1) + 1)';
% get offset
offset = (find(diff(itrace) == -1) + 1)';

min_num = min([numel(onset) numel(offset)]);

stimuli_onset_offset = [onset(1:min_num), offset(1:min_num)];

if size(stimuli_onset_offset, 1) > 1
    
    i = 1;
    k = 0;
    
    while k == 0
        
        if (stimuli_onset_offset(i + 1, 1) - ...
                stimuli_onset_offset(i, 2) < minwidth) ...
                && (i < size(stimuli_onset_offset, 1))
            
            % update upper limit
            stimuli_onset_offset(i, 2) = stimuli_onset_offset(i + 1, 2);
            % delete contiguous one
            stimuli_onset_offset(i + 1, :) = []; 
            
        else
            
            i = i + 1; 
            
        end
        
        k = double(i == size(stimuli_onset_offset, 1));
        
    end
    
end

end
