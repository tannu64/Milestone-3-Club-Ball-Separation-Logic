function temporal_features = extract_temporal_features(velocity_data, impact_events, config)
%% Extract Temporal Features
% Duration, timing relative to impact for the 7D feature vector

% Validate inputs
if ~isstruct(velocity_data) || ~isfield(velocity_data, 'velocity_segments')
    error('velocity_data must contain velocity_segments field');
end

if ~isstruct(impact_events) || ~isfield(impact_events, 'impact_times')
    error('impact_events must contain impact_times field');
end

% Default configuration
if nargin < 3 || isempty(config)
    config = struct();
end

if ~isfield(config, 'time_window_ms')
    config.time_window_ms = 100;  % Analysis window around impact
end

if ~isfield(config, 'min_duration_ms')
    config.min_duration_ms = 1.0;  % Minimum track duration
end

if ~isfield(config, 'max_duration_ms')
    config.max_duration_ms = 200.0;  % Maximum expected duration
end

velocity_segments = velocity_data.velocity_segments;
impact_times = impact_events.impact_times;
num_segments = length(velocity_segments);

fprintf('Extracting temporal features from %d velocity segments...\n', num_segments);

%% Initialize Results
temporal_features = struct();
temporal_features.num_segments = num_segments;
temporal_features.temporal_tracks = [];

%% Process Each Velocity Segment
for seg_idx = 1:num_segments
    segment = velocity_segments(seg_idx);
    
    % Extract timing information
    start_time = segment.start_time;
    end_time = segment.end_time;
    duration = segment.duration;
    times = segment.times;
    
    % Convert duration to milliseconds
    duration_ms = duration * 1000;
    
    %% Compute Temporal Features
    
    % 1. Duration feature
    duration_feature = duration_ms;
    
    % 2. Impact timing feature - find closest impact
    impact_timing_ms = inf;  % Default: very far from impact
    closest_impact_idx = [];
    
    if ~isempty(impact_times)
        % Find impact closest to this segment
        segment_center = (start_time + end_time) / 2;
        impact_distances = abs(impact_times - segment_center);
        [min_distance, closest_idx] = min(impact_distances);
        
        impact_timing_ms = min_distance * 1000;  % Convert to ms
        closest_impact_idx = closest_idx;
    end
    
    % 3. Relative timing features
    time_to_start_ms = (start_time - (start_time + end_time)/2) * 1000;  % Always negative
    time_to_end_ms = (end_time - (start_time + end_time)/2) * 1000;     % Always positive
    
    % 4. Temporal position features
    if ~isempty(impact_times) && ~isempty(closest_impact_idx)
        closest_impact_time = impact_times(closest_impact_idx);
        
        % Time relative to impact
        impact_relative_start = (start_time - closest_impact_time) * 1000;  % ms
        impact_relative_end = (end_time - closest_impact_time) * 1000;      % ms
        impact_relative_center = ((start_time + end_time)/2 - closest_impact_time) * 1000;
        
        % Temporal classification hints
        if abs(impact_relative_center) <= 5  % Within 5ms of impact
            temporal_class_hint = 'near_impact';
        elseif impact_relative_center < -10  % More than 10ms before impact
            temporal_class_hint = 'pre_impact';
        elseif impact_relative_center > 10   % More than 10ms after impact
            temporal_class_hint = 'post_impact';
        else
            temporal_class_hint = 'around_impact';
        end
    else
        impact_relative_start = nan;
        impact_relative_end = nan;
        impact_relative_center = nan;
        temporal_class_hint = 'no_impact';
    end
    
    % 5. Temporal extent features
    temporal_extent = end_time - start_time;  % seconds
    temporal_extent_ms = temporal_extent * 1000;  % milliseconds
    
    % 6. Sampling density
    num_samples = length(times);
    sampling_density = num_samples / temporal_extent_ms;  % samples per ms
    
    % 7. Temporal stability (how consistent the timing is)
    if length(times) > 1
        time_diffs = diff(times);
        time_diff_std = std(time_diffs);
        temporal_stability = 1 / (1 + time_diff_std);  % Higher = more stable
    else
        temporal_stability = 0;
    end
    
    %% Quality Assessment
    quality_score = 0;
    quality_factors = 0;
    
    % Duration quality
    if duration_ms >= config.min_duration_ms && duration_ms <= config.max_duration_ms
        quality_score = quality_score + 1;
    end
    quality_factors = quality_factors + 1;
    
    % Impact proximity quality
    if impact_timing_ms < config.time_window_ms
        quality_score = quality_score + 1;
    end
    quality_factors = quality_factors + 1;
    
    % Sampling quality
    if sampling_density > 0.1  % At least 0.1 samples per ms
        quality_score = quality_score + 1;
    end
    quality_factors = quality_factors + 1;
    
    % Temporal stability quality
    if temporal_stability > 0.5
        quality_score = quality_score + 1;
    end
    quality_factors = quality_factors + 1;
    
    overall_quality = quality_score / quality_factors;
    
    %% Classification Hints Based on Temporal Features
    classification_hints = struct();
    
    % Duration-based hints
    if duration_ms < 5
        classification_hints.duration = 'ball';  % Very short duration suggests ball
        classification_hints.duration_confidence = 0.7;
    elseif duration_ms > 50
        classification_hints.duration = 'club';  % Long duration suggests club
        classification_hints.duration_confidence = 0.6;
    else
        classification_hints.duration = 'uncertain';
        classification_hints.duration_confidence = 0.5;
    end
    
    % Impact timing-based hints
    if impact_timing_ms < 2
        classification_hints.impact_timing = 'ball';  % Very close to impact
        classification_hints.impact_timing_confidence = 0.8;
    elseif impact_timing_ms < 10
        classification_hints.impact_timing = 'near_impact';
        classification_hints.impact_timing_confidence = 0.6;
    else
        classification_hints.impact_timing = 'uncertain';
        classification_hints.impact_timing_confidence = 0.3;
    end
    
    % Combined temporal hint
    if strcmp(classification_hints.duration, 'ball') && strcmp(classification_hints.impact_timing, 'ball')
        classification_hints.combined = 'ball';
        classification_hints.combined_confidence = min(classification_hints.duration_confidence, classification_hints.impact_timing_confidence) + 0.1;
    elseif strcmp(classification_hints.duration, 'club')
        classification_hints.combined = 'club';
        classification_hints.combined_confidence = classification_hints.duration_confidence;
    else
        classification_hints.combined = 'uncertain';
        classification_hints.combined_confidence = 0.5;
    end
    
    %% Store Temporal Track
    temporal_track = struct();
    temporal_track.segment_idx = seg_idx;
    temporal_track.start_time = start_time;
    temporal_track.end_time = end_time;
    temporal_track.duration = duration;
    temporal_track.duration_ms = duration_ms;
    temporal_track.impact_timing_ms = impact_timing_ms;
    temporal_track.closest_impact_idx = closest_impact_idx;
    temporal_track.impact_relative_start = impact_relative_start;
    temporal_track.impact_relative_end = impact_relative_end;
    temporal_track.impact_relative_center = impact_relative_center;
    temporal_track.temporal_class_hint = temporal_class_hint;
    temporal_track.temporal_extent_ms = temporal_extent_ms;
    temporal_track.num_samples = num_samples;
    temporal_track.sampling_density = sampling_density;
    temporal_track.temporal_stability = temporal_stability;
    temporal_track.overall_quality = overall_quality;
    temporal_track.classification_hints = classification_hints;
    
    temporal_features.temporal_tracks = [temporal_features.temporal_tracks; temporal_track];
end

%% Compute Overall Statistics
if num_segments > 0
    durations_ms = [temporal_features.temporal_tracks.duration_ms];
    impact_timings_ms = [temporal_features.temporal_tracks.impact_timing_ms];
    impact_timings_ms = impact_timings_ms(~isinf(impact_timings_ms));  % Remove inf values
    
    temporal_features.statistics = struct();
    temporal_features.statistics.duration_mean = mean(durations_ms);
    temporal_features.statistics.duration_std = std(durations_ms);
    temporal_features.statistics.duration_range = [min(durations_ms), max(durations_ms)];
    
    if ~isempty(impact_timings_ms)
        temporal_features.statistics.impact_timing_mean = mean(impact_timings_ms);
        temporal_features.statistics.impact_timing_std = std(impact_timings_ms);
        temporal_features.statistics.impact_timing_range = [min(impact_timings_ms), max(impact_timings_ms)];
        temporal_features.statistics.near_impact_count = sum(impact_timings_ms < 10);  % Within 10ms
        temporal_features.statistics.near_impact_rate = temporal_features.statistics.near_impact_count / length(impact_timings_ms);
    end
    
    % Quality statistics
    qualities = [temporal_features.temporal_tracks.overall_quality];
    temporal_features.statistics.quality_mean = mean(qualities);
    temporal_features.statistics.quality_std = std(qualities);
    temporal_features.statistics.high_quality_count = sum(qualities > 0.7);
    temporal_features.statistics.high_quality_rate = temporal_features.statistics.high_quality_count / num_segments;
end

%% Feature Extraction Summary
fprintf('\n=== Temporal Features Summary ===\n');
fprintf('Processed segments: %d\n', num_segments);

if num_segments > 0
    fprintf('Duration: %.1f ± %.1f ms (%.1f - %.1f)\n', ...
        temporal_features.statistics.duration_mean, temporal_features.statistics.duration_std, ...
        temporal_features.statistics.duration_range(1), temporal_features.statistics.duration_range(2));
    
    if isfield(temporal_features.statistics, 'impact_timing_mean')
        fprintf('Impact timing: %.1f ± %.1f ms\n', ...
            temporal_features.statistics.impact_timing_mean, temporal_features.statistics.impact_timing_std);
        fprintf('Near impact (≤10ms): %d/%d (%.1f%%)\n', ...
            temporal_features.statistics.near_impact_count, length(impact_timings_ms), ...
            temporal_features.statistics.near_impact_rate * 100);
    end
    
    fprintf('High quality tracks: %d/%d (%.1f%%)\n', ...
        temporal_features.statistics.high_quality_count, num_segments, ...
        temporal_features.statistics.high_quality_rate * 100);
    
    % Classification hints summary
    temporal_tracks = temporal_features.temporal_tracks;
    combined_hints = {temporal_tracks.classification_hints};
    ball_hints = sum(cellfun(@(x) strcmp(x.combined, 'ball'), combined_hints));
    club_hints = sum(cellfun(@(x) strcmp(x.combined, 'club'), combined_hints));
    uncertain_hints = sum(cellfun(@(x) strcmp(x.combined, 'uncertain'), combined_hints));
    
    fprintf('Classification hints: %d ball, %d club, %d uncertain\n', ball_hints, club_hints, uncertain_hints);
end

fprintf('Temporal feature extraction completed.\n');

end