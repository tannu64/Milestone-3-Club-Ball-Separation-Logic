function fusion_result = multi_channel_fusion(iq_data, config)
%% Multi Channel Fusion
% Combine 4 channel I/Q for robust detection

% Validate inputs
if ~isstruct(iq_data)
    error('iq_data must be a structure containing I/Q channels');
end

% Default configuration
if nargin < 2 || isempty(config)
    config = struct();
end

if ~isfield(config, 'fusion_weights')
    config.fusion_weights = [0.25, 0.25, 0.25, 0.25];  % Equal weighting
end

if ~isfield(config, 'fusion_method')
    config.fusion_method = 'weighted_sum';  % Options: 'weighted_sum', 'max', 'rms'
end

if ~isfield(config, 'normalize_channels')
    config.normalize_channels = true;
end

if ~isfield(config, 'energy_computation')
    config.energy_computation = 'magnitude_squared';  % Options: 'magnitude', 'magnitude_squared'
end

fprintf('Performing multi-channel fusion with method: %s\n', config.fusion_method);

%% Extract Channel Data
channels = {'channel1', 'channel2', 'channel3', 'channel4'};
channel_labels = {'IF1_Upper', 'IF1_Lower', 'IF2_Upper', 'IF2_Lower'};
available_channels = {};
channel_data = {};
channel_energies = {};

% Check available channels and extract data
for ch = 1:length(channels)
    if isfield(iq_data, channels{ch}) && ~isempty(iq_data.(channels{ch}))
        available_channels{end+1} = channels{ch};
        channel_data{end+1} = iq_data.(channels{ch});
        
        % Compute channel energy based on configuration
        switch config.energy_computation
            case 'magnitude'
                channel_energies{end+1} = abs(iq_data.(channels{ch}));
            case 'magnitude_squared'
                channel_energies{end+1} = abs(iq_data.(channels{ch})).^2;
            otherwise
                channel_energies{end+1} = abs(iq_data.(channels{ch})).^2;
        end
        
        fprintf('Channel %s: %d samples\n', channel_labels{ch}, length(channel_data{end}));
    else
        fprintf('Channel %s: Not available\n', channel_labels{ch});
    end
end

num_available_channels = length(available_channels);

if num_available_channels == 0
    error('No valid I/Q channels found in input data');
end

%% Align Channel Lengths
% Find minimum length to ensure all channels have same length
min_length = inf;
for ch = 1:num_available_channels
    min_length = min(min_length, length(channel_energies{ch}));
end

% Truncate all channels to minimum length
for ch = 1:num_available_channels
    channel_energies{ch} = channel_energies{ch}(1:min_length);
    channel_data{ch} = channel_data{ch}(1:min_length);
end

fprintf('Aligned all channels to length: %d samples\n', min_length);

%% Normalize Channels (if requested)
if config.normalize_channels
    for ch = 1:num_available_channels
        energy = channel_energies{ch};
        max_energy = max(energy);
        
        if max_energy > 0
            channel_energies{ch} = energy / max_energy;
        else
            channel_energies{ch} = energy;  % Keep zeros as zeros
        end
    end
    fprintf('Normalized channel energies\n');
end

%% Channel Fusion
fusion_weights = config.fusion_weights(1:num_available_channels);
fusion_weights = fusion_weights / sum(fusion_weights);  % Normalize weights

switch lower(config.fusion_method)
    case 'weighted_sum'
        fused_energy = zeros(min_length, 1);
        for ch = 1:num_available_channels
            fused_energy = fused_energy + fusion_weights(ch) * channel_energies{ch};
        end
        
    case 'max'
        % Take maximum across channels at each time point
        energy_matrix = zeros(min_length, num_available_channels);
        for ch = 1:num_available_channels
            energy_matrix(:, ch) = channel_energies{ch};
        end
        fused_energy = max(energy_matrix, [], 2);
        
    case 'rms'
        % Root mean square fusion
        energy_matrix = zeros(min_length, num_available_channels);
        for ch = 1:num_available_channels
            energy_matrix(:, ch) = channel_energies{ch};
        end
        fused_energy = sqrt(mean(energy_matrix.^2, 2));
        
    case 'adaptive'
        % Adaptive fusion based on SNR
        fused_energy = adaptive_fusion(channel_energies, config);
        
    otherwise
        error('Unknown fusion method: %s', config.fusion_method);
end

%% Compute Channel Quality Metrics
channel_quality = struct();
for ch = 1:num_available_channels
    energy = channel_energies{ch};
    
    % Signal quality metrics
    channel_quality.(available_channels{ch}) = struct();
    channel_quality.(available_channels{ch}).mean_energy = mean(energy);
    channel_quality.(available_channels{ch}).max_energy = max(energy);
    channel_quality.(available_channels{ch}).energy_variance = var(energy);
    channel_quality.(available_channels{ch}).dynamic_range = max(energy) - min(energy);
    
    % SNR estimate (simple)
    signal_power = mean(energy);
    noise_floor = prctile(energy, 10);  % 10th percentile as noise estimate
    snr_estimate = 10 * log10(signal_power / max(noise_floor, eps));
    channel_quality.(available_channels{ch}).snr_estimate_db = snr_estimate;
    
    % Contribution to fusion
    if strcmp(config.fusion_method, 'weighted_sum')
        contribution = fusion_weights(ch) * mean(energy) / mean(fused_energy);
        channel_quality.(available_channels{ch}).fusion_contribution = contribution;
    end
end

%% Fusion Quality Assessment
fusion_quality = struct();
fusion_quality.num_channels_used = num_available_channels;
fusion_quality.fusion_method = config.fusion_method;
fusion_quality.fusion_weights = fusion_weights;

% Overall fusion metrics
fusion_quality.fused_energy_mean = mean(fused_energy);
fusion_quality.fused_energy_max = max(fused_energy);
fusion_quality.fused_energy_variance = var(fused_energy);
fusion_quality.dynamic_range = max(fused_energy) - min(fused_energy);

% Fusion effectiveness (how much better than single channel)
if num_available_channels > 1
    best_single_channel_energy = 0;
    for ch = 1:num_available_channels
        single_channel_max = max(channel_energies{ch});
        best_single_channel_energy = max(best_single_channel_energy, single_channel_max);
    end
    
    fusion_improvement = fusion_quality.fused_energy_max / best_single_channel_energy;
    fusion_quality.fusion_improvement_ratio = fusion_improvement;
    
    if fusion_improvement > 1.1
        fusion_quality.fusion_effectiveness = 'good';
    elseif fusion_improvement > 1.05
        fusion_quality.fusion_effectiveness = 'moderate';
    else
        fusion_quality.fusion_effectiveness = 'minimal';
    end
else
    fusion_quality.fusion_improvement_ratio = 1.0;
    fusion_quality.fusion_effectiveness = 'single_channel';
end

%% Create Output Structure
fusion_result = struct();
fusion_result.fused_energy = fused_energy;
fusion_result.num_samples = min_length;
fusion_result.available_channels = available_channels;
fusion_result.channel_data = channel_data;
fusion_result.channel_energies = channel_energies;
fusion_result.channel_quality = channel_quality;
fusion_result.fusion_quality = fusion_quality;
fusion_result.config = config;

% Add time axis if sampling rate is available
if isfield(iq_data, 'sampling_rate') || isfield(config, 'sampling_rate')
    if isfield(iq_data, 'sampling_rate')
        fs = iq_data.sampling_rate;
    else
        fs = config.sampling_rate;
    end
    
    fusion_result.time_axis = (0:min_length-1) / fs;
    fusion_result.sampling_rate = fs;
end

%% Summary Report
fprintf('\n=== Multi-Channel Fusion Summary ===\n');
fprintf('Channels used: %d/%d\n', num_available_channels, length(channels));
fprintf('Fusion method: %s\n', config.fusion_method);
fprintf('Fusion effectiveness: %s\n', fusion_quality.fusion_effectiveness);

if num_available_channels > 1
    fprintf('Improvement ratio: %.2fx\n', fusion_quality.fusion_improvement_ratio);
end

fprintf('Fused energy range: %.2e - %.2e\n', min(fused_energy), max(fused_energy));

% Channel contributions
if strcmp(config.fusion_method, 'weighted_sum')
    fprintf('Channel contributions:\n');
    for ch = 1:num_available_channels
        fprintf('  %s: %.1f%% (weight: %.3f)\n', ...
            available_channels{ch}, ...
            channel_quality.(available_channels{ch}).fusion_contribution * 100, ...
            fusion_weights(ch));
    end
end

fprintf('Multi-channel fusion completed.\n');

end

function fused_energy = adaptive_fusion(channel_energies, config)
%% Adaptive Fusion Based on Local SNR

num_channels = length(channel_energies);
min_length = length(channel_energies{1});

% Window size for adaptive analysis
window_size = 64;  % samples
overlap = 0.5;
hop_size = round(window_size * (1 - overlap));

fused_energy = zeros(min_length, 1);

% Process in overlapping windows
for start_idx = 1:hop_size:min_length-window_size+1
    end_idx = min(start_idx + window_size - 1, min_length);
    window_indices = start_idx:end_idx;
    
    % Compute local SNR for each channel
    local_weights = zeros(num_channels, 1);
    
    for ch = 1:num_channels
        window_energy = channel_energies{ch}(window_indices);
        
        % Local SNR estimate
        signal_power = mean(window_energy);
        noise_power = var(window_energy);  % Simple noise estimate
        
        if noise_power > 0
            local_snr = signal_power / noise_power;
        else
            local_snr = 1;
        end
        
        local_weights(ch) = local_snr;
    end
    
    % Normalize weights
    if sum(local_weights) > 0
        local_weights = local_weights / sum(local_weights);
    else
        local_weights = ones(num_channels, 1) / num_channels;
    end
    
    % Apply adaptive fusion for this window
    window_fused = zeros(length(window_indices), 1);
    for ch = 1:num_channels
        window_fused = window_fused + local_weights(ch) * channel_energies{ch}(window_indices);
    end
    
    fused_energy(window_indices) = window_fused;
end

end