# Redis HA template for Rancher

[![Redis Image Layers](https://images.microbadger.com/badges/image/nettoclaudio/rancher-cattle-redis-ha-redis.svg)](https://microbadger.com/images/nettoclaudio/rancher-cattle-redis-ha-redis "Layers of 'nettoclaudio/rancher-cattle-redis-ha-redis:latest'")
[![Redis Sentinel Layers](https://images.microbadger.com/badges/image/nettoclaudio/rancher-cattle-redis-ha-redis-sentinel.svg)](https://microbadger.com/images/nettoclaudio/rancher-cattle-redis-ha-redis-sentinel "Layers of 'nettoclaudio/rancher-cattle-redis-ha-redis-sentinel:latest'")

## Requirements

1. For high-availability reasons, make sure that your [Environment](https://rancher.com/docs/rancher/latest/en/environments/#what-is-an-environment "Read about Rancher Environment") has three [Hosts](https://rancher.com/docs/rancher/latest/en/hosts/ "Read about Rancher Host") at least.

## Installation

Click on **Catalog** > **All** > **Manage** and **Add catalog**:

* Name: any (e.g., "redis-ha")
* URL: https://github.com/nettoclaudio/rancher-cattle-redis-ha.git
* Branch: master

Then click on **Save** button and wait a few minutes.

![Rancher UI - Manage catalogs](media/manage_catalogs.png "Adding a catalog on environment")

Now, back to **Catalog** page and search by "redis ha". Click on **View Details** button on Redis HA template entry.

![Rancher UI - Redis HA template](media/redis-ha_template.png "Redis HA template entry")

Fill in the required fields according to the desired settings and click **Launch**.

![Rancher UI - Redis HA stack](media/redis-ha_launched.png "Redis HA stack launched")