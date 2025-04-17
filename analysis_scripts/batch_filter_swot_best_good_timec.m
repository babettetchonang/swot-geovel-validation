function batch_hp_lp_swot(inputDir, outputDir, lambda)
    % Ensure MATLAB function path is set for `filt2`
    addpath('/home/tchonang/matlab_functions');

    % Ensure output directory exists
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    % Get list of NetCDF files
    filePattern = fullfile(inputDir, '*v2.0.1.nc');
    fileList = dir(filePattern);

    % Check if files exist
    if isempty(fileList)
        fprintf('No NetCDF files found in %s\n', inputDir);
        return;
    end

    fprintf('Found %d files to process in %s\n', length(fileList), inputDir);

    % Process each file
    for k = 1:length(fileList)
        ncfile = fullfile(inputDir, fileList(k).name);
        fprintf('Processing file: %s\n', ncfile);

        % Read coordinates (lat, lon, timec)
        lat = ncread(ncfile, 'latitude'); % (num_lines, num_pixels)
        lon = ncread(ncfile, 'longitude'); % (num_lines, num_pixels)
        timec = ncread(ncfile, 'timec'); % Scalar (single time value)

        % Get reference time from NetCDF attributes
        timec_units = ncreadatt(ncfile, 'timec', 'units');
        ref_time_str = extractAfter(timec_units, "days since ");  
        ref_time = datetime(ref_time_str, 'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSSSSSSSS', 'TimeZone', 'UTC');

        % Convert timec to datetime
        timec_datetime = ref_time + days(timec);
        %timec_datetime

        % Convert timec to seconds since 2000-01-01 00:00:00 UTC (keeping name as timec)
        standard_ref_time = datetime(2000,1,1,0,0,0, 'TimeZone', 'UTC');
        timec_seconds = seconds(timec_datetime - standard_ref_time);

        % Read variables for filtering
        ssha = ncread(ncfile, 'ssha_unfiltered') + ncread(ncfile, 'mdt'); 
        ugosa = ncread(ncfile, 'ugosa_unfiltered'); 
        vgosa = ncread(ncfile, 'vgosa_unfiltered'); 

        % Set Resolution for SWOT Data
        res = 2; % Resolution in km (SWOT data)
        filtertype = 'hp'; % High-pass filtering

        % Apply high-pass filtering
        fprintf('Applying high-pass filter (λ = %d km, res = %d km)...\n', lambda, res);
        ssha_hp = filt2(ssha, res, lambda, filtertype);
        ugosa_hp = filt2(ugosa, res, lambda, filtertype);
        vgosa_hp = filt2(vgosa, res, lambda, filtertype);

        % Compute low-pass (residual)
        ssha_lp = ssha - ssha_hp;
        ugosa_lp = ugosa - ugosa_hp;
        vgosa_lp = vgosa - vgosa_hp;

        % Define output file name
        [~, fileName, ~] = fileparts(ncfile);
        outputFileName = fullfile(outputDir, sprintf('%s_%dkm_hp_lp.nc', fileName, lambda));

        % Delete existing file to avoid conflicts
        if exist(outputFileName, 'file')
            fprintf('Output file already exists: %s. Deleting and recreating...\n', outputFileName);
            delete(outputFileName);
        end

        % Create NetCDF file and define dimensions
        ncid = netcdf.create(outputFileName, 'NETCDF4');

        % Define dimensions
        dim_lines = netcdf.defDim(ncid, 'num_lines', size(lat, 1));
        dim_pixels = netcdf.defDim(ncid, 'num_pixels', size(lat, 2));
        dim_timec = netcdf.defDim(ncid, 'timec', 1); % Keep the name timec

        % Define coordinate variables
        varid_lat = netcdf.defVar(ncid, 'latitude', 'double', [dim_lines, dim_pixels]);
        varid_lon = netcdf.defVar(ncid, 'longitude', 'double', [dim_lines, dim_pixels]);
        varid_timec = netcdf.defVar(ncid, 'timec', 'double', dim_timec); % Kept as timec

        % Define high-pass filtered variables
        varid_ssha_hp = netcdf.defVar(ncid, sprintf('ssha_hp_%dkm', lambda), 'double', [dim_lines, dim_pixels]);
        varid_ugosa_hp = netcdf.defVar(ncid, sprintf('ugosa_hp_%dkm', lambda), 'double', [dim_lines, dim_pixels]);
        varid_vgosa_hp = netcdf.defVar(ncid, sprintf('vgosa_hp_%dkm', lambda), 'double', [dim_lines, dim_pixels]);

        % Define low-pass residual variables
        varid_ssha_lp = netcdf.defVar(ncid, sprintf('ssha_lp_%dkm', lambda), 'double', [dim_lines, dim_pixels]);
        varid_ugosa_lp = netcdf.defVar(ncid, sprintf('ugosa_lp_%dkm', lambda), 'double', [dim_lines, dim_pixels]);
        varid_vgosa_lp = netcdf.defVar(ncid, sprintf('vgosa_lp_%dkm', lambda), 'double', [dim_lines, dim_pixels]);

        % Assign coordinate attributes
        netcdf.putAtt(ncid, varid_lat, 'coordinates', 'latitude');
        netcdf.putAtt(ncid, varid_lon, 'coordinates', 'longitude');
        netcdf.putAtt(ncid, varid_timec, 'coordinates', 'timec'); 
        netcdf.putAtt(ncid, varid_timec, 'units', 'seconds since 2000-01-01 00:00:00 UTC'); % Update units
        netcdf.putAtt(ncid, varid_timec, 'long_name', 'Converted timec from days to seconds');

        % Close definition mode
        netcdf.endDef(ncid);

        % Write coordinate data
        netcdf.putVar(ncid, varid_lat, lat);
        netcdf.putVar(ncid, varid_lon, lon);
        netcdf.putVar(ncid, varid_timec, 0, 1, timec_seconds); % Save converted timec

        % Write high-pass filtered data
        netcdf.putVar(ncid, varid_ssha_hp, ssha_hp);
        netcdf.putVar(ncid, varid_ugosa_hp, ugosa_hp);
        netcdf.putVar(ncid, varid_vgosa_hp, vgosa_hp);

        % Write low-pass residual data
        netcdf.putVar(ncid, varid_ssha_lp, ssha_lp);
        netcdf.putVar(ncid, varid_ugosa_lp, ugosa_lp);
        netcdf.putVar(ncid, varid_vgosa_lp, vgosa_lp);

        % Close NetCDF file
        netcdf.close(ncid);

        fprintf('✅ HP & LP filtered data saved to %s\n', outputFileName);
    end
end

