function classification_results = apply_classification(feature_vectors, trained_models, config)
%% Apply Classification
% Execute club/ball classification on feature vectors using trained models
%
% Inputs:
%   feature_vectors - 7D feature vectors from build_feature_vectors
%   trained_models - Trained ML models from train_ml_classifier (optional)
%   config - Configuration structure with classification parameters
%
% Outputs:
%   classification_results - Structure containing classification results

% Validate inputs
if ~isstruct(feature_vectors) || ~isfield(feature_vectors, 'feature_matrix')
    error('feature_vectors must contain feature_matrix field');
end

% Default configuration parameters
if nargin < 3 || isempty(config)
    config = struct();
end

if ~isfield(config, 'method')
    if nargin >= 2 && ~isempty(trained_models)
        config.method = 'ensemble';  % Use ensemble if models available
    else
        config.method = 'rule_based';  % Default to rule-based only
    end
end

if ~isfield(config, 'confidence_threshold')
    config.confidence_threshold = 0.7;
end

% Extract data
num_vectors = size(feature_vectors.feature_matrix, 1);
fprintf('Applying classification to %d feature vectors using %s method...\n', num_vectors, config.method);

%% Apply Classification Based on Method
switch lower(config.method)
    case 'rule_based'
        % Rule-based classification only
        if ~isfield(config, 'rule_based')
            % Create default rule-based config
            config.rule_based = struct();
            config.rule_based.velocity_ratio_wedge = [1.2, 1.8];
            config.rule_based.velocity_ratio_iron = [1.4, 2.2];
            config.rule_based.velocity_ratio_driver = [1.6, 2.5];
            config.rule_based.continuity_smooth_threshold = 2.0;
            config.rule_based.continuity_impulsive_threshold = 15.0;
            config.rule_based.rise_time_threshold_ms = 2.0;
        end
        
        classification_results = rule_based_classifier(feature_vectors, config.rule_based);
        classification_results.method_used = 'rule_based';
        
    case 'ml_only'
        % Machine learning only
        if isempty(trained_models)
            error('ML classification requested but no trained models provided');
        end
        
        classification_results = apply_ml_classification(feature_vectors, trained_models, config);
        classification_results.method_used = 'ml_only';
        
    case 'ensemble'
        % Hybrid: Rule-based + ML ensemble
        if isempty(trained_models)
            warning('Ensemble requested but no ML models available. Falling back to rule-based.');
            config.method = 'rule_based';
            classification_results = apply_classification(feature_vectors, [], config);
            return;
        end
        
        % First get rule-based results
        rule_config = config;
        if ~isfield(rule_config, 'rule_based')
            rule_config.rule_based = struct();
            rule_config.rule_based.velocity_ratio_wedge = [1.2, 1.8];
            rule_config.rule_based.velocity_ratio_iron = [1.4, 2.2];
            rule_config.rule_based.velocity_ratio_driver = [1.6, 2.5];
            rule_config.rule_based.continuity_smooth_threshold = 2.0;
            rule_config.rule_based.continuity_impulsive_threshold = 15.0;
            rule_config.rule_based.rise_time_threshold_ms = 2.0;
        end
        
        rule_based_results = rule_based_classifier(feature_vectors, rule_config.rule_based);
        
        % Then apply ensemble
        ensemble_config = config;
        if ~isfield(ensemble_config, 'rule_weight')
            ensemble_config.rule_weight = 0.6;
        end
        if ~isfield(ensemble_config, 'ml_weight')
            ensemble_config.ml_weight = 0.4;
        end
        
        classification_results = ensemble_classifier(feature_vectors, rule_based_results, trained_models, ensemble_config);
        classification_results.method_used = 'ensemble';
        classification_results.rule_based_results = rule_based_results;
        
    otherwise
        error('Unknown classification method: %s. Use rule_based, ml_only, or ensemble.', config.method);
end

%% Post-processing and Quality Assessment
classification_results.config = config;
classification_results.processing_timestamp = datetime('now');

% Compute classification statistics
if isfield(classification_results, 'classifications') && ~isempty(classification_results.classifications)
    classifications = classification_results.classifications;
    
    % Count classifications by type
    if strcmp(config.method, 'ensemble')
        class_labels = {classifications.ensemble_class};
        confidences = [classifications.ensemble_confidence];
        high_confidence_flags = [classifications.is_high_confidence];
    else
        class_labels = {classifications.final_class};
        confidences = [classifications.confidence];
        high_confidence_flags = confidences >= config.confidence_threshold;
    end
    
    club_count = sum(strcmp(class_labels, 'club'));
    ball_count = sum(strcmp(class_labels, 'ball'));
    uncertain_count = sum(strcmp(class_labels, 'uncertain'));
    high_confidence_count = sum(high_confidence_flags);
    
    % Store statistics
    classification_results.classification_summary = struct();
    classification_results.classification_summary.total_classifications = length(classifications);
    classification_results.classification_summary.club_count = club_count;
    classification_results.classification_summary.ball_count = ball_count;
    classification_results.classification_summary.uncertain_count = uncertain_count;
    classification_results.classification_summary.high_confidence_count = high_confidence_count;
    classification_results.classification_summary.high_confidence_rate = high_confidence_count / length(classifications);
    classification_results.classification_summary.mean_confidence = mean(confidences);
    classification_results.classification_summary.confidence_std = std(confidences);
    
    % Quality indicators
    classification_results.quality_indicators = struct();
    classification_results.quality_indicators.decisive_rate = (club_count + ball_count) / length(classifications);
    classification_results.quality_indicators.uncertainty_rate = uncertain_count / length(classifications);
    classification_results.quality_indicators.confidence_distribution = [min(confidences), mean(confidences), max(confidences)];
    
    fprintf('Classification completed:\n');
    fprintf('- Club: %d, Ball: %d, Uncertain: %d\n', club_count, ball_count, uncertain_count);
    fprintf('- High confidence: %d/%d (%.1f%%)\n', high_confidence_count, length(classifications), ...
        classification_results.classification_summary.high_confidence_rate * 100);
    fprintf('- Mean confidence: %.3f\n', classification_results.classification_summary.mean_confidence);
end

end

function ml_results = apply_ml_classification(feature_vectors, trained_models, config)
%% Apply ML Classification Only
% Pure machine learning classification without rule-based component

X = feature_vectors.feature_matrix;
num_samples = size(X, 1);

% Normalize features
if isfield(trained_models, 'feature_normalization')
    X_norm = (X - trained_models.feature_normalization.mean) ./ trained_models.feature_normalization.std;
else
    X_norm = X;
end

% Initialize results
ml_classifications = [];

% Apply SVM if available
svm_predictions = [];
svm_confidences = [];
if ~isempty(trained_models.svm_model) && trained_models.training_results.svm_training_success
    try
        if exist('fitcsvm', 'file') && ~isfield(trained_models.svm_model, 'type')
            [svm_pred, svm_scores] = predict(trained_models.svm_model, X_norm);
            svm_predictions = svm_pred;
            svm_confidences = abs(svm_scores(:, 1)) / max(abs(svm_scores(:, 1)));
        else
            svm_pred = predict_simple_svm(trained_models.svm_model, X_norm);
            svm_predictions = svm_pred;
            svm_confidences = ones(num_samples, 1) * 0.7;
        end
    catch ME
        fprintf('SVM prediction failed: %s\n', ME.message);
    end
end

% Apply Random Forest if available
rf_predictions = [];
rf_confidences = [];
if ~isempty(trained_models.rf_model) && trained_models.training_results.rf_training_success
    try
        if exist('TreeBagger', 'file') && isa(trained_models.rf_model, 'TreeBagger')
            [rf_pred_cell, rf_scores] = predict(trained_models.rf_model, X_norm);
            rf_predictions = cellfun(@str2double, rf_pred_cell);
            rf_confidences = max(rf_scores, [], 2);
        else
            rf_pred = predict_simple_rf(trained_models.rf_model, X_norm);
            rf_predictions = rf_pred;
            rf_confidences = ones(num_samples, 1) * 0.8;
        end
    catch ME
        fprintf('Random Forest prediction failed: %s\n', ME.message);
    end
end

% Combine ML predictions
for sample_idx = 1:num_samples
    % Initialize voting
    club_votes = 0;
    ball_votes = 0;
    total_confidence = 0;
    
    % SVM vote
    if ~isempty(svm_predictions) && sample_idx <= length(svm_predictions)
        if svm_predictions(sample_idx) == 1
            club_votes = club_votes + svm_confidences(sample_idx);
        elseif svm_predictions(sample_idx) == 2
            ball_votes = ball_votes + svm_confidences(sample_idx);
        end
        total_confidence = total_confidence + svm_confidences(sample_idx);
    end
    
    % Random Forest vote
    if ~isempty(rf_predictions) && sample_idx <= length(rf_predictions)
        if rf_predictions(sample_idx) == 1
            club_votes = club_votes + rf_confidences(sample_idx);
        elseif rf_predictions(sample_idx) == 2
            ball_votes = ball_votes + rf_confidences(sample_idx);
        end
        total_confidence = total_confidence + rf_confidences(sample_idx);
    end
    
    % Final ML decision
    if club_votes > ball_votes
        final_class = 'club';
        confidence = club_votes / max(total_confidence, 1);
    elseif ball_votes > club_votes
        final_class = 'ball';
        confidence = ball_votes / max(total_confidence, 1);
    else
        final_class = 'uncertain';
        confidence = 0.5;
    end
    
    % Store result
    ml_result = struct();
    ml_result.sample_idx = sample_idx;
    ml_result.track_idx = sample_idx;  % Default mapping
    ml_result.final_class = final_class;
    ml_result.confidence = confidence;
    ml_result.feature_vector = X(sample_idx, :);
    
    ml_classifications = [ml_classifications; ml_result];
end

% Create output structure
ml_results = struct();
ml_results.num_classifications = length(ml_classifications);
ml_results.classifications = ml_classifications;
ml_results.trained_models_info = struct();
ml_results.trained_models_info.svm_available = ~isempty(svm_predictions);
ml_results.trained_models_info.rf_available = ~isempty(rf_predictions);

end

function predictions = predict_simple_svm(model, X)
if strcmp(model.type, 'simple_linear')
    distances = zeros(size(X, 1), 2);
    for class = 1:2
        distances(:, class) = sqrt(sum((X - model.class_means(class, :)).^2, 2));
    end
    [~, predictions] = min(distances, [], 2);
else
    predictions = ones(size(X, 1), 1);
end
end

function predictions = predict_simple_rf(model, X)
if strcmp(model.type, 'simple_rf')
    n_samples = size(X, 1);
    n_trees = length(model.trees);
    
    tree_predictions = zeros(n_samples, n_trees);
    
    for tree_idx = 1:n_trees
        tree = model.trees{tree_idx};
        tree_predictions(:, tree_idx) = (X(:, tree.feature) > tree.threshold) + 1;
    end
    
    predictions = mode(tree_predictions, 2);
else
    predictions = ones(size(X, 1), 1);
end
end