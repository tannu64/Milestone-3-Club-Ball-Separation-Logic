
function impact_events = detect_impact_events(iq_data, config)
%% Detect Impact Events Using Energy Burst Analysis
% Energy burst detection using temporal gradients with multi-channel fusion
%
% Inputs:
%   iq_data - Structure with 4-channel I/Q data (channel1, channel2, raw_data)
%   config - Configuration structure with impact detection parameters
%
% Outputs:
%   impact_events - Structure containing detected impact events and timing

% Validate inputs
if ~isstruct(iq_data)
    error('iq_data must be a structure with I/Q channels');
end

if ~isfield(iq_data, 'channel1') || ~isfield(iq_data, 'channel2')
    error('iq_data must contain channel1 and channel2 fields');
end

if ~isfield(config, 'energy_gradient_threshold')
    config.energy_gradient_threshold = 7.0;  % α = 7.0 from spec
end

if ~isfield(config, 'analysis_window_ms')
    config.analysis_window_ms = 20;  % ±10 ms window
end

if ~isfield(config, 'min_impact_duration_ms')
    config.min_impact_duration_ms = 0.3;  % Physical constraint
end

if ~isfield(config, 'channel_fusion_weights')
    config.channel_fusion_weights = [0.25, 0.25, 0.25, 0.25];  % Equal weights
end

% Extract sampling rate
if isfield(iq_data, 'sampling_rate')
    fs = iq_data.sampling_rate;
else
    fs = 22700;  % Default from dataset
end

% Create STFT configuration
stft_config = struct();
stft_config.fft_size = 1024;
stft_config.overlap_percent = 75;
stft_config.window_type = 'hamming';
stft_config.zero_padding_factor = 2;
stft_config.sampling_rate = fs;

% Compute STFT for each I/Q channel
fprintf('Computing STFT for impact detection...\n');

% Channel 1 (IF1)
stft_ch1 = compute_stft_spectrogram(iq_data.channel1, stft_config);
energy_ch1 = stft_ch1.spectral_energy;

% Channel 2 (IF2) 
stft_ch2 = compute_stft_spectrogram(iq_data.channel2, stft_config);
energy_ch2 = stft_ch2.spectral_energy;

% Extract raw channels for 4-channel processing
if isfield(iq_data, 'raw_data') && size(iq_data.raw_data, 1) == 4
    % Process individual raw channels
    if1_upper = iq_data.raw_data(1, :);
    if1_lower = iq_data.raw_data(2, :);
    if2_upper = iq_data.raw_data(3, :);
    if2_lower = iq_data.raw_data(4, :);
    
    % Compute STFT for raw channels
    stft_if1_upper = compute_stft_spectrogram(if1_upper, stft_config);
    stft_if1_lower = compute_stft_spectrogram(if1_lower, stft_config);
    stft_if2_upper = compute_stft_spectrogram(if2_upper, stft_config);
    stft_if2_lower = compute_stft_spectrogram(if2_lower, stft_config);
    
    energy_if1_upper = stft_if1_upper.spectral_energy;
    energy_if1_lower = stft_if1_lower.spectral_energy;
    energy_if2_upper = stft_if2_upper.spectral_energy;
    energy_if2_lower = stft_if2_lower.spectral_energy;
else
    % Use complex channels as fallback
    energy_if1_upper = energy_ch1;
    energy_if1_lower = energy_ch1;
    energy_if2_upper = energy_ch2;
    energy_if2_lower = energy_ch2;
end

% Multi-channel energy fusion
% E_fused(t) = Σ w_c × E_c(t) with equal weights [0.25, 0.25, 0.25, 0.25]
w = config.channel_fusion_weights;
fused_energy = w(1) * energy_if1_upper + w(2) * energy_if1_lower + ...
               w(3) * energy_if2_upper + w(4) * energy_if2_lower;

% Time axis from STFT
time_axis = stft_ch1.time_axis;
dt = time_axis(2) - time_axis(1);  % Time step

% Compute temporal energy gradient
% ∇E(t) = [E(t+Δt) - E(t-Δt)] / (2Δt)
energy_gradient = zeros(size(fused_energy));
for i = 2:length(fused_energy)-1
    energy_gradient(i) = (fused_energy(i+1) - fused_energy(i-1)) / (2 * dt);
end

% Handle boundary conditions
energy_gradient(1) = (fused_energy(2) - fused_energy(1)) / dt;
energy_gradient(end) = (fused_energy(end) - fused_energy(end-1)) / dt;

% Estimate noise standard deviation from quiet regions
% Use first and last 10% of signal as noise estimate
noise_samples = round(0.1 * length(fused_energy));
noise_energy = [fused_energy(1:noise_samples), fused_energy(end-noise_samples+1:end)];
sigma_noise = std(noise_energy);

% Impact detection criterion: ∇E(t) > α × σ_noise
alpha = config.energy_gradient_threshold;  % α = 7.0
detection_threshold = alpha * sigma_noise;

% Find impact candidates
impact_candidates = find(energy_gradient > detection_threshold);

% Filter candidates based on minimum impact duration
min_duration_samples = round(config.min_impact_duration_ms * fs / 1000);
analysis_window_samples = round(config.analysis_window_ms * fs / 1000);

% Group nearby detections and validate duration
valid_impacts = [];
if ~isempty(impact_candidates)
    % Group consecutive detections
    groups = {};
    current_group = impact_candidates(1);
    
    for i = 2:length(impact_candidates)
        if impact_candidates(i) - impact_candidates(i-1) <= analysis_window_samples
            current_group = [current_group, impact_candidates(i)];
        else
            groups{end+1} = current_group;
            current_group = impact_candidates(i);
        end
    end
    groups{end+1} = current_group;  % Add last group
    
    % Validate each group
    for g = 1:length(groups)
        group = groups{g};
        duration_samples = length(group);
        
        if duration_samples >= min_duration_samples
            % Find peak gradient in group
            [~, peak_idx] = max(energy_gradient(group));
            impact_time_idx = group(peak_idx);
            impact_time = time_axis(impact_time_idx);
            peak_gradient = energy_gradient(impact_time_idx);
            
            valid_impacts = [valid_impacts; [impact_time_idx, impact_time, peak_gradient]];
        end
    end
end

% Create output structure
impact_events = struct();
impact_events.num_impacts = size(valid_impacts, 1);
impact_events.impact_times = [];
impact_events.impact_indices = [];
impact_events.peak_gradients = [];

if impact_events.num_impacts > 0
    impact_events.impact_indices = valid_impacts(:, 1);
    impact_events.impact_times = valid_impacts(:, 2);
    impact_events.peak_gradients = valid_impacts(:, 3);
end

% Store analysis data
impact_events.fused_energy = fused_energy;
impact_events.energy_gradient = energy_gradient;
impact_events.time_axis = time_axis;
impact_events.detection_threshold = detection_threshold;
impact_events.sigma_noise = sigma_noise;
impact_events.config = config;
impact_events.channel_energies = struct();
impact_events.channel_energies.if1_upper = energy_if1_upper;
impact_events.channel_energies.if1_lower = energy_if1_lower;
impact_events.channel_energies.if2_upper = energy_if2_upper;
impact_events.channel_energies.if2_lower = energy_if2_lower;

% Log results
fprintf('Impact detection completed:\n');
fprintf('- Detection threshold: %.2e (α=%.1f × σ=%.2e)\n', ...
    detection_threshold, alpha, sigma_noise);
fprintf('- Number of impacts detected: %d\n', impact_events.num_impacts);
if impact_events.num_impacts > 0
    fprintf('- Impact times: ');
    for i = 1:impact_events.num_impacts
        fprintf('%.3fs ', impact_events.impact_times(i));
    end
    fprintf('\n');
end

end