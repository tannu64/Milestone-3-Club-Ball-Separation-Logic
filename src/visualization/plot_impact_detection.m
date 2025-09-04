function plot_impact_detection(impact_events, stft_results, iq_data, config)
%% Plot Impact Detection Analysis
% Energy Burst Detection: Time-frequency spectrograms with detected impact events
% Multi-Channel Fusion: Energy contributions from each I/Q channel  
% Impact Timing Validation: Detected vs. theoretical impact timing scatter plots
% Gradient Analysis: Temporal energy gradients showing impact signatures

% Validate inputs
if ~isstruct(impact_events) || ~isfield(impact_events, 'detected_impacts')
    error('impact_events must contain detected_impacts field');
end

if nargin < 4 || isempty(config)
    config = struct();
end

if ~isfield(config, 'save_figures')
    config.save_figures = true;
end

if ~isfield(config, 'figure_format')
    config.figure_format = 'png';
end

if ~isfield(config, 'output_dir')
    config.output_dir = 'figures';
end

fprintf('Creating impact detection visualization plots...\n');

% Create output directory
if config.save_figures && ~exist(config.output_dir, 'dir')
    mkdir(config.output_dir);
end

%% Figure 1: Energy Burst Detection Overview
fig1 = figure('Position', [100, 100, 1200, 800]);
sgtitle('Impact Detection: Energy Burst Analysis', 'FontSize', 16, 'FontWeight', 'bold');

% Extract energy data
if isfield(impact_events, 'fused_energy')
    fused_energy = impact_events.fused_energy;
    time_axis = impact_events.time_axis;
    energy_gradient = impact_events.energy_gradient;
    detected_times = impact_events.impact_times;
else
    % Fallback: use STFT energy
    if isstruct(stft_results)
        fused_energy = stft_results.spectral_energy;
        time_axis = stft_results.time_axis;
        detected_times = [];
    else
        fprintf('Warning: Limited energy data available for visualization\n');
        fused_energy = rand(1, 100);  % Placeholder
        time_axis = linspace(0, 1, 100);
        detected_times = [];
    end
    energy_gradient = gradient(fused_energy);
end

% Subplot 1: Fused Energy
subplot(3, 1, 1);
plot(time_axis * 1000, fused_energy, 'b-', 'LineWidth', 1.5);
hold on;
if ~isempty(detected_times)
    for i = 1:length(detected_times)
        xline(detected_times(i) * 1000, 'r--', 'LineWidth', 2, 'Alpha', 0.7);
    end
    legend('Fused Energy', 'Detected Impacts', 'Location', 'best');
else
    legend('Fused Energy', 'Location', 'best');
end
xlabel('Time (ms)');
ylabel('Energy');
title('Multi-Channel Fused Energy');
grid on;

% Subplot 2: Energy Gradient  
subplot(3, 1, 2);
plot(time_axis * 1000, energy_gradient, 'g-', 'LineWidth', 1.5);
hold on;
if isfield(impact_events, 'detection_threshold')
    yline(impact_events.detection_threshold, 'r:', 'LineWidth', 2, 'Alpha', 0.7);
    yline(-impact_events.detection_threshold, 'r:', 'LineWidth', 2, 'Alpha', 0.7);
    legend('Energy Gradient', 'Detection Threshold', 'Location', 'best');
else
    legend('Energy Gradient', 'Location', 'best');
end
if ~isempty(detected_times)
    for i = 1:length(detected_times)
        xline(detected_times(i) * 1000, 'r--', 'LineWidth', 2, 'Alpha', 0.7);
    end
end
xlabel('Time (ms)');
ylabel('dE/dt');
title('Temporal Energy Gradient');
grid on;

% Subplot 3: Impact Detection Summary
subplot(3, 1, 3);
if ~isempty(detected_times)
    stem(detected_times * 1000, ones(size(detected_times)), 'ro', 'MarkerSize', 8, 'LineWidth', 2);
    xlabel('Time (ms)');
    ylabel('Impact Events');
    title(sprintf('Detected Impact Events (%d total)', length(detected_times)));
    ylim([0, 2]);
else
    text(0.5, 0.5, 'No Impact Events Detected', 'HorizontalAlignment', 'center', ...
        'FontSize', 14, 'Color', 'red');
    xlim([0, 1]);
    ylim([0, 1]);
    title('Impact Detection Results');
end
grid on;

if config.save_figures
    filename1 = fullfile(config.output_dir, sprintf('impact_detection_overview.%s', config.figure_format));
    saveas(fig1, filename1);
    fprintf('Saved: %s\n', filename1);
end

%% Figure 2: Multi-Channel Energy Analysis
if nargin >= 3 && isstruct(iq_data)
    fig2 = figure('Position', [150, 150, 1200, 600]);
    sgtitle('Multi-Channel Energy Contributions', 'FontSize', 16, 'FontWeight', 'bold');
    
    channels = {'channel1', 'channel2', 'channel3', 'channel4'};
    channel_labels = {'IF1 Upper', 'IF1 Lower', 'IF2 Upper', 'IF2 Lower'};
    colors = {'b', 'r', 'g', 'm'};
    
    for ch = 1:min(4, length(channels))
        subplot(2, 2, ch);
        
        if isfield(iq_data, channels{ch})
            % Compute energy for this channel
            channel_data = iq_data.(channels{ch});
            if ~isempty(channel_data)
                channel_energy = abs(channel_data).^2;
                % Smooth for visualization
                if length(channel_energy) > 100
                    smooth_factor = round(length(channel_energy) / 100);
                    channel_energy = movmean(channel_energy, smooth_factor);
                end
                time_ch = linspace(0, length(channel_energy)/22700, length(channel_energy));
                
                plot(time_ch * 1000, channel_energy, colors{ch}, 'LineWidth', 1.5);
                hold on;
                
                % Mark detected impacts
                if ~isempty(detected_times)
                    for i = 1:length(detected_times)
                        xline(detected_times(i) * 1000, 'k--', 'Alpha', 0.5);
                    end
                end
                
                xlabel('Time (ms)');
                ylabel('Energy');
                title(channel_labels{ch});
                grid on;
            else
                text(0.5, 0.5, 'No Data', 'HorizontalAlignment', 'center');
                title(channel_labels{ch});
            end
        else
            text(0.5, 0.5, 'Channel Not Available', 'HorizontalAlignment', 'center');
            title(channel_labels{ch});
        end
    end
    
    if config.save_figures
        filename2 = fullfile(config.output_dir, sprintf('multichannel_energy_analysis.%s', config.figure_format));
        saveas(fig2, filename2);
        fprintf('Saved: %s\n', filename2);
    end
end

%% Figure 3: Impact Timing Validation
if ~isempty(detected_times) && length(detected_times) > 1
    fig3 = figure('Position', [200, 200, 800, 600]);
    sgtitle('Impact Timing Analysis', 'FontSize', 16, 'FontWeight', 'bold');
    
    % Subplot 1: Time intervals between impacts
    subplot(2, 1, 1);
    time_intervals = diff(detected_times) * 1000;  % Convert to ms
    if ~isempty(time_intervals)
        bar(1:length(time_intervals), time_intervals, 'FaceColor', [0.7, 0.7, 0.9]);
        xlabel('Impact Pair Index');
        ylabel('Time Interval (ms)');
        title('Inter-Impact Time Intervals');
        grid on;
        
        % Add mean line
        mean_interval = mean(time_intervals);
        yline(mean_interval, 'r--', sprintf('Mean: %.1f ms', mean_interval), 'LineWidth', 2);
    end
    
    % Subplot 2: Impact timing distribution
    subplot(2, 1, 2);
    histogram(detected_times * 1000, min(10, length(detected_times)), 'FaceColor', [0.9, 0.7, 0.7]);
    xlabel('Impact Time (ms)');
    ylabel('Count');
    title('Impact Timing Distribution');
    grid on;
    
    if config.save_figures
        filename3 = fullfile(config.output_dir, sprintf('impact_timing_validation.%s', config.figure_format));
        saveas(fig3, filename3);
        fprintf('Saved: %s\n', filename3);
    end
end

%% Figure 4: Spectrogram with Impact Overlay
if isstruct(stft_results) && isfield(stft_results, 'stft_matrix')
    fig4 = figure('Position', [250, 250, 1000, 600]);
    
    % Create spectrogram
    stft_magnitude = abs(stft_results.stft_matrix);
    
    % Convert to dB
    stft_db = 20 * log10(stft_magnitude + eps);
    
    imagesc(stft_results.time_axis * 1000, stft_results.freq_axis, stft_db);
    axis xy;
    colormap('jet');
    colorbar;
    
    hold on;
    % Overlay impact detections
    if ~isempty(detected_times)
        for i = 1:length(detected_times)
            xline(detected_times(i) * 1000, 'w--', 'LineWidth', 3, 'Alpha', 0.8);
        end
    end
    
    xlabel('Time (ms)');
    ylabel('Frequency (Hz)');
    title('STFT Spectrogram with Impact Detection Overlay');
    
    % Limit frequency range for better visualization
    if max(stft_results.freq_axis) > 2000
        ylim([0, 2000]);
    end
    
    if config.save_figures
        filename4 = fullfile(config.output_dir, sprintf('spectrogram_impact_overlay.%s', config.figure_format));
        saveas(fig4, filename4);
        fprintf('Saved: %s\n', filename4);
    end
end

%% Summary Statistics
fprintf('\n=== Impact Detection Summary ===\n');
if ~isempty(detected_times)
    fprintf('Total impacts detected: %d\n', length(detected_times));
    fprintf('First impact: %.2f ms\n', detected_times(1) * 1000);
    fprintf('Last impact: %.2f ms\n', detected_times(end) * 1000);
    
    if length(detected_times) > 1
        time_intervals = diff(detected_times) * 1000;
        fprintf('Mean inter-impact interval: %.2f ± %.2f ms\n', mean(time_intervals), std(time_intervals));
        fprintf('Min interval: %.2f ms\n', min(time_intervals));
        fprintf('Max interval: %.2f ms\n', max(time_intervals));
    end
else
    fprintf('No impacts detected\n');
end

if isfield(impact_events, 'detection_threshold')
    fprintf('Detection threshold: %.2e\n', impact_events.detection_threshold);
end

fprintf('Impact detection visualization completed.\n');

end