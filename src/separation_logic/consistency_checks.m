function consistency_results = consistency_checks(classification_results, separation_results, assignment_results, config)
%% Consistency Checks
% Cross-validation between different separation methods

% Validate inputs
if ~isstruct(classification_results) || ~isfield(classification_results, 'classifications')
    error('classification_results must contain classifications field');
end

if ~isstruct(separation_results) || ~isfield(separation_results, 'separations')
    error('separation_results must contain separations field');
end

if ~isstruct(assignment_results) || ~isfield(assignment_results, 'assignments')
    error('assignment_results must contain assignments field');
end

% Default configuration
if nargin < 4 || isempty(config)
    config = struct();
end

if ~isfield(config, 'consistency_threshold')
    config.consistency_threshold = 0.8;  % 80% consistency required
end

if ~isfield(config, 'velocity_tolerance_mph')
    config.velocity_tolerance_mph = 5.0;  % ±5 mph tolerance
end

fprintf('Performing consistency checks across separation methods...\n');

%% Initialize Consistency Results
consistency_results = struct();
consistency_results.consistency_tests = struct();
consistency_results.overall_consistency = struct();

%% Test 1: Classification vs Assignment Consistency
classifications = classification_results.classifications;
assignments = assignment_results.assignments;

num_classifications = length(classifications);
num_assignments = length(assignments);

fprintf('Checking classification vs assignment consistency...\n');
fprintf('Classifications: %d, Assignments: %d\n', num_classifications, num_assignments);

classification_assignment_consistency = struct();

if num_classifications > 0 && num_assignments > 0
    % Match classifications to assignments (simplified by index)
    num_matches = min(num_classifications, num_assignments);
    
    consistent_matches = 0;
    velocity_agreements = [];
    confidence_agreements = [];
    
    for i = 1:num_matches
        classification = classifications(i);
        assignment = assignments(i);
        
        % Extract classification results
        if isfield(classification, 'ensemble_class')
            predicted_class = classification.ensemble_class;
            class_confidence = classification.ensemble_confidence;
        elseif isfield(classification, 'final_class')
            predicted_class = classification.final_class;
            class_confidence = classification.confidence;
        else
            continue;
        end
        
        % Check consistency
        is_consistent = true;
        
        % Velocity consistency check
        if isfield(assignment, 'ball_velocity_mph') && isfield(assignment, 'club_velocity_mph')
            ball_vel = assignment.ball_velocity_mph;
            club_vel = assignment.club_velocity_mph;
            
            % Simple consistency: higher velocity should match predicted class
            if ball_vel > club_vel && ~strcmp(predicted_class, 'ball')
                is_consistent = false;
            elseif club_vel > ball_vel && ~strcmp(predicted_class, 'club')
                is_consistent = false;
            end
            
            velocity_agreements = [velocity_agreements; abs(ball_vel - club_vel)];
        end
        
        % Confidence consistency
        if isfield(assignment, 'overall_confidence')
            assignment_confidence = assignment.overall_confidence;
            confidence_diff = abs(class_confidence - assignment_confidence);
            confidence_agreements = [confidence_agreements; confidence_diff];
        end
        
        if is_consistent
            consistent_matches = consistent_matches + 1;
        end
    end
    
    classification_assignment_consistency.num_matches = num_matches;
    classification_assignment_consistency.consistent_matches = consistent_matches;
    classification_assignment_consistency.consistency_rate = consistent_matches / num_matches;
    classification_assignment_consistency.velocity_agreements = velocity_agreements;
    classification_assignment_consistency.confidence_agreements = confidence_agreements;
    
    if ~isempty(velocity_agreements)
        classification_assignment_consistency.mean_velocity_difference = mean(velocity_agreements);
        classification_assignment_consistency.velocity_consistency = mean(velocity_agreements) <= config.velocity_tolerance_mph;
    end
    
    if ~isempty(confidence_agreements)
        classification_assignment_consistency.mean_confidence_difference = mean(confidence_agreements);
    end
else
    classification_assignment_consistency.consistency_rate = 0;
end

consistency_results.consistency_tests.classification_assignment = classification_assignment_consistency;

%% Test 2: Separation vs Assignment Consistency
separations = separation_results.separations;
num_separations = length(separations);

fprintf('Checking separation vs assignment consistency...\n');

separation_assignment_consistency = struct();

if num_separations > 0 && num_assignments > 0
    num_matches = min(num_separations, num_assignments);
    consistent_separations = 0;
    velocity_errors = [];
    
    for i = 1:num_matches
        separation = separations(i);
        assignment = assignments(i);
        
        is_separation_consistent = true;
        
        % Check velocity consistency
        if isfield(separation, 'club_track') && isfield(separation, 'ball_track')
            if isfield(separation.club_track, 'max_velocity') && isfield(separation.ball_track, 'max_velocity')
                sep_club_vel = separation.club_track.max_velocity;
                sep_ball_vel = separation.ball_track.max_velocity;
                
                if isfield(assignment, 'club_velocity_mph') && isfield(assignment, 'ball_velocity_mph')
                    assign_club_vel = assignment.club_velocity_mph;
                    assign_ball_vel = assignment.ball_velocity_mph;
                    
                    club_error = abs(sep_club_vel - assign_club_vel);
                    ball_error = abs(sep_ball_vel - assign_ball_vel);
                    
                    velocity_errors = [velocity_errors; club_error; ball_error];
                    
                    if club_error > config.velocity_tolerance_mph || ball_error > config.velocity_tolerance_mph
                        is_separation_consistent = false;
                    end
                end
            end
        end
        
        if is_separation_consistent
            consistent_separations = consistent_separations + 1;
        end
    end
    
    separation_assignment_consistency.num_matches = num_matches;
    separation_assignment_consistency.consistent_separations = consistent_separations;
    separation_assignment_consistency.consistency_rate = consistent_separations / num_matches;
    separation_assignment_consistency.velocity_errors = velocity_errors;
    
    if ~isempty(velocity_errors)
        separation_assignment_consistency.mean_velocity_error = mean(velocity_errors);
        separation_assignment_consistency.rms_velocity_error = sqrt(mean(velocity_errors.^2));
    end
else
    separation_assignment_consistency.consistency_rate = 0;
end

consistency_results.consistency_tests.separation_assignment = separation_assignment_consistency;

%% Test 3: Internal Feature Consistency
fprintf('Checking internal feature consistency...\n');

feature_consistency = struct();

if isfield(classification_results, 'feature_vectors') && isfield(classification_results.feature_vectors, 'feature_matrix')
    feature_matrix = classification_results.feature_vectors.feature_matrix;
    
    if size(feature_matrix, 1) > 0
        % Check for feature value consistency
        feature_ranges = [min(feature_matrix); max(feature_matrix)];
        feature_means = mean(feature_matrix);
        feature_stds = std(feature_matrix);
        
        % Detect outliers (values beyond 3 standard deviations)
        outlier_flags = abs(feature_matrix - feature_means) > 3 * feature_stds;
        outlier_rate = sum(outlier_flags(:)) / numel(feature_matrix);
        
        feature_consistency.outlier_rate = outlier_rate;
        feature_consistency.feature_ranges = feature_ranges;
        feature_consistency.feature_stability = feature_stds ./ abs(feature_means);  % Coefficient of variation
        feature_consistency.mean_stability = mean(feature_consistency.feature_stability(~isnan(feature_consistency.feature_stability)));
        
        % Feature consistency score
        if outlier_rate < 0.05 && feature_consistency.mean_stability < 2.0
            feature_consistency.is_consistent = true;
        else
            feature_consistency.is_consistent = false;
        end
    end
end

consistency_results.consistency_tests.feature_consistency = feature_consistency;

%% Test 4: Temporal Consistency
fprintf('Checking temporal consistency...\n');

temporal_consistency = struct();

% Check if impact timings are consistent across methods
impact_times_collection = {};

if isfield(separation_results, 'impact_events') && isfield(separation_results.impact_events, 'impact_times')
    impact_times_collection{end+1} = separation_results.impact_events.impact_times;
end

if isfield(assignment_results, 'impact_times')
    impact_times_collection{end+1} = assignment_results.impact_times;
end

if length(impact_times_collection) >= 2
    % Compare impact timing consistency
    times1 = impact_times_collection{1};
    times2 = impact_times_collection{2};
    
    if ~isempty(times1) && ~isempty(times2)
        % Find closest matches
        timing_errors = [];
        for i = 1:length(times1)
            if ~isempty(times2)
                [min_diff, ~] = min(abs(times2 - times1(i)));
                timing_errors = [timing_errors; min_diff * 1000];  % Convert to ms
            end
        end
        
        temporal_consistency.timing_errors_ms = timing_errors;
        if ~isempty(timing_errors)
            temporal_consistency.mean_timing_error_ms = mean(timing_errors);
            temporal_consistency.max_timing_error_ms = max(timing_errors);
            temporal_consistency.timing_consistency = mean(timing_errors) <= 2.0;  % Within 2ms
        end
    end
end

consistency_results.consistency_tests.temporal_consistency = temporal_consistency;

%% Overall Consistency Assessment
consistency_scores = [];

% Collect individual consistency scores
if isfield(classification_assignment_consistency, 'consistency_rate')
    consistency_scores = [consistency_scores; classification_assignment_consistency.consistency_rate];
end

if isfield(separation_assignment_consistency, 'consistency_rate')
    consistency_scores = [consistency_scores; separation_assignment_consistency.consistency_rate];
end

if isfield(feature_consistency, 'is_consistent')
    consistency_scores = [consistency_scores; double(feature_consistency.is_consistent)];
end

if isfield(temporal_consistency, 'timing_consistency')
    consistency_scores = [consistency_scores; double(temporal_consistency.timing_consistency)];
end

% Overall consistency metrics
if ~isempty(consistency_scores)
    overall_consistency_score = mean(consistency_scores);
    consistency_results.overall_consistency.score = overall_consistency_score;
    consistency_results.overall_consistency.num_tests = length(consistency_scores);
    consistency_results.overall_consistency.passes_threshold = overall_consistency_score >= config.consistency_threshold;
    
    if overall_consistency_score >= 0.9
        consistency_results.overall_consistency.grade = 'Excellent';
    elseif overall_consistency_score >= 0.8
        consistency_results.overall_consistency.grade = 'Good';
    elseif overall_consistency_score >= 0.7
        consistency_results.overall_consistency.grade = 'Acceptable';
    else
        consistency_results.overall_consistency.grade = 'Poor';
    end
else
    consistency_results.overall_consistency.score = 0;
    consistency_results.overall_consistency.grade = 'No Data';
end

%% Generate Consistency Report
fprintf('\n=== Consistency Check Summary ===\n');

if isfield(classification_assignment_consistency, 'consistency_rate')
    fprintf('Classification-Assignment Consistency: %.1f%%\n', classification_assignment_consistency.consistency_rate * 100);
end

if isfield(separation_assignment_consistency, 'consistency_rate')
    fprintf('Separation-Assignment Consistency: %.1f%%\n', separation_assignment_consistency.consistency_rate * 100);
    if isfield(separation_assignment_consistency, 'mean_velocity_error')
        fprintf('  Mean velocity error: %.1f mph\n', separation_assignment_consistency.mean_velocity_error);
    end
end

if isfield(feature_consistency, 'outlier_rate')
    fprintf('Feature Consistency: %.1f%% outliers\n', feature_consistency.outlier_rate * 100);
end

if isfield(temporal_consistency, 'mean_timing_error_ms')
    fprintf('Temporal Consistency: %.1f ms average timing error\n', temporal_consistency.mean_timing_error_ms);
end

fprintf('\nOverall Consistency: %s (Score: %.2f)\n', ...
    consistency_results.overall_consistency.grade, consistency_results.overall_consistency.score);

if consistency_results.overall_consistency.passes_threshold
    fprintf('✓ Consistency threshold met (≥%.0f%%)\n', config.consistency_threshold * 100);
else
    fprintf('⚠ Consistency threshold not met (<%.0f%%)\n', config.consistency_threshold * 100);
end

fprintf('Consistency checks completed.\n');

end
