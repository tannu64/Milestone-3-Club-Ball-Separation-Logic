
%Extract ball\club speeds from directory names
function trackman_data = extract_trackman_ref(directory_name)
%% Extract TrackMan Reference Data from Directory Name
% Parses directory names to extract ball speed, height, and timestamp
% Handles all dataset schema variations (LOG[YYYYMMDD][HHMMSS] format)
%
% Inputs:
%   directory_name - Directory name string (e.g., 'LOG20240128164124_B97.9-H79.7')
%
% Outputs:
%   trackman_data - Structure containing parsed reference data

% Validate input
if isempty(directory_name) || ~ischar(directory_name)
    error('Directory name must be a non-empty string');
end

% Initialize output structure
trackman_data = struct();
trackman_data.directory_name = directory_name;
trackman_data.parsing_success = false;
trackman_data.ball_speed = NaN;
trackman_data.height = NaN;
trackman_data.timestamp = '';
trackman_data.date = '';
trackman_data.time = '';
trackman_data.performance_category = '';
trackman_data.is_valid_shot = false;

try
    % Parse the directory name pattern: LOG[YYYYMMDD][HHMMSS]_B[BallSpeed]-H[Height]
    
    % Extract date and time components
    date_time_pattern = 'LOG(\d{8})(\d{6})';
    date_time_match = regexp(directory_name, date_time_pattern, 'tokens');
    
    if isempty(date_time_match)
        warning('Could not parse date/time from directory: %s', directory_name);
        return;
    end
    
    date_str = date_time_match{1}{1};  % YYYYMMDD
    time_str = date_time_match{1}{2};  % HHMMSS
    
    % Parse date components
    year = str2double(date_str(1:4));
    month = str2double(date_str(5:6));
    day = str2double(date_str(7:8));
    
    % Parse time components
    hour = str2double(time_str(1:2));
    minute = str2double(time_str(3:4));
    second = str2double(time_str(5:6));
    
    % Create timestamp string
    timestamp = sprintf('%04d-%02d-%02d %02d:%02d:%02d', year, month, day, hour, minute, second);
    
    % Extract ball speed and height
    performance_pattern = 'B([\d.]+)-H([\d.]+)';
    performance_match = regexp(directory_name, performance_pattern, 'tokens');
    
    if isempty(performance_match)
        % Check for MISS values
        if contains(directory_name, 'BMISS') || contains(directory_name, 'HMISS')
            trackman_data.ball_speed = NaN;
            trackman_data.height = NaN;
            trackman_data.is_valid_shot = false;
            trackman_data.performance_category = 'MISS';
        else
            warning('Could not parse ball speed/height from directory: %s', directory_name);
            return;
        end
    else
        % Extract numeric values
        ball_speed = str2double(performance_match{1}{1});
        height = str2double(performance_match{1}{2});
        
        % Validate ranges
        if ball_speed >= 56.5 && ball_speed <= 178.9 && height >= 45.7 && height <= 120.4
            trackman_data.ball_speed = ball_speed;
            trackman_data.height = height;
            trackman_data.is_valid_shot = true;
            
            % Categorize performance
            trackman_data.performance_category = categorize_performance(ball_speed, height);
        else
            warning('Ball speed or height out of expected range in directory: %s', directory_name);
            trackman_data.ball_speed = ball_speed;
            trackman_data.height = height;
            trackman_data.is_valid_shot = false;
            trackman_data.performance_category = 'OUT_OF_RANGE';
        end
    end
    
    % Store parsed data
    trackman_data.timestamp = timestamp;
    trackman_data.date = sprintf('%04d-%02d-%02d', year, month, day);
    trackman_data.time = sprintf('%02d:%02d:%02d', hour, minute, second);
    trackman_data.parsing_success = true;
    
    % Log successful parsing
    if trackman_data.is_valid_shot
        fprintf('Successfully parsed TrackMan data: B%.1f-H%.1f (%s)\n', ...
            trackman_data.ball_speed, trackman_data.height, trackman_data.performance_category);
    else
        fprintf('Parsed directory with invalid shot: %s\n', directory_name);
    end
    
catch ME
    warning('Error parsing TrackMan data from directory %s: %s', directory_name, ME.message);
    trackman_data.parsing_success = false;
end

end

function category = categorize_performance(ball_speed, height)
%% Categorize golf shot performance based on ball speed and height
% 
% Inputs:
%   ball_speed - Ball speed in mph
%   height - Height/launch angle
%
% Outputs:
%   category - Performance category string

if ball_speed >= 56.5 && ball_speed < 90.0
    if height >= 45.7 && height < 70.0
        category = 'Low_Putter';
    else
        category = 'Mid_Putter';
    end
elseif ball_speed >= 90.0 && ball_speed < 130.0
    if height >= 70.0 && height < 90.0
        category = 'Low_Iron';
    else
        category = 'Mid_Iron';
    end
elseif ball_speed >= 130.0 && ball_speed < 160.0
    if height >= 85.0 && height < 105.0
        category = 'Low_Wood';
    else
        category = 'Mid_Wood';
    end
elseif ball_speed >= 160.0 && ball_speed <= 178.9
    if height >= 95.0 && height <= 120.4
        category = 'Driver';
    else
        category = 'High_Driver';
    end
else
    category = 'Unknown';
end

end