#!/usr/bin/env php
<?php

declare(strict_types=1);

use Pimcore\Bootstrap;
use Pimcore\Bundle\ApplicationLoggerBundle\Installer as ApplicationLoggerInstaller;
use Pimcore\Bundle\DataHubBundle\Installer as DataHubInstaller;
use Pimcore\Bundle\DataImporterBundle\Installer as DataImporterInstaller;
use Pimcore\Cache;
use Pimcore\Db;
use Pimcore\Model\User\Permission\Definition;

$autoload = getcwd() . '/vendor/autoload.php';

if (!is_file($autoload)) {
    fwrite(STDERR, "Run this repair from the Pimcore project root.\n");
    exit(1);
}

require $autoload;

if (!defined('PIMCORE_CONSOLE')) {
    define('PIMCORE_CONSOLE', true);
}

Bootstrap::setProjectRoot();
$kernel = Bootstrap::startupCli();

try {
    $container = $kernel->getContainer();
    $repairedBundles = [];

    /** @var DataHubInstaller $dataHubInstaller */
    $dataHubInstaller = $container->get(DataHubInstaller::class);

    if ($dataHubInstaller->isInstalled() && dataHubInstallerArtifactsMissing()) {
        fwrite(STDOUT, "Repairing PimcoreDataHubBundle installer state\n");
        $dataHubInstaller->install();
        $repairedBundles[] = 'PimcoreDataHubBundle';
    }

    /** @var DataImporterInstaller $dataImporterInstaller */
    $dataImporterInstaller = $container->get(DataImporterInstaller::class);
    /** @var ApplicationLoggerInstaller $applicationLoggerInstaller */
    $applicationLoggerInstaller = $container->get(ApplicationLoggerInstaller::class);

    $dataImporterPermissionMissing =
        Definition::getByKey(DataImporterInstaller::DATAHUB_ADAPTER_PERMISSION) === null;

    if (
        $dataImporterInstaller->isInstalled()
        && ($dataImporterPermissionMissing || !$applicationLoggerInstaller->isInstalled())
    ) {
        fwrite(STDOUT, "Repairing PimcoreDataImporterBundle installer state\n");
        $dataImporterInstaller->install();
        $repairedBundles[] = 'PimcoreDataImporterBundle';
    }

    if ($repairedBundles !== []) {
        Cache::remove('studio_backend_user_permissions');
        fwrite(
            STDOUT,
            sprintf(
                "Repaired bundle installer state: %s; cleared studio_backend_user_permissions\n",
                implode(', ', $repairedBundles)
            )
        );
    } else {
        fwrite(STDOUT, "Bundle installer state is consistent; no repair required\n");
    }
} finally {
    $kernel->shutdown();
}

function dataHubInstallerArtifactsMissing(): bool
{
    if (Definition::getByKey(DataHubInstaller::CONFIG_NAME) === null) {
        return true;
    }

    $db = Db::get();

    foreach (['document', 'asset', 'object'] as $type) {
        $table = 'plugin_datahub_workspaces_' . $type;
        $exists = (int) $db->fetchOne(
            'SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?',
            [$table]
        );

        if ($exists === 0) {
            return true;
        }
    }

    return false;
}
