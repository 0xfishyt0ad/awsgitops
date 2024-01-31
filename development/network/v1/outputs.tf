output "workspaces_network" {
  value = {
    for workspace, cidr_block in local.cidr_blocks: workspace =>
      {
        vpc_id             = aws_vpc.this.id
        availability_zones = {for az in local.availability_zones: az => "${data.aws_region.this.name}${az}"}
        cidr_block         = cidr_block
        igw_route_table    = aws_route_table.public.id
        nat_route_tables   = {for az in local.availability_zones: az => module.nat[az].route_table_id}
      }
 }

  description = "Object containing all network information for each workspace"
}