<?php
declare(strict_types=1);

function normalizeRepositoryBasename(string $url): string
{
    $url = preg_replace('~^git@github\.com:~', 'https://github.com/', trim($url)) ?? trim($url);
    $path = parse_url($url, PHP_URL_PATH);

    if (!is_string($path) || $path === '') {
        return '';
    }

    return preg_replace('/\.git$/', '', basename($path)) ?? '';
}

function generateDevComposer(string $appDir, string $bundlesDir): array
{
    $sourcePath = rtrim($appDir, '/') . '/composer.json';
    $targetPath = rtrim($appDir, '/') . '/composer.dev.json';

    $source = json_decode((string) file_get_contents($sourcePath), true, 512, JSON_THROW_ON_ERROR);
    if (!is_array($source)) {
        throw new RuntimeException('Application composer.json is invalid.');
    }

    $versions = [];
    $bundleBasenames = [];

    foreach (glob(rtrim($bundlesDir, '/') . '/*', GLOB_ONLYDIR) ?: [] as $bundleDir) {
        $composerPath = $bundleDir . '/composer.json';
        if (!is_file($composerPath)) {
            continue;
        }

        $bundle = json_decode((string) file_get_contents($composerPath), true, 512, JSON_THROW_ON_ERROR);
        $name = $bundle['name'] ?? null;

        if (!is_string($name) || $name === '') {
            throw new RuntimeException(sprintf('Bundle composer.json has no package name: %s', $composerPath));
        }

        $versions[$name] = 'dev-main';
        $bundleBasenames[basename($bundleDir)] = true;
    }

    if ($versions === []) {
        throw new RuntimeException('No local Pimcore bundles were found.');
    }

    ksort($versions);

    $repositories = [];
    foreach ($source['repositories'] ?? [] as $repository) {
        if (
            is_array($repository)
            && ($repository['type'] ?? null) === 'vcs'
            && is_string($repository['url'] ?? null)
            && isset($bundleBasenames[normalizeRepositoryBasename($repository['url'])])
        ) {
            continue;
        }

        $repositories[] = $repository;
    }

    array_unshift($repositories, [
        'type' => 'path',
        'url' => rtrim($bundlesDir, '/') . '/*',
        'options' => [
            'symlink' => true,
            'reference' => 'config',
            'versions' => $versions,
        ],
    ]);

    $source['repositories'] = $repositories;

    $json = json_encode(
        $source,
        JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR
    );

    if (file_put_contents($targetPath, $json . "\n") === false) {
        throw new RuntimeException('Could not write composer.dev.json.');
    }

    return array_keys($versions);
}

if (realpath($_SERVER['SCRIPT_FILENAME'] ?? '') === __FILE__) {
    try {
        $packages = generateDevComposer(
            $argv[1] ?? '/var/www/html',
            $argv[2] ?? '/var/www/bundles'
        );

        echo json_encode($packages, JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR), "\n";
    } catch (Throwable $error) {
        fwrite(STDERR, 'Dev Composer generation failed: ' . $error->getMessage() . "\n");
        exit(1);
    }
}
