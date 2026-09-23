<?php
declare(strict_types=1);

if ($argc < 4) {
    fwrite(STDERR, "Usage: verify-dev-composer-lock.php <source-lock> <dev-lock> <local-package>...\n");
    exit(64);
}

$source = json_decode((string) file_get_contents($argv[1]), true, 512, JSON_THROW_ON_ERROR);
$dev = json_decode((string) file_get_contents($argv[2]), true, 512, JSON_THROW_ON_ERROR);
$local = array_fill_keys(array_slice($argv, 3), true);

$index = static function (array $lock): array {
    $result = [];
    foreach (['packages', 'packages-dev'] as $section) {
        foreach ($lock[$section] ?? [] as $package) {
            $name = $package['name'] ?? null;
            if (is_string($name)) {
                $result[$name] = (string) ($package['version'] ?? '');
            }
        }
    }
    ksort($result);
    return $result;
};

$sourcePackages = $index($source);
$devPackages = $index($dev);

foreach ($local as $name => $_) {
    unset($sourcePackages[$name], $devPackages[$name]);
}

if ($sourcePackages !== $devPackages) {
    $names = array_unique(array_merge(array_keys($sourcePackages), array_keys($devPackages)));
    $changed = [];

    foreach ($names as $name) {
        $from = $sourcePackages[$name] ?? '<missing>';
        $to = $devPackages[$name] ?? '<missing>';
        if ($from !== $to) {
            $changed[] = sprintf('%s: %s -> %s', $name, $from, $to);
        }
    }

    fwrite(
        STDERR,
        "Development Composer overlay changed non-local dependencies:\n - "
        . implode("\n - ", $changed)
        . "\n"
    );
    exit(1);
}

echo "Development Composer lock preserves all non-local package versions.\n";
