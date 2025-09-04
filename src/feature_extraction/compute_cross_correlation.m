function correlation_features = compute_cross_correlation(velocity_features, impact_events, config)
%% Compute Cross-Correlation Between Club and Ball Velocity Tracks
% Club-ball velocity relationship analysis for 7D feature vector
%
% Inputs:
%   velocity_features - Velocity features structure with track segments
%   impact_events - Impact events structure from detect_impact_events
%   config - Configuration structure with correlation parameters
%
% Outputs:
%   correlation_features - Structure containing cross-correlation features

% Validate inputs
if ~isstruct(velocity_features)
    error('velocity_features must be a structure');
end

if ~isfield(velocity_features, 'features') || isempty(velocity_features.features)
    warning('No velocity features found for cross-correlation analysis');
    correlation_features = struct();
    correlation_features.num_correlations = 0;
    correlation_features.features = [];
    return;
end

if ~isstruct(impact_events)
    error('impact_events must be a structure');
end

% Default configuration parameters
if ~isfield(config, 'correlation_lag_range_ms')
    config.correlation_lag_range_ms = 20;  % ±10 ms search window
end

if ~isfield(config, 'expected_delay_range_ms')
    config.expected_delay_range_ms = [1, 3];  % Expected 1-3 ms delay for golf impact
end

% Extract velocity track features
velocity_tracks = velocity_features.features;
num_tracks = length(velocity_tracks);

if num_tracks < 2
    warning('Need at least 2 velocity tracks for cross-correlation analysis');
    correlation_features = struct();
    correlation_features.num_correlations = 0;
    correlation_features.features = [];
    return;
end

% Get impact timing for reference
impact_times = [];
if isfield(impact_events, 'impact_times') && ~isempty(impact_events.impact_times)
    impact_times = impact_events.impact_times;
end

fprintf('Computing cross-correlations between %d velocity tracks...\n', num_tracks);

correlation_results = [];

% Compute cross-correlation between all track pairs
for i = 1:num_tracks-1
    for j = i+1:num_tracks
        track1 = velocity_tracks(i);
        track2 = velocity_tracks(j);
        
        % Check if tracks overlap in time (potential club-ball pair)
        time_overlap = max(0, min(track1.end_time, track2.end_time) - max(track1.start_time, track2.start_time));
        
        if time_overlap <= 0
            continue;  % No temporal overlap
        end
        
        % Determine which track is likely club vs ball based on timing and velocity
        % Club typically appears before ball, ball has higher peak velocity
        if track1.start_time < track2.start_time && track2.max_velocity > track1.max_velocity
            club_track = track1;
            ball_track = track2;
            club_idx = i;
            ball_idx = j;
        elseif track2.start_time < track1.start_time && track1.max_velocity > track2.max_velocity
            club_track = track2;
            ball_track = track1;
            club_idx = j;
            ball_idx = i;
        else
            % Ambiguous case - use velocity magnitude
            if track1.max_velocity > track2.max_velocity
                club_track = track2;
                ball_track = track1;
                club_idx = j;
                ball_idx = i;
            else
                club_track = track1;
                ball_track = track2;
                club_idx = i;
                ball_idx = j;
            end
        end
        
        % Create interpolated velocity signals for correlation
        % Find common time base
        start_time = max(club_track.start_time, ball_track.start_time);
        end_time = min(club_track.end_time, ball_track.end_time);
        
        if end_time <= start_time
            continue;  % No valid overlap
        end
        
        % Create high-resolution time base for correlation
        dt = 0.001;  % 1 ms resolution
        common_time = start_time:dt:end_time;
        
        if length(common_time) < 10
            continue;  % Too short for meaningful correlation
        end
        
        % Extract velocity segments (this would need actual velocity time series)
        % For now, create synthetic signals based on the track characteristics
        club_duration = club_track.end_time - club_track.start_time;
        ball_duration = ball_track.end_time - ball_track.start_time;
        
        % Create synthetic velocity profiles based on track features
        club_signal = create_velocity_profile(common_time, club_track, 'club');
        ball_signal = create_velocity_profile(common_time, ball_track, 'ball');
        
        % Compute cross-correlation
        % R_cb(τ) = Σv_club(t) × v_ball(t+τ) / √(Σv_club² × Σv_ball²)
        max_lag_samples = round(config.correlation_lag_range_ms / 1000 / dt);
        
        % Normalize signals for correlation
        club_norm = (club_signal - mean(club_signal)) / std(club_signal);
        ball_norm = (ball_signal - mean(ball_signal)) / std(ball_signal);
        
        % Compute cross-correlation
        [correlation, lags] = xcorr(club_norm, ball_norm, max_lag_samples, 'normalized');
        
        % Convert lag samples to time delays
        lag_times_ms = lags * dt * 1000;  % Convert to milliseconds
        
        % Find peak correlation and corresponding delay
        [max_correlation, max_idx] = max(abs(correlation));
        peak_correlation = correlation(max_idx);
        delay_ms = lag_times_ms(max_idx);
        
        % Check if delay is within expected physics range (1-3 ms)
        is_physics_valid = (delay_ms >= config.expected_delay_range_ms(1)) && ...
                          (delay_ms <= config.expected_delay_range_ms(2));
        
        % Compute correlation quality metrics
        correlation_quality = struct();
        correlation_quality.peak_correlation = peak_correlation;
        correlation_quality.max_correlation_abs = max_correlation;
        correlation_quality.delay_ms = delay_ms;
        correlation_quality.is_physics_valid = is_physics_valid;
        correlation_quality.signal_overlap_duration = time_overlap;
        
        % Additional correlation statistics
        correlation_quality.mean_correlation = mean(correlation);
        correlation_quality.std_correlation = std(correlation);
        correlation_quality.correlation_snr = max_correlation / std(correlation);
        
        % Find nearest impact event for validation
        nearest_impact_time = NaN;
        impact_proximity_ms = NaN;
        
        if ~isempty(impact_times)
            track_center_time = (start_time + end_time) / 2;
            [min_distance, min_idx] = min(abs(impact_times - track_center_time));
            nearest_impact_time = impact_times(min_idx);
            impact_proximity_ms = min_distance * 1000;
        end
        
        % Store correlation result
        correlation_result = struct();
        correlation_result.club_track_idx = club_idx;
        correlation_result.ball_track_idx = ball_idx;
        correlation_result.club_max_velocity = club_track.max_velocity;
        correlation_result.ball_max_velocity = ball_track.max_velocity;
        correlation_result.velocity_ratio = ball_track.max_velocity / club_track.max_velocity;
        correlation_result.correlation_quality = correlation_quality;
        correlation_result.nearest_impact_time = nearest_impact_time;
        correlation_result.impact_proximity_ms = impact_proximity_ms;
        correlation_result.temporal_overlap = time_overlap;
        correlation_result.start_time = start_time;
        correlation_result.end_time = end_time;
        
        correlation_results = [correlation_results; correlation_result];
    end
end

% Create output structure
correlation_features = struct();
correlation_features.num_correlations = length(correlation_results);
correlation_features.features = correlation_results;
correlation_features.config = config;

% Compute overall statistics
if correlation_features.num_correlations > 0
    all_delays = [correlation_results.correlation_quality];
    all_delays = [all_delays.delay_ms];
    all_correlations = [correlation_results.correlation_quality];
    all_correlations = [all_correlations.peak_correlation];
    all_velocity_ratios = [correlation_results.velocity_ratio];
    
    correlation_features.correlation_statistics = struct();
    correlation_features.correlation_statistics.delay_range_ms = [min(all_delays), max(all_delays)];
    correlation_features.correlation_statistics.mean_delay_ms = mean(all_delays);
    correlation_features.correlation_statistics.correlation_range = [min(all_correlations), max(all_correlations)];
    correlation_features.correlation_statistics.mean_correlation = mean(all_correlations);
    correlation_features.correlation_statistics.velocity_ratio_range = [min(all_velocity_ratios), max(all_velocity_ratios)];
    correlation_features.correlation_statistics.mean_velocity_ratio = mean(all_velocity_ratios);
    
    % Count physics-valid correlations
    physics_valid = [correlation_results.correlation_quality];
    physics_valid = [physics_valid.is_physics_valid];
    correlation_features.correlation_statistics.physics_valid_count = sum(physics_valid);
    correlation_features.correlation_statistics.physics_valid_ratio = sum(physics_valid) / length(physics_valid);
end

% Log cross-correlation results
fprintf('Cross-correlation analysis completed:\n');
fprintf('- Number of track pairs analyzed: %d\n', correlation_features.num_correlations);

if correlation_features.num_correlations > 0
    fprintf('- Delay range: %.2f - %.2f ms\n', min(all_delays), max(all_delays));
    fprintf('- Mean delay: %.2f ms\n', mean(all_delays));
    fprintf('- Correlation range: %.3f - %.3f\n', min(all_correlations), max(all_correlations));
    fprintf('- Physics-valid correlations: %d/%d (%.1f%%)\n', ...
        sum(physics_valid), length(physics_valid), sum(physics_valid)/length(physics_valid)*100);
end

end

function velocity_profile = create_velocity_profile(time_axis, track, track_type)
%% Create Synthetic Velocity Profile Based on Track Characteristics
% This is a simplified model - in real implementation would use actual velocity data

duration = track.end_time - track.start_time;
max_vel = track.max_velocity;
rise_time = track.rise_time_ms / 1000;  % Convert to seconds

% Normalize time to track duration
t_norm = (time_axis - time_axis(1)) / duration;

if strcmp(track_type, 'club')
    % Club: smoother, longer duration profile
    velocity_profile = max_vel * sin(pi * t_norm) .* exp(-2 * t_norm);
else
    % Ball: sharper, more impulsive profile
    if rise_time > 0
        peak_time = rise_time / duration;
    else
        peak_time = 0.1;  % Default 10% of duration
    end
    
    velocity_profile = max_vel * exp(-((t_norm - peak_time) / 0.1).^2);
end

end