include_recipe 'chocolatey'

node['demo']['pkgs'].each do |pkg|
  chocolatey pkg
end

include_recipe 'workstation::certs-keys'
include_recipe 'workstation::terminal'
include_recipe 'workstation::browser'
include_recipe 'workstation::editor'
include_recipe 'workstation::chef'
include_recipe 'workstation::profile'
include_recipe 'wombat::etc-hosts'
