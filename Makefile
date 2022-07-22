DOCKER_RUN     := @docker run --rm
COMPOSER_IMAGE := -v "$$(pwd):/app" --user $$(id -u):$$(id -g) composer
NODE_IMAGE     := -w /home/node/app -v "$$(pwd):/home/node/app" --user node node:lts
HIGHLIGHT      :=\033[0;32m
END_HIGHLIGHT  :=\033[0m # No Color

.PHONY: build
build: build-pot-file  ## Generates a .pot file for use in translations.

.PHONY: clean
clean:
	@echo "Cleaning up build-artifacts"
	rm -rf \
		wordpress

.PHONY: destroy
destroy: ## Destroys the developer environment completely (this is irreversible)
	docker compose down
	docker compose down --volumes
	docker compose down --rmi
	$(MAKE) clean

.PHONY: flush-cache
flush-cache: ## Clears all server caches enabled within WordPress
	@echo "Flushing cache"
	lando wp cache flush --path=./wordpress

.PHONY: delete-transients
delete-transients: ## Deletes all WordPress transients stored in the database
	@echo "Deleting transients"
	lando wp transient delete --path=./wordpress --all

.PHONY: help
help:  ## Display help
	@awk -F ':|##' \
		'/^[^\t].+?:.*?##/ {\
			printf "\033[36m%-30s\033[0m %s\n", $$1, $$NF \
		}' $(MAKEFILE_LIST) | sort


.PHONY: dc-start
dc-start:
	if [ ! "$$(docker ps | grep cfa_appserver)" ]; then \
		echo "Running Docker Compose"; \
		docker compose up; \
	fi
	if [ ! -f ./wordpress/wp-config.php ]; then \
		$(MAKE) setup-wordpress; \
		$(MAKE) setup-wordpress-wps; \
		echo "Your dev site is at: ${HIGHLIGHT}https://cfa.lndo.site${END_HIGHLIGHT}"; \
		echo "See the readme for further details."; \
	fi
	if [ ! -d ./r2-cfa/.git ]; then \
		$(MAKE) download-repo; \
	fi

.PHONY: dc-stop
dc-stop:
	if [ "$$(docker ps | grep cfa_appserver)" ]; then \
		echo "Stopping..."; \
		docker compose stop; \
	fi

.PHONY: open
open: ## Open the development site in your default browser
	open https://cfa.lndo.site

.PHONY: open-db
open-db: ## Open the database in TablePlus
	@echo "Opening the database for direct access"
	open mysql://wordpress:wordpress@127.0.0.1:$$(lando info --service=database --path 0.external_connection.port | tr -d "'")/wordpress?enviroment=local&name=$database&safeModeLevel=0&advancedSafeModeLevel=0

.PHONY: open-site
open-site: open

.PHONY: reset
reset: destroy start ## Resets a running dev environment to new

.PHONY: setup-wordpress
setup-wordpress:
	@echo "Setting up WordPress"
	lando wp core download --path=./wordpress --version=5.4.2 --insecure
	lando wp config create --dbname=wordpress --dbuser=wordpress --dbpass=wordpress --dbhost=database --path=./wordpress
	lando wp core install --path=./wordpress --url=https://cfa.lndo.site --title="cfa Development" --admin_user=admin --admin_password=password --admin_email=nota@realemail.no
	cp -f ./wp-config.copy ./wordpress/wp-config.php

.PHONY: setup-wordpress-wps
setup-wordpress-wps:
	@echo "Adding BU Plugins and Themes"
	if [ ! -d ./wordpress/mu-plugins ]; then \
		./bu-repos.sh; \
	fi
	rsync -avzrP ../bu-repos/mu-plugins/ ./wordpress/wp-content/mu-plugins/;
	rsync -avzrP ../bu-repos/plugins/ ./wordpress/wp-content/plugins/;
	rsync -avzrP ../bu-repos/themes/ ./wordpress/wp-content/themes/;
	@echo "Bouncing Lando"
	lando stop
	lando start
	@echo "Activating Plugins"
	lando wp plugin install safe-redirect-manager --activate --path=./wordpress
	lando wp plugin install regenerate-thumbnails --activate --path=./wordpress
	lando wp plugin install classic-editor --activate --path=./wordpress
	lando wp plugin install wordpress-importer --activate --path=./wordpress
	lando wp plugin install query-monitor --activate --path=./wordpress
	lando wp plugin install cmb2 --activate --path=./wordpress
	lando wp plugin activate --path=./wordpress gravityforms
	lando wp plugin activate --path=./wordpress bu-banners
	lando wp plugin activate --path=./wordpress course-feeds
	lando wp plugin activate --path=./wordpress bu-external-permalinks
	lando wp plugin activate --path=./wordpress bu-front-end-library
	lando wp plugin activate --path=./wordpress bu-landing-pages
	lando wp plugin activate --path=./wordpress bu-profiles
	lando wp plugin activate --path=./wordpress bu-post-details
	lando wp plugin activate --path=./wordpress bu-sharing
	lando wp plugin activate --path=./wordpress bu-slideshow
	lando wp plugin activate --path=./wordpress bu-taxonomies

.PHONY: download-repo
download-repo:
	git clone git@github.com:bu-ist/r2-cfa.git ./r2-cfa

.PHONY: start
start: lando-start ## Starts the development environment including downloading and setting up everything it needs

.PHONY: stop
stop: lando-stop ## Stops the development environment. This is non-destructive.

.PHONY: test
test: test-lint test-phpunit  ## Run all testing

.PHONY: test-lint
test-lint: test-lint-php test-lint-javascript ## Run linting on both PHP and JavaScript

.PHONY: test-lint-javascript
test-lint-javascript: ## Run linting on JavaScript only
	@echo "Running JavaScript linting"
	$(DOCKER_RUN) $(NODE_IMAGE) npm run lint

.PHONY: lint
lint: ## Run linting on PHP only
	if [ ! command -v watchexec ]; then \
		echo "Installing watchexec"; \
		brew install watchexec; \
	fi
	watchexec --clear --on-busy-update=do-nothing --exts=php,js --watch=./r2-cfa ./linter.sh

.PHONY: test-phpunit
test-phpunit: ## Run PhpUnit
	@echo "Running Unit Tests Without Coverage"
	docker run \
		-v "$$(pwd):/app" \
		--workdir /app \
		--rm \
		php:7.4-cli \
		/app/vendor/bin/phpunit

.PHONY: trust-lando-cert-mac
trust-lando-cert-mac: ## Trust Lando's SSL certificate on your mac
	@echo "Trusting Lando cert"
	sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/.lando/certs/lndo.site.pem

.PHONY: update-composer
update-composer:
	$(DOCKER_RUN) $(COMPOSER_IMAGE) update

.PHONY: update-npm
update-npm:
	$(DOCKER_RUN) $(NODE_IMAGE) npm update
