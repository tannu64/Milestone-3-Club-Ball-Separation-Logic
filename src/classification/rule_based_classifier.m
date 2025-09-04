
function classification_results = rule_based_classifier(feature_vectors, config)
%% Rule-Based Club/Ball Classification
% Physics based decision tree (fast,interpretable)
%
% Inputs:
%   feature_vectors - 7D feature vectors from build_feature_vectors
%   config - Configuration structure with classification parameters
%
% Outputs:
%   classification_results - Structure containing rule-based classifications

% Validate inputs
if ~isstruct(feature_vectors) || ~isfield(feature_vectors, 'vectors')
    error('feature_vectors must be a structure with vectors field');
end

if isempty(feature_vectors.vectors)
    warning('No feature vectors provided for classification');
    classification_results = struct();
    classification_results.num_classifications = 0;
    classification_results.classifications = [];
    return;
end

% Default configuration parameters
if ~isfield(config, 'velocity_ratio_wedge')
    config.velocity_ratio_wedge = [1.2, 1.8];  % Wedge velocity ratio range
end

if ~isfield(config, 'velocity_ratio_iron')
    config.velocity_ratio_iron = [1.4, 2.2];  % Iron velocity ratio range
end

if ~isfield(config, 'velocity_ratio_driver')
    config.velocity_ratio_driver = [1.6, 2.5];  % Driver velocity ratio range
end

if ~isfield(config, 'continuity_smooth_threshold')
    config.continuity_smooth_threshold = 2.0;  % mph/ms for club motion
end

if ~isfield(config, 'continuity_impulsive_threshold')
    config.continuity_impulsive_threshold = 15.0;  % mph/ms for ball motion
end

if ~isfield(config, 'rise_time_threshold_ms')
    config.rise_time_threshold_ms = 2.0;  % ms for ball acceleration
end

% Extract feature vectors
vectors = feature_vectors.vectors;
num_vectors = length(vectors);

fprintf('Applying rule-based classification to %d feature vectors...\n', num_vectors);

% Initialize classification results
classification_data = [];

% Classify each feature vector
for vec_idx = 1:num_vectors
    vector = vectors(vec_idx);
    
    % Extract 7D features
    max_velocity = vector.max_velocity;
    rise_time_ms = vector.rise_time_ms;
    spectral_width = vector.spectral_width;
    impact_timing_ms = vector.impact_timing_ms;
    continuity_metric = vector.continuity_metric;
    duration_ms = vector.duration_ms;
    correlation_delay_ms = vector.correlation_delay_ms;
    
    % Initialize classification scores
    club_score = 0;
    ball_score = 0;
    rule_decisions = struct();
    
    % Rule 1: Continuity Metric Analysis
    % Club: C < 2.0 mph/ms (smooth motion)
    % Ball: C > 15.0 mph/ms (impulsive motion)
    if continuity_metric < config.continuity_smooth_threshold
        club_score = club_score + 3;  % Strong club indicator
        rule_decisions.continuity = 'club';
    elseif continuity_metric > config.continuity_impulsive_threshold
        ball_score = ball_score + 3;  % Strong ball indicator
        rule_decisions.continuity = 'ball';
    else
        rule_decisions.continuity = 'uncertain';
    end
    
    % Rule 2: Rise Time Analysis
    % Ball: rise_time < 2.0 ms AND high velocity (rapid acceleration)
    if rise_time_ms < config.rise_time_threshold_ms && max_velocity > 50
        ball_score = ball_score + 2;  % Ball acceleration criterion
        rule_decisions.rise_time = 'ball';
    elseif rise_time_ms > 10  % Slower rise time suggests club
        club_score = club_score + 1;
        rule_decisions.rise_time = 'club';
    else
        rule_decisions.rise_time = 'uncertain';
    end
    
    % Rule 3: Spectral Width Analysis
    % Club: W_s > 50 Hz (extended contact, broad spectrum)
    % Ball: W_s < 20 Hz (point target, narrow spectrum)
    if spectral_width > 50
        club_score = club_score + 2;  % Extended contact indicator
        rule_decisions.spectral_width = 'club';
    elseif spectral_width > 0 && spectral_width < 20
        ball_score = ball_score + 2;  % Point target indicator
        rule_decisions.spectral_width = 'ball';
    else
        rule_decisions.spectral_width = 'uncertain';
    end
    
    % Rule 4: Correlation Delay Analysis
    % Physics-valid delay (1-3 ms) suggests proper club-ball interaction
    if correlation_delay_ms >= 1 && correlation_delay_ms <= 3
        ball_score = ball_score + 1;  % Physics-consistent delay
        rule_decisions.correlation_delay = 'ball';
    elseif correlation_delay_ms > 3
        club_score = club_score + 1;  % Longer delay suggests club
        rule_decisions.correlation_delay = 'club';
    else
        rule_decisions.correlation_delay = 'uncertain';
    end
    
    % Rule 5: Velocity Magnitude Analysis
    % Higher velocities more likely to be ball
    if max_velocity > 120  % High velocity range
        ball_score = ball_score + 1;
        rule_decisions.velocity_magnitude = 'ball';
    elseif max_velocity < 80  % Lower velocity range
        club_score = club_score + 1;
        rule_decisions.velocity_magnitude = 'club';
    else
        rule_decisions.velocity_magnitude = 'uncertain';
    end
    
    % Rule 6: Duration Analysis
    % Longer duration suggests extended club contact
    if duration_ms > 50  % Extended duration
        club_score = club_score + 1;
        rule_decisions.duration = 'club';
    elseif duration_ms < 20  % Short duration
        ball_score = ball_score + 1;
        rule_decisions.duration = 'ball';
    else
        rule_decisions.duration = 'uncertain';
    end
    
    % Rule 7: Impact Timing Proximity
    % Close to impact event suggests ball (more impulsive)
    if impact_timing_ms < 5  % Very close to impact
        ball_score = ball_score + 1;
        rule_decisions.impact_timing = 'ball';
    elseif impact_timing_ms > 20  % Far from impact
        club_score = club_score + 1;
        rule_decisions.impact_timing = 'club';
    else
        rule_decisions.impact_timing = 'uncertain';
    end
    
    % Final classification decision
    total_score = club_score + ball_score;
    if total_score > 0
        club_confidence = club_score / total_score;
        ball_confidence = ball_score / total_score;
    else
        club_confidence = 0.5;
        ball_confidence = 0.5;
    end
    
    % Determine final class
    if ball_score > club_score
        final_class = 'ball';
        confidence = ball_confidence;
    elseif club_score > ball_score
        final_class = 'club';
        confidence = club_confidence;
    else
        final_class = 'uncertain';
        confidence = 0.5;
    end
    
    % Estimate club type based on velocity characteristics
    club_type = 'unknown';
    if strcmp(final_class, 'club') || strcmp(final_class, 'ball')
        if max_velocity < 90
            club_type = 'wedge';
        elseif max_velocity < 140
            club_type = 'iron';
        else
            club_type = 'driver';
        end
    end
    
    % Store classification result
    classification_result = struct();
    classification_result.vector_idx = vec_idx;
    classification_result.track_idx = vector.track_idx;
    classification_result.final_class = final_class;
    classification_result.confidence = confidence;
    classification_result.club_score = club_score;
    classification_result.ball_score = ball_score;
    classification_result.total_score = total_score;
    classification_result.club_confidence = club_confidence;
    classification_result.ball_confidence = ball_confidence;
    classification_result.estimated_club_type = club_type;
    classification_result.rule_decisions = rule_decisions;
    classification_result.feature_vector = vector.feature_vector;
    classification_result.start_time = vector.start_time;
    classification_result.end_time = vector.end_time;
    
    classification_data = [classification_data; classification_result];
end

% Create output structure
classification_results = struct();
classification_results.num_classifications = length(classification_data);
classification_results.classifications = classification_data;
classification_results.config = config;

% Compute overall statistics
if classification_results.num_classifications > 0
    final_classes = {classification_data.final_class};
    club_count = sum(strcmp(final_classes, 'club'));
    ball_count = sum(strcmp(final_classes, 'ball'));
    uncertain_count = sum(strcmp(final_classes, 'uncertain'));
    
    confidences = [classification_data.confidence];
    mean_confidence = mean(confidences);
    
    % Club type distribution
    club_types = {classification_data.estimated_club_type};
    wedge_count = sum(strcmp(club_types, 'wedge'));
    iron_count = sum(strcmp(club_types, 'iron'));
    driver_count = sum(strcmp(club_types, 'driver'));
    
    classification_results.classification_statistics = struct();
    classification_results.classification_statistics.club_count = club_count;
    classification_results.classification_statistics.ball_count = ball_count;
    classification_results.classification_statistics.uncertain_count = uncertain_count;
    classification_results.classification_statistics.mean_confidence = mean_confidence;
    classification_results.classification_statistics.confidence_range = [min(confidences), max(confidences)];
    
    classification_results.club_type_statistics = struct();
    classification_results.club_type_statistics.wedge_count = wedge_count;
    classification_results.club_type_statistics.iron_count = iron_count;
    classification_results.club_type_statistics.driver_count = driver_count;
    
    % Rule effectiveness analysis
    all_rule_decisions = [classification_data.rule_decisions];
    rule_names = fieldnames(all_rule_decisions(1));
    
    classification_results.rule_effectiveness = struct();
    for rule_idx = 1:length(rule_names)
        rule_name = rule_names{rule_idx};
        rule_decisions_array = {all_rule_decisions.(rule_name)};
        
        rule_club_count = sum(strcmp(rule_decisions_array, 'club'));
        rule_ball_count = sum(strcmp(rule_decisions_array, 'ball'));
        rule_uncertain_count = sum(strcmp(rule_decisions_array, 'uncertain'));
        
        classification_results.rule_effectiveness.(rule_name) = struct();
        classification_results.rule_effectiveness.(rule_name).club_decisions = rule_club_count;
        classification_results.rule_effectiveness.(rule_name).ball_decisions = rule_ball_count;
        classification_results.rule_effectiveness.(rule_name).uncertain_decisions = rule_uncertain_count;
        classification_results.rule_effectiveness.(rule_name).decisiveness = ...
            (rule_club_count + rule_ball_count) / length(rule_decisions_array);
    end
end

% Log rule-based classification results
fprintf('Rule-based classification completed:\n');
fprintf('- Number of classifications: %d\n', classification_results.num_classifications);

if classification_results.num_classifications > 0
    fprintf('- Final classifications: %d club, %d ball, %d uncertain\n', ...
        club_count, ball_count, uncertain_count);
    fprintf('- Mean confidence: %.3f\n', mean_confidence);
    fprintf('- Club type estimates: %d wedge, %d iron, %d driver\n', ...
        wedge_count, iron_count, driver_count);
    
    fprintf('- Rule decisiveness:\n');
    for rule_idx = 1:length(rule_names)
        rule_name = rule_names{rule_idx};
        decisiveness = classification_results.rule_effectiveness.(rule_name).decisiveness;
        fprintf('  %s: %.1f%% decisive\n', rule_name, decisiveness * 100);
    end
end

end