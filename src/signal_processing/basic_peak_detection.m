
function peak_result = basic_peak_detection(signal_data, config)
%% Basic Peak Detection
% Simple Peak Finding in velocity domain

% Validate inputs
if ~isvector(signal_data)
    error('signal_data must be a vector');
end

signal_data = signal_data(:);  % Ensure column vector

% Default configuration
if nargin < 2 || isempty(config)
    config = struct();
end

if ~isfield(config, 'min_peak_height')
    config.min_peak_height = 0.1;  % Minimum relative peak height
end

if ~isfield(config, 'min_peak_distance')
    config.min_peak_distance = 5;  % Minimum distance between peaks (samples)
end

if ~isfield(config, 'peak_prominence')
    config.peak_prominence = 0.05;  % Minimum peak prominence
end

if ~isfield(config, 'smoothing_window')
    config.smoothing_window = 3;  % Smoothing window size
end

if ~isfield(config, 'use_absolute_values')
    config.use_absolute_values = true;  % Use absolute values for peak detection
end

fprintf('Performing basic peak detection on signal of length %d...\n', length(signal_data));

%% Pre-processing
% Apply smoothing if requested
if config.smoothing_window > 1
    smoothed_signal = movmean(signal_data, config.smoothing_window);
else
    smoothed_signal = signal_data;
end

% Use absolute values if requested (common for velocity magnitude detection)
if config.use_absolute_values
    detection_signal = abs(smoothed_signal);
else
    detection_signal = smoothed_signal;
end

%% Peak Detection Algorithm
N = length(detection_signal);

% Initialize peak detection
peak_indices = [];
peak_values = [];
peak_prominences = [];

% Adaptive threshold based on signal statistics
signal_mean = mean(detection_signal);
signal_std = std(detection_signal);
signal_max = max(detection_signal);

% Set minimum height threshold
if signal_max > 0
    min_height_threshold = max(config.min_peak_height * signal_max, signal_mean + signal_std);
else
    min_height_threshold = config.min_peak_height;
end

fprintf('Peak detection threshold: %.3f\n', min_height_threshold);

%% Simple Peak Finding Algorithm
for i = 2:N-1
    current_value = detection_signal(i);
    
    % Check if current point is a local maximum
    if current_value > detection_signal(i-1) && current_value > detection_signal(i+1)
        % Check height threshold
        if current_value >= min_height_threshold
            % Check minimum distance from existing peaks
            if isempty(peak_indices) || min(abs(peak_indices - i)) >= config.min_peak_distance
                % Calculate prominence
                prominence = calculate_peak_prominence(detection_signal, i);
                
                % Check prominence threshold
                if prominence >= config.peak_prominence * signal_max
                    peak_indices = [peak_indices; i];
                    peak_values = [peak_values; current_value];
                    peak_prominences = [peak_prominences; prominence];
                end
            end
        end
    end
end

%% Post-processing: Sort peaks by height
if ~isempty(peak_indices)
    [sorted_values, sort_idx] = sort(peak_values, 'descend');
    peak_indices = peak_indices(sort_idx);
    peak_values = sorted_values;
    peak_prominences = peak_prominences(sort_idx);
end

%% Peak Quality Assessment
peak_quality = struct();
peak_quality.num_peaks = length(peak_indices);
peak_quality.signal_length = N;
peak_quality.peak_density = length(peak_indices) / N;

if ~isempty(peak_values)
    peak_quality.max_peak_value = max(peak_values);
    peak_quality.min_peak_value = min(peak_values);
    peak_quality.mean_peak_value = mean(peak_values);
    peak_quality.peak_value_std = std(peak_values);
    peak_quality.peak_value_range = max(peak_values) - min(peak_values);
    
    % Peak spacing analysis
    if length(peak_indices) > 1
        peak_spacings = diff(sort(peak_indices));
        peak_quality.mean_peak_spacing = mean(peak_spacings);
        peak_quality.min_peak_spacing = min(peak_spacings);
        peak_quality.peak_spacing_std = std(peak_spacings);
    end
    
    % Prominence statistics
    peak_quality.mean_prominence = mean(peak_prominences);
    peak_quality.max_prominence = max(peak_prominences);
    peak_quality.min_prominence = min(peak_prominences);
end

%% Create Peak Information Structure
peak_info = [];
for i = 1:length(peak_indices)
    peak_struct = struct();
    peak_struct.index = peak_indices(i);
    peak_struct.value = peak_values(i);
    peak_struct.prominence = peak_prominences(i);
    peak_struct.original_value = signal_data(peak_indices(i));  % Original signal value
    
    % Calculate peak width (simple estimate)
    peak_width = estimate_peak_width(detection_signal, peak_indices(i));
    peak_struct.width = peak_width;
    
    % Peak quality score
    normalized_height = peak_values(i) / signal_max;
    normalized_prominence = peak_prominences(i) / signal_max;
    peak_struct.quality_score = 0.6 * normalized_height + 0.4 * normalized_prominence;
    
    peak_info = [peak_info; peak_struct];
end

%% Create Output Structure
peak_result = struct();
peak_result.peak_indices = peak_indices;
peak_result.peak_values = peak_values;
peak_result.peak_prominences = peak_prominences;
peak_result.peak_info = peak_info;
peak_result.smoothed_signal = smoothed_signal;
peak_result.detection_signal = detection_signal;
peak_result.peak_quality = peak_quality;
peak_result.config = config;
peak_result.detection_threshold = min_height_threshold;

% Add time axis if sampling rate is provided
if isfield(config, 'sampling_rate')
    peak_result.time_axis = (0:N-1) / config.sampling_rate;
    if ~isempty(peak_indices)
        peak_result.peak_times = (peak_indices - 1) / config.sampling_rate;
    else
        peak_result.peak_times = [];
    end
end

%% Generate Peak Detection Report
fprintf('\n=== Peak Detection Summary ===\n');
fprintf('Signal length: %d samples\n', N);
fprintf('Peaks detected: %d\n', peak_quality.num_peaks);
fprintf('Peak density: %.4f peaks/sample\n', peak_quality.peak_density);

if peak_quality.num_peaks > 0
    fprintf('Peak values: %.3f - %.3f (mean: %.3f)\n', ...
        peak_quality.min_peak_value, peak_quality.max_peak_value, peak_quality.mean_peak_value);
    fprintf('Peak prominences: %.3f - %.3f (mean: %.3f)\n', ...
        peak_quality.min_prominence, peak_quality.max_prominence, peak_quality.mean_prominence);
    
    if isfield(peak_quality, 'mean_peak_spacing')
        fprintf('Peak spacing: %.1f ± %.1f samples (min: %d)\n', ...
            peak_quality.mean_peak_spacing, peak_quality.peak_spacing_std, peak_quality.min_peak_spacing);
    end
    
    % Show top peaks
    num_show = min(5, length(peak_info));
    fprintf('\nTop %d peaks:\n', num_show);
    for i = 1:num_show
        peak = peak_info(i);
        fprintf('  Peak %d: Index %d, Value %.3f, Prominence %.3f, Quality %.3f\n', ...
            i, peak.index, peak.value, peak.prominence, peak.quality_score);
    end
end

fprintf('Basic peak detection completed.\n');

end

function prominence = calculate_peak_prominence(signal, peak_idx)
%% Calculate Peak Prominence
% Prominence is the minimum height difference between the peak and the lowest contour line

N = length(signal);
peak_value = signal(peak_idx);

% Find left minimum
left_min = peak_value;
for i = peak_idx-1:-1:1
    if signal(i) < left_min
        left_min = signal(i);
    end
    if i > 1 && signal(i) > signal(i-1)  % Found a higher point going left
        break;
    end
end

% Find right minimum
right_min = peak_value;
for i = peak_idx+1:N
    if signal(i) < right_min
        right_min = signal(i);
    end
    if i < N && signal(i) > signal(i+1)  % Found a higher point going right
        break;
    end
end

% Prominence is height above the higher of the two minima
prominence = peak_value - max(left_min, right_min);

end

function width = estimate_peak_width(signal, peak_idx)
%% Estimate Peak Width at Half Maximum

N = length(signal);
peak_value = signal(peak_idx);

% Find half maximum level
half_max = peak_value / 2;

% Find left half-maximum point
left_idx = peak_idx;
for i = peak_idx-1:-1:1
    if signal(i) <= half_max
        left_idx = i;
        break;
    end
end

% Find right half-maximum point
right_idx = peak_idx;
for i = peak_idx+1:N
    if signal(i) <= half_max
        right_idx = i;
        break;
    end
end

% Width in samples
width = right_idx - left_idx + 1;

end