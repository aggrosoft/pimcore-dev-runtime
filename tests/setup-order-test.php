<?php

declare(strict_types=1);

$setup = file_get_contents(__DIR__ . '/../scripts/setup.sh');

if ($setup === false) {
    fwrite(STDERR, "Could not read scripts/setup.sh\n");
    exit(1);
}

$position = static function (string $needle) use ($setup): int {
    $position = strpos($setup, $needle);

    if ($position === false) {
        fwrite(STDERR, sprintf("Missing expected setup step: %s\n", $needle));
        exit(1);
    }

    return $position;
};

$coreInstall = $position('vendor/bin/pimcore-install');
$repair = $position('repair-bundle-installers.php');
$dataHubInstall = $position('install_bundle PimcoreDataHubBundle');
$dataImporterInstall = $position('install_bundle PimcoreDataImporterBundle');
$lastApplicationBundleInstall = $position('install_bundle AggrosoftPimcoreAgentBundle');
$migrations = $position('run_console doctrine:migrations:migrate --no-interaction');

if (!($coreInstall < $repair)) {
    fwrite(STDERR, "Legacy repair must run after the Pimcore core installation block.\n");
    exit(1);
}

if (!($repair < $dataHubInstall && $dataHubInstall < $dataImporterInstall)) {
    fwrite(STDERR, "DataHub and Data Importer installers are in the wrong order.\n");
    exit(1);
}

if (!($dataImporterInstall < $lastApplicationBundleInstall && $lastApplicationBundleInstall < $migrations)) {
    fwrite(STDERR, "All application bundle installers must run before Doctrine migrations.\n");
    exit(1);
}

if (substr_count($setup, 'doctrine:migrations:migrate') !== 1) {
    fwrite(STDERR, "Expected exactly one global Doctrine migration pass.\n");
    exit(1);
}

fwrite(STDOUT, "setup order ok\n");
