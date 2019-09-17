function batch_tiff2mat(FolderName, FileName, iparams)
% batch_tiff2mat: extract data from tiffs (generated by scanimage)
%
% Usage:
%   batch_tiff2mat(FolderName, FileName, iparams)
%
% Args:
%   FolderName: name of folders to load
%   FileName: name of files to load
%   iparams: parameters to update
%       (FieldOfView: default 768um, set for this setup)
%       (cDir: directory)
%       (ch2save: channels to save)
%           (1, red)
%           (2, green)
%       (SpMode: main string used for all preprocesing steps it basically
%           sets:
%           (data dimensions: 2DxT, 3DxT, or 3D)
%           (type of stimuli delivered: _song, _opto)
%           (for opto only: which code was used prv or LEDcontroler: _prv, 
%               (otherwise it assumes it used LEDcontroler))
%           (for song: we only used prv)
%           (version of tiff: _old, (otherwise it assumes it is the new version))
%           (type of axial device: 'piezo', 'remotefocus')
%               examples: 2DxT_song_prv, 3DxT_song_prv, 3DxT_opto_prv, 3DxT_opto
%       (Zres: space between planes, 1 um)
%       (pixelsym: flag for pixel symmetry)
%           (0, asymmetric)
%           (1, symmetric)
%       (fStrain: append animal strain to metadata)
%           ([])
%       (region2crop: Y and X coordinates to use from whole FOV)
%           ([])
%
% Notes:
% this function assumes tiff files have the following structure:
%   (year|month|day)_animalnum_(trial/rep)num_'*'.tif ('*' refers to any
%       integer), beware scanimage starts counting from 0. (see demo)
% this function generates *_rawdata.mat and *_metadata.mat
%   *_rawdata.mat: has a Data variable with dimensions:
%       (y (rows/lines), x (columns/pixels per line), z, time, pmt) 
%   *_metadata.mat: is populated with imaging structure variable 'iDat' and
%       file/directory structure variable fDat, and initial stimuli
%       structure variable lStim.
%
% iDat: image metadata structure
%   iDat.FrameN: number of planes
%   iDat.StackN: number of timeseries
%   iDat.FrameSize: [heigth, width]
%   iDat.Power: laser power
%   iDat.DelFrames: frames to delete (deprecated)
%   iDat.LEDCorr: flag for LED corrected stacks
%   iDat.MotCorr: flag for motion corrected stacks
%   iDat.histshift: (deprecated)
%   iDat.bsSubs: (deprecated)
%   iDat.XYresmatch: flag for spatially resampled stacks
%   iDat.sSmooth: flag for spatially smoothed stacks
%   iDat.tResample: flag for temporally resampled stacks
%   iDat.tSmooth: flag for temporally smoothed stacks
%   iDat.MetaData: image resolution
%       {'voxelsize', 'y x z', []}
%
% fDat: file or directory metadata structure
%   fDat.FileName: input file name (without suffices '_rawdata.mat' or '.tiff')
%   fDat.FolderOrigin: original data directory
%   fDat.FolderTrace: original main directory
%   fDat.DataType: main string used for all preprocesing
%   fDat.fName: name of all inout tiffs contributing to this mat file
%
% lStim: stimuli related (auditory/opto) metadata structure
%   lStim.fName: file name
%   lStim.fs: default sampling rate (stimuli delivery)
%   lStim.trialn: number of trials delivered 
%   lStim.fStrain: fly strain / genotype
%   lStim.channels: number of channels recorded
%
% Field of view: needs to be measured per objective or 2P setup
%   using zoom 10 and 256 pixels (width and heigth)
%   motion of 2.1um ~= 7 pixels (~twice the distance calculated for zoom 20)
%   Inter-pixel distance: 0.3, from which you infer voxel size in x and y == 0.3.
%   whole area is then: 768x768 um2 == (voxel size)X(zoom)X(number of pixels)

% default params
tifpars.FieldOfView = 768;
tifpars.cDir = pwd;
tifpars.ch2save = [1 2];
tifpars.SpMode = [];
tifpars.Zres = 1;
tifpars.pixelsym = 0;
tifpars.fStrain = [];
tifpars.region2crop = [];

% internal variables
tifpars.fName = [];
% max spatial resolution to use (round all values smaller than 1/p.sres)
tifpars.sres = 10^4;
tifpars.f2reject = {'.', '..', 'preprocessed', 'BData'};

% update variables
if ~exist('FileName', 'var'); FileName = []; end
if ~exist('FolderName', 'var'); FolderName = []; end
if ~exist('iparams', 'var'); iparams = []; end
tifpars = loparam_updater(tifpars, iparams);

if isempty(tifpars.SpMode)
    fprintf('Error, need to specify SpMode');
    return;
end

fprintf('Running Tiff2Mat\n');

% finding folders and filtering out data that is not selected
f2run = dir;
f2run = str2match(FolderName, f2run);
f2run = str2rm(tifpars.f2reject, f2run);
f2run = {f2run.name};

fprintf(['Running n-folders : ', num2str(numel(f2run)), '\n'])

% checking files inside folder
for Fol_i = 1:numel(f2run)
    
    tifpars.Folder2Run = f2run{Fol_i};
    cd(f2run{Fol_i});
    
    [BaseFName, ~, ~] = rdir_namesplit([], [], [], {'Zstack'}, FileName);
    
    % rdir_namesplit: select all 
    %   '(year|month|day)_(animalnum)_(trialnum/repnum)' names
    UBaseFName = unique(BaseFName); 
    fprintf(['Running Folder : ', num2str(f2run{Fol_i}), ...
        ' (n-exp-types, ', num2str(numel(UBaseFName)), ') ,'])
    clear BaseFName
    
    % running each exptype (basename)
    
    % get unique flynum and fly-trials per basename
    for basename_i = 1:numel(UBaseFName)
        
        [~, AnimalNum, TrialNum] = ...
            rdir_namesplit(UBaseFName(basename_i), [], [], {'Zstack'}, FileName);
        
        % get the number of trials per unique AnimalNum and basename
        for ani_i = unique(AnimalNum)
            
            TrialPerAnimal = TrialNum(AnimalNum == ani_i);
            
            if isempty(TrialPerAnimal)
                
                fprintf(['Does not have any file with', ...
                    ' flynumber :', num2str(ani_i), ' \n'])
                
            else
                
                Trial2Load = unique(TrialPerAnimal);
                fprintf([' (n-trials, ', ...
                    num2str(unique(TrialPerAnimal)), ')\n']);
                
                for trial_i = Trial2Load
                    
                    % collapsing all timepoints and z-slices to 1 mat file
                    NameRoot = [UBaseFName{basename_i}, '_', ...
                        num2str(ani_i), '_', num2str(trial_i), '_'];
                    loadertype(NameRoot, tifpars);
                    
                end 
                
            end
            
            clear TNPFlyNum
            
        end
        
        clear FlyNum TrialNum
        
    end
    
    cd(tifpars.cDir)
    
end

fprintf('\n ********** Done **********\n')

end

function loadertype(NameRoot, tifpars)
% loadertype: main tiff2mat function depending on datatype
%
% Usage:
%   loadertype(NameRoot)
%
% Args:
%   NameRoot: basic name of file to load
%   tifpars: parameters

switch tifpars.SpMode
    % collapsing files with the same animal and trial number to one mat files
    case {'3DxT_opto_old', '3DxT_song_old'}
        trialcollapser(NameRoot, tifpars);
    case {'2DxT', '3DxT', '2DxT_song', '3DxT_song', '2DxT_opto', '3DxT_opto', ...
            '3DxT_opto_prv'}
        trialcollapsernew(NameRoot, tifpars)
    % saving each file independently, '2DxT' or single '3D'
    case {'2DxT_single', '3D'}
        singleacqcollapser(NameRoot, tifpars);
end

end

function trialcollapsernew(repname, tifpars)
% trialcollapsernew: collect all tiffs that belong to a single file and
% generates the varariable Data(Y, X, Z, T, Ch) or (Y, X, T, Ch)
%
% Usage:
%   trialcollapsernew(repname)
%
% Args:
%   repname: name pattern
%   tifpars: parameters

% collapsing files with the same animal and trial number to one mat file
repname_tif = rdir([repname, '0.tif']);
repname_tif = {repname_tif.name};
repname_tif = repname_tif{1};
tif_num = numel(rdir([repname, '*.tif']));
clear NameRoot

Data = [];
tempdata_pre = [];
tempdata = [];

fprintf(['n-repts = ', num2str(tif_num), '\n']) 

% generate matfile to save Data
% overwrite
if exist([tifpars.cDir, filesep, tifpars.Folder2Run, filesep, ...
    repname_tif(1:(end-6)), '_rawdata.mat'], 'file')
    
    delete([tifpars.cDir, filesep, tifpars.Folder2Run, filesep, ...
        repname_tif(1:(end-6)), '_rawdata.mat'])

    try
        delete([tifpars.cDir, filesep, tifpars.Folder2Run, filesep, ...
        repname_tif(1:(end-6)), '_refdata.mat'])
    end

end

dataObj = matfile([tifpars.cDir, filesep, tifpars.Folder2Run, filesep, ...
    repname_tif(1:(end-6)), '_rawdata.mat'], 'Writable', true);

% importing and concatenating Data on the 3r dim

% dimension to accumulate across tiffs
dim2count = 0;

for tif_i = 1:tif_num
    
    tif_idx = num2str(tif_i - 1);
    tifpars.fName{1, tif_i} = [repname_tif(1:(end-6)), '_', tif_idx];
    
    try
        % tiff2mat_scanimage output is 4D or 3D (Y, X, frame, pmt)
        [tempdata, ImMeta] = ...
            tiff2mat_scanimage(tifpars.fName{1, tif_i}, tifpars.SpMode, 1);
        
        % crop region
        if ~isempty(tifpars.region2crop)
            y_ = tifpars.region2crop(1):...
                tifpars.region2crop(2);
            x_ = tifpars.region2crop(3):...
                tifpars.region2crop(4);
            ImMeta.X = numel(x_);
            ImMeta.Y = numel(y_);
            tempdata = tempdata(y_, x_, :, :);
            clear y_ x_
        end
        
        % selecting Channel(s) to save
        pmtNum = size(tempdata, 4);

        if pmtNum > 1 % Selecting channel to save
            if length(tifpars.ch2save) < 2
                tempdata = squeeze(tempdata(:, :, :, tifpars.ch2save));
                fprintf(['Collecting just channel ', ...
                    num2str(tifpars.ch2save), '\n'])
            end
        end
        
        % count planes
        if ~isempty(ImMeta.Z)
            ImMeta.FrameNum = ImMeta.Z;
        else
            ImMeta.FrameNum = 1;
        end
       
        % add pre from last tiff
        if ~isempty(tempdata_pre)
            [size(tempdata_pre); size(tempdata)]
            tempdata = cat(3, tempdata_pre, tempdata);
            size(tempdata)
        end
        
        % chop & reshape
        RepeatNum_temp = floor(size(tempdata, 3)/ImMeta.FrameNum);
        siz = size(tempdata);
        if length(siz) == 4
            siz(5) = siz(4);
        end
        siz(3) = ImMeta.FrameNum;
        siz(4) = RepeatNum_temp;

        tempdata_pre = tempdata(:, :, (RepeatNum_temp*ImMeta.FrameNum + 1):end, :);
        tempdata = tempdata(:, :, 1:RepeatNum_temp*ImMeta.FrameNum, :);
        tempdata = reshape(tempdata, siz);
        clear siz

        % concatenate
        siz = size(tempdata);
        
        if ImMeta.FrameNum == 1
            
            if numel(siz) < 5; siz(5) = 1; end
           
            idx2use = ((dim2count + 1) : (dim2count + siz(4)));

            if siz(5) > 1
                dataObj.Data(1:siz(1), 1:siz(2), idx2use, 1:siz(5)) ...
                    = squeeze(single(tempdata));
            else
                dataObj.Data(1:siz(1), 1:siz(2), idx2use) ...
                    = squeeze(single(tempdata));
            end
            
            dim2count = dim2count + siz(4);
            
        else
            
            if numel(siz) < 5; siz(5) = 1; end

            idx2use = ((dim2count + 1) : (dim2count + siz(4)));
            
            if siz(5) > 1
                dataObj.Data(1:siz(1), 1:siz(2), 1:siz(3), idx2use, 1:siz(5)) ...
                    = single(tempdata);
            else
                dataObj.Data(1:siz(1), 1:siz(2), 1:siz(3), idx2use) ...
                    = single(tempdata);
            end
            
            dim2count = dim2count + siz(4);
            
        end
        
        clear tempdata;
    catch
        keyboard
    end
    
    if tif_i == 1
        fprintf(['Channels imported: ', num2str(ImMeta.ChNum), '\n'])
    end
    
    fprintf('*');
    if mod(tif_i, 60) == 0 || tif_i == tif_num
        fprintf('\n');
    end
    
end

clear tempdata_pre

% Default values for reshape
ImMeta.RepeatNum = dim2count;
ImMeta.DelFrames = [];

fprintf(['Data final size: ', num2str(size(dataObj.Data)), '\n'])

% generate metadata
[fDat, iDat] = generatemetadata(repname_tif(1:(end-6)), ImMeta,  ...
    tifpars.cDir, tifpars.Folder2Run, tifpars.SpMode, ...
    tifpars.pixelsym, tifpars.Zres, tifpars.sres, ...
    tifpars.FieldOfView, tifpars.fName);

% save metadata
if contains(tifpars.SpMode, 'song') || ...
        contains(tifpars.SpMode, 'prv')
    
    % all prv (for song or opto)
    SavingDataNew([], fDat, iDat, 3, ...
        tifpars.cDir, tifpars.Folder2Run, ...
        tifpars.fStrain)
    
elseif ~contains(tifpars.SpMode, 'prv')
    
    % old opto using LEDcontroler
    SavingDataNew([], fDat, iDat, 1, ...
        tifpars.cDir, tifpars.Folder2Run, ...
        tifpars.fStrain)
    
end

clear Data iDat fDat ImMeta

end

function singleacqcollapser(NameRoot, tifpars)

% collapsing files with the same fly and trial number to one mat files
fprintf(['Running File ', NameRoot])
TemplateFile = rdir([NameRoot, '*.tif']);
TemplateFile = {TemplateFile.name};
clear NameRoot

% Saving each tiff file independently
fprintf([' (n-trials, ', num2str(numel(TemplateFile)), ')\n'])

for acqIdx = 1:numel(TemplateFile)
    
    fprintf(TemplateFile{acqIdx}(1:end-4))
    
    % importing data
    % importing single tiff files
    % tiff2mat_scanimage output is always 4D (X, Y, frame, pmt)
    [Data, ImMeta] = tiff2mat_scanimage(...
        TemplateFile{acqIdx}(1:(end-4)), tifpars.SpMode);
    fprintf([' (Channels, ', num2str(ImMeta.ChNum), ')'])
    
    switch tifpars.SpMode
        case '3D'
            
            % Data is 5D (X, Y, Z, pmt), volumes
            Data = uint16(Data);
            Data = flipdim(Data, 3);
            % deleting first frame (weird projection plane)
            Data = Data(:, :, 2:end, :);
            
        case '2DxT_single'
            
            % Data is 5D (X, Y, Time, pmt)
            Data = uint16(Data);
    end
    
    % Selecting channel to save
    pmtNum = size(Data, 4); 
    
    % Selecting channel to save
    if pmtNum > 1
        if length(tifpars.ch2save) < 2
            Data = squeeze(Data(:, :, :, tifpars.ch2save));
            fprintf([' collecting just channel ', num2str(tifpars.ch2save)])
        end
    end
    
    % Metadata
    ImMeta.RepeatNum = 1;
    ImMeta.FrameNum = size(Data, 3);
    [fDat, iDat] = generatemetadata(TemplateFile{acqIdx}(1:(end-4)), ImMeta,  ...
        tifpars.cDir, tifpars.Folder2Run, tifpars.SpMode, ...
        tifpars.pixelsym, tifpars.Zres, tifpars.sres, ...
        tifpars.FieldOfView, tifpars.fName);
    
    SavingDataNew(Data, fDat, iDat, 1, ...
        tifpars.cDir, tifpars.Folder2Run, ...
        tifpars.fStrain)
    
    clear Data iDat fDat ImMeta
    
    fprintf('\n')
    
end
end

function trialcollapser(NameRoot, tifpars)

% collapsing files with the same fly and trial number to one mat files
TemplateFile = rdir([NameRoot, '001.tif']);
TemplateFile = {TemplateFile.name};
TemplateFile = TemplateFile{1};
tiffNumel = numel(rdir([NameRoot, '*.tif']));
clear NameRoot

% Collapsing data from all timepoints to a single matfile
fprintf(['n-repts = ', num2str(tiffNumel), '\n']) 

for RepIdx = 1:tiffNumel
    
    % importing tiff files
    if RepIdx<10
        NumIdx = ['00',num2str(RepIdx)];
    elseif RepIdx > 99
        NumIdx = num2str(RepIdx);
    else 
        NumIdx = ['0',num2str(RepIdx)];
    end
    
    % OptROISeg output is always 4D (X, Y, frame, pmt)
    tifpars.fName{1, RepIdx} = [TemplateFile(1:(end-8)), '_', NumIdx];
    [Data(:, :, :, :, RepIdx), ImMeta] = ...
        tiff2mat_scanimage(tifpars.fName{1, RepIdx}, tifpars.SpMode);
    fprintf('*');
    
    if mod(RepIdx, 60) == 0 || RepIdx == tiffNumel
        fprintf('\n');
    end
    
end

fprintf('\n')
fprintf(['Channels imported: ',num2str(ImMeta.ChNum),'\n'])

% update RepeatNum
ImMeta.RepeatNum = RepIdx;
ImMeta.FrameNum = size(Data, 3);

% Data is 5D (X, Y, frame, pmt, reps)
Data = permute(Data, [1 2 3 5 4]);
[Data, ImMeta.DelFrames] = zeroframedetect(Data);

% Data is 5D (X, Y, Z, Time, pmt)
eval(['Data = ', ImMeta.Imclass, '(Data);'])

% Selecting channel to save
pmtNum = size(Data, 5); 
if pmtNum > 1
    if length(tifpars.ch2save) < 2
        Data = squeeze(Data(:, :, :, :, tifpars.ch2save));
    end
end

% Metadata
[fDat, iDat] = generatemetadata(TemplateFile(1:(end-8)), ImMeta, ...
    tifpars.cDir, tifpars.Folder2Run, tifpars.SpMode, ...
    tifpars.pixelsym, tifpars.Zres, tifpars.sres, ...
    tifpars.FieldOfView, tifpars.fName);

SavingDataNew(Data, fDat, iDat, 2, ...
        tifpars.cDir, tifpars.Folder2Run, ...
        tifpars.fStrain)
    
clear X Y FrameNum Channels Zoom Data iDat fDat

end

function [Data, Idx] = zeroframedetect(Data)
% zeroframedetect: detect frames with values below greenFThs
%
% Usage:
%   [Data, Idx] = zeroframedetect(Data)
%
% Args:
%   Data: 3D or 4D matrix

siz = size(Data);
greenFThs = 50;
GreenData = Data(:, :, :, :, 2);
maxPixF = squeeze(max(max(GreenData, [], 1), [], 2));
emptyframes = maxPixF <= greenFThs; 
vol2fill = sum(emptyframes, 1) > 0; ...
    vol2fill = find(vol2fill == 1);

if ~isempty(vol2fill)
    
    % volume filling
    Data(:, :, :, :, 2) = OptVolFill(vol2fill, GreenData);
    % get Idx in a 3D version of data arragement
    emptyframes(:, vol2fill) = 1;
    emptyframes = reshape(emptyframes, [prod(siz(3:4)) 1]);
    Idx = find(emptyframes == 1);
    
else
    
    Idx = [];
    
end

end

function [fDat, iDat] = ...
    generatemetadata(ifilename, ImMeta, ...
    cDir, Folder2Run, SpMode, pixelsym, ...
    Zres, sres, FieldOfView, fName)
% generatemetadata: collect image metadata
%
% Usage:
%   [fDat, iDat] = generatemetadata(ifilename, ImMeta)
%
% Args:
%   ifilename: input filename
%   ImMeta: medatada with dimensions
%   cDir: current directory
%   Folder2Run: file directory
%   SpMode: type of data to run (2DxT, 3DxT, old, new, etc)
%   pixelsym: flag for pixel symmetry
%       (0, asymmetric)
%       (1, symmetric)
%   Zres: space between planes, 1 um
%   sres: max spatial resolution to use (round all values smaller than 1/p.sres)
%       (default, 10^4)
%   FieldOfView: default 768um, set for this setup
%   fName: name of all tiff files contributing to this matfile

% Loading existing metadata, Load matfile asociated with this tiff file
try
    load([cDir, filesep, Folder2Run, ...
        filesep, ifilename, '_metadata.mat'], 'fDat', 'iDat');
end

% Updating / reseting variables
fDat.FileName = ifilename;
fDat.FolderOrigin = cDir;
fDat.FolderTrace = cDir((max(strfind(cDir, filesep)) + 1):end);
fDat.DataType = SpMode;
fDat.fName = fName;

if ~exist('iDat', 'var')
    fprintf('writing new iDat');
    iDat = struct('MetaData', [], 'ZoomFactor', ImMeta.Zoom);
end

% pixel size (symmetric or not)
if pixelsym == 0
    
    iDat.MetaData = {'voxelsize', 'y x z', ...
        round([FieldOfView/(ImMeta.Zoom*ImMeta.Y), ...
        FieldOfView/(ImMeta.Zoom*ImMeta.X), ...
        Zres]*sres)/sres};
    
else
    
    iDat.MetaData = {'voxelsize', 'y x z', ...
        round([FieldOfView/(ImMeta.Zoom*ImMeta.X), ...
        FieldOfView/(ImMeta.Zoom*ImMeta.X), ...
        Zres]*sres)/sres};
    
end

% pass variables to iDat
iDat.FrameN = ImMeta.FrameNum;
iDat.StackN = ImMeta.RepeatNum;
iDat.FrameSize = [ImMeta.Y, ImMeta.X]; % [Y, X], [heigth, width]
iDat.Power = ImMeta.Power;
iDat.DelFrames = ImMeta.DelFrames;

% reset preprocessing count
iDat.LEDCorr = 0;
iDat.MotCorr = 0;
iDat.histshift = 0;
iDat.bsSubs = 0;
iDat.XYresmatch = 0;
iDat.sSmooth = 0;
iDat.tResample = 0;
iDat.tSmooth = 0;

% remove some fields produced later
f2rem = {'lstEn', 'fstEn', 'GreenChaMean', ...
    'RedChaMean', 'Tres', 'sstEn', 'sSmoothpar', 'PMT_fscore'};

for i = 1:numel(f2rem)
    try iDat = rmfield(iDat, f2rem{i}); end
end

end

function SavingDataNew(Data, fDat, iDat, saveType, ...
    cDir, Folder2Run, ifStrain)
% SavingDataNew: saving both dataand metadata in current folder
%
% Usage:
%   SavingDataNew(Data, fDat, iDat, saveType, ...
%       cDir, Folder2Run, ifStrain)
%
% Args:
%   Data: 3D or 4D matrix
%   fDat: file metadata
%   iDat: image metadata
%   saveType: which input file to read
%   cDir: current directory
%   Folder2Run: file directory
%   ifStrain: input fStrain

o_file_name_preffix = [cDir, filesep, ...
    Folder2Run, filesep, fDat.FileName];

% save Data
if ~isempty(Data)
    save([cDir, filesep, Folder2Run, filesep, ...
        fDat.FileName, '_rawdata.mat'], 'Data', '-v7.3')
end

% load extra metadata
if saveType == 1
    
    try load([o_file_name_preffix, '.mat'], 'sDat'); end
    
elseif saveType == 2
    
    load([o_file_name_preffix, '_001.mat'], 'sDat');
            
elseif saveType == 3
    
    try load([o_file_name_preffix, '_vDat.mat'], 'rDat', 'logs'); end
    
end

lStim.fName = fDat.FileName;
lStim.fs = [];
lStim.trialn = [];
lStim.fStrain = [];
lStim.channels = [];

% update lStim (using rDat)
if exist('rDat', 'var')
    lStim.fs = rDat.Fs;
    lStim.trialn = numel(rDat.selectedStimulus);  
end

% update lStim (using logs)
if exist('logs', 'var')
    lStim.fStrain = logs.fStrain;
end

% update lStim (using sDat)
if exist('sDat', 'var')
    lStim.fs = sDat.fs;
    lStim.trialn = sDat.trial;
    lStim.fStrain = sDat.fStrain;
    lStim.channels = sDat.channels;
end

% replace/append userdefine fStrain metadata to lStim
if ~isempty(ifStrain)
    lStim.fStrain = ifStrain;
end

% update and save metadata
save([o_file_name_preffix, '_metadata.mat'], 'fDat', 'iDat', 'lStim')

end

% function SavingData(Data, fDat, iDat, saveType)
% 
% global p
% 
% o_file_name_preffix = [p.cDir, filesep, p.Folder2Run, filesep, fDat.FileName];
% 
% % Saving data in current folder
% save([o_file_name_preffix, '_rawdata.mat'], 'Data', '-v7.3')
% 
% % Saving metadata
% if saveType == 1
%     
%     save([o_file_name_preffix, '_metadata.mat'], ...
%         'fDat', 'iDat', '-append')
%     
% else
%     
%     % updates sDat to include names of all the trials used to collapse this file
%     % it assumes that all the other stimuli parameters are the same
%     load([o_file_name_preffix, '_001.mat'], 'sDat');
%     sDat.fName = p.fName;
%     
%     if exist([o_file_name_preffix, '_metadata.mat'], 'file') == 2
%         save([o_file_name_preffix, '_metadata.mat'], ...
%             'fDat', 'iDat', 'sDat', '-append')
%     else
%         save([o_file_name_preffix, '_metadata.mat'], ...
%             'fDat', 'iDat', 'sDat')
%     end
%     
% end
% 
% p.fName = [];
% 
% end
