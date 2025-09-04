function save_status = save_separation_results(results_data, output_path, config)
%% Save Separation Results
% Output management and validation for club/ball separation results

% Validate inputs
if ~isstruct(results_data)
    error('results_data must be a structure containing separation results');
end

if nargin < 2 || isempty(output_path)
    output_path = 'results';
end

if nargin < 3 || isempty(config)
    config = struct();
end

if ~isfield(config, 'save_format')
    config.save_format = {'mat', 'json'};  % Default formats
end

if ~isfield(config, 'compression')
    config.compression = true;
end

if ~isfield(config, 'backup_existing')
    config.backup_existing = true;
end

fprintf('Saving separation results to: %s\n', output_path);

% Create output directory
if ~exist(output_path, 'dir')
    mkdir(output_path);
    fprintf('Created output directory: %s\n', output_path);
end

save_status = struct();
save_status.output_path = output_path;
save_status.timestamp = datetime('now');
save_status.saved_files = {};
save_status.errors = {};

%% Prepare Results Data
% Add metadata
results_with_metadata = results_data;
results_with_metadata.metadata = struct();
results_with_metadata.metadata.save_timestamp = save_status.timestamp;
results_with_metadata.metadata.matlab_version = version;
results_with_metadata.metadata.system_info = struct();

try
    results_with_metadata.metadata.system_info.computer = computer;
    results_with_metadata.metadata.system_info.username = getenv('USERNAME');
catch
    results_with_metadata.metadata.system_info.computer = 'unknown';
    results_with_metadata.metadata.system_info.username = 'unknown';
end

%% Save in Different Formats
for format_idx = 1:length(config.save_format)
    format_type = config.save_format{format_idx};
    
    try
        switch lower(format_type)
            case 'mat'
                save_status = save_mat_format(results_with_metadata, output_path, config, save_status);
                
            case 'json'
                save_status = save_json_format(results_with_metadata, output_path, config, save_status);
                
            case 'csv'
                save_status = save_csv_format(results_with_metadata, output_path, config, save_status);
                
            case 'xlsx'
                save_status = save_excel_format(results_with_metadata, output_path, config, save_status);
                
            otherwise
                warning('Unsupported save format: %s', format_type);
        end
        
    catch ME
        error_msg = sprintf('Failed to save in %s format: %s', format_type, ME.message);
        save_status.errors{end+1} = error_msg;
        fprintf('Error: %s\n', error_msg);
    end
end

%% Generate Summary Report
summary_file = fullfile(output_path, 'separation_results_summary.txt');
try
    generate_summary_report(results_with_metadata, summary_file);
    save_status.saved_files{end+1} = summary_file;
    fprintf('Generated summary report: %s\n', summary_file);
catch ME
    error_msg = sprintf('Failed to generate summary report: %s', ME.message);
    save_status.errors{end+1} = error_msg;
end

%% Final Status
save_status.num_saved_files = length(save_status.saved_files);
save_status.num_errors = length(save_status.errors);
save_status.success = save_status.num_errors == 0;

fprintf('\nSave Results Summary:\n');
fprintf('- Files saved: %d\n', save_status.num_saved_files);
fprintf('- Errors: %d\n', save_status.num_errors);
fprintf('- Status: %s\n', char("SUCCESS" * save_status.success + "PARTIAL" * ~save_status.success));

end

function save_status = save_mat_format(results_data, output_path, config, save_status)
%% Save in MATLAB .mat format

filename = fullfile(output_path, 'separation_results.mat');

% Backup existing file if requested
if config.backup_existing && exist(filename, 'file')
    backup_filename = fullfile(output_path, sprintf('separation_results_backup_%s.mat', ...
        datestr(now, 'yyyymmdd_HHMMSS')));
    copyfile(filename, backup_filename);
    fprintf('Backed up existing file to: %s\n', backup_filename);
end

% Save with compression if requested
if config.compression
    save(filename, 'results_data', '-v7.3', '-nocompression');
else
    save(filename, 'results_data', '-v7.3');
end

save_status.saved_files{end+1} = filename;
fprintf('Saved MAT file: %s\n', filename);

end

function save_status = save_json_format(results_data, output_path, config, save_status)
%% Save key results in JSON format

% Extract key results for JSON (avoid complex nested structures)
json_data = struct();
json_data.metadata = results_data.metadata;

% Processing summary
if isfield(results_data, 'processing_summary')
    json_data.processing_summary = results_data.processing_summary;
end

% Summary statistics
if isfield(results_data, 'summary_stats')
    json_data.summary_stats = results_data.summary_stats;
end

% Performance metrics (simplified)
if isfield(results_data, 'performance_metrics')
    json_data.performance_metrics = results_data.performance_metrics;
end

filename = fullfile(output_path, 'separation_results_summary.json');

% Convert to JSON string
json_str = jsonencode(json_data, 'PrettyPrint', true);

% Write to file
fid = fopen(filename, 'w', 'n', 'UTF-8');
if fid == -1
    error('Could not open file for writing: %s', filename);
end

try
    fprintf(fid, '%s', json_str);
    fclose(fid);
    save_status.saved_files{end+1} = filename;
    fprintf('Saved JSON file: %s\n', filename);
catch ME
    fclose(fid);
    rethrow(ME);
end

end

function save_status = save_csv_format(results_data, output_path, config, save_status)
%% Save tabular results in CSV format

% Extract assignment results for CSV
if isfield(results_data, 'assignment_results') && isfield(results_data.assignment_results, 'assignments')
    assignments = results_data.assignment_results.assignments;
    
    if ~isempty(assignments)
        % Create table from assignments
        shot_names = cell(length(assignments), 1);
        club_velocities = zeros(length(assignments), 1);
        ball_velocities = zeros(length(assignments), 1);
        velocity_ratios = zeros(length(assignments), 1);
        confidences = zeros(length(assignments), 1);
        club_types = cell(length(assignments), 1);
        
        for i = 1:length(assignments)
            assignment = assignments(i);
            shot_names{i} = sprintf('Shot_%d', i);
            club_velocities(i) = assignment.club_velocity_mph;
            ball_velocities(i) = assignment.ball_velocity_mph;
            velocity_ratios(i) = assignment.velocity_ratio;
            confidences(i) = assignment.overall_confidence;
            club_types{i} = assignment.estimated_club_type;
        end
        
        % Create table
        results_table = table(shot_names, club_velocities, ball_velocities, ...
                            velocity_ratios, confidences, club_types, ...
                            'VariableNames', {'Shot', 'Club_Velocity_mph', 'Ball_Velocity_mph', ...
                            'Velocity_Ratio', 'Confidence', 'Club_Type'});
        
        filename = fullfile(output_path, 'separation_results.csv');
        writetable(results_table, filename);
        save_status.saved_files{end+1} = filename;
        fprintf('Saved CSV file: %s\n', filename);
    end
end

end

function save_status = save_excel_format(results_data, output_path, config, save_status)
%% Save results in Excel format (if available)

if ~exist('writetable', 'file')
    warning('Excel export requires writetable function (not available)');
    return;
end

filename = fullfile(output_path, 'separation_results.xlsx');

try
    % Similar to CSV but with multiple sheets
    if isfield(results_data, 'assignment_results') && isfield(results_data.assignment_results, 'assignments')
        assignments = results_data.assignment_results.assignments;
        
        if ~isempty(assignments)
            % Create main results table (same as CSV)
            shot_names = cell(length(assignments), 1);
            club_velocities = zeros(length(assignments), 1);
            ball_velocities = zeros(length(assignments), 1);
            velocity_ratios = zeros(length(assignments), 1);
            confidences = zeros(length(assignments), 1);
            club_types = cell(length(assignments), 1);
            
            for i = 1:length(assignments)
                assignment = assignments(i);
                shot_names{i} = sprintf('Shot_%d', i);
                club_velocities(i) = assignment.club_velocity_mph;
                ball_velocities(i) = assignment.ball_velocity_mph;
                velocity_ratios(i) = assignment.velocity_ratio;
                confidences(i) = assignment.overall_confidence;
                club_types{i} = assignment.estimated_club_type;
            end
            
            results_table = table(shot_names, club_velocities, ball_velocities, ...
                                velocity_ratios, confidences, club_types, ...
                                'VariableNames', {'Shot', 'Club_Velocity_mph', 'Ball_Velocity_mph', ...
                                'Velocity_Ratio', 'Confidence', 'Club_Type'});
            
            writetable(results_table, filename, 'Sheet', 'Results');
            save_status.saved_files{end+1} = filename;
            fprintf('Saved Excel file: %s\n', filename);
        end
    end
    
catch ME
    warning('Excel export failed: %s', ME.message);
end

end

function generate_summary_report(results_data, filename)
%% Generate text summary report

fid = fopen(filename, 'w');
if fid == -1
    error('Could not open summary file for writing: %s', filename);
end

try
    fprintf(fid, '=== Golf Launch Monitor - Club/Ball Separation Results ===\n');
    fprintf(fid, 'Generated: %s\n\n', datestr(now));
    
    % Processing summary
    if isfield(results_data, 'processing_summary')
        ps = results_data.processing_summary;
        fprintf(fid, '--- Processing Summary ---\n');
        fprintf(fid, 'Total shots: %d\n', ps.total_shots);
        fprintf(fid, 'Successful: %d (%.1f%%)\n', ps.successful_shots, ps.successful_shots/ps.total_shots*100);
        fprintf(fid, 'Failed: %d (%.1f%%)\n', ps.failed_shots, ps.failed_shots/ps.total_shots*100);
        if isfield(ps, 'processing_times')
            fprintf(fid, 'Average processing time: %.2f seconds\n', mean(ps.processing_times));
        end
        fprintf(fid, '\n');
    end
    
    % Velocity statistics
    if isfield(results_data, 'summary_stats') && isfield(results_data.summary_stats, 'velocity_statistics')
        vs = results_data.summary_stats.velocity_statistics;
        fprintf(fid, '--- Velocity Statistics ---\n');
        if isfield(vs, 'club_velocities')
            fprintf(fid, 'Club velocities: %.1f ± %.1f mph (%.1f - %.1f)\n', ...
                mean(vs.club_velocities), std(vs.club_velocities), ...
                min(vs.club_velocities), max(vs.club_velocities));
        end
        if isfield(vs, 'ball_velocities')
            fprintf(fid, 'Ball velocities: %.1f ± %.1f mph (%.1f - %.1f)\n', ...
                mean(vs.ball_velocities), std(vs.ball_velocities), ...
                min(vs.ball_velocities), max(vs.ball_velocities));
        end
        if isfield(vs, 'velocity_ratios')
            fprintf(fid, 'Velocity ratios: %.2f ± %.2f (%.2f - %.2f)\n', ...
                mean(vs.velocity_ratios), std(vs.velocity_ratios), ...
                min(vs.velocity_ratios), max(vs.velocity_ratios));
        end
        fprintf(fid, '\n');
    end
    
    % TrackMan validation
    if isfield(results_data, 'summary_stats') && isfield(results_data.summary_stats, 'trackman_validation')
        tv = results_data.summary_stats.trackman_validation;
        fprintf(fid, '--- TrackMan Validation ---\n');
        fprintf(fid, 'Mean error: %.1f mph\n', tv.mean_error);
        fprintf(fid, 'RMS error: %.1f mph\n', tv.rms_error);
        fprintf(fid, 'Within 10 mph: %.1f%%\n', tv.within_10mph_rate * 100);
        fprintf(fid, '\n');
    end
    
    fprintf(fid, '=== End of Report ===\n');
    
    fclose(fid);
    
catch ME
    fclose(fid);
    rethrow(ME);
end

end
