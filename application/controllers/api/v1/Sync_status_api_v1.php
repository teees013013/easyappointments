<?php defined('BASEPATH') or exit('No direct script access allowed');

/* ----------------------------------------------------------------------------
 * Easy!Appointments - Online Appointment Scheduler
 *
 * @package     EasyAppointments
 * @author      A.Tselegidis <alextselegidis@gmail.com>
 * @copyright   Copyright (c) Alex Tselegidis
 * @license     https://opensource.org/licenses/GPL-3.0 - GPLv3
 * @link        https://easyappointments.org
 * @since       v1.5.0
 * ---------------------------------------------------------------------------- */

/**
 * Sync Status API v1 controller.
 *
 * Reports Google Calendar sync status per provider.
 *
 * @package Controllers
 */
class Sync_status_api_v1 extends EA_Controller
{
    /**
     * Sync_status_api_v1 constructor.
     */
    public function __construct()
    {
        parent::__construct();

        $this->load->library('api');

        $this->api->auth();

        $this->api->model('providers_model');
    }

    /**
     * Get sync status for all providers.
     */
    public function index(): void
    {
        try {
            $providers = $this->providers_model->get();

            $google_sync_enabled = config('google_sync_feature');

            $provider_statuses = [];

            foreach ($providers as $provider) {
                $settings = $provider['settings'] ?? [];

                $provider_statuses[] = [
                    'providerId' => (int) $provider['id'],
                    'providerName' => ($provider['first_name'] ?? '') . ' ' . ($provider['last_name'] ?? ''),
                    'googleSync' => array_key_exists('google_sync', $settings)
                        ? filter_var($settings['google_sync'], FILTER_VALIDATE_BOOLEAN)
                        : false,
                    'googleCalendar' => $settings['google_calendar'] ?? null,
                    'caldavSync' => array_key_exists('caldav_sync', $settings)
                        ? filter_var($settings['caldav_sync'], FILTER_VALIDATE_BOOLEAN)
                        : false,
                ];
            }

            json_response([
                'googleSyncEnabled' => filter_var($google_sync_enabled, FILTER_VALIDATE_BOOLEAN),
                'providers' => $provider_statuses,
            ]);
        } catch (Throwable $e) {
            json_exception($e);
        }
    }
}
