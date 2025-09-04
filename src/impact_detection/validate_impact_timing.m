function validation_result = validate_impact_timing(impact_events, config)
%% Validate Impact Timing
% Physics based validation (0.3-3ms impact duration)

% Validate inputs
if ~isstruct(impact_events) || ~isfield(impact_events, 'impact_times')
    error('impact_events must contain impact_times field');
end

% Default configuration
if nargin < 2 || isempty(config)
    config = struct();
end

if ~isfield(config, 'min_impact_duration_ms')
    config.min_impact_duration_ms = 0.3;  % Minimum physical impact duration
end

if ~isfield(config, 'max_impact_duration_ms')
    config.max_impact_duration_ms = 3.0;  % Maximum physical impact duration
end

if ~isfield(config, 'impact_timing_tolerance_ms')
    config.impact_timing_tolerance_ms = 2.0;  % ±2ms accuracy target
end

if ~isfield(config, 'expected_impact_time')
    config.expected_impact_time = [];  % Expected impact time (if known)
end

if ~isfield(config, 'physics_constraints')
    config.physics_constraints = true;
end

impact_times = impact_events.impact_times;
num_impacts = length(impact_times);

fprintf('Validating %d impact events against physics constraints...\n', num_impacts);

%% Initialize Validation Results
validation_result = struct();
validation_result.num_impacts = num_impacts;
validation_result.validated_impacts = [];
validation_result.rejected_impacts = [];
validation_result.validation_summary = struct();

if num_impacts == 0
    fprintf('No impact events to validate\n');
    validation_result.validation_summary.all_valid = true;
    validation_result.validation_summary.validation_rate = 1.0;
    return;
end

%% Physics-Based Validation
validated_impacts = [];
rejected_impacts = [];

for impact_idx = 1:num_impacts
    impact_time = impact_times(impact_idx);
    
    % Create validation record
    validation_record = struct();
    validation_record.impact_idx = impact_idx;
    validation_record.impact_time = impact_time;
    validation_record.impact_time_ms = impact_time * 1000;
    validation_record.validation_tests = struct();
    validation_record.is_valid = true;
    validation_record.rejection_reasons = {};
    
    %% Test 1: Impact Duration Validation
    if num_impacts > 1
        % Find closest neighboring impacts
        other_impacts = impact_times([1:impact_idx-1, impact_idx+1:end]);
        
        if ~isempty(other_impacts)
            min_separation = min(abs(other_impacts - impact_time)) * 1000;  % Convert to ms
            
            validation_record.validation_tests.min_separation_ms = min_separation;
            
            if min_separation < config.min_impact_duration_ms
                validation_record.is_valid = false;
                validation_record.rejection_reasons{end+1} = sprintf('Too close to other impact (%.2f ms < %.2f ms)', ...
                    min_separation, config.min_impact_duration_ms);
            end
            
            if min_separation > config.max_impact_duration_ms * 10  % Very isolated
                validation_record.validation_tests.isolation_warning = true;
            end
        end
    end
    
    %% Test 2: Expected Timing Validation (if reference provided)
    if ~isempty(config.expected_impact_time)
        timing_error = abs(impact_time - config.expected_impact_time) * 1000;  % ms
        validation_record.validation_tests.timing_error_ms = timing_error;
        
        if timing_error > config.impact_timing_tolerance_ms
            validation_record.is_valid = false;
            validation_record.rejection_reasons{end+1} = sprintf('Timing error too large (%.2f ms > %.2f ms)', ...
                timing_error, config.impact_timing_tolerance_ms);
        end
    end
    
    %% Test 3: Physical Plausibility
    if config.physics_constraints
        % Check if impact time is within reasonable bounds
        if impact_time < 0
            validation_record.is_valid = false;
            validation_record.rejection_reasons{end+1} = 'Negative impact time (unphysical)';
        end
        
        % Check for extremely late impacts (beyond reasonable swing duration)
        max_reasonable_time = 2.0;  % 2 seconds maximum
        if impact_time > max_reasonable_time
            validation_record.is_valid = false;
            validation_record.rejection_reasons{end+1} = sprintf('Impact too late (%.2f s > %.2f s)', ...
                impact_time, max_reasonable_time);
        end
    end
    
    %% Test 4: Signal Quality Assessment (if available)
    if isfield(impact_events, 'impact_strengths') && length(impact_events.impact_strengths) >= impact_idx
        impact_strength = impact_events.impact_strengths(impact_idx);
        validation_record.validation_tests.impact_strength = impact_strength;
        
        % Minimum strength threshold
        min_strength_threshold = 0.1;  % Relative threshold
        if impact_strength < min_strength_threshold
            validation_record.is_valid = false;
            validation_record.rejection_reasons{end+1} = sprintf('Impact strength too low (%.3f < %.3f)', ...
                impact_strength, min_strength_threshold);
        end
    end
    
    %% Test 5: Gradient Quality (if available)
    if isfield(impact_events, 'energy_gradient') && isfield(impact_events, 'detection_indices')
        detection_indices = impact_events.detection_indices;
        
        % Find corresponding gradient value
        if ~isempty(detection_indices) && impact_idx <= length(detection_indices)
            gradient_idx = detection_indices(impact_idx);
            if gradient_idx <= length(impact_events.energy_gradient)
                gradient_value = impact_events.energy_gradient(gradient_idx);
                validation_record.validation_tests.gradient_value = gradient_value;
                
                % Check gradient significance
                if isfield(impact_events, 'detection_threshold')
                    threshold = impact_events.detection_threshold;
                    gradient_significance = abs(gradient_value) / threshold;
                    validation_record.validation_tests.gradient_significance = gradient_significance;
                    
                    if gradient_significance < 1.5  % Must be 50% above threshold
                        validation_record.is_valid = false;
                        validation_record.rejection_reasons{end+1} = sprintf('Gradient not significant enough (%.1fx threshold)', ...
                            gradient_significance);
                    end
                end
            end
        end
    end
    
    %% Store Validation Result
    if validation_record.is_valid
        validated_impacts = [validated_impacts; validation_record];
    else
        rejected_impacts = [rejected_impacts; validation_record];
    end
end

%% Compile Validation Results
validation_result.validated_impacts = validated_impacts;
validation_result.rejected_impacts = rejected_impacts;
validation_result.num_validated = length(validated_impacts);
validation_result.num_rejected = length(rejected_impacts);

% Validation summary
validation_result.validation_summary.validation_rate = validation_result.num_validated / num_impacts;
validation_result.validation_summary.rejection_rate = validation_result.num_rejected / num_impacts;
validation_result.validation_summary.all_valid = validation_result.num_rejected == 0;

% Extract validated impact times
if validation_result.num_validated > 0
    validation_result.validated_impact_times = [validated_impacts.impact_time];
else
    validation_result.validated_impact_times = [];
end

%% Quality Metrics
quality_metrics = struct();

if validation_result.num_validated > 0
    validated_times_ms = [validated_impacts.impact_time_ms];
    
    % Timing statistics
    quality_metrics.mean_impact_time_ms = mean(validated_times_ms);
    quality_metrics.std_impact_time_ms = std(validated_times_ms);
    quality_metrics.impact_time_range_ms = [min(validated_times_ms), max(validated_times_ms)];
    
    % Inter-impact intervals (if multiple impacts)
    if validation_result.num_validated > 1
        intervals = diff(sort([validated_impacts.impact_time])) * 1000;  % Convert to ms
        quality_metrics.inter_impact_intervals_ms = intervals;
        quality_metrics.mean_interval_ms = mean(intervals);
        quality_metrics.min_interval_ms = min(intervals);
        
        % Check if intervals are within physics constraints
        valid_intervals = intervals >= config.min_impact_duration_ms & intervals <= config.max_impact_duration_ms * 5;
        quality_metrics.valid_interval_rate = sum(valid_intervals) / length(intervals);
    end
    
    % Expected timing validation (if reference provided)
    if ~isempty(config.expected_impact_time)
        timing_errors = abs([validated_impacts.impact_time] - config.expected_impact_time) * 1000;
        quality_metrics.timing_errors_ms = timing_errors;
        quality_metrics.mean_timing_error_ms = mean(timing_errors);
        quality_metrics.rms_timing_error_ms = sqrt(mean(timing_errors.^2));
        quality_metrics.within_tolerance_rate = sum(timing_errors <= config.impact_timing_tolerance_ms) / length(timing_errors);
    end
end

validation_result.quality_metrics = quality_metrics;

%% Generate Validation Report
fprintf('\n=== Impact Timing Validation Summary ===\n');
fprintf('Total impacts: %d\n', num_impacts);
fprintf('Validated: %d (%.1f%%)\n', validation_result.num_validated, validation_result.validation_summary.validation_rate * 100);
fprintf('Rejected: %d (%.1f%%)\n', validation_result.num_rejected, validation_result.validation_summary.rejection_rate * 100);

if validation_result.num_validated > 0
    fprintf('\nValidated Impact Statistics:\n');
    fprintf('Impact times: %.1f ± %.1f ms\n', quality_metrics.mean_impact_time_ms, quality_metrics.std_impact_time_ms);
    fprintf('Time range: %.1f - %.1f ms\n', quality_metrics.impact_time_range_ms(1), quality_metrics.impact_time_range_ms(2));
    
    if isfield(quality_metrics, 'mean_interval_ms')
        fprintf('Inter-impact intervals: %.1f ± %.1f ms (min: %.1f ms)\n', ...
            quality_metrics.mean_interval_ms, std(quality_metrics.inter_impact_intervals_ms), quality_metrics.min_interval_ms);
        
        if quality_metrics.min_interval_ms >= config.min_impact_duration_ms
            fprintf('✓ All intervals meet physics constraints (≥%.1f ms)\n', config.min_impact_duration_ms);
        else
            fprintf('⚠ Some intervals violate physics constraints\n');
        end
    end
    
    if isfield(quality_metrics, 'mean_timing_error_ms')
        fprintf('\nTiming Accuracy (vs expected):\n');
        fprintf('Mean error: %.2f ms\n', quality_metrics.mean_timing_error_ms);
        fprintf('RMS error: %.2f ms\n', quality_metrics.rms_timing_error_ms);
        fprintf('Within tolerance (±%.1f ms): %.1f%%\n', ...
            config.impact_timing_tolerance_ms, quality_metrics.within_tolerance_rate * 100);
        
        if quality_metrics.rms_timing_error_ms <= config.impact_timing_tolerance_ms
            fprintf('✓ Timing accuracy target achieved\n');
        else
            fprintf('⚠ Timing accuracy target not met\n');
        end
    end
end

if validation_result.num_rejected > 0
    fprintf('\nRejection Reasons:\n');
    all_reasons = {};
    for i = 1:length(rejected_impacts)
        all_reasons = [all_reasons, rejected_impacts(i).rejection_reasons];
    end
    unique_reasons = unique(all_reasons);
    
    for i = 1:length(unique_reasons)
        reason_count = sum(strcmp(all_reasons, unique_reasons{i}));
        fprintf('- %s: %d cases\n', unique_reasons{i}, reason_count);
    end
end

fprintf('Impact timing validation completed.\n');

end
