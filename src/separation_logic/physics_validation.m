function physics_results = physics_validation(separation_results, config)
%% Physics Validation
% Validate against golf ball impact physics

% Validate inputs
if ~isstruct(separation_results) || ~isfield(separation_results, 'separations')
    error('separation_results must contain separations field');
end

% Default configuration
if nargin < 2 || isempty(config)
    config = struct();
end

if ~isfield(config, 'velocity_ratio_limits')
    config.velocity_ratio_limits = [1.0, 3.0];  % Ball/club velocity ratio limits
end

if ~isfield(config, 'impact_duration_limits_ms')
    config.impact_duration_limits_ms = [0.3, 3.0];  % Physical impact duration limits
end

separations = separation_results.separations;
num_separations = length(separations);

fprintf('Validating %d separations against golf ball impact physics...\n', num_separations);

%% Initialize Physics Results
physics_results = struct();
physics_results.num_separations = num_separations;
physics_results.validated_separations = [];
physics_results.physics_violations = [];

%% Process Each Separation
for sep_idx = 1:num_separations
    separation = separations(sep_idx);
    
    % Initialize physics validation record
    physics_record = struct();
    physics_record.separation_idx = sep_idx;
    physics_record.is_physics_valid = true;
    physics_record.violation_reasons = {};
    physics_record.warning_flags = {};
    
    % Extract velocity information
    if isfield(separation, 'club_track') && isfield(separation, 'ball_track')
        club_track = separation.club_track;
        ball_track = separation.ball_track;
        
        % Get peak velocities
        if isfield(club_track, 'max_velocity') && isfield(ball_track, 'max_velocity')
            club_velocity = club_track.max_velocity;
            ball_velocity = ball_track.max_velocity;
            
            physics_record.club_velocity_mph = club_velocity;
            physics_record.ball_velocity_mph = ball_velocity;
            
            %% Test 1: Velocity Ratio Validation
            if club_velocity > 0
                velocity_ratio = ball_velocity / club_velocity;
                physics_record.velocity_ratio = velocity_ratio;
                
                if velocity_ratio < config.velocity_ratio_limits(1) || velocity_ratio > config.velocity_ratio_limits(2)
                    physics_record.is_physics_valid = false;
                    physics_record.violation_reasons{end+1} = sprintf('Velocity ratio out of range (%.2f not in [%.1f, %.1f])', ...
                        velocity_ratio, config.velocity_ratio_limits(1), config.velocity_ratio_limits(2));
                end
                
                % Club-specific validation
                estimated_club_type = estimate_club_type_from_velocity(ball_velocity);
                physics_record.estimated_club_type = estimated_club_type;
                
                ratio_range = get_expected_velocity_ratio(estimated_club_type);
                if velocity_ratio < ratio_range(1) || velocity_ratio > ratio_range(2)
                    physics_record.warning_flags{end+1} = sprintf('%s velocity ratio unusual (%.2f not in [%.1f, %.1f])', ...
                        estimated_club_type, velocity_ratio, ratio_range(1), ratio_range(2));
                end
            end
            
            %% Test 2: Velocity Range Validation
            ball_range = get_velocity_range(estimated_club_type, 'ball');
            club_range = get_velocity_range(estimated_club_type, 'club');
            
            if ball_velocity < ball_range(1) || ball_velocity > ball_range(2)
                physics_record.warning_flags{end+1} = sprintf('Ball velocity outside typical %s range (%.1f not in [%.1f, %.1f] mph)', ...
                    estimated_club_type, ball_velocity, ball_range(1), ball_range(2));
            end
            
            if club_velocity < club_range(1) || club_velocity > club_range(2)
                physics_record.warning_flags{end+1} = sprintf('Club velocity outside typical %s range (%.1f not in [%.1f, %.1f] mph)', ...
                    estimated_club_type, club_velocity, club_range(1), club_range(2));
            end
        end
    end
    
    %% Test 3: Impact Timing Validation
    if isfield(separation, 'impact_timing') && ~isnan(separation.impact_timing)
        impact_duration_ms = separation.impact_timing * 1000;
        
        if impact_duration_ms < config.impact_duration_limits_ms(1) || ...
           impact_duration_ms > config.impact_duration_limits_ms(2)
            physics_record.is_physics_valid = false;
            physics_record.violation_reasons{end+1} = sprintf('Impact duration unphysical (%.2f ms not in [%.1f, %.1f] ms)', ...
                impact_duration_ms, config.impact_duration_limits_ms(1), config.impact_duration_limits_ms(2));
        end
    end
    
    %% Store Physics Record
    if physics_record.is_physics_valid
        physics_results.validated_separations = [physics_results.validated_separations; physics_record];
    else
        physics_results.physics_violations = [physics_results.physics_violations; physics_record];
    end
end

%% Compile Results
physics_results.num_validated = length(physics_results.validated_separations);
physics_results.num_violations = length(physics_results.physics_violations);

physics_results.validation_summary = struct();
physics_results.validation_summary.validation_rate = physics_results.num_validated / num_separations;
physics_results.validation_summary.violation_rate = physics_results.num_violations / num_separations;

%% Generate Report
fprintf('\n=== Physics Validation Summary ===\n');
fprintf('Total separations: %d\n', num_separations);
fprintf('Physics valid: %d (%.1f%%)\n', physics_results.num_validated, physics_results.validation_summary.validation_rate * 100);
fprintf('Physics violations: %d (%.1f%%)\n', physics_results.num_violations, physics_results.validation_summary.violation_rate * 100);

fprintf('Physics validation completed.\n');

end

function club_type = estimate_club_type_from_velocity(ball_velocity)
if ball_velocity < 90
    club_type = 'wedge';
elseif ball_velocity < 140
    club_type = 'iron';
else
    club_type = 'driver';
end
end

function ratio_range = get_expected_velocity_ratio(club_type)
switch club_type
    case 'wedge'
        ratio_range = [1.2, 1.8];
    case 'iron'
        ratio_range = [1.4, 2.2];
    case 'driver'
        ratio_range = [1.6, 2.5];
    otherwise
        ratio_range = [1.0, 3.0];
end
end

function velocity_range = get_velocity_range(club_type, track_type)
switch club_type
    case 'wedge'
        if strcmp(track_type, 'ball')
            velocity_range = [56.5, 89.9];
        else
            velocity_range = [40, 60];
        end
    case 'iron'
        if strcmp(track_type, 'ball')
            velocity_range = [90, 139.9];
        else
            velocity_range = [60, 85];
        end
    case 'driver'
        if strcmp(track_type, 'ball')
            velocity_range = [140, 178.9];
        else
            velocity_range = [85, 120];
        end
    otherwise
        velocity_range = [0, 200];
end
end