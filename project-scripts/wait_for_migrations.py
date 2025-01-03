#!/usr/bin/env python
from time import sleep

import click
import aerospike


def wait_for_migrations(client, check_interval=10):
    while True:
        migrations_in_progress = 0

        # Fetch cluster nodes
        nodes = client.get_node_names()

        # Iterate over each node
        for node in nodes:
            # Get migration statistics for the namespace
            stats_str = client.info_single_node(f'statistics', node['node_name'])

            stats = stats_str.split(';')

            migrate_partitions_remaining_on_node = None
            for stat in stats:
                if 'migrate_partitions_remaining' in stat:
                    migrate_partitions_remaining_on_node = int(stat.split('=')[1])

            if migrate_partitions_remaining_on_node is None:
                raise ValueError("migrations statistics are not available")

            # Check if migrations are in progress
            if migrate_partitions_remaining_on_node > 0:
                migrations_in_progress += migrate_partitions_remaining_on_node

        if migrations_in_progress > 0:
            print(f"migrations remaining: {migrations_in_progress}")
        else:
            print("all migrations are complete")
            break

        # Wait before the next check
        sleep(check_interval)


@click.command()
@click.option('--hostname', required=True, help='Set the cluster seed hostname')
@click.option('--port', default=3000, help='Set the cluster seed hostname')
def main(hostname, port):
    """This script waits for partition migrations to complete on an aerospike cluster"""
    config = {'hosts': [(hostname, port)]}
    client = aerospike.client(config).connect()

    print(f"checking for migrations on {hostname}")
    wait_for_migrations(client)


if __name__ == "__main__":
    main()
