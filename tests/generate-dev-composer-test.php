<?php
declare(strict_types=1);

require __DIR__ . '/../scripts/generate-dev-composer.php';

$root = sys_get_temp_dir() . '/pimcore-dev-composer-' . bin2hex(random_bytes(6));
$app = $root . '/app';
$bundles = $root . '/bundles';

mkdir($app, 0777, true);
mkdir($bundles . '/pimcore-data-bundle', 0777, true);
mkdir($bundles . '/pimcore-agent-bundle', 0777, true);

file_put_contents($app . '/composer.json', json_encode([
    'name' => 'test/app',
    'require' => [
        'aggrosoft/pimcore-data-bundle' => 'dev-main',
        'aggrosoft/pimcore-agent-bundle' => 'dev-main',
    ],
    'repositories' => [
        ['name' => 'data', 'type' => 'vcs', 'url' => 'https://github.com/aggrosoft/pimcore-data-bundle.git'],
        ['name' => 'agent', 'type' => 'vcs', 'url' => 'https://github.com/aggrosoft/pimcore-agent-bundle.git'],
        ['type' => 'composer', 'url' => 'https://repo.example.invalid'],
    ],
], JSON_THROW_ON_ERROR));

file_put_contents($bundles . '/pimcore-data-bundle/composer.json', json_encode([
    'name' => 'aggrosoft/pimcore-data-bundle',
], JSON_THROW_ON_ERROR));

file_put_contents($bundles . '/pimcore-agent-bundle/composer.json', json_encode([
    'name' => 'aggrosoft/pimcore-agent-bundle',
], JSON_THROW_ON_ERROR));

$packages = generateDevComposer($app, $bundles);
sort($packages);

$expected = [
    'aggrosoft/pimcore-agent-bundle',
    'aggrosoft/pimcore-data-bundle',
];

if ($packages !== $expected) {
    throw new RuntimeException('Unexpected local package list.');
}

$generated = json_decode(
    (string) file_get_contents($app . '/composer.dev.json'),
    true,
    512,
    JSON_THROW_ON_ERROR
);

$pathRepo = $generated['repositories'][0] ?? null;
if (($pathRepo['type'] ?? null) !== 'path') {
    throw new RuntimeException('Path repository is not first.');
}
if (($pathRepo['url'] ?? null) !== $bundles . '/*') {
    throw new RuntimeException('Wrong path repository URL.');
}
if (($pathRepo['options']['symlink'] ?? null) !== true) {
    throw new RuntimeException('Path repository does not force symlinks.');
}
if (($pathRepo['options']['reference'] ?? null) !== 'config') {
    throw new RuntimeException('Path repository does not use stable config references.');
}
foreach ($expected as $package) {
    if (($pathRepo['options']['versions'][$package] ?? null) !== 'dev-main') {
        throw new RuntimeException('Local package version is not pinned to dev-main.');
    }
}

foreach ($generated['repositories'] as $repo) {
    if (($repo['type'] ?? null) === 'vcs') {
        throw new RuntimeException('Local GitHub VCS repository leaked into dev composer config.');
    }
}

if (($generated['repositories'][1]['type'] ?? null) !== 'composer') {
    throw new RuntimeException('Unrelated repositories were not preserved.');
}

echo "Dev Composer generation tests: OK\n";
