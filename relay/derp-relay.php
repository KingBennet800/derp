<?php
/* Derp's pairing relay: it passes encrypted snapshots between paired Derps.
 *
 * Paired Derps share a secret that never leaves them (it travels from the
 * computer to the phone in a QR code). From it each derives a box name, a
 * write token and an encryption key. The relay only ever sees the box name,
 * a hash of the write token, and encrypted bytes: each device keeps one slot
 * in its box (its bookmarks, passwords and open tabs, encrypted with
 * AES-256-GCM on the device), reads the others' slots, and merges them itself.
 *
 *   GET  (X-Derp-Box)                             every slot in the box, as JSON
 *   POST (X-Derp-Box, X-Derp-Token, X-Derp-Device) body: this device's slot
 *   POST (… and X-Derp-Delete: 1)                 removes this device's slot
 *
 * Names and tokens go in headers, so they stay out of the server's logs.
 * Slots nobody updates for 120 days go away. Lives at
 * bennettholland.com/derp-relay.php; data is kept outside public_html. */
declare(strict_types=1);

// Room for thousands of bookmarks and passwords per device, with a ceiling
// on the whole (about 3 GB at worst) so nobody can fill the server.
const MAX_SLOT = 524288;    // bytes per device
const MAX_DEVICES = 6;      // per box
const MAX_BOXES = 1000;
const NEW_BOXES = 5;        // new boxes per address per day
const KEEP_DAYS = 120;
const RATE = 300;           // requests per address per 10 minutes

header('Content-Type: application/json');
header('Cache-Control: no-store');
header('X-Content-Type-Options: nosniff');
header('Referrer-Policy: no-referrer');

function done(int $code, ?array $body = null): void
{
    http_response_code($code);
    if ($body !== null) {
        echo json_encode($body);
    }
    exit;
}

function in_window(string $file, int $window): bool
{
    return substr($file, -strlen(".$window")) === ".$window";
}

function slots(string $dir): array
{
    $files = glob("$dir/*.bin");
    return $files === false ? [] : $files;
}

$root = dirname(__DIR__) . '/derp-relay';
foreach (['boxes', 'rate'] as $folder) {
    if (!is_dir("$root/$folder") && !@mkdir("$root/$folder", 0700, true) && !is_dir("$root/$folder")) {
        done(500, ['error' => 'storage']);
    }
}

$method = $_SERVER['REQUEST_METHOD'] ?? 'GET';
$box = strtolower($_SERVER['HTTP_X_DERP_BOX'] ?? '');
if ($method === 'GET' && $box === '') {
    done(200, ['relay' => 'derp', 'version' => 1]);
}
if (!preg_match('/^[0-9a-f]{64}$/', $box)) {
    done(400, ['error' => 'box']);
}

// A gentle limit per address (hashed, never stored as is), in 10-minute windows.
$window = intdiv(time(), 600);
$who = substr(hash('sha256', ($_SERVER['REMOTE_ADDR'] ?? '') . '|derp-relay'), 0, 32);
$rate = "$root/rate/$who.$window";
$count = (int)@file_get_contents($rate) + 1;
@file_put_contents($rate, (string)$count, LOCK_EX);
if ($count > RATE) {
    done(429, ['error' => 'slow down']);
}

// Now and then, sweep: old rate counters, slots nobody updates, empty boxes.
if (random_int(1, 50) === 1) {
    foreach (glob("$root/rate/*") ?: [] as $file) {
        if (!in_window($file, $window) && !in_window($file, intdiv(time(), 86400))) {
            @unlink($file);
        }
    }
    $old = time() - KEEP_DAYS * 86400;
    foreach (glob("$root/boxes/*", GLOB_ONLYDIR) ?: [] as $dir) {
        foreach (slots($dir) as $file) {
            if (filemtime($file) < $old) {
                @unlink($file);
            }
        }
        if (!slots($dir)) {
            @unlink("$dir/token");
            @rmdir($dir);
        }
    }
}

$dir = "$root/boxes/$box";

if ($method === 'GET') {
    $slots = [];
    foreach (slots($dir) as $file) {
        $slots[basename($file, '.bin')] = ['at' => filemtime($file), 'data' => base64_encode((string)file_get_contents($file))];
    }
    ksort($slots);
    $etag = '"' . hash('sha256', json_encode($slots)) . '"';
    header("ETag: $etag");
    if (trim($_SERVER['HTTP_IF_NONE_MATCH'] ?? '') === $etag) {
        done(304);
    }
    done(200, ['slots' => (object)$slots]);
}

if ($method !== 'POST') {
    done(405, ['error' => 'method']);
}
$device = strtolower($_SERVER['HTTP_X_DERP_DEVICE'] ?? '');
$token = strtolower($_SERVER['HTTP_X_DERP_TOKEN'] ?? '');
if (!preg_match('/^[0-9a-f]{32}$/', $device) || !preg_match('/^[0-9a-f]{64}$/', $token)) {
    done(400, ['error' => 'device or token']);
}
$leaving = ($_SERVER['HTTP_X_DERP_DELETE'] ?? '') === '1';

// The first write to a box sets its token; every later write must match it.
if (!is_dir($dir)) {
    if ($leaving) {
        done(204);
    }
    if (count(glob("$root/boxes/*", GLOB_ONLYDIR) ?: []) >= MAX_BOXES) {
        done(507, ['error' => 'full']);
    }
    $today = "$root/rate/new-$who." . intdiv(time(), 86400);
    $made = (int)@file_get_contents($today) + 1;
    @file_put_contents($today, (string)$made, LOCK_EX);
    if ($made > NEW_BOXES) {
        done(429, ['error' => 'too many new boxes today']);
    }
    if (!@mkdir($dir, 0700) && !is_dir($dir)) {
        done(500, ['error' => 'storage']);
    }
    $new = @fopen("$dir/token", 'x');
    if ($new !== false) {
        fwrite($new, hash('sha256', $token));
        fclose($new);
    }
}
if (!hash_equals((string)@file_get_contents("$dir/token"), hash('sha256', $token))) {
    done(403, ['error' => 'token']);
}

if ($leaving) {
    @unlink("$dir/$device.bin");
    if (!slots($dir)) {
        @unlink("$dir/token");
        @rmdir($dir);
    }
    done(204);
}

$body = file_get_contents('php://input', false, null, 0, MAX_SLOT + 1);
if ($body === false || $body === '' || strlen($body) > MAX_SLOT) {
    done(413, ['error' => 'size']);
}
if (!file_exists("$dir/$device.bin") && count(slots($dir)) >= MAX_DEVICES) {
    done(409, ['error' => 'too many devices']);
}
$temp = "$dir/$device.tmp";
if (@file_put_contents($temp, $body, LOCK_EX) === false || !@rename($temp, "$dir/$device.bin")) {
    done(500, ['error' => 'storage']);
}
done(204);
