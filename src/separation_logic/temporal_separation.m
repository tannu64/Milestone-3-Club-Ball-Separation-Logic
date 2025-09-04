
function separation_results = temporal_separation(classification_results, impact_events, velocity_data, config)
%% Temporal Club/Ball Separation Logic
% Time-domain analysis around impact events with physics validation
%
% Inputs:
%   classification_results - Results from rule_based_classifier
%   impact_events - Impact events from detect_impact_events
%   velocity_data - Velocity data from doppler_to_velocity
%   config - Configuration structure
%
% Outputs:
%   separation_results - Structure containing separated club/ball velocities

% Validate inputs
if ~isstruct(classification_results) || ~isfield(classification_results, 'classifications')
    error('classification_results must be a structure with classifications field');
end

if ~isstruct(impact_events)
    error('impact_events must be a structure');
end

if ~isstruct(velocity_data)
    error('velocity_data must be a structure');
end

% Default configuration parameters
if ~isfield(config, 'velocity_window_ms')
    config.velocity_window_ms = 100;  % ±50 ms analysis window
end

if ~isfield(config, 'impact_timing_tolerance_ms')
    config.impact_timing_tolerance_ms = 2.0;  % ±2 ms impact timing tolerance
end

% Extract data
classifications = classification_results.classifications;
num_classifications = length(classifications);

% Get impact timing
impact_times = [];
if isfield(impact_events, 'impact_times') && ~isempty(impact_events.impact_times)
    impact_times = impact_events.impact_times;
end

% Get velocity segments
velocity_segments = [];
if isfield(velocity_data, 'velocity_segments') && ~isempty(velocity_data.velocity_segments)
    velocity_segments = velocity_data.velocity_segments;
end

fprintf('Performing temporal separation on %d classified tracks...\n', num_classifications);

% Initialize separation results
separation_data = [];

% Process each impact event
if ~isempty(impact_times)
    for impact_idx = 1:length(impact_times)
        impact_time = impact_times(impact_idx);
        
        % Find tracks near this impact event
        window_start = impact_time - config.velocity_window_ms / 1000;
        window_end = impact_time + config.velocity_window_ms / 1000;
        
        nearby_tracks = [];
        for class_idx = 1:num_classifications
            classification = classifications(class_idx);
            track_center = (classification.start_time + classification.end_time) / 2;
            
            if track_center >= window_start && track_center <= window_end
                nearby_tracks = [nearby_tracks; classification];
            end
        end
        
        if length(nearby_tracks) < 2
            continue;  % Need at least 2 tracks for separation
        end
        
        % Separate club and ball tracks for this impact
        [club_track, ball_track] = separate_club_ball_pair(nearby_tracks, impact_time, config);
        
        if ~isempty(club_track) && ~isempty(ball_track)
            % Validate separation using physics constraints
            separation_valid = validate_separation_physics(club_track, ball_track, impact_time, config);
            
            % Create separation result
            separation_result = struct();
            separation_result.impact_idx = impact_idx;
            separation_result.impact_time = impact_time;
            separation_result.club_track = club_track;
            separation_result.ball_track = ball_track;
            separation_result.separation_valid = separation_valid;
            separation_result.velocity_ratio = ball_track.max_velocity / club_track.max_velocity;
            separation_result.timing_separation_ms = abs(ball_track.start_time - club_track.start_time) * 1000;
            
            % Physics validation metrics
            separation_result.physics_metrics = compute_physics_metrics(club_track, ball_track, impact_time);
            
            separation_data = [separation_data; separation_result];
        end
    end
else
    % No impact events - try to separate based on classification alone
    club_tracks = [];
    ball_tracks = [];
    
    for class_idx = 1:num_classifications
        classification = classifications(class_idx);
        
        if strcmp(classification.final_class, 'club')
            club_tracks = [club_tracks; classification];
        elseif strcmp(classification.final_class, 'ball')
            ball_tracks = [ball_tracks; classification];
        end
    end
    
    % Pair club and ball tracks by temporal proximity
    for club_idx = 1:length(club_tracks)
        club_track = club_tracks(club_idx);
        club_center_time = (club_track.start_time + club_track.end_time) / 2;
        
        % Find closest ball track
        min_distance = inf;
        best_ball_idx = 0;
        
        for ball_idx = 1:length(ball_tracks)
            ball_track = ball_tracks(ball_idx);
            ball_center_time = (ball_track.start_time + ball_track.end_time) / 2;
            distance = abs(club_center_time - ball_center_time);
            
            if distance < min_distance
                min_distance = distance;
                best_ball_idx = ball_idx;
            end
        end
        
        if best_ball_idx > 0 && min_distance < config.velocity_window_ms / 1000
            ball_track = ball_tracks(best_ball_idx);
            estimated_impact_time = (club_center_time + ball_center_time) / 2;
            
            % Validate separation
            separation_valid = validate_separation_physics(club_track, ball_track, estimated_impact_time, config);
            
            % Create separation result
            separation_result = struct();
            separation_result.impact_idx = club_idx;  % Use club index as identifier
            separation_result.impact_time = estimated_impact_time;
            separation_result.club_track = club_track;
            separation_result.ball_track = ball_track;
            separation_result.separation_valid = separation_valid;
            separation_result.velocity_ratio = ball_track.max_velocity / club_track.max_velocity;
            separation_result.timing_separation_ms = min_distance * 1000;
            
            % Physics validation metrics
            separation_result.physics_metrics = compute_physics_metrics(club_track, ball_track, estimated_impact_time);
            
            separation_data = [separation_data; separation_result];
        end
    end
end

% Create output structure
separation_results = struct();
separation_results.num_separations = length(separation_data);
separation_results.separations = separation_data;
separation_results.config = config;

% Compute separation statistics
if separation_results.num_separations > 0
    velocity_ratios = [separation_data.velocity_ratio];
    timing_separations = [separation_data.timing_separation_ms];
    separation_validities = [separation_data.separation_valid];
    
    separation_results.separation_statistics = struct();
    separation_results.separation_statistics.velocity_ratio_range = [min(velocity_ratios), max(velocity_ratios)];
    separation_results.separation_statistics.mean_velocity_ratio = mean(velocity_ratios);
    separation_results.separation_statistics.timing_separation_range = [min(timing_separations), max(timing_separations)];
    separation_results.separation_statistics.mean_timing_separation = mean(timing_separations);
    separation_results.separation_statistics.valid_separations = sum(separation_validities);
    separation_results.separation_statistics.separation_success_rate = sum(separation_validities) / length(separation_validities);
end

% Log temporal separation results
fprintf('Temporal separation completed:\n');
fprintf('- Number of separations: %d\n', separation_results.num_separations);

if separation_results.num_separations > 0
    fprintf('- Velocity ratio range: %.2f - %.2f (mean: %.2f)\n', ...
        min(velocity_ratios), max(velocity_ratios), mean(velocity_ratios));
    fprintf('- Timing separation range: %.2f - %.2f ms (mean: %.2f ms)\n', ...
        min(timing_separations), max(timing_separations), mean(timing_separations));
    fprintf('- Valid separations: %d/%d (%.1f%%)\n', ...
        sum(separation_validities), length(separation_validities), ...
        sum(separation_validities)/length(separation_validities)*100);
end

end

function [club_track, ball_track] = separate_club_ball_pair(tracks, impact_time, config)
%% Separate Club and Ball Tracks from Candidates
% Select best club/ball pair based on physics and timing

club_track = [];
ball_track = [];

if length(tracks) < 2
    return;
end

% Score each track as potential club or ball
track_scores = [];
for i = 1:length(tracks)
    track = tracks(i);
    
    % Calculate scores based on classification confidence and timing
    if strcmp(track.final_class, 'club')
        club_score = track.confidence;
        ball_score = 1 - track.confidence;
    elseif strcmp(track.final_class, 'ball')
        club_score = 1 - track.confidence;
        ball_score = track.confidence;
    else
        club_score = 0.5;
        ball_score = 0.5;
    end
    
    % Adjust scores based on timing relative to impact
    track_center = (track.start_time + track.end_time) / 2;
    time_to_impact = abs(track_center - impact_time) * 1000;  % ms
    
    % Closer to impact suggests ball (more impulsive)
    if time_to_impact < 10
        ball_score = ball_score + 0.2;
    else
        club_score = club_score + 0.1;
    end
    
    track_scores = [track_scores; [i, club_score, ball_score]];
end

% Find best club/ball combination
best_score = 0;
best_club_idx = 0;
best_ball_idx = 0;

for i = 1:length(tracks)
    for j = 1:length(tracks)
        if i ~= j
            combined_score = track_scores(i, 2) + track_scores(j, 3);  % i as club, j as ball
            
            if combined_score > best_score
                best_score = combined_score;
                best_club_idx = i;
                best_ball_idx = j;
            end
        end
    end
end

if best_club_idx > 0 && best_ball_idx > 0
    club_track = tracks(best_club_idx);
    ball_track = tracks(best_ball_idx);
end

end

function is_valid = validate_separation_physics(club_track, ball_track, impact_time, config)
%% Validate Separation Using Golf Physics Constraints

is_valid = true;

% Check velocity ratio is physically reasonable
velocity_ratio = ball_track.max_velocity / club_track.max_velocity;
if velocity_ratio < 1.0 || velocity_ratio > 3.0
    is_valid = false;
    return;
end

% Check timing makes sense (club before or simultaneous with ball)
club_center = (club_track.start_time + club_track.end_time) / 2;
ball_center = (ball_track.start_time + ball_track.end_time) / 2;

if ball_center < club_center - 0.01  % Ball significantly before club is suspicious
    is_valid = false;
    return;
end

% Check impact timing tolerance
club_impact_distance = abs(club_center - impact_time) * 1000;
ball_impact_distance = abs(ball_center - impact_time) * 1000;

if club_impact_distance > config.impact_timing_tolerance_ms * 5 || ...
   ball_impact_distance > config.impact_timing_tolerance_ms * 5
    is_valid = false;
    return;
end

end

function physics_metrics = compute_physics_metrics(club_track, ball_track, impact_time)
%% Compute Physics-Based Validation Metrics

physics_metrics = struct();

% Velocity ratio
physics_metrics.velocity_ratio = ball_track.max_velocity / club_track.max_velocity;

% Timing metrics
club_center = (club_track.start_time + club_track.end_time) / 2;
ball_center = (ball_track.start_time + ball_track.end_time) / 2;

physics_metrics.club_to_impact_ms = (impact_time - club_center) * 1000;
physics_metrics.ball_to_impact_ms = (impact_time - ball_center) * 1000;
physics_metrics.club_to_ball_delay_ms = (ball_center - club_center) * 1000;

% Energy transfer estimate (simplified)
club_ke = 0.5 * club_track.max_velocity^2;  % Assuming unit mass
ball_ke = 0.5 * ball_track.max_velocity^2;
physics_metrics.energy_transfer_ratio = ball_ke / club_ke;

% Momentum conservation check (simplified)
physics_metrics.momentum_ratio = ball_track.max_velocity / club_track.max_velocity;

end