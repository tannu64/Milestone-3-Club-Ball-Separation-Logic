
function velocity_data = doppler_to_velocity(stft_result, metadata)
%% Convert Doppler Frequencies to Velocity (mph)
% Convert doppler frequencies to mph using speed coefficient from dataset
%
% Inputs:
%   stft_result - STFT result structure from compute_stft_spectrogram
%   metadata - Metadata structure containing speed coefficient
%
% Outputs:
%   velocity_data - Structure containing velocity measurements and analysis

% Validate inputs
if ~isstruct(stft_result)
    error('stft_result must be a structure from compute_stft_spectrogram');
end

if ~isfield(stft_result, 'stft_matrix') || ~isfield(stft_result, 'freq_axis')
    error('stft_result must contain stft_matrix and freq_axis fields');
end

if ~isstruct(metadata)
    error('metadata must be a structure');
end

% Extract speed coefficient from metadata
if isfield(metadata, 'speed_coef')
    speed_coef = metadata.speed_coef;
elseif isfield(metadata, 'speed_coefficient')
    speed_coef = metadata.speed_coefficient;
else
    speed_coef = 0.1388888888888889;  % Default from dataset schema
    warning('Using default speed coefficient: %.12f', speed_coef);
end

% Validate speed coefficient
if isnan(speed_coef) || speed_coef <= 0
    error('Invalid speed coefficient: %f', speed_coef);
end

% Extract STFT data
stft_matrix = stft_result.stft_matrix;
freq_axis = stft_result.freq_axis;
time_axis = stft_result.time_axis;

% Convert Doppler frequencies to velocities
% velocity = doppler_frequency × speed_coefficient
velocity_axis = freq_axis * speed_coef;

% Compute magnitude spectrogram for velocity analysis
magnitude_spectrogram = abs(stft_matrix);

% Find peak velocities at each time frame
num_frames = size(stft_matrix, 2);
peak_velocities = zeros(1, num_frames);
peak_frequencies = zeros(1, num_frames);
peak_magnitudes = zeros(1, num_frames);

for frame_idx = 1:num_frames
    frame_magnitude = magnitude_spectrogram(:, frame_idx);
    
    % Find peak in magnitude spectrum
    [peak_mag, peak_freq_idx] = max(frame_magnitude);
    
    peak_magnitudes(frame_idx) = peak_mag;
    peak_frequencies(frame_idx) = freq_axis(peak_freq_idx);
    peak_velocities(frame_idx) = velocity_axis(peak_freq_idx);
end

% Smooth velocity measurements to reduce noise
% Use simple moving average filter
window_size = 5;  % Small window to preserve transients
if length(peak_velocities) >= window_size
    smoothed_velocities = movmean(peak_velocities, window_size);
else
    smoothed_velocities = peak_velocities;
end

% Detect velocity tracks using simple peak detection
% This will be used for club/ball separation
velocity_threshold = 5.0;  % Minimum velocity in mph to consider valid
valid_frames = abs(smoothed_velocities) > velocity_threshold;

% Extract continuous velocity segments
velocity_segments = [];
if any(valid_frames)
    % Find start and end of continuous segments
    segment_starts = find(diff([false, valid_frames]) == 1);
    segment_ends = find(diff([valid_frames, false]) == -1);
    
    for seg_idx = 1:length(segment_starts)
        start_frame = segment_starts(seg_idx);
        end_frame = segment_ends(seg_idx);
        
        if end_frame - start_frame + 1 >= 3  % Minimum 3 frames for valid segment
            segment = struct();
            segment.start_time = time_axis(start_frame);
            segment.end_time = time_axis(end_frame);
            segment.start_frame = start_frame;
            segment.end_frame = end_frame;
            segment.velocities = smoothed_velocities(start_frame:end_frame);
            segment.times = time_axis(start_frame:end_frame);
            segment.max_velocity = max(abs(segment.velocities));
            segment.duration = segment.end_time - segment.start_time;
            
            velocity_segments = [velocity_segments; segment];
        end
    end
end

% Create output structure
velocity_data = struct();
velocity_data.velocity_axis = velocity_axis;
velocity_data.peak_velocities = peak_velocities;
velocity_data.smoothed_velocities = smoothed_velocities;
velocity_data.peak_frequencies = peak_frequencies;
velocity_data.peak_magnitudes = peak_magnitudes;
velocity_data.time_axis = time_axis;
velocity_data.magnitude_spectrogram = magnitude_spectrogram;
velocity_data.velocity_segments = velocity_segments;
velocity_data.num_segments = length(velocity_segments);
velocity_data.speed_coefficient = speed_coef;
velocity_data.velocity_threshold = velocity_threshold;

% Add velocity statistics
if ~isempty(peak_velocities)
    velocity_data.max_velocity = max(abs(peak_velocities));
    velocity_data.mean_velocity = mean(abs(peak_velocities(abs(peak_velocities) > velocity_threshold)));
    velocity_data.velocity_range = [min(peak_velocities), max(peak_velocities)];
else
    velocity_data.max_velocity = 0;
    velocity_data.mean_velocity = 0;
    velocity_data.velocity_range = [0, 0];
end

% Log conversion results
fprintf('Doppler to velocity conversion completed:\n');
fprintf('- Speed coefficient: %.12f\n', speed_coef);
fprintf('- Velocity range: %.1f to %.1f mph\n', velocity_data.velocity_range(1), velocity_data.velocity_range(2));
fprintf('- Maximum velocity: %.1f mph\n', velocity_data.max_velocity);
fprintf('- Number of velocity segments: %d\n', velocity_data.num_segments);

if velocity_data.num_segments > 0
    fprintf('- Segment durations: ');
    for i = 1:min(5, velocity_data.num_segments)  % Show first 5 segments
        fprintf('%.3fs ', velocity_segments(i).duration);
    end
    if velocity_data.num_segments > 5
        fprintf('...');
    end
    fprintf('\n');
end

end