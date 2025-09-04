
function separation_metrics = compute_separation_metrics(classification_results, ground_truth, config)
%% Compute Separation Metrics
% Classification accuracy, precision, recall, F1 scores and other performance metrics
%
% Inputs:
%   classification_results - Results from apply_classification
%   ground_truth - Ground truth labels (optional, can be derived from TrackMan)
%   config - Configuration structure
%
% Outputs:
%   separation_metrics - Structure containing all performance metrics

% Validate inputs
if ~isstruct(classification_results) || ~isfield(classification_results, 'classifications')
    error('classification_results must contain classifications field');
end

% Default configuration
if nargin < 3 || isempty(config)
    config = struct();
end

if ~isfield(config, 'classes')
    config.classes = {'club', 'ball'};
end

classifications = classification_results.classifications;
num_classifications = length(classifications);

fprintf('Computing separation metrics for %d classifications...\n', num_classifications);

% Extract predicted labels and confidences
if isfield(classifications, 'ensemble_class')
    predicted_labels = {classifications.ensemble_class};
    predicted_confidences = [classifications.ensemble_confidence];
    method_used = 'ensemble';
elseif isfield(classifications, 'final_class')
    predicted_labels = {classifications.final_class};
    predicted_confidences = [classifications.confidence];
    method_used = 'rule_based';
else
    error('Cannot find classification labels in results');
end

%% Basic Classification Statistics
separation_metrics = struct();
separation_metrics.num_classifications = num_classifications;
separation_metrics.method_used = method_used;

% Count predictions by class
club_predictions = sum(strcmp(predicted_labels, 'club'));
ball_predictions = sum(strcmp(predicted_labels, 'ball'));
uncertain_predictions = sum(strcmp(predicted_labels, 'uncertain'));

separation_metrics.prediction_counts = struct();
separation_metrics.prediction_counts.club = club_predictions;
separation_metrics.prediction_counts.ball = ball_predictions;
separation_metrics.prediction_counts.uncertain = uncertain_predictions;
separation_metrics.prediction_counts.decisive = club_predictions + ball_predictions;
separation_metrics.prediction_counts.decisive_rate = separation_metrics.prediction_counts.decisive / num_classifications;

% Confidence statistics
separation_metrics.confidence_stats = struct();
separation_metrics.confidence_stats.mean = mean(predicted_confidences);
separation_metrics.confidence_stats.std = std(predicted_confidences);
separation_metrics.confidence_stats.min = min(predicted_confidences);
separation_metrics.confidence_stats.max = max(predicted_confidences);
separation_metrics.confidence_stats.median = median(predicted_confidences);

%% Ground Truth Comparison (if available)
if nargin >= 2 && ~isempty(ground_truth)
    
    % Ensure ground truth has same length
    if length(ground_truth) ~= num_classifications
        if length(ground_truth) > num_classifications
            ground_truth = ground_truth(1:num_classifications);
            warning('Ground truth truncated to match classification results');
        else
            error('Ground truth length (%d) does not match classifications (%d)', ...
                length(ground_truth), num_classifications);
        end
    end
    
    % Convert ground truth to consistent format
    if iscell(ground_truth)
        true_labels = ground_truth;
    else
        true_labels = cell(size(ground_truth));
        for i = 1:length(ground_truth)
            if ground_truth(i) == 1
                true_labels{i} = 'club';
            elseif ground_truth(i) == 2
                true_labels{i} = 'ball';
            else
                true_labels{i} = 'uncertain';
            end
        end
    end
    
    %% Confusion Matrix Computation
    classes = {'club', 'ball'};
    confusion_matrix = zeros(length(classes), length(classes));
    
    % Build confusion matrix (excluding uncertain predictions/truth)
    valid_indices = ~strcmp(predicted_labels, 'uncertain') & ~strcmp(true_labels, 'uncertain');
    valid_predicted = predicted_labels(valid_indices);
    valid_true = true_labels(valid_indices);
    
    for i = 1:length(classes)
        for j = 1:length(classes)
            confusion_matrix(i, j) = sum(strcmp(valid_true, classes{i}) & strcmp(valid_predicted, classes{j}));
        end
    end
    
    separation_metrics.confusion_matrix = confusion_matrix;
    separation_metrics.class_labels = classes;
    separation_metrics.valid_comparisons = length(valid_predicted);
    
    %% Performance Metrics Calculation
    if separation_metrics.valid_comparisons > 0
        % True/False Positives and Negatives for each class
        metrics_by_class = struct();
        
        for class_idx = 1:length(classes)
            class_name = classes{class_idx};
            
            % For binary classification metrics
            tp = confusion_matrix(class_idx, class_idx);  % True positives
            fp = sum(confusion_matrix(:, class_idx)) - tp;  % False positives
            fn = sum(confusion_matrix(class_idx, :)) - tp;  % False negatives
            tn = sum(confusion_matrix(:)) - tp - fp - fn;   % True negatives
            
            % Precision, Recall, F1
            precision = tp / max(tp + fp, 1);
            recall = tp / max(tp + fn, 1);
            f1_score = 2 * precision * recall / max(precision + recall, 1e-10);
            
            % Specificity and Accuracy
            specificity = tn / max(tn + fp, 1);
            accuracy = (tp + tn) / max(tp + tn + fp + fn, 1);
            
            metrics_by_class.(class_name) = struct();
            metrics_by_class.(class_name).true_positives = tp;
            metrics_by_class.(class_name).false_positives = fp;
            metrics_by_class.(class_name).false_negatives = fn;
            metrics_by_class.(class_name).true_negatives = tn;
            metrics_by_class.(class_name).precision = precision;
            metrics_by_class.(class_name).recall = recall;
            metrics_by_class.(class_name).f1_score = f1_score;
            metrics_by_class.(class_name).specificity = specificity;
            metrics_by_class.(class_name).accuracy = accuracy;
        end
        
        separation_metrics.metrics_by_class = metrics_by_class;
        
        % Overall metrics
        overall_accuracy = trace(confusion_matrix) / sum(confusion_matrix(:));
        
        % Macro-averaged metrics
        precisions = [metrics_by_class.club.precision, metrics_by_class.ball.precision];
        recalls = [metrics_by_class.club.recall, metrics_by_class.ball.recall];
        f1_scores = [metrics_by_class.club.f1_score, metrics_by_class.ball.f1_score];
        
        separation_metrics.overall_metrics = struct();
        separation_metrics.overall_metrics.accuracy = overall_accuracy;
        separation_metrics.overall_metrics.macro_precision = mean(precisions);
        separation_metrics.overall_metrics.macro_recall = mean(recalls);
        separation_metrics.overall_metrics.macro_f1 = mean(f1_scores);
        
        % Weighted metrics (by support)
        supports = [sum(confusion_matrix(1, :)), sum(confusion_matrix(2, :))];
        total_support = sum(supports);
        
        if total_support > 0
            weighted_precision = sum(precisions .* supports) / total_support;
            weighted_recall = sum(recalls .* supports) / total_support;
            weighted_f1 = sum(f1_scores .* supports) / total_support;
            
            separation_metrics.overall_metrics.weighted_precision = weighted_precision;
            separation_metrics.overall_metrics.weighted_recall = weighted_recall;
            separation_metrics.overall_metrics.weighted_f1 = weighted_f1;
        end
        
        %% Error Analysis
        % Find misclassified samples
        misclassified_indices = find(~strcmp(valid_predicted, valid_true));
        separation_metrics.error_analysis = struct();
        separation_metrics.error_analysis.num_errors = length(misclassified_indices);
        separation_metrics.error_analysis.error_rate = length(misclassified_indices) / length(valid_predicted);
        
        if ~isempty(misclassified_indices)
            % Analyze confidence of misclassified samples
            valid_confidences = predicted_confidences(valid_indices);
            error_confidences = valid_confidences(misclassified_indices);
            
            separation_metrics.error_analysis.mean_error_confidence = mean(error_confidences);
            separation_metrics.error_analysis.error_confidence_std = std(error_confidences);
            
            % High-confidence errors (potentially problematic)
            high_conf_errors = sum(error_confidences > 0.8);
            separation_metrics.error_analysis.high_confidence_errors = high_conf_errors;
            separation_metrics.error_analysis.high_confidence_error_rate = high_conf_errors / length(error_confidences);
        end
    end
    
    separation_metrics.has_ground_truth = true;
    
else
    separation_metrics.has_ground_truth = false;
    fprintf('No ground truth provided - computing prediction statistics only\n');
end

%% Confidence-based Analysis
confidence_thresholds = [0.5, 0.6, 0.7, 0.8, 0.9];
confidence_analysis = struct();

for thresh_idx = 1:length(confidence_thresholds)
    threshold = confidence_thresholds(thresh_idx);
    high_conf_mask = predicted_confidences >= threshold;
    
    confidence_analysis.(sprintf('threshold_%.1f', threshold)) = struct();
    confidence_analysis.(sprintf('threshold_%.1f', threshold)).count = sum(high_conf_mask);
    confidence_analysis.(sprintf('threshold_%.1f', threshold)).rate = sum(high_conf_mask) / num_classifications;
    
    if separation_metrics.has_ground_truth && sum(high_conf_mask) > 0
        high_conf_predicted = predicted_labels(high_conf_mask);
        high_conf_true = true_labels(high_conf_mask);
        
        % Accuracy for high-confidence predictions
        high_conf_correct = strcmp(high_conf_predicted, high_conf_true) & ...
                           ~strcmp(high_conf_predicted, 'uncertain') & ...
                           ~strcmp(high_conf_true, 'uncertain');
        
        if sum(~strcmp(high_conf_predicted, 'uncertain') & ~strcmp(high_conf_true, 'uncertain')) > 0
            high_conf_accuracy = sum(high_conf_correct) / ...
                sum(~strcmp(high_conf_predicted, 'uncertain') & ~strcmp(high_conf_true, 'uncertain'));
            confidence_analysis.(sprintf('threshold_%.1f', threshold)).accuracy = high_conf_accuracy;
        end
    end
end

separation_metrics.confidence_analysis = confidence_analysis;

%% Performance Summary
fprintf('\n=== Separation Metrics Summary ===\n');
fprintf('Total classifications: %d\n', num_classifications);
fprintf('Decisive classifications: %d (%.1f%%)\n', ...
    separation_metrics.prediction_counts.decisive, ...
    separation_metrics.prediction_counts.decisive_rate * 100);
fprintf('Club: %d, Ball: %d, Uncertain: %d\n', club_predictions, ball_predictions, uncertain_predictions);
fprintf('Mean confidence: %.3f (±%.3f)\n', ...
    separation_metrics.confidence_stats.mean, separation_metrics.confidence_stats.std);

if separation_metrics.has_ground_truth
    fprintf('\nAccuracy Metrics:\n');
    fprintf('Overall accuracy: %.3f\n', separation_metrics.overall_metrics.accuracy);
    fprintf('Macro F1-score: %.3f\n', separation_metrics.overall_metrics.macro_f1);
    fprintf('Club precision: %.3f, recall: %.3f\n', ...
        separation_metrics.metrics_by_class.club.precision, ...
        separation_metrics.metrics_by_class.club.recall);
    fprintf('Ball precision: %.3f, recall: %.3f\n', ...
        separation_metrics.metrics_by_class.ball.precision, ...
        separation_metrics.metrics_by_class.ball.recall);
    
    if separation_metrics.error_analysis.num_errors > 0
        fprintf('\nError Analysis:\n');
        fprintf('Errors: %d (%.1f%%)\n', separation_metrics.error_analysis.num_errors, ...
            separation_metrics.error_analysis.error_rate * 100);
        fprintf('Mean error confidence: %.3f\n', separation_metrics.error_analysis.mean_error_confidence);
    end
end

end