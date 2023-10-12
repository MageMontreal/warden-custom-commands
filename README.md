# Warden Custom commands

Provides additional commands to simplify local installation.

### Installation
Clone this repository in `~/.warden/commands` to install it globally (recommended), or locally per project in `[project directory]/.warden/commands`.

### Configuration
In the project `.env` (after `warden env-init`), add and configure these values:

```
REMOTE_PROD_HOST=project.com
REMOTE_PROD_USER=user
REMOTE_PROD_PORT=22
REMOTE_PROD_PATH=/var/www/html

REMOTE_STAGING_HOST=staging.project.com
REMOTE_STAGING_USER=user
REMOTE_STAGING_PORT=22
REMOTE_STAGING_PATH=/var/www/html

REMOTE_DEV_HOST=dev.project.com
REMOTE_DEV_USER=user
REMOTE_DEV_PORT=22
REMOTE_DEV_PATH=/var/www/html
```

#### Adobe Commerce Cloud
The `REMOTE_[env]_HOST` variables must be set with the name of the environment. All other variables are not used and can be removed.  

Additionally, you must have this variable:  
`CLOUD_PROJECT=[projectId]`

### Usage

For all commands, execute `warden <command> -h` to see the details of all options.

`warden bootstrap`  
* Create and configure warden environment
* Download and import database dump from selected remote
* Download medias from selected remote
* Install composer dependencies
* Configure Redis, Varnish and ElasticSearch if applicable
* Other Magento config like domain, switch some payment methods to sandbox
* Create admin user

`warden db-dump`
* Dump DB from selected remote

`warden import-db`
* Import DB. File **must** be specified with option `--file`

`warden sync-media`
* Download medias from selected remote
* Product images are not downloaded by default (use `--include-product`)

`warden open`
* Open DB tunnel to local or remote environments
* SSH to local or remote environments
* Show SFTP link you can use in your SFTP client
