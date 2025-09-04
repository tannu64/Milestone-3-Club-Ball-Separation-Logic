
function validation_results = trackman_validation(assignment_results, trackman_references, config)
%% TrackMan Validation
% Direct comparison with reference measurements for performance assessment
%
% Inputs:
%   assignment_results - Results from velocity_assignment
%   trackman_references - Array of TrackMan reference data structures
%   config - Configuration structure with validation parameters
%
% Outputs:
%   validation_results - Structure containing validation metrics and analysis

% Validate inputs
if ~isstruct(assignment_results) || ~isfield(assignment_results, 'assignments')
    error('assignment_results must contain assignments field');
end

if isempty(trackman_references)
    warning('No TrackMan reference data provided');
    validation_results = struct();
    validation_results.num_validations = 0;
    return;
end

% Default configuration parameters
if ~isfield(config, 'max_velocity_error_mph')
    config.max_velocity_error_mph = 10.0;
end

if ~isfield(config, 'target_wedge_accuracy')
    config.target_wedge_accuracy = 0.8;  % 80% target for wedges
end

if ~isfield(config, 'target_iron_accuracy')
    config.target_iron_accuracy = 0.9;  % 90% target for irons
end

if ~isfield(config, 'target_driver_accuracy')
    config.target_driver_accuracy = 0.9;  % 90% target for drivers
end

% Extract assignments
assignments = assignment_results.assignments;
num_assignments = length(assignments);

fprintf('Validating %d assignments against TrackMan reference data...\n', num_assignments);

% Initialize validation data
validation_data = [];
velocity_errors = [];
club_type_performance = struct();
club_type_performance.wedge = [];
club_type_performance.iron = [];
club_type_performance.driver = [];

%% Process Each Assignment
for assign_idx = 1:num_assignments
    assignment = assignments(assign_idx);
    
    % Find corresponding TrackMan reference
    trackman_ref = [];
    if isfield(assignment, 'trackman_ball_speed') && ~isnan(assignment.trackman_ball_speed)
        % TrackMan data already embedded in assignment
        trackman_ref = struct();
        trackman_ref.ball_speed = assignment.trackman_ball_speed;
        trackman_ref.is_valid_shot = true;
    else
        % Search in trackman_references array (if available)
        % This would require matching by timing or other criteria
        for ref_idx = 1:length(trackman_references)
            ref = trackman_references(ref_idx);
            if ref.is_valid_shot
                trackman_ref = ref;
                break;  % Use first valid reference (simplified)
            end
        end
    end
    
    if isempty(trackman_ref) || ~trackman_ref.is_valid_shot
        continue;  % Skip if no valid reference
    end
    
    % Calculate velocity error
    predicted_ball_speed = assignment.ball_velocity_mph;
    reference_ball_speed = trackman_ref.ball_speed;
    velocity_error = abs(predicted_ball_speed - reference_ball_speed);
    velocity_error_percent = (velocity_error / reference_ball_speed) * 100;
    
    % Classification accuracy
    predicted_club_type = assignment.estimated_club_type;
    
    % Determine reference club type from ball speed (simplified)
    if reference_ball_speed < 90
        reference_club_type = 'wedge';
    elseif reference_ball_speed < 140
        reference_club_type = 'iron';
    else
        reference_club_type = 'driver';
    end
    
    classification_correct = strcmp(predicted_club_type, reference_club_type);
    
    % Velocity accuracy check
    velocity_within_tolerance = velocity_error <= config.max_velocity_error_mph;
    
    % Overall assignment quality
    overall_valid = velocity_within_tolerance && assignment.assignment_accepted;
    
    % Store validation result
    validation_result = struct();
    validation_result.assignment_idx = assign_idx;
    validation_result.predicted_ball_speed = predicted_ball_speed;
    validation_result.reference_ball_speed = reference_ball_speed;
    validation_result.velocity_error_mph = velocity_error;
    validation_result.velocity_error_percent = velocity_error_percent;
    validation_result.velocity_within_tolerance = velocity_within_tolerance;
    validation_result.predicted_club_type = predicted_club_type;
    validation_result.reference_club_type = reference_club_type;
    validation_result.classification_correct = classification_correct;
    validation_result.overall_valid = overall_valid;
    validation_result.assignment_confidence = assignment.overall_confidence;
    validation_result.velocity_ratio = assignment.velocity_ratio;
    
    validation_data = [validation_data; validation_result];
    velocity_errors = [velocity_errors; velocity_error];
    
    % Store by club type for detailed analysis
    club_type_performance.(reference_club_type) = [club_type_performance.(reference_club_type); validation_result];
end

%% Compute Validation Metrics
validation_results = struct();
validation_results.num_validations = length(validation_data);
validation_results.validations = validation_data;
validation_results.config = config;

if validation_results.num_validations == 0
    fprintf('No valid comparisons found!\n');
    return;
end

% Overall velocity accuracy metrics
validation_results.velocity_metrics = struct();
validation_results.velocity_metrics.mean_error_mph = mean(velocity_errors);
validation_results.velocity_metrics.rms_error_mph = sqrt(mean(velocity_errors.^2));
validation_results.velocity_metrics.max_error_mph = max(velocity_errors);
validation_results.velocity_metrics.min_error_mph = min(velocity_errors);
validation_results.velocity_metrics.std_error_mph = std(velocity_errors);

% Error distribution
within_5mph = sum(velocity_errors <= 5);
within_10mph = sum(velocity_errors <= 10);
within_15mph = sum(velocity_errors <= 15);

validation_results.velocity_metrics.within_5mph_count = within_5mph;
validation_results.velocity_metrics.within_10mph_count = within_10mph;
validation_results.velocity_metrics.within_15mph_count = within_15mph;
validation_results.velocity_metrics.within_5mph_rate = within_5mph / validation_results.num_validations;
validation_results.velocity_metrics.within_10mph_rate = within_10mph / validation_results.num_validations;
validation_results.velocity_metrics.within_15mph_rate = within_15mph / validation_results.num_validations;

% Classification accuracy metrics
classification_correct = [validation_data.classification_correct];
validation_results.classification_metrics = struct();
validation_results.classification_metrics.overall_accuracy = sum(classification_correct) / validation_results.num_validations;
validation_results.classification_metrics.correct_classifications = sum(classification_correct);
validation_results.classification_metrics.total_classifications = validation_results.num_validations;

% Club-type specific performance
club_types = {'wedge', 'iron', 'driver'};
for i = 1:length(club_types)
    club_type = club_types{i};
    club_data = club_type_performance.(club_type);
    
    if ~isempty(club_data)
        club_errors = [club_data.velocity_error_mph];
        club_classifications = [club_data.classification_correct];
        
        validation_results.club_type_metrics.(club_type) = struct();
        validation_results.club_type_metrics.(club_type).num_samples = length(club_data);
        validation_results.club_type_metrics.(club_type).mean_error_mph = mean(club_errors);
        validation_results.club_type_metrics.(club_type).rms_error_mph = sqrt(mean(club_errors.^2));
        validation_results.club_type_metrics.(club_type).classification_accuracy = sum(club_classifications) / length(club_classifications);
        validation_results.club_type_metrics.(club_type).within_10mph_rate = sum(club_errors <= 10) / length(club_errors);
        
        % Target achievement
        target_accuracy = config.(['target_' club_type '_accuracy']);
        actual_accuracy = validation_results.club_type_metrics.(club_type).classification_accuracy;
        validation_results.club_type_metrics.(club_type).target_achieved = actual_accuracy >= target_accuracy;
        validation_results.club_type_metrics.(club_type).target_accuracy = target_accuracy;
    else
        validation_results.club_type_metrics.(club_type) = struct();
        validation_results.club_type_metrics.(club_type).num_samples = 0;
        validation_results.club_type_metrics.(club_type).target_achieved = false;
    end
end

% Overall system performance assessment
rms_error = validation_results.velocity_metrics.rms_error_mph;
overall_classification_accuracy = validation_results.classification_metrics.overall_accuracy;

validation_results.system_performance = struct();
validation_results.system_performance.rms_error_target_met = rms_error <= config.max_velocity_error_mph;
validation_results.system_performance.wedge_target_met = validation_results.club_type_metrics.wedge.target_achieved;
validation_results.system_performance.iron_target_met = validation_results.club_type_metrics.iron.target_achieved;
validation_results.system_performance.driver_target_met = validation_results.club_type_metrics.driver.target_achieved;

targets_met = sum([validation_results.system_performance.rms_error_target_met, ...
                  validation_results.system_performance.wedge_target_met, ...
                  validation_results.system_performance.iron_target_met, ...
                  validation_results.system_performance.driver_target_met]);

validation_results.system_performance.overall_score = targets_met / 4;  % 0-1 score
validation_results.system_performance.grade = assign_performance_grade(validation_results.system_performance.overall_score);

%% Log Validation Results
fprintf('\n=== TrackMan Validation Results ===\n');
fprintf('Validated samples: %d\n', validation_results.num_validations);

fprintf('\nVelocity Accuracy:\n');
fprintf('- Mean error: %.1f mph\n', validation_results.velocity_metrics.mean_error_mph);
fprintf('- RMS error: %.1f mph (Target: ≤%.1f mph)\n', rms_error, config.max_velocity_error_mph);
fprintf('- Within 10 mph: %d/%d (%.1f%%)\n', within_10mph, validation_results.num_validations, ...
    validation_results.velocity_metrics.within_10mph_rate * 100);

fprintf('\nClassification Accuracy:\n');
fprintf('- Overall: %.1f%%\n', overall_classification_accuracy * 100);

for i = 1:length(club_types)
    club_type = club_types{i};
    if validation_results.club_type_metrics.(club_type).num_samples > 0
        accuracy = validation_results.club_type_metrics.(club_type).classification_accuracy;
        target = validation_results.club_type_metrics.(club_type).target_accuracy;
        target_met = validation_results.club_type_metrics.(club_type).target_achieved;
        fprintf('- %s: %.1f%% (Target: ≥%.1f%%) %s\n', ...
            club_type, accuracy * 100, target * 100, ...
            char("✓" * target_met + "✗" * ~target_met));
    end
end

fprintf('\nOverall Performance: %s (Score: %.2f/1.00)\n', ...
    validation_results.system_performance.grade, validation_results.system_performance.overall_score);

end

function grade = assign_performance_grade(score)
%% Assign Performance Grade Based on Score

if score >= 0.9
    grade = 'Excellent';
elseif score >= 0.8
    grade = 'Good';
elseif score >= 0.7
    grade = 'Satisfactory';
elseif score >= 0.6
    grade = 'Needs Improvement';
else
    grade = 'Poor';
end

end