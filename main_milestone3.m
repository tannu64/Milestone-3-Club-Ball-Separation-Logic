%% Milestone 3: Club/Ball Separation Logic - Main Execution Script
% Golf Launch Monitor DSP Algorithm Development

clear all; close all; clc;

fprintf('=== Milestone 3: Club/Ball Separation Logic ===\n');
fprintf('Golf Launch Monitor DSP Algorithm Development\n\n');

%% Configuration and Setup
addpath(genpath('src'));
addpath('config');

% Load configuration
config_file = 'config/milestone3_config.json';
if exist(config_file, 'file')
    config = jsondecode(fileread(config_file));
    fprintf('Loaded configuration from: %s\n', config_file);
else
    config = create_default_config();
    fprintf('Using default configuration\n');
end

% Dataset configuration
data_folder = '28-01-2024 DATA';
results_folder = 'results';

% Create output directories
if ~exist(results_folder, 'dir')
    mkdir(results_folder);
end

%% Dataset Processing
fprintf('\n=== Dataset Processing ===\n');

dataset_dirs = dir(fullfile(data_folder, 'LOG*'));
dataset_dirs = dataset_dirs([dataset_dirs.isdir]);
num_shots = length(dataset_dirs);

fprintf('Found %d shot recordings in dataset\n', num_shots);

% Initialize results
all_results = struct();
processing_summary = struct();
processing_summary.total_shots = num_shots;
processing_summary.successful_shots = 0;
processing_summary.failed_shots = 0;

%% Process Each Shot
fprintf('\n=== Processing Individual Shots ===\n');

for shot_idx = 1:min(num_shots, 10)  % Process first 10 shots for testing
    shot_dir = dataset_dirs(shot_idx);
    shot_path = fullfile(data_folder, shot_dir.name);
    
    fprintf('\n--- Processing Shot %d: %s ---\n', shot_idx, shot_dir.name);
    
    try
        % Extract TrackMan reference
        trackman_data = extract_trackman_reference(shot_dir.name);
        
        if ~trackman_data.parsing_success || ~trackman_data.is_valid_shot
            fprintf('Skipping invalid shot\n');
            processing_summary.failed_shots = processing_summary.failed_shots + 1;
            continue;
        end
        
        % Find data files
        bin_files = dir(fullfile(shot_path, '*.bin'));
        json_files = dir(fullfile(shot_path, '*.json'));
        
        if isempty(bin_files) || isempty(json_files)
            fprintf('Missing data files\n');
            processing_summary.failed_shots = processing_summary.failed_shots + 1;
            continue;
        end
        
        % Load data
        bin_file = fullfile(shot_path, bin_files(1).name);
        json_file = fullfile(shot_path, json_files(1).name);
        
        metadata = load_json_metadata(json_file);
        if ~metadata.parsing_success
            fprintf('Failed to load metadata\n');
            processing_summary.failed_shots = processing_summary.failed_shots + 1;
            continue;
        end
        
        proc_config = config.signal_processing;
        proc_config.sampling_rate = metadata.sampling_freq_hz;
        
        iq_data = load_iq_data(bin_file, proc_config);
        
        %% Core Processing Pipeline
        fprintf('  Processing pipeline...\n');
        
        % 1. Impact Detection
        impact_events = detect_impact_events(iq_data, config.impact_detection);
        
        % 2. Velocity Extraction
        stft_ch1 = compute_stft_spectrogram(iq_data.channel1, proc_config);
        velocity_data = doppler_to_velocity(stft_ch1, metadata);
        
        % 3. Feature Extraction
        velocity_features = extract_velocity_features(velocity_data, config.feature_extraction);
        spectral_features = extract_spectral_features(stft_ch1, velocity_data, config.feature_extraction);
        correlation_features = compute_cross_correlation(velocity_features, impact_events, config.feature_extraction);
        temporal_features = extract_temporal_features(velocity_data, impact_events, config.feature_extraction);
        
        % 4. Build Feature Vectors
        feature_vectors = build_feature_vectors(velocity_features, spectral_features, correlation_features, temporal_features, impact_events, config);
        
        % 5. Classification
        classification_results = rule_based_classifier(feature_vectors, config.classification.rule_based);
        
        % 5.1. Classification Confidence Analysis
        confidence_results = classification_confidence(classification_results, feature_vectors, config);
        
        % 6. Separation
        separation_results = temporal_separation(classification_results, impact_events, velocity_data, config);
        
        % 6.1. Physics Validation
        physics_results = physics_validation(separation_results, config);
        
        % 7. Assignment
        assignment_results = velocity_assignment(separation_results, trackman_data, config.validation);
        
        % 7.1. Consistency Checks
        consistency_results = consistency_checks(classification_results, separation_results, assignment_results, config);
        
        % 7.2. Impact Timing Validation
        validated_impacts = validate_impact_timing(impact_events, config);
        
        % 7.3. Multi-channel Fusion (for enhanced processing)
        if isfield(iq_data, 'channel2') && isfield(iq_data, 'channel3') && isfield(iq_data, 'channel4')
            fusion_result = multi_channel_fusion(iq_data, config);
            % Enhanced gradient analysis on fused signal
            gradient_result = temporal_gradient_analysis(fusion_result.fused_energy, config);
        else
            fusion_result = [];
            gradient_result = [];
        end
        
        % Store comprehensive results
        shot_results = struct();
        shot_results.shot_name = shot_dir.name;
        shot_results.trackman_data = trackman_data;
        shot_results.impact_events = impact_events;
        shot_results.feature_vectors = feature_vectors;
        shot_results.classification_results = classification_results;
        shot_results.confidence_results = confidence_results;
        shot_results.separation_results = separation_results;
        shot_results.physics_results = physics_results;
        shot_results.assignment_results = assignment_results;
        shot_results.consistency_results = consistency_results;
        shot_results.validated_impacts = validated_impacts;
        shot_results.fusion_result = fusion_result;
        shot_results.gradient_result = gradient_result;
        
        all_results.(sprintf('shot_%03d', shot_idx)) = shot_results;
        processing_summary.successful_shots = processing_summary.successful_shots + 1;
        
        % Display enhanced results
        if assignment_results.num_assignments > 0
            assignment = assignment_results.assignments(1);
            fprintf('  Results: Club=%.1f mph, Ball=%.1f mph (Confidence=%.3f)\n', ...
                assignment.club_velocity_mph, assignment.ball_velocity_mph, assignment.overall_confidence);
            
            % Display validation status
            if physics_results.num_validated > 0
                fprintf('  Physics: ✓ Valid, Consistency: %.1f%%\n', consistency_results.overall_consistency.score * 100);
            else
                fprintf('  Physics: ⚠ Issues detected\n');
            end
        end
        
    catch ME
        fprintf('Error: %s\n', ME.message);
        processing_summary.failed_shots = processing_summary.failed_shots + 1;
    end
end

%% Comprehensive Analysis and Validation
fprintf('\n=== Comprehensive Analysis ===\n');

if processing_summary.successful_shots > 0
    % Compile summary statistics
    summary_stats = compute_separation_metrics(all_results, config);
    all_results.summary_stats = summary_stats;
    
    % TrackMan validation
    trackman_validation = trackman_validation(all_results, config);
    all_results.trackman_validation = trackman_validation;
    
    % Performance by club type
    club_performance = performance_by_club_type(all_results, config);
    all_results.club_performance = club_performance;
    
    % Confusion matrix analysis
    confusion_analysis = confusion_matrix_analysis(all_results, config);
    all_results.confusion_analysis = confusion_analysis;
    
    fprintf('Analysis completed for %d successful shots\n', processing_summary.successful_shots);
end

%% Advanced Visualization Dashboard
fprintf('\n=== Generating Visualization Dashboard ===\n');

if processing_summary.successful_shots > 0
    % Create figures directory
    figures_dir = fullfile(results_folder, 'figures');
    if ~exist(figures_dir, 'dir')
        mkdir(figures_dir);
    end
    
    viz_config = struct();
    viz_config.save_figures = true;
    viz_config.output_dir = figures_dir;
    viz_config.figure_format = 'png';
    
    try
        % Performance Dashboard
        performance_dashboard(all_results, viz_config);
        
        % Classification Results Analysis
        if isfield(all_results, 'shot_001') && isfield(all_results.shot_001, 'classification_results')
            % Aggregate classification results
            all_classifications = struct();
            all_classifications.classifications = [];
            
            shot_fields = fieldnames(all_results);
            for i = 1:length(shot_fields)
                if startsWith(shot_fields{i}, 'shot_') && isfield(all_results.(shot_fields{i}), 'classification_results')
                    shot_class = all_results.(shot_fields{i}).classification_results;
                    if isfield(shot_class, 'classifications')
                        all_classifications.classifications = [all_classifications.classifications; shot_class.classifications];
                    end
                end
            end
            
            plot_classification_results(all_classifications, [], viz_config);
        end
        
        % Feature Analysis
        if isfield(all_results, 'shot_001') && isfield(all_results.shot_001, 'feature_vectors')
            % Aggregate feature vectors
            all_features = struct();
            all_features.feature_matrix = [];
            all_class_results = struct();
            all_class_results.classifications = [];
            
            shot_fields = fieldnames(all_results);
            for i = 1:length(shot_fields)
                if startsWith(shot_fields{i}, 'shot_') && isfield(all_results.(shot_fields{i}), 'feature_vectors')
                    shot_feat = all_results.(shot_fields{i}).feature_vectors;
                    shot_class = all_results.(shot_fields{i}).classification_results;
                    
                    if isfield(shot_feat, 'feature_matrix') && ~isempty(shot_feat.feature_matrix)
                        all_features.feature_matrix = [all_features.feature_matrix; shot_feat.feature_matrix];
                        if isfield(shot_class, 'classifications')
                            all_class_results.classifications = [all_class_results.classifications; shot_class.classifications];
                        end
                    end
                end
            end
            
            if ~isempty(all_features.feature_matrix)
                plot_feature_analysis(all_features, all_class_results, viz_config);
            end
        end
        
        % Individual shot visualizations (first few shots)
        shot_fields = fieldnames(all_results);
        for i = 1:min(3, length(shot_fields))  % Visualize first 3 shots
            if startsWith(shot_fields{i}, 'shot_')
                shot_data = all_results.(shot_fields{i});
                
                if isfield(shot_data, 'assignment_results')
                    plot_velocity_separation(shot_data.assignment_results, viz_config);
                end
                
                if isfield(shot_data, 'impact_events')
                    plot_impact_detection(shot_data.impact_events, viz_config);
                end
            end
        end
        
        fprintf('Visualization dashboard generated in: %s\n', figures_dir);
        
    catch ME
        fprintf('Visualization error: %s\n', ME.message);
    end
end

%% Save Comprehensive Results
fprintf('\n=== Saving Results ===\n');

% Save main results
save(fullfile(results_folder, 'milestone3_results.mat'), 'all_results', 'processing_summary');
fprintf('Results saved to: %s\n', fullfile(results_folder, 'milestone3_results.mat'));

% Save results in multiple formats
if processing_summary.successful_shots > 0
    save_config = struct();
    save_config.save_format = {'mat', 'json', 'csv'};
    save_config.compression = true;
    save_config.backup_existing = true;
    
    try
        save_separation_results(all_results, results_folder, save_config);
        fprintf('Multi-format results saved\n');
    catch ME
        fprintf('Save error: %s\n', ME.message);
    end
end

%% Results Summary
fprintf('\n=== Results Summary ===\n');
fprintf('Successful shots: %d/%d\n', processing_summary.successful_shots, processing_summary.total_shots);

if processing_summary.successful_shots > 0 && isfield(all_results, 'summary_stats')
    stats = all_results.summary_stats;
    if isfield(stats, 'velocity_statistics')
        vs = stats.velocity_statistics;
        fprintf('Average velocities: Club=%.1f mph, Ball=%.1f mph\n', mean(vs.club_velocities), mean(vs.ball_velocities));
    end
    
    if isfield(all_results, 'trackman_validation')
        tv = all_results.trackman_validation;
        fprintf('TrackMan validation: RMS Error=%.1f mph\n', tv.rms_error);
        if tv.rms_error <= 10
            fprintf('✓ Target accuracy achieved (<10 mph)\n');
        else
            fprintf('⚠ Target accuracy not met (>10 mph)\n');
        end
    end
end

fprintf('\n=== Processing Complete ===\n');

function config = create_default_config()
config = struct();
config.signal_processing = struct();
config.signal_processing.sampling_rate = 22700;
config.signal_processing.fft_size = 1024;
config.signal_processing.overlap_percent = 75;
config.signal_processing.window_type = 'hamming';
config.signal_processing.zero_padding_factor = 2;

config.impact_detection = struct();
config.impact_detection.energy_gradient_threshold = 7.0;
config.impact_detection.analysis_window_ms = 20;
config.impact_detection.min_impact_duration_ms = 0.3;
config.impact_detection.max_impact_duration_ms = 3.0;
config.impact_detection.channel_fusion_weights = [0.25, 0.25, 0.25, 0.25];
config.impact_detection.fusion_method = 'weighted_sum';
config.impact_detection.normalize_channels = true;

config.feature_extraction = struct();
config.feature_extraction.velocity_window_ms = 100;
config.feature_extraction.continuity_smooth_threshold = 2.0;
config.feature_extraction.continuity_impulsive_threshold = 15.0;
config.feature_extraction.rise_time_threshold_ms = 2.0;
config.feature_extraction.spectral_width_broad_hz = 50;
config.feature_extraction.spectral_width_narrow_hz = 20;
config.feature_extraction.correlation_lag_range_ms = 20;
config.feature_extraction.time_window_ms = 100;
config.feature_extraction.min_duration_ms = 1.0;
config.feature_extraction.max_duration_ms = 200.0;

config.classification = struct();
config.classification.rule_based = struct();
config.classification.rule_based.velocity_ratio_wedge = [1.2, 1.8];
config.classification.rule_based.velocity_ratio_iron = [1.4, 2.2];
config.classification.rule_based.velocity_ratio_driver = [1.6, 2.5];
config.classification.rule_based.continuity_smooth_threshold = 2.0;
config.classification.rule_based.continuity_impulsive_threshold = 15.0;
config.classification.rule_based.rise_time_threshold_ms = 2.0;

% Classification confidence settings
config.confidence_thresholds = [0.5, 0.6, 0.7, 0.8, 0.9];
config.target_accuracies = struct();
config.target_accuracies.wedge = 0.8;   % 80%
config.target_accuracies.iron = 0.9;    % 90%
config.target_accuracies.driver = 0.9;  % 90%

config.validation = struct();
config.validation.target_wedge_accuracy = 0.8;
config.validation.target_iron_accuracy = 0.9;
config.validation.target_driver_accuracy = 0.9;
config.validation.max_velocity_error_mph = 10.0;
config.validation.impact_timing_tolerance_ms = 2.0;
config.validation.confidence_threshold = 0.7;

% Physics validation settings
config.velocity_ratio_limits = [1.0, 3.0];
config.energy_transfer_efficiency = [0.6, 0.9];
config.impact_duration_limits_ms = [0.3, 3.0];
config.momentum_conservation_tolerance = 0.2;

% Consistency check settings
config.consistency_threshold = 0.8;
config.velocity_tolerance_mph = 5.0;

% Signal processing settings
config.gradient_method = 'central_difference';
config.threshold_factor = 7.0;
config.noise_estimation_method = 'percentile';
config.adaptive_threshold = true;

% Peak detection settings
config.min_peak_height = 0.1;
config.min_peak_distance = 5;
config.peak_prominence = 0.05;
end