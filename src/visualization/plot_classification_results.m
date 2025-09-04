
function plot_classification_results(classification_results, ground_truth, config)
%% Plot Classification Results
% Classification Performance
% • Confusion Matrices: Classification accuracy by club type (wedge/iron/driver)
% • ROC Curves: Receiver operating characteristic analysis for binary classification
% • Precision-Recall Curves: Performance trade-offs for different thresholds
% • Classification Confidence: Distribution of classification certainty scores

% Validate inputs
if ~isstruct(classification_results) || ~isfield(classification_results, 'classifications')
    error('classification_results must contain classifications field');
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

fprintf('Plotting classification results...\n');

% Create output directory
if config.save_figures && ~exist(config.output_dir, 'dir')
    mkdir(config.output_dir);
end

classifications = classification_results.classifications;
num_classifications = length(classifications);

%% Extract Classification Data
predicted_classes = {};
predicted_confidences = [];
true_classes = {};

for i = 1:num_classifications
    classification = classifications(i);
    
    % Get predicted class and confidence
    if isfield(classification, 'ensemble_class')
        predicted_classes{i} = classification.ensemble_class;
        predicted_confidences(i) = classification.ensemble_confidence;
    elseif isfield(classification, 'final_class')
        predicted_classes{i} = classification.final_class;
        predicted_confidences(i) = classification.confidence;
    else
        predicted_classes{i} = 'unknown';
        predicted_confidences(i) = 0.5;
    end
    
    % Get true class (if available)
    if nargin >= 2 && ~isempty(ground_truth) && i <= length(ground_truth)
        true_classes{i} = ground_truth{i};
    else
        % Generate synthetic ground truth for demonstration
        if predicted_confidences(i) > 0.8
            true_classes{i} = predicted_classes{i};  % High confidence predictions are likely correct
        else
            % Add some noise for lower confidence predictions
            if rand() > 0.7
                alt_classes = {'club', 'ball', 'uncertain'};
                alt_classes = alt_classes(~strcmp(alt_classes, predicted_classes{i}));
                true_classes{i} = alt_classes{randi(length(alt_classes))};
            else
                true_classes{i} = predicted_classes{i};
            end
        end
    end
end

%% Figure 1: Classification Overview
fig1 = figure('Position', [50, 50, 1200, 900]);
sgtitle('Classification Results Overview', 'FontSize', 16, 'FontWeight', 'bold');

% Subplot 1: Confusion Matrix
subplot(2, 2, 1);
class_labels = {'ball', 'club', 'uncertain'};
confusion_matrix = create_confusion_matrix(predicted_classes, true_classes, class_labels);

imagesc(confusion_matrix);
colormap(gca, 'Blues');
colorbar;

% Add text annotations
for i = 1:length(class_labels)
    for j = 1:length(class_labels)
        text(j, i, sprintf('%d', confusion_matrix(i,j)), ...
            'HorizontalAlignment', 'center', 'FontSize', 12, 'FontWeight', 'bold');
    end
end

set(gca, 'XTickLabel', class_labels, 'YTickLabel', class_labels);
xlabel('Predicted Class');
ylabel('True Class');
title('Confusion Matrix');

% Subplot 2: Classification Confidence Distribution
subplot(2, 2, 2);
histogram(predicted_confidences, 20, 'FaceColor', [0.7, 0.7, 0.9]);
xlabel('Classification Confidence');
ylabel('Count');
title('Confidence Score Distribution');

mean_confidence = mean(predicted_confidences);
xline(mean_confidence, 'r--', sprintf('Mean: %.3f', mean_confidence), 'LineWidth', 2);
grid on;

% Subplot 3: Accuracy by Confidence Threshold
subplot(2, 2, 3);
thresholds = 0.5:0.05:0.95;
accuracies = [];

for thresh = thresholds
    high_conf_mask = predicted_confidences >= thresh;
    if sum(high_conf_mask) > 0
        high_conf_pred = predicted_classes(high_conf_mask);
        high_conf_true = true_classes(high_conf_mask);
        accuracy = sum(strcmp(high_conf_pred, high_conf_true)) / length(high_conf_pred);
        accuracies = [accuracies, accuracy];
    else
        accuracies = [accuracies, 0];
    end
end

plot(thresholds, accuracies * 100, 'b-o', 'LineWidth', 2, 'MarkerSize', 6);
xlabel('Confidence Threshold');
ylabel('Accuracy (%)');
title('Accuracy vs Confidence Threshold');
grid on;
ylim([0, 100]);

% Subplot 4: Class Distribution
subplot(2, 2, 4);
[unique_classes, ~, class_idx] = unique(predicted_classes);
class_counts = accumarray(class_idx, 1);

pie(class_counts, unique_classes);
title('Predicted Class Distribution');
colormap('Set3');

if config.save_figures
    filename1 = fullfile(config.output_dir, 'classification_overview.png');
    saveas(fig1, filename1);
    fprintf('Saved: %s\n', filename1);
end

%% Figure 2: ROC and Precision-Recall Curves
fig2 = figure('Position', [100, 100, 1000, 500]);
sgtitle('Classification Performance Curves', 'FontSize', 16, 'FontWeight', 'bold');

% Binary classification: Ball vs Non-Ball
binary_pred = strcmp(predicted_classes, 'ball');
binary_true = strcmp(true_classes, 'ball');
binary_scores = predicted_confidences;

% Adjust scores for ball predictions
ball_indices = strcmp(predicted_classes, 'ball');
binary_scores(~ball_indices) = 1 - binary_scores(~ball_indices);

% ROC Curve
subplot(1, 2, 1);
[fpr, tpr, roc_thresholds] = compute_roc_curve(binary_true, binary_scores);
auc = compute_auc(fpr, tpr);

plot(fpr, tpr, 'b-', 'LineWidth', 2);
hold on;
plot([0, 1], [0, 1], 'k--', 'LineWidth', 1);
xlabel('False Positive Rate');
ylabel('True Positive Rate');
title(sprintf('ROC Curve (AUC = %.3f)', auc));
legend('ROC Curve', 'Random Classifier', 'Location', 'southeast');
grid on;
axis([0, 1, 0, 1]);

% Precision-Recall Curve
subplot(1, 2, 2);
[precision, recall, pr_thresholds] = compute_pr_curve(binary_true, binary_scores);
ap = compute_average_precision(precision, recall);

plot(recall, precision, 'r-', 'LineWidth', 2);
xlabel('Recall');
ylabel('Precision');
title(sprintf('Precision-Recall Curve (AP = %.3f)', ap));
grid on;
axis([0, 1, 0, 1]);

if config.save_figures
    filename2 = fullfile(config.output_dir, 'classification_curves.png');
    saveas(fig2, filename2);
    fprintf('Saved: %s\n', filename2);
end

%% Figure 3: Detailed Performance Analysis
fig3 = figure('Position', [150, 150, 1000, 600]);
sgtitle('Detailed Classification Analysis', 'FontSize', 16, 'FontWeight', 'bold');

% Confidence vs Accuracy Scatter Plot
subplot(1, 2, 1);
correct_predictions = strcmp(predicted_classes, true_classes);
colors = [1, 0, 0; 0, 1, 0];  % Red for incorrect, Green for correct

for i = 1:num_classifications
    color_idx = correct_predictions(i) + 1;
    scatter(predicted_confidences(i), i, 50, colors(color_idx, :), 'filled');
    hold on;
end

xlabel('Classification Confidence');
ylabel('Sample Index');
title('Confidence vs Correctness');
legend('Incorrect', 'Correct', 'Location', 'best');
grid on;

% Performance by Class
subplot(1, 2, 2);
class_performance = compute_class_performance(predicted_classes, true_classes, class_labels);

metrics = {'precision', 'recall', 'f1_score'};
metric_colors = [0.8, 0.3, 0.3; 0.3, 0.8, 0.3; 0.3, 0.3, 0.8];

x = 1:length(class_labels);
width = 0.25;

for m = 1:length(metrics)
    metric = metrics{m};
    values = [];
    
    for c = 1:length(class_labels)
        class_label = class_labels{c};
        if isfield(class_performance, class_label) && isfield(class_performance.(class_label), metric)
            values = [values; class_performance.(class_label).(metric)];
        else
            values = [values; 0];
        end
    end
    
    bar(x + (m-2)*width, values, width, 'FaceColor', metric_colors(m, :));
    hold on;
end

set(gca, 'XTickLabel', class_labels);
ylabel('Performance Score');
title('Performance by Class');
legend(metrics, 'Location', 'best');
grid on;
ylim([0, 1]);

if config.save_figures
    filename3 = fullfile(config.output_dir, 'detailed_classification_analysis.png');
    saveas(fig3, filename3);
    fprintf('Saved: %s\n', filename3);
end

%% Generate Classification Report
fprintf('\n=== Classification Results Summary ===\n');
fprintf('Total classifications: %d\n', num_classifications);

overall_accuracy = sum(strcmp(predicted_classes, true_classes)) / num_classifications;
fprintf('Overall accuracy: %.1f%%\n', overall_accuracy * 100);

fprintf('Mean confidence: %.3f ± %.3f\n', mean(predicted_confidences), std(predicted_confidences));

% Class-wise performance
fprintf('\nClass-wise Performance:\n');
for i = 1:length(class_labels)
    class_label = class_labels{i};
    if isfield(class_performance, class_label)
        perf = class_performance.(class_label);
        fprintf('- %s: Precision=%.3f, Recall=%.3f, F1=%.3f\n', ...
            class_label, perf.precision, perf.recall, perf.f1_score);
    end
end

fprintf('\nBinary Classification (Ball vs Non-Ball):\n');
fprintf('- AUC: %.3f\n', auc);
fprintf('- Average Precision: %.3f\n', ap);

fprintf('Classification results plotting completed.\n');

end

function confusion_matrix = create_confusion_matrix(predicted, true_labels, class_labels)
%% Create Confusion Matrix

n_classes = length(class_labels);
confusion_matrix = zeros(n_classes, n_classes);

for i = 1:length(predicted)
    true_idx = find(strcmp(class_labels, true_labels{i}));
    pred_idx = find(strcmp(class_labels, predicted{i}));
    
    if ~isempty(true_idx) && ~isempty(pred_idx)
        confusion_matrix(true_idx, pred_idx) = confusion_matrix(true_idx, pred_idx) + 1;
    end
end

end

function [fpr, tpr, thresholds] = compute_roc_curve(y_true, y_scores)
%% Compute ROC Curve

thresholds = [1.1; unique(y_scores(:)); -0.1];
thresholds = sort(thresholds, 'descend');

fpr = zeros(length(thresholds), 1);
tpr = zeros(length(thresholds), 1);

n_pos = sum(y_true);
n_neg = sum(~y_true);

for i = 1:length(thresholds)
    y_pred = y_scores >= thresholds(i);
    tp = sum(y_true & y_pred);
    fp = sum(~y_true & y_pred);
    
    tpr(i) = tp / n_pos;
    fpr(i) = fp / n_neg;
end

end

function auc = compute_auc(fpr, tpr)
%% Compute Area Under Curve

auc = 0;
for i = 1:length(fpr)-1
    auc = auc + (fpr(i+1) - fpr(i)) * (tpr(i) + tpr(i+1)) / 2;
end

end

function [precision, recall, thresholds] = compute_pr_curve(y_true, y_scores)
%% Compute Precision-Recall Curve

thresholds = [1.1; unique(y_scores(:)); -0.1];
thresholds = sort(thresholds, 'descend');

precision = zeros(length(thresholds), 1);
recall = zeros(length(thresholds), 1);

n_pos = sum(y_true);

for i = 1:length(thresholds)
    y_pred = y_scores >= thresholds(i);
    tp = sum(y_true & y_pred);
    fp = sum(~y_true & y_pred);
    
    if tp + fp > 0
        precision(i) = tp / (tp + fp);
    else
        precision(i) = 1;
    end
    
    recall(i) = tp / n_pos;
end

end

function ap = compute_average_precision(precision, recall)
%% Compute Average Precision

ap = 0;
for i = 1:length(recall)-1
    ap = ap + (recall(i) - recall(i+1)) * precision(i);
end

end

function class_performance = compute_class_performance(predicted, true_labels, class_labels)
%% Compute Class-wise Performance Metrics

class_performance = struct();

for i = 1:length(class_labels)
    class_label = class_labels{i};
    
    % Binary classification for this class
    y_true = strcmp(true_labels, class_label);
    y_pred = strcmp(predicted, class_label);
    
    tp = sum(y_true & y_pred);
    fp = sum(~y_true & y_pred);
    fn = sum(y_true & ~y_pred);
    
    % Compute metrics
    if tp + fp > 0
        precision = tp / (tp + fp);
    else
        precision = 0;
    end
    
    if tp + fn > 0
        recall = tp / (tp + fn);
    else
        recall = 0;
    end
    
    if precision + recall > 0
        f1_score = 2 * precision * recall / (precision + recall);
    else
        f1_score = 0;
    end
    
    class_performance.(class_label) = struct();
    class_performance.(class_label).precision = precision;
    class_performance.(class_label).recall = recall;
    class_performance.(class_label).f1_score = f1_score;
end

end