require 'redis'
require 'yaml'

# ansible_deploy.rb must be deployed to `ansible-repo` root directory, like:
# ansible-repo/
#   roles/
#   host_vars/
#   group_vars/
#   ansible_deploy.rb
class AnsibleDeploy
  def initialize(source, destination)
    @source = source
    @destination = destination
    @run_list = {}
    @current_roles = {}
    @redis = Redis.new
  end

  def run_list
    Dir['roles/*/version'].each do |file|
      name = role_name(file)
      version = role_version(file)
      @current_roles[name] = get_role_version(name)
      update_role_version(name, version)
    end
    render_playbook
  end

  private

  def role_name(file)
    file.match(%r{roles\/(.*)\/version})[1]
  end

  def role_version(file)
    File.read(file).chop
  end

  def get_role_version(role)
    @redis.hmget("ansible:#{@source}:role:#{role}", 'version').first
  end

  def update_role_version(role, version)
    @redis.hmset("ansible:#{@source}:role:#{role}", 'version', version)
    @run_list[role] = version
  end

  def diff
    @run_list.map do |role, version|
      next if @current_roles[role] == version
      role
    end.compact
  end

  def roles_from_yaml
    YAML.load_file(@source).last['roles']
  end

  def deploy_info_from_yaml
    YAML.load_file(@source).map do |playbook|
      playbook.delete('roles')
      playbook
    end
  end

  def render_playbook
    playbooks = deploy_info_from_yaml.map do |deploy|
      if mapping.any?
        deploy.merge('roles' => mapping)
      else
        deploy
      end
    end
    File.write(@destination, playbooks.to_yaml)
  end

  def mapping
    roles_from_yaml.map do |role|
      if role.is_a? String
        role if diff.include?(role)
      else
        role if diff.include?(role['role'])
      end
    end.compact
  end
end

source = ARGV[0]
destination = ARGV[1]

AnsibleDeploy.new(source, destination).run_list
