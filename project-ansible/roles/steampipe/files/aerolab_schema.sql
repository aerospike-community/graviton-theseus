-- TODO: replace this command with whatever makes most sense for the particular instance (file, aerolab command, etc)
CREATE TABLE IF NOT EXISTS aerolab_inventory AS
SELECT
    stdout_output AS inventory,
    (
        SELECT CASE
                   WHEN EXISTS (
                                  SELECT 1
                                  FROM exec_command
                                  WHERE stdout_output like '%Config.Backend.Type = gcp%'
                                            AND command = 'aerolab config backend'
                              ) THEN 'gcp'
                   WHEN EXISTS (
                                  SELECT 1
                                  FROM exec_command
                                  WHERE stdout_output like '%Config.Backend.Type = aws%'
                                            AND command = 'aerolab config backend'
                              ) THEN 'aws'
                   ELSE 'Unknown'
               END
    ) AS cloud
FROM
    exec_command
WHERE
    command = 'aerolab inventory list -j';

CREATE VIEW IF NOT EXISTS aerolab_instance_impl AS
SELECT json_extract(cluster.value, '$.InstanceId') AS instance_id,
       json_extract(cluster.value, '$.ClusterName') AS cluster_name,
       'aerospike' AS cluster_type,
       json_extract(cluster.value, '$.ClusterName') || '-' || json_extract(cluster.value, '$.NodeNo') AS node_name,
       CAST(json_extract(cluster.value, '$.NodeNo') AS INT) AS node_no,
       inventory.cloud,
       json_extract(cluster.value, '$.State') AS state,
       json_extract(cluster.value, '$.Expires') AS expires,
       json_extract(cluster.value, '$.PublicIp') AS public_ip,
       json_extract(cluster.value, '$.PrivateIp') AS private_ip,
       json_extract(cluster.value, '$.Owner') AS owner,
       json_extract(cluster.value, '$.AerospikeVersion') AS aerospike_version,
       json_extract(cluster.value, '$.InstanceRunningCost') AS instance_running_cost,
       json_extract(cluster.value, '$.Firewalls') AS firewalls,
       json_extract(cluster.value, '$.Arch') AS arch,
       json_extract(cluster.value, '$.Distribution') AS distribution,
       json_extract(cluster.value, '$.OSVersion') AS os_version,
       json_extract(cluster.value, '$.Zone') AS zone,
       json_extract(cluster.value, '$.ImageId') AS image_id,
       json_extract(cluster.value, '$.InstanceType') AS instance_type,
       json_extract(cluster.value, '$.DockerExposePorts') AS docker_expose_ports,
       json_extract(cluster.value, '$.DockerInternalPort') AS docker_internal_port,
       json_extract(cluster.value, '$.AwsIsSpot') AS aws_is_spot,
       json_extract(cluster.value, '$.GcpIsSpot') AS gcp_is_spot,
       json_extract(cluster.value, '$.AccessUrl') AS access_url,
       json_extract(cluster.value, '$.IsRunning') AS is_running,
       CASE
           WHEN inventory.cloud = 'aws' THEN 'aerolab-' || json_extract(cluster.value, '$.ClusterName') || '_' || json_extract(cluster.value, '$.Zone')
           WHEN inventory.cloud = 'gcp' THEN 'aerolab-gcp-' || json_extract(cluster.value, '$.ClusterName')
       END AS ssh_key,
       CASE
           WHEN inventory.cloud = 'aws' THEN json_extract(cluster.value, '$.AwsTags.project')
           WHEN inventory.cloud = 'gcp' THEN json_extract(cluster.value, '$.GcpLabels.project')
       END AS project,
       CASE
           WHEN inventory.cloud = 'aws' THEN json_extract(cluster.value, '$.AwsTags')
           WHEN inventory.cloud = 'gcp' THEN json_extract(cluster.value, '$.GcpLabels')
       END AS tags
FROM aerolab_inventory inventory,
     json_each(json_extract(inventory, '$.Clusters')) AS cluster
UNION ALL
SELECT json_extract(client.value, '$.InstanceId') AS instance_id,
       json_extract(client.value, '$.ClientName') AS cluster_name,
       json_extract(client.value, '$.ClientType') AS cluster_type,
       json_extract(client.value, '$.ClientName') || '-' || json_extract(client.value, '$.NodeNo') AS node_name,
       CAST(json_extract(client.value, '$.NodeNo') AS INT) AS node_no,
       inventory.cloud,
       json_extract(client.value, '$.State') AS state,
       json_extract(client.value, '$.Expires') AS expires,
       json_extract(client.value, '$.PublicIp') AS public_ip,
       json_extract(client.value, '$.PrivateIp') AS private_ip,
       json_extract(client.value, '$.Owner') AS owner,
       json_extract(client.value, '$.AerospikeVersion') AS aerospike_version,
       json_extract(client.value, '$.InstanceRunningCost') AS instance_running_cost,
       json_extract(client.value, '$.Firewalls') AS firewalls,
       json_extract(client.value, '$.Arch') AS arch,
       json_extract(client.value, '$.Distribution') AS distribution,
       json_extract(client.value, '$.OSVersion') AS os_version,
       json_extract(client.value, '$.Zone') AS zone,
       json_extract(client.value, '$.ImageId') AS image_id,
       json_extract(client.value, '$.InstanceType') AS instance_type,
       json_extract(client.value, '$.DockerExposePorts') AS docker_expose_ports,
       json_extract(client.value, '$.DockerInternalPort') AS docker_internal_port,
       json_extract(client.value, '$.AwsIsSpot') AS aws_is_spot,
       json_extract(client.value, '$.GcpIsSpot') AS gcp_is_spot,
       json_extract(client.value, '$.AccessUrl') AS access_url,
       json_extract(client.value, '$.IsRunning') AS is_running,
       CASE
           WHEN inventory.cloud = 'aws' THEN 'aerolab-' || json_extract(client.value, '$.ClientName') || '_' || json_extract(client.value, '$.Zone')
           WHEN inventory.cloud = 'gcp' THEN 'aerolab-gcp-' || json_extract(client.value, '$.ClientName')
       END AS ssh_key,
       CASE
           WHEN inventory.cloud = 'aws' THEN json_extract(client.value, '$.AwsTags.project')
           WHEN inventory.cloud = 'gcp' THEN json_extract(client.value, '$.GcpLabels.project')
       END AS project,
       CASE
           WHEN inventory.cloud = 'aws' THEN json_extract(client.value, '$.AwsTags')
           WHEN inventory.cloud = 'gcp' THEN json_extract(client.value, '$.GcpLabels')
       END AS tags
FROM aerolab_inventory inventory,
     json_each(json_extract(inventory, '$.Clients')) AS client;

CREATE VIEW IF NOT EXISTS aerolab_instance AS
SELECT
    instance_id,
    cluster_name,
    CASE
        WHEN json_extract(tags, '$.customcluster') == 'true' THEN 'custom'
        ELSE cluster_type
    END AS cluster_type,
    node_name,
    node_no,
    cloud,
    state,
    expires,
    public_ip,
    private_ip,
    owner,
    REPLACE(aerospike_version, '-', '.') AS aerospike_version,
    instance_running_cost,
    firewalls,
    arch,
    distribution,
    os_version,
    zone,
    image_id,
    CASE
        WHEN cloud = 'gcp' THEN substr(instance_type, instr(instance_type, 'machineTypes/') + length('machineTypes/'))
        ELSE instance_type
    END AS instance_type,
    docker_expose_ports,
    docker_internal_port,
    aws_is_spot,
    gcp_is_spot,
    access_url,
    is_running,
    ssh_key,
    project,
    tags
FROM aerolab_instance_impl;

CREATE VIEW IF NOT EXISTS aerolab_cluster_instance AS
SELECT json_extract(cluster.value, '$.InstanceId')      AS instance_id,
       json_extract(cluster.value, '$.Features')        AS features,
       json_extract(cluster.value, '$.AGILabel')        AS agi_label,
       json_extract(cluster.value, '$.AccessProtocol')  AS access_protocol
FROM aerolab_inventory inventory,
     json_each(json_extract(inventory, '$.Clusters')) AS cluster;

CREATE VIEW IF NOT EXISTS aerolab_client_instance AS
SELECT json_extract(client.value, '$.InstanceId')    AS instance_id,
       json_extract(client.value, '$.AccessPort')       AS access_port
FROM aerolab_inventory inventory,
     json_each(json_extract(inventory, '$.Clients')) AS client;

CREATE VIEW IF NOT EXISTS aerolab_cluster AS
SELECT cluster_name,
       cluster_type,
       project,
       instance_type,
       zone,
       count(*)     AS node_count
  FROM aerolab_instance
  GROUP BY cluster_name, cluster_type, project, instance_type;

CREATE VIEW IF NOT EXISTS aerolab_aerospike_cluster AS
SELECT cluster_name,
       cluster_type,
       project,
       aerospike_version
FROM aerolab_instance
WHERE cluster_type = 'aerospike'
GROUP BY cluster_name, cluster_type, aerospike_version;

CREATE VIEW IF NOT EXISTS aerolab_custom_cluster AS
SELECT cluster_name,
       cluster_type,
       project,
       json_extract(tags, '$.aerolab4client_type') as custom_type
FROM aerolab_instance
WHERE cluster_type = 'custom'
GROUP BY cluster_name, cluster_type, aerospike_version;

CREATE VIEW IF NOT EXISTS aerolab_template AS
SELECT json_extract(template.value, '$.AerospikeVersion') AS aerospike_version,
       json_extract(template.value, '$.Distribution')     AS distribution,
       json_extract(template.value, '$.OSVersion')        AS os_version,
       json_extract(template.value, '$.Arch')             AS arch,
       json_extract(template.value, '$.Region')           AS region
FROM aerolab_inventory,
     json_each(json_extract(inventory, '$.Templates')) AS template;

CREATE VIEW aerolab_gcp_disk AS
SELECT instance_id,
       CAST(substr(key, length(rtrim(key, '0123456789')) + 1) AS INTEGER)                    AS disk_index,
       cluster_name,
       node_name,
       GROUP_CONCAT(rtrim(substr(key, 10), '0123456789') || '=' || value, ',') AS disk_spec
FROM aerolab_instance, json_each(tags)
WHERE
        key LIKE 'gcp_disk%'
        GROUP BY
        instance_id,
        disk_index
        ORDER BY instance_id, disk_index;


CREATE VIEW IF NOT EXISTS aerolab_aws_firewall_rule AS
SELECT json_extract(firewall.value, '$.AWS.SecurityGroupName') AS security_group_name,
       json_extract(firewall.value, '$.AWS.SecurityGroupID')   AS security_group_id,
       json_extract(firewall.value, '$.AWS.VPC')               AS vpc_id,
       json_extract(firewall.value, '$.AWS.Region')            AS region,
       json_extract(firewall.value, '$.AWS.IPs')               AS ips
FROM aerolab_inventory,
     json_each(json_extract(inventory, '$.FirewallRules')) AS firewall;


CREATE VIEW IF NOT EXISTS aerolab_aws_subnet AS
SELECT json_extract(subnet.value, '$.AWS.SubnetId')         AS subnet_id,
       json_extract(subnet.value, '$.AWS.SubnetName')       AS subnet_name,
       json_extract(subnet.value, '$.AWS.SubnetCidr')       AS subnet_cidr,
       json_extract(subnet.value, '$.AWS.VpcId')            AS vpc_id,
       json_extract(subnet.value, '$.AWS.VpcName')          AS vpc_name,
       json_extract(subnet.value, '$.AWS.VpcCidr')          AS vpc_cidr,
       json_extract(subnet.value, '$.AWS.AvailabilityZone') AS availability_zone,
       json_extract(subnet.value, '$.AWS.IsAzDefault')      AS is_az_default,
       json_extract(subnet.value, '$.AWS.AutoPublicIP')     AS auto_public_ip
FROM aerolab_inventory,
     json_each(json_extract(inventory, '$.Subnets')) AS subnet;

CREATE VIEW IF NOT EXISTS aerolab_expiry_system AS
SELECT json_extract(expiry_system.value, '$.Schedule')     AS schedule,
       json_extract(expiry_system.value, '$.IAMScheduler') AS iam_scheduler,
       json_extract(expiry_system.value, '$.IAMFunction')  AS iam_function,
       json_extract(expiry_system.value, '$.Scheduler')    AS scheduler,
       json_extract(expiry_system.value, '$.Function')     AS function,
       json_extract(expiry_system.value, '$.SourceBucket') AS source_bucket
FROM aerolab_inventory,
     json_each(json_extract(inventory, '$.ExpirySystem')) AS expiry_system;


CREATE VIEW IF NOT EXISTS aerolab_instance_firewall_association AS
SELECT c.instance_id,
       json_each.value AS security_group_name
FROM aerolab_instance c, json_each(c.firewalls)
WHERE c.firewalls IS NOT NULL;

CREATE VIEW IF NOT EXISTS aerolab_instance_vpc_association AS
SELECT c.instance_id,
       r.vpc_id
FROM aerolab_instance c,
     json_each(c.firewalls)
JOIN aerolab_aws_firewall_rule r on json_each.value = r.security_group_name
WHERE c.firewalls IS NOT NULL
GROUP BY c.instance_id, r.vpc_id;

CREATE TABLE IF NOT EXISTS o_aerolab_instance_type AS
SELECT
    stdout_output AS stdout,
    (
        SELECT CASE
                   WHEN EXISTS (
                       SELECT 1
                       FROM exec_command
                       WHERE stdout_output like '%Config.Backend.Type = gcp%'
                         AND command = 'aerolab config backend'
                   ) THEN 'gcp'
                   WHEN EXISTS (
                       SELECT 1
                       FROM exec_command
                       WHERE stdout_output like '%Config.Backend.Type = aws%'
                         AND command = 'aerolab config backend'
                   ) THEN 'aws'
                   ELSE 'Unknown'
                   END
    ) AS cloud
FROM
    exec_command
WHERE
    command = 'aerolab inventory instance-types --json';

CREATE VIEW aerolab_instance_type AS
SELECT
    json_extract(instance.value, '$.InstanceName') AS instance_name,
    json_extract(instance.value, '$.CPUs') AS cpus,
    json_extract(instance.value, '$.RamGB') AS ram_gb,
    json_extract(instance.value, '$.EphemeralDisks') AS ephemeral_disks,
    json_extract(instance.value, '$.EphemeralDiskTotalSizeGB') AS ephemeral_disk_total_size_gb,
    json_extract(instance.value, '$.PriceUSD') AS price_usd,
    json_extract(instance.value, '$.SpotPriceUSD') AS spot_price_usd,
    json_extract(instance.value, '$.IsArm') AS is_arm,
    json_extract(instance.value, '$.IsX86') AS is_x86,
    cloud
FROM
    o_aerolab_instance_type o_instance_type,
    json_each(stdout) AS instance;

