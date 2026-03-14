<?php defined('BASEPATH') or exit('No direct script access allowed');

/*
|--------------------------------------------------------------------------
| App Configuration
|--------------------------------------------------------------------------
|
| Declare some of the global config values of Easy!Appointments.
|
*/

$config['version'] = '1.5.2'; // This must be changed manually.

$config['url'] = getenv('EA_BASE_URL') ?: Config::BASE_URL;

$config['debug'] = filter_var(
    getenv('EA_DEBUG_MODE') ?: Config::DEBUG_MODE,
    FILTER_VALIDATE_BOOLEAN,
);

$config['cache_busting_token'] = 'TSJ79';
