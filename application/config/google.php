<?php defined('BASEPATH') or exit('No direct script access allowed');

/*
|--------------------------------------------------------------------------
| Google Calendar - Internal Configuration
|--------------------------------------------------------------------------
|
| Declare some of the global config values of the Google Calendar
| synchronization feature.
|
*/

$config['google_sync_feature'] = filter_var(
    getenv('EA_GOOGLE_SYNC') ?: Config::GOOGLE_SYNC_FEATURE,
    FILTER_VALIDATE_BOOLEAN,
);

$config['google_client_id'] = getenv('EA_GOOGLE_CLIENT_ID') ?: Config::GOOGLE_CLIENT_ID;

$config['google_client_secret'] = getenv('EA_GOOGLE_CLIENT_SECRET') ?: Config::GOOGLE_CLIENT_SECRET;
