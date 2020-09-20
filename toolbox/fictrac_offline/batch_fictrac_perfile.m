function batch_fictrac_perfile(FolderName, FileName, iparams)
% batch_fictrac_perfile: runs fictrac on each video 
%
% Usage:
%	batch_fictrac_perfile(FolderName, FileName, iparams)
%
% Args:
%   FolderName: name of folder to run
%   FileName: name of file to run
%   iparams: parameters to update
%       (redo: flag to redo tracking)
%           (default, 0)
%
% Notes:
%   requires fictrac to be installed.
%       for windows use https://github.com/murthylab/fic-trac-win
%       If you are using a Point Grey/FLIR camera, make sure the FlyCapture SDK is installed. 
%           Copy FlyCapture2_C.dll from the Point Grey directory
%           (it is in the bin folder - for instance, 
%           C:\Program Files\Point Grey Research\FlyCapture2\bin64) 
%           and place it in your FicTrac directory. 
%           If it is named FlyCapture2_C_v100.dll rename it.
%           some times it requires both: FlyCapture2_v100 and FlyCapture2_C_v100
%       see https://github.com/murthylab/fly-vr for some additional
%           instalation info
%
%   requires a config_file template in the current directory
%       (generated by batch_gen_fictrac_input_files.m)
%
%   From command line fictrac can be run using the following lines
%       FicTrac-PGR FicTracPGR_config.txt
%       FicTrac FicTrac_config.txt

% default params
fictracpars.redo = 0;
fictracpars.cDir = pwd;

if ~exist('FolderName', 'var')
   FolderName = [];
end

if ~exist('FileName', 'var')
   FileName = [];
end

if ~exist('iparams', 'var'); iparams = []; end
fictracpars = loparam_updater(fictracpars, iparams);

fo2reject = {'.', '..', 'preprocessed', ...
    'BData', 'motcor', 'rawtiff', 'stitch'};

% finding folders and filtering out data that is not selected
fo2run = dir;
fo2run = str2match(FolderName, fo2run);
fo2run = str2rm(fo2reject, fo2run);
fo2run = {fo2run.name};

fprintf(['Running n-folders : ', num2str(numel(fo2run)), '\n'])

for folder_i = 1:numel(fo2run)
    
    fprintf(['Running folder : ', fo2run{folder_i}, '\n']);
    cd(fo2run{folder_i}); 
    runperfolder(FileName, fictracpars);
    cd(fictracpars.cDir)
    
end

fprintf('... Done\n')

end

function runperfolder(fname, fictracpars)
% runperfolder: function that runs all files per directory
%
% Usage:
%   runperfolder(fname, fictracpars)
%
% Args:
%   fname: file name
%   fictracpars: input parameters

% find all videos to process
vid2run = rdir('*.mp4');
vid2run = {vid2run.name}';
vid2run = str2match(fname, vid2run);
vid2run = strrep(vid2run, '_vid.mp4', '');

fprintf(['Running n-videos : ', num2str(numel(vid2run)), '\n'])

% default config file name
config_file = 'FicTrac_config.txt';
temp_config_file = 'temp_config.txt';

for i = 1:numel(vid2run)
    
    % run fictrac
    %   this generates the following outout files:
    %       *_fictrac.txt'
    %       *_maskim.tiff'
    %       *_calibration-transform.dat'
    %       *_template.jpg'
    
    if ~exist([vid2run{i}, '_fictrac.txt'], 'file') || ...
            fictracpars.redo
        % edit config file to include file name
        edit_FicTrac_config(config_file, vid2run{i})

        command2run = ['FicTrac ', temp_config_file];

        % execute fictrac
        if ispc
            dos(command2run);
        else
            unix(command2run);
        end

        % delete temp config file
        delete(temp_config_file)
    end
    
    % add fictrac variable to '_vDat.mat' file
    fictrac_txt2mat([vid2run{i}, '_fictrac.txt'])
    
end

end

function edit_FicTrac_config(config_file, vid_name)
% edit_FicTrac_config: edit config_file to run each video file
%
% Usage:
%	edit_FicTrac_config(config_file, vid_name)
%
% Args:
%   config_file: config file to use as template
%   vid_name: video name

% load text file
fid = fopen(config_file, 'r');
i = 1;
tline = fgetl(fid);
A{i} = tline;

while ischar(tline)
    i = i+1;
    tline = fgetl(fid);
    A{i} = tline;
end
fclose(fid);

% replace field
A{2} = ['input_vid_fn        ', vid_name, '_vid.mp4'];
A{3} = ['output_fn           ', vid_name, '_fictrac.txt'];
A{4} = ['mask_fn             ', vid_name, '_maskim.tiff'];
A{5} = ['transform_fn        ', vid_name, '_calibration-transform.dat'];
A{6} = ['template_fn         ', vid_name, '_template.jpg'];

% save txt file
fid = fopen('temp_config.txt', 'w');

for i = 1:numel(A)
    
    if A{i+1} == -1
        fprintf(fid, '%s', A{i});
        break
    else
        fprintf(fid, '%s\n', A{i});
    end
    
end

fclose(fid);

end
