require 'erb'
require 'json'
require 'openssl'
require 'net/ssh'

namespace :keys do
  desc 'create keys'
  task :create do
    %w(chef-server delivery compliance).each do |hostname|
      gen_x509_cert(hostname)
    end
    gen_ssh_key
  end
end

namespace :vendor do
  desc 'Vendor build-node cookbooks'
  task :build_node do
    sh 'rm -rf packer/vendored-cookbooks/build-node'
    sh 'berks vendor -b packer/cookbooks/build-node/Berksfile packer/vendored-cookbooks/build-node'
  end

  desc 'Vendor workstation cookbooks'
  task :workstation do
    sh 'rm -rf packer/vendored-cookbooks/workstation'
    sh 'berks vendor -b packer/cookbooks/workstation/Berksfile packer/vendored-cookbooks/workstation'
  end
end

desc 'Vendor all cookbooks'
task vendor: ['vendor:build_node', 'vendor:workstation']

namespace :aws do
  desc 'Pack an AMI'
  task :pack_ami, :template do |t, args|
    Rake::Task['vendor:build_node'].invoke()
    Rake::Task['vendor:workstation'].invoke()
    sh packer_build(args[:template], 'amazon-ebs')
  end

  desc 'Pack AMIs'
  task :pack_amis do
    %w(chef-server delivery build-node workstation).each do |template|
      Rake::Task['aws:pack_ami'].invoke("#{template}.json")
      Rake::Task['aws:pack_ami'].reenable
    end
  end

  desc 'Update AMIS in wombat.json'
  task :update_amis, :chef_server_ami, :delivery_ami, :build_node_ami, :workstation_ami do |t, args|
    copy = {}
    copy = wombat
    copy['aws']['amis'][ENV['AWS_REGION']]['chef-server'] = args[:chef_server_ami] || File.read('./packer/logs/ami-chef-server.log').split("\n").last.split(" ")[1]
    copy['aws']['amis'][ENV['AWS_REGION']]['delivery'] = args[:delivery_ami] || File.read('./packer/logs/ami-delivery.log').split("\n").last.split(" ")[1]
    copy['aws']['amis'][ENV['AWS_REGION']]['build-node']['1'] = args[:build_node_ami] || File.read('./packer/logs/ami-build-node.log').split("\n").last.split(" ")[1]
    copy['aws']['amis'][ENV['AWS_REGION']]['workstation'] = args[:workstation_ami] || File.read('./packer/logs/ami-workstation.log').split("\n").last.split(" ")[1]
    copy['last_updated'] = Time.now.gmtime.strftime("%Y%m%d%H%M%S")
    # fail "packer build logs not found, nor were image ids provided" unless chef_server && delivery && builder && workstation
    puts "Updating wombat.json based on most recent packer logs"
    File.open("wombat.json","w") do |f|
      f.write(JSON.pretty_generate(copy))
    end
  end

  desc 'Generate Cloud Formation Template'
  task :create_cfn_template do
    puts "Generate CloudFormation template"
    @chef_server_ami = wombat['aws']['amis'][ENV['AWS_REGION']]['chef-server']
    @delivery_ami = wombat['aws']['amis'][ENV['AWS_REGION']]['delivery']
    @build_nodes = wombat['build-nodes'].to_i
    @build_node_ami = {}
    1.upto(@build_nodes) do |i|
      @build_node_ami[i] = wombat['aws']['amis'][ENV['AWS_REGION']]["build-node"][i.to_s]
    end
    @workstation_ami = wombat['aws']['amis'][ENV['AWS_REGION']]['workstation']
    @availability_zone = wombat['aws']['availability_zone']
    @demo = wombat['demo']
    @version = wombat['version']
    rendered_cfn = ERB.new(File.read('cloudformation/cfn.json.erb'),nil,'-').result
    File.open("cloudformation/#{@demo}.json", "w") {|file| file.puts rendered_cfn }
    puts "Created cloudformation/#{@demo}.json"
  end

  desc 'Create a Stack from a CloudFormation template'
  task :create_cfn_stack, :stack, :region, :keypair do |t, args|
    stack = args[:stack] || wombat['demo']
    region = args[:region] || wombat['aws']['region']
    keypair = args[:keypair] || wombat['aws']['keypair']
    sh create_stack(stack, region, keypair)
  end

  desc 'Build a CloudFormation stack'
  task build_cfn_stack: ['vendor', 'aws:pack_amis', 'aws:update_amis', 'aws:create_cfn_template']
end

namespace :tf do
  desc 'Update AMIS in tfvars'
  task :update_amis, :chef_server_ami, :delivery_ami, :build_node_ami, :workstation_ami do |t, args|
    chef_server = args[:chef_server_ami] || File.read('./packer/logs/ami-chef-server.log').split("\n").last.split(" ")[1]
    delivery = args[:delivery_ami] || File.read('./packer/logs/ami-delivery.log').split("\n").last.split(" ")[1]
    builder = args[:build_node_ami] || File.read('./packer/logs/ami-build-node.log').split("\n").last.split(" ")[1]
    workstation = args[:workstation_ami] || File.read('./packer/logs/ami-workstation.log').split("\n").last.split(" ")[1]
    fail "packer build logs not found, nor were image ids provided" unless chef_server && delivery && builder && workstation
    puts "Updating tfvars based on most recent packer logs"
    @chef_server_ami = chef_server
    @delivery_ami = delivery
    @build_node_ami = builder
    @workstation_ami = workstation
    rendered_tfvars = ERB.new(File.read('terraform/templates/terraform.tfvars.erb')).result
    File.open('terraform/terraform.tfvars', "w") {|file| file.puts rendered_tfvars }
    puts "\n" + rendered_tfvars
  end

  desc 'Terraform plan'
  task :plan do
    sh 'cd terraform && terraform plan'
  end

  desc 'Terraform apply'
  task :apply do
    sh 'cd terraform && terraform apply'
  end

  desc 'Terraform destroy'
  task :destroy do
    sh 'cd terraform && terraform destroy -force'
  end
end

def packer_build(template, builder)
  base = template.split('.json')[0]
  cmd = %W(packer build packer/#{template} | tee packer/logs/ami-#{base}.log)
  cmd.insert(2, "--only #{builder}")
  cmd.insert(2, "--var org='#{wombat['org']}'") if !(base =~ /delivery/)
  cmd.insert(2, "--var domain='#{wombat['domain']}'")
  cmd.insert(2, "--var enterprise='#{wombat['enterprise']}'") if !(base =~ /chef-server/)
  cmd.insert(2, "--var chefdk='#{version('chefdk')}'") if !(base =~ /chef-server/)
  cmd.insert(2, "--var delivery='#{version('delivery')}'") if (base =~ /delivery/)
  cmd.insert(2, "--var chef-server='#{version('chef-server')}'") if (base =~ /chef-server/)
  cmd.insert(2, "--var build-nodes='#{wombat['build-nodes']}'") if (base =~ /build-nodes/)
  cmd.join(' ')
end

def create_stack(stack, region, keypair)
  template_file = "file://#{File.dirname(__FILE__)}/cloudformation/#{stack}.json"
  timestamp = Time.now.gmtime.strftime("%Y%m%d%H%M%S")
  cmd = %W(aws cloudformation create-stack)
  cmd.insert(3, "--template-body #{template_file}")
  cmd.insert(3, "--parameters ParameterKey='KeyName',ParameterValue='#{keypair}'")
  cmd.insert(3, "--region #{region}")
  cmd.insert(3, "--stack-name #{stack}-#{timestamp}")
  cmd.join(' ')
end

def wombat
  file = File.read('wombat.json')
  hash = JSON.parse(file)
end

def version(thing)
  wombat['pkg-versions'][thing]
end

def gen_x509_cert(hostname)
  rsa_key = OpenSSL::PKey::RSA.new(2048)
  public_key = rsa_key.public_key

  subject = "/C=AU/ST=New South Wales/L=Sydney/O=#{wombat['org']}/OU=wombats/CN=#{hostname}.#{wombat['domain']}"

  cert = OpenSSL::X509::Certificate.new
  cert.subject = cert.issuer = OpenSSL::X509::Name.parse(subject)
  cert.not_before = Time.now
  cert.not_after = Time.now + 365 * 24 * 60 * 60
  cert.public_key = public_key
  cert.serial = 0x0
  cert.version = 2

  ef = OpenSSL::X509::ExtensionFactory.new
  ef.subject_certificate = cert
  ef.issuer_certificate = cert
  cert.extensions = [
    ef.create_extension("basicConstraints","CA:TRUE", true),
    ef.create_extension("subjectKeyIdentifier", "hash"),
    # ef.create_extension("keyUsage", "cRLSign,keyCertSign", true),
  ]
  cert.add_extension ef.create_extension("authorityKeyIdentifier",
                                        "keyid:always,issuer:always")

  cert.sign(rsa_key, OpenSSL::Digest::SHA256.new)

  File.open("packer/keys/#{hostname}.crt", "w") {|file| file.puts cert.to_pem }
  File.open("packer/keys/#{hostname}.key", "w") {|file| file.puts rsa_key.to_pem }
  puts "Certificate created for #{hostname}.#{wombat['domain']}"
end

def gen_ssh_key
  rsa_key = OpenSSL::PKey::RSA.new 2048

  type = rsa_key.ssh_type
  data = [ rsa_key.to_blob ].pack('m0')

  openssh_format = "#{type} #{data}"
  File.open('packer/keys/public.pub', "w") {|file| file.puts openssh_format }
  File.open('packer/keys/private.pem', "w") {|file| file.puts rsa_key.to_pem }
  puts 'SSH Keypair created'
end