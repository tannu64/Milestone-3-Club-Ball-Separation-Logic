
function plot_feature_analysis(feature_vectors, classification_results, config)
%% Plot Feature Analysis
% Feature Space Analysis
% • Feature Distributions: Histograms of club vs. ball feature values
% • Feature Correlation Matrix: Cross-correlations between extracted features
% • Principal Component Analysis: 2D/3D visualization of feature space
% • Feature Importance: Rankings for different club types and classification methods

% Validate inputs
if ~isstruct(feature_vectors) || ~isfield(feature_vectors, 'feature_matrix')
    error('feature_vectors must contain feature_matrix field');
end

% Default configuration
if nargin < 3 || isempty(config)
    config = struct();
end

if ~isfield(config, 'save_figures')
    config.save_figures = true;
end

if ~isfield(config, 'output_dir')
    config.output_dir = 'figures';
end

fprintf('Plotting feature analysis...\n');

% Create output directory
if config.save_figures && ~exist(config.output_dir, 'dir')
    mkdir(config.output_dir);
end

feature_matrix = feature_vectors.feature_matrix;
[num_samples, num_features] = size(feature_matrix);

% Feature names (7D feature vector)
feature_names = {'Max Velocity', 'Rise Time', 'Spectral Width', 'Impact Timing', ...
                'Continuity', 'Duration', 'Correlation Delay'};

% Truncate feature names if we have fewer features
if num_features < length(feature_names)
    feature_names = feature_names(1:num_features);
end

%% Extract Classification Labels (if available)
if nargin >= 2 && ~isempty(classification_results) && isfield(classification_results, 'classifications')
    classifications = classification_results.classifications;
    class_labels = {};
    
    for i = 1:min(num_samples, length(classifications))
        if isfield(classifications(i), 'ensemble_class')
            class_labels{i} = classifications(i).ensemble_class;
        elseif isfield(classifications(i), 'final_class')
            class_labels{i} = classifications(i).final_class;
        else
            class_labels{i} = 'unknown';
        end
    end
    
    % Pad with unknown if needed
    while length(class_labels) < num_samples
        class_labels{end+1} = 'unknown';
    end
else
    % Generate synthetic labels for demonstration
    class_labels = cell(num_samples, 1);
    for i = 1:num_samples
        if feature_matrix(i, 1) > median(feature_matrix(:, 1))  % High velocity -> ball
            class_labels{i} = 'ball';
        else
            class_labels{i} = 'club';
        end
    end
end

%% Figure 1: Feature Distributions
fig1 = figure('Position', [50, 50, 1400, 1000]);
sgtitle('Feature Distribution Analysis', 'FontSize', 16, 'FontWeight', 'bold');

% Create subplots for each feature
n_cols = 3;
n_rows = ceil(num_features / n_cols);

for feat_idx = 1:num_features
    subplot(n_rows, n_cols, feat_idx);
    
    feature_values = feature_matrix(:, feat_idx);
    
    % Separate by class
    unique_classes = unique(class_labels);
    colors = lines(length(unique_classes));
    
    hold on;
    for class_idx = 1:length(unique_classes)
        class_name = unique_classes{class_idx};
        class_mask = strcmp(class_labels, class_name);
        class_values = feature_values(class_mask);
        
        if ~isempty(class_values)
            histogram(class_values, 15, 'FaceColor', colors(class_idx, :), 'FaceAlpha', 0.6);
        end
    end
    
    xlabel(feature_names{feat_idx});
    ylabel('Count');
    title(sprintf('Feature %d: %s', feat_idx, feature_names{feat_idx}));
    legend(unique_classes, 'Location', 'best');
    grid on;
end

if config.save_figures
    filename1 = fullfile(config.output_dir, 'feature_distributions.png');
    saveas(fig1, filename1);
    fprintf('Saved: %s\n', filename1);
end

%% Figure 2: Feature Correlation Matrix
fig2 = figure('Position', [100, 100, 800, 700]);
sgtitle('Feature Correlation Analysis', 'FontSize', 16, 'FontWeight', 'bold');

% Compute correlation matrix
correlation_matrix = corrcoef(feature_matrix);

% Plot correlation matrix
imagesc(correlation_matrix);
colormap('RdBu');
colorbar;
caxis([-1, 1]);

% Add correlation values as text
for i = 1:num_features
    for j = 1:num_features
        text(j, i, sprintf('%.2f', correlation_matrix(i,j)), ...
            'HorizontalAlignment', 'center', 'FontSize', 10, 'FontWeight', 'bold');
    end
end

set(gca, 'XTick', 1:num_features, 'YTick', 1:num_features);
set(gca, 'XTickLabel', feature_names, 'YTickLabel', feature_names);
xtickangle(45);
title('Feature Correlation Matrix');

if config.save_figures
    filename2 = fullfile(config.output_dir, 'feature_correlation.png');
    saveas(fig2, filename2);
    fprintf('Saved: %s\n', filename2);
end

%% Figure 3: Principal Component Analysis
fig3 = figure('Position', [150, 150, 1200, 500]);
sgtitle('Principal Component Analysis', 'FontSize', 16, 'FontWeight', 'bold');

% Normalize features for PCA
normalized_features = zscore(feature_matrix);

% Perform PCA
[coeff, score, latent, ~, explained] = pca(normalized_features);

% 2D PCA Plot
subplot(1, 2, 1);
unique_classes = unique(class_labels);
colors = lines(length(unique_classes));

hold on;
for class_idx = 1:length(unique_classes)
    class_name = unique_classes{class_idx};
    class_mask = strcmp(class_labels, class_name);
    
    scatter(score(class_mask, 1), score(class_mask, 2), 50, colors(class_idx, :), 'filled');
end

xlabel(sprintf('PC1 (%.1f%% variance)', explained(1)));
ylabel(sprintf('PC2 (%.1f%% variance)', explained(2)));
title('PCA: First Two Components');
legend(unique_classes, 'Location', 'best');
grid on;

% Explained Variance Plot
subplot(1, 2, 2);
bar(explained, 'FaceColor', [0.7, 0.7, 0.9]);
xlabel('Principal Component');
ylabel('Explained Variance (%)');
title('Explained Variance by Component');
grid on;

% Add cumulative variance line
cumulative_variance = cumsum(explained);
yyaxis right;
plot(1:length(explained), cumulative_variance, 'ro-', 'LineWidth', 2);
ylabel('Cumulative Variance (%)');

if config.save_figures
    filename3 = fullfile(config.output_dir, 'pca_analysis.png');
    saveas(fig3, filename3);
    fprintf('Saved: %s\n', filename3);
end

%% Figure 4: Feature Importance Analysis
fig4 = figure('Position', [200, 200, 1000, 600]);
sgtitle('Feature Importance Analysis', 'FontSize', 16, 'FontWeight', 'bold');

% Compute feature importance using different methods
importance_scores = compute_feature_importance(feature_matrix, class_labels, feature_names);

% Method 1: Variance-based importance
subplot(1, 2, 1);
bar(importance_scores.variance_importance, 'FaceColor', [0.8, 0.6, 0.8]);
set(gca, 'XTickLabel', feature_names);
ylabel('Importance Score');
title('Variance-based Feature Importance');
xtickangle(45);
grid on;

% Method 2: Correlation-based importance
subplot(1, 2, 2);
bar(importance_scores.correlation_importance, 'FaceColor', [0.6, 0.8, 0.6]);
set(gca, 'XTickLabel', feature_names);
ylabel('Importance Score');
title('Class Correlation-based Importance');
xtickangle(45);
grid on;

if config.save_figures
    filename4 = fullfile(config.output_dir, 'feature_importance.png');
    saveas(fig4, filename4);
    fprintf('Saved: %s\n', filename4);
end

%% Figure 5: Feature Space Visualization (3D)
if num_features >= 3
    fig5 = figure('Position', [250, 250, 800, 600]);
    
    % Use first 3 principal components for 3D visualization
    unique_classes = unique(class_labels);
    colors = lines(length(unique_classes));
    
    hold on;
    for class_idx = 1:length(unique_classes)
        class_name = unique_classes{class_idx};
        class_mask = strcmp(class_labels, class_name);
        
        scatter3(score(class_mask, 1), score(class_mask, 2), score(class_mask, 3), ...
                50, colors(class_idx, :), 'filled');
    end
    
    xlabel(sprintf('PC1 (%.1f%%)', explained(1)));
    ylabel(sprintf('PC2 (%.1f%%)', explained(2)));
    zlabel(sprintf('PC3 (%.1f%%)', explained(3)));
    title('3D Feature Space (PCA)');
    legend(unique_classes, 'Location', 'best');
    grid on;
    view(45, 30);
    
    if config.save_figures
        filename5 = fullfile(config.output_dir, 'feature_space_3d.png');
        saveas(fig5, filename5);
        fprintf('Saved: %s\n', filename5);
    end
end

%% Generate Feature Analysis Report
fprintf('\n=== Feature Analysis Summary ===\n');
fprintf('Number of samples: %d\n', num_samples);
fprintf('Number of features: %d\n', num_features);

% Feature statistics
fprintf('\nFeature Statistics:\n');
for i = 1:num_features
    feature_vals = feature_matrix(:, i);
    fprintf('- %s: %.3f ± %.3f (range: %.3f - %.3f)\n', ...
        feature_names{i}, mean(feature_vals), std(feature_vals), ...
        min(feature_vals), max(feature_vals));
end

% PCA summary
fprintf('\nPCA Summary:\n');
fprintf('First 3 components explain %.1f%% of variance\n', sum(explained(1:min(3, length(explained)))));
if length(explained) >= 2
    fprintf('PC1: %.1f%%, PC2: %.1f%%\n', explained(1), explained(2));
end

% Feature importance summary
fprintf('\nTop 3 Most Important Features:\n');
[~, var_idx] = sort(importance_scores.variance_importance, 'descend');
[~, corr_idx] = sort(importance_scores.correlation_importance, 'descend');

fprintf('By variance: ');
for i = 1:min(3, length(var_idx))
    fprintf('%s ', feature_names{var_idx(i)});
end
fprintf('\n');

fprintf('By class correlation: ');
for i = 1:min(3, length(corr_idx))
    fprintf('%s ', feature_names{corr_idx(i)});
end
fprintf('\n');

% Class distribution
unique_classes = unique(class_labels);
fprintf('\nClass Distribution:\n');
for i = 1:length(unique_classes)
    class_count = sum(strcmp(class_labels, unique_classes{i}));
    fprintf('- %s: %d (%.1f%%)\n', unique_classes{i}, class_count, class_count/num_samples*100);
end

fprintf('Feature analysis plotting completed.\n');

end

function importance_scores = compute_feature_importance(feature_matrix, class_labels, feature_names)
%% Compute Feature Importance using different methods

[num_samples, num_features] = size(feature_matrix);
importance_scores = struct();

% Method 1: Variance-based importance
variance_importance = var(feature_matrix, [], 1);
variance_importance = variance_importance / sum(variance_importance);  % Normalize
importance_scores.variance_importance = variance_importance;

% Method 2: Class correlation-based importance
correlation_importance = zeros(1, num_features);

% Convert class labels to numeric (simple binary: ball vs others)
numeric_labels = double(strcmp(class_labels, 'ball'));

for feat_idx = 1:num_features
    feature_vals = feature_matrix(:, feat_idx);
    
    % Compute correlation with class labels
    if length(unique(numeric_labels)) > 1 && length(unique(feature_vals)) > 1
        corr_coef = abs(corr(feature_vals, numeric_labels));
        if ~isnan(corr_coef)
            correlation_importance(feat_idx) = corr_coef;
        end
    end
end

% Normalize
if sum(correlation_importance) > 0
    correlation_importance = correlation_importance / sum(correlation_importance);
end

importance_scores.correlation_importance = correlation_importance;

% Method 3: Statistical separation (simplified F-score)
f_scores = zeros(1, num_features);
unique_classes = unique(class_labels);

if length(unique_classes) >= 2
    for feat_idx = 1:num_features
        feature_vals = feature_matrix(:, feat_idx);
        
        % Compute between-class and within-class variance
        overall_mean = mean(feature_vals);
        between_var = 0;
        within_var = 0;
        
        for class_idx = 1:length(unique_classes)
            class_mask = strcmp(class_labels, unique_classes{class_idx});
            class_vals = feature_vals(class_mask);
            
            if ~isempty(class_vals)
                class_mean = mean(class_vals);
                class_size = length(class_vals);
                
                between_var = between_var + class_size * (class_mean - overall_mean)^2;
                within_var = within_var + sum((class_vals - class_mean).^2);
            end
        end
        
        if within_var > 0
            f_scores(feat_idx) = between_var / within_var;
        end
    end
    
    % Normalize F-scores
    if sum(f_scores) > 0
        f_scores = f_scores / sum(f_scores);
    end
end

importance_scores.f_score_importance = f_scores;

end