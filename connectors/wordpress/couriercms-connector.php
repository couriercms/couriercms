<?php
/**
 * Plugin Name: CourierCMS Connector
 * Description: Sends signed WordPress publish/update events to a CourierCMS installation.
 * Version: 0.1.0
 * Requires at least: 6.0
 * Requires PHP: 7.4
 * Author: CourierCMS
 */

if (!defined('ABSPATH')) {
    exit;
}

final class CourierCMS_Connector
{
    private const OPTION_KEY = 'couriercms_connector_settings';
    private const QUEUE_KEY = 'couriercms_connector_pending_events';
    private const RETRY_HOOK = 'couriercms_connector_retry_events';
    private const MAX_QUEUE_SIZE = 100;
    private const MAX_ATTEMPTS = 10;

    public static function boot(): void
    {
        add_action('admin_menu', [self::class, 'admin_menu']);
        add_action('admin_init', [self::class, 'register_settings']);
        add_action('wp_after_insert_post', [self::class, 'post_saved'], 10, 4);
        add_action(self::RETRY_HOOK, [self::class, 'retry_events']);
    }

    public static function admin_menu(): void
    {
        add_options_page(
            'CourierCMS Connector',
            'CourierCMS Connector',
            'manage_options',
            'couriercms-connector',
            [self::class, 'settings_page']
        );
    }

    public static function register_settings(): void
    {
        register_setting('couriercms_connector', self::OPTION_KEY, [
            'type' => 'object',
            'sanitize_callback' => [self::class, 'sanitize_settings'],
            'default' => [],
        ]);
    }

    public static function sanitize_settings($input): array
    {
        return [
            'endpoint' => esc_url_raw((string) ($input['endpoint'] ?? '')),
            'secret' => sanitize_text_field((string) ($input['secret'] ?? '')),
        ];
    }

    public static function settings_page(): void
    {
        if (!current_user_can('manage_options')) {
            return;
        }

        $settings = self::settings();
        ?>
        <div class="wrap">
            <h1>CourierCMS Connector</h1>
            <p>Copy the webhook URL and signing secret generated on the CourierCMS Connections page.</p>
            <form method="post" action="options.php">
                <?php settings_fields('couriercms_connector'); ?>
                <table class="form-table" role="presentation">
                    <tr>
                        <th scope="row"><label for="couriercms-endpoint">Webhook URL</label></th>
                        <td><input id="couriercms-endpoint" class="regular-text code" type="url"
                            name="<?php echo esc_attr(self::OPTION_KEY); ?>[endpoint]"
                            value="<?php echo esc_attr($settings['endpoint'] ?? ''); ?>" required></td>
                    </tr>
                    <tr>
                        <th scope="row"><label for="couriercms-secret">Signing secret</label></th>
                        <td><input id="couriercms-secret" class="regular-text code" type="password"
                            name="<?php echo esc_attr(self::OPTION_KEY); ?>[secret]"
                            value="<?php echo esc_attr($settings['secret'] ?? ''); ?>" required
                            autocomplete="new-password"></td>
                    </tr>
                </table>
                <?php submit_button(); ?>
            </form>
            <p><strong>Pending retries:</strong> <?php echo esc_html((string) count(self::queue())); ?></p>
        </div>
        <?php
    }

    public static function post_saved(int $post_id, WP_Post $post, bool $update, ?WP_Post $post_before): void
    {
        if (
            $post->post_type !== 'post' ||
            $post->post_status !== 'publish' ||
            wp_is_post_revision($post_id) ||
            wp_is_post_autosave($post_id)
        ) {
            return;
        }

        $was_published = $post_before instanceof WP_Post && $post_before->post_status === 'publish';

        $payload = [
            'contract_version' => 1,
            'event_id' => wp_generate_uuid4(),
            'event' => $update && $was_published ? 'content.updated' : 'content.published',
            'source_item_id' => (string) $post_id,
            'source_modified_at' => get_post_modified_time('c', true, $post),
        ];

        if (!self::send($payload)) {
            self::enqueue($payload, 1);
        }
    }

    public static function retry_events(): void
    {
        $now = time();
        $remaining = [];

        foreach (self::queue() as $queued) {
            if (($queued['next_at'] ?? 0) > $now) {
                $remaining[] = $queued;
                continue;
            }

            if (self::send($queued['payload'] ?? [])) {
                continue;
            }

            $attempts = (int) ($queued['attempts'] ?? 1) + 1;
            if ($attempts <= self::MAX_ATTEMPTS) {
                $remaining[] = [
                    'payload' => $queued['payload'],
                    'attempts' => $attempts,
                    'next_at' => $now + min(3600, 60 * (2 ** min($attempts - 1, 6))),
                ];
            }
        }

        self::save_queue($remaining);
        self::schedule_retry($remaining);
    }

    private static function send(array $payload): bool
    {
        $settings = self::settings();
        $endpoint = (string) ($settings['endpoint'] ?? '');
        $secret = (string) ($settings['secret'] ?? '');

        if ($endpoint === '' || strlen($secret) < 32 || empty($payload['event_id'])) {
            return false;
        }

        $body = wp_json_encode($payload);
        if (!is_string($body)) {
            return false;
        }

        $timestamp = (string) time();
        $signature = hash_hmac('sha256', $timestamp . '.' . $body, $secret);
        $response = wp_remote_post($endpoint, [
            'timeout' => 8,
            'redirection' => 0,
            'headers' => [
                'Content-Type' => 'application/json',
                'X-CourierCMS-Timestamp' => $timestamp,
                'X-CourierCMS-Signature' => 'sha256=' . $signature,
            ],
            'body' => $body,
        ]);

        return !is_wp_error($response) && wp_remote_retrieve_response_code($response) >= 200
            && wp_remote_retrieve_response_code($response) < 300;
    }

    private static function enqueue(array $payload, int $attempts): void
    {
        $queue = self::queue();
        $queue[] = [
            'payload' => $payload,
            'attempts' => $attempts,
            'next_at' => time() + 60,
        ];
        $queue = array_slice($queue, -self::MAX_QUEUE_SIZE);
        self::save_queue($queue);
        self::schedule_retry($queue);
    }

    private static function schedule_retry(array $queue): void
    {
        if (!empty($queue) && !wp_next_scheduled(self::RETRY_HOOK)) {
            wp_schedule_single_event(time() + 60, self::RETRY_HOOK);
        }
    }

    private static function settings(): array
    {
        $settings = get_option(self::OPTION_KEY, []);
        return is_array($settings) ? $settings : [];
    }

    private static function queue(): array
    {
        $queue = get_option(self::QUEUE_KEY, []);
        return is_array($queue) ? $queue : [];
    }

    private static function save_queue(array $queue): void
    {
        if (get_option(self::QUEUE_KEY, null) === null) {
            add_option(self::QUEUE_KEY, $queue, '', false);
        } else {
            update_option(self::QUEUE_KEY, $queue, false);
        }
    }
}

CourierCMS_Connector::boot();
