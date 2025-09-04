
function gradient_result = temporal_gradient_analysis(energy_signal, config)
%% Temporal Gradient Analysis
% Compute energy gradients with adaptive thresholds for impact detection

% Validate inputs
if ~isvector(energy_signal)
    error('energy_signal must be a vector');
end

energy_signal = energy_signal(:);  % Ensure column vector

% Default configuration
if nargin < 2 || isempty(config)
    config = struct();
end

if ~isfield(config, 'gradient_method')
    config.gradient_method = 'central_difference';  % Options: 'central_difference', 'forward', 'backward'
end

if ~isfield(config, 'smoothing_window')
    config.smoothing_window = 3;  % Smoothing window size
end

if ~isfield(config, 'adaptive_threshold')
    config.adaptive_threshold = true;
end

if ~isfield(config, 'threshold_factor')
    config.threshold_factor = 7.0;  % α = 7.0 from specification
end

if ~isfield(config, 'noise_estimation_method')
    config.noise_estimation_method = 'percentile';  % Options: 'std', 'percentile', 'mad'
end

if ~isfield(config, 'sampling_rate')
    config.sampling_rate = 22700;  % Default sampling rate
end

fprintf('Computing temporal energy gradients using %s method...\n', config.gradient_method);

%% Pre-processing: Smoothing (if requested)
if config.smoothing_window > 1
    % Apply smoothing to reduce noise
    smoothed_energy = movmean(energy_signal, config.smoothing_window);
    fprintf('Applied smoothing with window size: %d\n', config.smoothing_window);
else
    smoothed_energy = energy_signal;
end

%% Compute Temporal Gradient
% ∇E(t) = [E(t+Δt) - E(t-Δt)] / (2Δt)

N = length(smoothed_energy);
dt = 1 / config.sampling_rate;  % Time step

switch lower(config.gradient_method)
    case 'central_difference'
        % Central difference: ∇E(t) = [E(t+1) - E(t-1)] / (2Δt)
        energy_gradient = zeros(N, 1);
        
        % Interior points
        for i = 2:N-1
            energy_gradient(i) = (smoothed_energy(i+1) - smoothed_energy(i-1)) / (2 * dt);
        end
        
        % Boundary conditions
        energy_gradient(1) = (smoothed_energy(2) - smoothed_energy(1)) / dt;  % Forward difference
        energy_gradient(N) = (smoothed_energy(N) - smoothed_energy(N-1)) / dt;  % Backward difference
        
    case 'forward'
        % Forward difference: ∇E(t) = [E(t+1) - E(t)] / Δt
        energy_gradient = zeros(N, 1);
        
        for i = 1:N-1
            energy_gradient(i) = (smoothed_energy(i+1) - smoothed_energy(i)) / dt;
        end
        energy_gradient(N) = energy_gradient(N-1);  % Extrapolate last point
        
    case 'backward'
        % Backward difference: ∇E(t) = [E(t) - E(t-1)] / Δt
        energy_gradient = zeros(N, 1);
        
        energy_gradient(1) = 0;  % First point
        for i = 2:N
            energy_gradient(i) = (smoothed_energy(i) - smoothed_energy(i-1)) / dt;
        end
        
    otherwise
        error('Unknown gradient method: %s', config.gradient_method);
end

%% Noise Estimation and Adaptive Thresholding
if config.adaptive_threshold
    % Estimate noise level in the gradient signal
    switch lower(config.noise_estimation_method)
        case 'std'
            % Standard deviation of gradient (assuming most is noise)
            sigma_noise = std(energy_gradient);
            
        case 'percentile'
            % Use percentile-based robust noise estimation
            % Assume 90% of the signal is noise, 10% is signal+noise
            abs_gradient = abs(energy_gradient);
            sigma_noise = prctile(abs_gradient, 75);  % 75th percentile as noise level
            
        case 'mad'
            % Median Absolute Deviation (robust to outliers)
            median_gradient = median(energy_gradient);
            mad_gradient = median(abs(energy_gradient - median_gradient));
            sigma_noise = 1.4826 * mad_gradient;  % Scale factor for normal distribution
            
        otherwise
            sigma_noise = std(energy_gradient);
    end
    
    % Adaptive threshold: α × σ_noise
    detection_threshold = config.threshold_factor * sigma_noise;
    
    fprintf('Noise level (σ): %.2e\n', sigma_noise);
    fprintf('Detection threshold (%.1fσ): %.2e\n', config.threshold_factor, detection_threshold);
    
else
    % Fixed threshold (if provided)
    if isfield(config, 'fixed_threshold')
        detection_threshold = config.fixed_threshold;
        sigma_noise = detection_threshold / config.threshold_factor;
    else
        error('Fixed threshold must be provided when adaptive_threshold is false');
    end
end

%% Impact Detection Based on Gradient
% Impact detected when: ∇E(t) > α × σ_noise

positive_detections = energy_gradient > detection_threshold;
negative_detections = energy_gradient < -detection_threshold;  % Also check negative spikes

% Find detection indices
positive_detection_indices = find(positive_detections);
negative_detection_indices = find(negative_detections);
all_detection_indices = sort([positive_detection_indices; negative_detection_indices]);

%% Post-processing: Group nearby detections
if ~isempty(all_detection_indices)
    % Group detections that are close together (within min_separation samples)
    min_separation_samples = round(0.001 * config.sampling_rate);  % 1ms minimum separation
    
    grouped_detections = [];
    current_group = all_detection_indices(1);
    
    for i = 2:length(all_detection_indices)
        if all_detection_indices(i) - current_group(end) <= min_separation_samples
            % Add to current group
            current_group = [current_group; all_detection_indices(i)];
        else
            % Start new group, but first process current group
            % Take the detection with maximum absolute gradient in the group
            [~, max_idx] = max(abs(energy_gradient(current_group)));
            grouped_detections = [grouped_detections; current_group(max_idx)];
            
            current_group = all_detection_indices(i);
        end
    end
    
    % Process final group
    [~, max_idx] = max(abs(energy_gradient(current_group)));
    grouped_detections = [grouped_detections; current_group(max_idx)];
    
    detection_indices = grouped_detections;
else
    detection_indices = [];
end

%% Gradient Quality Assessment
gradient_quality = struct();

% Signal-to-noise ratio in gradient domain
if sigma_noise > 0
    max_gradient = max(abs(energy_gradient));
    gradient_snr = 20 * log10(max_gradient / sigma_noise);
    gradient_quality.snr_db = gradient_snr;
else
    gradient_quality.snr_db = inf;
end

% Dynamic range
gradient_quality.dynamic_range = max(energy_gradient) - min(energy_gradient);
gradient_quality.max_positive_gradient = max(energy_gradient);
gradient_quality.max_negative_gradient = min(energy_gradient);

% Detection statistics
gradient_quality.num_detections = length(detection_indices);
gradient_quality.detection_rate = length(detection_indices) / (N * dt);  % Detections per second

% Gradient statistics
gradient_quality.gradient_mean = mean(energy_gradient);
gradient_quality.gradient_std = std(energy_gradient);
gradient_quality.gradient_rms = sqrt(mean(energy_gradient.^2));

%% Create Output Structure
gradient_result = struct();
gradient_result.energy_gradient = energy_gradient;
gradient_result.smoothed_energy = smoothed_energy;
gradient_result.detection_threshold = detection_threshold;
gradient_result.sigma_noise = sigma_noise;
gradient_result.detection_indices = detection_indices;
gradient_result.positive_detections = positive_detections;
gradient_result.negative_detections = negative_detections;
gradient_result.gradient_quality = gradient_quality;
gradient_result.config = config;

% Add time axis
gradient_result.time_axis = (0:N-1) / config.sampling_rate;

% Convert detection indices to times
if ~isempty(detection_indices)
    gradient_result.detection_times = (detection_indices - 1) / config.sampling_rate;
else
    gradient_result.detection_times = [];
end

%% Summary Report
fprintf('\n=== Temporal Gradient Analysis Summary ===\n');
fprintf('Gradient method: %s\n', config.gradient_method);
fprintf('Noise estimation: %s\n', config.noise_estimation_method);
fprintf('Signal length: %.3f seconds (%d samples)\n', N/config.sampling_rate, N);

fprintf('\nGradient Statistics:\n');
fprintf('Max gradient: %+.2e\n', gradient_quality.max_positive_gradient);
fprintf('Min gradient: %+.2e\n', gradient_quality.max_negative_gradient);
fprintf('RMS gradient: %.2e\n', gradient_quality.gradient_rms);
fprintf('SNR: %.1f dB\n', gradient_quality.snr_db);

fprintf('\nDetection Results:\n');
fprintf('Detection threshold: %.2e\n', detection_threshold);
fprintf('Detections found: %d\n', gradient_quality.num_detections);

if gradient_quality.num_detections > 0
    fprintf('Detection times: ');
    for i = 1:min(5, length(gradient_result.detection_times))  % Show first 5
        fprintf('%.3fs ', gradient_result.detection_times(i));
    end
    if length(gradient_result.detection_times) > 5
        fprintf('... (%d more)', length(gradient_result.detection_times) - 5);
    end
    fprintf('\n');
    
    fprintf('Detection rate: %.1f per second\n', gradient_quality.detection_rate);
end

fprintf('Temporal gradient analysis completed.\n');

end