
function velocity_features = extract_velocity_features(velocity_data, config)
%% Extract Velocity Features for Club/Ball Classification
% Max velocity, rise time, continuity metrics for 7D feature vector
%
% Inputs:
%   velocity_data - Velocity data structure from doppler_to_velocity
%   config - Configuration structure with feature extraction parameters
%
% Outputs:
%   velocity_features - Structure containing velocity-based features

% Validate inputs
if ~isstruct(velocity_data)
    error('velocity_data must be a structure from doppler_to_velocity');
end

if ~isfield(velocity_data, 'velocity_segments')
    error('velocity_data must contain velocity_segments field');
end

% Default configuration parameters
if ~isfield(config, 'continuity_smooth_threshold')
    config.continuity_smooth_threshold = 2.0;  % mph/ms for club motion
end

if ~isfield(config, 'continuity_impulsive_threshold')
    config.continuity_impulsive_threshold = 15.0;  % mph/ms for ball motion
end

if ~isfield(config, 'rise_time_threshold_ms')
    config.rise_time_threshold_ms = 2.0;  % ms for ball acceleration
end

% Extract velocity segments
velocity_segments = velocity_data.velocity_segments;
num_segments = length(velocity_segments);

if num_segments == 0
    warning('No velocity segments found for feature extraction');
    velocity_features = struct();
    velocity_features.num_tracks = 0;
    velocity_features.features = [];
    return;
end

% Initialize feature arrays
features = [];

fprintf('Extracting velocity features from %d segments...\n', num_segments);

for seg_idx = 1:num_segments
    segment = velocity_segments(seg_idx);
    velocities = segment.velocities;
    times = segment.times;
    
    if length(velocities) < 3
        continue;  % Skip segments too short for analysis
    end
    
    % Feature 1: Maximum velocity (v_max)
    max_velocity = max(abs(velocities));
    
    % Feature 2: Rise time (t_rise) - time to reach peak velocity
    [~, peak_idx] = max(abs(velocities));
    rise_time_ms = (times(peak_idx) - times(1)) * 1000;  % Convert to ms
    
    % Feature 3: Continuity metric (C)
    % C = (1/N) * Σ|v(t+1) - v(t)| - measures smoothness vs impulsiveness
    velocity_diffs = abs(diff(velocities));
    time_diffs = diff(times) * 1000;  % Convert to ms
    
    if length(time_diffs) > 0
        continuity_metric = mean(velocity_diffs ./ time_diffs);  % mph/ms
    else
        continuity_metric = 0;
    end
    
    % Feature 4: Duration (T_duration)
    duration_ms = segment.duration * 1000;  % Convert to ms
    
    % Feature 5: Velocity acceleration profile
    % Compute acceleration as dv/dt
    if length(velocities) >= 3
        accelerations = diff(velocities) ./ diff(times);
        max_acceleration = max(abs(accelerations));
        mean_acceleration = mean(abs(accelerations));
    else
        max_acceleration = 0;
        mean_acceleration = 0;
    end
    
    % Feature 6: Velocity smoothness (variance of accelerations)
    if length(accelerations) > 1
        acceleration_variance = var(accelerations);
    else
        acceleration_variance = 0;
    end
    
    % Classification hints based on continuity metric
    % Club: C < 2.0 mph/ms (smooth motion)
    % Ball: C > 15.0 mph/ms (impulsive motion)
    if continuity_metric < config.continuity_smooth_threshold
        motion_type_hint = 'club';
    elseif continuity_metric > config.continuity_impulsive_threshold
        motion_type_hint = 'ball';
    else
        motion_type_hint = 'uncertain';
    end
    
    % Rise time classification hint
    % Ball: rise_time < 2.0 ms (rapid acceleration)
    if rise_time_ms < config.rise_time_threshold_ms && max_velocity > 50
        rise_time_hint = 'ball';
    else
        rise_time_hint = 'club';
    end
    
    % Store features for this segment
    segment_features = struct();
    segment_features.segment_idx = seg_idx;
    segment_features.max_velocity = max_velocity;
    segment_features.rise_time_ms = rise_time_ms;
    segment_features.continuity_metric = continuity_metric;
    segment_features.duration_ms = duration_ms;
    segment_features.max_acceleration = max_acceleration;
    segment_features.mean_acceleration = mean_acceleration;
    segment_features.acceleration_variance = acceleration_variance;
    segment_features.motion_type_hint = motion_type_hint;
    segment_features.rise_time_hint = rise_time_hint;
    segment_features.start_time = segment.start_time;
    segment_features.end_time = segment.end_time;
    
    % Add to features array
    features = [features; segment_features];
end

% Create output structure
velocity_features = struct();
velocity_features.num_tracks = length(features);
velocity_features.features = features;
velocity_features.config = config;

% Compute overall statistics
if velocity_features.num_tracks > 0
    all_max_velocities = [features.max_velocity];
    all_continuity_metrics = [features.continuity_metric];
    all_rise_times = [features.rise_time_ms];
    
    velocity_features.velocity_statistics = struct();
    velocity_features.velocity_statistics.max_velocity_overall = max(all_max_velocities);
    velocity_features.velocity_statistics.mean_velocity = mean(all_max_velocities);
    velocity_features.velocity_statistics.velocity_std = std(all_max_velocities);
    velocity_features.velocity_statistics.continuity_range = [min(all_continuity_metrics), max(all_continuity_metrics)];
    velocity_features.velocity_statistics.rise_time_range = [min(all_rise_times), max(all_rise_times)];
    
    % Count classification hints
    motion_hints = {features.motion_type_hint};
    club_hints = sum(strcmp(motion_hints, 'club'));
    ball_hints = sum(strcmp(motion_hints, 'ball'));
    uncertain_hints = sum(strcmp(motion_hints, 'uncertain'));
    
    velocity_features.classification_hints = struct();
    velocity_features.classification_hints.club_tracks = club_hints;
    velocity_features.classification_hints.ball_tracks = ball_hints;
    velocity_features.classification_hints.uncertain_tracks = uncertain_hints;
end

% Log feature extraction results
fprintf('Velocity feature extraction completed:\n');
fprintf('- Number of tracks analyzed: %d\n', velocity_features.num_tracks);

if velocity_features.num_tracks > 0
    fprintf('- Max velocity range: %.1f - %.1f mph\n', ...
        min(all_max_velocities), max(all_max_velocities));
    fprintf('- Continuity metric range: %.2f - %.2f mph/ms\n', ...
        min(all_continuity_metrics), max(all_continuity_metrics));
    fprintf('- Rise time range: %.2f - %.2f ms\n', ...
        min(all_rise_times), max(all_rise_times));
    fprintf('- Classification hints: %d club, %d ball, %d uncertain\n', ...
        club_hints, ball_hints, uncertain_hints);
end

end