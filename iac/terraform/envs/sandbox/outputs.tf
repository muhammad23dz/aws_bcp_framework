output "tagging_baseline" {
  description = "Tagging baseline outputs"
  value = {
    high_criticality_group_arn = module.tagging_baseline.high_criticality_group_arn
    warm_standby_group_arn     = module.tagging_baseline.warm_standby_group_arn
  }
}

output "s3_crr" {
  description = "S3 cross-region replication outputs"
  value = {
    primary_bucket_name  = module.s3_crr.primary_bucket_name
    primary_bucket_arn   = module.s3_crr.primary_bucket_arn
    replica_bucket_name  = module.s3_crr.replica_bucket_name
    replica_bucket_arn   = module.s3_crr.replica_bucket_arn
    replication_role_arn = module.s3_crr.replication_role_arn
  }
}

output "drs_network" {
  description = "DRS network outputs"
  value = {
    dr_vpc_id            = module.drs_network.dr_vpc_id
    dr_subnet_id         = module.drs_network.dr_subnet_id
    dr_security_group_id = module.drs_network.dr_security_group_id
    dr_kms_key_arn       = module.drs_network.dr_kms_key_arn
    drs_source_server_id = module.drs_network.drs_source_server_id
  }
}

output "warm_standby" {
  description = "Warm standby ASG outputs"
  value = {
    dr_vpc_id          = module.warm_standby.dr_vpc_id
    dr_subnet_ids      = module.warm_standby.dr_subnet_ids
    asg_name           = module.warm_standby.asg_name
    launch_template_id = module.warm_standby.launch_template_id
    security_group_id  = module.warm_standby.security_group_id
    sns_topic_arn      = module.warm_standby.sns_topic_arn
  }
}
