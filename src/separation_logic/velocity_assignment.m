
function assignment_results = velocity_assignment(separation_results, trackman_data, config)
%% Velocity Assignment and Validation
% Assign velocity measurements to club or ball tracks using classification results
%
% Inputs:
%   separation_results - Results from temporal_separation
%   trackman_data - TrackMan reference data for validation
%   config - Configuration structure
%
% Outputs:
%   assignment_results - Structure containing final velocity assignments

% Validate inputs
if ~isstruct(separation_results) || ~isfield(separation_results, 'separations')
    error('separation_results must be a structure with separations field');
end

if ~isstruct(trackman_data)
    warning('trackman_data not provided - validation will be limited');
    trackman_data = struct();
end

% Default configuration parameters
if ~isfield(config, 'max_velocity_error_mph')
    config.max_velocity_error_mph = 10.0;  % Maximum acceptable velocity error
end

if ~isfield(config, 'confidence_threshold')
    config.confidence_threshold = 0.7;  % Minimum confidence for assignment
end

% Extract separation data
separations = separation_results.separations;
num_separations = length(separations);

fprintf('Performing velocity assignment on %d separated track pairs...\n', num_separations);

% Initialize assignment results
assignment_data = [];

% Process each separation
for sep_idx = 1:num_separations
    separation = separations(sep_idx);
    
    % Extract club and ball tracks
    club_track = separation.club_track;
    ball_track = separation.ball_track;
    
    % Create velocity assignment
    assignment = struct();
    assignment.separation_idx = sep_idx;
    assignment.impact_time = separation.impact_time;
    assignment.separation_valid = separation.separation_valid;
    
    % Club velocity assignment
    assignment.club_velocity_mph = club_track.max_velocity;
    assignment.club_confidence = club_track.confidence;
    assignment.club_track_idx = club_track.track_idx;
    assignment.club_start_time = club_track.start_time;
    assignment.club_end_time = club_track.end_time;
    assignment.club_rise_time_ms = club_track.rise_time_ms;
    assignment.club_continuity = club_track.continuity_metric;
    assignment.club_classification = club_track.final_class;
    
    % Ball velocity assignment
    assignment.ball_velocity_mph = ball_track.max_velocity;
    assignment.ball_confidence = ball_track.confidence;
    assignment.ball_track_idx = ball_track.track_idx;
    assignment.ball_start_time = ball_track.start_time;
    assignment.ball_end_time = ball_track.end_time;
    assignment.ball_rise_time_ms = ball_track.rise_time_ms;
    assignment.ball_continuity = ball_track.continuity_metric;
    assignment.ball_classification = ball_track.final_class;
    
    % Physics metrics
    assignment.velocity_ratio = separation.velocity_ratio;
    assignment.timing_separation_ms = separation.timing_separation_ms;
    assignment.physics_metrics = separation.physics_metrics;
    
    % Assignment quality metrics
    assignment.assignment_quality = compute_assignment_quality(club_track, ball_track, separation);
    
    % Club type estimation
    assignment.estimated_club_type = estimate_club_type(assignment.velocity_ratio, assignment.ball_velocity_mph);
    
    % TrackMan validation if available
    if isfield(trackman_data, 'ball_speed') && ~isnan(trackman_data.ball_speed)
        assignment.trackman_ball_speed = trackman_data.ball_speed;
        assignment.ball_velocity_error_mph = abs(assignment.ball_velocity_mph - trackman_data.ball_speed);
        assignment.ball_velocity_error_percent = (assignment.ball_velocity_error_mph / trackman_data.ball_speed) * 100;
        
        % Check if error is within acceptable range
        assignment.ball_velocity_valid = assignment.ball_velocity_error_mph <= config.max_velocity_error_mph;
    else
        assignment.trackman_ball_speed = NaN;
        assignment.ball_velocity_error_mph = NaN;
        assignment.ball_velocity_error_percent = NaN;
        assignment.ball_velocity_valid = true;  % Assume valid if no reference
    end
    
    % Overall assignment confidence
    min_confidence = min(assignment.club_confidence, assignment.ball_confidence);
    physics_confidence = separation.separation_valid * 0.8 + 0.2;  % Physics validation boost
    assignment.overall_confidence = (min_confidence + physics_confidence) / 2;
    
    % Assignment acceptance
    assignment.assignment_accepted = (assignment.overall_confidence >= config.confidence_threshold) && ...
                                   assignment.ball_velocity_valid && ...
                                   assignment.separation_valid;
    
    assignment_data = [assignment_data; assignment];
end

% Create output structure
assignment_results = struct();
assignment_results.num_assignments = length(assignment_data);
assignment_results.assignments = assignment_data;
assignment_results.config = config;

% Compute assignment statistics
if assignment_results.num_assignments > 0
    % Velocity statistics
    club_velocities = [assignment_data.club_velocity_mph];
    ball_velocities = [assignment_data.ball_velocity_mph];
    velocity_ratios = [assignment_data.velocity_ratio];
    
    % Confidence statistics
    overall_confidences = [assignment_data.overall_confidence];
    
    % Validation statistics
    assignments_accepted = [assignment_data.assignment_accepted];
    ball_velocity_valid = [assignment_data.ball_velocity_valid];
    
    % TrackMan validation (if available)
    has_trackman = ~isnan([assignment_data.trackman_ball_speed]);
    if any(has_trackman)
        trackman_errors = [assignment_data(has_trackman).ball_velocity_error_mph];
        trackman_error_percent = [assignment_data(has_trackman).ball_velocity_error_percent];
    else
        trackman_errors = [];
        trackman_error_percent = [];
    end
    
    % Club type distribution
    club_types = {assignment_data.estimated_club_type};
    wedge_count = sum(strcmp(club_types, 'wedge'));
    iron_count = sum(strcmp(club_types, 'iron'));
    driver_count = sum(strcmp(club_types, 'driver'));
    
    assignment_results.assignment_statistics = struct();
    assignment_results.assignment_statistics.club_velocity_range = [min(club_velocities), max(club_velocities)];
    assignment_results.assignment_statistics.ball_velocity_range = [min(ball_velocities), max(ball_velocities)];
    assignment_results.assignment_statistics.mean_club_velocity = mean(club_velocities);
    assignment_results.assignment_statistics.mean_ball_velocity = mean(ball_velocities);
    assignment_results.assignment_statistics.velocity_ratio_range = [min(velocity_ratios), max(velocity_ratios)];
    assignment_results.assignment_statistics.mean_velocity_ratio = mean(velocity_ratios);
    assignment_results.assignment_statistics.mean_confidence = mean(overall_confidences);
    assignment_results.assignment_statistics.confidence_range = [min(overall_confidences), max(overall_confidences)];
    assignment_results.assignment_statistics.assignments_accepted = sum(assignments_accepted);
    assignment_results.assignment_statistics.acceptance_rate = sum(assignments_accepted) / length(assignments_accepted);
    assignment_results.assignment_statistics.ball_velocity_valid_count = sum(ball_velocity_valid);
    assignment_results.assignment_statistics.ball_velocity_valid_rate = sum(ball_velocity_valid) / length(ball_velocity_valid);
    
    % Club type statistics
    assignment_results.club_type_statistics = struct();
    assignment_results.club_type_statistics.wedge_count = wedge_count;
    assignment_results.club_type_statistics.iron_count = iron_count;
    assignment_results.club_type_statistics.driver_count = driver_count;
    
    % TrackMan validation statistics
    if ~isempty(trackman_errors)
        assignment_results.trackman_validation = struct();
        assignment_results.trackman_validation.num_validated = length(trackman_errors);
        assignment_results.trackman_validation.mean_error_mph = mean(trackman_errors);
        assignment_results.trackman_validation.rms_error_mph = sqrt(mean(trackman_errors.^2));
        assignment_results.trackman_validation.max_error_mph = max(trackman_errors);
        assignment_results.trackman_validation.mean_error_percent = mean(trackman_error_percent);
        assignment_results.trackman_validation.within_10mph_count = sum(trackman_errors <= 10);
        assignment_results.trackman_validation.within_10mph_rate = sum(trackman_errors <= 10) / length(trackman_errors);
    end
end

% Log velocity assignment results
fprintf('Velocity assignment completed:\n');
fprintf('- Number of assignments: %d\n', assignment_results.num_assignments);

if assignment_results.num_assignments > 0
    fprintf('- Club velocity range: %.1f - %.1f mph (mean: %.1f)\n', ...
        min(club_velocities), max(club_velocities), mean(club_velocities));
    fprintf('- Ball velocity range: %.1f - %.1f mph (mean: %.1f)\n', ...
        min(ball_velocities), max(ball_velocities), mean(ball_velocities));
    fprintf('- Velocity ratio range: %.2f - %.2f (mean: %.2f)\n', ...
        min(velocity_ratios), max(velocity_ratios), mean(velocity_ratios));
    fprintf('- Mean confidence: %.3f\n', mean(overall_confidences));
    fprintf('- Assignments accepted: %d/%d (%.1f%%)\n', ...
        sum(assignments_accepted), length(assignments_accepted), ...
        sum(assignments_accepted)/length(assignments_accepted)*100);
    fprintf('- Club type distribution: %d wedge, %d iron, %d driver\n', ...
        wedge_count, iron_count, driver_count);
    
    if ~isempty(trackman_errors)
        fprintf('- TrackMan validation: %.1f mph RMS error (%.1f%% within 10mph)\n', ...
            sqrt(mean(trackman_errors.^2)), sum(trackman_errors <= 10)/length(trackman_errors)*100);
    end
end

end

function quality = compute_assignment_quality(club_track, ball_track, separation)
%% Compute Assignment Quality Score

quality = struct();

% Confidence-based quality
confidence_quality = (club_track.confidence + ball_track.confidence) / 2;

% Physics-based quality
physics_quality = 0;
if separation.separation_valid
    physics_quality = physics_quality + 0.3;
end

% Velocity ratio quality
velocity_ratio = separation.velocity_ratio;
if velocity_ratio >= 1.2 && velocity_ratio <= 2.5
    physics_quality = physics_quality + 0.3;
end

% Timing quality
if separation.timing_separation_ms <= 10  % Good temporal separation
    physics_quality = physics_quality + 0.2;
end

% Feature consistency quality
feature_quality = 0;

% Club features should indicate club-like behavior
if club_track.continuity_metric < 5.0  % Reasonable continuity
    feature_quality = feature_quality + 0.25;
end

% Ball features should indicate ball-like behavior
if ball_track.rise_time_ms < 10  % Reasonable rise time
    feature_quality = feature_quality + 0.25;
end

% Combined quality score
quality.confidence_quality = confidence_quality;
quality.physics_quality = min(physics_quality, 1.0);
quality.feature_quality = feature_quality;
quality.overall_quality = (confidence_quality + quality.physics_quality + feature_quality) / 3;

end

function club_type = estimate_club_type(velocity_ratio, ball_velocity)
%% Estimate Club Type Based on Velocity Characteristics

if ball_velocity < 90
    club_type = 'wedge';
elseif ball_velocity < 130
    if velocity_ratio < 1.6
        club_type = 'wedge';
    else
        club_type = 'iron';
    end
elseif ball_velocity < 160
    if velocity_ratio < 1.8
        club_type = 'iron';
    else
        club_type = 'driver';
    end
else
    club_type = 'driver';
end

end