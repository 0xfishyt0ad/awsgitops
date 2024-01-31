[OUTPUT]
    Name cloudwatch_logs
    Match *
    region ${region}
    log_group_name /aws/eks/${cluster_name}
    log_stream_prefix app-
    auto_create_group true