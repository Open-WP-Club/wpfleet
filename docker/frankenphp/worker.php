<?php
/**
 * FrankenPHP Worker Script for WordPress
 *
 * This worker script keeps WordPress loaded in memory for maximum performance.
 * It uses FrankenPHP's worker mode with structured logging for better observability.
 *
 * @package WPFleet
 * @version 1.0.0
 */

// Worker initialization with structured logging
if (function_exists('frankenphp_log')) {
    frankenphp_log(
        message: "FrankenPHP worker initializing",
        level: FRANKENPHP_LOG_LEVEL_INFO,
        context: [
            'php_version' => PHP_VERSION,
            'worker_pid' => getmypid(),
            'memory_limit' => ini_get('memory_limit'),
            'opcache_enabled' => function_exists('opcache_get_status') && opcache_get_status() !== false,
        ]
    );
}

// Set up error handling for worker
set_error_handler(function($errno, $errstr, $errfile, $errline) {
    if (function_exists('frankenphp_log')) {
        $level = FRANKENPHP_LOG_LEVEL_ERROR;
        if ($errno === E_WARNING || $errno === E_USER_WARNING) {
            $level = FRANKENPHP_LOG_LEVEL_WARN;
        } elseif ($errno === E_NOTICE || $errno === E_USER_NOTICE) {
            $level = FRANKENPHP_LOG_LEVEL_DEBUG;
        }

        frankenphp_log(
            message: "PHP Error in worker: {$errstr}",
            level: $level,
            context: [
                'file' => $errfile,
                'line' => $errline,
                'type' => $errno,
            ]
        );
    }
    return false;
});

// Track worker statistics
$worker_stats = [
    'requests_handled' => 0,
    'start_time' => microtime(true),
    'memory_peak' => 0,
];

// Main worker loop
while ($request = frankenphp_handle_request(function() use (&$worker_stats) {
    $request_start = microtime(true);
    $worker_stats['requests_handled']++;

    // Load WordPress with structured logging
    try {
        // Check if WordPress is installed
        $wp_load = $_SERVER['DOCUMENT_ROOT'] . '/wp-load.php';

        if (!file_exists($wp_load)) {
            if (function_exists('frankenphp_log')) {
                frankenphp_log(
                    message: "WordPress not found",
                    level: FRANKENPHP_LOG_LEVEL_WARN,
                    context: [
                        'document_root' => $_SERVER['DOCUMENT_ROOT'],
                        'wp_load_path' => $wp_load,
                    ]
                );
            }

            // Serve a helpful message
            http_response_code(503);
            echo "<!DOCTYPE html><html><head><title>WordPress Not Installed</title></head><body>";
            echo "<h1>WordPress Not Installed</h1>";
            echo "<p>Please install WordPress in the document root.</p>";
            echo "</body></html>";
            return;
        }

        // Load WordPress
        require_once $wp_load;

        // Log request completion with performance metrics
        $request_duration = (microtime(true) - $request_start) * 1000; // Convert to ms
        $memory_used = memory_get_peak_usage(true);
        $worker_stats['memory_peak'] = max($worker_stats['memory_peak'], $memory_used);

        if (function_exists('frankenphp_log')) {
            frankenphp_log(
                message: "Request completed",
                level: FRANKENPHP_LOG_LEVEL_INFO,
                context: [
                    'duration_ms' => round($request_duration, 2),
                    'memory_mb' => round($memory_used / 1024 / 1024, 2),
                    'uri' => $_SERVER['REQUEST_URI'] ?? 'unknown',
                    'method' => $_SERVER['REQUEST_METHOD'] ?? 'unknown',
                    'status' => http_response_code(),
                    'requests_total' => $worker_stats['requests_handled'],
                    'worker_uptime_seconds' => round(microtime(true) - $worker_stats['start_time']),
                ]
            );
        }

    } catch (Throwable $e) {
        // Log exceptions with full context
        if (function_exists('frankenphp_log')) {
            frankenphp_log(
                message: "Worker exception: {$e->getMessage()}",
                level: FRANKENPHP_LOG_LEVEL_ERROR,
                context: [
                    'exception_class' => get_class($e),
                    'file' => $e->getFile(),
                    'line' => $e->getLine(),
                    'trace' => $e->getTraceAsString(),
                ]
            );
        }

        http_response_code(500);
        echo "Internal Server Error";
    }

    // Clean up after each request
    if (function_exists('wp_cache_flush')) {
        wp_cache_flush();
    }
})) {
    // Optional: Log worker health metrics periodically
    if ($worker_stats['requests_handled'] % 100 === 0) {
        if (function_exists('frankenphp_log')) {
            frankenphp_log(
                message: "Worker health check",
                level: FRANKENPHP_LOG_LEVEL_INFO,
                context: [
                    'requests_handled' => $worker_stats['requests_handled'],
                    'uptime_seconds' => round(microtime(true) - $worker_stats['start_time']),
                    'memory_peak_mb' => round($worker_stats['memory_peak'] / 1024 / 1024, 2),
                    'memory_current_mb' => round(memory_get_usage(true) / 1024 / 1024, 2),
                ]
            );
        }
    }

    // Check if worker should restart (memory threshold)
    $max_memory = getenv('FRANKENPHP_WORKER_MAX_MEMORY') ?: 512 * 1024 * 1024; // 512MB default
    if (memory_get_usage(true) > $max_memory) {
        if (function_exists('frankenphp_log')) {
            frankenphp_log(
                message: "Worker restarting due to memory threshold",
                level: FRANKENPHP_LOG_LEVEL_WARN,
                context: [
                    'memory_used_mb' => round(memory_get_usage(true) / 1024 / 1024, 2),
                    'memory_limit_mb' => round($max_memory / 1024 / 1024, 2),
                    'requests_handled' => $worker_stats['requests_handled'],
                ]
            );
        }
        break;
    }
}

// Worker shutdown logging
if (function_exists('frankenphp_log')) {
    frankenphp_log(
        message: "FrankenPHP worker shutting down",
        level: FRANKENPHP_LOG_LEVEL_INFO,
        context: [
            'total_requests' => $worker_stats['requests_handled'],
            'uptime_seconds' => round(microtime(true) - $worker_stats['start_time']),
            'memory_peak_mb' => round($worker_stats['memory_peak'] / 1024 / 1024, 2),
        ]
    );
}
