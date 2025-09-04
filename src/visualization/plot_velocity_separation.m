
function plot_velocity_separation(assignment_results, trackman_validation, velocity_data, config)
%% Plot Velocity Separation Results
% Separation Accuracy: Club/ball velocity estimates vs. TrackMan scatter plots
% Error Analysis: RMS error distributions by shot type and velocity range  
% Velocity Trajectories: Time-series plots showing separated club/ball tracks
% Physics Validation: Velocity ratios and energy transfer consistency checks

% Validate inputs
if ~isstruct(assignment_results) || ~isfield(assignment_results, 'assignments')
    error('assignment_results must contain assignments field');
end

if nargin < 4 || isempty(config)
    config = struct();
end

if ~isfield(config, 'save_figures')
    config.save_figures = true;
end

if ~isfield(config, 'figure_format')
    config.figure_format = 'png';
end

if ~isfield(config, 'output_dir')
    config.output_dir = 'figures';
end

fprintf('Creating velocity separation visualization plots...\n');

% Create output directory
if config.save_figures && ~exist(config.output_dir, 'dir')
    mkdir(config.output_dir);
end

assignments = assignment_results.assignments;
num_assignments = length(assignments);

%% Figure 1: Club vs Ball Velocity Scatter Plot
fig1 = figure('Position', [100, 100, 1000, 800]);
sgtitle('Club/Ball Velocity Separation Results', 'FontSize', 16, 'FontWeight', 'bold');

% Extract velocities
club_velocities = [assignments.club_velocity_mph];
ball_velocities = [assignments.ball_velocity_mph];
velocity_ratios = [assignments.velocity_ratio];

% Subplot 1: Club vs Ball velocities
subplot(2, 2, 1);
scatter(club_velocities, ball_velocities, 50, velocity_ratios, 'filled');
colorbar;
colormap('viridis');
xlabel('Club Velocity (mph)');
ylabel('Ball Velocity (mph)');
title('Club vs Ball Velocity Separation');
grid on;

% Add physics constraint lines
hold on;
x_range = [min(club_velocities), max(club_velocities)];
plot(x_range, 1.2 * x_range, 'r--', 'LineWidth', 2, 'Alpha', 0.7);  % Min ratio
plot(x_range, 2.5 * x_range, 'r--', 'LineWidth', 2, 'Alpha', 0.7);  % Max ratio
legend('Measurements', 'Physics Bounds', 'Location', 'best');

% Subplot 2: Velocity ratio distribution
subplot(2, 2, 2);
histogram(velocity_ratios, 20, 'FaceColor', [0.7, 0.8, 0.9]);
xlabel('Velocity Ratio (Ball/Club)');
ylabel('Count');
title('Velocity Ratio Distribution');
grid on;

% Add expected ranges
xline(1.2, 'r--', 'Wedge Min', 'LineWidth', 2);
xline(1.8, 'r--', 'Wedge Max', 'LineWidth', 2);
xline(2.5, 'g--', 'Driver Max', 'LineWidth', 2);

% Subplot 3: Club velocity distribution
subplot(2, 2, 3);
histogram(club_velocities, 15, 'FaceColor', [0.9, 0.7, 0.7]);
xlabel('Club Velocity (mph)');
ylabel('Count');
title('Club Velocity Distribution');
grid on;

% Subplot 4: Ball velocity distribution
subplot(2, 2, 4);
histogram(ball_velocities, 15, 'FaceColor', [0.7, 0.9, 0.7]);
xlabel('Ball Velocity (mph)');
ylabel('Count');
title('Ball Velocity Distribution');
grid on;

if config.save_figures
    filename1 = fullfile(config.output_dir, sprintf('velocity_separation_overview.%s', config.figure_format));
    saveas(fig1, filename1);
    fprintf('Saved: %s\n', filename1);
end

%% Figure 2: TrackMan Validation (if available)
if nargin >= 2 && ~isempty(trackman_validation) && isfield(trackman_validation, 'validations')
    fig2 = figure('Position', [150, 150, 1200, 600]);
    sgtitle('TrackMan Validation Results', 'FontSize', 16, 'FontWeight', 'bold');
    
    validations = trackman_validation.validations;
    
    if ~isempty(validations)
        predicted_speeds = [validations.predicted_ball_speed];
        reference_speeds = [validations.reference_ball_speed];
        velocity_errors = [validations.velocity_error_mph];
        
        % Subplot 1: Predicted vs Reference scatter
        subplot(1, 3, 1);
        scatter(reference_speeds, predicted_speeds, 50, 'b', 'filled');
        hold on;
        
        % Perfect prediction line
        speed_range = [min([reference_speeds, predicted_speeds]), max([reference_speeds, predicted_speeds])];
        plot(speed_range, speed_range, 'r--', 'LineWidth', 2);
        
        % ±10 mph error bounds
        plot(speed_range, speed_range + 10, 'g:', 'LineWidth', 1.5);
        plot(speed_range, speed_range - 10, 'g:', 'LineWidth', 1.5);
        
        xlabel('TrackMan Reference (mph)');
        ylabel('Predicted Ball Speed (mph)');
        title('Prediction Accuracy');
        legend('Predictions', 'Perfect', '±10 mph', 'Location', 'best');
        grid on;
        axis equal;
        
        % Subplot 2: Error distribution
        subplot(1, 3, 2);
        histogram(velocity_errors, 15, 'FaceColor', [0.8, 0.8, 0.9]);
        xlabel('Velocity Error (mph)');
        ylabel('Count');
        title('Error Distribution');
        grid on;
        
        % Add error statistics
        mean_error = mean(velocity_errors);
        rms_error = sqrt(mean(velocity_errors.^2));
        xline(mean_error, 'r-', sprintf('Mean: %.1f', mean_error), 'LineWidth', 2);
        xline(rms_error, 'g-', sprintf('RMS: %.1f', rms_error), 'LineWidth', 2);
        
        % Subplot 3: Error vs ball speed
        subplot(1, 3, 3);
        scatter(reference_speeds, velocity_errors, 50, 'r', 'filled');
        xlabel('Ball Speed (mph)');
        ylabel('Velocity Error (mph)');
        title('Error vs Ball Speed');
        grid on;
        
        % Add 10 mph threshold line
        yline(10, 'k--', '10 mph threshold', 'LineWidth', 2);
        
        if config.save_figures
            filename2 = fullfile(config.output_dir, sprintf('trackman_validation.%s', config.figure_format));
            saveas(fig2, filename2);
            fprintf('Saved: %s\n', filename2);
        end
    end
end

%% Figure 3: Velocity Trajectories (if velocity_data available)
if nargin >= 3 && ~isempty(velocity_data) && isfield(velocity_data, 'velocity_segments')
    fig3 = figure('Position', [200, 200, 1200, 800]);
    sgtitle('Velocity Trajectories Over Time', 'FontSize', 16, 'FontWeight', 'bold');
    
    velocity_segments = velocity_data.velocity_segments;
    
    if ~isempty(velocity_segments)
        % Plot first few segments for visualization
        max_segments = min(6, length(velocity_segments));
        
        for seg_idx = 1:max_segments
            subplot(2, 3, seg_idx);
            
            segment = velocity_segments(seg_idx);
            times = segment.times * 1000;  % Convert to ms
            velocities = abs(segment.velocities);  % Take magnitude
            
            plot(times, velocities, 'b-', 'LineWidth', 2);
            hold on;
            
            % Mark peak velocity
            [peak_vel, peak_idx] = max(velocities);
            plot(times(peak_idx), peak_vel, 'ro', 'MarkerSize', 8, 'LineWidth', 2);
            
            xlabel('Time (ms)');
            ylabel('Velocity (mph)');
            title(sprintf('Segment %d (Peak: %.1f mph)', seg_idx, peak_vel));
            grid on;
            
            % Add segment classification if available
            if isfield(segment, 'classification')
                text(0.05, 0.95, sprintf('Class: %s', segment.classification), ...
                    'Units', 'normalized', 'FontSize', 10, 'BackgroundColor', 'white');
            end
        end
        
        if config.save_figures
            filename3 = fullfile(config.output_dir, sprintf('velocity_trajectories.%s', config.figure_format));
            saveas(fig3, filename3);
            fprintf('Saved: %s\n', filename3);
        end
    end
end

%% Figure 4: Physics Validation
fig4 = figure('Position', [250, 250, 1000, 600]);
sgtitle('Physics Validation Analysis', 'FontSize', 16, 'FontWeight', 'bold');

% Subplot 1: Velocity ratio vs ball speed
subplot(2, 2, 1);
scatter(ball_velocities, velocity_ratios, 50, 'b', 'filled');
xlabel('Ball Velocity (mph)');
ylabel('Velocity Ratio');
title('Velocity Ratio vs Ball Speed');
grid on;

% Add expected ranges by club type
hold on;
% Wedge range
fill([56.5, 89.9, 89.9, 56.5], [1.2, 1.2, 1.8, 1.8], 'r', 'Alpha', 0.2);
% Iron range
fill([90, 139.9, 139.9, 90], [1.4, 1.4, 2.2, 2.2], 'g', 'Alpha', 0.2);
% Driver range
fill([140, 178.9, 178.9, 140], [1.6, 1.6, 2.5, 2.5], 'b', 'Alpha', 0.2);
legend('Measurements', 'Wedge', 'Iron', 'Driver', 'Location', 'best');

% Subplot 2: Energy transfer analysis (simplified)
subplot(2, 2, 2);
% Approximate kinetic energy ratio
energy_ratios = velocity_ratios.^2;  % Assuming equal mass ratio
scatter(ball_velocities, energy_ratios, 50, 'g', 'filled');
xlabel('Ball Velocity (mph)');
ylabel('Energy Ratio');
title('Energy Transfer Efficiency');
grid on;

% Subplot 3: Confidence vs velocity ratio
confidences = [assignments.overall_confidence];
subplot(2, 2, 3);
scatter(velocity_ratios, confidences, 50, 'r', 'filled');
xlabel('Velocity Ratio');
ylabel('Assignment Confidence');
title('Confidence vs Velocity Ratio');
grid on;

% Subplot 4: Club type classification
subplot(2, 2, 4);
estimated_club_types = {assignments.estimated_club_type};
club_type_counts = [sum(strcmp(estimated_club_types, 'wedge')), ...
                   sum(strcmp(estimated_club_types, 'iron')), ...
                   sum(strcmp(estimated_club_types, 'driver'))];

pie(club_type_counts, {'Wedge', 'Iron', 'Driver'});
title('Club Type Distribution');

if config.save_figures
    filename4 = fullfile(config.output_dir, sprintf('physics_validation.%s', config.figure_format));
    saveas(fig4, filename4);
    fprintf('Saved: %s\n', filename4);
end

%% Summary Statistics
fprintf('\n=== Velocity Separation Summary ===\n');
fprintf('Total assignments: %d\n', num_assignments);
fprintf('Club velocity: %.1f ± %.1f mph (%.1f - %.1f)\n', ...
    mean(club_velocities), std(club_velocities), min(club_velocities), max(club_velocities));
fprintf('Ball velocity: %.1f ± %.1f mph (%.1f - %.1f)\n', ...
    mean(ball_velocities), std(ball_velocities), min(ball_velocities), max(ball_velocities));
fprintf('Velocity ratio: %.2f ± %.2f (%.2f - %.2f)\n', ...
    mean(velocity_ratios), std(velocity_ratios), min(velocity_ratios), max(velocity_ratios));

% Physics validation
valid_ratios = velocity_ratios >= 1.2 & velocity_ratios <= 2.5;
fprintf('Physics-valid ratios: %d/%d (%.1f%%)\n', ...
    sum(valid_ratios), length(valid_ratios), sum(valid_ratios)/length(valid_ratios)*100);

if exist('validations', 'var') && ~isempty(validations)
    fprintf('\nTrackMan Validation:\n');
    fprintf('RMS error: %.1f mph\n', sqrt(mean(velocity_errors.^2)));
    fprintf('Mean error: %.1f mph\n', mean(velocity_errors));
    fprintf('Within 10 mph: %d/%d (%.1f%%)\n', ...
        sum(velocity_errors <= 10), length(velocity_errors), ...
        sum(velocity_errors <= 10)/length(velocity_errors)*100);
end

fprintf('Velocity separation visualization completed.\n');

end