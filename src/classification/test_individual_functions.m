function test_individual_functions()
%% Test Individual Classification Functions
% Simple focused tests for each classification function

fprintf('=== Testing Individual Classification Functions ===\n');

%% Test Data Setup
fprintf('Setting up test data...\n');

% Create realistic test feature vectors
feature_vectors = create_test_feature_vectors();
config = create_basic_config();

%% Test 1: Rule-Based Classifier
fprintf('\n--- Test 1: Rule-Based Classifier ---\n');
test_rule_based_classifier(feature_vectors, config);

%% Test 2: Classification Confidence
fprintf('\n--- Test 2: Classification Confidence ---\n');
test_classification_confidence(feature_vectors, config);

%% Test 3: Ensemble Classifier
fprintf('\n--- Test 3: Ensemble Classifier ---\n');
test_ensemble_classifier(feature_vectors, config);

%% Test 4: Apply Classification
fprintf('\n--- Test 4: Apply Classification ---\n');
test_apply_classification(feature_vectors, config);

%% Test 5: ML Classifier Training
fprintf('\n--- Test 5: ML Classifier Training ---\n');
test_ml_classifier_training(feature_vectors, config);

fprintf('\n=== Individual Function Tests Complete ===\n');

end

function feature_vectors = create_test_feature_vectors()
%% Create Test Feature Vectors

fprintf('Creating test feature vectors...\n');

% Define realistic feature combinations
% [max_vel, rise_time, spectral_width, impact_timing, continuity, duration, correlation_delay]
test_data = [
    % Ball-like features (high velocity, low rise time, high continuity)
    [130, 1.2, 25, 1.5, 10.5, 12, 3];    % Strong ball signal
    [115, 1.8, 30, 1.8, 8.9, 15, 5];     % Moderate ball signal
    [145, 1.0, 20, 1.2, 12.1, 10, 2];    % Very strong ball signal
    
    % Club-like features (lower velocity, higher rise time, lower continuity)
    [75, 3.5, 45, 2.2, 2.1, 35, 14];     % Strong club signal
    [68, 4.2, 52, 2.8, 1.8, 42, 18];     % Very strong club signal
    [82, 3.0, 38, 2.5, 2.8, 30, 12];     % Moderate club signal
    
    % Uncertain/mixed features
    [95, 2.5, 35, 2.0, 5.5, 25, 8];      % Mixed characteristics
    [88, 2.8, 40, 2.3, 4.2, 28, 10];     % Uncertain signal
    [102, 2.2, 32, 1.9, 6.8, 22, 7];     % Borderline case
    
    % Edge cases
    [45, 5.0, 65, 3.0, 1.2, 50, 25];     % Very low velocity club
    [180, 0.8, 15, 0.8, 15.2, 8, 1];     % Very high velocity ball
];

% Create feature vectors in expected format
feature_vectors = struct();
feature_vectors.vectors = [];
for i = 1:size(test_data, 1)
    vector_struct = struct();
    vector_struct.features = test_data(i, :);
    vector_struct.segment_id = i;
    vector_struct.track_id = sprintf('track_%d', i);
    feature_vectors.vectors = [feature_vectors.vectors; vector_struct];
end

feature_vectors.feature_names = {
    'max_velocity', 'rise_time_ms', 'spectral_width', 'impact_timing_ms', ...
    'continuity_metric', 'duration_ms', 'correlation_delay_ms'
};

fprintf('Created %d test feature vectors\n', size(test_data, 1));

end

function config = create_basic_config()
%% Create Basic Configuration

config = struct();

% Rule-based classifier parameters
config.velocity_ratio_wedge = [1.2, 1.8];
config.velocity_ratio_iron = [1.4, 2.2];
config.velocity_ratio_driver = [1.6, 2.5];
config.continuity_smooth_threshold = 2.0;
config.continuity_impulsive_threshold = 15.0;
config.rise_time_threshold_ms = 2.0;

% Confidence parameters
config.confidence_thresholds = [0.5, 0.6, 0.7, 0.8, 0.9];
config.target_accuracies = struct();
config.target_accuracies.wedge = 0.8;
config.target_accuracies.iron = 0.9;
config.target_accuracies.driver = 0.9;

% Ensemble parameters
config.voting_method = 'weighted';
config.confidence_threshold = 0.6;
config.enable_rule_based = true;
config.enable_ml_classifier = false;

% General parameters
config.classification_method = 'rule_based';
config.uncertainty_threshold = 0.3;

end

function test_rule_based_classifier(feature_vectors, config)
%% Test Rule-Based Classifier

fprintf('Testing rule_based_classifier function...\n');

try
    % Call the function
    tic;
    results = rule_based_classifier(feature_vectors, config);
    elapsed_time = toc;
    
    % Verify output structure
    assert(isstruct(results), 'Output should be a struct');
    assert(isfield(results, 'classifications'), 'Should have classifications field');
    assert(isfield(results, 'processing_summary'), 'Should have processing_summary field');
    
    classifications = results.classifications;
    num_classifications = length(classifications);
    
    fprintf('✓ Function executed successfully\n');
    fprintf('  Processing time: %.3f seconds\n', elapsed_time);
    fprintf('  Number of classifications: %d\n', num_classifications);
    
    % Analyze results
    if num_classifications > 0
        % Check first classification structure
        first_class = classifications(1);
        required_fields = {'final_class', 'confidence', 'feature_vector'};
        
        for i = 1:length(required_fields)
            field = required_fields{i};
            assert(isfield(first_class, field), sprintf('Missing field: %s', field));
        end
        
        % Count class distributions
        classes = {classifications.final_class};
        unique_classes = unique(classes);
        
        fprintf('  Classification distribution:\n');
        for i = 1:length(unique_classes)
            count = sum(strcmp(classes, unique_classes{i}));
            percentage = count / num_classifications * 100;
            fprintf('    %s: %d (%.1f%%)\n', unique_classes{i}, count, percentage);
        end
        
        % Check confidence values
        confidences = [classifications.confidence];
        fprintf('  Confidence statistics:\n');
        fprintf('    Mean: %.3f, Std: %.3f\n', mean(confidences), std(confidences));
        fprintf('    Range: %.3f - %.3f\n', min(confidences), max(confidences));
        
        % Show sample results
        fprintf('  Sample classifications:\n');
        for i = 1:min(3, num_classifications)
            class_result = classifications(i);
            fprintf('    Sample %d: %s (conf: %.3f, vel: %.1f)\n', ...
                i, class_result.final_class, class_result.confidence, ...
                class_result.feature_vector(1));
        end
    end
    
catch ME
    fprintf('✗ rule_based_classifier test failed: %s\n', ME.message);
    if ~isempty(ME.stack)
        fprintf('  Error in: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
    end
end

end

function test_classification_confidence(feature_vectors, config)
%% Test Classification Confidence

fprintf('Testing classification_confidence function...\n');

try
    % First get classification results
    classification_results = rule_based_classifier(feature_vectors, config);
    
    % Convert feature_vectors to the format expected by classification_confidence
    feature_matrix_struct = struct();
    feature_matrix_struct.feature_matrix = [];
    for i = 1:length(feature_vectors.vectors)
        feature_matrix_struct.feature_matrix = [feature_matrix_struct.feature_matrix; feature_vectors.vectors(i).features];
    end
    
    % Test confidence analysis
    tic;
    confidence_results = classification_confidence(classification_results, feature_matrix_struct, config);
    elapsed_time = toc;
    
    % Verify output structure
    assert(isstruct(confidence_results), 'Output should be a struct');
    assert(isfield(confidence_results, 'confidence_stats'), 'Should have confidence_stats field');
    assert(isfield(confidence_results, 'quality_assessment'), 'Should have quality_assessment field');
    
    fprintf('✓ Function executed successfully\n');
    fprintf('  Processing time: %.3f seconds\n', elapsed_time);
    
    % Display results
    stats = confidence_results.confidence_stats;
    fprintf('  Confidence statistics:\n');
    fprintf('    Mean: %.3f ± %.3f\n', stats.mean, stats.std);
    fprintf('    Range: %.3f - %.3f\n', stats.min, stats.max);
    fprintf('    Median: %.3f\n', stats.median);
    
    if isfield(confidence_results, 'quality_assessment')
        qa = confidence_results.quality_assessment;
        fprintf('  Quality assessment:\n');
        fprintf('    Confidence quality: %s\n', qa.confidence_quality);
        fprintf('    Decisiveness: %s\n', qa.decisiveness);
        if isfield(qa, 'decisive_rate')
            fprintf('    Decisive rate: %.1f%%\n', qa.decisive_rate * 100);
        end
    end
    
    if isfield(confidence_results, 'club_type_confidence')
        fprintf('  Club type confidence:\n');
        club_types = fieldnames(confidence_results.club_type_confidence);
        for i = 1:length(club_types)
            club_type = club_types{i};
            club_data = confidence_results.club_type_confidence.(club_type);
            target_met = club_data.target_likely_met;
            status = char("✓" * target_met + "⚠" * ~target_met);
            fprintf('    %s: %.3f (%d samples) %s\n', ...
                club_type, club_data.mean, club_data.count, status);
        end
    end
    
catch ME
    fprintf('✗ classification_confidence test failed: %s\n', ME.message);
    if ~isempty(ME.stack)
        fprintf('  Error in: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
    end
end

end

function test_ensemble_classifier(feature_vectors, config)
%% Test Ensemble Classifier

fprintf('Testing ensemble_classifier function...\n');

try
    tic;
    ensemble_results = ensemble_classifier(feature_vectors, config);
    elapsed_time = toc;
    
    % Verify output structure
    assert(isstruct(ensemble_results), 'Output should be a struct');
    assert(isfield(ensemble_results, 'classifications'), 'Should have classifications field');
    
    classifications = ensemble_results.classifications;
    num_classifications = length(classifications);
    
    fprintf('✓ Function executed successfully\n');
    fprintf('  Processing time: %.3f seconds\n', elapsed_time);
    fprintf('  Number of ensemble classifications: %d\n', num_classifications);
    
    if num_classifications > 0
        % Check ensemble classification structure
        first_ensemble = classifications(1);
        required_fields = {'ensemble_class', 'ensemble_confidence', 'method_votes'};
        
        for i = 1:length(required_fields)
            field = required_fields{i};
            if ~isfield(first_ensemble, field)
                fprintf('  ⚠ Missing field: %s\n', field);
            end
        end
        
        % Analyze ensemble results
        if isfield(first_ensemble, 'ensemble_class')
            ensemble_classes = {classifications.ensemble_class};
            unique_classes = unique(ensemble_classes);
            
            fprintf('  Ensemble classification distribution:\n');
            for i = 1:length(unique_classes)
                count = sum(strcmp(ensemble_classes, unique_classes{i}));
                percentage = count / num_classifications * 100;
                fprintf('    %s: %d (%.1f%%)\n', unique_classes{i}, count, percentage);
            end
        end
        
        % Check ensemble confidence
        if isfield(first_ensemble, 'ensemble_confidence')
            ensemble_confidences = [classifications.ensemble_confidence];
            fprintf('  Ensemble confidence statistics:\n');
            fprintf('    Mean: %.3f, Std: %.3f\n', mean(ensemble_confidences), std(ensemble_confidences));
            fprintf('    Range: %.3f - %.3f\n', min(ensemble_confidences), max(ensemble_confidences));
        end
        
        % Show sample ensemble results
        fprintf('  Sample ensemble classifications:\n');
        for i = 1:min(3, num_classifications)
            ensemble_result = classifications(i);
            if isfield(ensemble_result, 'ensemble_class') && isfield(ensemble_result, 'ensemble_confidence')
                fprintf('    Sample %d: %s (ensemble conf: %.3f)\n', ...
                    i, ensemble_result.ensemble_class, ensemble_result.ensemble_confidence);
            end
        end
    end
    
catch ME
    fprintf('✗ ensemble_classifier test failed: %s\n', ME.message);
    if ~isempty(ME.stack)
        fprintf('  Error in: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
    end
end

end

function test_apply_classification(feature_vectors, config)
%% Test Apply Classification

fprintf('Testing apply_classification function...\n');

try
    % Test different classification methods
    methods = {'rule_based', 'ensemble'};
    
    for method_idx = 1:length(methods)
        method = methods{method_idx};
        fprintf('  Testing with method: %s\n', method);
        
        test_config = config;
        test_config.classification_method = method;
        
        tic;
        apply_results = apply_classification(feature_vectors, test_config);
        elapsed_time = toc;
        
        % Verify output
        assert(isstruct(apply_results), 'Output should be a struct');
        assert(isfield(apply_results, 'classifications'), 'Should have classifications field');
        
        classifications = apply_results.classifications;
        num_classifications = length(classifications);
        
        fprintf('    ✓ Method %s: %d classifications (%.3f s)\n', ...
            method, num_classifications, elapsed_time);
        
        if num_classifications > 0
            % Analyze method results
            if isfield(classifications(1), 'final_class')
                classes = {classifications.final_class};
                unique_classes = unique(classes);
                
                fprintf('    Distribution: ');
                for i = 1:length(unique_classes)
                    count = sum(strcmp(classes, unique_classes{i}));
                    fprintf('%s=%d ', unique_classes{i}, count);
                end
                fprintf('\n');
            end
        end
    end
    
    fprintf('✓ apply_classification test completed\n');
    
catch ME
    fprintf('✗ apply_classification test failed: %s\n', ME.message);
    if ~isempty(ME.stack)
        fprintf('  Error in: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
    end
end

end

function test_ml_classifier_training(feature_vectors, config)
%% Test ML Classifier Training

fprintf('Testing train_ml_classifier function...\n');

try
    % Create labeled training data
    num_samples = size(feature_vectors.feature_matrix, 1);
    
    % Create realistic labels based on features
    labels = cell(num_samples, 1);
    for i = 1:num_samples
        features = feature_vectors.feature_matrix(i, :);
        max_vel = features(1);
        continuity = features(5);
        
        % Simple labeling rule
        if max_vel > 120 && continuity > 8
            labels{i} = 'ball';
        elseif max_vel < 85 && continuity < 3
            labels{i} = 'club';
        else
            labels{i} = 'uncertain';
        end
    end
    
    % Extract features from feature_vectors structure
    feature_matrix = [];
    for i = 1:length(feature_vectors.vectors)
        feature_matrix = [feature_matrix; feature_vectors.vectors(i).features];
    end
    
    % Create training data structure
    training_data = struct();
    training_data.features = feature_matrix;
    training_data.labels = labels;
    
    % Test configuration
    ml_config = struct();
    ml_config.classifier_type = 'svm';
    ml_config.cross_validation_folds = 3;
    ml_config.feature_scaling = true;
    
    fprintf('  Training data: %d samples with %d features\n', ...
        size(training_data.features, 1), size(training_data.features, 2));
    
    % Count label distribution
    unique_labels = unique(labels);
    fprintf('  Label distribution: ');
    for i = 1:length(unique_labels)
        count = sum(strcmp(labels, unique_labels{i}));
        fprintf('%s=%d ', unique_labels{i}, count);
    end
    fprintf('\n');
    
    tic;
    ml_results = train_ml_classifier(training_data, ml_config);
    elapsed_time = toc;
    
    % Verify output
    assert(isstruct(ml_results), 'Output should be a struct');
    
    fprintf('✓ ML classifier training completed\n');
    fprintf('  Training time: %.3f seconds\n', elapsed_time);
    
    if isfield(ml_results, 'model_performance')
        perf = ml_results.model_performance;
        fprintf('  Performance metrics:\n');
        
        if isfield(perf, 'accuracy')
            fprintf('    Training accuracy: %.3f\n', perf.accuracy);
        end
        if isfield(perf, 'cv_score')
            fprintf('    Cross-validation score: %.3f ± %.3f\n', ...
                perf.cv_score, perf.cv_std);
        end
        if isfield(perf, 'confusion_matrix')
            fprintf('    Confusion matrix available\n');
        end
    end
    
    if isfield(ml_results, 'model_info')
        info = ml_results.model_info;
        if isfield(info, 'classifier_type')
            fprintf('  Model type: %s\n', info.classifier_type);
        end
        if isfield(info, 'num_features')
            fprintf('  Number of features: %d\n', info.num_features);
        end
    end
    
catch ME
    fprintf('✗ train_ml_classifier test failed: %s\n', ME.message);
    if ~isempty(ME.stack)
        fprintf('  Error in: %s (line %d)\n', ME.stack(1).name, ME.stack(1).line);
    end
end

end
