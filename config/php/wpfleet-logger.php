<?php
/**
 * WPFleet Structured Logger
 *
 * Provides structured logging for WordPress sites using FrankenPHP's frankenphp_log()
 * This library should be included in wp-config.php or as a mu-plugin
 *
 * @package WPFleet
 * @version 1.0.0
 */

if (!function_exists('wpfleet_log')) {
    /**
     * Log a message with structured context using FrankenPHP's native logging
     *
     * @param string $message The log message
     * @param string $level Log level (debug, info, warn, error)
     * @param array $context Additional context data
     * @return void
     */
    function wpfleet_log($message, $level = 'info', $context = []) {
        // Map our log levels to FrankenPHP constants
        $levels = [
            'debug' => FRANKENPHP_LOG_LEVEL_DEBUG,
            'info'  => FRANKENPHP_LOG_LEVEL_INFO,
            'warn'  => FRANKENPHP_LOG_LEVEL_WARN,
            'error' => FRANKENPHP_LOG_LEVEL_ERROR,
        ];

        $frankenphp_level = $levels[strtolower($level)] ?? FRANKENPHP_LOG_LEVEL_INFO;

        // Add WordPress context automatically
        $context = array_merge([
            'site' => defined('DOMAIN_CURRENT_SITE') ? DOMAIN_CURRENT_SITE : ($_SERVER['HTTP_HOST'] ?? 'unknown'),
            'request_uri' => $_SERVER['REQUEST_URI'] ?? '',
            'user_agent' => $_SERVER['HTTP_USER_AGENT'] ?? '',
            'php_version' => PHP_VERSION,
        ], $context);

        // Check if frankenphp_log exists (it should in FrankenPHP 1.11+)
        if (function_exists('frankenphp_log')) {
            frankenphp_log(
                message: $message,
                level: $frankenphp_level,
                context: $context
            );
        } else {
            // Fallback to error_log with JSON formatting
            $log_entry = json_encode([
                'timestamp' => gmdate('Y-m-d\TH:i:s\Z'),
                'level' => strtoupper($level),
                'message' => $message,
                'context' => $context,
            ]);
            error_log($log_entry);
        }
    }
}

if (!class_exists('WPFleet_Logger')) {
    /**
     * Object-oriented interface for WPFleet logging
     */
    class WPFleet_Logger {
        private $default_context = [];

        public function __construct($default_context = []) {
            $this->default_context = $default_context;
        }

        public function debug($message, $context = []) {
            wpfleet_log($message, 'debug', array_merge($this->default_context, $context));
        }

        public function info($message, $context = []) {
            wpfleet_log($message, 'info', array_merge($this->default_context, $context));
        }

        public function warn($message, $context = []) {
            wpfleet_log($message, 'warn', array_merge($this->default_context, $context));
        }

        public function error($message, $context = []) {
            wpfleet_log($message, 'error', array_merge($this->default_context, $context));
        }

        /**
         * Log with exception details
         */
        public function exception($message, $exception, $context = []) {
            $context['exception'] = [
                'class' => get_class($exception),
                'message' => $exception->getMessage(),
                'file' => $exception->getFile(),
                'line' => $exception->getLine(),
                'trace' => $exception->getTraceAsString(),
            ];

            $this->error($message, $context);
        }

        /**
         * Log performance metrics
         */
        public function performance($operation, $duration_ms, $context = []) {
            $context['duration_ms'] = $duration_ms;
            $context['operation'] = $operation;

            $this->info("Performance: {$operation}", $context);
        }
    }
}

// WordPress integration hooks
if (defined('WPINC')) {
    /**
     * Hook into WordPress errors and log them structurally
     */
    add_action('wp_error_added', function($code, $message, $data, $wp_error) {
        wpfleet_log(
            message: "WordPress Error: {$code}",
            level: 'error',
            context: [
                'error_code' => $code,
                'error_message' => $message,
                'error_data' => $data,
            ]
        );
    }, 10, 4);

    /**
     * Log failed login attempts
     */
    add_action('wp_login_failed', function($username) {
        wpfleet_log(
            message: "Failed login attempt",
            level: 'warn',
            context: [
                'username' => $username,
                'ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown',
            ]
        );
    });

    /**
     * Log successful logins
     */
    add_action('wp_login', function($user_login, $user) {
        wpfleet_log(
            message: "User logged in",
            level: 'info',
            context: [
                'user_id' => $user->ID,
                'user_login' => $user_login,
                'ip' => $_SERVER['REMOTE_ADDR'] ?? 'unknown',
            ]
        );
    }, 10, 2);

    /**
     * Log PHP errors and warnings
     */
    if (defined('WPFLEET_LOG_PHP_ERRORS') && WPFLEET_LOG_PHP_ERRORS) {
        set_error_handler(function($errno, $errstr, $errfile, $errline) {
            $level = 'error';
            $error_type = 'PHP Error';

            switch ($errno) {
                case E_WARNING:
                case E_USER_WARNING:
                    $level = 'warn';
                    $error_type = 'PHP Warning';
                    break;
                case E_NOTICE:
                case E_USER_NOTICE:
                    $level = 'info';
                    $error_type = 'PHP Notice';
                    break;
            }

            wpfleet_log(
                message: "{$error_type}: {$errstr}",
                level: $level,
                context: [
                    'file' => $errfile,
                    'line' => $errline,
                    'error_type' => $errno,
                ]
            );

            // Don't interfere with normal error handling
            return false;
        });
    }
}
