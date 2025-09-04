function club_performance = performance_by_club_type(assignment_results, trackman_validation, config)
%% Performance by Club Type
% Detailed wedge/iron/driver breakdown

% Validate inputs
if ~isstruct(assignment_results) || ~isfield(assignment_results, 'assignments')
    error('assignment_results must contain assignments field');
end

% Default configuration
if nargin < 3 || isempty(config)
    config = struct();
end

if ~isfield(config, 'club_speed_thresholds')
    config.club_speed_thresholds = [90, 140];  % [wedge/iron, iron/driver]
end

if ~isfield(config, 'target_accuracies')
    config.target_accuracies = struct();
    config.target_accuracies.wedge = 0.8;   % 80%
    config.target_accuracies.iron = 0.9;    % 90%
    config.target_accuracies.driver = 0.9;  % 90%
end

assignments = assignment_results.assignments;
num_assignments = length(assignments);

fprintf('Analyzing performance by club type for %d assignments...\n', num_assignments);

%% Initialize Club Type Categories
club_types = {'wedge', 'iron', 'driver'};
club_performance = struct();

for i = 1:length(club_types)
    club_type = club_types{i};
    club_performance.(club_type) = struct();
    club_performance.(club_type).assignments = [];
    club_performance.(club_type).num_assignments = 0;
    club_performance.(club_type).velocity_errors = [];
    club_performance.(club_type).velocity_ratios = [];
    club_performance.(club_type).confidences = [];
end

%% Categorize Assignments by Club Type
for assign_idx = 1:num_assignments
    assignment = assignments(assign_idx);
    ball_speed = assignment.ball_velocity_mph;
    
    % Determine club type based on ball speed
    if ball_speed < config.club_speed_thresholds(1)
        club_type = 'wedge';
    elseif ball_speed < config.club_speed_thresholds(2)
        club_type = 'iron';
    else
        club_type = 'driver';
    end
    
    % Store assignment in appropriate category
    club_performance.(club_type).assignments = [club_performance.(club_type).assignments; assignment];
    club_performance.(club_type).num_assignments = club_performance.(club_type).num_assignments + 1;
    club_performance.(club_type).velocity_ratios = [club_performance.(club_type).velocity_ratios; assignment.velocity_ratio];
    club_performance.(club_type).confidences = [club_performance.(club_type).confidences; assignment.overall_confidence];
    
    % TrackMan comparison if available
    if isfield(assignment, 'trackman_ball_speed') && ~isnan(assignment.trackman_ball_speed)
        velocity_error = abs(assignment.ball_velocity_mph - assignment.trackman_ball_speed);
        club_performance.(club_type).velocity_errors = [club_performance.(club_type).velocity_errors; velocity_error];
    end
end

%% Compute Metrics for Each Club Type
for i = 1:length(club_types)
    club_type = club_types{i};
    club_data = club_performance.(club_type);
    
    if club_data.num_assignments == 0
        continue;
    end
    
    assignments_for_type = club_data.assignments;
    
    % Velocity Statistics
    ball_speeds = [assignments_for_type.ball_velocity_mph];
    club_speeds = [assignments_for_type.club_velocity_mph];
    velocity_ratios = club_data.velocity_ratios;
    
    club_performance.(club_type).velocity_stats = struct();
    club_performance.(club_type).velocity_stats.ball_speed_mean = mean(ball_speeds);
    club_performance.(club_type).velocity_stats.ball_speed_std = std(ball_speeds);
    club_performance.(club_type).velocity_stats.velocity_ratio_mean = mean(velocity_ratios);
    club_performance.(club_type).velocity_stats.velocity_ratio_std = std(velocity_ratios);
    
    % Confidence Analysis
    confidences = club_data.confidences;
    club_performance.(club_type).confidence_stats = struct();
    club_performance.(club_type).confidence_stats.mean = mean(confidences);
    club_performance.(club_type).confidence_stats.std = std(confidences);
    
    high_conf_count = sum(confidences >= 0.7);
    club_performance.(club_type).confidence_stats.high_confidence_rate = high_conf_count / club_data.num_assignments;
    
    % TrackMan Validation (if available)
    if ~isempty(club_data.velocity_errors)
        velocity_errors = club_data.velocity_errors;
        
        club_performance.(club_type).trackman_validation = struct();
        club_performance.(club_type).trackman_validation.mean_error = mean(velocity_errors);
        club_performance.(club_type).trackman_validation.rms_error = sqrt(mean(velocity_errors.^2));
        club_performance.(club_type).trackman_validation.within_10mph_rate = sum(velocity_errors <= 10) / length(velocity_errors);
        club_performance.(club_type).has_trackman_validation = true;
    else
        club_performance.(club_type).has_trackman_validation = false;
    end
    
    % Classification Performance
    estimated_club_types = {assignments_for_type.estimated_club_type};
    correct_classifications = sum(strcmp(estimated_club_types, club_type));
    club_performance.(club_type).classification_accuracy = correct_classifications / club_data.num_assignments;
    
    % Target achievement
    target_accuracy = config.target_accuracies.(club_type);
    club_performance.(club_type).target_accuracy = target_accuracy;
    club_performance.(club_type).target_achieved = club_performance.(club_type).classification_accuracy >= target_accuracy;
end

%% Generate Performance Report
fprintf('\n=== Performance by Club Type Summary ===\n');

for i = 1:length(club_types)
    club_type = club_types{i};
    club_data = club_performance.(club_type);
    
    if club_data.num_assignments == 0
        fprintf('%s: No samples\n', upper(club_type));
        continue;
    end
    
    fprintf('\n--- %s (%d samples) ---\n', upper(club_type), club_data.num_assignments);
    
    % Velocity statistics
    fprintf('Ball speed: %.1f ± %.1f mph\n', ...
        club_data.velocity_stats.ball_speed_mean, club_data.velocity_stats.ball_speed_std);
    
    fprintf('Velocity ratio: %.2f ± %.2f\n', ...
        club_data.velocity_stats.velocity_ratio_mean, club_data.velocity_stats.velocity_ratio_std);
    
    % Classification performance
    target_status = char("✓" * club_data.target_achieved + "✗" * ~club_data.target_achieved);
    fprintf('Classification: %.1f%% (Target: %.1f%%) %s\n', ...
        club_data.classification_accuracy * 100, club_data.target_accuracy * 100, target_status);
    
    % TrackMan validation
    if club_data.has_trackman_validation
        fprintf('TrackMan: %.1f mph RMS error\n', club_data.trackman_validation.rms_error);
    end
    
    fprintf('Confidence: %.3f ± %.3f\n', ...
        club_data.confidence_stats.mean, club_data.confidence_stats.std);
end

end