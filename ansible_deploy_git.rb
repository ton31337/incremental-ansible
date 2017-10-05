require 'yaml'
require 'git'

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
    @roles_changed = roles_changed
  end

  def run!
    render_playbook
  end

  private

  def roles_changed
    g = Git.open('.')
    commits = g.log(2)
    g.diff(commits.first.sha, commits.last.sha).stats[:files].map do |file, _|
      parsed = file.match(%r{roles\/([\d\w\-\_]+)\/})
      parsed[1] if parsed
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
        deploy.merge('roles' => roles_from_yaml)
      end
    end
    File.write(@destination, playbooks.to_yaml)
  end

  def mapping
    roles_from_yaml.map do |role|
      if role.is_a? String
        role if @roles_changed.include?(role)
      else
        role if @roles_changed.include?(role['role'])
      end
    end.compact
  end
end

source = ARGV[0]
destination = ARGV[1]

AnsibleDeploy.new(source, destination).run!
