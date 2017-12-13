#!/bin/bash

# This script provides setup steps needed to build eZ Platform docker containers ready to execute
# functional and acceptance (behat) tests.
#
# Example usage:
# $ ./bin/.travis/trusty/setup_ezplatform.sh ["${DEPENDENCY_PACKAGE_DIR}"]
#
# Required environment variables:
# - ${COMPOSE_FILE}           compose file(s) paths
#
# Arguments:
# - ${DEPENDENCY_PACKAGE_DIR} optional, directory containing existing eZ Platform dependency package

DEPENDENCY_PACKAGE_DIR=$1

# Determine eZ Platform Build dir as relative to current script path
EZPLATFORM_BUILD_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )/../../.." && pwd )"

if [[ -z "${COMPOSE_FILE}" ]]; then
    echo 'Missing environment variable COMPOSE_FILE' >&2
    exit 1
fi

if [[ -n "${DEPENDENCY_PACKAGE_DIR}" ]]; then
    # Get details about dependency package
    DEPENDENCY_PACKAGE_NAME=`php -r "echo json_decode(file_get_contents('${DEPENDENCY_PACKAGE_DIR}/composer.json'))->name;"`

    if [[ -z "${DEPENDENCY_PACKAGE_NAME}" ]]; then
        echo 'Missing composer package name of tested dependency' >&2
        exit 2
    fi
fi

echo '> Preparing eZ Platform container using the following setup:'
echo "- EZPLATFORM_BUILD_DIR=${EZPLATFORM_BUILD_DIR}"
echo "- COMPOSE_FILE=${COMPOSE_FILE}"
if [[ -n "${DEPENDENCY_PACKAGE_NAME}" ]]; then
    echo "- DEPENDENCY_PACKAGE_NAME=${DEPENDENCY_PACKAGE_NAME}"
fi

echo '> Remove XDebug PHP extension'
phpenv config-rm xdebug.ini

echo "> Start docker containers specified by ${COMPOSE_FILE}"
docker-compose up -d
docker-compose exec app sh -c 'chown -R www-data:www-data /var/www'

echo '> Run composer install inside docker app container'
docker-compose exec --user www-data app sh -c 'COMPOSER_HOME=$HOME/.composer composer install --no-suggest --no-progress --no-interaction --prefer-dist --optimize-autoloader'

# Handle dependency if needed
if [[ -n "${DEPENDENCY_PACKAGE_NAME}" ]]; then
    # check if dependency exists for current meta-package version
    if [[ ! -d "./vendor/${DEPENDENCY_PACKAGE_NAME}" ]]; then
        echo "Testing dependency failed: package ${DEPENDENCY_PACKAGE_NAME} does not exist" >&2
        exit 3
    fi

    echo "> Overwrite ./vendor/${DEPENDENCY_PACKAGE_NAME} with ${DEPENDENCY_PACKAGE_DIR}"
    if ! (sudo rm -rf "./vendor/${DEPENDENCY_PACKAGE_NAME}" && sudo mv ${DEPENDENCY_PACKAGE_DIR} "./vendor/${DEPENDENCY_PACKAGE_NAME}"); then
        echo 'Overwrite failed' >&2
        exit 4
    fi

    echo '> Clear Symfony cache inside docker app container'
    docker-compose exec --user www-data app sh -c 'php ./bin/console cache:clear --no-warmup && php ./bin/console cache:warmup'
fi

echo '> Install data'
docker-compose exec --user www-data app sh -c "php /scripts/wait_for_db.php; php bin/console ezplatform:install ${INSTALL_EZ_INSTALL_TYPE}"

echo '> Done, ready to run tests'
