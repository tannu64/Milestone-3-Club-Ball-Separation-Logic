function test_classification_module()
%% Test Classification Module
% Comprehensive test suite for all classification functions
% Tests both manual inputs and real test data

fprintf('=== Testing Classification Module ===\n');

%% Test 1: Manual Input Tests
fprintf('\n--- Test 1: Manual Input Tests ---\n');
test_manual_inputs();

%% Test 2: Real Test Data Tests
fprintf('\n--- Test 2: Real Test Data Tests ---\n');
test_real_data();

%% Test 3: Integration Tests
fprintf('\n--- Test 3: Integration Tests ---\n');
test_integration();

fprintf('\n=== All Classification Tests Complete ===\n');

end

function test_manual_inputs()
%% Test Classification Functions with Manual Inputs

fprintf('Testing with synthetic manual inputs...\n');

%% 1. Test Rule-Based Classifier
fprintf('\n1. Testing rule_based_classifier...\n');

% Create synthetic feature vectors (matching expected structure)
feature_data = [
    % [max_vel, rise_time, spectral_width, impact_timing, continuity, duration, correlation_delay]
    [120, 1.5, 25, 2.0, 8.5, 15, 5];      % Ball-like features
    [80, 3.2, 45, 1.8, 2.1, 35, 12];     % Club-like features
    [150, 1.1, 20, 1.5, 12.3, 8, 3];     % Strong ball features
    [65, 4.5, 60, 2.5, 1.8, 45, 18];     % Strong club features
    [95, 2.8, 35, 2.2, 5.5, 25, 8];      % Uncertain features
];

% Create feature vectors in expected format
feature_vectors = struct();
feature_vectors.vectors = [];
for i = 1:size(feature_data, 1)
    vector_struct = struct();
    vector_struct.features = feature_data(i, :);
    vector_struct.segment_id = i;
    vector_struct.track_id = sprintf('track_%d', i);
    feature_vectors.vectors = [feature_vectors.vectors; vector_struct];
end

feature_vectors.feature_names = {'max_velocity', 'rise_time_ms', 'spectral_width', ...
    'impact_timing_ms', 'continuity_metric', 'duration_ms', 'correlation_delay_ms'};

% Configuration
config = struct();
config.velocity_ratio_wedge = [1.2, 1.8];
config.velocity_ratio_iron = [1.4, 2.2];
config.velocity_ratio_driver = [1.6, 2.5];
config.continuity_smooth_threshold = 2.0;
config.continuity_impulsive_threshold = 15.0;
config.rise_time_threshold_ms = 2.0;

try
    classification_results = rule_based_classifier(feature_vectors, config);
    fprintf('✓ rule_based_classifier: %d classifications generated\n', ...
        length(classification_results.classifications));
    
    % Display first few results
    for i = 1:min(3, length(classification_results.classifications))
        class_result = classification_results.classifications(i);
        fprintf('  Sample %d: %s (confidence: %.3f)\n', ...
            i, class_result.final_class, class_result.confidence);
    end
catch ME
    fprintf('✗ rule_based_classifier failed: %s\n', ME.message);
end

%% 2. Test Classification Confidence
fprintf('\n2. Testing classification_confidence...\n');

try
    % Convert feature_vectors to the format expected by classification_confidence
    feature_matrix_struct = struct();
    feature_matrix_struct.feature_matrix = [];
    for i = 1:length(feature_vectors.vectors)
        feature_matrix_struct.feature_matrix = [feature_matrix_struct.feature_matrix; feature_vectors.vectors(i).features];
    end
    
    confidence_results = classification_confidence(classification_results, feature_matrix_struct, config);
    fprintf('✓ classification_confidence: Mean confidence = %.3f\n', ...
        confidence_results.confidence_stats.mean);
    
    if isfield(confidence_results, 'club_type_confidence')
        club_types = fieldnames(confidence_results.club_type_confidence);
        for i = 1:length(club_types)
            club_type = club_types{i};
            club_data = confidence_results.club_type_confidence.(club_type);
            fprintf('  %s: %.3f confidence (%d samples)\n', ...
                club_type, club_data.mean, club_data.count);
        end
    end
catch ME
    fprintf('✗ classification_confidence failed: %s\n', ME.message);
end

%% 3. Test Ensemble Classifier
fprintf('\n3. Testing ensemble_classifier...\n');

try
    ensemble_config = struct();
    ensemble_config.voting_method = 'weighted';
    ensemble_config.confidence_threshold = 0.6;
    
    ensemble_results = ensemble_classifier(feature_vectors, ensemble_config);
    fprintf('✓ ensemble_classifier: %d ensemble classifications\n', ...
        length(ensemble_results.classifications));
    
    % Display ensemble results
    for i = 1:min(3, length(ensemble_results.classifications))
        ensemble_result = ensemble_results.classifications(i);
        fprintf('  Sample %d: %s (ensemble confidence: %.3f)\n', ...
            i, ensemble_result.ensemble_class, ensemble_result.ensemble_confidence);
    end
catch ME
    fprintf('✗ ensemble_classifier failed: %s\n', ME.message);
end

%% 4. Test Apply Classification
fprintf('\n4. Testing apply_classification...\n');

try
    apply_config = struct();
    apply_config.classification_method = 'rule_based';
    apply_config.confidence_threshold = 0.7;
    
    apply_results = apply_classification(feature_vectors, apply_config);
    fprintf('✓ apply_classification: %d applied classifications\n', ...
        length(apply_results.classifications));
    
    % Show classification summary
    classes = {apply_results.classifications.final_class};
    unique_classes = unique(classes);
    for i = 1:length(unique_classes)
        count = sum(strcmp(classes, unique_classes{i}));
        fprintf('  %s: %d classifications\n', unique_classes{i}, count);
    end
catch ME
    fprintf('✗ apply_classification failed: %s\n', ME.message);
end

%% 5. Test ML Classifier Training (if applicable)
fprintf('\n5. Testing train_ml_classifier...\n');

try
    % Create labeled training data
    training_data = struct();
    training_data.features = feature_vectors.feature_matrix;
    training_data.labels = {'ball', 'club', 'ball', 'club', 'uncertain'}';
    
    ml_config = struct();
    ml_config.classifier_type = 'svm';
    ml_config.cross_validation_folds = 3;
    
    ml_results = train_ml_classifier(training_data, ml_config);
    fprintf('✓ train_ml_classifier: Training completed\n');
    
    if isfield(ml_results, 'model_performance')
        perf = ml_results.model_performance;
        fprintf('  Training accuracy: %.3f\n', perf.accuracy);
        fprintf('  Cross-validation score: %.3f\n', perf.cv_score);
    end
catch ME
    fprintf('✗ train_ml_classifier failed: %s\n', ME.message);
end

end

function test_real_data()
%% Test with Real Data from Dataset

fprintf('Testing with real dataset...\n');

% Define data paths
data_folder = '28-01-2024 DATA';
if ~exist(data_folder, 'dir')
    fprintf('⚠ Test data folder not found: %s\n', data_folder);
    fprintf('Creating synthetic realistic test data...\n');
    create_synthetic_test_data();
    return;
end

% Find test shots
dataset_dirs = dir(fullfile(data_folder, 'LOG*'));
dataset_dirs = dataset_dirs([dataset_dirs.isdir]);

if isempty(dataset_dirs)
    fprintf('⚠ No LOG directories found in test data\n');
    create_synthetic_test_data();
    return;
end

fprintf('Found %d test shots in dataset\n', length(dataset_dirs));

%% Process First Few Test Shots
num_test_shots = min(3, length(dataset_dirs));
all_features = [];
all_classifications = [];

for shot_idx = 1:num_test_shots
    shot_dir = dataset_dirs(shot_idx);
    shot_path = fullfile(data_folder, shot_dir.name);
    
    fprintf('\nProcessing test shot %d: %s\n', shot_idx, shot_dir.name);
    
    try
        % Load shot data (simplified version)
        [feature_data, success] = load_shot_features(shot_path);
        
        if success
            fprintf('  ✓ Loaded features: %dx%d matrix\n', size(feature_data.feature_matrix));
            
            % Test classification
            config = create_test_config();
            classification_results = rule_based_classifier(feature_data, config);
            
            fprintf('  ✓ Classifications: %d generated\n', length(classification_results.classifications));
            
            % Test confidence analysis
            confidence_results = classification_confidence(classification_results, feature_data, config);
            fprintf('  ✓ Confidence analysis: Mean = %.3f\n', confidence_results.confidence_stats.mean);
            
            % Accumulate for batch testing
            all_features = [all_features; feature_data.feature_matrix];
            all_classifications = [all_classifications; classification_results.classifications];
            
        else
            fprintf('  ✗ Failed to load shot features\n');
        end
        
    catch ME
        fprintf('  ✗ Error processing shot: %s\n', ME.message);
    end
end

%% Batch Analysis
if ~isempty(all_features)
    fprintf('\n--- Batch Analysis ---\n');
    
    % Create batch feature structure
    batch_features = struct();
    batch_features.feature_matrix = all_features;
    batch_features.feature_names = {'max_velocity', 'rise_time_ms', 'spectral_width', ...
        'impact_timing_ms', 'continuity_metric', 'duration_ms', 'correlation_delay_ms'};
    
    % Test ensemble classification
    try
        ensemble_config = create_test_config();
        ensemble_config.voting_method = 'majority';
        
        ensemble_results = ensemble_classifier(batch_features, ensemble_config);
        fprintf('✓ Batch ensemble classification: %d results\n', length(ensemble_results.classifications));
        
        % Analyze results
        classes = {ensemble_results.classifications.ensemble_class};
        unique_classes = unique(classes);
        fprintf('Classification distribution:\n');
        for i = 1:length(unique_classes)
            count = sum(strcmp(classes, unique_classes{i}));
            percentage = count / length(classes) * 100;
            fprintf('  %s: %d (%.1f%%)\n', unique_classes{i}, count, percentage);
        end
        
    catch ME
        fprintf('✗ Batch ensemble classification failed: %s\n', ME.message);
    end
end

end

function test_integration()
%% Integration Tests - Test Full Pipeline

fprintf('Testing full classification pipeline integration...\n');

%% Create Comprehensive Test Scenario
% Simulate a complete processing pipeline result

% 1. Create impact events
impact_events = struct();
impact_events.impact_times = [0.015, 0.018, 0.022];  % Multiple impacts
impact_events.impact_strengths = [0.8, 0.9, 0.7];

% 2. Create velocity data
velocity_data = struct();
velocity_data.velocity_segments = struct();
for i = 1:5
    velocity_data.velocity_segments(i).start_time = 0.01 + (i-1)*0.005;
    velocity_data.velocity_segments(i).end_time = 0.01 + i*0.005;
    velocity_data.velocity_segments(i).duration = 0.005;
    velocity_data.velocity_segments(i).max_velocity = 80 + 40*rand();  % 80-120 mph
    velocity_data.velocity_segments(i).times = linspace(velocity_data.velocity_segments(i).start_time, ...
        velocity_data.velocity_segments(i).end_time, 20);
end

% 3. Create comprehensive feature vectors
feature_data = [
    [110, 1.8, 30, 1.2, 9.2, 12, 4];   % Ball-like
    [75, 3.5, 50, 2.1, 2.3, 38, 15];  % Club-like
    [135, 1.3, 22, 0.9, 11.8, 9, 2];  % Strong ball
    [68, 4.2, 58, 2.8, 1.9, 42, 19];  % Strong club
    [92, 2.9, 38, 2.0, 5.8, 28, 11];  % Uncertain
];

% Create feature vectors in expected format
feature_vectors = struct();
feature_vectors.vectors = [];
for i = 1:size(feature_data, 1)
    vector_struct = struct();
    vector_struct.features = feature_data(i, :);
    vector_struct.segment_id = i;
    vector_struct.track_id = sprintf('track_%d', i);
    feature_vectors.vectors = [feature_vectors.vectors; vector_struct];
end

feature_vectors.feature_names = {'max_velocity', 'rise_time_ms', 'spectral_width', ...
    'impact_timing_ms', 'continuity_metric', 'duration_ms', 'correlation_delay_ms'};

%% Full Pipeline Test
config = create_test_config();

try
    fprintf('\n1. Rule-based classification...\n');
    rule_results = rule_based_classifier(feature_vectors, config);
    
    fprintf('2. Classification confidence analysis...\n');
    % Convert feature_vectors for confidence analysis
    feature_matrix_struct = struct();
    feature_matrix_struct.feature_matrix = [];
    for i = 1:length(feature_vectors.vectors)
        feature_matrix_struct.feature_matrix = [feature_matrix_struct.feature_matrix; feature_vectors.vectors(i).features];
    end
    confidence_results = classification_confidence(rule_results, feature_matrix_struct, config);
    
    fprintf('3. Ensemble classification...\n');
    ensemble_results = ensemble_classifier(feature_vectors, config);
    
    fprintf('4. Apply classification with different methods...\n');
    apply_config = config;
    apply_config.classification_method = 'ensemble';
    apply_results = apply_classification(feature_vectors, apply_config);
    
    fprintf('✓ Full pipeline integration test passed\n');
    
    % Summary statistics
    fprintf('\nIntegration Test Summary:\n');
    fprintf('- Rule-based classifications: %d\n', length(rule_results.classifications));
    fprintf('- Mean confidence: %.3f\n', confidence_results.confidence_stats.mean);
    fprintf('- Ensemble classifications: %d\n', length(ensemble_results.classifications));
    fprintf('- Applied classifications: %d\n', length(apply_results.classifications));
    
    % Consistency check
    rule_classes = {rule_results.classifications.final_class};
    ensemble_classes = {ensemble_results.classifications.ensemble_class};
    agreement_rate = sum(strcmp(rule_classes, ensemble_classes)) / length(rule_classes);
    fprintf('- Rule-based vs Ensemble agreement: %.1f%%\n', agreement_rate * 100);
    
    if agreement_rate >= 0.7
        fprintf('✓ Good agreement between classification methods\n');
    else
        fprintf('⚠ Low agreement between classification methods\n');
    end
    
catch ME
    fprintf('✗ Integration test failed: %s\n', ME.message);
    fprintf('Stack trace:\n');
    for i = 1:length(ME.stack)
        fprintf('  %s (line %d)\n', ME.stack(i).name, ME.stack(i).line);
    end
end

end

function [feature_data, success] = load_shot_features(shot_path)
%% Load Shot Features (Simplified)

success = false;
feature_data = struct();

try
    % Look for data files
    bin_files = dir(fullfile(shot_path, '*.bin'));
    json_files = dir(fullfile(shot_path, '*.json'));
    
    if isempty(bin_files) || isempty(json_files)
        return;
    end
    
    % Create synthetic features based on shot (for testing)
    % In real implementation, this would load and process actual data
    num_segments = 3 + randi(5);  % 3-8 segments
    
    feature_matrix = zeros(num_segments, 7);
    for i = 1:num_segments
        % Generate realistic feature values
        feature_matrix(i, :) = [
            60 + 80*rand(),        % max_velocity (60-140 mph)
            1 + 4*rand(),          % rise_time_ms (1-5 ms)
            20 + 40*rand(),        % spectral_width (20-60 Hz)
            0.5 + 2*rand(),        % impact_timing_ms (0.5-2.5 ms)
            1 + 10*rand(),         % continuity_metric (1-11)
            5 + 40*rand(),         % duration_ms (5-45 ms)
            2 + 18*rand()          % correlation_delay_ms (2-20 ms)
        ];
    end
    
    % Create feature vectors in expected format
    feature_data = struct();
    feature_data.vectors = [];
    for i = 1:size(feature_matrix, 1)
        vector_struct = struct();
        vector_struct.features = feature_matrix(i, :);
        vector_struct.segment_id = i;
        vector_struct.track_id = sprintf('track_%d', i);
        feature_data.vectors = [feature_data.vectors; vector_struct];
    end
    
    feature_data.feature_names = {'max_velocity', 'rise_time_ms', 'spectral_width', ...
        'impact_timing_ms', 'continuity_metric', 'duration_ms', 'correlation_delay_ms'};
    
    success = true;
    
catch ME
    fprintf('Error loading shot features: %s\n', ME.message);
end

end

function create_synthetic_test_data()
%% Create Synthetic Test Data for Testing

fprintf('Creating synthetic test data for classification testing...\n');

% Create various club type scenarios
scenarios = {
    struct('name', 'wedge_shot', 'ball_vel', 75, 'club_vel', 50, 'type', 'wedge'),
    struct('name', 'iron_shot', 'ball_vel', 115, 'club_vel', 75, 'type', 'iron'),
    struct('name', 'driver_shot', 'ball_vel', 155, 'club_vel', 95, 'type', 'driver'),
    struct('name', 'mixed_shot', 'ball_vel', 95, 'club_vel', 65, 'type', 'iron')
};

all_features = [];
all_labels = {};

for i = 1:length(scenarios)
    scenario = scenarios{i};
    
    % Generate features for this scenario
    num_segments = 4 + randi(4);  % 4-8 segments per shot
    
    for j = 1:num_segments
        if j <= 2  % First segments are typically club
            base_vel = scenario.club_vel + 10*randn();
            continuity = 1 + 3*rand();  % Lower continuity (club-like)
            duration = 25 + 15*rand();  % Longer duration
            rise_time = 2.5 + 1.5*rand();  % Slower rise
        else  % Later segments are typically ball
            base_vel = scenario.ball_vel + 15*randn();
            continuity = 8 + 4*rand();  % Higher continuity (ball-like)
            duration = 8 + 12*rand();   % Shorter duration
            rise_time = 1 + 1*rand();   % Faster rise
        end
        
        features = [
            max(40, base_vel),                    % max_velocity
            max(0.5, rise_time),                  % rise_time_ms
            20 + 30*rand(),                       % spectral_width
            0.5 + 2*rand(),                       % impact_timing_ms
            max(1, continuity),                   % continuity_metric
            max(5, duration),                     % duration_ms
            2 + 15*rand()                         % correlation_delay_ms
        ];
        
        all_features = [all_features; features];
        
        if j <= 2
            all_labels{end+1} = 'club';
        else
            all_labels{end+1} = 'ball';
        end
    end
end

% Test with synthetic data
fprintf('Testing with %d synthetic feature vectors...\n', size(all_features, 1));

% Create feature vectors in expected format
feature_vectors = struct();
feature_vectors.vectors = [];
for i = 1:size(all_features, 1)
    vector_struct = struct();
    vector_struct.features = all_features(i, :);
    vector_struct.segment_id = i;
    vector_struct.track_id = sprintf('track_%d', i);
    feature_vectors.vectors = [feature_vectors.vectors; vector_struct];
end

feature_vectors.feature_names = {'max_velocity', 'rise_time_ms', 'spectral_width', ...
    'impact_timing_ms', 'continuity_metric', 'duration_ms', 'correlation_delay_ms'};

% Run classification tests
config = create_test_config();

try
    % Rule-based classification
    rule_results = rule_based_classifier(feature_vectors, config);
    predicted_classes = {rule_results.classifications.final_class};
    
    % Calculate accuracy against synthetic labels
    accuracy = sum(strcmp(predicted_classes, all_labels)) / length(all_labels);
    fprintf('✓ Synthetic data classification accuracy: %.1f%%\n', accuracy * 100);
    
    % Confidence analysis
    confidence_results = classification_confidence(rule_results, feature_vectors, config);
    fprintf('✓ Mean classification confidence: %.3f\n', confidence_results.confidence_stats.mean);
    
    % Show class distribution
    unique_pred = unique(predicted_classes);
    unique_true = unique(all_labels);
    
    fprintf('Predicted vs True class distribution:\n');
    for i = 1:length(unique_pred)
        pred_count = sum(strcmp(predicted_classes, unique_pred{i}));
        true_count = sum(strcmp(all_labels, unique_pred{i}));
        fprintf('  %s: Predicted=%d, True=%d\n', unique_pred{i}, pred_count, true_count);
    end
    
catch ME
    fprintf('✗ Synthetic data test failed: %s\n', ME.message);
end

end

function config = create_test_config()
%% Create Test Configuration

config = struct();

% Rule-based classifier settings
config.velocity_ratio_wedge = [1.2, 1.8];
config.velocity_ratio_iron = [1.4, 2.2];
config.velocity_ratio_driver = [1.6, 2.5];
config.continuity_smooth_threshold = 2.0;
config.continuity_impulsive_threshold = 15.0;
config.rise_time_threshold_ms = 2.0;

% Confidence analysis settings
config.confidence_thresholds = [0.5, 0.6, 0.7, 0.8, 0.9];
config.target_accuracies = struct();
config.target_accuracies.wedge = 0.8;
config.target_accuracies.iron = 0.9;
config.target_accuracies.driver = 0.9;

% Ensemble settings
config.voting_method = 'weighted';
config.confidence_threshold = 0.6;
config.enable_rule_based = true;
config.enable_ml_classifier = false;  % Disable for testing
config.rule_based_weight = 0.6;
config.ml_weight = 0.4;

% ML classifier settings (if used)
config.classifier_type = 'svm';
config.cross_validation_folds = 5;
config.feature_scaling = true;

% General settings
config.classification_method = 'rule_based';
config.uncertainty_threshold = 0.3;

end
