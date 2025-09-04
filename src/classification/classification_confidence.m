
function confidence_results = classification_confidence(classification_results, feature_vectors, config)
%% Classification Confidence
% Uncertainty quantification for classifications
% Target: 80% wedge accuracy and 90% iron/driver accuracy

% Validate inputs
if ~isstruct(classification_results) || ~isfield(classification_results, 'classifications')
    error('classification_results must contain classifications field');
end

if ~isstruct(feature_vectors) || ~isfield(feature_vectors, 'feature_matrix')
    error('feature_vectors must contain feature_matrix field');
end

% Default configuration
if nargin < 3 || isempty(config)
    config = struct();
end

if ~isfield(config, 'confidence_thresholds')
    config.confidence_thresholds = [0.5, 0.6, 0.7, 0.8, 0.9];
end

if ~isfield(config, 'target_accuracies')
    config.target_accuracies = struct();
    config.target_accuracies.wedge = 0.8;   % 80%
    config.target_accuracies.iron = 0.9;    % 90%
    config.target_accuracies.driver = 0.9;  % 90%
end

classifications = classification_results.classifications;
feature_matrix = feature_vectors.feature_matrix;
num_classifications = length(classifications);

fprintf('Computing classification confidence for %d classifications...\n', num_classifications);

%% Extract Classification Data
if isfield(classifications, 'ensemble_class')
    predicted_classes = {classifications.ensemble_class};
    predicted_confidences = [classifications.ensemble_confidence];
    method_used = 'ensemble';
elseif isfield(classifications, 'final_class')
    predicted_classes = {classifications.final_class};
    predicted_confidences = [classifications.confidence];
    method_used = 'rule_based';
else
    error('Cannot find classification results');
end

%% Confidence Distribution Analysis
confidence_results = struct();
confidence_results.method_used = method_used;
confidence_results.num_classifications = num_classifications;

% Basic confidence statistics
confidence_results.confidence_stats = struct();
confidence_results.confidence_stats.mean = mean(predicted_confidences);
confidence_results.confidence_stats.std = std(predicted_confidences);
confidence_results.confidence_stats.min = min(predicted_confidences);
confidence_results.confidence_stats.max = max(predicted_confidences);
confidence_results.confidence_stats.median = median(predicted_confidences);

% Confidence distribution by class
club_indices = strcmp(predicted_classes, 'club');
ball_indices = strcmp(predicted_classes, 'ball');
uncertain_indices = strcmp(predicted_classes, 'uncertain');

confidence_results.class_confidence = struct();
if sum(club_indices) > 0
    confidence_results.class_confidence.club_mean = mean(predicted_confidences(club_indices));
    confidence_results.class_confidence.club_std = std(predicted_confidences(club_indices));
    confidence_results.class_confidence.club_count = sum(club_indices);
end

if sum(ball_indices) > 0
    confidence_results.class_confidence.ball_mean = mean(predicted_confidences(ball_indices));
    confidence_results.class_confidence.ball_std = std(predicted_confidences(ball_indices));
    confidence_results.class_confidence.ball_count = sum(ball_indices);
end

if sum(uncertain_indices) > 0
    confidence_results.class_confidence.uncertain_mean = mean(predicted_confidences(uncertain_indices));
    confidence_results.class_confidence.uncertain_count = sum(uncertain_indices);
end

%% Confidence Threshold Analysis
threshold_analysis = struct();

for i = 1:length(config.confidence_thresholds)
    threshold = config.confidence_thresholds(i);
    high_conf_mask = predicted_confidences >= threshold;
    
    threshold_key = sprintf('threshold_%.1f', threshold);
    threshold_analysis.(threshold_key) = struct();
    threshold_analysis.(threshold_key).count = sum(high_conf_mask);
    threshold_analysis.(threshold_key).rate = sum(high_conf_mask) / num_classifications;
    
    if sum(high_conf_mask) > 0
        high_conf_classes = predicted_classes(high_conf_mask);
        threshold_analysis.(threshold_key).club_count = sum(strcmp(high_conf_classes, 'club'));
        threshold_analysis.(threshold_key).ball_count = sum(strcmp(high_conf_classes, 'ball'));
        threshold_analysis.(threshold_key).uncertain_count = sum(strcmp(high_conf_classes, 'uncertain'));
    end
end

confidence_results.threshold_analysis = threshold_analysis;

%% Feature-Based Confidence Analysis
% Analyze confidence vs feature values
if size(feature_matrix, 1) == num_classifications
    feature_names = {'max_velocity', 'rise_time_ms', 'spectral_width', 'impact_timing_ms', ...
                    'continuity_metric', 'duration_ms', 'correlation_delay_ms'};
    
    feature_confidence_correlation = struct();
    
    for feat_idx = 1:min(size(feature_matrix, 2), length(feature_names))
        feature_name = feature_names{feat_idx};
        feature_values = feature_matrix(:, feat_idx);
        
        % Compute correlation with confidence
        correlation_coeff = corr(feature_values, predicted_confidences');
        
        feature_confidence_correlation.(feature_name) = struct();
        feature_confidence_correlation.(feature_name).correlation = correlation_coeff;
        
        % High vs low confidence feature statistics
        high_conf_mask = predicted_confidences >= 0.7;
        if sum(high_conf_mask) > 0 && sum(~high_conf_mask) > 0
            feature_confidence_correlation.(feature_name).high_conf_mean = mean(feature_values(high_conf_mask));
            feature_confidence_correlation.(feature_name).low_conf_mean = mean(feature_values(~high_conf_mask));
            feature_confidence_correlation.(feature_name).difference = ...
                feature_confidence_correlation.(feature_name).high_conf_mean - ...
                feature_confidence_correlation.(feature_name).low_conf_mean;
        end
    end
    
    confidence_results.feature_confidence_correlation = feature_confidence_correlation;
end

%% Club Type Confidence Analysis
% Estimate club type from velocities and analyze confidence
club_type_confidence = struct();

for class_idx = 1:num_classifications
    classification = classifications(class_idx);
    
    % Get velocity information if available
    if isfield(classification, 'feature_vector') && length(classification.feature_vector) >= 1
        max_velocity = classification.feature_vector(1);  % First feature is max_velocity
        
        % Estimate club type from velocity
        if max_velocity < 90
            estimated_club_type = 'wedge';
        elseif max_velocity < 140
            estimated_club_type = 'iron';
        else
            estimated_club_type = 'driver';
        end
        
        % Store confidence by club type
        if ~isfield(club_type_confidence, estimated_club_type)
            club_type_confidence.(estimated_club_type) = [];
        end
        club_type_confidence.(estimated_club_type) = [club_type_confidence.(estimated_club_type); predicted_confidences(class_idx)];
    end
end

% Compute statistics for each club type
club_types = {'wedge', 'iron', 'driver'};
for i = 1:length(club_types)
    club_type = club_types{i};
    if isfield(club_type_confidence, club_type) && ~isempty(club_type_confidence.(club_type))
        confidences = club_type_confidence.(club_type);
        
        confidence_results.club_type_confidence.(club_type) = struct();
        confidence_results.club_type_confidence.(club_type).mean = mean(confidences);
        confidence_results.club_type_confidence.(club_type).std = std(confidences);
        confidence_results.club_type_confidence.(club_type).count = length(confidences);
        confidence_results.club_type_confidence.(club_type).high_conf_rate = sum(confidences >= 0.7) / length(confidences);
        
        % Target achievement estimate
        target_accuracy = config.target_accuracies.(club_type);
        estimated_accuracy = confidence_results.club_type_confidence.(club_type).mean;
        confidence_results.club_type_confidence.(club_type).target_accuracy = target_accuracy;
        confidence_results.club_type_confidence.(club_type).estimated_accuracy = estimated_accuracy;
        confidence_results.club_type_confidence.(club_type).target_likely_met = estimated_accuracy >= target_accuracy * 0.9;  % 90% of target
    end
end

%% Uncertainty Quantification
uncertainty_analysis = struct();

% Entropy-based uncertainty (for multi-class)
class_counts = [sum(club_indices), sum(ball_indices), sum(uncertain_indices)];
class_probs = class_counts / sum(class_counts);
class_probs(class_probs == 0) = eps;  % Avoid log(0)

entropy = -sum(class_probs .* log2(class_probs));
max_entropy = log2(3);  % Maximum entropy for 3 classes
normalized_entropy = entropy / max_entropy;

uncertainty_analysis.entropy = entropy;
uncertainty_analysis.normalized_entropy = normalized_entropy;
uncertainty_analysis.predictive_uncertainty = 1 - normalized_entropy;

% Confidence-based uncertainty measures
uncertainty_analysis.mean_confidence_uncertainty = 1 - mean(predicted_confidences);
uncertainty_analysis.confidence_variance = var(predicted_confidences);

% High uncertainty classifications (low confidence)
low_confidence_threshold = 0.6;
high_uncertainty_mask = predicted_confidences < low_confidence_threshold;
uncertainty_analysis.high_uncertainty_count = sum(high_uncertainty_mask);
uncertainty_analysis.high_uncertainty_rate = sum(high_uncertainty_mask) / num_classifications;

confidence_results.uncertainty_analysis = uncertainty_analysis;

%% Quality Assessment
quality_assessment = struct();

% Overall confidence quality
mean_confidence = confidence_results.confidence_stats.mean;
if mean_confidence >= 0.8
    quality_assessment.confidence_quality = 'high';
elseif mean_confidence >= 0.7
    quality_assessment.confidence_quality = 'good';
elseif mean_confidence >= 0.6
    quality_assessment.confidence_quality = 'moderate';
else
    quality_assessment.confidence_quality = 'low';
end

% Decisive classification rate
decisive_rate = (sum(club_indices) + sum(ball_indices)) / num_classifications;
quality_assessment.decisive_rate = decisive_rate;

if decisive_rate >= 0.9
    quality_assessment.decisiveness = 'high';
elseif decisive_rate >= 0.8
    quality_assessment.decisiveness = 'good';
else
    quality_assessment.decisiveness = 'low';
end

confidence_results.quality_assessment = quality_assessment;

%% Generate Report
fprintf('\n=== Classification Confidence Analysis ===\n');
fprintf('Method used: %s\n', method_used);
fprintf('Total classifications: %d\n', num_classifications);

fprintf('\nConfidence Statistics:\n');
fprintf('Mean confidence: %.3f ± %.3f\n', confidence_results.confidence_stats.mean, confidence_results.confidence_stats.std);
fprintf('Confidence range: %.3f - %.3f\n', confidence_results.confidence_stats.min, confidence_results.confidence_stats.max);

fprintf('\nClass Distribution:\n');
fprintf('Club: %d (%.1f%%), Ball: %d (%.1f%%), Uncertain: %d (%.1f%%)\n', ...
    sum(club_indices), sum(club_indices)/num_classifications*100, ...
    sum(ball_indices), sum(ball_indices)/num_classifications*100, ...
    sum(uncertain_indices), sum(uncertain_indices)/num_classifications*100);

fprintf('\nQuality Assessment:\n');
fprintf('Confidence quality: %s\n', quality_assessment.confidence_quality);
fprintf('Decisiveness: %s (%.1f%% decisive)\n', quality_assessment.decisiveness, decisive_rate*100);
fprintf('Uncertainty level: %.1f%% (entropy-based)\n', normalized_entropy*100);

if isfield(confidence_results, 'club_type_confidence')
    fprintf('\nClub Type Confidence:\n');
    for i = 1:length(club_types)
        club_type = club_types{i};
        if isfield(confidence_results.club_type_confidence, club_type)
            club_data = confidence_results.club_type_confidence.(club_type);
            target_status = char("likely" * club_data.target_likely_met + "unlikely" * ~club_data.target_likely_met);
            fprintf('- %s: %.3f confidence (%d samples) - Target %.0f%% %s met\n', ...
                club_type, club_data.mean, club_data.count, club_data.target_accuracy*100, target_status);
        end
    end
end

fprintf('Classification confidence analysis completed.\n');

end