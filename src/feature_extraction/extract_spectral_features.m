
function spectral_features = extract_spectral_features(stft_result, velocity_data, config)
%% Extract Spectral Features for Club/Ball Classification
% Spectral width, bandwidth analysis for 7D feature vector
%
% Inputs:
%   stft_result - STFT result structure from compute_stft_spectrogram
%   velocity_data - Velocity data with segments for analysis
%   config - Configuration structure with spectral analysis parameters
%
% Outputs:
%   spectral_features - Structure containing spectral-based features

% Validate inputs
if ~isstruct(stft_result)
    error('stft_result must be a structure from compute_stft_spectrogram');
end

if ~isfield(stft_result, 'stft_matrix') || ~isfield(stft_result, 'freq_axis')
    error('stft_result must contain stft_matrix and freq_axis fields');
end

if ~isstruct(velocity_data)
    error('velocity_data must be a structure');
end

% Default configuration parameters
if ~isfield(config, 'spectral_width_broad_hz')
    config.spectral_width_broad_hz = 50;  % Hz threshold for club (extended contact)
end

if ~isfield(config, 'spectral_width_narrow_hz')
    config.spectral_width_narrow_hz = 20;  % Hz threshold for ball (point target)
end

% Extract STFT data
stft_matrix = stft_result.stft_matrix;
freq_axis = stft_result.freq_axis;
time_axis = stft_result.time_axis;

% Compute magnitude spectrogram
magnitude_spectrogram = abs(stft_matrix);
power_spectrogram = magnitude_spectrogram.^2;

% Get velocity segments for targeted analysis
if isfield(velocity_data, 'velocity_segments')
    velocity_segments = velocity_data.velocity_segments;
else
    % Create single segment covering entire signal if no segments available
    velocity_segments = struct();
    velocity_segments.start_time = time_axis(1);
    velocity_segments.end_time = time_axis(end);
    velocity_segments.start_frame = 1;
    velocity_segments.end_frame = length(time_axis);
    velocity_segments = [velocity_segments];
end

num_segments = length(velocity_segments);
features = [];

fprintf('Extracting spectral features from %d segments...\n', num_segments);

for seg_idx = 1:num_segments
    segment = velocity_segments(seg_idx);
    
    % Find time frames corresponding to this velocity segment
    start_time = segment.start_time;
    end_time = segment.end_time;
    
    % Map to STFT time frames
    [~, start_frame] = min(abs(time_axis - start_time));
    [~, end_frame] = min(abs(time_axis - end_time));
    
    if start_frame >= end_frame || end_frame > length(time_axis)
        continue;  % Skip invalid segments
    end
    
    % Extract segment data
    segment_power = power_spectrogram(:, start_frame:end_frame);
    segment_magnitude = magnitude_spectrogram(:, start_frame:end_frame);
    
    % Compute average power spectrum for this segment
    avg_power_spectrum = mean(segment_power, 2);
    
    % Spectral width calculation
    % W_s = sqrt(Σf²|X(f)|² / Σ|X(f)|²)
    total_power = sum(avg_power_spectrum);
    
    if total_power > 0
        % Compute weighted frequency moments
        freq_squared_weighted = sum((freq_axis(:).^2) .* avg_power_spectrum) / total_power;
        freq_weighted = sum(freq_axis(:) .* avg_power_spectrum) / total_power;
        
        % Spectral width (standard deviation of frequency)
        spectral_width = sqrt(freq_squared_weighted - freq_weighted^2);
    else
        spectral_width = 0;
        freq_weighted = 0;
    end
    
    % Peak frequency and bandwidth analysis
    [peak_power, peak_freq_idx] = max(avg_power_spectrum);
    peak_frequency = freq_axis(peak_freq_idx);
    
    % Compute 3dB bandwidth
    half_power = peak_power / 2;
    above_half_power = avg_power_spectrum >= half_power;
    
    if any(above_half_power)
        freq_indices = find(above_half_power);
        bandwidth_3db = freq_axis(freq_indices(end)) - freq_axis(freq_indices(1));
    else
        bandwidth_3db = 0;
    end
    
    % Spectral centroid (center of mass of spectrum)
    if total_power > 0
        spectral_centroid = sum(freq_axis(:) .* avg_power_spectrum) / total_power;
    else
        spectral_centroid = 0;
    end
    
    % Spectral spread (second moment around centroid)
    if total_power > 0
        spectral_spread = sqrt(sum(((freq_axis(:) - spectral_centroid).^2) .* avg_power_spectrum) / total_power);
    else
        spectral_spread = 0;
    end
    
    % Spectral rolloff (frequency below which 85% of energy lies)
    if total_power > 0
        cumulative_power = cumsum(avg_power_spectrum) / total_power;
        rolloff_idx = find(cumulative_power >= 0.85, 1, 'first');
        if ~isempty(rolloff_idx)
            spectral_rolloff = freq_axis(rolloff_idx);
        else
            spectral_rolloff = freq_axis(end);
        end
    else
        spectral_rolloff = 0;
    end
    
    % Classification based on spectral width
    % Club: W_s > 50 Hz (extended contact, broad spectrum)
    % Ball: W_s < 20 Hz (point target, narrow spectrum)
    if spectral_width > config.spectral_width_broad_hz
        spectral_type_hint = 'club';
    elseif spectral_width < config.spectral_width_narrow_hz
        spectral_type_hint = 'ball';
    else
        spectral_type_hint = 'uncertain';
    end
    
    % Store features for this segment
    segment_features = struct();
    segment_features.segment_idx = seg_idx;
    segment_features.spectral_width = spectral_width;
    segment_features.peak_frequency = peak_frequency;
    segment_features.bandwidth_3db = bandwidth_3db;
    segment_features.spectral_centroid = spectral_centroid;
    segment_features.spectral_spread = spectral_spread;
    segment_features.spectral_rolloff = spectral_rolloff;
    segment_features.total_power = total_power;
    segment_features.peak_power = peak_power;
    segment_features.spectral_type_hint = spectral_type_hint;
    segment_features.start_time = start_time;
    segment_features.end_time = end_time;
    segment_features.duration = end_time - start_time;
    
    % Add to features array
    features = [features; segment_features];
end

% Create output structure
spectral_features = struct();
spectral_features.num_tracks = length(features);
spectral_features.features = features;
spectral_features.config = config;

% Compute overall statistics
if spectral_features.num_tracks > 0
    all_spectral_widths = [features.spectral_width];
    all_peak_frequencies = [features.peak_frequency];
    all_bandwidths = [features.bandwidth_3db];
    
    spectral_features.spectral_statistics = struct();
    spectral_features.spectral_statistics.spectral_width_range = [min(all_spectral_widths), max(all_spectral_widths)];
    spectral_features.spectral_statistics.mean_spectral_width = mean(all_spectral_widths);
    spectral_features.spectral_statistics.peak_frequency_range = [min(all_peak_frequencies), max(all_peak_frequencies)];
    spectral_features.spectral_statistics.bandwidth_range = [min(all_bandwidths), max(all_bandwidths)];
    
    % Count classification hints
    spectral_hints = {features.spectral_type_hint};
    club_hints = sum(strcmp(spectral_hints, 'club'));
    ball_hints = sum(strcmp(spectral_hints, 'ball'));
    uncertain_hints = sum(strcmp(spectral_hints, 'uncertain'));
    
    spectral_features.classification_hints = struct();
    spectral_features.classification_hints.club_tracks = club_hints;
    spectral_features.classification_hints.ball_tracks = ball_hints;
    spectral_features.classification_hints.uncertain_tracks = uncertain_hints;
end

% Log spectral feature extraction results
fprintf('Spectral feature extraction completed:\n');
fprintf('- Number of tracks analyzed: %d\n', spectral_features.num_tracks);

if spectral_features.num_tracks > 0
    fprintf('- Spectral width range: %.1f - %.1f Hz\n', ...
        min(all_spectral_widths), max(all_spectral_widths));
    fprintf('- Peak frequency range: %.1f - %.1f Hz\n', ...
        min(all_peak_frequencies), max(all_peak_frequencies));
    fprintf('- 3dB bandwidth range: %.1f - %.1f Hz\n', ...
        min(all_bandwidths), max(all_bandwidths));
    fprintf('- Classification hints: %d club, %d ball, %d uncertain\n', ...
        club_hints, ball_hints, uncertain_hints);
end

end