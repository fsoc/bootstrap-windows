#!/usr/bin/env/ruby
#
require 'socket'
require 'optparse'

# Options
options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: example.rb [options]"

  opts.on('-n', '--name NAME', 'node name') { |v| options[:name] = v }
  opts.on('-v', '--version VERSION', 'windows version') { |v| options[:version] = v }

end.parse!

ami_id = ENV["AWS_AMI"] || 'ami-ecb4449b'

ver_to_role = {'ie8' => 'teamcity_agent_windows_ie8',
  'ie9' => 'teamcity_agent_windows_ie9'}


if ver_to_role.has_key?options[:version]
  role = ver_to_role[options[:version]]
  puts "using role: #{role}"
else
  puts "the ie version #{options[:version]} has no role set."
  exit 1
end

# AWS API Credentials
# Save these in your shell as per instructions at
# http://docs.aws.amazon.com/AWSEC2/latest/CommandLineReference/set-up-ec2-cli-linux.html
AWS_ACCESS_KEY = ENV["AWS_ACCESS_KEY"]
AWS_SECRET_KEY = ENV["AWS_SECRET_KEY"]

# Node details
NODE_NAME         = options[:name]
CHEF_ENVIRONMENT  = "ci"
INSTANCE_SIZE     = "m1.medium"
EBS_ROOT_VOL_SIZE = 70   # in GB
AVAILABILITY_ZONE = "eu-west-1a"
AMI_NAME          = ami_id
SECURITY_GROUP    = ENV["AWS_SG"]
RUN_LIST          = "role['#{role}']"
USER_DATA_FILE    = "/tmp/userdata.txt"
USERNAME          = "Administrator"
PASSWORD          = ENV["AWS_WIN_PWD"]
SUBNET            = ENV["AWS_SUBNET"]

# Write user data file that sets up WinRM and sets the Administrator password.
File.open(USER_DATA_FILE, "w") do |f|
  f.write <<EOT
<script>
winrm quickconfig -q & winrm set winrm/config/winrs @{MaxMemoryPerShellMB="3000"} & winrm set winrm/config @{MaxTimeoutms="9900000"} & winrm set winrm/config/service @{AllowUnencrypted="true"} & winrm set winrm/config/service/auth @{Basic="true"}
</script>
<powershell>
$admin = [adsi]("WinNT://./administrator, user")
$admin.psbase.invoke("SetPassword", "#{PASSWORD}")
</powershell>
EOT
end

# Define the command to provision the instance
provision_cmd = [
  "knife ec2 server create",
  "--identity-file ~/.ssh/keys/ocean.pem",
  "--ssh-key ocean",
  "--aws-access-key-id #{AWS_ACCESS_KEY}",
  "--aws-secret-access-key #{AWS_SECRET_KEY}",
  "--tags 'Name=#{NODE_NAME},ChefEnv=ci'",
  "-E '#{CHEF_ENVIRONMENT}'",
  "--flavor #{INSTANCE_SIZE}",
  "--ebs-size #{EBS_ROOT_VOL_SIZE}",
  "--availability-zone #{AVAILABILITY_ZONE}",
  "--image #{AMI_NAME}",
  "--security-group-ids '#{SECURITY_GROUP}'",
  "--user-data #{USER_DATA_FILE}",
  "--subnet #{SUBNET}",
  "--verbose"
].join(" ")

# Run `knife ec2 server create` to provision the new instance and
# read the output until we know it's public IP address. At that point,
# knife is going to wait until the instance responds on the SSH port. Of
# course, being Windows, this will never happen, so we need to go ahead and
# kill knife and then proceed with the rest of this script to wait until
# WinRM is up and we can bootstrap the node with Chef over WinRM.
ip_addr = nil
IO.popen(provision_cmd) do |pipe|
  begin
    while line = pipe.readline
      puts line
      if line =~ /^Private IP Address: (.*)$/
        ip_addr = $1.strip
        Process.kill("TERM", pipe.pid)
        break
      end
    end
  rescue EOFError
    # done
  end
end
if ip_addr.nil?
  puts "ERROR: Unable to get new instance's IP address"
  exit -1
end

# Now the new instance is provisioned, but we have no idea when it will
# be ready to go. The first thing we'll do is wait until the WinRM port
# responds to connections.
puts "Waiting for WinRM..."
start_time = Time.now
begin
  s = TCPSocket.new ip_addr, 5985
rescue 
  puts "Still waiting..."
  retry
end
s.close

# You'd think we'd be good to go now...but NOPE! There is still more Windows
# bootstrap crap going on, and we have no idea what we need to wait on. So,
# in a last-ditch effort to make this all work, we've seen that a few minutes
# ought to be enough...
wait_time = 120 
while wait_time > 0
  puts "Better wait #{wait_time} more seconds..."
  sleep 1
  wait_time -= 1
end
puts "Finally ready to try bootstrapping instance..."

bootstrap_cmd = [
  "knife bootstrap windows winrm #{ip_addr}",
  "-x #{USERNAME}",
  "-P '#{PASSWORD}'",
  "--environment #{CHEF_ENVIRONMENT}",
  "--node-name #{NODE_NAME}",
  "--run-list '#{RUN_LIST}'",
  "--verbose"
].join(' ')

puts "executing #{bootstrap_cmd}"
# Now we can bootstrap the instance with Chef and the configured run list.
status = system(bootstrap_cmd) ? 0 : -1
exit status
