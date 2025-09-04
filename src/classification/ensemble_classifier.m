function ensemble_results = ensemble_classifier(feature_vectors, rule_based_results, trained_models, config)
%% Ensemble Classifier: Hybrid Rule-Based + ML
% Combine Rules based + ML for robustness

% Validate inputs
if ~isstruct(feature_vectors) || ~isfield(feature_vectors, 'feature_matrix')
    error('feature_vectors must contain feature_matrix field');
end

if ~isstruct(rule_based_results) || ~isfield(rule_based_results, 'classifications')
    error('rule_based_results must contain classifications field');
end

% Default configuration
if ~isfield(config, 'confidence_threshold')
    config.confidence_threshold = 0.7;
end
if ~isfield(config, 'rule_weight')
    config.rule_weight = 0.6;  % Rule-based weight
end
if ~isfield(config, 'ml_weight')
    config.ml_weight = 0.4;  % ML weight  
end

% Extract data
X = feature_vectors.feature_matrix;
rule_classifications = rule_based_results.classifications;
num_samples = size(X, 1);

fprintf('Running ensemble classification on %d samples...\n', num_samples);

% Initialize results
ensemble_classifications = [];

% Get ML predictions if available
ml_predictions_svm = [];
ml_confidence_svm = [];

if ~isempty(trained_models.svm_model) && trained_models.training_results.svm_training_success
    try
        % Normalize features
        X_norm = (X - trained_models.feature_normalization.mean) ./ trained_models.feature_normalization.std;
        
        if exist('fitcsvm', 'file') && ~isfield(trained_models.svm_model, 'type')
            [svm_pred, svm_scores] = predict(trained_models.svm_model, X_norm);
            ml_predictions_svm = svm_pred;
            ml_confidence_svm = abs(svm_scores(:, 1)) / max(abs(svm_scores(:, 1)));
        else
            svm_pred = predict_simple_svm(trained_models.svm_model, X_norm);
            ml_predictions_svm = svm_pred;
            ml_confidence_svm = ones(num_samples, 1) * 0.7;
        end
        
        fprintf('SVM predictions obtained\n');
    catch ME
        fprintf('SVM prediction failed: %s\n', ME.message);
        ml_predictions_svm = [];
    end
end

% Process each sample
for sample_idx = 1:num_samples
    rule_result = rule_classifications(sample_idx);
    
    % Rule-based classification
    rule_class = rule_result.final_class;
    rule_confidence = rule_result.confidence;
    
    % Initialize ensemble scores
    club_score = 0;
    ball_score = 0;
    total_weight = 0;
    
    % Rule-based contribution
    if strcmp(rule_class, 'club')
        club_score = club_score + config.rule_weight * rule_confidence;
        total_weight = total_weight + config.rule_weight;
    elseif strcmp(rule_class, 'ball')
        ball_score = ball_score + config.rule_weight * rule_confidence;
        total_weight = total_weight + config.rule_weight;
    end
    
    % ML contribution (if available)
    if ~isempty(ml_predictions_svm) && sample_idx <= length(ml_predictions_svm)
        ml_class = ml_predictions_svm(sample_idx);
        ml_conf = ml_confidence_svm(sample_idx);
        
        if ml_class == 1  % Club
            club_score = club_score + config.ml_weight * ml_conf;
        elseif ml_class == 2  % Ball
            ball_score = ball_score + config.ml_weight * ml_conf;
        end
        total_weight = total_weight + config.ml_weight;
    end
    
    % Final ensemble decision
    if total_weight > 0
        club_score = club_score / total_weight;
        ball_score = ball_score / total_weight;
    end
    
    if club_score > ball_score
        ensemble_class = 'club';
        ensemble_confidence = club_score;
    elseif ball_score > club_score
        ensemble_class = 'ball';
        ensemble_confidence = ball_score;
    else
        ensemble_class = 'uncertain';
        ensemble_confidence = 0.5;
    end
    
    % Store result
    ensemble_result = struct();
    ensemble_result.sample_idx = sample_idx;
    ensemble_result.track_idx = rule_result.track_idx;
    ensemble_result.ensemble_class = ensemble_class;
    ensemble_result.ensemble_confidence = ensemble_confidence;
    ensemble_result.is_high_confidence = ensemble_confidence >= config.confidence_threshold;
    ensemble_result.rule_class = rule_class;
    ensemble_result.rule_confidence = rule_confidence;
    ensemble_result.start_time = rule_result.start_time;
    ensemble_result.end_time = rule_result.end_time;
    
    ensemble_classifications = [ensemble_classifications; ensemble_result];
end

% Create output structure
ensemble_results = struct();
ensemble_results.num_classifications = length(ensemble_classifications);
ensemble_results.classifications = ensemble_classifications;
ensemble_results.config = config;

% Statistics
if ensemble_results.num_classifications > 0
    ensemble_classes = {ensemble_classifications.ensemble_class};
    club_count = sum(strcmp(ensemble_classes, 'club'));
    ball_count = sum(strcmp(ensemble_classes, 'ball'));
    uncertain_count = sum(strcmp(ensemble_classes, 'uncertain'));
    high_conf_count = sum([ensemble_classifications.is_high_confidence]);
    
    ensemble_results.ensemble_statistics = struct();
    ensemble_results.ensemble_statistics.club_count = club_count;
    ensemble_results.ensemble_statistics.ball_count = ball_count;
    ensemble_results.ensemble_statistics.uncertain_count = uncertain_count;
    ensemble_results.ensemble_statistics.high_confidence_count = high_conf_count;
    ensemble_results.ensemble_statistics.high_confidence_rate = high_conf_count / ensemble_results.num_classifications;
end

fprintf('Ensemble completed: %d club, %d ball, %d uncertain\n', club_count, ball_count, uncertain_count);

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