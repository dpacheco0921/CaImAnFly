function batch_collectmetada(FolderName, FileName, iparams)
% batch_collectmetada: collect metadata from *.mat files (from Ephys/Stimuli
%   delivery PC) generated by prv or LEDcontroler
%
% Usage:
%   batch_collectmetada(FolderName, FileName, iparams)
%
% Args:
%   FolderName: name of folders to load
%   FileName: name of files to load
%   iparams: parameters to update
%       (frameCh: 2PM shutter trigger / Y-axis of galvo or resonant channel)
%           (default, 1)
%       (lstimCh: stimuli channel in bin file)
%           (default, 2)
%       (lstimrDat: stimuli channel in rDat)
%           (default, 1)
%       (buffer: time to chop from recording end 0 (ms))
%           (default, 0)
%       (pgate: plot frame width time for each file per folder)
%           (default, 0)
%       (pgates: plot raw Y trace, start and end of each frame)
%           (default, 0)
%       (cDir: current directory)
%       (fo2reject: extra string to select transformation)
%       (fsuffix: suffix of files with Data variable)
%           (default, '_rawdata.mat')
%       (fmetsuffix: suffix of metadata file)
%           (default, '_metadata.mat')
%       (mode: two modes:
%           (0, readout resuls, default)
%           (1, generate and save)
%       (minframet: minimun frame duration in tens of miliseconds)
%           (default, 900 (90 ms))
%       (findstim: gate to use stimuli trace to find stimuli start and end)
%           (default, 0)
%       (minwidth: minimun width of stimuli (ms))
%           (default, [])
%       (stimths: voltage threshold to find stimuli)
%           (default, 0)      
% 
% Notes
% this function updates: lStim and iDat
% lStim: stimuli related (auditory/opto) metadata structure
%   adds the following fields:
%       lStim.trace: stimulus raw trace
%       lStim.lstEn: stimulus onset and offset  (sound and opto)
%       lStim.sPars.order: stimulus order (sound and opto)
%       lStim.sPars.name: name of each stimulus (sound and opto)
%       lStim.sPars.int: stimulus intensity (sound and opto)
%       lStim.sPars.sr: sampling rate (sound and opto)
%       lStim.sPars.basPre: silence pre stimulus (sound and opto)
%       lStim.sPars.basPost: silence post stimulus (sound and opto)
%       lStim.sPars.freq: frequency of pulse stimulus (opto)
%       lStim.sPars.width: width of pulse stimulus (opto)
%
% iDat: image metadata structure
%   adds the following fields:
%       iDat.StackN: updates depending on the length of time stamps
%           collected
%       iDat.fstEn: frame timestamps [onset offset]
%       iDat.sstEn: volume timestamps [onset offset]
%
% 2019-02-22: bleedthrough is adding a stronger DC change than expected and
%   affecting Frame time estimation, so now it runs calculate the mode frame
%   width and then uses it to eliminate peaks in between. need to work on
%   denoising this opto-related signal
% 2019-07-26:
%   1) now it is compatible with cases where no Y-galvo info is
%   provided or extra stimuli info
%   2) compatible with new setup (reads Y-galvo from data_*.mat files)

% default params
metpars.frameCh = 1;
metpars.lstimCh = 2;
metpars.lstimrDat = 1;
metpars.buffer = 0;
metpars.pgate = 0;
metpars.pgates = 0;
metpars.cDir = pwd;
metpars.fo2reject = {'.', '..', 'preprocessed', 'BData'};
metpars.fi2reject = [];
metpars.fsuffix = '_rawdata.mat';
metpars.fmetsuffix = '_metadata.mat';
metpars.mode = 1;
metpars.minframet = 900;
metpars.findstim = 0;
metpars.minwidth = [];
metpars.stimths = 0;

% update variables
if ~exist('FolderName', 'var'); FolderName = []; end
if ~exist('FileName', 'var'); FileName = []; end
if ~exist('iparams', 'var'); iparams = []; end
metpars = loparam_updater(metpars, iparams);

% find folders
fo2run = dir;
fo2run = str2match(FolderName, fo2run);
fo2run = str2rm(metpars.fo2reject, fo2run);
fo2run = {fo2run.name};

fprintf(['Running n-folders : ', num2str(numel(fo2run)), '\n'])

for i = 1:numel(fo2run)
    
    fprintf(['Running folder : ', fo2run{i}, '\n']);
    cd(fo2run{i}); 
    runperfolder(FileName, fo2run{i}, metpars);
    cd(metpars.cDir)
    
end

fprintf('... Done\n')

end

function runperfolder(fname, foname, metpars)
% runperfolder: function collects timestamps and stimulus from bin file 
%   with "metpars.fsuffix" suffix and fDat info
%
% Usage:
%   runperfolder(fname, foname, metpars)
%
% Args:
%   fname: file name template string
%   foname: figure name
%   metpars: parameters

% directory params
fi2run = rdir(['.', filesep, '*', metpars.fsuffix]);
fname = addsuffix(fname, metpars.fsuffix);
fi2run = str2match(fname, fi2run);
fi2run = str2rm(metpars.fi2reject, fi2run);
fi2run = {fi2run.name};
fi2run = strrep(fi2run, ['.', filesep], '');
fi2run = strrep(fi2run, '_rawdata.mat', '');

% plot times
if metpars.pgate == 1
    metpars.figH = figure('Name', foname);
    metpars.AxH = subplot(1, 1, 1);
end

for F2R_idx = 1:numel(fi2run)
    
    display(['Running file : ', fi2run{F2R_idx}])   
    runperfile(fi2run{F2R_idx}, metpars)
    
end

fprintf('****** Done ******\n')

end

function runperfile(filename, metpars)
% runperfolder: function collects timestamps and stimulus from bin file 
% with "metpars.fsuffix" suffix and fDat info
%
% Usage:
%   runperfolder(filename, ip)
%
% Args:
%   filename: name of file to load
%   metpars: parameters

% Load main variables 'lStim', 'iDat', 'fDat'
display(['Running file : ', filename])
load(['.', filesep, filename, '_metadata.mat'], ...
    'lStim', 'iDat', 'fDat')

% copy datatype (2D or 4D)
datatype = fDat.DataType;

% input data to load
stim_file2load = [];
if contains(datatype, 'song') || contains(datatype, 'prv') ...
        && ~contains(datatype, 'fict')
    stim_file2load = 'prv';
elseif contains(datatype, 'opto') && ~contains(datatype, 'prv') ...
        && ~contains(datatype, 'fict')
    stim_file2load = 'LEDcontroler';
elseif contains(datatype, 'fict')
    stim_file2load = 'fict';
end

% Notes:
% cases for 3DxT new data, sometimes the Y movement stops, giving you a
%   wrong frame end for the last frame, which is then deleted

if contains(stim_file2load, 'prv')
    % stimuli delivered using prv code

    if contains(datatype, 'prv') && contains(datatype, 'opto')
        %ip.frameCh = 3; ip.lstimCh = 4; ip.lstimrDat = 2;
        metpars.frameCh = 2;
        metpars.lstimCh = 1;
        metpars.lstimrDat = 2;
    else
        metpars.frameCh = 2;
        metpars.lstimCh = 1;
    end

    bin_file_name = ['.', filesep, filename, '_bin.mat'];

    if exist(bin_file_name, 'file')

        load(bin_file_name, 'data', 'dataScalingFactor')
        Ch = data';
        Ch = double(Ch)/dataScalingFactor;
        clear data

    else

        fprintf('No stimulus & timestamp-related bin file found\n')
        Ch = [];

    end

elseif contains(stim_file2load, 'LEDcontroler')

    % stimuli delivered using LEDcontroler (old setup)
    Ch = local_binread(lStim);

elseif contains(stim_file2load, 'fict')

    % stimuli delivered using **
    data = h5load(['.', filesep, filename, '.h5']);
    eval(['Ch = ', 'data.input.samples(:,3);']);
    Ch = double(Ch)';
    clear data

    metpars.frameCh = 1;
    
    if contains(datatype, 'opto')

        % read stimulus from *.h5 file
        data = h5load(['.', filesep, filename, '.h5']);
        eval(['Ch(2, :) = ', 'data.input.samples(:, 2);']);
        clear data
                
    else
        
        Ch(2, :) = zeros(size(Ch));
        
    end

    metpars.lstimCh = 2;
    
else

    fprintf('No stimulus & timestamp-related bin file found\n')
    Ch = [];

end

% collect timestamps
FrameN = iDat.FrameN*iDat.StackN;

if ~isempty(Ch)
    [FrameInit, FrameEnd] = ...
        colecttimestamp(Ch(metpars.frameCh, :), ...
        FrameN, metpars.minframet, stim_file2load);
else

    % generate arbitrary timestamps
    %   (in case you dont have a readout of the Y galvo)
    FrameInit = (0:(FrameN-1))*10^3;
    FrameInit(1) = 1;
    FrameEnd = FrameInit + 900;

end

iDat.fstEn = [FrameInit' FrameEnd'];
clear FrameInit FrameEnd

% plot stim trace
if metpars.pgates == 1 && ~isempty(Ch)

    figure('Name', filename);
    AxHs = subplot(1, 1, 1);
    plot(Ch(metpars.frameCh, :), 'Parent', AxHs);
    hold(AxHs, 'on');
    plot(iDat.fstEn(:, 1), ...
        Ch(metpars.frameCh, iDat.fstEn(:, 1)), ...
        'o', 'Parent', AxHs)
    plot(iDat.fstEn(:, 2), ...
        Ch(metpars.frameCh, iDat.fstEn(:, 2)), ...
        'go', 'Parent', AxHs)
    xlabel(AxHs, 'Time 0.1 ms');
    ylabel(AxHs, 'V')

end

% update lStim field 'fName'
if contains(datatype, 'song') || contains(datatype, 'prv')
    lStim.fName = [lStim.fName, '_bin.mat'];
elseif contains(datatype, 'opto') && ~contains(datatype, 'prv')
    lStim.fName = [lStim.fName, '.bin'];
else
    lStim.fName = 'no stimulus file';
end

fprintf(['first frame ', num2str(iDat.fstEn(1, :)), ...
    ' second ', num2str(iDat.fstEn(2, :)), '\n'])

% homogenize frames and frametimes
%   edits iDat fields iDat.fstEn, iDat.FrameN & iDat.StackN
iDat = homogenize_frame_frametime(...
    filename, FrameN, iDat, datatype, metpars.mode);

% plot frame-diff
if metpars.pgate == 1

    plot(iDat.fstEn(:, 2) - iDat.fstEn(:, 1), ...
        'parent', metpars.AxH);
    hold(metpars.AxH,'on')
    xlabel(metpars.AxH, 'Frame');
    ylabel(metpars.AxH, 'Frame width 0.1 ms')

end

% chopping stim trace to start and end of imaging + buffer time
start_end = [iDat.fstEn(1, 1) - metpars.buffer*lStim.fs, ...
    (iDat.fstEn(end, 2) + metpars.buffer*lStim.fs)];

% chop and pass Ch (stimuli trace) to lStim.trace
if ~isempty(Ch)
    Ch = Ch(metpars.lstimCh, :);

    if start_end(2) > numel(Ch)
        lStim.trace = Ch(start_end(1):end);
        lStim.trace = [lStim.trace, zeros(1, start_end(2)-numel(Ch))];
    else
        lStim.trace = Ch(start_end(1):start_end(2));
    end

else
    lStim.trace = zeros(1, iDat.fstEn(end, 2));          
end

% set first frame start to index 1
iDat.fstEn = iDat.fstEn - start_end(1) + 1;

% generate sstEn (volume time)
if iDat.FrameN > 1 && metpars.mode

    preInit = min(reshape(iDat.fstEn(:, 1), ...
        [iDat.FrameN, iDat.StackN]), [], 1)';
    preEnd =  max(reshape(iDat.fstEn(:, 1), ...
        [iDat.FrameN, iDat.StackN]), [], 1)';
    iDat.sstEn = [preInit, preEnd];
    clear preInit preEnd

end

% get stim onset and offset and extra metadata
if contains(stim_file2load, 'prv')

    % load rDat
    load(['.', filesep, filename, '_vDat.mat'], 'rDat')

    [lStim.lstEn, lStim.trace] = ...
        songstim_init_end_rDat(rDat, start_end, ...
        metpars.lstimrDat, metpars.findstim, ...
        metpars.minwidth, metpars.stimths);

    % collect extra metadata
    lStim.sPars.order = rDat.stimOrder;
    lStim.sPars.name = rDat.ctrl.stimFileName;

    all_int = cell2mat(rDat.ctrl.intensity(:, 1));

    if contains(datatype, 'song')
        lStim.sPars.int = all_int(:, 1);
    elseif contains(datatype, 'opto')
        lStim.sPars.int = all_int(:, 2);
    end

    lStim.sPars.sr = rDat.ctrl.rate;
    lStim.sPars.basPre = rDat.ctrl.silencePre;
    lStim.sPars.basPost = rDat.ctrl.silencePost;
    clear rDat

elseif contains(stim_file2load, 'LEDcontroler')

    load(['.', filesep, filename, '.mat'], 'sDat');
    lStim.lstEn = optostim_init_end(lStim.trace, ...
        sDat);

    % collect extra metadata
    lStim.sPars.freq = ...
        repmat(sDat.freq, [size(lStim.lstEn, 1), 1]); 
    lStim.sPars.width = ...
        repmat(sDat.width, [size(lStim.lstEn, 1), 1]); 
    lStim.sPars.int = ...
        repmat(sDat.intensity, [size(lStim.lstEn, 1), 1]); 
    lStim.sPars.sr = ...
        repmat(sDat.fs, [size(lStim.lstEn, 1), 1]); 
    lStim.sPars.basPre = ...
        repmat(sDat.silencePre, [size(lStim.lstEn, 1), 1]); 
    lStim.sPars.basPost = ...
        repmat(sDat.silencePost, [size(lStim.lstEn, 1), 1]);

    lStim.sPars.order = 1:size(lStim.lstEn, 1);

    if isfield(sDat, 'stimFileName')
        lStim.sPars.name = ...
            repmat({sDat.stimFileName}, [size(lStim.lstEn, 1), 1]);
    else
        lStim.sPars.name = ...
            repmat({'OPTO'}, [size(lStim.lstEn, 1), 1]);                
    end

    clear sDat
    
elseif contains(stim_file2load, 'fict')
    
    % read text file with stimulus info
    sDat = parse_opto_fictrac_txtfile(...
        ['.', filesep, filename, '.txt']);
    
    lStim.lstEn = find_stim_int(lStim.trace, ...
        metpars.minwidth, metpars.stimths);
        
    % collect extra metadata
    lStim.sPars.freq = []; 
    lStim.sPars.width = []; 
    lStim.sPars.int = sDat.intensity(1:size(lStim.lstEn, 1)); 
    lStim.sPars.sr = sDat.rate(1:size(lStim.lstEn, 1)); 
    lStim.sPars.basPre = sDat.silencePre(1:size(lStim.lstEn, 1)); 
    lStim.sPars.basPost = sDat.silencePost(1:size(lStim.lstEn, 1));
    lStim.sPars.order = 1:size(lStim.lstEn, 1);

    if isfield(sDat, 'stimFileName')
        lStim.sPars.name = ...
            sDat.stimFileName(1:size(lStim.lstEn, 1));
    else
        lStim.sPars.name = ...
            repmat({'OPTO'}, [size(lStim.lstEn, 1), 1]);                
    end

    clear sDat
    
else

    % generate arbitrary stimulus information
    lStim.sPars.freq = 1;
    lStim.sPars.width = 1; 
    lStim.sPars.int = 0; 
    lStim.sPars.sr = 10^4; 
    lStim.sPars.basPre = 0; 
    lStim.sPars.basPost = 0;
    lStim.sPars.order = 1;
    lStim.sPars.name = {'nostim'};
    lStim.lstEn = [1 2];

end

if metpars.mode
    save(['.', filesep, filename, '_metadata.mat'], ...
        'iDat', 'lStim', '-append')
end

clear FrameInit FrameEnd order2chop Data NewStart lStim

clear iDat fDat Ch lStim ROI lStim

end

function iDat = homogenize_frame_frametime(...
    filename, frame_n, iDat, datatype, imode)
% homogenize_frame_frametime: chop frametimes or 
%   Data depending on length, correct time stamp 
%   for last frame.
% it edits iDat.fstEn, iDat.FrameN, iDat.StackN
%
% Usage:
%   homogenize_frame_frametime(frame_n, iDat, datatype, imode, Data)
%
% Args:
%   filename: name of file to load
%   frame_n: number of frames
%   iDat: image metadata variable
%   datatype: type of data
%   imode: two modes
%       (0, readout resuls)
%       (1, generate and save)

if imode
    % load data
    load(['.', filesep, filename, '_rawdata.mat'], 'Data');
end

if frame_n < size(iDat.fstEn, 1)

    % chop stamps
    fprintf('Chopping time stamps\n')
    iDat.fstEn = iDat.fstEn(1:frame_n, :);

elseif frame_n > size(iDat.fstEn, 1)

    % chop data
    if imode

        if contains(datatype, '2DxT')

            fprintf('Chopping Data matrix\n')
            Data = Data(:, :, 1:size(iDat.fstEn, 1), :);
            iDat.FrameN = 1; 
            iDat.StackN = size(Data, 3);

        elseif contains(datatype, '3DxT')

            if frame_n - size(iDat.fstEn, 1) < iDat.FrameN*0.5

                fprintf('increase fstEn\n')
                
                % extrapolate the frame time
                for fi = (size(iDat.fstEn, 1) + 1):frame_n
                    iDat.fstEn(fi, :) = iDat.fstEn(end, :) + ...
                        iDat.fstEn(end, :) - iDat.fstEn(end-1, :);
                end

            else
                
                fprintf('Chopping Data matrix\n')
                % prune n-volume
                z_end = floor((size(iDat.fstEn, 1))/iDat.FrameN);
                Data = Data(:, :, :, 1:z_end, :);
                iDat.FrameN = size(Data, 3);
                iDat.StackN = size(Data, 4);
                frame_n = iDat.FrameN*iDat.StackN;
                
                % prune fstEn
                iDat.fstEn = iDat.fstEn(1:frame_n, :);
                
            end

        end

        save(['.', filesep, filename, '_rawdata.mat'], 'Data', '-v7.3')

    end

elseif frame_n == size(iDat.fstEn, 1)

    % sometimes last frame ending is not counted right
    iDat.fstEn(end, 2) = iDat.fstEn(end, 1) + ...
        iDat.fstEn(end-1, 2) - iDat.fstEn(end-1, 1);

end

end

function [Frame_Init, Frame_End] = ...
    colecttimestamp(mirror_y_trace, ...
    frame_num, min_frame_time, stim_file2load)
% colecttimestamp: calculate frame onset anf offset based on the movement
% of the Y galvo.
%
% Usage:
%   [Frame_Init, Frame_End] = ...
%       colecttimestampNew(mirror_y_trace, frame_num, min_frame_time)
%
% Args:
%   mirror_y_trace: mirror y trace from 2PM
%   frame_num: number of frames (from Data)
%   min_frame_time: minimun time between frames
%   stim_file2load: stimuli delivery setup
%
% Notes:
% regular vs resonant galvo

if size(mirror_y_trace, 1) > 1; mirror_y_trace = mirror_y_trace'; end

% edit trace for resonant galvo
if contains(stim_file2load, 'fict')
    idx_start = find(mirror_y_trace < -1, 1, 'last');
    mirror_y_trace(1, 1:idx_start) = mirror_y_trace(idx_start + 1);
end

% calculate the diff of the smooth vector
tracet = -diff(diff(smooth(mirror_y_trace(1, :), 10)));

% amplitude threshold
max_pred = prctile(tracet, 99.8)*0.5;

% find frame ends & delete peaks that are shorter than expected frame interval
[~, Frame_End] = findpeaks(tracet, 'MinPeakHeight', max_pred);
Frame_End(diff(Frame_End) < min_frame_time*0.8) = [];
Frame_End = Frame_End';

% correct for artifact peak at the beginning
if Frame_End(1) > min_frame_time*0.8
    % frame end is as expected
    Frame_End = Frame_End(1:end);
else
    % frame end is too short, so delete this frametime
    % this could be due to a later start (happens for different settings).
    Frame_End = Frame_End(2:end);
end

% amplitude threshold
max_pred = prctile(-tracet, 99.8)*0.5;

% find frame inits delete peaks that are shorter than expected frame interval
[~, Frame_Init] = findpeaks(-tracet, 'MinPeakHeight', max_pred);
Frame_Init(diff(Frame_Init) < min_frame_time*0.8) = [];
Frame_Init = Frame_Init';

% if first time init is missed, add one
if Frame_Init(1) > min_frame_time*0.8
    fprintf(['missing first frame start time: ', num2str(Frame_Init(1)), ' '])
	Frame_Init = [Frame_Init(1) - round(mean(Frame_Init(2:2:10^2) ...
        - Frame_Init(1:2:10^2))), Frame_Init];
end

if Frame_Init(1) <= 0; Frame_Init(1) = 1; end

Frame_Init = Frame_Init(1:numel(Frame_End));

fprintf([' FrameTimePoints ( ', num2str(numel(Frame_Init)), ' )'])

if frame_num == numel(Frame_Init)
    fprintf('\n');
else
    fprintf([' # of frames ~= from image (', ...
        num2str(frame_num), ')\n']);
end

% get the mode
mode_frame_width = mode(Frame_End - Frame_Init)*0.9;

% recalculate frame times

tracet = -diff(diff(smooth(mirror_y_trace(1, :), 10)));
% tracet_detrend = prctfilt(mirror_y_trace, 10, 10^3, 10, 0);
% think more about which detrending would be better

% amplitude threshold
max_pred = prctile(tracet, 99.8)*0.5;

% find frame ends & delete peaks that are closer than expected frame interval
[~, Frame_End] = findpeaks(tracet, 'MinPeakHeight', max_pred, ...
    'MinPeakDistance', mode_frame_width);
Frame_End(diff(Frame_End) < min_frame_time*0.8) = [];
Frame_End = Frame_End';

% correct for artifact peak at the beginning
if Frame_End(1) > min_frame_time*0.8
    Frame_End = Frame_End(1:end);
else
    Frame_End = Frame_End(2:end);
end

% amplitude threshold
max_pred = prctile(-tracet, 99.8)*0.5;

% find frame inits delete peaks that are closer than expected frame interval
[~, Frame_Init] = findpeaks(-tracet, 'MinPeakHeight', max_pred, ...
    'MinPeakDistance', mode_frame_width);
Frame_Init(diff(Frame_Init) < min_frame_time*0.8) = [];
Frame_Init = Frame_Init';

% manual shift of onset/offset
if ~contains(stim_file2load, 'fict')
    Frame_Init = Frame_Init + 15;
else
    Frame_End = Frame_End - 2;
    Frame_Init = Frame_Init + 4;
end

if Frame_Init(1) > min_frame_time*0.8
	Frame_Init = [Frame_Init(1) - round(mean(Frame_Init(2:2:10^2) ...
        - Frame_Init(1:2:10^2))), Frame_Init];
end

if Frame_Init(1) <= 0; Frame_Init(1) = 1; end

Frame_Init = Frame_Init(1:numel(Frame_End));

fprintf([' FrameTimePoints ( ', num2str(numel(Frame_Init)), ' )'])

if frame_num == numel(Frame_Init)
    fprintf('\n');
else
    fprintf([' # of frames ~= from image (', ...
        num2str(frame_num), ')\n']);
end

end

function Y = local_binread(stimrel_var, cNum)
% local_binread: read '.bin' files
%
% Usage:
%   data = local_binread(stimrel_var, cNum)
%
% Args:
%   stimrel_var: stimuli related variable generated by LEDcontroler
%   cNum: number of channels to load
%
% Returns:
%   Y: vector or matrix contained in bin file

fID = fopen([strrep(stimrel_var.fName, '.mat', '') '.bin'], 'r');

if ~exist('cNum', 'var')
    
    Y = fread(fID, [length(stimrel_var.channels) inf], 'double');
    
else
    
    status = fseek(fID, 8*(cNum-1), -1);
    
    if status ~=0
        error('Could not seek for channel');
    end
    
    Y = fread(fID, 'double', (length(stimrel_var.channels)-1)*8)';
    
end

fclose(fID);

end
