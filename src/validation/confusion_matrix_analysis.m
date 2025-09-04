
function confusion_analysis = confusion_matrix_analysis(separation_metrics, assignment_results, config)
%% Confusion Matrix Analysis
% Error pattern analysis by club type with detailed misclassification study
%
% Inputs:
%   separation_metrics - Results from compute_separation_metrics
%   assignment_results - Results from velocity_assignment (optional)
%   config - Configuration structure
%
% Outputs:
%   confusion_analysis - Structure containing detailed error pattern analysis

% Validate inputs
if ~isstruct(separation_metrics)
    error('separation_metrics must be a structure from compute_separation_metrics');
end

if ~isfield(separation_metrics, 'confusion_matrix') || ~separation_metrics.has_ground_truth
    warning('No confusion matrix available - ground truth required for analysis');
    confusion_analysis = struct();
    confusion_analysis.analysis_available = false;
    return;
end

% Default configuration
if nargin < 3 || isempty(config)
    config = struct();
end

if ~isfield(config, 'club_speed_thresholds')
    config.club_speed_thresholds = [90, 140];  % [wedge/iron, iron/driver]
end

fprintf('Analyzing confusion matrix and error patterns...\n');

%% Extract Basic Confusion Matrix Data
confusion_matrix = separation_metrics.confusion_matrix;
class_labels = separation_metrics.class_labels;
num_classes = length(class_labels);

confusion_analysis = struct();
confusion_analysis.analysis_available = true;
confusion_analysis.confusion_matrix = confusion_matrix;
confusion_analysis.class_labels = class_labels;
confusion_analysis.total_samples = sum(confusion_matrix(:));

%% Detailed Confusion Matrix Analysis
% Normalize confusion matrix for percentages
confusion_matrix_norm = confusion_matrix ./ sum(confusion_matrix, 2);
confusion_matrix_norm(isnan(confusion_matrix_norm)) = 0;

confusion_analysis.confusion_matrix_normalized = confusion_matrix_norm;

% Classification accuracy per class
class_accuracies = diag(confusion_matrix_norm);
confusion_analysis.class_accuracies = class_accuracies;

% Misclassification patterns
misclassification_matrix = confusion_matrix - diag(diag(confusion_matrix));
confusion_analysis.misclassification_matrix = misclassification_matrix;
confusion_analysis.total_misclassifications = sum(misclassification_matrix(:));

%% Error Pattern Analysis
error_patterns = struct();

for true_class_idx = 1:num_classes
    true_class = class_labels{true_class_idx};
    
    % Find most common misclassification for this true class
    misclassifications = confusion_matrix(true_class_idx, :);
    misclassifications(true_class_idx) = 0;  % Remove correct classifications
    
    [max_misclass, max_misclass_idx] = max(misclassifications);
    
    error_patterns.(true_class) = struct();
    error_patterns.(true_class).total_samples = sum(confusion_matrix(true_class_idx, :));
    error_patterns.(true_class).correct_classifications = confusion_matrix(true_class_idx, true_class_idx);
    error_patterns.(true_class).total_errors = sum(misclassifications);
    error_patterns.(true_class).error_rate = sum(misclassifications) / error_patterns.(true_class).total_samples;
    
    if max_misclass > 0
        error_patterns.(true_class).most_common_error = class_labels{max_misclass_idx};
        error_patterns.(true_class).most_common_error_count = max_misclass;
        error_patterns.(true_class).most_common_error_rate = max_misclass / error_patterns.(true_class).total_samples;
    else
        error_patterns.(true_class).most_common_error = 'none';
        error_patterns.(true_class).most_common_error_count = 0;
        error_patterns.(true_class).most_common_error_rate = 0;
    end
end

confusion_analysis.error_patterns = error_patterns;

%% Club Type Specific Analysis (if assignment results available)
if nargin >= 2 && ~isempty(assignment_results) && isfield(assignment_results, 'assignments')
    assignments = assignment_results.assignments;
    
    % Categorize by club type based on ball velocity
    club_type_analysis = struct();
    club_types = {'wedge', 'iron', 'driver'};
    
    for i = 1:length(club_types)
        club_type_analysis.(club_types{i}) = struct();
        club_type_analysis.(club_types{i}).samples = [];
        club_type_analysis.(club_types{i}).errors = [];
        club_type_analysis.(club_types{i}).error_confidences = [];
    end
    
    % Analyze each assignment
    for assign_idx = 1:length(assignments)
        assignment = assignments(assign_idx);
        ball_speed = assignment.ball_velocity_mph;
        
        % Determine club type from ball speed
        if ball_speed < config.club_speed_thresholds(1)
            club_type = 'wedge';
        elseif ball_speed < config.club_speed_thresholds(2)
            club_type = 'iron';
        else
            club_type = 'driver';
        end
        
        % Store sample information
        sample_info = struct();
        sample_info.ball_speed = ball_speed;
        sample_info.club_speed = assignment.club_velocity_mph;
        sample_info.velocity_ratio = assignment.velocity_ratio;
        sample_info.confidence = assignment.overall_confidence;
        
        club_type_analysis.(club_type).samples = [club_type_analysis.(club_type).samples; sample_info];
        
        % Check if this is a classification error (simplified)
        if isfield(assignment, 'classification_correct') && ~assignment.classification_correct
            club_type_analysis.(club_type).errors = [club_type_analysis.(club_type).errors; sample_info];
            club_type_analysis.(club_type).error_confidences = [club_type_analysis.(club_type).error_confidences; sample_info.confidence];
        end
    end
    
    % Compute club type error statistics
    for i = 1:length(club_types)
        club_type = club_types{i};
        num_samples = length(club_type_analysis.(club_type).samples);
        num_errors = length(club_type_analysis.(club_type).errors);
        
        club_type_analysis.(club_type).num_samples = num_samples;
        club_type_analysis.(club_type).num_errors = num_errors;
        
        if num_samples > 0
            club_type_analysis.(club_type).error_rate = num_errors / num_samples;
            club_type_analysis.(club_type).accuracy = 1 - club_type_analysis.(club_type).error_rate;
            
            % Velocity statistics
            ball_speeds = [club_type_analysis.(club_type).samples.ball_speed];
            club_speeds = [club_type_analysis.(club_type).samples.club_speed];
            velocity_ratios = [club_type_analysis.(club_type).samples.velocity_ratio];
            
            club_type_analysis.(club_type).ball_speed_stats = struct();
            club_type_analysis.(club_type).ball_speed_stats.mean = mean(ball_speeds);
            club_type_analysis.(club_type).ball_speed_stats.std = std(ball_speeds);
            club_type_analysis.(club_type).ball_speed_stats.range = [min(ball_speeds), max(ball_speeds)];
            
            club_type_analysis.(club_type).velocity_ratio_stats = struct();
            club_type_analysis.(club_type).velocity_ratio_stats.mean = mean(velocity_ratios);
            club_type_analysis.(club_type).velocity_ratio_stats.std = std(velocity_ratios);
            club_type_analysis.(club_type).velocity_ratio_stats.range = [min(velocity_ratios), max(velocity_ratios)];
            
            if num_errors > 0
                club_type_analysis.(club_type).mean_error_confidence = mean(club_type_analysis.(club_type).error_confidences);
                club_type_analysis.(club_type).error_confidence_std = std(club_type_analysis.(club_type).error_confidences);
            else
                club_type_analysis.(club_type).mean_error_confidence = 0;
                club_type_analysis.(club_type).error_confidence_std = 0;
            end
        else
            club_type_analysis.(club_type).error_rate = 0;
            club_type_analysis.(club_type).accuracy = 0;
        end
    end
    
    confusion_analysis.club_type_analysis = club_type_analysis;
    confusion_analysis.has_club_type_analysis = true;
else
    confusion_analysis.has_club_type_analysis = false;
end

%% Performance vs Target Analysis
target_accuracies = struct();
target_accuracies.wedge = 0.8;  % 80% target
target_accuracies.iron = 0.9;   % 90% target
target_accuracies.driver = 0.9; % 90% target

if confusion_analysis.has_club_type_analysis
    performance_vs_targets = struct();
    
    for i = 1:length(club_types)
        club_type = club_types{i};
        actual_accuracy = club_type_analysis.(club_type).accuracy;
        target_accuracy = target_accuracies.(club_type);
        
        performance_vs_targets.(club_type) = struct();
        performance_vs_targets.(club_type).actual_accuracy = actual_accuracy;
        performance_vs_targets.(club_type).target_accuracy = target_accuracy;
        performance_vs_targets.(club_type).target_met = actual_accuracy >= target_accuracy;
        performance_vs_targets.(club_type).accuracy_gap = actual_accuracy - target_accuracy;
    end
    
    confusion_analysis.performance_vs_targets = performance_vs_targets;
end

%% Error Severity Analysis
if isfield(separation_metrics, 'error_analysis') && separation_metrics.error_analysis.num_errors > 0
    error_severity = struct();
    
    % Categorize errors by confidence level
    if isfield(separation_metrics.error_analysis, 'mean_error_confidence')
        mean_error_conf = separation_metrics.error_analysis.mean_error_confidence;
        
        if mean_error_conf > 0.8
            error_severity.level = 'high';
            error_severity.description = 'High-confidence errors indicate systematic issues';
        elseif mean_error_conf > 0.6
            error_severity.level = 'medium';
            error_severity.description = 'Medium-confidence errors suggest boundary cases';
        else
            error_severity.level = 'low';
            error_severity.description = 'Low-confidence errors are expected uncertainty';
        end
        
        error_severity.mean_confidence = mean_error_conf;
    end
    
    confusion_analysis.error_severity = error_severity;
end

%% Generate Summary Report
fprintf('\n=== Confusion Matrix Analysis Summary ===\n');
fprintf('Total samples analyzed: %d\n', confusion_analysis.total_samples);
fprintf('Total misclassifications: %d (%.1f%%)\n', ...
    confusion_analysis.total_misclassifications, ...
    confusion_analysis.total_misclassifications / confusion_analysis.total_samples * 100);

fprintf('\nPer-class Performance:\n');
for i = 1:num_classes
    class_name = class_labels{i};
    accuracy = class_accuracies(i);
    error_info = error_patterns.(class_name);
    
    fprintf('- %s: %.1f%% accuracy (%d correct, %d errors)\n', ...
        class_name, accuracy * 100, error_info.correct_classifications, error_info.total_errors);
    
    if error_info.total_errors > 0
        fprintf('  Most common error: %s (%d cases, %.1f%%)\n', ...
            error_info.most_common_error, error_info.most_common_error_count, ...
            error_info.most_common_error_rate * 100);
    end
end

if confusion_analysis.has_club_type_analysis
    fprintf('\nClub Type Performance:\n');
    for i = 1:length(club_types)
        club_type = club_types{i};
        club_analysis = club_type_analysis.(club_type);
        
        if club_analysis.num_samples > 0
            fprintf('- %s: %.1f%% accuracy (%d samples, %d errors)\n', ...
                club_type, club_analysis.accuracy * 100, ...
                club_analysis.num_samples, club_analysis.num_errors);
            
            if isfield(performance_vs_targets, club_type)
                target_info = performance_vs_targets.(club_type);
                status = char("✓" * target_info.target_met + "✗" * ~target_info.target_met);
                fprintf('  Target: %.1f%% %s (Gap: %+.1f%%)\n', ...
                    target_info.target_accuracy * 100, status, target_info.accuracy_gap * 100);
            end
        else
            fprintf('- %s: No samples\n', club_type);
        end
    end
end

if isfield(confusion_analysis, 'error_severity')
    fprintf('\nError Severity: %s\n', upper(confusion_analysis.error_severity.level));
    fprintf('%s\n', confusion_analysis.error_severity.description);
end

end