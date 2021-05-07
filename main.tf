provider "alicloud" {
}
variable "k8s_name_prefix" {
  description = "The name prefix used to create managed kubernetes cluster."
  default     = "hbb"
}
resource "random_uuid" "this" {}
# 默认资源名称
locals {
  k8s_name         = substr(join("-", [var.k8s_name_prefix, random_uuid.this.result]), 0, 63)
  cluster_domain   = join(".",[var.k8s_name_prefix,"local"])
  new_vpc_name     = "vpc-${local.k8s_name}"
  new_vsw_name     = "vsw-${local.k8s_name}"
  log_project_name = "log-for-${local.k8s_name}"
}
# 节点ECS实例配置
data "alicloud_instance_types" "default" {
  cpu_core_count       = 4
  memory_size          = 8
  kubernetes_node_role = "Worker"
}
// 满足实例规格的AZ
data "alicloud_zones" "default" {
  available_instance_type = data.alicloud_instance_types.default.instance_types[0].id
}
# 专有网络
resource "alicloud_vpc" "default" {
  name       = local.new_vpc_name
  cidr_block = "172.19.0.0/16"
}
# 交换机
resource "alicloud_vswitch" "vswitches" {
  name              = local.new_vsw_name
  vpc_id            = alicloud_vpc.default.id
  cidr_block        = "172.19.240.0/20"
  availability_zone = data.alicloud_zones.default.zones[0].id
}
# 日志服务
resource "alicloud_log_project" "log" {
  name        = local.log_project_name
  description = "created by terraform for managedkubernetes cluster"
}
# 附加配置
variable "cluster_addons" {
  type = list(object({
    name      = string
    config    = string
  }))
  default = [
    {
      "name"     = "logtail-ds",
      "config"   = "{\"IngressDashboardEnabled\":\"true\",\"sls_project_name\":alicloud_log_project.log.name}",
    },
    {
      "name"     = "nginx-ingress-controller",
      "config"   = "{\"IngressSlbNetworkType\":\"internet\"}",
    },
    {
      "name"     = "flannel",
      "config"   = "",
    }
  ]
}
# kubernetes托管版
resource "alicloud_cs_managed_kubernetes" "default" {
  # kubernetes集群名称
  name                      = local.k8s_name
  cluster_domain            = local.cluster_domain
  # 新的kubernetes集群将位于的vswitch。指定一个或多个vswitch的ID。它必须在availability_zone指定的区域中
  worker_vswitch_ids        = split(",", join(",", alicloud_vswitch.vswitches.*.id))
  # 节点的ECS实例类型。
  worker_instance_types     = [data.alicloud_instance_types.default.instance_types[0].id]
  #缺省操作系统
  platform                  = "Centos"
  # kubernetes群集的总工作节点数。默认值为3。最大限制为50。
  worker_number             = 2
  # ssh登录群集节点的密码。
  enable_ssh                = true
  password                  = "Yourpassword1234"
  # 网络模式
  proxy_mode                = "ipvs"
  # pod网络的CIDR块。当cluster_network_type设置为flannel，你必须设定该参数。它不能与VPC CIDR相同，并且不能与VPC中的Kubernetes群集使用的CIDR相同，也不能在创建后进行修改。群集中允许的最大主机数量：256。
  pod_cidr                  = "10.240.0.0/20"
  # 服务网络的CIDR块。它不能与VPC CIDR相同，不能与VPC中的Kubernetes群集使用的CIDR相同，也不能在创建后进行修改。
  service_cidr              = "192.168.240.0/20"
  # 是否为kubernetes的节点安装云监控。
  install_cloud_monitor     = true
  # 是否在创建kubernetes集群时创建新的nat网关。默认为true。
  new_nat_gateway           = true
  # 是否为API Server创建Internet负载均衡。默认为false。
  slb_internet_enabled      = true
  # 节点的系统磁盘类别。其有效值为cloud_ssd和cloud_efficiency。默认为cloud_efficiency。
  worker_disk_category      = "cloud_efficiency"
  # 节点的数据磁盘类别。其有效值为cloud_ssd和cloud_efficiency，如果未设置，将不会创建数据磁盘。
  worker_data_disk_category = "cloud_ssd"
  # 节点的数据磁盘大小。有效值范围[20〜32768]，以GB为单位。当worker_data_disk_category被呈现，则默认为40。
  worker_data_disk_size     = 40
  # 附加配置
  dynamic "addons" {
      for_each = var.cluster_addons
      content {
        name          = lookup(addons.value, "name", var.cluster_addons)
        config        = lookup(addons.value, "config", var.cluster_addons)
        disabled      = lookup(addons.value, "disabled", var.cluster_addons)
      }
  }
}
