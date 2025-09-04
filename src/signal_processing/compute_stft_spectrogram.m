
function [stft_result, time_axis, freq_axis] = compute_stft_spectrogram(iq_data, config)
%% Compute STFT Spectrogram for Impact Detection
% Sliding window STFT optimized for impact detection using specified parameters
%
% Inputs:
%   iq_data - Complex I/Q data (single channel)
%   config - Configuration structure with STFT parameters
%
% Outputs:
%   stft_result - STFT matrix (frequency x time)
%   time_axis - Time axis for STFT frames
%   freq_axis - Frequency axis for STFT bins

% Validate inputs
if ~isnumeric(iq_data) || ~isvector(iq_data)
    error('iq_data must be a numeric vector');
end

if ~isfield(config, 'fft_size')
    config.fft_size = 1024;
end

if ~isfield(config, 'overlap_percent')
    config.overlap_percent = 75;
end

if ~isfield(config, 'window_type')
    config.window_type = 'hamming';
end

if ~isfield(config, 'zero_padding_factor')
    config.zero_padding_factor = 2;
end

if ~isfield(config, 'sampling_rate')
    error('Configuration must include sampling_rate');
end

% STFT parameters from technical specification
fft_size = config.fft_size;                    % 1024 points
overlap_percent = config.overlap_percent;      % 75% overlap
window_size = fft_size;
hop_size = round(window_size * (1 - overlap_percent/100));
zero_pad_size = fft_size * config.zero_padding_factor;

% Create window function
switch lower(config.window_type)
    case 'hamming'
        window = hamming(window_size);
    case 'hann'
        window = hann(window_size);
    case 'blackman'
        window = blackman(window_size);
    otherwise
        window = hamming(window_size);
        warning('Unknown window type, using Hamming');
end

% Ensure iq_data is column vector
if isrow(iq_data)
    iq_data = iq_data(:);
end

% Calculate number of frames
signal_length = length(iq_data);
num_frames = floor((signal_length - window_size) / hop_size) + 1;

% Initialize STFT matrix
stft_matrix = zeros(zero_pad_size, num_frames);

% Compute STFT
for frame_idx = 1:num_frames
    % Extract frame
    start_idx = (frame_idx - 1) * hop_size + 1;
    end_idx = start_idx + window_size - 1;
    
    if end_idx > signal_length
        break;
    end
    
    frame_data = iq_data(start_idx:end_idx);
    
    % Apply window
    windowed_frame = frame_data .* window;
    
    % Zero pad if needed
    if zero_pad_size > window_size
        padded_frame = [windowed_frame; zeros(zero_pad_size - window_size, 1)];
    else
        padded_frame = windowed_frame;
    end
    
    % Compute FFT
    fft_frame = fft(padded_frame, zero_pad_size);
    
    % Store in STFT matrix
    stft_matrix(:, frame_idx) = fft_frame;
end

% Create time axis
time_step = hop_size / config.sampling_rate;
time_axis = (0:num_frames-1) * time_step;

% Create frequency axis
freq_step = config.sampling_rate / zero_pad_size;
freq_axis = (0:zero_pad_size-1) * freq_step;

% Shift frequency axis to center around 0
if zero_pad_size > 1
    freq_axis = freq_axis - config.sampling_rate/2;
    stft_matrix = fftshift(stft_matrix, 1);
end

% Calculate spectral energy for impact detection
% E(t) = Σ|STFT(f,t)|² across frequency bins
spectral_energy = sum(abs(stft_matrix).^2, 1);

% Store energy in result structure for impact detection
stft_result = struct();
stft_result.stft_matrix = stft_matrix;
stft_result.spectral_energy = spectral_energy;
stft_result.time_axis = time_axis;
stft_result.freq_axis = freq_axis;
stft_result.config = config;
stft_result.num_frames = num_frames;
stft_result.window_size = window_size;
stft_result.hop_size = hop_size;

end