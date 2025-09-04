
%Parse Json configuration files
function metadata = load_json_metadata(json_file)
%% Load JSON Metadata from File
% Parses JSON metadata files with sampling parameters and configuration
%
% Inputs:
%   json_file - Path to JSON metadata file
%
% Outputs:
%   metadata - Structure containing parsed metadata parameters

% Validate input
if ~exist(json_file, 'file')
    error('JSON metadata file not found: %s', json_file);
end

% Initialize output structure
metadata = struct();
metadata.file_path = json_file;
metadata.parsing_success = false;
metadata.sampling_freq = '';
metadata.speed_coef = NaN;
metadata.data_step = NaN;
metadata.fft_num = NaN;
metadata.data_channels = '';
metadata.data_mode = '';
metadata.file_name_bin = '';
metadata.create_time_bin = '';

try
    % Read JSON file
    fid = fopen(json_file, 'r');
    if fid == -1
        error('Cannot open JSON file: %s', json_file);
    end
    
    % Read entire file content
    json_content = fread(fid, inf, 'char=>char')';
    fclose(fid);
    
    % Remove BOM (Byte Order Mark) if present
    if startsWith(json_content, char([239, 187, 191]))  % UTF-8 BOM
        json_content = json_content(4:end);
        fprintf('Removed UTF-8 BOM from JSON file\n');
    elseif startsWith(json_content, char([255, 254]))  % UTF-16 LE BOM
        json_content = json_content(3:end);
        fprintf('Removed UTF-16 LE BOM from JSON file\n');
    elseif startsWith(json_content, char([254, 255]))  % UTF-16 BE BOM
        json_content = json_content(3:end);
        fprintf('Removed UTF-16 BE BOM from JSON file\n');
    end
    
    % Parse JSON content
    try
        json_data = jsondecode(json_content);
    catch ME
        % Try to clean the content and parse again
        json_content = strtrim(json_content);
        json_content = regexprep(json_content, '[\x00-\x1F\x7F]', ''); % Remove control characters
        json_data = jsondecode(json_content);
    end
    
    % Extract metadata fields with validation
    if isfield(json_data, 'samplingFreq')
        metadata.sampling_freq = json_data.samplingFreq;
    else
        warning('Missing samplingFreq in metadata file: %s', json_file);
        metadata.sampling_freq = '22.7kHz';  % Default from dataset
    end
    
    if isfield(json_data, 'speedCoef')
        metadata.speed_coef = json_data.speedCoef;
    else
        warning('Missing speedCoef in metadata file: %s', json_file);
        metadata.speed_coef = 0.1388888888888889;  % Default from dataset
    end
    
    if isfield(json_data, 'dataStep')
        metadata.data_step = json_data.dataStep;
    else
        warning('Missing dataStep in metadata file: %s', json_file);
        metadata.data_step = 64;  % Default from dataset
    end
    
    if isfield(json_data, 'fftNum')
        metadata.fft_num = json_data.fftNum;
    else
        warning('Missing fftNum in metadata file: %s', json_file);
        metadata.fft_num = 1024;  % Default from dataset
    end
    
    if isfield(json_data, 'binFile_DataArray')
        metadata.data_channels = json_data.binFile_DataArray;
    else
        warning('Missing binFile_DataArray in metadata file: %s', json_file);
        metadata.data_channels = 'IF1 Upper,IF1 Lower,IF2 Upper,IF2 Lower';  % Default
    end
    
    if isfield(json_data, 'dataMode')
        metadata.data_mode = json_data.dataMode;
    else
        warning('Missing dataMode in metadata file: %s', json_file);
        metadata.data_mode = 'Seamless';  % Default from dataset
    end
    
    if isfield(json_data, 'FileNameBin')
        metadata.file_name_bin = json_data.FileNameBin;
    else
        warning('Missing FileNameBin in metadata file: %s', json_file);
        metadata.file_name_bin = '';
    end
    
    if isfield(json_data, 'createTimeBin')
        metadata.create_time_bin = json_data.createTimeBin;
    else
        warning('Missing createTimeBin in metadata file: %s', json_file);
        metadata.create_time_bin = '';
    end
    
    % Convert sampling frequency string to numeric value
    if contains(metadata.sampling_freq, 'kHz')
        freq_str = strrep(metadata.sampling_freq, 'kHz', '');
        metadata.sampling_freq_hz = str2double(freq_str) * 1000;
    elseif contains(metadata.sampling_freq, 'Hz')
        freq_str = strrep(metadata.sampling_freq, 'Hz', '');
        metadata.sampling_freq_hz = str2double(freq_str);
    else
        metadata.sampling_freq_hz = 22700;  % Default fallback
    end
    
    % Add alias for compatibility
    metadata.speed_coefficient = metadata.speed_coef;
    
    % Validate critical parameters
    if isnan(metadata.speed_coef) || metadata.speed_coef <= 0
        error('Invalid speed coefficient: %f', metadata.speed_coef);
    end
    
    if isnan(metadata.data_step) || metadata.data_step <= 0
        error('Invalid data step: %d', metadata.data_step);
    end
    
    if isnan(metadata.fft_num) || metadata.fft_num <= 0
        error('Invalid FFT size: %d', metadata.fft_num);
    end
    
    if metadata.sampling_freq_hz <= 0
        error('Invalid sampling frequency: %f Hz', metadata.sampling_freq_hz);
    end
    
    % Mark parsing as successful
    metadata.parsing_success = true;
    
    % Log successful parsing
    fprintf('Successfully loaded metadata from: %s\n', json_file);
    fprintf('- Sampling Frequency: %s (%.0f Hz)\n', metadata.sampling_freq, metadata.sampling_freq_hz);
    fprintf('- Speed Coefficient: %.12f\n', metadata.speed_coef);
    fprintf('- Data Step: %d\n', metadata.data_step);
    fprintf('- FFT Size: %d\n', metadata.fft_num);
    fprintf('- Data Channels: %s\n', metadata.data_channels);
    fprintf('- Data Mode: %s\n', metadata.data_mode);
    
    % Additional metadata validation
    metadata.is_valid = validate_metadata(metadata);
    
catch ME
    warning('Error parsing JSON metadata from file %s: %s', json_file, ME.message);
    metadata.parsing_success = false;
    metadata.is_valid = false;
end

end

function is_valid = validate_metadata(metadata)
%% Validate metadata parameters for consistency
%
% Inputs:
%   metadata - Metadata structure to validate
%
% Outputs:
%   is_valid - Boolean indicating if metadata is valid

is_valid = true;

% Check if all required fields are present
required_fields = {'sampling_freq', 'speed_coef', 'data_step', 'fft_num', 'data_channels', 'data_mode'};
for i = 1:length(required_fields)
    if ~isfield(metadata, required_fields{i}) || isempty(metadata.(required_fields{i}))
        warning('Missing required metadata field: %s', required_fields{i});
        is_valid = false;
    end
end

% Check parameter ranges
if metadata.speed_coef <= 0 || metadata.speed_coef > 1
    warning('Speed coefficient out of expected range: %f', metadata.speed_coef);
    is_valid = false;
end

if metadata.data_step <= 0 || metadata.data_step > 1000
    warning('Data step out of expected range: %d', metadata.data_step);
    is_valid = false;
end

if metadata.fft_num <= 0 || metadata.fft_num > 10000
    warning('FFT size out of expected range: %d', metadata.fft_num);
    is_valid = false;
end

if metadata.sampling_freq_hz <= 0 || metadata.sampling_freq_hz > 1000000
    warning('Sampling frequency out of expected range: %f Hz', metadata.sampling_freq_hz);
    is_valid = false;
end

end