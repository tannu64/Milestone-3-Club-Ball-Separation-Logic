
function feature_vectors = build_feature_vectors(velocity_features, spectral_features, correlation_features, impact_events, config)
%% Build 7D Feature Vectors for Club/Ball Classification
% Combine all features into 7D vectors for machine learning classification
%
% Inputs:
%   velocity_features - Velocity features from extract_velocity_features
%   spectral_features - Spectral features from extract_spectral_features  
%   correlation_features - Correlation features from compute_cross_correlation
%   impact_events - Impact events from detect_impact_events
%   config - Configuration structure
%
% Outputs:
%   feature_vectors - Structure containing 7D feature vectors and metadata

% Validate inputs
if ~isstruct(velocity_features) || ~isfield(velocity_features, 'features')
    error('velocity_features must be a structure with features field');
end

if ~isstruct(spectral_features) || ~isfield(spectral_features, 'features')
    error('spectral_features must be a structure with features field');
end

if ~isstruct(correlation_features)
    error('correlation_features must be a structure');
end

if ~isstruct(impact_events)
    error('impact_events must be a structure');
end

% Extract feature data
velocity_tracks = velocity_features.features;
spectral_tracks = spectral_features.features;
correlation_pairs = correlation_features.features;

% Get impact timing for reference
impact_times = [];
if isfield(impact_events, 'impact_times') && ~isempty(impact_events.impact_times)
    impact_times = impact_events.impact_times;
end

num_velocity_tracks = length(velocity_tracks);
num_spectral_tracks = length(spectral_tracks);

if num_velocity_tracks == 0
    warning('No velocity tracks found for feature vector construction');
    feature_vectors = struct();
    feature_vectors.num_vectors = 0;
    feature_vectors.vectors = [];
    return;
end

fprintf('Building 7D feature vectors from %d velocity tracks...\n', num_velocity_tracks);

% Initialize feature vector array
feature_vector_data = [];

% Build feature vectors for each track
for track_idx = 1:num_velocity_tracks
    vel_track = velocity_tracks(track_idx);
    
    % Feature 1: Maximum velocity (v_max)
    max_velocity = vel_track.max_velocity;
    
    % Feature 2: Rise time (t_rise) in ms
    rise_time_ms = vel_track.rise_time_ms;
    
    % Feature 3: Spectral width (W_s) - find matching spectral track
    spectral_width = 0;  % Default value
    if num_spectral_tracks > 0
        % Find closest spectral track by timing
        track_center_time = (vel_track.start_time + vel_track.end_time) / 2;
        min_time_diff = inf;
        best_spectral_idx = 1;
        
        for spec_idx = 1:num_spectral_tracks
            spec_track = spectral_tracks(spec_idx);
            spec_center_time = (spec_track.start_time + spec_track.end_time) / 2;
            time_diff = abs(track_center_time - spec_center_time);
            
            if time_diff < min_time_diff
                min_time_diff = time_diff;
                best_spectral_idx = spec_idx;
            end
        end
        
        if min_time_diff < 0.1  % Within 100ms
            spectral_width = spectral_tracks(best_spectral_idx).spectral_width;
        end
    end
    
    % Feature 4: Impact timing (t_impact) - relative to nearest impact event
    impact_timing_ms = 0;  % Default value
    if ~isempty(impact_times)
        track_center_time = (vel_track.start_time + vel_track.end_time) / 2;
        [min_distance, ~] = min(abs(impact_times - track_center_time));
        impact_timing_ms = min_distance * 1000;  % Convert to ms
    end
    
    % Feature 5: Continuity metric (C) in mph/ms
    continuity_metric = vel_track.continuity_metric;
    
    % Feature 6: Duration (T_duration) in ms
    duration_ms = vel_track.duration_ms;
    
    % Feature 7: Correlation delay (τ_delay) - find matching correlation pair
    correlation_delay_ms = 0;  % Default value
    if ~isempty(correlation_pairs)
        % Find correlation pair involving this track
        for corr_idx = 1:length(correlation_pairs)
            corr_pair = correlation_pairs(corr_idx);
            if corr_pair.club_track_idx == track_idx || corr_pair.ball_track_idx == track_idx
                correlation_delay_ms = corr_pair.correlation_quality.delay_ms;
                break;
            end
        end
    end
    
    % Create 7D feature vector
    feature_vector = [max_velocity, rise_time_ms, spectral_width, impact_timing_ms, ...
                     continuity_metric, duration_ms, correlation_delay_ms];
    
    % Classification hints based on individual features
    % Rule-based preliminary classification
    club_votes = 0;
    ball_votes = 0;
    
    % Vote 1: Continuity metric
    if continuity_metric < 2.0
        club_votes = club_votes + 1;
    elseif continuity_metric > 15.0
        ball_votes = ball_votes + 1;
    end
    
    % Vote 2: Rise time
    if rise_time_ms < 2.0 && max_velocity > 50
        ball_votes = ball_votes + 1;
    else
        club_votes = club_votes + 1;
    end
    
    % Vote 3: Spectral width
    if spectral_width > 50
        club_votes = club_votes + 1;
    elseif spectral_width > 0 && spectral_width < 20
        ball_votes = ball_votes + 1;
    end
    
    % Vote 4: Correlation delay
    if correlation_delay_ms >= 1 && correlation_delay_ms <= 3
        ball_votes = ball_votes + 1;  % Physics-valid delay suggests ball
    end
    
    % Preliminary classification
    if ball_votes > club_votes
        preliminary_class = 'ball';
        confidence = ball_votes / (ball_votes + club_votes);
    elseif club_votes > ball_votes
        preliminary_class = 'club';
        confidence = club_votes / (ball_votes + club_votes);
    else
        preliminary_class = 'uncertain';
        confidence = 0.5;
    end
    
    % Store feature vector with metadata
    vector_data = struct();
    vector_data.track_idx = track_idx;
    vector_data.feature_vector = feature_vector;
    vector_data.max_velocity = max_velocity;
    vector_data.rise_time_ms = rise_time_ms;
    vector_data.spectral_width = spectral_width;
    vector_data.impact_timing_ms = impact_timing_ms;
    vector_data.continuity_metric = continuity_metric;
    vector_data.duration_ms = duration_ms;
    vector_data.correlation_delay_ms = correlation_delay_ms;
    vector_data.preliminary_class = preliminary_class;
    vector_data.preliminary_confidence = confidence;
    vector_data.club_votes = club_votes;
    vector_data.ball_votes = ball_votes;
    vector_data.start_time = vel_track.start_time;
    vector_data.end_time = vel_track.end_time;
    
    feature_vector_data = [feature_vector_data; vector_data];
end

% Create output structure
feature_vectors = struct();
feature_vectors.num_vectors = length(feature_vector_data);
feature_vectors.vectors = feature_vector_data;
feature_vectors.feature_names = {'max_velocity', 'rise_time_ms', 'spectral_width', ...
                                'impact_timing_ms', 'continuity_metric', 'duration_ms', ...
                                'correlation_delay_ms'};
feature_vectors.config = config;

% Extract feature matrix for ML processing
if feature_vectors.num_vectors > 0
    feature_matrix = zeros(feature_vectors.num_vectors, 7);
    for i = 1:feature_vectors.num_vectors
        feature_matrix(i, :) = feature_vector_data(i).feature_vector;
    end
    feature_vectors.feature_matrix = feature_matrix;
    
    % Compute feature statistics
    feature_vectors.feature_statistics = struct();
    feature_vectors.feature_statistics.mean = mean(feature_matrix, 1);
    feature_vectors.feature_statistics.std = std(feature_matrix, 1);
    feature_vectors.feature_statistics.min = min(feature_matrix, [], 1);
    feature_vectors.feature_statistics.max = max(feature_matrix, [], 1);
    
    % Count preliminary classifications
    preliminary_classes = {feature_vector_data.preliminary_class};
    club_count = sum(strcmp(preliminary_classes, 'club'));
    ball_count = sum(strcmp(preliminary_classes, 'ball'));
    uncertain_count = sum(strcmp(preliminary_classes, 'uncertain'));
    
    feature_vectors.preliminary_classification = struct();
    feature_vectors.preliminary_classification.club_count = club_count;
    feature_vectors.preliminary_classification.ball_count = ball_count;
    feature_vectors.preliminary_classification.uncertain_count = uncertain_count;
    feature_vectors.preliminary_classification.total_count = feature_vectors.num_vectors;
end

% Log feature vector construction results
fprintf('7D feature vector construction completed:\n');
fprintf('- Number of feature vectors: %d\n', feature_vectors.num_vectors);

if feature_vectors.num_vectors > 0
    fprintf('- Feature ranges:\n');
    for i = 1:7
        fprintf('  %s: %.2f - %.2f (mean: %.2f)\n', ...
            feature_vectors.feature_names{i}, ...
            feature_vectors.feature_statistics.min(i), ...
            feature_vectors.feature_statistics.max(i), ...
            feature_vectors.feature_statistics.mean(i));
    end
    
    fprintf('- Preliminary classification: %d club, %d ball, %d uncertain\n', ...
        club_count, ball_count, uncertain_count);
end

end