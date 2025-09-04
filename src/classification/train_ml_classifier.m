function trained_models = train_ml_classifier(feature_vectors, ground_truth_labels, config)
%% Train Machine Learning Classifiers
% SVM (RBF KERNEL γ=0.1) and Random Forest Training for club/ball classification
%
% Inputs:
%   feature_vectors - 7D feature vectors from build_feature_vectors
%   ground_truth_labels - Ground truth labels ('club' or 'ball')
%   config - Configuration structure with ML parameters
%
% Outputs:
%   trained_models - Structure containing trained SVM and Random Forest models

% Validate inputs
if ~isstruct(feature_vectors) || ~isfield(feature_vectors, 'feature_matrix')
    error('feature_vectors must contain feature_matrix field');
end

if length(ground_truth_labels) ~= size(feature_vectors.feature_matrix, 1)
    error('Number of labels must match number of feature vectors');
end

% Default configuration parameters
if ~isfield(config, 'svm')
    config.svm = struct();
end
if ~isfield(config.svm, 'kernel')
    config.svm.kernel = 'rbf';
end
if ~isfield(config.svm, 'gamma')
    config.svm.gamma = 0.1;  % γ = 0.1 from specification
end
if ~isfield(config.svm, 'C')
    config.svm.C = 1.0;  % C = 1.0 from specification
end

if ~isfield(config, 'random_forest')
    config.random_forest = struct();
end
if ~isfield(config.random_forest, 'n_estimators')
    config.random_forest.n_estimators = 100;  % 100 trees from specification
end
if ~isfield(config.random_forest, 'max_depth')
    config.random_forest.max_depth = 10;  % Max depth 10 from specification
end

% Extract feature matrix and prepare data
X = feature_vectors.feature_matrix;
y = ground_truth_labels;

% Convert string labels to numeric for MATLAB compatibility
if iscell(y)
    unique_labels = unique(y);
    y_numeric = zeros(length(y), 1);
    for i = 1:length(y)
        y_numeric(i) = find(strcmp(y{i}, unique_labels));
    end
    label_map = unique_labels;
else
    y_numeric = y;
    label_map = {'club', 'ball'};  % Default mapping
end

fprintf('Training ML classifiers on %d samples with %d features...\n', size(X, 1), size(X, 2));
fprintf('Label distribution: ');
for i = 1:length(label_map)
    count = sum(strcmp(y, label_map{i}));
    fprintf('%s: %d (%.1f%%) ', label_map{i}, count, count/length(y)*100);
end
fprintf('\n');

% Feature normalization (important for SVM)
X_mean = mean(X, 1);
X_std = std(X, 1);
X_std(X_std == 0) = 1;  % Avoid division by zero
X_normalized = (X - X_mean) ./ X_std;

% Data splitting for training and validation
train_ratio = 0.8;
n_samples = size(X, 1);
n_train = round(train_ratio * n_samples);

% Random split
rng(42);  % For reproducibility
rand_indices = randperm(n_samples);
train_indices = rand_indices(1:n_train);
val_indices = rand_indices(n_train+1:end);

X_train = X_normalized(train_indices, :);
X_val = X_normalized(val_indices, :);
y_train = y_numeric(train_indices);
y_val = y_numeric(val_indices);

fprintf('Training set: %d samples, Validation set: %d samples\n', length(train_indices), length(val_indices));

%% Train SVM Classifier
fprintf('\n--- Training SVM Classifier ---\n');
fprintf('Parameters: RBF kernel, γ=%.1f, C=%.1f\n', config.svm.gamma, config.svm.C);

try
    % Check if Statistics and Machine Learning Toolbox is available
    if exist('fitcsvm', 'file')
        % Use MATLAB's built-in SVM
        svm_model = fitcsvm(X_train, y_train, ...
            'KernelFunction', 'rbf', ...
            'BoxConstraint', config.svm.C, ...
            'KernelScale', 1/sqrt(2*config.svm.gamma));  % Convert gamma to KernelScale
        
        % Validate SVM
        svm_predictions = predict(svm_model, X_val);
        svm_accuracy = sum(svm_predictions == y_val) / length(y_val);
        
        fprintf('SVM training completed. Validation accuracy: %.3f\n', svm_accuracy);
        
    else
        % Fallback: Simple implementation for systems without ML toolbox
        fprintf('Statistics and Machine Learning Toolbox not available. Using simplified SVM.\n');
        svm_model = train_simple_svm(X_train, y_train, config.svm);
        
        % Simple validation
        svm_predictions = predict_simple_svm(svm_model, X_val);
        svm_accuracy = sum(svm_predictions == y_val) / length(y_val);
        
        fprintf('Simple SVM training completed. Validation accuracy: %.3f\n', svm_accuracy);
    end
    
    svm_training_success = true;
    
catch ME
    fprintf('SVM training failed: %s\n', ME.message);
    svm_model = [];
    svm_accuracy = 0;
    svm_training_success = false;
end

%% Train Random Forest Classifier
fprintf('\n--- Training Random Forest Classifier ---\n');
fprintf('Parameters: %d estimators, max depth %d\n', config.random_forest.n_estimators, config.random_forest.max_depth);

try
    if exist('TreeBagger', 'file')
        % Use MATLAB's TreeBagger for Random Forest
        rf_model = TreeBagger(config.random_forest.n_estimators, X_train, y_train, ...
            'Method', 'classification', ...
            'MaxNumSplits', 2^config.random_forest.max_depth - 1, ...
            'OOBPrediction', 'on');
        
        % Validate Random Forest
        rf_predictions_cell = predict(rf_model, X_val);
        rf_predictions = cellfun(@str2double, rf_predictions_cell);
        rf_accuracy = sum(rf_predictions == y_val) / length(y_val);
        
        fprintf('Random Forest training completed. Validation accuracy: %.3f\n', rf_accuracy);
        
    else
        % Fallback: Simple decision tree ensemble
        fprintf('TreeBagger not available. Using simplified Random Forest.\n');
        rf_model = train_simple_rf(X_train, y_train, config.random_forest);
        
        rf_predictions = predict_simple_rf(rf_model, X_val);
        rf_accuracy = sum(rf_predictions == y_val) / length(y_val);
        
        fprintf('Simple Random Forest training completed. Validation accuracy: %.3f\n', rf_accuracy);
    end
    
    rf_training_success = true;
    
catch ME
    fprintf('Random Forest training failed: %s\n', ME.message);
    rf_model = [];
    rf_accuracy = 0;
    rf_training_success = false;
end

%% Create Output Structure
trained_models = struct();
trained_models.svm_model = svm_model;
trained_models.rf_model = rf_model;
trained_models.feature_normalization = struct();
trained_models.feature_normalization.mean = X_mean;
trained_models.feature_normalization.std = X_std;
trained_models.label_map = label_map;
trained_models.feature_names = feature_vectors.feature_names;
trained_models.config = config;

% Training results
trained_models.training_results = struct();
trained_models.training_results.svm_accuracy = svm_accuracy;
trained_models.training_results.rf_accuracy = rf_accuracy;
trained_models.training_results.svm_training_success = svm_training_success;
trained_models.training_results.rf_training_success = rf_training_success;
trained_models.training_results.n_train_samples = n_train;
trained_models.training_results.n_val_samples = length(val_indices);

% Feature importance (if available)
if rf_training_success && exist('TreeBagger', 'file')
    try
        feature_importance = rf_model.OOBPermutedPredictorDeltaError;
        trained_models.feature_importance = feature_importance;
        
        fprintf('\nFeature Importance (Random Forest):\n');
        for i = 1:length(feature_importance)
            fprintf('  %s: %.4f\n', feature_vectors.feature_names{i}, feature_importance(i));
        end
    catch
        trained_models.feature_importance = [];
    end
else
    trained_models.feature_importance = [];
end

fprintf('\n--- ML Training Summary ---\n');
fprintf('SVM: %s (Accuracy: %.3f)\n', ...
    char("Success" * svm_training_success + "Failed" * ~svm_training_success), svm_accuracy);
fprintf('Random Forest: %s (Accuracy: %.3f)\n', ...
    char("Success" * rf_training_success + "Failed" * ~rf_training_success), rf_accuracy);

end

function svm_model = train_simple_svm(X, y, config)
%% Simple SVM Implementation (Fallback)
% Basic linear classifier when ML toolbox not available

% Simple linear separation based on feature means
class_means = zeros(2, size(X, 2));
for class = 1:2
    class_indices = (y == class);
    if any(class_indices)
        class_means(class, :) = mean(X(class_indices, :), 1);
    end
end

svm_model = struct();
svm_model.type = 'simple_linear';
svm_model.class_means = class_means;
svm_model.decision_boundary = mean(class_means, 1);

end

function predictions = predict_simple_svm(model, X)
%% Simple SVM Prediction (Fallback)

if strcmp(model.type, 'simple_linear')
    % Distance-based classification
    distances = zeros(size(X, 1), 2);
    for class = 1:2
        distances(:, class) = sqrt(sum((X - model.class_means(class, :)).^2, 2));
    end
    [~, predictions] = min(distances, [], 2);
else
    predictions = ones(size(X, 1), 1);  % Default to class 1
end

end

function rf_model = train_simple_rf(X, y, config)
%% Simple Random Forest Implementation (Fallback)

n_trees = min(config.n_estimators, 20);  % Limit for simplicity
n_samples = size(X, 1);
n_features = size(X, 2);

trees = cell(n_trees, 1);

for tree_idx = 1:n_trees
    % Bootstrap sampling
    bootstrap_indices = randsample(n_samples, n_samples, true);
    X_bootstrap = X(bootstrap_indices, :);
    y_bootstrap = y(bootstrap_indices);
    
    % Simple decision tree (threshold-based)
    tree = struct();
    
    % Find best feature and threshold
    best_feature = 1;
    best_threshold = mean(X_bootstrap(:, 1));
    best_accuracy = 0;
    
    for feature_idx = 1:n_features
        feature_values = X_bootstrap(:, feature_idx);
        threshold = mean(feature_values);
        
        predictions = (feature_values > threshold) + 1;
        accuracy = sum(predictions == y_bootstrap) / length(y_bootstrap);
        
        if accuracy > best_accuracy
            best_accuracy = accuracy;
            best_feature = feature_idx;
            best_threshold = threshold;
        end
    end
    
    tree.feature = best_feature;
    tree.threshold = best_threshold;
    trees{tree_idx} = tree;
end

rf_model = struct();
rf_model.type = 'simple_rf';
rf_model.trees = trees;

end

function predictions = predict_simple_rf(model, X)
%% Simple Random Forest Prediction (Fallback)

if strcmp(model.type, 'simple_rf')
    n_samples = size(X, 1);
    n_trees = length(model.trees);
    
    tree_predictions = zeros(n_samples, n_trees);
    
    for tree_idx = 1:n_trees
        tree = model.trees{tree_idx};
        tree_predictions(:, tree_idx) = (X(:, tree.feature) > tree.threshold) + 1;
    end
    
    % Majority voting
    predictions = mode(tree_predictions, 2);
else
    predictions = ones(size(X, 1), 1);  % Default to class 1
end

end